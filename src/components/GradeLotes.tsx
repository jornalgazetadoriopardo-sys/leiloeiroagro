'use client';
import Link from 'next/link';
import { useState } from 'react';
import { brl, plural, tempoRestante } from '@/lib/formato';
import type { LotePublico } from '@/lib/tipos';
import { IconeEscudo, IconePlay, IconeRelogio } from './Icones';
import { LinhaStatus, situacao } from './StatusLance';
import { useEstadoLote } from './useEstadoLote';
import { useAgora } from './useRelogio';

interface Props {
  lotes: LotePublico[];
  servidorAgora: number;
  meuCodigo: number | null;
  demo: boolean;
}

const FILTROS = [
  { id: 'todos', rotulo: 'Todos', categorias: null },
  { id: 'bezerros', rotulo: 'Bezerros', categorias: ['bezerros', 'bezerras'] },
  { id: 'garrotes', rotulo: 'Garrotes', categorias: ['garrotes'] },
  { id: 'novilhas', rotulo: 'Novilhas', categorias: ['novilhas'] },
  { id: 'vacas', rotulo: 'Vacas', categorias: ['vacas', 'vacas paridas'] },
  { id: 'boi', rotulo: 'Boi magro', categorias: ['boi magro'] },
] as const;

export function GradeLotes({ lotes, servidorAgora, meuCodigo, demo }: Props) {
  const [filtro, setFiltro] = useState<string>('todos');
  const ativo = FILTROS.find((f) => f.id === filtro)!;
  const visiveis = ativo.categorias
    ? lotes.filter((l) => (ativo.categorias as readonly string[]).includes(l.categoria))
    : lotes;

  return (
    <>
      <div className="sec-head" style={{ justifyContent: 'space-between', alignItems: 'flex-end' }}>
        <h2>Leilões abertos</h2>
        <div className="filters" role="group" aria-label="Filtrar por categoria">
          {FILTROS.map((f) => (
            <button key={f.id} type="button" className={`filter${f.id === filtro ? ' on' : ''}`}
              aria-pressed={f.id === filtro} onClick={() => setFiltro(f.id)}>
              {f.rotulo}
            </button>
          ))}
        </div>
      </div>
      {visiveis.length === 0 ? (
        <div className="vazio">Nenhum lote aberto nesta categoria agora.</div>
      ) : (
        <div className="grid">
          {visiveis.map((l) => (
            <CartaoLote key={l.id} lote={l} servidorAgora={servidorAgora} meuCodigo={meuCodigo} demo={demo} />
          ))}
        </div>
      )}
    </>
  );
}

const DEZ_MIN = 10 * 60_000;

function CartaoLote({ lote: inicial, servidorAgora, meuCodigo, demo }: Omit<Props, 'lotes'> & { lote: LotePublico }) {
  const lote = useEstadoLote(inicial, meuCodigo, demo);
  const agora = useAgora(servidorAgora);
  const ms = lote.termina_em ? new Date(lote.termina_em).getTime() - agora : 0;
  const encerrado = lote.status_publico === 'encerrado' || ms <= 0;
  const classeTimer = encerrado ? ' ended' : ms < DEZ_MIN ? ' urgent' : '';
  const idade = lote.idade_min != null ? ` · ${lote.idade_min} a ${lote.idade_max} meses` : '';

  return (
    <article className="lot">
      <div className="media">
        <IconePlay tamanho={18} cor="#2F3833" /><span>Vídeo do lote</span>
        <span className="tag">Lote {String(lote.numero ?? '').padStart(2, '0')}</span>
        <span className={`timer${classeTimer}`}><IconeRelogio tamanho={12} /><span>{tempoRestante(ms)}</span></span>
      </div>
      <div className="body">
        <div>
          <h3>{lote.titulo}</h3>
          <p className="meta">{lote.cidade} – {lote.uf} · {Number(lote.peso_medio).toLocaleString('pt-BR')} kg méd.{idade}</p>
        </div>
        <div className="verified"><IconeEscudo tamanho={13} />Vendedor verificado · vistoria feita</div>
        <div>
          <div className="sub" style={{ fontWeight: 600 }}>{lote.lance_atual == null ? 'Lance inicial por cabeça' : 'Lance atual por cabeça'}</div>
          <div className="per">{brl(lote.lance_atual ?? lote.preco_inicial)}</div>
          <div className="sub">Total {brl(lote.total_atual)} · {plural(lote.qtd_lances, 'lance', 'lances')}</div>
        </div>
        <LinhaStatus s={situacao(lote, encerrado)} />
        <div className="actions">
          {!encerrado && lote.status_publico === 'aberto' && (
            <Link className="btn-primary" href={`/lotes/${lote.id}`}>Lance de {brl(lote.lance_minimo)}</Link>
          )}
          <Link className="btn-ghost" href={`/lotes/${lote.id}`}>Ver lote</Link>
        </div>
      </div>
    </article>
  );
}
