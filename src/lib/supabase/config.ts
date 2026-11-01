export const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? '';
// Chave pública (publishable "sb_publishable_..." ou a antiga "anon"). Pode ir para o navegador.
export const SUPABASE_ANON_KEY =
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? '';

/** Sem as variáveis de ambiente, o app roda com dados de demonstração. */
export const supabaseConfigurado = Boolean(SUPABASE_URL && SUPABASE_ANON_KEY);
