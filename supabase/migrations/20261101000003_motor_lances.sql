-- =====================================================================
-- Pregão do Campo — Fase 1 · Migração 3: motor de lances
-- Seção 7 do guia. Toda validação acontece aqui, com o horário do servidor.
-- O cronômetro do navegador é só visual.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Auxiliares
-- ---------------------------------------------------------------------

-- Formata em reais: 2930 -> "R$ 2.930"; 2930.5 -> "R$ 2.930,50"
create or replace function app.brl(p numeric)
returns text language sql immutable set search_path = '' as $$
  select 'R$ ' || replace(to_char(trunc(p), 'FM999,999,999,990'), ',', '.')
         || case when p <> trunc(p) then ',' || lpad(((abs(p) - trunc(abs(p))) * 100)::int::text, 2, '0') else '' end;
$$;

-- Recusa de negócio: vira {ok:false, codigo, mensagem, ...} em place_bid
create or replace function app.recusar(p_codigo text, p_mensagem text, p_extra jsonb default '{}')
returns void language plpgsql set search_path = '' as $$
begin
  raise exception using errcode = 'PB001', message = p_codigo, detail = p_mensagem, hint = p_extra::text;
end $$;

create or replace function app.notificar(
  p_tenant uuid, p_usuario uuid, p_lote uuid, p_tipo text, p_dados jsonb, p_chave_dedup text default null)
returns void language sql security definer set search_path = '' as $$
  insert into public.notificacoes (tenant_id, usuario_id, lote_id, tipo, dados, chave_dedup)
  values (p_tenant, p_usuario, p_lote, p_tipo, coalesce(p_dados, '{}'), p_chave_dedup)
  on conflict (chave_dedup) do nothing;
$$;

create or replace function app.incremento(p_lote public.lotes)
returns numeric language sql stable set search_path = '' as $$
  select coalesce(p_lote.incremento, app.config_num(p_lote.tenant_id, 'lance.incremento_minimo'));
$$;

-- Valor comprometido do comprador: lotes abertos em que lidera + compras não pagas
create or replace function app.exposicao_credito(p_usuario uuid, p_excluir_lote uuid)
returns numeric language sql stable security definer set search_path = '' as $$
  select
    coalesce((select sum(l.lance_atual * l.quantidade) from public.lotes l
              where l.lider_id = p_usuario and l.id <> p_excluir_lote
                and (l.status = 'aberto'
                     or (l.status = 'nao_vendido' and l.consulta_vendedor_status = 'pendente'))), 0)
  + coalesce((select sum(v.total) from public.vendas v
              where v.comprador_id = p_usuario and v.status in ('aguardando_pagamento', 'em_atraso')), 0);
$$;

-- Estado público do lote (vai no canal realtime e na resposta do lance)
create or replace function app.estado_publico(p_lote_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'lote_id', l.id,
    'status', case when l.status in ('agendado', 'aberto') then l.status::text else 'encerrado' end,
    'lance_atual', l.lance_atual,
    'total', coalesce(l.lance_atual, 0) * l.quantidade,
    'lance_minimo', case when l.lance_atual is null then l.preco_inicial else l.lance_atual + app.incremento(l) end,
    'qtd_lances', l.qtd_lances,
    'termina_em', l.termina_em,
    'prorrogado', l.prorrogado,
    'lider_codigo', u.codigo_publico,
    'servidor_agora', clock_timestamp()
  )
  from public.lotes l
  left join public.usuarios u on u.id = l.lider_id
  where l.id = p_lote_id;
$$;

