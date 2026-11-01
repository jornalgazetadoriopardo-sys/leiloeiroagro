import 'server-only';
import { connection } from 'next/server';
import { criarClienteServidor } from './supabase/server';
import { supabaseConfigurado } from './supabase/config';
import type { StatusVerificacao, Tenant } from './tipos';

// Fase 1: um único tenant ativo. Na Fase 3 o tenant sai do subdomínio.
export const SUBDOMINIO = process.env.NEXT_PUBLIC_TENANT_SUBDOMINIO ?? 'piloto';

export interface MeuCadastro {
  id: string;
  codigo_publico: number;
  nome: string | null;
  cpf_cnpj: string | null;
  celular: string;
  email: string | null;
  cidade: string | null;
  uf: string | null;
  inscricao_estadual: string | null;
  referencia_bancaria: string | null;
  status_verificacao: StatusVerificacao;
  optin_whatsapp: boolean;
  cadastro_enviado_em: string | null;
  observacao_analise: string | null;
}

export interface Sessao {
  tenant: Tenant | null;
  logado: boolean;
  cadastro: MeuCadastro | null;
}

export async function obterTenant(supabase: Awaited<ReturnType<typeof criarClienteServidor>>): Promise<Tenant | null> {
  const { data, error } = await supabase
    .from('tenants')
    .select('id, nome, subdominio, cor_destaque, logo_url')
    .eq('subdominio', SUBDOMINIO)
    .maybeSingle();
  if (error) throw error;
  return data;
}

/** Tenant, login e cadastro do usuário atual. Lê cookies: use dentro de <Suspense>. */
export async function obterSessao(): Promise<Sessao> {
  await connection();
  if (!supabaseConfigurado) return { tenant: null, logado: false, cadastro: null };
  const supabase = await criarClienteServidor();
  const [tenant, { data: auth }] = await Promise.all([obterTenant(supabase), supabase.auth.getUser()]);
  if (!tenant || !auth.user) return { tenant, logado: Boolean(auth.user), cadastro: null };

  const { data } = await supabase
    .from('usuarios')
    .select('id, codigo_publico, nome, cpf_cnpj, celular, email, cidade, uf, inscricao_estadual, referencia_bancaria, status_verificacao, optin_whatsapp, cadastro_enviado_em, observacao_analise')
    .eq('tenant_id', tenant.id)
    .eq('auth_user_id', auth.user.id)
    .maybeSingle();
  return { tenant, logado: true, cadastro: data as MeuCadastro | null };
}
