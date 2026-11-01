-- =====================================================================
-- Pregão do Campo — Fase 1 · Migração 2: configurações, auditoria e RLS
-- Seções 0, 4.3, 7.4, 8 e 14 do guia.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Valores padrão [CONFIGURÁVEL]. Cada tenant pode sobrescrever em
-- public.configuracoes. a_definir = true marca valor provisório (seção 17).
-- ---------------------------------------------------------------------
insert into public.configuracoes_padrao (chave, valor, descricao, a_definir) values
  ('lance.incremento_minimo',           '20',                 'Incremento mínimo por cabeça (R$)', false),
  ('lance.botoes_rapidos',              '[20, 50, 100]',      'Botões de lance rápido (R$ por cabeça)', false),
  ('lance.janela_prorrogacao_seg',      '180',                'Lance com menos que isto restante leva o fim para agora + isto', false),
  ('lance.intervalo_minimo_ms',         '1000',               'Frequência máxima de lances por usuário por lote', false),
  ('leilao.intervalo_fechamento_seg',   '120',                'Intervalo entre o fechamento de lotes do mesmo leilão', false),
  ('lote.categorias',                   '["bezerros", "bezerras", "garrotes", "novilhas", "vacas", "vacas paridas", "boi magro", "touros"]',
                                                              'Categorias de gado', true),
  ('lote.pesagem_prazo_max_dias',       '15',                 'Idade máxima da pesagem na publicação do lote (dias)', true),
  ('lote.retirada_prazo_dias',          '5',                  'Prazo padrão de retirada (dias)', false),
  ('lote.tolerancia_quebra_pct',        '3',                  'Tolerância padrão de quebra de peso no transporte (%)', true),
  ('comissao.comprador_pct',            '2',                  'Comissão do comprador (%)', true),
  ('comissao.vendedor_pct',             '2',                  'Comissão do vendedor (%)', true),
  ('comissao.divisao_originador',       '{"originador_pct": 70, "plataforma_pct": 30}',
                                                              'Divisão da comissão quando há originador', true),
  ('penalidade.desistencia_multa_pct',  '10',                 'Multa por desistência (% do lote) + suspensão', true),
  ('venda.consulta_vendedor_automatica','true',               'Reserva não atingida: consultar o vendedor automaticamente', false),
  ('venda.consulta_vendedor_horas',     '24',                 'Prazo para o vendedor aceitar o maior lance (h)', false),
  ('pagamento.prazo_horas',             '48',                 'Prazo de pagamento após o arremate (h)', true),
  ('entrega.prazo_contestacao_horas',   '48',                 'Prazo de contestação após o recebimento (h)', false),
  ('cadastro.selfie_obrigatoria',       'false',              'Exigir selfie no cadastro', false),
  ('anonimato.exibir_nome_fazenda',     'false',              'Permitir que vendedores mostrem o nome da fazenda', false),
  ('aviso.doulhe_minutos',              '{"doulhe_1": 10, "doulhe_2": 5, "doulhe_3": 3}',
                                                              'Antecedência dos avisos de dou-lhe (min)', false),
  ('aviso.max_avisos_prorrogacao',      '2',                  'Máximo de avisos de prorrogação por lote', false),
  ('aviso.agrupar_coberto_seg',         '120',                'Janela de agrupamento do WhatsApp de lance coberto', false),
  ('aviso.pular_whatsapp_se_presente',  'true',               'Não enviar WhatsApp de coberto se o usuário está com o lote aberto', false),
  ('franquia.ao_estourar',              '"cobrar_excedente"', 'cobrar_excedente ou somente_push', false);

insert into public.planos (nome, limite_cadastros, franquia_msgs, preco_mensal, preco_excedente) values
  ('Básico',        100,  3000, 159.00, 0.06),
  ('Profissional',  250,  8000, 429.00, 0.06),
  ('Avançado',      500, 15000, 789.00, 0.06);

