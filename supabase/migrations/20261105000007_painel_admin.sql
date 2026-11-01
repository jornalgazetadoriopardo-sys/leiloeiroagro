-- =====================================================================
-- Pregão do Campo — Fase 1 · Migração 7: painel da leiloeira (etapa 4)
-- Seção 11.2 do guia. Pode ser rodada mais de uma vez sem erro.
--
-- Lotes só mudam por funções do servidor: ninguém (nem a equipe) altera
-- lance atual, líder ou status direto na tabela.
-- =====================================================================

revoke insert, update, delete on public.lotes from anon, authenticated;

create or replace function app.erro(p_codigo text, p_mensagem text)
returns jsonb language sql immutable set search_path = '' as $$
  select jsonb_build_object('ok', false, 'codigo', p_codigo, 'mensagem', p_mensagem);
$$;

-- ---------------------------------------------------------------------
-- Vendedor cadastrado pela leiloeira (não precisa entrar no sistema na Fase 1)
-- p_dados: { nome, celular, cidade, uf, cpf_cnpj?, fazenda, exibir_nome? }
-- ---------------------------------------------------------------------
create or replace function public.criar_vendedor(p_tenant_id uuid, p_dados jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_nome     text := btrim(coalesce(p_dados ->> 'nome', ''));
  v_celular  text := '+55' || right(app.so_digitos(p_dados ->> 'celular'), 11);
  v_cidade   text := btrim(coalesce(p_dados ->> 'cidade', ''));
  v_uf       text := upper(btrim(coalesce(p_dados ->> 'uf', '')));
  v_doc      text := nullif(app.so_digitos(p_dados ->> 'cpf_cnpj'), '');
  v_fazenda  text := btrim(coalesce(p_dados ->> 'fazenda', ''));
  v_usuario  uuid;
begin
  if not app.e_equipe(p_tenant_id) then return app.erro('sem_permissao', 'Só a equipe da leiloeira.'); end if;
  if v_nome !~ '\S+\s+\S+' then return app.erro('nome', 'Informe nome e sobrenome do vendedor.'); end if;
  if length(v_celular) <> 14 then return app.erro('celular', 'Celular com DDD (11 números).'); end if;
  if length(v_cidade) < 2 or length(v_uf) <> 2 then return app.erro('cidade', 'Informe cidade e UF.'); end if;
  if v_doc is not null and not app.cpf_cnpj_valido(v_doc) then return app.erro('cpf_cnpj', 'CPF/CNPJ inválido.'); end if;
  if v_fazenda = '' then v_fazenda := 'Fazenda de ' || split_part(v_nome, ' ', 1); end if;

  select id into v_usuario from public.usuarios where tenant_id = p_tenant_id and celular = v_celular;
  if v_usuario is null then
    insert into public.usuarios (tenant_id, nome, celular, cidade, uf, cpf_cnpj, status_verificacao, cadastro_enviado_em)
    values (p_tenant_id, v_nome, v_celular, v_cidade, v_uf, v_doc, 'verificado', now())
    returning id into v_usuario;
  end if;
  insert into public.papeis_usuario (tenant_id, usuario_id, papel) values (p_tenant_id, v_usuario, 'vendedor')
  on conflict (usuario_id, papel) do nothing;
  insert into public.fazendas (tenant_id, vendedor_id, nome, cidade, uf, exibir_nome)
  select p_tenant_id, v_usuario, v_fazenda, v_cidade, v_uf, coalesce((p_dados ->> 'exibir_nome')::boolean, false)
  where not exists (select 1 from public.fazendas f where f.vendedor_id = v_usuario and f.nome = v_fazenda);

  return jsonb_build_object('ok', true, 'usuario_id', v_usuario);
end $$;

-- ---------------------------------------------------------------------
-- Criar / editar lote (seção 6.1). Só antes de abrir para lances.
-- ---------------------------------------------------------------------
create or replace function public.salvar_lote(p_tenant_id uuid, p_lote_id uuid, p_dados jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_lote     public.lotes%rowtype;
  v_vendedor uuid := nullif(p_dados ->> 'vendedor_id', '')::uuid;
  v_fazenda  uuid;
  v_cats     jsonb := app.config(p_tenant_id, 'lote.categorias');
  v_id       uuid;
  v_inicial  numeric := nullif(p_dados ->> 'preco_inicial', '')::numeric;
  v_reserva  numeric := nullif(p_dados ->> 'preco_reserva', '')::numeric;
  v_qtd      integer := nullif(p_dados ->> 'quantidade', '')::integer;
  v_peso     numeric := nullif(p_dados ->> 'peso_medio', '')::numeric;
  v_pesagem  date    := nullif(p_dados ->> 'data_pesagem', '')::date;
  v_imin     integer := nullif(p_dados ->> 'idade_min', '')::integer;
  v_imax     integer := nullif(p_dados ->> 'idade_max', '')::integer;
begin
  if not app.e_equipe(p_tenant_id) then return app.erro('sem_permissao', 'Só a equipe da leiloeira.'); end if;

  if p_lote_id is not null then
    select * into v_lote from public.lotes where id = p_lote_id and tenant_id = p_tenant_id for update;
    if not found then return app.erro('lote_nao_encontrado', 'Lote não encontrado.'); end if;
    if v_lote.status not in ('rascunho', 'em_vistoria', 'aprovado', 'agendado') then
      return app.erro('lote_bloqueado', 'Lote aberto ou encerrado não pode ser editado. Se preciso, cancele com motivo.');
    end if;
  end if;

  -- Validações (seção 6.1)
  if coalesce(btrim(p_dados ->> 'titulo'), '') = '' then return app.erro('titulo', 'Informe o título (ex.: 30 garrotes Nelore).'); end if;
  if not (v_cats ? (p_dados ->> 'categoria')) then return app.erro('categoria', 'Escolha a categoria.'); end if;
  if coalesce(btrim(p_dados ->> 'raca'), '') = '' then return app.erro('raca', 'Informe a raça ou cruzamento.'); end if;
  if coalesce(p_dados ->> 'sexo', '') not in ('macho', 'femea', 'misto') then return app.erro('sexo', 'Escolha o sexo.'); end if;
  if v_qtd is null or v_qtd <= 0 then return app.erro('quantidade', 'Informe a quantidade de cabeças.'); end if;
  if v_peso is null or v_peso <= 0 then return app.erro('peso_medio', 'Informe o peso médio.'); end if;
  if v_pesagem is null or v_pesagem > current_date then return app.erro('data_pesagem', 'Informe a data da pesagem.'); end if;
  if v_imin is not null and v_imax is not null and v_imax < v_imin then return app.erro('idade_max', 'Idade máxima menor que a mínima.'); end if;
  if coalesce(btrim(p_dados ->> 'cidade'), '') = '' or length(btrim(coalesce(p_dados ->> 'uf', ''))) <> 2 then
    return app.erro('cidade', 'Informe cidade e UF de origem.');
  end if;
  if v_inicial is null or v_inicial <= 0 then return app.erro('preco_inicial', 'Informe o preço inicial por cabeça.'); end if;
  if v_reserva is not null and v_reserva < v_inicial then return app.erro('preco_reserva', 'A reserva não pode ser menor que o preço inicial.'); end if;
  if v_vendedor is null or not exists (
    select 1 from public.papeis_usuario p where p.usuario_id = v_vendedor and p.tenant_id = p_tenant_id and p.papel = 'vendedor'
  ) then
    return app.erro('vendedor_id', 'Escolha o vendedor.');
  end if;
  select f.id into v_fazenda from public.fazendas f where f.vendedor_id = v_vendedor order by f.criado_em limit 1;

  if p_lote_id is null then
    insert into public.lotes (tenant_id, vendedor_id, fazenda_id, titulo, categoria, raca, sexo, quantidade, peso_medio,
      data_pesagem, idade_min, idade_max, sanidade, cidade, uf, retirada_prazo, frete, tolerancia_quebra,
      preco_inicial, preco_reserva, incremento, status)
    values (p_tenant_id, v_vendedor, v_fazenda, btrim(p_dados ->> 'titulo'), p_dados ->> 'categoria', btrim(p_dados ->> 'raca'),
      p_dados ->> 'sexo', v_qtd, v_peso, v_pesagem, v_imin, v_imax, coalesce(p_dados -> 'sanidade', '{}'),
      btrim(p_dados ->> 'cidade'), upper(btrim(p_dados ->> 'uf')),
      coalesce(nullif(p_dados ->> 'retirada_prazo', '')::integer, app.config_num(p_tenant_id, 'lote.retirada_prazo_dias')::integer),
      coalesce(nullif(p_dados ->> 'frete', ''), 'comprador'),
      coalesce(nullif(p_dados ->> 'tolerancia_quebra', '')::numeric, app.config_num(p_tenant_id, 'lote.tolerancia_quebra_pct')),
      v_inicial, v_reserva, nullif(p_dados ->> 'incremento', '')::numeric, 'rascunho')
    returning id into v_id;
  else
    update public.lotes set
      vendedor_id = v_vendedor, fazenda_id = v_fazenda, titulo = btrim(p_dados ->> 'titulo'),
      categoria = p_dados ->> 'categoria', raca = btrim(p_dados ->> 'raca'), sexo = p_dados ->> 'sexo',
      quantidade = v_qtd, peso_medio = v_peso, data_pesagem = v_pesagem, idade_min = v_imin, idade_max = v_imax,
      sanidade = coalesce(p_dados -> 'sanidade', '{}'), cidade = btrim(p_dados ->> 'cidade'), uf = upper(btrim(p_dados ->> 'uf')),
      retirada_prazo = coalesce(nullif(p_dados ->> 'retirada_prazo', '')::integer, retirada_prazo),
      frete = coalesce(nullif(p_dados ->> 'frete', ''), frete),
      tolerancia_quebra = nullif(p_dados ->> 'tolerancia_quebra', '')::numeric,
      preco_inicial = v_inicial, preco_reserva = v_reserva, incremento = nullif(p_dados ->> 'incremento', '')::numeric
    where id = p_lote_id
    returning id into v_id;
  end if;
  return jsonb_build_object('ok', true, 'lote_id', v_id);
end $$;

-- O que falta para o lote ficar pronto (tela "Lotes em preparação")
create or replace function public.pendencias_lote(p_lote_id uuid)
returns text[] language sql stable security definer set search_path = '' as $$
  select array_remove(array[
    case when not exists (select 1 from public.midias_lote m where m.lote_id = l.id and m.tipo = 'video') then 'video' end,
    case when (select count(*) from public.midias_lote m where m.lote_id = l.id and m.tipo = 'foto') < 3 then 'fotos' end,
    case when not exists (select 1 from public.midias_lote m where m.lote_id = l.id and m.tipo = 'laudo') then 'laudo' end,
    case when l.data_pesagem < current_date - app.config_num(l.tenant_id, 'lote.pesagem_prazo_max_dias')::integer then 'pesagem_antiga' end
  ], null)
  from public.lotes l where l.id = p_lote_id;
$$;

-- Aprovar o lote para entrar num leilão (exige vídeo, 3 fotos, laudo e pesagem recente)
create or replace function public.aprovar_lote(p_lote_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_lote public.lotes%rowtype;
  v_pend text[];
begin
  select * into v_lote from public.lotes where id = p_lote_id for update;
  if not found then return app.erro('lote_nao_encontrado', 'Lote não encontrado.'); end if;
  if not app.e_equipe(v_lote.tenant_id) then return app.erro('sem_permissao', 'Só a equipe da leiloeira.'); end if;
  if v_lote.status not in ('rascunho', 'em_vistoria') then return app.erro('status', 'Este lote já foi aprovado.'); end if;
  v_pend := public.pendencias_lote(p_lote_id);
  if cardinality(v_pend) > 0 then
    return app.erro('pendencias', 'Faltam itens para aprovar o lote.') || jsonb_build_object('pendencias', to_jsonb(v_pend));
  end if;
  update public.lotes set status = 'aprovado' where id = p_lote_id;
  return jsonb_build_object('ok', true);
end $$;

-- Incluir/retirar lote de um leilão (só antes de abrir)
create or replace function public.definir_leilao_do_lote(p_lote_id uuid, p_leilao_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_lote   public.lotes%rowtype;
  v_leilao public.leiloes%rowtype;
begin
  select * into v_lote from public.lotes where id = p_lote_id for update;
  if not found then return app.erro('lote_nao_encontrado', 'Lote não encontrado.'); end if;
  if not app.e_equipe(v_lote.tenant_id) then return app.erro('sem_permissao', 'Só a equipe da leiloeira.'); end if;
  if v_lote.status not in ('aprovado', 'agendado') then
    return app.erro('status', 'Só lotes aprovados (e ainda não abertos) entram ou saem de um leilão.');
  end if;
  if p_leilao_id is not null then
    select * into v_leilao from public.leiloes where id = p_leilao_id and tenant_id = v_lote.tenant_id;
    if not found or v_leilao.status not in ('rascunho', 'agendado') then
      return app.erro('leilao', 'Leilão não encontrado ou já aberto.');
    end if;
  end if;
  update public.lotes set
    leilao_id = p_leilao_id,
    ordem = case when p_leilao_id is null then null
                 else coalesce((select max(l.ordem) from public.lotes l where l.leilao_id = p_leilao_id), 0) + 1 end,
    status = 'aprovado', abre_em = null, termina_em = null, termina_em_original = null
  where id = p_lote_id;
  return jsonb_build_object('ok', true);
end $$;

-- Cancelar lote com motivo (qualquer estado até "aberto") — seções 6.2 e 11.2
create or replace function public.cancelar_lote(p_lote_id uuid, p_motivo text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_lote public.lotes%rowtype;
  v_u    uuid;
begin
  select * into v_lote from public.lotes where id = p_lote_id for update;
  if not found then return app.erro('lote_nao_encontrado', 'Lote não encontrado.'); end if;
  if not app.e_admin(v_lote.tenant_id) then return app.erro('sem_permissao', 'Só o admin cancela lotes.'); end if;
  if v_lote.status not in ('rascunho', 'em_vistoria', 'aprovado', 'agendado', 'aberto') then
    return app.erro('status', 'Lote já encerrado não pode ser cancelado aqui.');
  end if;
  if coalesce(btrim(p_motivo), '') = '' then return app.erro('motivo', 'Informe o motivo do cancelamento.'); end if;

  update public.lotes set status = 'cancelado', motivo_cancelamento = btrim(p_motivo) where id = p_lote_id;
  update public.tetos set ativo = false where lote_id = p_lote_id and ativo;
  update public.avisos_lote set status = 'cancelado' where lote_id = p_lote_id and status = 'pendente';
  for v_u in select distinct x.usuario_id from public.lances x where x.lote_id = p_lote_id loop
    perform app.notificar(v_lote.tenant_id, v_u, p_lote_id, 'lote_cancelado',
      jsonb_build_object('numero', v_lote.numero, 'titulo', v_lote.titulo, 'motivo', btrim(p_motivo)),
      'lote_cancelado:' || p_lote_id || ':' || v_u);
  end loop;
  perform app.publicar_lote(p_lote_id);
  return jsonb_build_object('ok', true);
end $$;

-- Pagamento confirmado manualmente (piloto: PIX/transferência fora do sistema — seção 9.1)
create or replace function public.confirmar_pagamento(p_venda_id uuid, p_observacao text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_venda public.vendas%rowtype;
  v_valor numeric;
begin
  select * into v_venda from public.vendas where id = p_venda_id for update;
  if not found then return app.erro('venda_nao_encontrada', 'Venda não encontrada.'); end if;
  if not app.e_admin(v_venda.tenant_id) then return app.erro('sem_permissao', 'Só o admin confirma pagamentos.'); end if;
  if v_venda.status not in ('aguardando_pagamento', 'em_atraso') then return app.erro('status', 'Esta venda já foi paga ou cancelada.'); end if;

  v_valor := v_venda.total + v_venda.comissao_comprador;
  insert into public.pagamentos (tenant_id, venda_id, provedor, valor, status, pago_em, confirmado_por, id_externo)
  values (v_venda.tenant_id, p_venda_id, 'manual', v_valor, 'pago', now(), app.usuario_atual(v_venda.tenant_id), nullif(btrim(p_observacao), ''));
  update public.vendas set status = 'pago' where id = p_venda_id;
  update public.lotes set status = 'pago_em_garantia' where id = v_venda.lote_id and status = 'aguardando_pagamento';

  perform app.notificar(v_venda.tenant_id, v_venda.comprador_id, v_venda.lote_id, 'pagamento_confirmado',
    jsonb_build_object('valor', v_valor), 'pagamento_confirmado:comprador:' || p_venda_id);
  perform app.notificar(v_venda.tenant_id, v_venda.vendedor_id, v_venda.lote_id, 'pagamento_confirmado',
    jsonb_build_object('valor', v_venda.total), 'pagamento_confirmado:vendedor:' || p_venda_id);
  return jsonb_build_object('ok', true);
end $$;

-- Resumo do painel (contadores da tela inicial do admin)
create or replace function public.resumo_painel(p_tenant_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select case when not app.e_equipe(p_tenant_id) then null else jsonb_build_object(
    'cadastros_pendentes', (select count(*) from public.usuarios u where u.tenant_id = p_tenant_id
                              and u.status_verificacao = 'pendente' and u.cadastro_enviado_em is not null),
    'lotes_preparacao', (select count(*) from public.lotes l where l.tenant_id = p_tenant_id and l.status in ('rascunho', 'em_vistoria')),
    'lotes_aprovados', (select count(*) from public.lotes l where l.tenant_id = p_tenant_id and l.status = 'aprovado'),
    'lotes_abertos', (select count(*) from public.lotes l where l.tenant_id = p_tenant_id and l.status = 'aberto'),
    'vendas_aguardando', (select count(*) from public.vendas v where v.tenant_id = p_tenant_id and v.status in ('aguardando_pagamento', 'em_atraso'))
  ) end;
$$;

revoke execute on function public.criar_vendedor(uuid, jsonb), public.salvar_lote(uuid, uuid, jsonb),
  public.pendencias_lote(uuid), public.aprovar_lote(uuid), public.definir_leilao_do_lote(uuid, uuid),
  public.cancelar_lote(uuid, text), public.confirmar_pagamento(uuid, text), public.resumo_painel(uuid)
  from public, anon;
grant execute on function public.criar_vendedor(uuid, jsonb), public.salvar_lote(uuid, uuid, jsonb),
  public.pendencias_lote(uuid), public.aprovar_lote(uuid), public.definir_leilao_do_lote(uuid, uuid),
  public.cancelar_lote(uuid, text), public.confirmar_pagamento(uuid, text), public.resumo_painel(uuid)
  to authenticated;
grant execute on function app.erro(text, text) to authenticated, service_role;
