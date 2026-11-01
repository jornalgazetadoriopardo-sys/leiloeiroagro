// Testes do motor de lances — casos obrigatórios da seção 7.7 do guia
// e regras complementares (seções 5.3, 7.2, 7.3, 7.4, 10.4).
//
// Rodar: npm run test:db
import { test, before, after, describe } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import pg from 'pg';
import { subirBanco } from './db.mjs';

let banco, admin, tenantId;
const clientes = new Map();
const u = {}; // usuários do cenário: { id (usuarios.id), auth (auth.users.id) }

const MIN = 60_000;

before(async () => {
  banco = await subirBanco();
  admin = banco.admin;

  tenantId = (await admin.query(
    `insert into tenants (nome, subdominio) values ('Leiloeira Piloto', 'piloto') returning id`)).rows[0].id;
  // Nos testes, sem limite de frequência (há um teste específico para ele)
  await config('lance.intervalo_minimo_ms', 0);

  const pessoas = {
    vendedor: 'verificado', A: 'verificado', B: 'verificado', C: 'verificado',
    pendente: 'pendente', suspenso: 'suspenso', delegado: 'verificado',
    outroTenant: 'verificado',
  };
  for (const [nome, status] of Object.entries(pessoas)) {
    const auth = (await admin.query(`insert into auth.users (phone) values ($1) returning id`, [nome])).rows[0].id;
    const { rows } = await admin.query(
      `insert into usuarios (tenant_id, auth_user_id, nome, celular, cidade, uf, status_verificacao)
       values ($1, $2, $3, $4, 'Mococa', 'SP', $5) returning id`,
      [tenantId, auth, nome, `+55199${Math.floor(Math.random() * 1e8)}`, status]);
    u[nome] = { id: rows[0].id, auth };
  }
  await admin.query(`insert into papeis_usuario (tenant_id, usuario_id, papel) values ($1, $2, 'vendedor')`, [tenantId, u.vendedor.id]);
});

after(async () => {
  for (const c of clientes.values()) await c.end();
  await banco?.parar();
});

// ---------------------------------------------------------------- helpers
async function config(chave, valor) {
  await admin.query(
    `insert into configuracoes (tenant_id, chave, valor) values ($1, $2, $3::jsonb)
     on conflict (tenant_id, chave) do update set valor = excluded.valor`,
    [tenantId, chave, JSON.stringify(valor)]);
}

/** Conexão logada como o usuário (papel authenticated, como na API do Supabase). */
async function como(nome) {
  if (clientes.has(nome)) return clientes.get(nome);
  const c = new pg.Client({ connectionString: banco.url });
  await c.connect();
  if (nome === 'service') {
    await c.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ role: 'service_role' })]);
    await c.query('set role service_role');
  } else {
    await c.query(`select set_config('request.jwt.claims', $1, false)`,
      [JSON.stringify({ sub: u[nome].auth, role: 'authenticated' })]);
    await c.query('set role authenticated');
  }
  clientes.set(nome, c);
  return c;
}

async function lance(nome, loteId, valor, tipo = 'manual', { chave = null, emNomeDe = null, cliente } = {}) {
  const c = cliente || (await como(nome));
  const { rows } = await c.query(`select public.place_bid($1, $2, $3, $4, $5) as r`, [loteId, valor, tipo, chave, emNomeDe]);
  return rows[0].r;
}

async function criarLote({ precoInicial = 2800, quantidade = 30, terminaEmMs = 60 * MIN, reserva = null, status = 'aberto', leilaoId = null } = {}) {
  const { rows } = await admin.query(
    `insert into lotes (tenant_id, leilao_id, vendedor_id, titulo, categoria, raca, sexo, quantidade, peso_medio,
                        data_pesagem, cidade, uf, preco_inicial, preco_reserva, abre_em, termina_em, termina_em_original, status)
     values ($1, $2, $3, '30 garrotes Nelore', 'garrotes', 'Nelore', 'macho', $4, 268, current_date, 'Mococa', 'SP',
             $5, $6, now() - interval '1 hour', now() + $7 * interval '1 millisecond', now() + $7 * interval '1 millisecond', $8)
     returning id`,
    [tenantId, leilaoId, u.vendedor.id, quantidade, precoInicial, reserva, terminaEmMs, status]);
  return rows[0].id;
}

