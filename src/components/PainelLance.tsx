'use client';
import Link from 'next/link';
import { useCallback, useEffect, useRef, useState } from 'react';
import { brl, plural, tempoRestante } from '@/lib/formato';
import { clienteNavegador } from '@/lib/supabase/client';
import type { ConfigPublica, LancePublico, LotePublico, Visitante } from '@/lib/tipos';
import { IconeAlerta, IconeOk } from './Icones';
import { FaixaStatus, situacao } from './StatusLance';
import { useEstadoLote } from './useEstadoLote';
import { useAgora } from './useRelogio';

interface Props {
  lote: LotePublico;
  historico: LancePublico[];
  meuTeto: number | null;
  config: ConfigPublica;
  visitante: Visitante;
  meuCodigo: number | null;
  servidorAgora: number;
  demo: boolean;
}

// Pedido aguardando confirmação (seção 7.5: "Confirmar lance de R$ 2.930/cab · total R$ 87.900")
interface Pedido {
  tipo: 'manual' | 'teto';
  valor: number;
  chave: string; // idempotência: o mesmo pedido nunca vira dois lances
}

const DEZ_MIN = 10 * 60_000;

/** Painel de lance da página do lote — seções 7 e 11.1 (2). Quem decide tudo é o servidor (place_bid). */
export function PainelLance(p: Props) {
  const lote = useEstadoLote(p.lote, p.meuCodigo, p.demo);
  const agora = useAgora(p.servidorAgora);
  const [historico, setHistorico] = useState(p.historico);
  const [teto, setTeto] = useState<number | null>(p.meuTeto);
  const [tetoDigitado, setTetoDigitado] = useState('');
  const [pedido, setPedido] = useState<Pedido | null>(null);
  const [enviando, setEnviando] = useState(false);
  const [aviso, setAviso] = useState<{ tipo: 'ok' | 'erro'; texto: string } | null>(null);
  // Resposta do meu último lance, válida até o lote receber outro lance
  const [resposta, setResposta] = useState<{ lider: boolean; qtd: number } | null>(null);
  const dialogo = useRef<HTMLDialogElement>(null);

  const ms = lote.termina_em ? new Date(lote.termina_em).getTime() - agora : 0;
  const encerrado = lote.status_publico === 'encerrado' || ms <= 0;
  const agendado = lote.status_publico === 'agendado';
  // A resposta do próprio lance chega antes do broadcast: usa a mais recente
  const respostaValida = resposta && resposta.qtd >= lote.qtd_lances;
  const loteVisto = respostaValida ? { ...lote, voce_lidera: resposta.lider, voce_deu_lance: true } : lote;
  const s = situacao(loteVisto, encerrado);
  const podeDarLance = p.visitante === 'verificado' && !encerrado && !agendado && !p.demo;

  // Histórico: recarrega quando o lote muda (broadcast) — a view já vem anônima
  const recarregarHistorico = useCallback(async () => {
    if (p.demo) return;
    const { data } = await clienteNavegador().from('lances_publicos')
      .select('id, seq, valor_por_cabeca, criado_em, rotulo, e_meu')
      .eq('lote_id', lote.id).order('seq', { ascending: false }).limit(30);
    if (data) setHistorico(data as LancePublico[]);
  }, [lote.id, p.demo]);

  useEffect(() => {
    // setState só acontece depois da resposta da rede (assíncrono)
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void recarregarHistorico();
  }, [lote.qtd_lances, lote.lance_atual, recarregarHistorico]);

  // Valor de cada botão rápido: "cobrir com + R$ 20" sobre o lance atual
  const base = lote.lance_atual ?? lote.preco_inicial - p.config.incremento;
  const valorBotao = (inc: number) => Math.max(base + inc, lote.lance_minimo);

  function abrir(tipo: Pedido['tipo'], valor: number) {
    setAviso(null);
    setPedido({ tipo, valor, chave: crypto.randomUUID() });
    dialogo.current?.showModal();
  }

  function fechar() {
    dialogo.current?.close();
    setPedido(null);
  }

  async function confirmar() {
    if (!pedido) return;
    setEnviando(true);
    try {
      const { data, error } = await clienteNavegador().rpc('place_bid', {
        p_lote_id: lote.id, p_valor: pedido.valor, p_tipo: pedido.tipo, p_chave_idempotencia: pedido.chave,
      });
      if (error) throw error;
      const r = data as { ok: boolean; mensagem?: string; voce_lidera?: boolean; teto?: number | null; qtd_lances?: number };
      if (!r.ok) {
        setAviso({ tipo: 'erro', texto: r.mensagem ?? 'Lance não aceito.' });
      } else {
        setResposta({ lider: Boolean(r.voce_lidera), qtd: r.qtd_lances ?? 0 });
        setTeto(r.teto ?? null);
        if (pedido.tipo === 'teto') setTetoDigitado('');
        setAviso({ tipo: r.voce_lidera ? 'ok' : 'erro', texto: r.mensagem ?? 'Lance registrado.' });
        void recarregarHistorico();
      }
      fechar();
    } catch {
      // Falha de rede: o pedido continua aberto e "Confirmar" reenvia com a MESMA chave
      setAviso({ tipo: 'erro', texto: 'Sem conexão. Toque em Confirmar de novo — o lance não será duplicado.' });
    } finally {
      setEnviando(false);
    }
  }

  async function cancelarTeto() {
    const { data } = await clienteNavegador().rpc('cancelar_teto', { p_lote_id: lote.id });
    const r = data as { ok: boolean; mensagem?: string } | null;
    if (r?.ok) setTeto(null);
    else setAviso({ tipo: 'erro', texto: r?.mensagem ?? 'Não foi possível cancelar.' });
  }

  function ativarTeto() {
    const v = Number(tetoDigitado.replace(/\D/g, ''));
    if (!v) return;
    const minimo = loteVisto.voce_lidera ? Math.max(teto ?? 0, lote.lance_atual ?? 0) + 1 : lote.lance_minimo;
    if (v < minimo) {
      setAviso({ tipo: 'erro', texto: `O teto precisa ser de pelo menos ${brl(minimo)} por cabeça.` });
      return;
    }
    abrir('teto', v);
  }

  return (
    <div className="panel">
      <div role="status" aria-live="polite">
        {agendado ? <div className="banner b-gray">Abre para lances em breve</div> : <FaixaStatus s={s} />}
      </div>

      <div>
        <div className="row-between">
          <span className="label upper">{agendado ? 'Fecha em' : 'Termina em'}</span>
          {lote.prorrogado && !encerrado && <span className="ext">Prorrogado +{p.config.janelaMin} min</span>}
        </div>
        <div className="clock" style={!encerrado && ms < DEZ_MIN ? { color: 'var(--orange)' } : undefined}>
          {tempoRestante(ms)}
        </div>
        {!encerrado && lote.termina_em && (
          <div className="small">
            {new Date(lote.termina_em).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo', weekday: 'short', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })}
            {' '}· horário de Brasília
          </div>
        )}
      </div>

      <div className="price-block">
        <div className="label">{lote.lance_atual == null ? 'Lance inicial por cabeça' : 'Lance atual por cabeça'}</div>
        <div className="big-price">{brl(lote.lance_atual ?? lote.preco_inicial)}</div>
        <div className="small">
          Total do lote {brl((lote.lance_atual ?? lote.preco_inicial) * lote.quantidade)} · {plural(lote.qtd_lances, 'lance', 'lances')} · {plural(lote.participantes, 'participante', 'participantes')}
        </div>
      </div>

      {aviso && (
        <div className={aviso.tipo === 'ok' ? 'msg-ok' : 'msg-erro'} role="alert">
          {aviso.tipo === 'ok' ? <IconeOk /> : <IconeAlerta />}{aviso.texto}
        </div>
      )}

      {!encerrado && !agendado && (podeDarLance ? (
        <>
          <div>
            <div style={{ fontSize: 14, fontWeight: 600, marginBottom: 8 }}>{lote.lance_atual == null ? 'Dar o primeiro lance' : 'Cobrir com'}</div>
            <div className="incs">
              {p.config.botoes.map((inc) => (
                <button key={inc} className="btn-primary" type="button" onClick={() => abrir('manual', valorBotao(inc))}
                  aria-label={`Dar lance de ${brl(valorBotao(inc))} por cabeça`}>
                  {lote.lance_atual == null && inc === p.config.botoes[0] ? brl(valorBotao(inc)) : `+ ${brl(valorBotao(inc) - base)}`}
                </button>
              ))}
            </div>
            <div className="hint">Lance mínimo agora: {brl(lote.lance_minimo)}/cab · valores por cabeça</div>
          </div>

          <div className="auto">
            <label htmlFor="teto">Lance automático</label>
            <div className="desc">
              Informe seu teto por cabeça. O sistema cobre outros lances por você, de {brl(p.config.incremento)} em {brl(p.config.incremento)}, até esse valor. Ninguém vê o seu teto.
            </div>
            <div className="controls">
              <input id="teto" type="text" inputMode="numeric" placeholder={`Ex.: ${(lote.lance_minimo + 200).toLocaleString('pt-BR')}`}
                value={tetoDigitado} onChange={(e) => setTetoDigitado(e.target.value.replace(/\D/g, '') ? Number(e.target.value.replace(/\D/g, '')).toLocaleString('pt-BR') : '')} />
              <button className="btn-outline" type="button" onClick={ativarTeto}>{teto ? 'Aumentar' : 'Ativar'}</button>
            </div>
            {teto != null && (
              <div className="teto-ativo">
                <span><IconeOk tamanho={14} /> Ativo até {brl(teto)}/cab</span>
                {!loteVisto.voce_lidera && <button type="button" className="btn-link" onClick={cancelarTeto}>Cancelar</button>}
              </div>
            )}
          </div>
        </>
      ) : <AvisoCadastro visitante={p.visitante} demo={p.demo} loteId={lote.id} />)}

      <div>
        <div style={{ fontSize: 14, fontWeight: 600, marginBottom: 8 }}>Últimos lances</div>
        {historico.length === 0 ? <div className="small">Ainda sem lances. Seja o primeiro.</div> : (
          <ol className="hist">
            {historico.slice(0, 8).map((h) => (
              <li key={h.id}>
                <span className={h.e_meu ? 'me' : 'other'}>{h.rotulo}</span>
                <span style={{ whiteSpace: 'nowrap', textAlign: 'right' }}>
                  <strong>{brl(Number(h.valor_por_cabeca))}</strong> <span className="when">{ha(h.criado_em, agora)}</span>
                </span>
              </li>
            ))}
          </ol>
        )}
      </div>

      <div className="note">Lance é compromisso: o lance vencedor obriga a compra. O horário que vale é o do servidor.</div>

      <dialog ref={dialogo} className="confirmar" onClose={() => setPedido(null)} aria-labelledby="titulo-confirmar">
        {pedido && (
          <>
            <h2 id="titulo-confirmar">{pedido.tipo === 'teto' ? 'Confirmar lance automático' : 'Confirmar lance'}</h2>
            <div className="valor">{brl(pedido.valor)}<span style={{ fontSize: 18 }}>/cab</span></div>
            <div className="small" style={{ fontSize: 16 }}>
              {pedido.tipo === 'teto' ? 'Total até ' : 'Total '}<b>{brl(pedido.valor * lote.quantidade)}</b> · {plural(lote.quantidade, 'cabeça', 'cabeças')}
            </div>
            {pedido.tipo === 'teto' && <p className="small">O sistema dá lances por você só quando alguém cobrir, até este teto.</p>}
            {aviso?.tipo === 'erro' && <div className="msg-erro" style={{ marginTop: 12 }}><IconeAlerta />{aviso.texto}</div>}
            <div className="acoes">
              <button type="button" className="btn-ghost" onClick={fechar} disabled={enviando}>Cancelar</button>
              <button type="button" className="btn-primary" onClick={confirmar} disabled={enviando} autoFocus>
                {enviando ? 'Enviando…' : 'Confirmar'}
              </button>
            </div>
          </>
        )}
      </dialog>
    </div>
  );
}

function AvisoCadastro({ visitante, demo, loteId }: { visitante: Visitante; demo: boolean; loteId: string }) {
  if (demo) return <div className="aviso-cadastro">Modo demonstração: os lances funcionam quando o sistema estiver ligado ao banco.</div>;
  const voltar = encodeURIComponent(`/lotes/${loteId}`);
  switch (visitante) {
    case 'visitante':
      return <div className="aviso-cadastro">Entre com seu celular para dar lance.<Link className="btn-primary" href={`/entrar?voltar=${voltar}`}>Entrar para dar lance</Link></div>;
    case 'sem_cadastro':
    case 'cadastro_incompleto':
      return <div className="aviso-cadastro">Complete seu cadastro. Depois da aprovação você poderá dar lances.<Link className="btn-primary" href="/cadastro">Completar cadastro</Link></div>;
    case 'pendente':
      return <div className="aviso-cadastro">Seu cadastro está em análise. Você poderá dar lances assim que for aprovado.</div>;
    case 'divergente':
      return <div className="aviso-cadastro">A leiloeira pediu um ajuste no seu cadastro.<Link className="btn-primary" href="/cadastro">Corrigir cadastro</Link></div>;
    default:
      return <div className="aviso-cadastro">Seu cadastro não está liberado para lances. Fale com a leiloeira.</div>;
  }
}

function ha(iso: string, agora: number): string {
  const s = Math.max(0, Math.floor((agora - new Date(iso).getTime()) / 1000));
  if (s < 10) return 'agora';
  if (s < 60) return `há ${s} s`;
  if (s < 3600) return `há ${Math.floor(s / 60)} min`;
  return new Date(iso).toLocaleTimeString('pt-BR', { timeZone: 'America/Sao_Paulo', hour: '2-digit', minute: '2-digit' });
}
