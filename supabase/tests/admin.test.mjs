// Testes do painel da leiloeira — seção 11.2 do guia (etapa 4).
import { test, before, after, describe } from 'node:test';
import assert from 'node:assert/strict';
import pg from 'pg';
import { subirBanco } from './db.mjs';

let banco, admin, tenantId, outroTenant;
const clientes = [];
const u = {};

async function conectar(authId) {
  const c = new pg.Client({ connectionString: banco.url });
  await c.connect();
  await c.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ sub: authId, role: 'authenticated' })]);
  await c.query('set role authenticated');
  clientes.push(c);
  return c;
}

async function pessoa(nome, tenant, papeis = [], status = 'verificado') {
  const auth = (await admin.query(`insert into auth.users (phone) values ($1) returning id`, [nome])).rows[0].id;
  const id = (await admin.query(
    `insert into usuarios (tenant_id, auth_user_id, nome, celular, status_verificacao, cidade, uf) values ($1, $2, $3, $4, $5, 'Mococa', 'SP') returning id`,
    [tenant, auth, nome, '+5519' + Math.floor(1e8 + Math.random() * 8e8), status])).rows[0].id;
  for (const p of papeis) await admin.query(`insert into papeis_usuario (tenant_id, usuario_id, papel) values ($1, $2, $3)`, [tenant, id, p]);
  const c = await conectar(auth);
  const rpc = async (fn, ...args) => (await c.query(`select public.${fn}(${args.map((_, i) => `$${i + 1}`).join(', ')}) as r`, args)).rows[0].r;
  return { id, c, rpc };
}

const LOTE = {
  titulo: '30 garrotes Nelore', categoria: 'garrotes', raca: 'Nelore', sexo: 'macho', quantidade: '30',
  peso_medio: '268', data_pesagem: new Date().toISOString().slice(0, 10), idade_min: '12', idade_max: '14',
  sanidade: { vacinas: 'Em dia' }, cidade: 'Mococa', uf: 'sp', preco_inicial: '2600', preco_reserva: '',
};

before(async () => {
  banco = await subirBanco();
  admin = banco.admin;
  tenantId = (await admin.query(`insert into tenants (nome, subdominio) values ('Piloto', 'piloto') returning id`)).rows[0].id;
  outroTenant = (await admin.query(`insert into tenants (nome, subdominio) values ('Outra', 'outra') returning id`)).rows[0].id;
  await admin.query(`insert into configuracoes (tenant_id, chave, valor) values ($1, 'lance.intervalo_minimo_ms', '0')`, [tenantId]);
  u.adm = await pessoa('admin', tenantId, ['admin']);
  u.op = await pessoa('operador', tenantId, ['operador']);
  u.comp = await pessoa('comprador', tenantId, ['comprador']);
  u.estranho = await pessoa('admin-outra', outroTenant, ['admin']);
});
after(async () => {
  for (const c of clientes) await c.end();
  await banco?.parar();
});

async function midias(loteId, { video = 1, fotos = 3, laudo = 1 } = {}) {
  const ins = (tipo) => admin.query(`insert into midias_lote (tenant_id, lote_id, tipo, url) values ($1, $2, $3, 'x')`, [tenantId, loteId, tipo]);
  for (let i = 0; i < video; i++) await ins('video');
  for (let i = 0; i < fotos; i++) await ins('foto');
  for (let i = 0; i < laudo; i++) await ins('laudo');
}