-- Publica no canal "lote:<id>" (Supabase Realtime Broadcast). Sem efeito
-- fora do Supabase (ex.: Postgres local dos testes).
create or replace function app.publicar_lote(p_lote_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if to_regprocedure('realtime.send(jsonb,text,text,boolean)') is not null then
    execute 'select realtime.send($1, $2, $3, false)'
      using app.estado_publico(p_lote_id), 'estado', 'lote:' || p_lote_id::text;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Avisos de "dou-lhe" (seção 10.4)
--   Na abertura: agenda termina_em − 10, − 5 e − 3 min.
--   Na prorrogação: reagenda os pendentes; se o dou-lhe 3 já saiu, cria
--   no máximo N avisos de prorrogação (aviso.max_avisos_prorrogacao).
-- ---------------------------------------------------------------------
create or replace function app.agendar_avisos(p_lote_id uuid, p_prorrogacao boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_lote      public.lotes%rowtype;
  v_agora     timestamptz := clock_timestamp();
  v_tipo      text;
  v_minutos   numeric;
  v_quando    timestamptz;
  v_max       integer;
  v_qtd       integer;
begin
  select * into v_lote from public.lotes where id = p_lote_id;
  if not found or v_lote.termina_em is null then return; end if;

  for v_tipo, v_minutos in
    select key, value::text::numeric from jsonb_each(app.config(v_lote.tenant_id, 'aviso.doulhe_minutos'))
  loop
    v_quando := v_lote.termina_em - make_interval(secs => v_minutos * 60);
    if v_quando < v_agora then
      -- Momento já passou: só o dou-lhe 3 ainda pendente sai na hora (prorrogação)
      continue when not (p_prorrogacao and v_tipo = 'doulhe_3');
      v_quando := v_agora;
    end if;
    insert into public.avisos_lote (tenant_id, lote_id, tipo, agendado_para)
    values (v_lote.tenant_id, v_lote.id, v_tipo, v_quando)
    on conflict (lote_id, tipo) do update
      set agendado_para = excluded.agendado_para
      where public.avisos_lote.status = 'pendente';
  end loop;

  if p_prorrogacao and exists (
    select 1 from public.avisos_lote a
    where a.lote_id = p_lote_id and a.tipo = 'doulhe_3' and a.status = 'enviado'
  ) then
    v_max := app.config_num(v_lote.tenant_id, 'aviso.max_avisos_prorrogacao')::integer;
    select count(*) into v_qtd from public.avisos_lote a
      where a.lote_id = p_lote_id and a.tipo like 'prorrogacao\_%';
    if v_qtd < v_max then
      insert into public.avisos_lote (tenant_id, lote_id, tipo, agendado_para)
      values (v_lote.tenant_id, v_lote.id, 'prorrogacao_' || (v_qtd + 1), v_agora)
      on conflict (lote_id, tipo) do nothing;
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- place_bid — função única e transacional (seção 7.5)
--
--   p_tipo = 'manual': lance de p_valor por cabeça.
--   p_tipo = 'teto'  : registra/aumenta o teto secreto (seção 7.3). Se o
--                      usuário não lidera, dá automaticamente o lance mínimo.
--   p_em_nome_de     : titular, quando quem clica é uma pessoa delegada.
--
-- Retorna jsonb: {ok:true, ...estado} ou {ok:false, codigo, mensagem}.
-- ---------------------------------------------------------------------
create or replace function public.place_bid(
  p_lote_id uuid,
  p_valor numeric,
  p_tipo text default 'manual',
  p_chave_idempotencia text default null,
  p_em_nome_de uuid default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_lote           public.lotes%rowtype;
  v_agora          timestamptz;
  v_ator           public.usuarios%rowtype;
  v_titular        public.usuarios%rowtype;
  v_delegado_id    uuid;
  v_inc            numeric;
  v_janela         interval;
  v_intervalo_ms   numeric;
  v_minimo         numeric;
  v_res            jsonb;
  v_lider_inicial  uuid;
  v_lider          uuid;
  v_lider_desde    timestamptz;
  v_preco          numeric;
  v_novos          integer := 0;
  v_teto_atual     numeric;
  v_lt             public.tetos%rowtype;
  v_tem_lt         boolean;
  v_c              public.tetos%rowtype;
  v_lcap           numeric;
  v_ltime          timestamptz;
  v_novo           numeric;
  v_guarda         integer := 0;
  v_exposto        numeric;
  v_prorrogou      boolean := false;
  v_esgotados      uuid[] := '{}';
  v_u              uuid;
  v_codigo         text;
  v_msg            text;
  v_extra          text;
begin
  begin
    if p_tipo is null or p_tipo not in ('manual', 'teto') then
      perform app.recusar('tipo_invalido', 'Tipo de lance inválido.');
    end if;
    if p_valor is null or p_valor <= 0 then
      perform app.recusar('valor_invalido', 'Informe um valor por cabeça válido.');
    end if;
    p_valor := round(p_valor, 2);

    -- Trava a linha do lote: lances do mesmo lote são processados em fila
    select * into v_lote from public.lotes where id = p_lote_id for update;
    if not found then
      perform app.recusar('lote_nao_encontrado', 'Lote não encontrado.');
    end if;
    v_agora := clock_timestamp();

    -- Idempotência: a mesma chave devolve o mesmo resultado, sem novo lance
    if p_chave_idempotencia is not null then
      select r.resultado into v_res from public.requisicoes_lance r
        where r.lote_id = p_lote_id and r.chave_idempotencia = p_chave_idempotencia;
      if found then
        return v_res || jsonb_build_object('repetido', true);
      end if;
    end if;

    -- Quem está dando o lance
    if auth.uid() is null then
      perform app.recusar('nao_autenticado', 'Entre na sua conta para dar lance.');
    end if;
    select * into v_ator from public.usuarios
      where auth_user_id = auth.uid() and tenant_id = v_lote.tenant_id;
    if not found then
      perform app.recusar('sem_cadastro', 'Faça seu cadastro para dar lance.');
    end if;

    if p_em_nome_de is null or p_em_nome_de = v_ator.id then
      v_titular := v_ator;
    else
      if not exists (
        select 1 from public.acessos_delegados d
        where d.titular_id = p_em_nome_de and d.delegado_id = v_ator.id and d.ativo
          and coalesce((d.permissoes ->> 'dar_lance')::boolean, false)
      ) then
        perform app.recusar('sem_delegacao', 'Você não tem autorização para dar lance por este cadastro.');
      end if;
      if v_ator.status_verificacao in ('suspenso', 'recusado') then
        perform app.recusar('cadastro_' || v_ator.status_verificacao, 'Seu cadastro não está liberado para lances.');
      end if;
      select * into v_titular from public.usuarios
        where id = p_em_nome_de and tenant_id = v_lote.tenant_id;
      v_delegado_id := v_ator.id;
    end if;

    if v_titular.status_verificacao <> 'verificado' then
      perform app.recusar('cadastro_' || v_titular.status_verificacao,
        case v_titular.status_verificacao
          when 'pendente'   then 'Seu cadastro ainda está em análise. Você poderá dar lances assim que for aprovado.'
          when 'divergente' then 'Seu cadastro precisa de um ajuste antes de liberar os lances.'
          when 'suspenso'   then 'Seu cadastro está suspenso. Fale com a leiloeira.'
          else 'Seu cadastro não foi aprovado para dar lances.'
        end);
    end if;

    if v_lote.vendedor_id in (v_titular.id, v_ator.id) then
      perform app.recusar('vendedor_do_lote', 'Você não pode dar lance no próprio lote.');
    end if;

    -- Prazo, sempre pelo relógio do servidor
    if v_lote.status = 'agendado' or (v_lote.status = 'aberto' and v_lote.abre_em is not null and v_agora < v_lote.abre_em) then
      perform app.recusar('lote_nao_aberto', 'Este lote ainda não abriu para lances.');
    end if;
    if v_lote.status <> 'aberto' or v_lote.termina_em is null or v_agora >= v_lote.termina_em then
      perform app.recusar('lote_encerrado', 'O prazo deste lote terminou.');
    end if;

    -- Frequência máxima por usuário e lote
    v_intervalo_ms := app.config_num(v_lote.tenant_id, 'lance.intervalo_minimo_ms');
    if v_intervalo_ms > 0 and exists (
      select 1 from public.requisicoes_lance r
      where r.lote_id = p_lote_id and r.usuario_id = v_titular.id
        and r.criado_em > v_agora - make_interval(secs => v_intervalo_ms / 1000.0)
    ) then
      perform app.recusar('muitos_lances', 'Aguarde um instante antes de dar outro lance.');
    end if;

    v_inc    := app.incremento(v_lote);
    v_janela := make_interval(secs => app.config_num(v_lote.tenant_id, 'lance.janela_prorrogacao_seg'));
    v_minimo := case when v_lote.lance_atual is null then v_lote.preco_inicial
                     else v_lote.lance_atual + v_inc end;

    v_lider_inicial := v_lote.lider_id;
    v_lider := v_lote.lider_id;
    v_preco := v_lote.lance_atual;
    select x.criado_em into v_lider_desde from public.lances x
      where x.lote_id = p_lote_id and x.usuario_id = v_lider order by x.seq desc limit 1;

    -- Limite de crédito (seção 5.3). Para teto, conta o valor máximo.
    if v_titular.limite_credito is not null then
      v_exposto := app.exposicao_credito(v_titular.id, v_lote.id);
      if v_exposto + p_valor * v_lote.quantidade > v_titular.limite_credito then
        perform app.recusar('limite_credito',
          format('Este lance passa do seu limite de compra de %s. Peça um aumento à leiloeira.', app.brl(v_titular.limite_credito)),
          jsonb_build_object('limite', v_titular.limite_credito,
                             'disponivel', greatest(v_titular.limite_credito - v_exposto, 0)));
      end if;
    end if;

    if p_tipo = 'manual' then
      if p_valor < v_minimo then
        perform app.recusar('abaixo_minimo',
          format('O lance mínimo agora é %s por cabeça.', app.brl(v_minimo)),
          jsonb_build_object('minimo', v_minimo));
      end if;
      insert into public.lances (tenant_id, lote_id, usuario_id, delegado_id, valor_por_cabeca, tipo, chave_idempotencia)
      values (v_lote.tenant_id, p_lote_id, v_titular.id, v_delegado_id, p_valor, 'manual', p_chave_idempotencia)
      returning criado_em into v_lider_desde;
      v_novos := v_novos + 1;
      v_lider := v_titular.id;
      v_preco := p_valor;

    else -- teto
      select t.valor_maximo into v_teto_atual from public.tetos t
        where t.lote_id = p_lote_id and t.usuario_id = v_titular.id and t.ativo;
      if v_lider = v_titular.id then
        if p_valor <= greatest(coalesce(v_teto_atual, 0), v_preco) then
          perform app.recusar('teto_invalido',
            format('O novo teto precisa ser maior que %s por cabeça.', app.brl(greatest(coalesce(v_teto_atual, 0), v_preco))));
        end if;
      elsif p_valor < v_minimo then
        perform app.recusar('abaixo_minimo',
          format('O teto precisa ser de pelo menos %s por cabeça.', app.brl(v_minimo)),
          jsonb_build_object('minimo', v_minimo));
      end if;

      insert into public.tetos (tenant_id, lote_id, usuario_id, delegado_id, valor_maximo, ativo, registrado_em)
      values (v_lote.tenant_id, p_lote_id, v_titular.id, v_delegado_id, p_valor, true, clock_timestamp())
      on conflict (lote_id, usuario_id) do update
        set valor_maximo = excluded.valor_maximo, ativo = true,
            delegado_id = excluded.delegado_id, registrado_em = excluded.registrado_em;

      if v_lider is distinct from v_titular.id then
        insert into public.lances (tenant_id, lote_id, usuario_id, delegado_id, valor_por_cabeca, tipo, chave_idempotencia)
        values (v_lote.tenant_id, p_lote_id, v_titular.id, v_delegado_id, v_minimo, 'automatico', p_chave_idempotencia)
        returning criado_em into v_lider_desde;
        v_novos := v_novos + 1;
        v_lider := v_titular.id;
        v_preco := v_minimo;
      end if;
    end if;

    -- -----------------------------------------------------------------
    -- Resolver tetos concorrentes (seção 7.3)
    -- O maior teto vence com (segundo maior + incremento), limitado ao
    -- próprio teto. Empate de teto: vence quem registrou primeiro.
    -- -----------------------------------------------------------------
    loop
      v_guarda := v_guarda + 1;
      exit when v_guarda > 1000;

      select * into v_lt from public.tetos t
        where t.lote_id = p_lote_id and t.usuario_id = v_lider and t.ativo;
      v_tem_lt := found;
      if v_tem_lt and v_lt.valor_maximo >= v_preco then
        v_lcap  := v_lt.valor_maximo;
        v_ltime := v_lt.registrado_em;
      else
        v_lcap  := v_preco;
        v_ltime := v_lider_desde;
      end if;

      -- Desafiante: maior teto de outro usuário capaz de cobrir o líder
      select * into v_c from public.tetos t
        where t.lote_id = p_lote_id and t.ativo and t.usuario_id <> v_lider
          and (t.valor_maximo >= v_preco + v_inc
               -- teto igual ao lance atual, registrado antes dele: vence o primeiro
               or (t.valor_maximo = v_preco and v_lcap = v_preco and t.registrado_em < v_ltime))
        order by t.valor_maximo desc, t.registrado_em asc
        limit 1;
      exit when not found;

      if v_c.valor_maximo > v_lcap or (v_c.valor_maximo = v_lcap and v_c.registrado_em < v_ltime) then
        -- O desafiante assume a liderança
        v_novo := least(v_c.valor_maximo, v_lcap + v_inc);
        if v_lcap > v_preco and v_lcap < v_novo then
          insert into public.lances (tenant_id, lote_id, usuario_id, delegado_id, valor_por_cabeca, tipo)
          values (v_lote.tenant_id, p_lote_id, v_lider, v_lt.delegado_id, v_lcap, 'automatico');
          v_novos := v_novos + 1;
        end if;
        if v_tem_lt then
          update public.tetos set ativo = false where id = v_lt.id;
          v_esgotados := v_esgotados || v_lider;
        end if;
        insert into public.lances (tenant_id, lote_id, usuario_id, delegado_id, valor_por_cabeca, tipo)
        values (v_lote.tenant_id, p_lote_id, v_c.usuario_id, v_c.delegado_id, v_novo, 'automatico')
        returning criado_em into v_lider_desde;
        v_novos := v_novos + 1;
        v_lider := v_c.usuario_id;
        v_preco := v_novo;
      else
        -- O líder se defende com o próprio teto
        v_novo := least(v_lcap, v_c.valor_maximo + v_inc);
        if v_c.valor_maximo < v_novo then
          insert into public.lances (tenant_id, lote_id, usuario_id, delegado_id, valor_por_cabeca, tipo)
          values (v_lote.tenant_id, p_lote_id, v_c.usuario_id, v_c.delegado_id, v_c.valor_maximo, 'automatico');
          v_novos := v_novos + 1;
        end if;
        update public.tetos set ativo = false where id = v_c.id;
        v_esgotados := v_esgotados || v_c.usuario_id;
        insert into public.lances (tenant_id, lote_id, usuario_id, delegado_id, valor_por_cabeca, tipo)
        values (v_lote.tenant_id, p_lote_id, v_lider, v_lt.delegado_id, v_novo, 'automatico')
        returning criado_em into v_lider_desde;
        v_novos := v_novos + 1;
        v_preco := v_novo;
      end if;
    end loop;

    -- Tetos de quem não lidera e já não alcançam o próximo lance: esgotados
    with esgotados as (
      update public.tetos t set ativo = false
      where t.lote_id = p_lote_id and t.ativo and t.usuario_id <> v_lider
        and t.valor_maximo < v_preco + v_inc
      returning t.usuario_id
    )
    select v_esgotados || coalesce(array_agg(usuario_id), '{}') into v_esgotados from esgotados;

    -- Atualiza o lote
    update public.lotes
      set lance_atual = v_preco, lider_id = v_lider, qtd_lances = qtd_lances + v_novos
      where id = p_lote_id;

    -- Prorrogação: lance com menos de N min restantes leva o fim para agora + N
    if v_novos > 0 and v_lote.termina_em - v_agora < v_janela then
      update public.lotes
        set termina_em = v_agora + v_janela, prorrogado = true, qtd_prorrogacoes = qtd_prorrogacoes + 1
        where id = p_lote_id;
      perform app.agendar_avisos(p_lote_id, true);
      v_prorrogou := true;
    end if;

    select * into v_lote from public.lotes where id = p_lote_id;

    -- Avisos: líder anterior coberto; donos de teto esgotado
    for v_u in select distinct unnest(v_esgotados || v_lider_inicial) loop
      continue when v_u is null or v_u = v_lider or v_u = v_titular.id;
      perform app.notificar(v_lote.tenant_id, v_u, p_lote_id,
        case when v_u = any (v_esgotados) then 'teto_atingido' else 'lance_coberto' end,
        jsonb_build_object('lance_atual', v_preco, 'termina_em', v_lote.termina_em, 'numero', v_lote.numero, 'titulo', v_lote.titulo));
    end loop;

    v_res := app.estado_publico(p_lote_id) || jsonb_build_object(
      'ok', true,
      'voce_lidera', v_lider = v_titular.id,
      'prorrogou_agora', v_prorrogou,
      'teto', (select t.valor_maximo from public.tetos t
               where t.lote_id = p_lote_id and t.usuario_id = v_titular.id and t.ativo),
      'mensagem', case
        when v_lider = v_titular.id then 'Lance registrado. Você está liderando.'
        else 'Outro comprador tem um lance automático maior. Seu lance foi coberto.'
      end
    );

    insert into public.requisicoes_lance (tenant_id, lote_id, usuario_id, chave_idempotencia, resultado)
    values (v_lote.tenant_id, p_lote_id, v_titular.id, p_chave_idempotencia, v_res);

    perform app.publicar_lote(p_lote_id);
    return v_res;

  exception when sqlstate 'PB001' then
    get stacked diagnostics v_codigo = message_text, v_msg = pg_exception_detail, v_extra = pg_exception_hint;
    v_res := jsonb_build_object('ok', false, 'codigo', v_codigo, 'mensagem', v_msg)
             || coalesce(nullif(v_extra, '')::jsonb, '{}');
    if v_lote.id is not null then
      perform app.registrar_evento(v_lote.tenant_id, 'lance_recusado', 'lotes', v_lote.id,
        v_res || jsonb_build_object('valor', p_valor, 'tipo', p_tipo, 'usuario_id', v_titular.id));
    end if;
    return v_res;
  end;
end $$;

-- Cancelar o teto (só enquanto não for o líder) — seção 7.3
create or replace function public.cancelar_teto(p_lote_id uuid, p_em_nome_de uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_lote    public.lotes%rowtype;
  v_usuario uuid;
begin
  select * into v_lote from public.lotes where id = p_lote_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'lote_nao_encontrado', 'mensagem', 'Lote não encontrado.');
  end if;
  v_usuario := app.usuario_atual(v_lote.tenant_id);
  if p_em_nome_de is not null and p_em_nome_de <> v_usuario then
    if not exists (select 1 from public.acessos_delegados d
                   where d.titular_id = p_em_nome_de and d.delegado_id = v_usuario and d.ativo) then
      return jsonb_build_object('ok', false, 'codigo', 'sem_delegacao', 'mensagem', 'Sem autorização.');
    end if;
    v_usuario := p_em_nome_de;
  end if;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sem_cadastro', 'mensagem', 'Faça seu cadastro.');
  end if;
  if v_lote.lider_id = v_usuario and v_lote.status = 'aberto' then
    return jsonb_build_object('ok', false, 'codigo', 'lider_nao_cancela',
      'mensagem', 'Você está liderando: o lance automático não pode ser cancelado agora.');
  end if;
  update public.tetos set ativo = false where lote_id = p_lote_id and usuario_id = v_usuario and ativo;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- Venda (criada no encerramento ou quando o vendedor aceita o maior lance)
-- ---------------------------------------------------------------------
create or replace function app.criar_venda(p_lote_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_lote   public.lotes%rowtype;
  v_total  numeric;
  v_id     uuid;
begin
  select * into v_lote from public.lotes where id = p_lote_id;
  v_total := v_lote.lance_atual * v_lote.quantidade;

  insert into public.vendas (tenant_id, lote_id, comprador_id, vendedor_id, valor_por_cabeca, quantidade, total,
                             comissao_comprador, comissao_vendedor, pagamento_ate)
  values (v_lote.tenant_id, v_lote.id, v_lote.lider_id, v_lote.vendedor_id, v_lote.lance_atual, v_lote.quantidade, v_total,
          round(v_total * app.config_num(v_lote.tenant_id, 'comissao.comprador_pct') / 100, 2),
          round(v_total * app.config_num(v_lote.tenant_id, 'comissao.vendedor_pct') / 100, 2),
          now() + make_interval(secs => app.config_num(v_lote.tenant_id, 'pagamento.prazo_horas') * 3600))
  on conflict (lote_id) do nothing
  returning id into v_id;

  if v_id is null then  -- já existia: encerramento repetido
    select id into v_id from public.vendas where lote_id = p_lote_id;
    return v_id;
  end if;

  update public.lotes set status = 'vendido' where id = p_lote_id;
  update public.lotes set status = 'aguardando_pagamento' where id = p_lote_id;

  perform app.notificar(v_lote.tenant_id, v_lote.lider_id, v_lote.id, 'arremate',
    jsonb_build_object('numero', v_lote.numero, 'titulo', v_lote.titulo,
                       'valor_por_cabeca', v_lote.lance_atual, 'total', v_total),
    'arremate:' || v_lote.id);
  perform app.notificar(v_lote.tenant_id, v_lote.vendedor_id, v_lote.id, 'lote_vendido',
    jsonb_build_object('numero', v_lote.numero, 'titulo', v_lote.titulo,
                       'valor_por_cabeca', v_lote.lance_atual, 'total', v_total),
    'lote_vendido:' || v_lote.id);
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- Encerramento do lote (seção 7.6) — idempotente
-- ---------------------------------------------------------------------
create or replace function public.encerrar_lote(p_lote_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_lote   public.lotes%rowtype;
  v_venda  uuid;
  v_u      uuid;
  v_horas  numeric;
begin
  select * into v_lote from public.lotes where id = p_lote_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'lote_nao_encontrado');
  end if;
  if v_lote.status <> 'aberto' then
    return jsonb_build_object('ok', true, 'ja_processado', true, 'status', v_lote.status);
  end if;
  if v_lote.termina_em > clock_timestamp() then
    return jsonb_build_object('ok', false, 'codigo', 'ainda_aberto', 'termina_em', v_lote.termina_em);
  end if;

  update public.lotes set status = 'encerrado', encerrado_em = clock_timestamp() where id = p_lote_id;
  update public.avisos_lote set status = 'cancelado' where lote_id = p_lote_id and status = 'pendente';

  if v_lote.lider_id is null then
    update public.lotes set status = 'nao_vendido' where id = p_lote_id;
    perform app.notificar(v_lote.tenant_id, v_lote.vendedor_id, v_lote.id, 'lote_nao_vendido',
      jsonb_build_object('numero', v_lote.numero, 'titulo', v_lote.titulo, 'motivo', 'sem_lances'),
      'lote_nao_vendido:' || v_lote.id);

  elsif v_lote.preco_reserva is not null and v_lote.lance_atual < v_lote.preco_reserva then
    -- Reserva não atingida (seção 6.3)
    update public.lotes set status = 'nao_vendido', reserva_nao_atingida = true where id = p_lote_id;
    if (app.config(v_lote.tenant_id, 'venda.consulta_vendedor_automatica'))::text::boolean then
      v_horas := app.config_num(v_lote.tenant_id, 'venda.consulta_vendedor_horas');
      update public.lotes
        set consulta_vendedor_status = 'pendente',
            consulta_vendedor_ate = clock_timestamp() + make_interval(secs => v_horas * 3600)
        where id = p_lote_id;
      perform app.notificar(v_lote.tenant_id, v_lote.vendedor_id, v_lote.id, 'consulta_reserva',
        jsonb_build_object('numero', v_lote.numero, 'titulo', v_lote.titulo,
                           'maior_lance', v_lote.lance_atual, 'prazo_horas', v_horas),
        'consulta_reserva:' || v_lote.id);
      perform app.notificar(v_lote.tenant_id, v_lote.lider_id, v_lote.id, 'aguardando_confirmacao_vendedor',
        jsonb_build_object('numero', v_lote.numero, 'titulo', v_lote.titulo, 'seu_lance', v_lote.lance_atual),
        'aguardando_vendedor:' || v_lote.id);
    end if;

  else
    v_venda := app.criar_venda(p_lote_id);
  end if;

  -- Demais participantes: lote encerrado
  for v_u in select distinct x.usuario_id from public.lances x
             where x.lote_id = p_lote_id and x.usuario_id <> v_lote.lider_id loop
    perform app.notificar(v_lote.tenant_id, v_u, v_lote.id, 'lote_encerrado',
      jsonb_build_object('numero', v_lote.numero, 'titulo', v_lote.titulo),
      'lote_encerrado:' || v_lote.id || ':' || v_u);
  end loop;

  perform app.publicar_lote(p_lote_id);
  select * into v_lote from public.lotes where id = p_lote_id;
  return jsonb_build_object('ok', true, 'status', v_lote.status, 'venda_id', v_venda);
end $$;

-- Resposta do vendedor (ou do admin por ele) quando a reserva não foi atingida
create or replace function public.responder_consulta_vendedor(p_lote_id uuid, p_aceita boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_lote  public.lotes%rowtype;
  v_venda uuid;
begin
  select * into v_lote from public.lotes where id = p_lote_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'lote_nao_encontrado');
  end if;
  if not (v_lote.vendedor_id = app.usuario_atual(v_lote.tenant_id) or app.e_admin(v_lote.tenant_id)) then
    return jsonb_build_object('ok', false, 'codigo', 'sem_permissao', 'mensagem', 'Só o vendedor ou o admin podem responder.');
  end if;
  if v_lote.status <> 'nao_vendido' or v_lote.consulta_vendedor_status is distinct from 'pendente' then
    return jsonb_build_object('ok', false, 'codigo', 'sem_consulta', 'mensagem', 'Não há consulta pendente para este lote.');
  end if;
  if v_lote.consulta_vendedor_ate <= clock_timestamp() then
    update public.lotes set consulta_vendedor_status = 'expirada' where id = p_lote_id;
    return jsonb_build_object('ok', false, 'codigo', 'consulta_expirada', 'mensagem', 'O prazo para responder terminou.');
  end if;

  if p_aceita then
    update public.lotes set consulta_vendedor_status = 'aceita' where id = p_lote_id;
    v_venda := app.criar_venda(p_lote_id);
  else
    update public.lotes set consulta_vendedor_status = 'recusada' where id = p_lote_id;
    perform app.notificar(v_lote.tenant_id, v_lote.lider_id, v_lote.id, 'reserva_recusada',
      jsonb_build_object('numero', v_lote.numero, 'titulo', v_lote.titulo), 'reserva_recusada:' || v_lote.id);
  end if;
  return jsonb_build_object('ok', true, 'venda_id', v_venda);
end $$;

-- ---------------------------------------------------------------------
-- Agendar leilão: encerramento escalonado (seção 7.2)
-- Lotes fecham em sequência, com intervalo configurável. A prorrogação de
-- um lote não empurra os seguintes (cada lote tem seu próprio termina_em).
-- ---------------------------------------------------------------------
create or replace function public.agendar_leilao(p_leilao_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_leilao     public.leiloes%rowtype;
  v_intervalo  interval;
  v_qtd        integer;
begin
  select * into v_leilao from public.leiloes where id = p_leilao_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'leilao_nao_encontrado');
  end if;
  if not app.e_equipe(v_leilao.tenant_id) and auth.role() is distinct from 'service_role' then
    return jsonb_build_object('ok', false, 'codigo', 'sem_permissao');
  end if;
  if v_leilao.abre_em is null or v_leilao.primeiro_fechamento_em is null
     or v_leilao.primeiro_fechamento_em <= v_leilao.abre_em then
    return jsonb_build_object('ok', false, 'codigo', 'datas_invalidas',
      'mensagem', 'Informe abertura e primeiro fechamento (depois da abertura).');
  end if;
  v_intervalo := coalesce(v_leilao.intervalo_fechamento,
    make_interval(secs => app.config_num(v_leilao.tenant_id, 'leilao.intervalo_fechamento_seg')));

  with ordenados as (
    select l.id, row_number() over (order by l.ordem nulls last, l.numero nulls last, l.criado_em) as n
    from public.lotes l
    where l.leilao_id = p_leilao_id and l.status in ('aprovado', 'agendado')
  )
  update public.lotes l
    set ordem = o.n,
        numero = coalesce(l.numero, o.n),
        abre_em = v_leilao.abre_em,
        termina_em = v_leilao.primeiro_fechamento_em + v_intervalo * (o.n - 1),
        termina_em_original = v_leilao.primeiro_fechamento_em + v_intervalo * (o.n - 1),
        status = 'agendado'
  from ordenados o where o.id = l.id;
  get diagnostics v_qtd = row_count;

  update public.leiloes set status = 'agendado' where id = p_leilao_id;
  return jsonb_build_object('ok', true, 'lotes_agendados', v_qtd);
end $$;

-- ---------------------------------------------------------------------
-- Relógio: abre lotes agendados, encerra vencidos, expira consultas.
-- Rodado pelo pg_cron a cada 5 s (ou por um worker externo).
-- Lances após termina_em já são recusados por place_bid mesmo que o
-- relógio ainda não tenha rodado.
-- ---------------------------------------------------------------------
create or replace function public.processar_relogio()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_id         uuid;
  v_abertos    integer := 0;
  v_encerrados integer := 0;
  v_expiradas  integer;
begin
  for v_id in
    select l.id from public.lotes l
    where l.status = 'agendado' and l.abre_em <= clock_timestamp()
    for update skip locked
  loop
    update public.lotes set status = 'aberto' where id = v_id;
    perform app.agendar_avisos(v_id, false);
    perform app.publicar_lote(v_id);
    v_abertos := v_abertos + 1;
  end loop;

  for v_id in
    select l.id from public.lotes l
    where l.status = 'aberto' and l.termina_em <= clock_timestamp()
    order by l.termina_em
  loop
    if (public.encerrar_lote(v_id) ->> 'ok')::boolean then
      v_encerrados := v_encerrados + 1;
    end if;
  end loop;

  update public.lotes set consulta_vendedor_status = 'expirada'
    where status = 'nao_vendido' and consulta_vendedor_status = 'pendente'
      and consulta_vendedor_ate <= clock_timestamp();
  get diagnostics v_expiradas = row_count;

  -- Status do leilão acompanha os lotes
  update public.leiloes e set status = 'aberto'
    where e.status = 'agendado'
      and exists (select 1 from public.lotes l where l.leilao_id = e.id and l.status = 'aberto');
  update public.leiloes e set status = 'encerrado'
    where e.status = 'aberto'
      and not exists (select 1 from public.lotes l where l.leilao_id = e.id and l.status in ('agendado', 'aberto'));

  return jsonb_build_object('abertos', v_abertos, 'encerrados', v_encerrados, 'consultas_expiradas', v_expiradas);
end $$;

-- ---------------------------------------------------------------------
-- Views públicas (anonimato — seção 7.4)
-- Rodam com os privilégios do dono para expor apenas colunas seguras:
-- nada de preço de reserva, vendedor, líder ou dados pessoais.
-- ---------------------------------------------------------------------
create view public.lotes_publicos with (security_barrier = true) as
select
  l.id, l.tenant_id, l.leilao_id, l.numero, l.ordem, l.titulo, l.categoria, l.raca, l.sexo,
  l.quantidade, l.peso_medio, l.data_pesagem, l.idade_min, l.idade_max, l.sanidade,
  l.cidade, l.uf, l.retirada_prazo, l.frete, l.tolerancia_quebra,
  l.preco_inicial, app.incremento(l) as incremento,
  l.lance_atual, l.qtd_lances,
  case when l.lance_atual is null then l.preco_inicial else l.lance_atual + app.incremento(l) end as lance_minimo,
  coalesce(l.lance_atual, 0) * l.quantidade as total_atual,
  l.abre_em, l.termina_em, l.prorrogado,
  case when l.status in ('agendado', 'aberto') then l.status::text else 'encerrado' end as status_publico,
  (select count(distinct x.usuario_id) from public.lances x where x.lote_id = l.id) as participantes,
  case
    when f.id is not null and f.exibir_nome
         and (app.config(l.tenant_id, 'anonimato.exibir_nome_fazenda'))::text::boolean
      then coalesce(f.apelido_publico, f.nome)
    else 'Fazenda #' || coalesce(f.codigo_publico, v.codigo_publico)
  end || ' · ' || l.cidade || '-' || l.uf as vendedor_rotulo,
  coalesce(l.lider_id = app.usuario_atual(l.tenant_id), false) as voce_lidera,
  exists (select 1 from public.lances x
          where x.lote_id = l.id and x.usuario_id = app.usuario_atual(l.tenant_id)) as voce_deu_lance
from public.lotes l
join public.tenants t on t.id = l.tenant_id and t.status = 'ativo'
join public.usuarios v on v.id = l.vendedor_id
left join public.fazendas f on f.id = l.fazenda_id
where l.status not in ('rascunho', 'em_vistoria', 'aprovado', 'cancelado');

create view public.lances_publicos with (security_barrier = true) as
select
  x.id, x.tenant_id, x.lote_id, x.seq, x.valor_por_cabeca, x.criado_em,
  coalesce(x.usuario_id = app.usuario_atual(x.tenant_id), false) as e_meu,
  case
    when x.usuario_id = app.usuario_atual(x.tenant_id)
      then 'Você' || case when x.tipo = 'automatico' then ' · automático' else '' end
    else 'Comprador #' || u.codigo_publico || coalesce(' · ' || u.cidade || '-' || u.uf, '')
  end as rotulo
from public.lances x
join public.usuarios u on u.id = x.usuario_id
join public.lotes l on l.id = x.lote_id
where l.status not in ('rascunho', 'em_vistoria', 'aprovado', 'cancelado');

grant select on public.lotes_publicos, public.lances_publicos to anon, authenticated;

-- ---------------------------------------------------------------------
-- Permissões das funções
-- ---------------------------------------------------------------------
revoke execute on function public.place_bid(uuid, numeric, text, text, uuid) from public, anon;
revoke execute on function public.cancelar_teto(uuid, uuid) from public, anon;
revoke execute on function public.responder_consulta_vendedor(uuid, boolean) from public, anon;
revoke execute on function public.agendar_leilao(uuid) from public, anon;
revoke execute on function public.encerrar_lote(uuid) from public, anon, authenticated;
revoke execute on function public.processar_relogio() from public, anon, authenticated;

grant execute on function public.place_bid(uuid, numeric, text, text, uuid) to authenticated;
grant execute on function public.cancelar_teto(uuid, uuid) to authenticated;
grant execute on function public.responder_consulta_vendedor(uuid, boolean) to authenticated;
grant execute on function public.agendar_leilao(uuid) to authenticated, service_role;
grant execute on function public.encerrar_lote(uuid) to service_role;
grant execute on function public.processar_relogio() to service_role;

revoke execute on function app.notificar(uuid, uuid, uuid, text, jsonb, text) from public, anon, authenticated;
revoke execute on function app.agendar_avisos(uuid, boolean) from public, anon, authenticated;
revoke execute on function app.criar_venda(uuid) from public, anon, authenticated;
revoke execute on function app.publicar_lote(uuid) from public, anon, authenticated;
revoke execute on function app.exposicao_credito(uuid, uuid) from public, anon, authenticated;
grant execute on function app.brl(numeric), app.recusar(text, text, jsonb), app.incremento(public.lotes),
  app.estado_publico(uuid) to anon, authenticated, service_role;

-- ---------------------------------------------------------------------
-- Agendamento (pg_cron), quando disponível. No Supabase: habilite a
-- extensão pg_cron no painel antes de aplicar, ou rode este bloco depois.
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    begin
      execute 'create extension if not exists pg_cron with schema pg_catalog';
      execute $cron$select cron.schedule('relogio-leiloes', '5 seconds', 'select public.processar_relogio()')$cron$;
    exception when others then
      raise notice 'pg_cron não configurado: %', sqlerrm;
    end;
  end if;
end $$;
