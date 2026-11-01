-- Pregão do Campo — instalação completa do banco
-- GERADO por scripts/gerar-instalacao.sh a partir de supabase/migrations. Não edite à mão.
-- Como usar: Supabase → SQL Editor → cole tudo → Run.
-- Antes: Database → Extensions → habilite pg_cron.

-- ===== supabase/migrations/20261101000001_base.sql =====
-- =====================================================================
-- Pregão do Campo — Fase 1 · Migração 1: estrutura base (multi-tenant)
-- Fonte de verdade: docs/GUIA-SISTEMA-LEILAO.md (seções 2, 4.3, 13)
--
-- Convenções:
--   * Toda tabela de negócio tem id, tenant_id, criado_em e atualizado_em.
--   * Valores [CONFIGURÁVEL] ficam em configuracoes / configuracoes_padrao.
--   * Funções internas ficam no schema "app" (não exposto pela API).
-- =====================================================================

create schema if not exists app;

-- ---------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------
create type public.status_verificacao as enum
  ('pendente', 'verificado', 'divergente', 'recusado', 'suspenso');

create type public.papel as enum
  ('admin', 'operador', 'vistoriador', 'comprador', 'vendedor');

-- Ciclo de vida do lote (seção 6.2)
create type public.status_lote as enum (
  'rascunho', 'em_vistoria', 'aprovado', 'agendado', 'aberto', 'encerrado',
  'vendido', 'nao_vendido',
  'aguardando_pagamento', 'pago_em_garantia', 'em_transporte', 'entregue',
  'conferido', 'pagamento_liberado', 'concluido',
  'em_disputa', 'cancelado'
);

create type public.tipo_lance as enum ('manual', 'automatico');

-- ---------------------------------------------------------------------
-- Utilitários
-- ---------------------------------------------------------------------
create or replace function app.tocar_atualizado_em()
returns trigger language plpgsql as $$
begin
  new.atualizado_em := now();
  return new;
end $$;