-- Valor efetivo de uma configuração para o tenant
create or replace function app.config(p_tenant uuid, p_chave text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select c.valor from public.configuracoes c where c.tenant_id = p_tenant and c.chave = p_chave),
    (select d.valor from public.configuracoes_padrao d where d.chave = p_chave)
  );
$$;

create or replace function app.config_num(p_tenant uuid, p_chave text)
returns numeric language sql stable set search_path = '' as $$
  select (app.config(p_tenant, p_chave))::text::numeric;
$$;

-- ---------------------------------------------------------------------
-- Identidade do usuário logado
-- ---------------------------------------------------------------------
create or replace function app.e_super_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.super_admins s where s.auth_user_id = auth.uid());
$$;

-- Tenants em que o usuário logado tem cadastro
create or replace function app.meus_tenants()
returns setof uuid language sql stable security definer set search_path = '' as $$
  select u.tenant_id from public.usuarios u where u.auth_user_id = auth.uid();
$$;

-- Registro do usuário logado no tenant
create or replace function app.usuario_atual(p_tenant uuid)
returns uuid language sql stable security definer set search_path = '' as $$
  select u.id from public.usuarios u
  where u.auth_user_id = auth.uid() and u.tenant_id = p_tenant;
$$;

create or replace function app.tem_papel(p_tenant uuid, p_papeis public.papel[])
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.papeis_usuario p
    join public.usuarios u on u.id = p.usuario_id
    where u.auth_user_id = auth.uid() and p.tenant_id = p_tenant and p.papel = any (p_papeis)
  );
$$;

-- Equipe da leiloeira (admin ou operador)
create or replace function app.e_equipe(p_tenant uuid)
returns boolean language sql stable set search_path = '' as $$
  select app.e_super_admin() or app.tem_papel(p_tenant, array['admin', 'operador']::public.papel[]);
$$;

create or replace function app.e_admin(p_tenant uuid)
returns boolean language sql stable set search_path = '' as $$
  select app.e_super_admin() or app.tem_papel(p_tenant, array['admin']::public.papel[]);
$$;

-- ---------------------------------------------------------------------
-- Auditoria genérica (seção 8: todo lote, lance, alteração e cancelamento)
-- ---------------------------------------------------------------------
create or replace function app.ip_requisicao()
returns text language sql stable set search_path = '' as $$
  select nullif(split_part(coalesce(
    (nullif(current_setting('request.headers', true), '')::json ->> 'x-forwarded-for'), ''), ',', 1), '');
$$;

create or replace function app.auditar()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_antes jsonb;
  v_depois jsonb;
begin
  if tg_op in ('UPDATE', 'DELETE') then v_antes := to_jsonb(old); end if;
  if tg_op in ('INSERT', 'UPDATE') then v_depois := to_jsonb(new); end if;
  if tg_op = 'UPDATE' and v_antes = v_depois then return new; end if;
  insert into public.audit_log (tenant_id, ator_id, acao, entidade, entidade_id, dados_antes, dados_depois, ip)
  values (
    coalesce((v_depois ->> 'tenant_id')::uuid, (v_antes ->> 'tenant_id')::uuid),
    auth.uid(), lower(tg_op), tg_table_name,
    coalesce((v_depois ->> 'id')::uuid, (v_antes ->> 'id')::uuid),
    v_antes, v_depois, app.ip_requisicao()
  );
  return coalesce(new, old);
end $$;

-- Evento de negócio sem alteração de linha (ex.: lance recusado, encerramento)
create or replace function app.registrar_evento(p_tenant uuid, p_acao text, p_entidade text, p_id uuid, p_dados jsonb)
returns void language sql security definer set search_path = '' as $$
  insert into public.audit_log (tenant_id, ator_id, acao, entidade, entidade_id, dados_depois, ip)
  values (p_tenant, auth.uid(), p_acao, p_entidade, p_id, p_dados, app.ip_requisicao());
