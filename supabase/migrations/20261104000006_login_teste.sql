-- =====================================================================
-- Pregão do Campo — Fase 1 · Migração 6: login de teste (celular + senha)
-- Enquanto o SMS não está ligado, a conta é criada com celular e senha.
-- O celular vem dos dados da conta (não verificado por código), então:
--   * não vincula convites pré-cadastrados (alguém poderia "assumir" o
--     cadastro de outra pessoa digitando o número dela);
--   * celular repetido na leiloeira é recusado.
-- Com o login por código (SMS/WhatsApp), o celular verificado tem prioridade.
-- Pode ser rodada mais de uma vez sem erro.
-- =====================================================================

create or replace function public.iniciar_cadastro(p_tenant_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid         uuid := auth.uid();
  v_celular     text;
  v_verificado  boolean;
  v_usuario     public.usuarios%rowtype;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'codigo', 'nao_autenticado', 'mensagem', 'Entre com seu celular.');
  end if;
  if not exists (select 1 from public.tenants t where t.id = p_tenant_id and t.status = 'ativo') then
    return jsonb_build_object('ok', false, 'codigo', 'leiloeira_indisponivel', 'mensagem', 'Leiloeira indisponível.');
  end if;

  select * into v_usuario from public.usuarios where tenant_id = p_tenant_id and auth_user_id = v_uid;
  if not found then
    select
      case when app.so_digitos(u.phone) <> '' then '+' || app.so_digitos(u.phone)
           when app.so_digitos(u.raw_user_meta_data ->> 'celular') <> '' then '+' || app.so_digitos(u.raw_user_meta_data ->> 'celular')
      end,
      app.so_digitos(u.phone) <> ''
    into v_celular, v_verificado
    from auth.users u where u.id = v_uid;

    if v_celular is null or length(v_celular) < 12 then
      return jsonb_build_object('ok', false, 'codigo', 'sem_celular', 'mensagem', 'Entre com seu número de celular.');
    end if;

    if v_verificado then
      -- Cadastro pré-criado pela leiloeira (convite) com o mesmo celular: vincula
      update public.usuarios set auth_user_id = v_uid
        where tenant_id = p_tenant_id and celular = v_celular and auth_user_id is null
        returning * into v_usuario;
    end if;

    if v_usuario.id is null then
      if exists (select 1 from public.usuarios u where u.tenant_id = p_tenant_id and u.celular = v_celular) then
        return jsonb_build_object('ok', false, 'codigo', 'celular_em_uso',
          'mensagem', 'Este celular já tem cadastro. Entre com a senha dele ou fale com a leiloeira.');
      end if;
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

revoke execute on function public.iniciar_cadastro(uuid) from public, anon;
grant execute on function public.iniciar_cadastro(uuid) to authenticated;
