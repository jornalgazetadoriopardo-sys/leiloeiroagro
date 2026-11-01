import 'server-only';
import { connection } from 'next/server';
import { lotesDemo } from './demo';
import { obterTenant } from './sessao';
import { criarClienteServidor } from './supabase/server';
import { supabaseConfigurado } from './supabase/config';
import type { LotePublico, StatusVerificacao, Tenant } from './tipos';


export interface Catalogo {
  demo: boolean;
  tenant: Tenant | null;
  lotes: LotePublico[];
  servidorAgora: number;
  /** Cadastro do usuário logado neste tenant (null = visitante). */
  usuario: { codigo: number; status: StatusVerificacao } | null;
}

/** Lotes abertos e agendados do tenant, ordenados pelo fechamento. */
export async function carregarCatalogo(): Promise<Catalogo> {
  await connection();
  const agora = Date.now();

  if (!supabaseConfigurado) {
    return { demo: true, tenant: null, lotes: lotesDemo(agora), servidorAgora: agora, usuario: { codigo: 4821, status: 'verificado' } };
  }

  const supabase = await criarClienteServidor();
  const tenant = await obterTenant(supabase);
  if (!tenant) return { demo: false, tenant: null, lotes: [], servidorAgora: agora, usuario: null };

  let usuario: Catalogo['usuario'] = null;
  const { data: auth } = await supabase.auth.getUser();
  if (auth.user) {
    const { data: u } = await supabase
      .from('usuarios')
      .select('codigo_publico, status_verificacao')
      .eq('tenant_id', tenant.id)
      .eq('auth_user_id', auth.user.id)
      .maybeSingle();
    if (u) usuario = { codigo: u.codigo_publico, status: u.status_verificacao };
  }

  const { data, error } = await supabase
    .from('lotes_publicos')
    .select('*')
    .eq('tenant_id', tenant.id)
    .in('status_publico', ['aberto', 'agendado'])
    .order('termina_em', { ascending: true })
    .limit(60);
  if (error) throw error;

  return { demo: false, tenant, lotes: (data ?? []) as LotePublico[], servidorAgora: agora, usuario };
}
