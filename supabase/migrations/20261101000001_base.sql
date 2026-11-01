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
