'use server';
import { redirect } from 'next/navigation';
import { obterTenant } from './sessao';
import { criarClienteServidor } from './supabase/server';

export interface Resultado {
  ok: boolean;
  codigo?: string;
  mensagem?: string;
  campos?: string[];
  [k: string]: unknown;
}

/** Depois de confirmar o código do celular: cria/recupera o cadastro e diz para onde ir. */
export async function iniciarCadastro(): Promise<Resultado & { destino?: string }> {
  const supabase = await criarClienteServidor();
  const tenant = await obterTenant(supabase);
  if (!tenant) return { ok: false, mensagem: 'Leiloeira não encontrada.' };
  const { data, error } = await supabase.rpc('iniciar_cadastro', { p_tenant_id: tenant.id });
  if (error) return { ok: false, mensagem: 'Não foi possível entrar agora. Tente de novo.' };
  const r = data as Resultado & { cadastro_completo: boolean; status: string };
  if (!r.ok) return r;
  const precisaCadastro = !r.cadastro_completo || r.status === 'divergente';
  return { ...r, destino: precisaCadastro ? '/cadastro' : '/conta' };
}

export interface DadosCadastro {
  nome: string;
  cpf_cnpj: string;
  cidade: string;
  uf: string;
  inscricao_estadual: string;
  email: string;
  referencia_bancaria: string;
  aceite_termos: boolean;
  aceite_regras: boolean;
  aceite_privacidade: boolean;
  optin_whatsapp: boolean;
}

/** Envia o cadastro para análise. As validações valem no banco (enviar_cadastro). */
export async function enviarCadastro(dados: DadosCadastro): Promise<Resultado> {
  const supabase = await criarClienteServidor();
  const tenant = await obterTenant(supabase);
  if (!tenant) return { ok: false, mensagem: 'Leiloeira não encontrada.' };
  const { data, error } = await supabase.rpc('enviar_cadastro', { p_tenant_id: tenant.id, p_dados: dados });
  if (error) return { ok: false, mensagem: 'Não foi possível enviar agora. Tente de novo.' };
  return data as Resultado;
}

export async function sair() {
  const supabase = await criarClienteServidor();
  await supabase.auth.signOut();
  redirect('/');
}
