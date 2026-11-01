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
