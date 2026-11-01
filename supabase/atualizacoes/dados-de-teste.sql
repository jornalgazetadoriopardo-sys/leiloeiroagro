-- DADOS DE TESTE (opcional): um vendedor fictício e um leilão com 3 lotes,
-- para ver a página inicial e a página do lote funcionando.
-- Os lotes abrem sozinhos em até 5 segundos (pg_cron) e fecham em 1, 3 e 24 horas.
-- Para apagar tudo depois, rode o bloco "LIMPAR" no fim deste arquivo.
do $$
declare
  v_tenant  uuid := (select id from public.tenants where subdominio = 'piloto');
  v_vend    uuid;
  v_faz     uuid;
  v_leilao  uuid;
begin
  if exists (select 1 from public.leiloes where tenant_id = v_tenant and titulo = '[TESTE] Leilão de demonstração') then
    raise notice 'Dados de teste já existem.';
    return;
  end if;

  insert into public.usuarios (tenant_id, nome, celular, cidade, uf, status_verificacao)
  values (v_tenant, '[TESTE] Vendedor', '+550000000001', 'Mococa', 'SP', 'verificado') returning id into v_vend;
  insert into public.papeis_usuario (tenant_id, usuario_id, papel) values (v_tenant, v_vend, 'vendedor');
  insert into public.fazendas (tenant_id, vendedor_id, nome, cidade, uf)
  values (v_tenant, v_vend, '[TESTE] Fazenda', 'Mococa', 'SP') returning id into v_faz;

  insert into public.leiloes (tenant_id, titulo, abre_em, primeiro_fechamento_em, status)
  values (v_tenant, '[TESTE] Leilão de demonstração', now(), now() + interval '1 hour', 'agendado')
  returning id into v_leilao;

  insert into public.lotes (tenant_id, leilao_id, vendedor_id, fazenda_id, numero, ordem, titulo, categoria, raca, sexo,
    quantidade, peso_medio, data_pesagem, idade_min, idade_max, sanidade, cidade, uf, tolerancia_quebra,
    preco_inicial, preco_reserva, abre_em, termina_em, termina_em_original, status)
  values
    (v_tenant, v_leilao, v_vend, v_faz, 1, 1, '30 garrotes Nelore', 'garrotes', 'Nelore', 'macho', 30, 268, current_date - 3, 12, 14,
     '{"vacinas": "Aftosa e brucelose em dia", "vermifugacao": "Out/2026"}', 'Mococa', 'SP', 3, 2600, null,
     now(), now() + interval '1 hour', now() + interval '1 hour', 'agendado'),
    (v_tenant, v_leilao, v_vend, v_faz, 2, 2, '18 novilhas Nelore', 'novilhas', 'Nelore', 'femea', 18, 290, current_date - 4, 18, 20,
     '{"vacinas": "Em dia"}', 'Casa Branca', 'SP', 3, 2900, 3200,
     now(), now() + interval '3 hours', now() + interval '3 hours', 'agendado'),
    (v_tenant, v_leilao, v_vend, v_faz, 3, 3, '40 bezerros desmamados anelorados', 'bezerros', 'Anelorado', 'macho', 40, 195, current_date - 2, 7, 8,
     '{}', 'Tambaú', 'SP', 3, 2100, null,
     now(), now() + interval '24 hours', now() + interval '24 hours', 'agendado');
  raise notice 'Leilão de teste criado.';
end $$;

-- Conferência (rode de novo depois de alguns segundos: o status deve virar "aberto")
select numero, titulo, status, termina_em at time zone 'America/Sao_Paulo' as termina_em_brasilia
from public.lotes where titulo is not null and leilao_id in (select id from public.leiloes where titulo like '[TESTE]%')
order by numero;

-- ===================== LIMPAR (descomente e rode quando quiser apagar) =====================
-- delete from public.notificacoes where lote_id in (select id from public.lotes where leilao_id in (select id from public.leiloes where titulo like '[TESTE]%'));
-- delete from public.vendas where lote_id in (select id from public.lotes where leilao_id in (select id from public.leiloes where titulo like '[TESTE]%'));
-- delete from public.lotes where leilao_id in (select id from public.leiloes where titulo like '[TESTE]%');
-- delete from public.leiloes where titulo like '[TESTE]%';
-- delete from public.fazendas where nome like '[TESTE]%';
-- delete from public.usuarios where nome like '[TESTE]%';
