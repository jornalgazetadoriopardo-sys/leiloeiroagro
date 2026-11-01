import 'server-only';
import type { Equipe } from '@/lib/admin';

export async function opcoesLote(e: Equipe) {
  const [{ data: cfg }, { data: padrao }, { data: papeis }] = await Promise.all([
    e.supabase.from('configuracoes').select('valor').eq('tenant_id', e.tenant.id).eq('chave', 'lote.categorias').maybeSingle(),
    e.supabase.from('configuracoes_padrao').select('valor').eq('chave', 'lote.categorias').single(),
    e.supabase.from('papeis_usuario').select('usuario_id, usuarios(id, nome, cidade)').eq('tenant_id', e.tenant.id).eq('papel', 'vendedor'),
  ]);
  const categorias = ((cfg?.valor ?? padrao?.valor) ?? []) as string[];
  const vendedores = (papeis ?? [])
    .map((p) => p.usuarios as unknown as { id: string; nome: string | null; cidade: string | null } | null)
    .filter((x): x is { id: string; nome: string | null; cidade: string | null } => Boolean(x))
    .map((x) => ({ id: x.id, nome: x.nome ?? 'Sem nome', cidade: x.cidade }))
    .sort((a, b) => a.nome.localeCompare(b.nome));
  return { categorias, vendedores };
}
