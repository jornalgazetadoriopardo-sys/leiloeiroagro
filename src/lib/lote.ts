import 'server-only';
import { lotesDemo } from './demo';
import { obterSessao } from './sessao';
import { criarClienteServidor } from './supabase/server';
import { SUPABASE_URL } from './supabase/config';
import type { ConfigPublica, LancePublico, LotePublico, MidiaLote, Tenant, Visitante } from './tipos';

export interface PaginaLote {
  demo: boolean;
  tenant: Tenant | null;
  lote: LotePublico;
  midias: MidiaLote[];
  historico: LancePublico[];
  meuTeto: number | null;
  config: ConfigPublica;
  visitante: Visitante;
  meuCodigo: number | null;
  servidorAgora: number;
}

const CONFIG_PADRAO: ConfigPublica = { incremento: 20, botoes: [20, 50, 100], janelaMin: 3 };

/** URL pública de uma mídia: endereço completo ou caminho no bucket midias-lotes. */
export function urlMidia(url: string): string {
  if (/^https?:\/\//.test(url)) return url;
  return `${SUPABASE_URL}/storage/v1/object/public/midias-lotes/${url.replace(/^\/+/, '')}`;
}

export async function carregarLote(id: string): Promise<PaginaLote | null> {
  const sessao = await obterSessao();
  const agora = Date.now();

  if (!sessao.tenant) {
    // Modo demonstração (sem Supabase configurado)
    const lote = lotesDemo(agora).find((l) => l.id === id);
    if (!lote) return null;
    const historico: LancePublico[] = lote.lance_atual == null ? [] : [0, 1, 2, 3].map((i) => ({
      id: `h${i}`, seq: 10 - i, valor_por_cabeca: lote.lance_atual! - i * 20,
      criado_em: new Date(agora - (i + 1) * 95_000).toISOString(),
      rotulo: i === 1 ? 'Você' : `Comprador #${[4821, 1307][i % 2]} · Mococa-SP`, e_meu: i === 1,
    }));
    return { demo: true, tenant: null, lote, midias: [], historico, meuTeto: null, config: CONFIG_PADRAO,
      visitante: 'verificado', meuCodigo: 4821, servidorAgora: agora };
  }

  if (!/^[0-9a-f-]{36}$/i.test(id)) return null;
  const supabase = await criarClienteServidor();
  const { data: lote } = await supabase.from('lotes_publicos').select('*').eq('id', id).eq('tenant_id', sessao.tenant.id).maybeSingle();
  if (!lote) return null;

  const cadastro = sessao.cadastro;
  const [midias, historico, teto, cfg] = await Promise.all([
    supabase.from('midias_lote').select('id, tipo, url, ordem').eq('lote_id', id).order('ordem'),
    supabase.from('lances_publicos').select('id, seq, valor_por_cabeca, criado_em, rotulo, e_meu')
      .eq('lote_id', id).order('seq', { ascending: false }).limit(30),
    cadastro
      ? supabase.from('tetos').select('valor_maximo').eq('lote_id', id).eq('usuario_id', cadastro.id).eq('ativo', true).maybeSingle()
      : Promise.resolve({ data: null }),
    supabase.rpc('config_publica', { p_tenant_id: sessao.tenant.id }),
  ]);

  const c = (cfg.data ?? {}) as Record<string, unknown>;
  const visitante: Visitante = !sessao.logado ? 'visitante'
    : !cadastro ? 'sem_cadastro'
    : !cadastro.cadastro_enviado_em && cadastro.status_verificacao === 'pendente' ? 'cadastro_incompleto'
    : cadastro.status_verificacao;

  return {
    demo: false,
    tenant: sessao.tenant,
    lote: lote as LotePublico,
    midias: (midias.data ?? []) as MidiaLote[],
    historico: (historico.data ?? []) as LancePublico[],
    meuTeto: teto.data ? Number(teto.data.valor_maximo) : null,
    config: {
      incremento: Number(c['lance.incremento_minimo'] ?? 20),
      botoes: Array.isArray(c['lance.botoes_rapidos']) ? (c['lance.botoes_rapidos'] as number[]) : CONFIG_PADRAO.botoes,
      janelaMin: Math.round(Number(c['lance.janela_prorrogacao_seg'] ?? 180) / 60),
    },
    visitante,
    meuCodigo: cadastro?.codigo_publico ?? null,
    servidorAgora: agora,
  };
}
