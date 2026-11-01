// Testes do cadastro e da verificação — seção 5 do guia.
import { test, before, after, describe } from 'node:test';
import assert from 'node:assert/strict';
import pg from 'pg';
import { subirBanco } from './db.mjs';

let banco, admin, tenantId;
const clientes = [];

before(async () => {
  banco = await subirBanco();
  admin = banco.admin;
  tenantId = (await admin.query(`insert into tenants (nome, subdominio) values ('Piloto', 'piloto') returning id`)).rows[0].id;
});
after(async () => {
  for (const c of clientes) await c.end();
  await banco?.parar();
});

async function pessoa(telefone) {
  const auth = (await admin.query(`insert into auth.users (phone) values ($1) returning id`, [telefone])).rows[0].id;
  const c = new pg.Client({ connectionString: banco.url });
  await c.connect();
  await c.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ sub: auth, role: 'authenticated' })]);
  await c.query('set role authenticated');
  clientes.push(c);
  const rpc = async (fn, ...args) => {
    const ps = args.map((_, i) => `$${i + 1}`).join(', ');
    return (await c.query(`select public.${fn}(${ps}) as r`, args)).rows[0].r;
  };
  return { auth, c, rpc };
}

const DADOS = {
  nome: 'João da Silva', cpf_cnpj: '529.982.247-25', cidade: 'Mococa', uf: 'sp', email: 'joao@exemplo.com',
  inscricao_estadual: '123456', referencia_bancaria: 'Banco do Brasil, ag. 1234, cliente desde 2010',
  aceite_termos: true, aceite_regras: true, aceite_privacidade: true, optin_whatsapp: true,
};

async function enviarDocumentos(p, usuarioId, tipos = ['documento_foto', 'comprovante_endereco']) {
  for (const tipo of tipos) {
    await p.c.query(`insert into documentos (tenant_id, dono_id, tipo, arquivo_url) values ($1, $2, $3, $4)`,
      [tenantId, usuarioId, tipo, `${tenantId}/${usuarioId}/${tipo}.jpg`]);
  }
}

describe('Validação de CPF/CNPJ', () => {
  test('aceita válidos e recusa inválidos', async () => {
    const casos = {
      '529.982.247-25': true, '11144477735': true, '11.222.333/0001-81': true,
      '529.982.247-24': false, '111.111.111-11': false, '11222333000182': false, '123': false,
    };
    for (const [doc, esperado] of Object.entries(casos)) {
      const r = (await admin.query(`select app.cpf_cnpj_valido($1) as v`, [doc])).rows[0].v;
      assert.equal(r, esperado, doc);
    }
  });
});

describe('Seção 5.1 — fluxo de cadastro', () => {
  test('login cria cadastro pendente com o celular do login e papel de comprador', async () => {
    const p = await pessoa('5519991110001');
    const r = await p.rpc('iniciar_cadastro', tenantId);
    assert.equal(r.ok, true);
    assert.equal(r.status, 'pendente');
    assert.equal(r.cadastro_completo, false);
    const u = (await admin.query(`select * from usuarios where id = $1`, [r.usuario_id])).rows[0];
    assert.equal(u.celular, '+5519991110001');
    assert.ok(u.codigo_publico >= 1000);
    const papeis = (await admin.query(`select papel from papeis_usuario where usuario_id = $1`, [u.id])).rows;
    assert.deepEqual(papeis.map((x) => x.papel), ['comprador']);
    // Repetir não duplica
    assert.equal((await p.rpc('iniciar_cadastro', tenantId)).usuario_id, r.usuario_id);
  });

  test('convite pré-cadastrado pela leiloeira é vinculado pelo celular', async () => {
    const pre = (await admin.query(
      `insert into usuarios (tenant_id, celular, nome) values ($1, '+5519991110002', 'Convidado') returning id`, [tenantId])).rows[0].id;
    const p = await pessoa('5519991110002');
    assert.equal((await p.rpc('iniciar_cadastro', tenantId)).usuario_id, pre);
  });

  test('envio exige campos válidos, documentos e aceites', async () => {
    const p = await pessoa('5519991110003');
    const { usuario_id } = await p.rpc('iniciar_cadastro', tenantId);
    const r = await p.rpc('enviar_cadastro', tenantId, { ...DADOS, cpf_cnpj: '123', aceite_regras: false, email: 'x' });
    assert.equal(r.ok, false);
    assert.deepEqual(new Set(r.campos), new Set(['cpf_cnpj', 'email', 'aceite_regras', 'documento_foto', 'comprovante_endereco']));

    await enviarDocumentos(p, usuario_id);
    const ok = await p.rpc('enviar_cadastro', tenantId, DADOS);
    assert.equal(ok.ok, true, JSON.stringify(ok));
    const u = (await admin.query(`select * from usuarios where id = $1`, [usuario_id])).rows[0];
    assert.equal(u.cpf_cnpj, '52998224725');
    assert.equal(u.uf, 'SP');
    assert.equal(u.status_verificacao, 'pendente');
    assert.ok(u.cadastro_enviado_em);
    assert.equal(u.optin_whatsapp, true);
    assert.ok(u.optin_whatsapp_em);
    const consent = (await admin.query(`select tipo, versao from consentimentos where usuario_id = $1 order by tipo`, [usuario_id])).rows;
    assert.deepEqual(consent.map((x) => x.tipo), ['optin_whatsapp', 'privacidade', 'regras_leilao', 'termos_uso']);
    assert.equal(consent[0].versao, '0.1-provisoria');
  });

  test('selfie obrigatória quando configurado', async () => {
    await admin.query(`insert into configuracoes (tenant_id, chave, valor) values ($1, 'cadastro.selfie_obrigatoria', 'true')`, [tenantId]);
    try {
      const p = await pessoa('5519991110004');
      const { usuario_id } = await p.rpc('iniciar_cadastro', tenantId);
      await enviarDocumentos(p, usuario_id);
      const r = await p.rpc('enviar_cadastro', tenantId, { ...DADOS, cpf_cnpj: '11144477735' });
      assert.deepEqual(r.campos, ['selfie']);
    } finally {
      await admin.query(`delete from configuracoes where chave = 'cadastro.selfie_obrigatoria'`);
    }
  });

  test('mesmo CPF não cria segundo cadastro na leiloeira', async () => {
    const p = await pessoa('5519991110005');
    const { usuario_id } = await p.rpc('iniciar_cadastro', tenantId);
    await enviarDocumentos(p, usuario_id);
    const r = await p.rpc('enviar_cadastro', tenantId, DADOS); // CPF do teste anterior
    assert.equal(r.codigo, 'cpf_cnpj_em_uso');
  });

  test('usuário não registra documento como aprovado nem fora da própria pasta', async () => {
    const p = await pessoa('5519991110006');
    const { usuario_id } = await p.rpc('iniciar_cadastro', tenantId);
    await assert.rejects(p.c.query(
      `insert into documentos (tenant_id, dono_id, tipo, arquivo_url, status) values ($1, $2, 'documento_foto', $3, 'aprovado')`,
      [tenantId, usuario_id, `${tenantId}/${usuario_id}/x.jpg`]), /row-level security/);
    await assert.rejects(p.c.query(
      `insert into documentos (tenant_id, dono_id, tipo, arquivo_url) values ($1, $2, 'documento_foto', 'outra/pasta/x.jpg')`,
      [tenantId, usuario_id]), /row-level security/);
    await assert.rejects(p.c.query(`update usuarios set status_verificacao = 'verificado' where id = $1`, [usuario_id]), /permission denied/);
  });
});