$$;

do $$
declare t text;
begin
  foreach t in array array[
    'tenants', 'configuracoes', 'usuarios', 'papeis_usuario', 'acessos_delegados', 'verificacoes',
    'documentos', 'fazendas', 'leiloes', 'lotes', 'midias_lote', 'vistorias', 'lances', 'tetos',
    'perguntas', 'vendas', 'pagamentos', 'repasses', 'entregas', 'disputas', 'penalidades'
  ] loop
    execute format(
      'create trigger auditar after insert or update or delete on public.%I
         for each row execute function app.auditar()', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Row Level Security: um tenant nunca vê dados de outro (seção 4.3)
-- ---------------------------------------------------------------------
do $$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t.tablename);
  end loop;
end $$;

-- Tabelas globais
create policy "tenants: leitura pública" on public.tenants for select using (true);
create policy "tenants: super admin gerencia" on public.tenants for all
  using (app.e_super_admin()) with check (app.e_super_admin());

create policy "planos: leitura" on public.planos for select using (true);
create policy "planos: super admin gerencia" on public.planos for all
  using (app.e_super_admin()) with check (app.e_super_admin());

create policy "super_admins: próprio registro" on public.super_admins for select
  using (auth_user_id = auth.uid());

create policy "configuracoes_padrao: leitura" on public.configuracoes_padrao for select using (true);
create policy "configuracoes_padrao: super admin gerencia" on public.configuracoes_padrao for all
  using (app.e_super_admin()) with check (app.e_super_admin());

create policy "configuracoes: leitura pública do tenant" on public.configuracoes for select using (true);
create policy "configuracoes: admin gerencia" on public.configuracoes for all
  using (app.e_admin(tenant_id)) with check (app.e_admin(tenant_id));

-- Usuários: cada um vê o próprio cadastro; a equipe vê os do tenant.
create policy "usuarios: próprio ou equipe" on public.usuarios for select
  using (auth_user_id = auth.uid() or app.e_equipe(tenant_id));
create policy "usuarios: próprio atualiza dados básicos" on public.usuarios for update
  using (auth_user_id = auth.uid()) with check (auth_user_id = auth.uid());
create policy "usuarios: equipe gerencia" on public.usuarios for all
  using (app.e_equipe(tenant_id)) with check (app.e_equipe(tenant_id));

-- O próprio usuário só pode alterar estas colunas (status, limite e código
-- só mudam por funções do servidor ou pela equipe via service role).
revoke insert, update on public.usuarios from anon, authenticated;
grant update (nome, email, cidade, uf, inscricao_estadual, referencia_bancaria) on public.usuarios to authenticated;

create policy "papeis: próprios ou equipe" on public.papeis_usuario for select
  using (usuario_id = app.usuario_atual(tenant_id) or app.e_equipe(tenant_id));
create policy "papeis: admin gerencia" on public.papeis_usuario for all
  using (app.e_admin(tenant_id)) with check (app.e_admin(tenant_id));

create policy "delegados: titular ou delegado" on public.acessos_delegados for select
  using (titular_id = app.usuario_atual(tenant_id) or delegado_id = app.usuario_atual(tenant_id) or app.e_equipe(tenant_id));
create policy "delegados: titular gerencia" on public.acessos_delegados for all
  using (titular_id = app.usuario_atual(tenant_id) or app.e_admin(tenant_id))
  with check (titular_id = app.usuario_atual(tenant_id) or app.e_admin(tenant_id));

create policy "consentimentos: próprio ou equipe" on public.consentimentos for select
  using (usuario_id = app.usuario_atual(tenant_id) or app.e_equipe(tenant_id));
create policy "consentimentos: próprio registra" on public.consentimentos for insert
  with check (usuario_id = app.usuario_atual(tenant_id));

create policy "verificacoes: equipe" on public.verificacoes for all
  using (app.e_equipe(tenant_id)) with check (app.e_equipe(tenant_id));

