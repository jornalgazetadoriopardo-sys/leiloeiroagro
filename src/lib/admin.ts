import 'server-only';
import { obterSessao, type MeuCadastro } from './sessao';
import { criarClienteServidor } from './supabase/server';
import type { Tenant } from './tipos';

export interface Equipe {
  tenant: Tenant;
  usuario: MeuCadastro;
  admin: boolean;
  supabase: Awaited<ReturnType<typeof criarClienteServidor>>;
}

/** Usuário logado da equipe (admin/operador) ou null. Use dentro de <Suspense>. */
export async function obterEquipe(): Promise<Equipe | null> {
  const { tenant, cadastro } = await obterSessao();
  if (!tenant || !cadastro) return null;
  const supabase = await criarClienteServidor();
  const { data } = await supabase.from('papeis_usuario').select('papel').eq('usuario_id', cadastro.id);
  const papeis = (data ?? []).map((p) => p.papel as string);
  if (!papeis.includes('admin') && !papeis.includes('operador')) return null;
  return { tenant, usuario: cadastro, admin: papeis.includes('admin'), supabase };
}

/** "2026-11-05T19:30" digitado no fuso de Brasília → ISO com fuso. */
export function deLocalBrasilia(valor: string): string | null {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(valor)) return null;
  return new Date(`${valor}:00-03:00`).toISOString();
}

/** ISO → "2026-11-05T19:30" no fuso de Brasília (para input datetime-local). */
export function paraLocalBrasilia(iso: string | null): string {
  if (!iso) return '';
  const d = new Date(new Date(iso).getTime() - 3 * 3600_000);
  return d.toISOString().slice(0, 16);
}

export function dataHora(iso: string | null): string {
  if (!iso) return '—';
  return new Date(iso).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
}

export const STATUS_LOTE: Record<string, { rotulo: string; classe: string }> = {
  rascunho: { rotulo: 'Em preparação', classe: 'st-cinza' },
  em_vistoria: { rotulo: 'Em vistoria', classe: 'st-cinza' },
  aprovado: { rotulo: 'Pronto', classe: 'st-verde' },
  agendado: { rotulo: 'Agendado', classe: 'st-azul' },
  aberto: { rotulo: 'Aberto', classe: 'st-verde-forte' },
  encerrado: { rotulo: 'Encerrado', classe: 'st-cinza' },
  vendido: { rotulo: 'Vendido', classe: 'st-verde' },
  nao_vendido: { rotulo: 'Não vendido', classe: 'st-laranja' },
  aguardando_pagamento: { rotulo: 'Aguardando pagamento', classe: 'st-laranja' },
  pago_em_garantia: { rotulo: 'Pago', classe: 'st-verde' },
  cancelado: { rotulo: 'Cancelado', classe: 'st-cinza' },
};

export const PENDENCIA: Record<string, string> = {
  video: 'Falta vídeo',
  fotos: 'Faltam fotos (mín. 3)',
  laudo: 'Falta laudo',
  pesagem_antiga: 'Pesagem antiga',
};

/** Hora atual no servidor (fora do corpo do componente, para o lint de pureza). */
export const agoraMs = () => Date.now();