const lote = async (id) => (await admin.query(`select * from lotes where id = $1`, [id])).rows[0];
const historico = async (id) => (await admin.query(
  `select usuario_id, valor_por_cabeca::numeric::float8 as valor, tipo from lances where lote_id = $1 order by seq`, [id])).rows;
const quem = (id) => Object.keys(u).find((k) => u[k].id === id);

// ------------------------------------------------- 7.7 casos obrigatórios
describe('Seção 7.7 — casos obrigatórios', () => {
  test('1. lance abaixo do mínimo é recusado', async () => {
    const id = await criarLote();
    const abaixoInicial = await lance('A', id, 2790);
    assert.equal(abaixoInicial.ok, false);
    assert.equal(abaixoInicial.codigo, 'abaixo_minimo');

    assert.equal((await lance('A', id, 2800)).ok, true); // primeiro lance = preço inicial
    const r = await lance('B', id, 2810);                 // incremento mínimo é R$ 20
    assert.equal(r.ok, false);
    assert.equal(r.codigo, 'abaixo_minimo');
    assert.equal(Number(r.minimo), 2820);
    assert.match(r.mensagem, /R\$ 2\.820/);
    assert.equal((await lance('B', id, 2820)).ok, true);
  });

  test('2. lance após o horário de término é recusado (mesmo sem o worker ter rodado)', async () => {
    const id = await criarLote({ terminaEmMs: -1000 }); // status ainda "aberto"
    const r = await lance('A', id, 3000);
    assert.equal(r.ok, false);
    assert.equal(r.codigo, 'lote_encerrado');
    assert.equal((await lote(id)).qtd_lances, 0);
  });

  test('3. dois lances simultâneos no mesmo valor: só o primeiro é aceito', async () => {
    const id = await criarLote();
    // Conexões dedicadas, disparadas enquanto a linha do lote está travada
    const cA = new pg.Client({ connectionString: banco.url });
    const cB = new pg.Client({ connectionString: banco.url });
    const trava = new pg.Client({ connectionString: banco.url });
    await Promise.all([cA.connect(), cB.connect(), trava.connect()]);
    for (const [c, n] of [[cA, 'A'], [cB, 'B']]) {
      await c.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ sub: u[n].auth, role: 'authenticated' })]);
      await c.query('set role authenticated');
    }
    await trava.query('begin');
    await trava.query('select 1 from lotes where id = $1 for update', [id]);
    const pA = lance('A', id, 2800, 'manual', { cliente: cA });
    await new Promise((r) => setTimeout(r, 150));
    const pB = lance('B', id, 2800, 'manual', { cliente: cB });
    await new Promise((r) => setTimeout(r, 150));
    await trava.query('commit');
    const [rA, rB] = await Promise.all([pA, pB]);
    await Promise.all([cA.end(), cB.end(), trava.end()]);

    assert.equal(rA.ok, true, 'o primeiro a chegar vence');
    assert.equal(rB.ok, false);
    assert.equal(rB.codigo, 'abaixo_minimo');
    const h = await historico(id);
    assert.equal(h.length, 1);
    assert.equal(quem(h[0].usuario_id), 'A');
  });

  test('4. lance com 2 min restantes leva o término para agora + 3 min', async () => {
    const id = await criarLote({ terminaEmMs: 2 * MIN });
    const antes = Date.now();
    const r = await lance('A', id, 2800);
    assert.equal(r.ok, true);
    assert.equal(r.prorrogou_agora, true);
    const l = await lote(id);
    assert.equal(l.prorrogado, true);
    const restante = l.termina_em.getTime() - antes;
    assert.ok(restante > 2.9 * MIN && restante < 3.1 * MIN, `restante = ${restante} ms`);
  });

  test('5. lance com 5 min restantes não altera o término', async () => {
    const id = await criarLote({ terminaEmMs: 5 * MIN });
    const antes = (await lote(id)).termina_em.getTime();
    const r = await lance('A', id, 2800);
    assert.equal(r.ok, true);
    assert.equal(r.prorrogou_agora, false);
    const l = await lote(id);
    assert.equal(l.termina_em.getTime(), antes);
    assert.equal(l.prorrogado, false);
  });

  test('6. teto de A (3.100) contra lance manual de B (2.950): A lidera com 2.970', async () => {
    const id = await criarLote();
    assert.equal((await lance('A', id, 3100, 'teto')).ok, true);
    const rB = await lance('B', id, 2950);
    assert.equal(rB.ok, true);
    assert.equal(rB.voce_lidera, false);
    const l = await lote(id);
    assert.equal(Number(l.lance_atual), 2970);
    assert.equal(quem(l.lider_id), 'A');
    assert.deepEqual((await historico(id)).map((h) => [quem(h.usuario_id), h.valor, h.tipo]), [
      ['A', 2800, 'automatico'],
      ['B', 2950, 'manual'],
      ['A', 2970, 'automatico'],
    ]);
  });

  test('7. tetos de A (3.100) e B (3.000): A lidera com 3.020 — nas duas ordens', async () => {
    for (const ordem of [['A', 'B'], ['B', 'A']]) {
      const id = await criarLote();
      for (const n of ordem) assert.equal((await lance(n, id, n === 'A' ? 3100 : 3000, 'teto')).ok, true);
      const l = await lote(id);
      assert.equal(Number(l.lance_atual), 3020, `ordem ${ordem}`);
      assert.equal(quem(l.lider_id), 'A');
      const tetoB = (await admin.query(`select ativo from tetos where lote_id = $1 and usuario_id = $2`, [id, u.B.id])).rows[0];
      assert.equal(tetoB.ativo, false, 'teto de B esgotado');
    }
  });

  test('8. tetos iguais: vence quem registrou primeiro — nas duas ordens', async () => {
    for (const [primeiro, segundo] of [['A', 'B'], ['B', 'A']]) {
      const id = await criarLote();
      await lance(primeiro, id, 3000, 'teto');
      const r2 = await lance(segundo, id, 3000, 'teto');
      assert.equal(r2.ok, true);
      assert.equal(r2.voce_lidera, false);
      const l = await lote(id);
      assert.equal(quem(l.lider_id), primeiro);
      assert.equal(Number(l.lance_atual), 3000);
    }
  });

  test('9. vendedor não consegue dar lance no próprio lote', async () => {
    const id = await criarLote();
    for (const tipo of ['manual', 'teto']) {
      const r = await lance('vendedor', id, 3000, tipo);
      assert.equal(r.ok, false);
      assert.equal(r.codigo, 'vendedor_do_lote');
    }
  });

  test('10. usuário pendente ou suspenso não consegue dar lance', async () => {
    const id = await criarLote();
    const rP = await lance('pendente', id, 2800);
    assert.equal(rP.ok, false);
    assert.equal(rP.codigo, 'cadastro_pendente');
    const rS = await lance('suspenso', id, 2800, 'teto');
    assert.equal(rS.ok, false);
    assert.equal(rS.codigo, 'cadastro_suspenso');
    assert.equal((await lote(id)).qtd_lances, 0);
  });

  test('11. encerramento executado duas vezes gera um único pedido', async () => {
    const id = await criarLote();
    await lance('A', id, 2800);
    await lance('B', id, 2900);
    await admin.query(`update lotes set termina_em = now() - interval '1 second' where id = $1`, [id]);

    const svc = await como('service');
    const [r1, r2] = await Promise.all([
      svc.query(`select public.encerrar_lote($1) as r`, [id]),
      admin.query(`select public.encerrar_lote($1) as r`, [id]),
    ]);
    await svc.query(`select public.processar_relogio()`); // terceira passada, pelo relógio
    assert.ok([r1.rows[0].r, r2.rows[0].r].some((r) => r.ja_processado), 'uma das chamadas encontra o lote já encerrado');

    const vendas = (await admin.query(`select * from vendas where lote_id = $1`, [id])).rows;
    assert.equal(vendas.length, 1);
    assert.equal(quem(vendas[0].comprador_id), 'B');
    assert.equal(Number(vendas[0].total), 2900 * 30);
    assert.equal(Number(vendas[0].comissao_comprador), 2900 * 30 * 0.02);
    assert.equal((await lote(id)).status, 'aguardando_pagamento');
    const avisos = (await admin.query(
      `select tipo from notificacoes where lote_id = $1 and tipo in ('arremate', 'lote_vendido') order by tipo`, [id])).rows;
    assert.deepEqual(avisos.map((a) => a.tipo), ['arremate', 'lote_vendido']);
  });

  test('12. reserva não atingida resulta em "não vendido", com consulta ao vendedor', async () => {
    const id = await criarLote({ reserva: 3500 });
    await lance('A', id, 3000);
    await admin.query(`update lotes set termina_em = now() - interval '1 second' where id = $1`, [id]);
    const r = (await (await como('service')).query(`select public.encerrar_lote($1) as r`, [id])).rows[0].r;
    assert.equal(r.status, 'nao_vendido');

    const l = await lote(id);
    assert.equal(l.reserva_nao_atingida, true);
    assert.equal(l.consulta_vendedor_status, 'pendente');
    assert.ok(l.consulta_vendedor_ate > new Date(Date.now() + 23 * 60 * MIN));
    const tipos = (await admin.query(`select tipo, usuario_id from notificacoes where lote_id = $1`, [id])).rows;
    assert.ok(tipos.some((t) => t.tipo === 'consulta_reserva' && quem(t.usuario_id) === 'vendedor'));
    assert.ok(tipos.some((t) => t.tipo === 'aguardando_confirmacao_vendedor' && quem(t.usuario_id) === 'A'));
    assert.equal((await admin.query(`select count(*)::int as n from vendas where lote_id = $1`, [id])).rows[0].n, 0);

    // Outro usuário não responde pelo vendedor; o vendedor aceita e a venda nasce
    assert.equal((await (await como('B')).query(`select public.responder_consulta_vendedor($1, true) as r`, [id])).rows[0].r.codigo, 'sem_permissao');
    const aceite = (await (await como('vendedor')).query(`select public.responder_consulta_vendedor($1, true) as r`, [id])).rows[0].r;
    assert.equal(aceite.ok, true);
    assert.equal((await lote(id)).status, 'aguardando_pagamento');
    assert.equal((await admin.query(`select count(*)::int as n from vendas where lote_id = $1`, [id])).rows[0].n, 1);
  });
});