create policy "documentos: dono ou equipe" on public.documentos for select
  using (dono_id = app.usuario_atual(tenant_id) or app.e_equipe(tenant_id));
create policy "documentos: dono envia" on public.documentos for insert
  with check (dono_id = app.usuario_atual(tenant_id));
create policy "documentos: equipe gerencia" on public.documentos for all
  using (app.e_equipe(tenant_id)) with check (app.e_equipe(tenant_id));

create policy "fazendas: vendedor ou equipe" on public.fazendas for select
  using (vendedor_id = app.usuario_atual(tenant_id) or app.e_equipe(tenant_id));
create policy "fazendas: vendedor gerencia" on public.fazendas for all
  using (vendedor_id = app.usuario_atual(tenant_id) or app.e_equipe(tenant_id))
  with check (vendedor_id = app.usuario_atual(tenant_id) or app.e_equipe(tenant_id));

-- Leilões são catálogo público (exceto rascunho)
create policy "leiloes: leitura pública" on public.leiloes for select
  using (status <> 'rascunho' or app.e_equipe(tenant_id));
create policy "leiloes: equipe gerencia" on public.leiloes for all
  using (app.e_equipe(tenant_id)) with check (app.e_equipe(tenant_id));

-- Lotes: tabela completa só para a equipe e o próprio vendedor.
-- Compradores leem pela view lotes_publicos (sem reserva nem vendedor).
create policy "lotes: equipe ou vendedor" on public.lotes for select
  using (app.e_equipe(tenant_id) or vendedor_id = app.usuario_atual(tenant_id));
create policy "lotes: equipe gerencia" on public.lotes for all
  using (app.e_equipe(tenant_id)) with check (app.e_equipe(tenant_id));

create policy "midias: leitura" on public.midias_lote for select
  using (
    app.e_equipe(tenant_id)
    or exists (select 1 from public.lotes l where l.id = lote_id
               and (l.status not in ('rascunho', 'em_vistoria', 'aprovado', 'cancelado')
                    or l.vendedor_id = app.usuario_atual(l.tenant_id)))
  );
create policy "midias: equipe gerencia" on public.midias_lote for all
  using (app.e_equipe(tenant_id)) with check (app.e_equipe(tenant_id));

create policy "vistorias: equipe ou vistoriador" on public.vistorias for all
  using (app.e_equipe(tenant_id) or vistoriador_id = app.usuario_atual(tenant_id))
  with check (app.e_equipe(tenant_id) or vistoriador_id = app.usuario_atual(tenant_id));

-- Lances: nenhum insert direto (só place_bid). Leitura própria ou da equipe;
-- o histórico anônimo sai pela view lances_publicos.
create policy "lances: próprios ou equipe" on public.lances for select
  using (usuario_id = app.usuario_atual(tenant_id) or app.e_equipe(tenant_id));
revoke insert, update, delete on public.lances from anon, authenticated;

-- Teto é secreto: só o dono e o admin enxergam.
create policy "tetos: dono ou admin" on public.tetos for select
  using (usuario_id = app.usuario_atual(tenant_id) or app.e_admin(tenant_id));
revoke insert, update, delete on public.tetos from anon, authenticated;

create policy "requisicoes: equipe" on public.requisicoes_lance for select
  using (app.e_admin(tenant_id));
revoke insert, update, delete on public.requisicoes_lance from anon, authenticated;

create policy "acompanhamentos: próprios" on public.acompanhamentos for all
  using (usuario_id = app.usuario_atual(tenant_id) or app.e_equipe(tenant_id))
  with check (usuario_id = app.usuario_atual(tenant_id));

create policy "perguntas: públicas, próprias ou equipe" on public.perguntas for select
  using (publica or usuario_id = app.usuario_atual(tenant_id) or app.e_equipe(tenant_id));