describe('Seção 5.1 (passo 8) — análise pelo admin', () => {
  test('aprovar, pedir ajuste, reenviar e recusar', async () => {
    const adm = await pessoa('5519990000000');
    const { usuario_id: admId } = await adm.rpc('iniciar_cadastro', tenantId);
    await admin.query(`insert into papeis_usuario (tenant_id, usuario_id, papel) values ($1, $2, 'admin')`, [tenantId, admId]);

    const p = await pessoa('5519991110007');
    const { usuario_id } = await p.rpc('iniciar_cadastro', tenantId);
    await enviarDocumentos(p, usuario_id);

    assert.equal((await adm.rpc('analisar_cadastro', usuario_id, 'aprovar', null)).codigo, 'cadastro_incompleto');
    await p.rpc('enviar_cadastro', tenantId, { ...DADOS, cpf_cnpj: '11.222.333/0001-81' });
    const fila = (await admin.query(`select tipo from notificacoes where usuario_id = $1`, [admId])).rows;
    assert.ok(fila.some((n) => n.tipo === 'cadastro_para_analise'), 'admin é avisado');

    // Comprador comum não analisa
    assert.equal((await p.rpc('analisar_cadastro', usuario_id, 'aprovar', null)).codigo, 'sem_permissao');

    assert.equal((await adm.rpc('analisar_cadastro', usuario_id, 'pedir_ajuste', '')).codigo, 'observacao_obrigatoria');
    const ajuste = await adm.rpc('analisar_cadastro', usuario_id, 'pedir_ajuste', 'Comprovante ilegível, envie outro.');
    assert.equal(ajuste.status, 'divergente');
    const visto = (await p.c.query(`select status_verificacao, observacao_analise from usuarios where id = $1`, [usuario_id])).rows[0];
    assert.equal(visto.status_verificacao, 'divergente');
    assert.equal(visto.observacao_analise, 'Comprovante ilegível, envie outro.');

    const reenvio = await p.rpc('enviar_cadastro', tenantId, { ...DADOS, cpf_cnpj: '11.222.333/0001-81' });
    assert.equal(reenvio.status, 'pendente');

    assert.equal((await adm.rpc('analisar_cadastro', usuario_id, 'aprovar', null)).status, 'verificado');
    const avisos = (await admin.query(`select tipo from notificacoes where usuario_id = $1 order by criado_em`, [usuario_id])).rows;
    assert.deepEqual(avisos.map((a) => a.tipo), ['cadastro_ajuste', 'cadastro_aprovado']);

    // Verificado não reenvia cadastro sozinho
    assert.equal((await p.rpc('enviar_cadastro', tenantId, DADOS)).codigo, 'cadastro_verificado');
  });
});