// ---------------------------------------------------- regras complementares
describe('Regras complementares', () => {
  test('lance coberto gera aviso para o líder anterior', async () => {
    const id = await criarLote();
    await lance('A', id, 2800);
    await lance('B', id, 2850);
    const n = (await admin.query(`select tipo, usuario_id, dados from notificacoes where lote_id = $1`, [id])).rows;
    assert.equal(n.length, 1);
    assert.equal(n[0].tipo, 'lance_coberto');
    assert.equal(quem(n[0].usuario_id), 'A');
    assert.equal(Number(n[0].dados.lance_atual), 2850);
  });

  test('teto esgotado avisa o dono com "teto_atingido"', async () => {
    const id = await criarLote();
    await lance('A', id, 2900, 'teto');
    await lance('B', id, 3000);
    const n = (await admin.query(`select tipo, usuario_id from notificacoes where lote_id = $1`, [id])).rows;
    assert.deepEqual(n.map((x) => [x.tipo, quem(x.usuario_id)]), [['teto_atingido', 'A']]);
  });

  test('lance manual igual a um teto registrado antes: vence o teto', async () => {
    const id = await criarLote();
    await lance('A', id, 3100, 'teto');
    const r = await lance('B', id, 3100);
    assert.equal(r.ok, true);
    assert.equal(r.voce_lidera, false);
    const l = await lote(id);
    assert.equal(quem(l.lider_id), 'A');
    assert.equal(Number(l.lance_atual), 3100);
  });

  test('líder pode aumentar o teto, mas não cancelar enquanto lidera', async () => {
    const id = await criarLote();
    await lance('A', id, 3000, 'teto');
    assert.equal((await lance('A', id, 2900, 'teto')).codigo, 'teto_invalido');
    const r = await lance('A', id, 3200, 'teto');
    assert.equal(r.ok, true);
    assert.equal(Number(r.teto), 3200);
    assert.equal((await lote(id)).qtd_lances, 1, 'aumentar o teto não gera lance novo');
    const c = (await (await como('A')).query(`select public.cancelar_teto($1) as r`, [id])).rows[0].r;
    assert.equal(c.codigo, 'lider_nao_cancela');
  });

  test('três tetos concorrentes', async () => {
    const id = await criarLote();
    await lance('A', id, 3000, 'teto');
    await lance('B', id, 3300, 'teto');
    await lance('C', id, 3150, 'teto');
    const l = await lote(id);
    assert.equal(quem(l.lider_id), 'B');
    assert.equal(Number(l.lance_atual), 3170);
  });

  test('idempotência: a mesma chave não gera dois lances', async () => {
    const id = await criarLote();
    const chave = randomUUID();
    const r1 = await lance('A', id, 2800, 'manual', { chave });
    const r2 = await lance('A', id, 2800, 'manual', { chave });
    assert.equal(r1.ok, true);
    assert.equal(r2.ok, true);
    assert.equal(r2.repetido, true);
    assert.equal((await historico(id)).length, 1);
  });

  test('limite de frequência: no máximo 1 lance por segundo por lote', async () => {
    await config('lance.intervalo_minimo_ms', 1000);
    try {
      const id = await criarLote();
      assert.equal((await lance('A', id, 2800)).ok, true);
      assert.equal((await lance('A', id, 2900)).codigo, 'muitos_lances');
    } finally {
      await config('lance.intervalo_minimo_ms', 0);
    }
  });

  test('limite de crédito bloqueia lance acima do limite', async () => {
    await admin.query(`update usuarios set limite_credito = 100000 where id = $1`, [u.C.id]);
    try {
      const id = await criarLote({ quantidade: 30 });
      const r = await lance('C', id, 3500); // 105.000 > 100.000
      assert.equal(r.codigo, 'limite_credito');
      assert.equal(Number(r.disponivel), 100000);
      assert.equal((await lance('C', id, 3300)).ok, true); // 99.000
      const outro = await criarLote({ quantidade: 30 });
      assert.equal((await lance('C', outro, 2800)).codigo, 'limite_credito', 'lote liderado conta no limite');
    } finally {
      await admin.query(`update usuarios set limite_credito = null where id = $1`, [u.C.id]);
    }
  });

  test('acesso delegado: lance em nome do titular registra quem clicou', async () => {
    const id = await criarLote();
    assert.equal((await lance('delegado', id, 2800, 'manual', { emNomeDe: u.A.id })).codigo, 'sem_delegacao');
    await admin.query(`insert into acessos_delegados (tenant_id, titular_id, delegado_id) values ($1, $2, $3)`,
      [tenantId, u.A.id, u.delegado.id]);
    const r = await lance('delegado', id, 2800, 'manual', { emNomeDe: u.A.id });
    assert.equal(r.ok, true);
    const x = (await admin.query(`select usuario_id, delegado_id from lances where lote_id = $1`, [id])).rows[0];
    assert.equal(quem(x.usuario_id), 'A');
    assert.equal(quem(x.delegado_id), 'delegado');
  });

  test('lote agendado ainda não aceita lance', async () => {
    const id = await criarLote({ status: 'agendado' });
    assert.equal((await lance('A', id, 2800)).codigo, 'lote_nao_aberto');
  });

  test('lote sem lances encerra como não vendido', async () => {
    const id = await criarLote({ terminaEmMs: -1000 });
    const r = (await (await como('service')).query(`select public.encerrar_lote($1) as r`, [id])).rows[0].r;
    assert.equal(r.status, 'nao_vendido');
    assert.equal((await lote(id)).reserva_nao_atingida, false);
  });
});