describe('Vendedor e lote', () => {
  let vendedorId;

  test('equipe cadastra vendedor com fazenda; comprador e outro tenant não', async () => {
    const dados = { nome: 'José Pereira', celular: '(19) 98888-7777', cidade: 'Mococa', uf: 'SP', fazenda: 'Fazenda Boa Vista' };
    assert.equal((await u.comp.rpc('criar_vendedor', tenantId, dados)).codigo, 'sem_permissao');
    assert.equal((await u.estranho.rpc('criar_vendedor', tenantId, dados)).codigo, 'sem_permissao');
    const r = await u.op.rpc('criar_vendedor', tenantId, dados);
    assert.equal(r.ok, true);
    vendedorId = r.usuario_id;
    const f = (await admin.query(`select nome from fazendas where vendedor_id = $1`, [vendedorId])).rows;
    assert.deepEqual(f.map((x) => x.nome), ['Fazenda Boa Vista']);
    // repetir não duplica
    assert.equal((await u.op.rpc('criar_vendedor', tenantId, dados)).usuario_id, vendedorId);
  });

  test('salvar lote valida campos e ninguém altera lotes direto na tabela', async () => {
    assert.equal((await u.op.rpc('salvar_lote', tenantId, null, { ...LOTE, vendedor_id: vendedorId, categoria: 'cavalos' })).codigo, 'categoria');
    assert.equal((await u.op.rpc('salvar_lote', tenantId, null, { ...LOTE, vendedor_id: u.comp.id })).codigo, 'vendedor_id');
    assert.equal((await u.op.rpc('salvar_lote', tenantId, null, { ...LOTE, vendedor_id: vendedorId, preco_reserva: '100' })).codigo, 'preco_reserva');
    const r = await u.op.rpc('salvar_lote', tenantId, null, { ...LOTE, vendedor_id: vendedorId });
    assert.equal(r.ok, true);
    const l = (await admin.query(`select * from lotes where id = $1`, [r.lote_id])).rows[0];
    assert.equal(l.status, 'rascunho');
    assert.equal(l.uf, 'SP');
    assert.equal(Number(l.tolerancia_quebra), 3, 'tolerância padrão da configuração');
    assert.ok(l.fazenda_id);
    await assert.rejects(u.adm.c.query(`update lotes set lance_atual = 1 where id = $1`, [r.lote_id]), /permission denied/);
  });

  test('aprovar exige vídeo, 3 fotos, laudo e pesagem recente', async () => {
    const { lote_id } = await u.op.rpc('salvar_lote', tenantId, null, { ...LOTE, vendedor_id: vendedorId });
    let r = await u.op.rpc('aprovar_lote', lote_id);
    assert.deepEqual(r.pendencias, ['video', 'fotos', 'laudo']);
    await midias(lote_id, { fotos: 2 });
    r = await u.op.rpc('aprovar_lote', lote_id);
    assert.deepEqual(r.pendencias, ['fotos']);
    await midias(lote_id, { video: 0, fotos: 1, laudo: 0 });
    await admin.query(`update lotes set data_pesagem = current_date - 40 where id = $1`, [lote_id]);
    assert.deepEqual((await u.op.rpc('aprovar_lote', lote_id)).pendencias, ['pesagem_antiga']);
    await admin.query(`update lotes set data_pesagem = current_date - 2 where id = $1`, [lote_id]);
    assert.equal((await u.op.rpc('aprovar_lote', lote_id)).ok, true);
  });

  test('leilão: incluir lotes aprovados, agendar e abrir', async () => {
    const leilao = (await admin.query(
      `insert into leiloes (tenant_id, titulo, abre_em, primeiro_fechamento_em) values ($1, 'Leilão teste', now() - interval '1 min', now() + interval '1 hour') returning id`,
      [tenantId])).rows[0].id;
    const ids = [];
    for (let i = 0; i < 2; i++) {
      const { lote_id } = await u.op.rpc('salvar_lote', tenantId, null, { ...LOTE, vendedor_id: vendedorId });
      ids.push(lote_id);
    }
    assert.equal((await u.op.rpc('definir_leilao_do_lote', ids[0], leilao)).codigo, 'status', 'rascunho não entra');
    for (const id of ids) {
      await midias(id);
      await u.op.rpc('aprovar_lote', id);
      assert.equal((await u.op.rpc('definir_leilao_do_lote', id, leilao)).ok, true);
    }
    const ordens = (await admin.query(`select ordem from lotes where id = any($1) order by ordem`, [ids])).rows.map((x) => x.ordem);
    assert.deepEqual(ordens, [1, 2]);
    assert.equal((await u.op.rpc('agendar_leilao', leilao)).lotes_agendados, 2);
    await admin.query(`select public.processar_relogio()`);
    assert.equal((await admin.query(`select status from lotes where id = $1`, [ids[0]])).rows[0].status, 'aberto');
    assert.equal((await u.op.rpc('definir_leilao_do_lote', ids[0], null)).codigo, 'status', 'lote aberto não sai do leilão');
  });
});

