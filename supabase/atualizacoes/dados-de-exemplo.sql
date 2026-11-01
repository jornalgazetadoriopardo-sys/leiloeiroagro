-- =====================================================================
-- DADOS DE EXEMPLO — 4 vendedores, 6 compradores fictícios e 3 leilões
-- (2 abertos com lances, 1 agendado). Para ver o site e o painel "vivos".
--
-- Como usar: SQL Editor → cole tudo → Run.
-- Rodar de novo não duplica. Para apagar, use o bloco LIMPAR no fim.
-- Marcadores: leilões com descricao começando por "[exemplo]" e
-- pessoas fictícias com celular +5500000…
-- =====================================================================
do $$
declare
  v_tenant   uuid := (select id from public.tenants where subdominio = 'piloto');
  v_tz       text := 'America/Sao_Paulo';
  v_hoje     timestamp := date_trunc('day', now() at time zone 'America/Sao_Paulo');
  v_vend     uuid[] := '{}';
  v_faz      uuid[] := '{}';
  v_comp     uuid[] := '{}';
  v_leilao   uuid[] := '{}';
  v_id       uuid;
  v_lote     uuid;
  r          record;
  v_valor    numeric;
  v_lider    uuid;
  i          int;
begin
  if v_tenant is null then raise exception 'Leiloeira "piloto" não encontrada.'; end if;
  if exists (select 1 from public.leiloes where tenant_id = v_tenant and descricao like '[exemplo]%') then
    raise notice 'Os dados de exemplo já existem.';
    return;
  end if;

  -- Vendedores (cadastrados pela leiloeira) e suas fazendas
  for r in select * from (values
    ('José Carlos Pereira',   '+5500000000101', 'Mococa',                  'SP', 'Fazenda Boa Vista'),
    ('Maria Aparecida Souza', '+5500000000102', 'Casa Branca',             'SP', 'Sítio Santa Luzia'),
    ('Antônio Ribeiro Lima',  '+5500000000103', 'Tambaú',                  'SP', 'Fazenda Três Irmãos'),
    ('Paulo Henrique Alves',  '+5500000000104', 'São José do Rio Pardo',   'SP', 'Fazenda Recanto do Pardo')
  ) as t(nome, celular, cidade, uf, fazenda) loop
    insert into public.usuarios (tenant_id, nome, celular, cidade, uf, status_verificacao, cadastro_enviado_em)
    values (v_tenant, r.nome, r.celular, r.cidade, r.uf, 'verificado', now()) returning id into v_id;
    insert into public.papeis_usuario (tenant_id, usuario_id, papel) values (v_tenant, v_id, 'vendedor');
    v_vend := v_vend || v_id;
    insert into public.fazendas (tenant_id, vendedor_id, nome, cidade, uf) values (v_tenant, v_id, r.fazenda, r.cidade, r.uf)
    returning id into v_id;
    v_faz := v_faz || v_id;
  end loop;

  -- Compradores fictícios (verificados) para dar movimento aos lotes
  for r in select * from (values
    ('Carlos Mendes',    '+5500000000201', 'Mococa'),
    ('Rogério Tavares',  '+5500000000202', 'Casa Branca'),
    ('Luiz Fernando',    '+5500000000203', 'São Sebastião da Grama'),
    ('Ana Paula Rocha',  '+5500000000204', 'Vargem Grande do Sul'),
    ('Marcos Vinícius',  '+5500000000205', 'Divinolândia'),
    ('Sebastião Prado',  '+5500000000206', 'Tambaú')
  ) as t(nome, celular, cidade) loop
    insert into public.usuarios (tenant_id, nome, celular, cidade, uf, status_verificacao, cadastro_enviado_em)
    values (v_tenant, r.nome, r.celular, r.cidade, 'SP', 'verificado', now()) returning id into v_id;
    insert into public.papeis_usuario (tenant_id, usuario_id, papel) values (v_tenant, v_id, 'comprador');
    v_comp := v_comp || v_id;
  end loop;

  -- Leilões: (1) fecha hoje em ~3 h; (2) fecha amanhã às 20h; (3) agendado
  insert into public.leiloes (tenant_id, titulo, descricao, abre_em, primeiro_fechamento_em, intervalo_fechamento, status)
  values (v_tenant, 'Garrotes e bois magros – Mococa', '[exemplo] Lotes da região de Mococa',
          now() - interval '1 day', now() + interval '3 hours', interval '2 minutes', 'aberto')
  returning id into v_id; v_leilao := v_leilao || v_id;
  insert into public.leiloes (tenant_id, titulo, descricao, abre_em, primeiro_fechamento_em, intervalo_fechamento, status)
  values (v_tenant, 'Novilhas e vacas – Casa Branca', '[exemplo] Fêmeas de reposição e cria',
          now() - interval '6 hours', (v_hoje + interval '1 day 20 hours') at time zone v_tz, interval '2 minutes', 'aberto')
  returning id into v_id; v_leilao := v_leilao || v_id;
  insert into public.leiloes (tenant_id, titulo, descricao, abre_em, primeiro_fechamento_em, intervalo_fechamento, status)
  values (v_tenant, 'Bezerros desmamados – Tambaú', '[exemplo] Abre daqui a 3 dias',
          (v_hoje + interval '3 days 8 hours') at time zone v_tz, (v_hoje + interval '5 days 20 hours') at time zone v_tz,
          interval '2 minutes', 'agendado')
  returning id into v_id; v_leilao := v_leilao || v_id;

  -- Lotes: leilão, ordem, título, categoria, raça, sexo, cabeças, peso, idade, cidade, vendedor, preço inicial, reserva, nº de lances
  for r in select * from (values
    (1, 1, '30 garrotes Nelore',                     'garrotes',      'Nelore',          'macho', 30, 268, 12, 14, 'Mococa',                1, 2600, null::numeric, 9),
    (1, 2, '25 bois magros Nelore',                  'boi magro',     'Nelore',          'macho', 25, 380, 24, 26, 'Mococa',                1, 3400, 3800,          6),
    (1, 3, '20 garrotes cruzados Angus',             'garrotes',      'Angus × Nelore',  'macho', 20, 290, 13, 15, 'São José do Rio Pardo', 4, 2900, null,          4),
    (1, 4, '35 bois magros anelorados',              'boi magro',     'Anelorado',       'macho', 35, 360, 22, 26, 'São José do Rio Pardo', 4, 3200, null,          0),
    (2, 1, '18 novilhas Nelore',                     'novilhas',      'Nelore',          'femea', 18, 290, 18, 20, 'Casa Branca',           2, 2900, null,          5),
    (2, 2, '12 vacas Girolando em lactação',         'vacas',         'Girolando',       'femea', 12, 480, 48, 72, 'Casa Branca',           2, 6000, 6500,          3),
    (2, 3, '10 vacas paridas Nelore com bezerro',    'vacas paridas', 'Nelore',          'femea', 10, 450, 40, 60, 'Mococa',                1, 5200, null,          2),
    (2, 4, '22 novilhas cruzadas Angus',             'novilhas',      'Angus × Nelore',  'femea', 22, 310, 20, 24, 'São José do Rio Pardo', 4, 3100, null,          0),
    (3, 1, '40 bezerros desmamados anelorados',      'bezerros',      'Anelorado',       'macho', 40, 195,  7,  8, 'Tambaú',                3, 2100, null,          0),
    (3, 2, '20 bezerras Angus × Nelore',             'bezerras',      'Angus × Nelore',  'femea', 20, 210,  8,  9, 'Tambaú',                3, 2650, null,          0),
    (3, 3, '30 bezerros Nelore',                     'bezerros',      'Nelore',          'macho', 30, 185,  7,  8, 'Tambaú',                3, 2000, null,          0)
  ) as t(leilao, ordem, titulo, categoria, raca, sexo, qtd, peso, imin, imax, cidade, vend, inicial, reserva, lances) loop
    insert into public.lotes (tenant_id, leilao_id, vendedor_id, fazenda_id, numero, ordem, titulo, categoria, raca, sexo,
      quantidade, peso_medio, data_pesagem, idade_min, idade_max, sanidade, cidade, uf, tolerancia_quebra,
      preco_inicial, preco_reserva, status)
    values (v_tenant, v_leilao[r.leilao], v_vend[r.vend], v_faz[r.vend], r.ordem, r.ordem, r.titulo, r.categoria, r.raca, r.sexo,
      r.qtd, r.peso, current_date - 3, r.imin, r.imax,
      jsonb_build_object('vacinas', 'Aftosa e brucelose em dia', 'vermifugacao', 'Outubro/2026'),
      r.cidade, 'SP', 3, r.inicial, r.reserva, 'aprovado')
    returning id into v_lote;

    -- Lances fictícios, do mais antigo ao mais recente (R$ 20 a R$ 60 de diferença)
    v_valor := null;
    v_lider := null;
    for i in 1..r.lances loop
      v_valor := case when v_valor is null then r.inicial else v_valor + 20 * (1 + (i % 3)) end;
      v_lider := v_comp[1 + ((i + r.ordem + r.leilao) % 6)];
      insert into public.lances (tenant_id, lote_id, usuario_id, valor_por_cabeca, tipo, criado_em)
      values (v_tenant, v_lote, v_lider, v_valor, 'manual', now() - make_interval(mins => (r.lances - i + 1) * 37));
    end loop;
    update public.lotes set lance_atual = v_valor, lider_id = v_lider, qtd_lances = r.lances where id = v_lote;
  end loop;

  -- Agenda os horários (fechamento escalonado) e abre os leilões que já começaram
  for i in 1..3 loop
    update public.lotes l set
      abre_em = e.abre_em,
      termina_em = e.primeiro_fechamento_em + e.intervalo_fechamento * (l.ordem - 1),
      termina_em_original = e.primeiro_fechamento_em + e.intervalo_fechamento * (l.ordem - 1),
      status = 'agendado'
    from public.leiloes e where e.id = v_leilao[i] and l.leilao_id = e.id;
  end loop;
  perform public.processar_relogio();

  raise notice 'Exemplo criado: 4 vendedores, 6 compradores, 3 leilões e 11 lotes.';
end $$;

-- Conferência
select e.titulo as leilao, l.numero, l.titulo, l.status, l.lance_atual, l.qtd_lances,
       to_char(l.termina_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as fecha
from public.lotes l join public.leiloes e on e.id = l.leilao_id
where e.descricao like '[exemplo]%'
order by e.primeiro_fechamento_em, l.ordem;

-- ===================== LIMPAR (descomente as linhas e rode para apagar o exemplo) =====================
-- delete from public.notificacoes where lote_id in (select l.id from public.lotes l join public.leiloes e on e.id = l.leilao_id where e.descricao like '[exemplo]%');
-- delete from public.vendas where lote_id in (select l.id from public.lotes l join public.leiloes e on e.id = l.leilao_id where e.descricao like '[exemplo]%');
-- delete from public.lances where lote_id in (select l.id from public.lotes l join public.leiloes e on e.id = l.leilao_id where e.descricao like '[exemplo]%');
-- delete from public.lotes where leilao_id in (select id from public.leiloes where descricao like '[exemplo]%');
-- delete from public.leiloes where descricao like '[exemplo]%';
-- delete from public.fazendas where vendedor_id in (select id from public.usuarios where celular like '+5500000%');
-- delete from public.usuarios where celular like '+5500000%';