describe('Seção 7.2 — encerramento escalonado', () => {
  test('lotes fecham em sequência e a prorrogação de um não empurra os seguintes', async () => {
    const leilao = (await admin.query(
      `insert into leiloes (tenant_id, titulo, abre_em, primeiro_fechamento_em)
       values ($1, 'Leilão de novembro', now() - interval '1 minute', now() + interval '2 minutes') returning id`,
      [tenantId])).rows[0].id;
    const ids = [];
    for (let i = 0; i < 3; i++) ids.push(await criarLote({ status: 'aprovado', leilaoId: leilao }));

    const r = (await (await como('A')).query(`select public.agendar_leilao($1) as r`, [leilao])).rows[0].r;
    assert.equal(r.codigo, 'sem_permissao', 'comprador não agenda leilão');
    const ok = (await (await como('service')).query(`select public.agendar_leilao($1) as r`, [leilao])).rows[0].r;
    assert.equal(ok.lotes_agendados, 3);

    const fins = [];
    for (const id of ids) fins.push((await lote(id)).termina_em.getTime());
    assert.equal(fins[1] - fins[0], 2 * MIN);
    assert.equal(fins[2] - fins[1], 2 * MIN);

    const relogio = (await (await como('service')).query(`select public.processar_relogio() as r`)).rows[0].r;
    assert.ok(relogio.abertos >= 3);
    assert.equal((await lote(ids[0])).status, 'aberto');
    assert.equal((await admin.query(`select status from leiloes where id = $1`, [leilao])).rows[0].status, 'aberto');

    // Lote 1 tem ~2 min restantes: lance prorroga só ele
    await lance('A', ids[0], 2800);
    const depois = [];
    for (const id of ids) depois.push(await lote(id));
    assert.ok(depois[0].termina_em.getTime() > fins[0]);
    assert.equal(depois[1].termina_em.getTime(), fins[1]);
    assert.equal(depois[2].termina_em.getTime(), fins[2]);
  });
});