describe('Ao vivo e pós-venda', () => {
  async function loteAberto() {
    const vend = (await admin.query(`select usuario_id from papeis_usuario where papel = 'vendedor' and tenant_id = $1 limit 1`, [tenantId])).rows[0].usuario_id;
    return (await admin.query(
      `insert into lotes (tenant_id, vendedor_id, titulo, categoria, raca, sexo, quantidade, peso_medio, data_pesagem, cidade, uf, preco_inicial, abre_em, termina_em, status)
       values ($1, $2, 'Lote', 'garrotes', 'Nelore', 'macho', 10, 200, current_date, 'Mococa', 'SP', 2000, now() - interval '1 h', now() + interval '1 h', 'aberto') returning id`,
      [tenantId, vend])).rows[0].id;
  }

  test('cancelar lote aberto exige admin e motivo, e avisa quem deu lance', async () => {
    const id = await loteAberto();
    await u.comp.rpc('place_bid', id, 2000, 'manual', null, null);
    assert.equal((await u.op.rpc('cancelar_lote', id, 'motivo')).codigo, 'sem_permissao');
    assert.equal((await u.adm.rpc('cancelar_lote', id, ' ')).codigo, 'motivo');
    assert.equal((await u.adm.rpc('cancelar_lote', id, 'Animal doente')).ok, true);
    assert.equal((await admin.query(`select status from lotes where id = $1`, [id])).rows[0].status, 'cancelado');
    const n = (await admin.query(`select tipo from notificacoes where lote_id = $1 and usuario_id = $2`, [id, u.comp.id])).rows;
    assert.ok(n.some((x) => x.tipo === 'lote_cancelado'));
    assert.equal((await u.comp.rpc('place_bid', id, 2100, 'manual', null, null)).codigo, 'lote_encerrado');
  });

  test('confirmar pagamento: só admin, uma vez, avisa as partes', async () => {
    const id = await loteAberto();
    await u.comp.rpc('place_bid', id, 2000, 'manual', null, null);
    await admin.query(`update lotes set termina_em = now() - interval '1 s' where id = $1`, [id]);
    await admin.query(`select public.encerrar_lote($1)`, [id]);
    const venda = (await admin.query(`select id from vendas where lote_id = $1`, [id])).rows[0].id;
    assert.equal((await u.op.rpc('confirmar_pagamento', venda, null)).codigo, 'sem_permissao');
    assert.equal((await u.adm.rpc('confirmar_pagamento', venda, 'PIX 01/11')).ok, true);
    assert.equal((await u.adm.rpc('confirmar_pagamento', venda, null)).codigo, 'status');
    const pg_ = (await admin.query(`select valor, status from pagamentos where venda_id = $1`, [venda])).rows;
    assert.equal(pg_.length, 1);
    assert.equal(Number(pg_[0].valor), 2000 * 10 * 1.02);
    assert.equal((await admin.query(`select status from lotes where id = $1`, [id])).rows[0].status, 'pago_em_garantia');
  });

  test('resumo do painel só para a equipe', async () => {
    const r = await u.op.rpc('resumo_painel', tenantId);
    assert.ok(r.lotes_abertos >= 1);
    assert.equal(await u.comp.rpc('resumo_painel', tenantId), null);
  });
});