create policy "perguntas: usuário pergunta" on public.perguntas for insert
  with check (usuario_id = app.usuario_atual(tenant_id) and resposta is null and not publica);
create policy "perguntas: equipe responde" on public.perguntas for update
  using (app.e_equipe(tenant_id)) with check (app.e_equipe(tenant_id));

create policy "vendas: partes ou equipe" on public.vendas for select
  using (comprador_id = app.usuario_atual(tenant_id) or vendedor_id = app.usuario_atual(tenant_id) or app.e_equipe(tenant_id));
create policy "vendas: equipe gerencia" on public.vendas for all
  using (app.e_equipe(tenant_id)) with check (app.e_equipe(tenant_id));

create policy "pagamentos: partes ou equipe" on public.pagamentos for select
  using (app.e_equipe(tenant_id) or exists (
    select 1 from public.vendas v where v.id = venda_id
    and app.usuario_atual(v.tenant_id) in (v.comprador_id, v.vendedor_id)));
create policy "pagamentos: equipe gerencia" on public.pagamentos for all
  using (app.e_equipe(tenant_id)) with check (app.e_equipe(tenant_id));

create policy "repasses: admin" on public.repasses for all
  using (app.e_admin(tenant_id)) with check (app.e_admin(tenant_id));

create policy "entregas: partes ou equipe" on public.entregas for select
  using (app.e_equipe(tenant_id) or exists (
    select 1 from public.vendas v where v.id = venda_id
    and app.usuario_atual(v.tenant_id) in (v.comprador_id, v.vendedor_id)));
create policy "entregas: equipe gerencia" on public.entregas for all
  using (app.e_equipe(tenant_id)) with check (app.e_equipe(tenant_id));

create policy "disputas: partes ou equipe" on public.disputas for select
  using (app.e_equipe(tenant_id) or exists (
    select 1 from public.vendas v where v.id = venda_id
    and app.usuario_atual(v.tenant_id) in (v.comprador_id, v.vendedor_id)));
create policy "disputas: equipe gerencia" on public.disputas for all
  using (app.e_equipe(tenant_id)) with check (app.e_equipe(tenant_id));

create policy "penalidades: próprio ou equipe" on public.penalidades for select
  using (usuario_id = app.usuario_atual(tenant_id) or app.e_equipe(tenant_id));
create policy "penalidades: admin gerencia" on public.penalidades for all
  using (app.e_admin(tenant_id)) with check (app.e_admin(tenant_id));

create policy "notificacoes: próprias" on public.notificacoes for select
  using (usuario_id = app.usuario_atual(tenant_id));
create policy "notificacoes: marcar como lida" on public.notificacoes for update
  using (usuario_id = app.usuario_atual(tenant_id)) with check (usuario_id = app.usuario_atual(tenant_id));
revoke insert, delete, update on public.notificacoes from anon, authenticated;
grant update (lida_em) on public.notificacoes to authenticated;

create policy "avisos_lote: equipe" on public.avisos_lote for select using (app.e_equipe(tenant_id));
create policy "uso_mensagens: admin" on public.uso_mensagens for select using (app.e_admin(tenant_id));

create policy "audit_log: admin do tenant" on public.audit_log for select
  using (app.e_admin(tenant_id));
revoke insert, update, delete on public.audit_log from anon, authenticated;

-- Schema "app" não é exposto pela API (PostgREST só expõe "public").
-- As funções de identidade precisam ser executáveis por anon/authenticated
-- porque são avaliadas dentro das políticas de RLS. As que gravam dados
-- ficam restritas ao dono (chamadas só por funções security definer).
grant usage on schema app to anon, authenticated, service_role;
grant execute on all functions in schema app to anon, authenticated, service_role;
revoke execute on function app.registrar_evento(uuid, text, text, uuid, jsonb) from public, anon, authenticated;
revoke execute on function app.auditar() from public, anon, authenticated;
revoke execute on function app.gerar_codigo_publico() from public, anon, authenticated;