describe('Seção 10.4 — avisos de dou-lhe', () => {
  test('abertura agenda dou-lhe 1/2/3; prorrogação reagenda e limita avisos extras', async () => {
    const id = await criarLote({ status: 'agendado', terminaEmMs: 30 * MIN });
    await (await como('service')).query(`select public.processar_relogio()`);
    const fim = (await lote(id)).termina_em.getTime();
    const avisos = (await admin.query(`select tipo, agendado_para from avisos_lote where lote_id = $1 order by agendado_para`, [id])).rows;
    assert.deepEqual(avisos.map((a) => a.tipo), ['doulhe_1', 'doulhe_2', 'doulhe_3']);
    assert.deepEqual(avisos.map((a) => (fim - a.agendado_para.getTime()) / MIN), [10, 5, 3]);

    // Dou-lhe 1, 2 e 3 já enviados; lote com 1 min restante
    await admin.query(`update avisos_lote set status = 'enviado', enviado_em = now() where lote_id = $1`, [id]);
    await admin.query(`update lotes set termina_em = now() + interval '1 minute' where id = $1`, [id]);
    for (const [n, v] of [['A', 2800], ['B', 2820], ['A', 2840], ['B', 2860]]) {
      assert.equal((await lance(n, id, v)).prorrogou_agora, true);
    }
    const extras = (await admin.query(
      `select tipo from avisos_lote where lote_id = $1 and tipo like 'prorrogacao%' order by tipo`, [id])).rows;
    assert.deepEqual(extras.map((a) => a.tipo), ['prorrogacao_1', 'prorrogacao_2'], 'no máximo 2 avisos de prorrogação');
    const reenviado = (await admin.query(
      `select count(*)::int as n from avisos_lote where lote_id = $1 and tipo = 'doulhe_3' and status = 'pendente'`, [id])).rows[0].n;
    assert.equal(reenviado, 0, 'dou-lhe 3 não é repetido');
  });

  test('prorrogação antes do dou-lhe 3 sair: o aviso é reagendado, não duplicado', async () => {
    const id = await criarLote({ status: 'agendado', terminaEmMs: 30 * MIN });
    await (await como('service')).query(`select public.processar_relogio()`);
    await admin.query(`update lotes set termina_em = now() + interval '2 minutes' where id = $1`, [id]);
    await lance('A', id, 2800);
    const d3 = (await admin.query(`select * from avisos_lote where lote_id = $1 and tipo = 'doulhe_3'`, [id])).rows;
    assert.equal(d3.length, 1);
    assert.equal(d3[0].status, 'pendente');
    assert.ok(Math.abs(d3[0].agendado_para.getTime() - Date.now()) < 5000, 'sai agora (faltam 3 min)');
  });
});