-- ---------------------------------------------------------------------
-- Planos (globais, editáveis pelo super admin) — seção 2.2
-- ---------------------------------------------------------------------
create table public.planos (
  id                uuid primary key default gen_random_uuid(),
  nome              text not null unique,
  limite_cadastros  integer not null,
  franquia_msgs     integer not null,
  preco_mensal      numeric(12,2) not null,
  preco_excedente   numeric(12,4) not null,
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Tenants (leiloeiras) — seção 4.3
-- ---------------------------------------------------------------------
create table public.tenants (
  id             uuid primary key default gen_random_uuid(),
  nome           text not null,
  subdominio     text not null unique check (subdominio ~ '^[a-z0-9][a-z0-9-]{1,62}$'),
  dominio        text unique,
  logo_url       text,
  cor_destaque   text not null default '#1F3D2B' check (cor_destaque ~ '^#[0-9A-Fa-f]{6}$'),
  textos_rodape  text,
  plano_id       uuid references public.planos(id),
  status         text not null default 'ativo' check (status in ('ativo', 'suspenso')),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);

-- Super admins da plataforma (Rafael). Não pertencem a um tenant.
create table public.super_admins (
  auth_user_id  uuid primary key references auth.users(id) on delete cascade,
  criado_em     timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Configurações: padrão global + valor por tenant — seção 0 [CONFIGURÁVEL]
-- ---------------------------------------------------------------------
create table public.configuracoes_padrao (
  chave      text primary key,
  valor      jsonb not null,
  descricao  text not null,
  a_definir  boolean not null default false  -- true = valor provisório, aguarda decisão (seção 17)
);

create table public.configuracoes (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants(id) on delete cascade,
  chave          text not null references public.configuracoes_padrao(chave),
  valor          jsonb not null,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  unique (tenant_id, chave)
);

-- ---------------------------------------------------------------------
-- Usuários (um registro por pessoa por tenant) — seções 3 e 5
-- ---------------------------------------------------------------------
create table public.usuarios (
  id                     uuid primary key default gen_random_uuid(),
  tenant_id              uuid not null references public.tenants(id) on delete cascade,
  auth_user_id           uuid references auth.users(id) on delete set null,
  nome                   text,
  cpf_cnpj               text,
  celular                text not null,
  email                  text,
  cidade                 text,
  uf                     char(2),
  inscricao_estadual     text,
  referencia_bancaria    text,
  status_verificacao     public.status_verificacao not null default 'pendente',
  limite_credito         numeric(14,2),            -- null = sem limite (seção 5.3)
  optin_whatsapp         boolean not null default false,
  optin_whatsapp_em      timestamptz,
  bsuid                  text,                     -- id do usuário no WhatsApp (seção 10.6)
  originador_id          uuid references public.usuarios(id),
  codigo_publico         integer not null,         -- "Comprador #4821"
  criado_em              timestamptz not null default now(),
  atualizado_em          timestamptz not null default now(),
  unique (tenant_id, auth_user_id),
  unique (tenant_id, celular),
  unique (tenant_id, codigo_publico)
);
create index on public.usuarios (auth_user_id);

create table public.papeis_usuario (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants(id) on delete cascade,
  usuario_id     uuid not null references public.usuarios(id) on delete cascade,
  papel          public.papel not null,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  unique (usuario_id, papel)
);

create table public.acessos_delegados (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants(id) on delete cascade,
  titular_id     uuid not null references public.usuarios(id) on delete cascade,
  delegado_id    uuid not null references public.usuarios(id) on delete cascade,
  permissoes     jsonb not null default '{"dar_lance": true}',
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  unique (titular_id, delegado_id),
  check (titular_id <> delegado_id)
);

-- Registro de consentimentos (termos, regras, opt-in WhatsApp) — seção 14
create table public.consentimentos (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants(id) on delete cascade,
  usuario_id     uuid not null references public.usuarios(id) on delete cascade,
  tipo           text not null check (tipo in ('termos_uso', 'regras_leilao', 'privacidade', 'optin_whatsapp', 'optout_whatsapp')),
  versao         text not null,
  ip             text,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);

create table public.verificacoes (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenants(id) on delete cascade,
  usuario_id      uuid not null references public.usuarios(id) on delete cascade,
  tipo            text not null,                    -- ex.: consulta_cpf, analise_manual
  resultado       text not null check (resultado in ('verificado', 'divergente', 'pendente', 'recusado', 'ajuste_solicitado')),
  dados_consulta  jsonb,
  analisado_por   uuid references public.usuarios(id),
  observacao      text,
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now()
);

create table public.documentos (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants(id) on delete cascade,
  dono_id        uuid not null references public.usuarios(id) on delete cascade,
  tipo           text not null,                     -- documento_foto, comprovante_endereco, selfie, gta, nf...
  arquivo_url    text not null,                     -- caminho no bucket privado
  status         text not null default 'enviado' check (status in ('enviado', 'aprovado', 'recusado')),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);

create table public.fazendas (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants(id) on delete cascade,
  vendedor_id      uuid not null references public.usuarios(id) on delete cascade,
  nome             text not null,
  cidade           text,
  uf               char(2),
  apelido_publico  text,
  exibir_nome      boolean not null default false,  -- vendedor autoriza mostrar o nome (seção 7.4)
  codigo_publico   integer not null,                -- "Fazenda #128"
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  unique (tenant_id, codigo_publico)
);

-- ---------------------------------------------------------------------
-- Leilões e lotes — seções 6 e 7
-- ---------------------------------------------------------------------
create table public.leiloes (
  id                      uuid primary key default gen_random_uuid(),
  tenant_id               uuid not null references public.tenants(id) on delete cascade,
  titulo                  text not null,
  descricao               text,
  abre_em                 timestamptz,
  primeiro_fechamento_em  timestamptz,
  intervalo_fechamento    interval,                 -- null = usa configuração do tenant
  status                  text not null default 'rascunho'
                          check (status in ('rascunho', 'agendado', 'aberto', 'encerrado', 'cancelado')),
  criado_em               timestamptz not null default now(),
  atualizado_em           timestamptz not null default now()
);

create table public.lotes (
  id                         uuid primary key default gen_random_uuid(),
  tenant_id                  uuid not null references public.tenants(id) on delete cascade,
  leilao_id                  uuid references public.leiloes(id) on delete set null,
  vendedor_id                uuid not null references public.usuarios(id),
  fazenda_id                 uuid references public.fazendas(id),
  originador_id              uuid references public.usuarios(id),
  numero                     integer,
  ordem                      integer,               -- ordem de fechamento dentro do leilão
  titulo                     text not null,
  categoria                  text not null,
  raca                       text not null,
  sexo                       text not null check (sexo in ('macho', 'femea', 'misto')),
  quantidade                 integer not null check (quantidade > 0),
  peso_medio                 numeric(8,2) not null check (peso_medio > 0),
  data_pesagem               date not null,
  idade_min                  integer,               -- meses
  idade_max                  integer,               -- meses
  sanidade                   jsonb not null default '{}',  -- { vacinas, vermifugacao, observacoes }
  cidade                     text not null,
  uf                         char(2) not null,
  retirada_prazo             integer not null default 5,   -- dias
  frete                      text not null default 'comprador' check (frete in ('comprador', 'vendedor', 'a_combinar')),
  tolerancia_quebra          numeric(5,2),          -- %
  preco_inicial              numeric(12,2) not null check (preco_inicial > 0),  -- por cabeça
  preco_reserva              numeric(12,2),         -- por cabeça, nunca exibido ao comprador
  incremento                 numeric(12,2),         -- null = usa configuração do tenant
  lance_atual                numeric(12,2),         -- por cabeça
  lider_id                   uuid references public.usuarios(id),
  qtd_lances                 integer not null default 0,
  abre_em                    timestamptz,
  termina_em                 timestamptz,
  termina_em_original        timestamptz,
  prorrogado                 boolean not null default false,
  qtd_prorrogacoes           integer not null default 0,
  status                     public.status_lote not null default 'rascunho',
  encerrado_em               timestamptz,
  reserva_nao_atingida       boolean not null default false,
  consulta_vendedor_status   text check (consulta_vendedor_status in ('pendente', 'aceita', 'recusada', 'expirada')),
  consulta_vendedor_ate      timestamptz,
  motivo_cancelamento        text,
  criado_em                  timestamptz not null default now(),
  atualizado_em              timestamptz not null default now(),
  check (idade_max is null or idade_min is null or idade_max >= idade_min),
  check (termina_em is null or abre_em is null or termina_em > abre_em)
);
create index on public.lotes (tenant_id, status);
create index on public.lotes (status, termina_em);
create index on public.lotes (leilao_id, ordem);

create table public.midias_lote (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants(id) on delete cascade,
  lote_id        uuid not null references public.lotes(id) on delete cascade,
  tipo           text not null check (tipo in ('video', 'foto', 'laudo')),
  url            text not null,
  ordem          integer not null default 0,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);

create table public.vistorias (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenants(id) on delete cascade,
  lote_id         uuid not null references public.lotes(id) on delete cascade,
  vistoriador_id  uuid references public.usuarios(id),
  checklist       jsonb not null default '{}',
  laudo_url       text,
  aprovado        boolean,
  assinado_em     timestamptz,
  localizacao     text,
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now()
);

-- Lances: só são gravados pela função place_bid (seção 7.5)
create table public.lances (
  id                  uuid primary key default gen_random_uuid(),
  seq                 bigint generated always as identity,  -- ordem exata de registro (desempate)
  tenant_id           uuid not null references public.tenants(id) on delete cascade,
  lote_id             uuid not null references public.lotes(id) on delete cascade,
  usuario_id          uuid not null references public.usuarios(id),   -- titular do lance
  delegado_id         uuid references public.usuarios(id),            -- quem clicou, se foi pessoa delegada
  valor_por_cabeca    numeric(12,2) not null check (valor_por_cabeca > 0),
  tipo                public.tipo_lance not null,
  chave_idempotencia  text,
  criado_em           timestamptz not null default clock_timestamp(),
  atualizado_em       timestamptz not null default now()
);
create index on public.lances (lote_id, seq desc);
create index on public.lances (usuario_id, lote_id);

-- Tetos de lance automático (valor secreto) — seção 7.3
create table public.tetos (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants(id) on delete cascade,
  lote_id        uuid not null references public.lotes(id) on delete cascade,
  usuario_id     uuid not null references public.usuarios(id),
  delegado_id    uuid references public.usuarios(id),
  valor_maximo   numeric(12,2) not null check (valor_maximo > 0),
  ativo          boolean not null default true,
  registrado_em  timestamptz not null default clock_timestamp(),  -- quando o valor atual foi registrado (desempate)
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  unique (lote_id, usuario_id)
);

-- Registro de requisições de lance: idempotência e limite de frequência
create table public.requisicoes_lance (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references public.tenants(id) on delete cascade,
  lote_id             uuid not null references public.lotes(id) on delete cascade,
  usuario_id          uuid not null references public.usuarios(id),
  chave_idempotencia  text,
  resultado           jsonb not null,
  criado_em           timestamptz not null default clock_timestamp(),
  atualizado_em       timestamptz not null default now(),
  unique (lote_id, chave_idempotencia)
);
create index on public.requisicoes_lance (lote_id, usuario_id, criado_em desc);

create table public.acompanhamentos (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants(id) on delete cascade,
  lote_id        uuid references public.lotes(id) on delete cascade,
  leilao_id      uuid references public.leiloes(id) on delete cascade,
  usuario_id     uuid not null references public.usuarios(id) on delete cascade,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  check ((lote_id is null) <> (leilao_id is null)),
  unique (usuario_id, lote_id),
  unique (usuario_id, leilao_id)
);

create table public.perguntas (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenants(id) on delete cascade,
  lote_id         uuid not null references public.lotes(id) on delete cascade,
  usuario_id      uuid not null references public.usuarios(id),
  pergunta        text not null,
  resposta        text,
  respondido_por  uuid references public.usuarios(id),
  publica         boolean not null default false,
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Pós-venda — seção 9
-- ---------------------------------------------------------------------
create table public.vendas (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references public.tenants(id) on delete cascade,
  lote_id             uuid not null unique references public.lotes(id),  -- unique = encerramento idempotente
  comprador_id        uuid not null references public.usuarios(id),
  vendedor_id         uuid not null references public.usuarios(id),
  valor_por_cabeca    numeric(12,2) not null,
  quantidade          integer not null,
  total               numeric(14,2) not null,
  comissao_comprador  numeric(14,2) not null default 0,
  comissao_vendedor   numeric(14,2) not null default 0,
  status              text not null default 'aguardando_pagamento'
                      check (status in ('aguardando_pagamento', 'pago', 'em_atraso', 'cancelada', 'concluida')),
  pagamento_ate       timestamptz,
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now()
);

create table public.pagamentos (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants(id) on delete cascade,
  venda_id       uuid not null references public.vendas(id),
  provedor       text not null default 'manual',     -- piloto: confirmação manual (seção 9.1)
  id_externo     text,
  valor          numeric(14,2) not null,
  status         text not null default 'pendente' check (status in ('pendente', 'pago', 'retido', 'liberado', 'estornado')),
  pago_em        timestamptz,
  liberado_em    timestamptz,
  confirmado_por uuid references public.usuarios(id),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);

create table public.repasses (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants(id) on delete cascade,
  pagamento_id   uuid not null references public.pagamentos(id),
  beneficiario   text not null check (beneficiario in ('vendedor', 'leiloeira', 'plataforma', 'originador')),
  beneficiario_id uuid references public.usuarios(id),
  valor          numeric(14,2) not null,
  status         text not null default 'pendente' check (status in ('pendente', 'pago', 'cancelado')),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);

create table public.entregas (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null references public.tenants(id) on delete cascade,
  venda_id           uuid not null unique references public.vendas(id),
  pesagem_saida      numeric(10,2),
  pesagem_saida_url  text,
  pesagem_chegada    numeric(10,2),
  cabecas_recebidas  integer,
  gta_url            text,
  nf_url             text,
  recebido_em        timestamptz,
  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now()
);

create table public.disputas (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants(id) on delete cascade,
  venda_id       uuid not null references public.vendas(id),
  aberta_por     uuid not null references public.usuarios(id),
  motivo         text not null,
  evidencias     jsonb not null default '[]',
  status         text not null default 'aberta' check (status in ('aberta', 'em_mediacao', 'resolvida')),
  resolucao      text check (resolucao in ('liberacao_total', 'desconto_parcial', 'cancelamento')),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);

create table public.penalidades (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants(id) on delete cascade,
  usuario_id     uuid not null references public.usuarios(id),
  venda_id       uuid references public.vendas(id),
  tipo           text not null check (tipo in ('multa_desistencia', 'suspensao', 'atraso_pagamento')),
  valor          numeric(14,2),
  status         text not null default 'pendente' check (status in ('pendente', 'paga', 'perdoada')),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Notificações — seção 10
-- ---------------------------------------------------------------------
-- Eventos por usuário. canal 'app' = sininho; o despachante (próxima etapa)
-- distribui para push / WhatsApp / e-mail conforme a matriz e as preferências.
create table public.notificacoes (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants(id) on delete cascade,
  usuario_id     uuid not null references public.usuarios(id) on delete cascade,
  lote_id        uuid references public.lotes(id) on delete cascade,
  tipo           text not null,
  canal          text not null default 'app' check (canal in ('app', 'push', 'whatsapp', 'email')),
  status         text not null default 'pendente' check (status in ('pendente', 'enviado', 'falhou', 'cancelado', 'ignorado')),
  chave_dedup    text unique,
  dados          jsonb not null default '{}',
  agendado_para  timestamptz not null default now(),
  enviado_em     timestamptz,
  lida_em        timestamptz,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);
create index on public.notificacoes (status, agendado_para);
create index on public.notificacoes (usuario_id, criado_em desc);

-- Avisos agendados por lote ("dou-lhe 1/2/3", prorrogação) — seção 10.4.
-- Os destinatários são calculados no momento do envio.
create table public.avisos_lote (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants(id) on delete cascade,
  lote_id        uuid not null references public.lotes(id) on delete cascade,
  tipo           text not null,     -- doulhe_1, doulhe_2, doulhe_3, prorrogacao_1, prorrogacao_2...
  agendado_para  timestamptz not null,
  status         text not null default 'pendente' check (status in ('pendente', 'enviado', 'cancelado')),
  enviado_em     timestamptz,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  unique (lote_id, tipo)
);
create index on public.avisos_lote (status, agendado_para);

create table public.uso_mensagens (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants(id) on delete cascade,
  mes            date not null,      -- primeiro dia do mês
  quantidade     integer not null default 0,
  excedente      integer not null default 0,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  unique (tenant_id, mes)
);

-- ---------------------------------------------------------------------
-- Auditoria — seção 8
-- ---------------------------------------------------------------------
create table public.audit_log (
  id            bigint generated always as identity primary key,
  tenant_id     uuid references public.tenants(id) on delete cascade,
  ator_id       uuid,                -- auth.users.id de quem executou (null = sistema)
  acao          text not null,       -- insert / update / delete / evento de negócio
  entidade      text not null,
  entidade_id   uuid,
  dados_antes   jsonb,
  dados_depois  jsonb,
  ip            text,
  criado_em     timestamptz not null default clock_timestamp()
);
create index on public.audit_log (tenant_id, criado_em desc);
create index on public.audit_log (entidade, entidade_id);

-- ---------------------------------------------------------------------
-- Gatilhos de atualizado_em em todas as tabelas que têm a coluna
-- ---------------------------------------------------------------------
do $$
declare t record;
begin
  for t in
    select c.table_name from information_schema.columns c
    where c.table_schema = 'public' and c.column_name = 'atualizado_em'
  loop
    execute format(
      'create trigger tocar_atualizado_em before update on public.%I
         for each row execute function app.tocar_atualizado_em()', t.table_name);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Código público aleatório (anonimato: "Comprador #4821", "Fazenda #128")
-- ---------------------------------------------------------------------
create or replace function app.gerar_codigo_publico()
returns trigger language plpgsql as $$
declare
  v_codigo integer;
  v_existe boolean;
  v_tentativas integer := 0;
  v_max integer := 9999;
begin
  if new.codigo_publico is not null then
    return new;
  end if;
  loop
    v_tentativas := v_tentativas + 1;
    if v_tentativas > 50 then v_max := 99999; end if;  -- muitos cadastros: passa a 5 dígitos
    v_codigo := 1000 + floor(random() * (v_max - 999))::integer;
    execute format('select exists (select 1 from public.%I where tenant_id = $1 and codigo_publico = $2)', tg_table_name)
      into v_existe using new.tenant_id, v_codigo;
    exit when not v_existe;
  end loop;
  new.codigo_publico := v_codigo;
  return new;
end $$;

create trigger gerar_codigo_publico before insert on public.usuarios
  for each row execute function app.gerar_codigo_publico();
create trigger gerar_codigo_publico before insert on public.fazendas
  for each row execute function app.gerar_codigo_publico();

-- ===== supabase/migrations/20261101000002_config_seguranca.sql =====
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

-- ===== supabase/migrations/20261101000003_motor_lances.sql =====
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

-- ===== supabase/migrations/20261102000004_cadastro.sql =====
-- =====================================================================
-- Pregão do Campo — Fase 1 · Migração 4: cadastro e verificação
-- Pode ser rodada mais de uma vez sem erro.
-- Seção 5 do guia (fluxo do comprador/vendedor e status de cadastro)
-- e seção 14 (consentimentos, documentos em armazenamento privado).
-- =====================================================================

insert into public.configuracoes_padrao (chave, valor, descricao, a_definir) values
  ('cadastro.versao_documentos_legais', '"0.1-provisoria"',
   'Versão vigente de termos de uso, regras do leilão e política de privacidade (redação final por advogado)', true)
on conflict (chave) do nothing;

alter table public.usuarios
  add column if not exists cadastro_enviado_em timestamptz,     -- null = cadastro ainda incompleto
  add column if not exists observacao_analise text;             -- mensagem do admin ao pedir ajuste/recusar

-- Um CPF/CNPJ só pode ter um cadastro por leiloeira
create unique index if not exists usuarios_tenant_cpf_cnpj_unico
  on public.usuarios (tenant_id, cpf_cnpj) where cpf_cnpj is not null;

alter table public.documentos drop constraint if exists documentos_tipo_valido;
alter table public.documentos
  add constraint documentos_tipo_valido check (tipo in (
    'documento_foto', 'comprovante_endereco', 'selfie', 'gta', 'nota_fiscal', 'outro'));

-- ---------------------------------------------------------------------
-- Utilitários
-- ---------------------------------------------------------------------
create or replace function app.so_digitos(p text)
returns text language sql immutable set search_path = '' as $$
  select regexp_replace(coalesce(p, ''), '\D', '', 'g');
$$;

-- Valida CPF (11 dígitos) ou CNPJ (14 dígitos) pelos dígitos verificadores
create or replace function app.cpf_cnpj_valido(p text)
returns boolean language plpgsql immutable set search_path = '' as $$
declare
  d    text := app.so_digitos(p);
  n    int[];
  soma int;
  dv   int;
  pesos1 int[] := array[5,4,3,2,9,8,7,6,5,4,3,2];
  pesos2 int[] := array[6,5,4,3,2,9,8,7,6,5,4,3,2];
  i    int;
begin
  if length(d) not in (11, 14) or d ~ '^(\d)\1+$' then
    return false;
  end if;
  n := array(select substr(d, g, 1)::int from generate_series(1, length(d)) g);

  if length(d) = 11 then
    for k in 0..1 loop
      soma := 0;
      for i in 1..(9 + k) loop
        soma := soma + n[i] * (10 + k + 1 - i);
      end loop;
      dv := (soma * 10) % 11;
      if dv = 10 then dv := 0; end if;
      if dv <> n[10 + k] then return false; end if;
    end loop;
    return true;
  end if;

  soma := 0;
  for i in 1..12 loop soma := soma + n[i] * pesos1[i]; end loop;
  dv := case when soma % 11 < 2 then 0 else 11 - soma % 11 end;
  if dv <> n[13] then return false; end if;
  soma := 0;
  for i in 1..13 loop soma := soma + n[i] * pesos2[i]; end loop;
  dv := case when soma % 11 < 2 then 0 else 11 - soma % 11 end;
  return dv = n[14];
end $$;

-- ---------------------------------------------------------------------
-- 1. Depois do login por celular: cria (ou recupera) o cadastro no tenant
-- ---------------------------------------------------------------------
create or replace function public.iniciar_cadastro(p_tenant_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid      uuid := auth.uid();
  v_celular  text;
  v_usuario  public.usuarios%rowtype;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'codigo', 'nao_autenticado', 'mensagem', 'Entre com seu celular.');
  end if;
  if not exists (select 1 from public.tenants t where t.id = p_tenant_id and t.status = 'ativo') then
    return jsonb_build_object('ok', false, 'codigo', 'leiloeira_indisponivel', 'mensagem', 'Leiloeira indisponível.');
  end if;

  select * into v_usuario from public.usuarios where tenant_id = p_tenant_id and auth_user_id = v_uid;
  if not found then
    select '+' || app.so_digitos(u.phone) into v_celular from auth.users u where u.id = v_uid;
    if v_celular is null or v_celular = '+' then
      return jsonb_build_object('ok', false, 'codigo', 'sem_celular', 'mensagem', 'Entre com seu número de celular.');
    end if;

    -- Cadastro pré-criado pela leiloeira (convite) com o mesmo celular: vincula
    update public.usuarios set auth_user_id = v_uid
      where tenant_id = p_tenant_id and celular = v_celular and auth_user_id is null
      returning * into v_usuario;

    if not found then
      insert into public.usuarios (tenant_id, auth_user_id, celular)
      values (p_tenant_id, v_uid, v_celular)
      returning * into v_usuario;
    end if;

    insert into public.papeis_usuario (tenant_id, usuario_id, papel)
    values (p_tenant_id, v_usuario.id, 'comprador')
    on conflict (usuario_id, papel) do nothing;
  end if;

  return jsonb_build_object(
    'ok', true,
    'usuario_id', v_usuario.id,
    'status', v_usuario.status_verificacao,
    'cadastro_completo', v_usuario.cadastro_enviado_em is not null
  );
end $$;

-- ---------------------------------------------------------------------
-- 2. Envio do cadastro para análise (passos 2 a 6 da seção 5.1)
--    p_dados: { nome, cpf_cnpj, cidade, uf, inscricao_estadual, email,
--               referencia_bancaria, aceite_termos, aceite_regras,
--               aceite_privacidade, optin_whatsapp }
-- ---------------------------------------------------------------------
create or replace function public.enviar_cadastro(p_tenant_id uuid, p_dados jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_usuario   public.usuarios%rowtype;
  v_nome      text := btrim(coalesce(p_dados ->> 'nome', ''));
  v_doc       text := app.so_digitos(p_dados ->> 'cpf_cnpj');
  v_cidade    text := btrim(coalesce(p_dados ->> 'cidade', ''));
  v_uf        text := upper(btrim(coalesce(p_dados ->> 'uf', '')));
  v_email     text := nullif(lower(btrim(coalesce(p_dados ->> 'email', ''))), '');
  v_ie        text := nullif(btrim(coalesce(p_dados ->> 'inscricao_estadual', '')), '');
  v_ref       text := btrim(coalesce(p_dados ->> 'referencia_bancaria', ''));
  v_optin     boolean := coalesce((p_dados ->> 'optin_whatsapp')::boolean, false);
  v_versao    text;
  v_faltam    text[] := '{}';
  v_selfie    boolean;
  v_admin     uuid;
  v_ip        text := app.ip_requisicao();
begin
  select * into v_usuario from public.usuarios
    where tenant_id = p_tenant_id and auth_user_id = auth.uid()
    for update;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'sem_cadastro', 'mensagem', 'Entre com seu celular primeiro.');
  end if;
  if v_usuario.status_verificacao not in ('pendente', 'divergente') then
    return jsonb_build_object('ok', false, 'codigo', 'cadastro_' || v_usuario.status_verificacao,
      'mensagem', case v_usuario.status_verificacao
        when 'verificado' then 'Seu cadastro já está verificado. Para mudar dados, fale com a leiloeira.'
        else 'Seu cadastro não pode ser alterado agora. Fale com a leiloeira.' end);
  end if;

  -- Validações (mensagens por campo)
  if v_nome !~ '\S+\s+\S+' then v_faltam := array_append(v_faltam, 'nome'); end if;
  if not app.cpf_cnpj_valido(v_doc) then v_faltam := array_append(v_faltam, 'cpf_cnpj'); end if;
  if length(v_cidade) < 2 then v_faltam := array_append(v_faltam, 'cidade'); end if;
  if v_uf not in ('AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB','PR','PE','PI',
                  'RJ','RN','RS','RO','RR','SC','SP','SE','TO') then v_faltam := array_append(v_faltam, 'uf'); end if;
  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then v_faltam := array_append(v_faltam, 'email'); end if;
  if length(v_ref) < 5 then v_faltam := array_append(v_faltam, 'referencia_bancaria'); end if;
  if not coalesce((p_dados ->> 'aceite_termos')::boolean, false) then v_faltam := array_append(v_faltam, 'aceite_termos'); end if;
  if not coalesce((p_dados ->> 'aceite_regras')::boolean, false) then v_faltam := array_append(v_faltam, 'aceite_regras'); end if;
  if not coalesce((p_dados ->> 'aceite_privacidade')::boolean, false) then v_faltam := array_append(v_faltam, 'aceite_privacidade'); end if;

  if not exists (select 1 from public.documentos d where d.dono_id = v_usuario.id and d.tipo = 'documento_foto' and d.status <> 'recusado') then
    v_faltam := array_append(v_faltam, 'documento_foto');
  end if;
  if not exists (select 1 from public.documentos d where d.dono_id = v_usuario.id and d.tipo = 'comprovante_endereco' and d.status <> 'recusado') then
    v_faltam := array_append(v_faltam, 'comprovante_endereco');
  end if;
  v_selfie := (app.config(p_tenant_id, 'cadastro.selfie_obrigatoria'))::text::boolean;
  if v_selfie and not exists (select 1 from public.documentos d where d.dono_id = v_usuario.id and d.tipo = 'selfie' and d.status <> 'recusado') then
    v_faltam := array_append(v_faltam, 'selfie');
  end if;

  if cardinality(v_faltam) > 0 then
    return jsonb_build_object('ok', false, 'codigo', 'dados_invalidos',
      'mensagem', 'Confira os campos destacados.', 'campos', to_jsonb(v_faltam));
  end if;

  if exists (select 1 from public.usuarios u where u.tenant_id = p_tenant_id and u.cpf_cnpj = v_doc and u.id <> v_usuario.id) then
    return jsonb_build_object('ok', false, 'codigo', 'cpf_cnpj_em_uso', 'campos', '["cpf_cnpj"]'::jsonb,
      'mensagem', 'Este CPF/CNPJ já tem cadastro. Fale com a leiloeira.');
  end if;

  update public.usuarios set
    nome = v_nome, cpf_cnpj = v_doc, cidade = v_cidade, uf = v_uf, email = v_email,
    inscricao_estadual = v_ie, referencia_bancaria = v_ref,
    optin_whatsapp = v_optin,
    optin_whatsapp_em = case when v_optin and not v_usuario.optin_whatsapp then now()
                             when v_optin then v_usuario.optin_whatsapp_em end,
    status_verificacao = 'pendente',
    cadastro_enviado_em = now()
  where id = v_usuario.id;

  -- Consentimentos com data e versão (seção 14)
  v_versao := app.config(p_tenant_id, 'cadastro.versao_documentos_legais') #>> '{}';
  insert into public.consentimentos (tenant_id, usuario_id, tipo, versao, ip)
  select p_tenant_id, v_usuario.id, t, v_versao, v_ip
  from unnest(array['termos_uso', 'regras_leilao', 'privacidade',
                    case when v_optin then 'optin_whatsapp'
                         when v_usuario.optin_whatsapp then 'optout_whatsapp' end]) t
  where t is not null;

  insert into public.verificacoes (tenant_id, usuario_id, tipo, resultado, observacao)
  values (p_tenant_id, v_usuario.id, 'envio_cadastro', 'pendente',
          case when v_usuario.status_verificacao = 'divergente' then 'Reenviado após pedido de ajuste' end);

  -- Avisa a equipe: novo cadastro na fila
  for v_admin in
    select p.usuario_id from public.papeis_usuario p
    where p.tenant_id = p_tenant_id and p.papel in ('admin', 'operador')
  loop
    perform app.notificar(p_tenant_id, v_admin, null, 'cadastro_para_analise',
      jsonb_build_object('usuario_id', v_usuario.id, 'nome', v_nome));
  end loop;

  return jsonb_build_object('ok', true, 'status', 'pendente',
    'mensagem', 'Cadastro enviado. Avisaremos quando a análise terminar.');
end $$;

-- ---------------------------------------------------------------------
-- 3. Análise pelo admin (passo 8): aprovar, pedir ajuste ou recusar
-- ---------------------------------------------------------------------
create or replace function public.analisar_cadastro(p_usuario_id uuid, p_decisao text, p_observacao text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_usuario  public.usuarios%rowtype;
  v_status   public.status_verificacao;
  v_analista uuid;
begin
  select * into v_usuario from public.usuarios where id = p_usuario_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'usuario_nao_encontrado');
  end if;
  if not app.e_admin(v_usuario.tenant_id) then
    return jsonb_build_object('ok', false, 'codigo', 'sem_permissao', 'mensagem', 'Só o admin da leiloeira analisa cadastros.');
  end if;
  if v_usuario.cadastro_enviado_em is null then
    return jsonb_build_object('ok', false, 'codigo', 'cadastro_incompleto', 'mensagem', 'O cadastro ainda não foi enviado.');
  end if;

  v_status := case p_decisao
    when 'aprovar' then 'verificado'
    when 'pedir_ajuste' then 'divergente'
    when 'recusar' then 'recusado'
  end;
  if v_status is null then
    return jsonb_build_object('ok', false, 'codigo', 'decisao_invalida');
  end if;
  if p_decisao <> 'aprovar' and coalesce(btrim(p_observacao), '') = '' then
    return jsonb_build_object('ok', false, 'codigo', 'observacao_obrigatoria',
      'mensagem', 'Explique ao usuário o que precisa ser ajustado ou o motivo da recusa.');
  end if;

  v_analista := app.usuario_atual(v_usuario.tenant_id);
  update public.usuarios
    set status_verificacao = v_status,
        observacao_analise = case when p_decisao = 'aprovar' then null else btrim(p_observacao) end
    where id = p_usuario_id;

  insert into public.verificacoes (tenant_id, usuario_id, tipo, resultado, analisado_por, observacao)
  values (v_usuario.tenant_id, p_usuario_id, 'analise_manual',
          case p_decisao when 'aprovar' then 'verificado' when 'pedir_ajuste' then 'ajuste_solicitado' else 'recusado' end,
          v_analista, p_observacao);

  perform app.notificar(v_usuario.tenant_id, p_usuario_id, null,
    case p_decisao when 'aprovar' then 'cadastro_aprovado' when 'pedir_ajuste' then 'cadastro_ajuste' else 'cadastro_recusado' end,
    jsonb_build_object('observacao', p_observacao));

  return jsonb_build_object('ok', true, 'status', v_status);
end $$;

revoke execute on function public.iniciar_cadastro(uuid) from public, anon;
revoke execute on function public.enviar_cadastro(uuid, jsonb) from public, anon;
revoke execute on function public.analisar_cadastro(uuid, text, text) from public, anon;
grant execute on function public.iniciar_cadastro(uuid) to authenticated;
grant execute on function public.enviar_cadastro(uuid, jsonb) to authenticated;
grant execute on function public.analisar_cadastro(uuid, text, text) to authenticated;
grant execute on function app.so_digitos(text), app.cpf_cnpj_valido(text) to anon, authenticated, service_role;

-- ---------------------------------------------------------------------
-- Armazenamento privado dos documentos (Supabase Storage)
-- Caminho: <tenant_id>/<usuario_id>/<arquivo>. Só o dono envia e lê;
-- a equipe da leiloeira lê. Ninguém apaga nem sobrescreve (evidência).
-- Sem efeito fora do Supabase (testes locais).
-- ---------------------------------------------------------------------
create or replace function app.caminho_do_usuario(p_nome text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare
  partes text[] := string_to_array(p_nome, '/');
begin
  return array_length(partes, 1) = 3
     and app.usuario_atual(partes[1]::uuid)::text = partes[2];
exception when invalid_text_representation then
  return false;
end $$;

create or replace function app.caminho_da_equipe(p_nome text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
begin
  return app.e_equipe(split_part(p_nome, '/', 1)::uuid);
exception when invalid_text_representation then
  return false;
end $$;

grant execute on function app.caminho_do_usuario(text), app.caminho_da_equipe(text) to authenticated;

do $$
begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('documentos', 'documentos', false, 10485760,
            array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'application/pdf'])
    on conflict (id) do nothing;

    execute $p$drop policy if exists "documentos: dono envia" on storage.objects$p$;
    execute $p$drop policy if exists "documentos: dono ou equipe lê" on storage.objects$p$;
    execute $p$create policy "documentos: dono envia" on storage.objects for insert to authenticated
      with check (bucket_id = 'documentos' and app.caminho_do_usuario(name))$p$;
    execute $p$create policy "documentos: dono ou equipe lê" on storage.objects for select to authenticated
      using (bucket_id = 'documentos' and (app.caminho_do_usuario(name) or app.caminho_da_equipe(name)))$p$;
  end if;
end $$;

-- O dono só registra documento como "enviado" e apontando para a própria pasta
alter policy "documentos: dono envia" on public.documentos
  with check (
    dono_id = app.usuario_atual(tenant_id)
    and status = 'enviado'
    and arquivo_url like tenant_id::text || '/' || dono_id::text || '/%'
  );

-- Leiloeira piloto
insert into public.tenants (nome, subdominio) values ('Pregão do Campo', 'piloto') on conflict (subdominio) do nothing;
