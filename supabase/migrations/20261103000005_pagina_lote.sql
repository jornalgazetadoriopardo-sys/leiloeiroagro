-- =====================================================================
-- Pregão do Campo — Fase 1 · Migração 5: página do lote
-- Seção 11.1 (2). Pode ser rodada mais de uma vez sem erro.
-- =====================================================================

-- Mídias dos lotes (fotos, vídeo, laudo) são catálogo público: bucket público.
-- Só a equipe da leiloeira envia, troca ou apaga. Caminho: <tenant_id>/<lote_id>/<arquivo>
do $$
begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('midias-lotes', 'midias-lotes', true, 524288000,
            array['image/jpeg', 'image/png', 'image/webp', 'video/mp4', 'video/quicktime', 'video/webm', 'application/pdf'])
    on conflict (id) do nothing;

    execute $p$drop policy if exists "midias-lotes: equipe envia" on storage.objects$p$;
    execute $p$drop policy if exists "midias-lotes: equipe altera" on storage.objects$p$;
    execute $p$drop policy if exists "midias-lotes: equipe apaga" on storage.objects$p$;
    execute $p$create policy "midias-lotes: equipe envia" on storage.objects for insert to authenticated
      with check (bucket_id = 'midias-lotes' and app.caminho_da_equipe(name))$p$;
    execute $p$create policy "midias-lotes: equipe altera" on storage.objects for update to authenticated
      using (bucket_id = 'midias-lotes' and app.caminho_da_equipe(name))$p$;
    execute $p$create policy "midias-lotes: equipe apaga" on storage.objects for delete to authenticated
      using (bucket_id = 'midias-lotes' and app.caminho_da_equipe(name))$p$;
  end if;
end $$;

-- Configurações que a página do lote precisa mostrar (botões, prorrogação).
-- Só chaves públicas: nada de comissões ou regras internas.
create or replace function public.config_publica(p_tenant_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_object_agg(k, app.config(p_tenant_id, k))
  from unnest(array[
    'lance.incremento_minimo', 'lance.botoes_rapidos', 'lance.janela_prorrogacao_seg',
    'entrega.prazo_contestacao_horas', 'cadastro.selfie_obrigatoria'
  ]) k;
$$;
grant execute on function public.config_publica(uuid) to anon, authenticated;