describe('Seção 4.3 / 7.4 — segurança e anonimato', () => {
  test('comprador não lê a tabela de lotes (reserva, vendedor) nem tetos de outros', async () => {
    const id = await criarLote({ reserva: 4000 });
    await lance('A', id, 3100, 'teto');
    const b = await como('B');
    assert.equal((await b.query(`select * from lotes where id = $1`, [id])).rowCount, 0);
    assert.equal((await b.query(`select * from tetos where lote_id = $1`, [id])).rowCount, 0);
    const a = await como('A');
    assert.equal((await a.query(`select valor_maximo from tetos where lote_id = $1`, [id])).rowCount, 1, 'dono vê o próprio teto');

    const pub = (await b.query(`select * from lotes_publicos where id = $1`, [id])).rows[0];
    assert.ok(pub);
    assert.equal('preco_reserva' in pub, false);
    assert.equal('vendedor_id' in pub, false);
    assert.equal('lider_id' in pub, false);
    assert.match(pub.vendedor_rotulo, /^Fazenda #\d+ · Mococa-SP$/);
    assert.equal(Number(pub.lance_minimo), 2820);
  });

  test('histórico anônimo: "Você · automático" para o dono, "Comprador #" para os demais', async () => {
    const id = await criarLote();
    await lance('A', id, 3100, 'teto');
    await lance('B', id, 2950);
    const visaoA = (await (await como('A')).query(`select rotulo from lances_publicos where lote_id = $1 order by seq`, [id])).rows;
    const visaoB = (await (await como('B')).query(`select rotulo from lances_publicos where lote_id = $1 order by seq`, [id])).rows;
    assert.equal(visaoA[2].rotulo, 'Você · automático');
    assert.match(visaoB[2].rotulo, /^Comprador #\d+ · Mococa-SP$/);
    assert.equal(visaoB[1].rotulo, 'Você');
  });

  test('ninguém grava lance direto na tabela nem encerra lote pela API', async () => {
    const id = await criarLote();
    const a = await como('A');
    await assert.rejects(a.query(
      `insert into lances (tenant_id, lote_id, usuario_id, valor_por_cabeca, tipo) values ($1, $2, $3, 9999, 'manual')`,
      [tenantId, id, u.A.id]), /permission denied/);
    await assert.rejects(a.query(`select public.encerrar_lote($1)`, [id]), /permission denied/);
    await assert.rejects(a.query(`update usuarios set status_verificacao = 'verificado' where id = $1`, [u.A.id]), /permission denied/);
  });

  test('um tenant não vê dados de outro', async () => {
    const outro = (await admin.query(`insert into tenants (nome, subdominio) values ('Outra', 'outra') returning id`)).rows[0].id;
    const auth = (await admin.query(`insert into auth.users (phone) values ('x') returning id`)).rows[0].id;
    await admin.query(`insert into usuarios (tenant_id, auth_user_id, celular, status_verificacao) values ($1, $2, '+5511', 'verificado')`, [outro, auth]);
    const adm = (await admin.query(`select id from usuarios where auth_user_id = $1`, [auth])).rows[0].id;
    await admin.query(`insert into papeis_usuario (tenant_id, usuario_id, papel) values ($1, $2, 'admin')`, [outro, adm]);

    const c = new pg.Client({ connectionString: banco.url });
    await c.connect();
    await c.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ sub: auth, role: 'authenticated' })]);
    await c.query('set role authenticated');
    try {
      assert.equal((await c.query(`select * from lotes where tenant_id = $1`, [tenantId])).rowCount, 0);
      assert.equal((await c.query(`select * from usuarios where tenant_id = $1`, [tenantId])).rowCount, 0);
      assert.equal((await c.query(`select * from audit_log where tenant_id = $1`, [tenantId])).rowCount, 0);
      const id = await criarLote();
      assert.equal((await lance(null, id, 2800, 'manual', { cliente: c })).codigo, 'sem_cadastro');
    } finally {
      await c.end();
    }
  });

  test('audit_log registra lances e lances recusados', async () => {
    const id = await criarLote();
    await lance('A', id, 2800);
    await lance('B', id, 2801);
    const acoes = (await admin.query(
      `select acao, entidade from audit_log where (entidade = 'lances' and dados_depois->>'lote_id' = $1::text)
          or (entidade = 'lotes' and entidade_id = $1::uuid and acao = 'lance_recusado')`, [id])).rows;
    assert.ok(acoes.some((a) => a.entidade === 'lances' && a.acao === 'insert'));
    assert.ok(acoes.some((a) => a.acao === 'lance_recusado'));
  });
});
