'use client';
import Link from 'next/link';
import { useState } from 'react';
import { brl, plural, tempoRestante } from '@/lib/formato';
import type { LotePublico } from '@/lib/tipos';
import { IconePlay, IconeRelogio } from './Icones';
import { SelosCartao } from './Selos';
import { situacao, TarjaStatus } from './StatusLance';
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
  const s = situacao(lote, encerrado);
  const urgente = !encerrado && ms < DEZ_MIN;
  const href = `/lotes/${lote.id}`;
  const precoPorCabeca = lote.lance_atual ?? lote.preco_inicial;
  const idade = lote.idade_min != null ? `${lote.idade_min}–${lote.idade_max} m` : '—';

  return (
    <article className={`lot lot-${s}`}>
      <Link href={href} className="media" aria-label={`Ver vídeo e detalhes do lote ${lote.numero ?? ''}`}>
        <IconePlay tamanho={18} cor="#2F3833" /><span>Vídeo do lote</span>
        <span className="tag">Lote {String(lote.numero ?? '').padStart(2, '0')}</span>
      </Link>
      <div className={`timer-linha${encerrado ? ' ended' : urgente ? ' urgent' : ''}`}>
        <IconeRelogio tamanho={18} />
        <span>{encerrado ? 'Encerrado' : lote.status_publico === 'agendado' ? 'Fecha em' : urgente ? 'Últimos minutos' : 'Termina em'}</span>
        {!encerrado && <strong>{tempoRestante(ms)}</strong>}
      </div>
      {s !== 'sem_lance' && <TarjaStatus s={s} />}
      <div className="body">
        <div>
          <h3><Link href={href}>{lote.titulo}</Link></h3>
          <p className="meta">{lote.cidade} – {lote.uf}</p>
        </div>
        <dl className="fatos">
          <div><dt>Cabeças</dt><dd>{lote.quantidade}</dd></div>
          <div><dt>Peso méd.</dt><dd>{Number(lote.peso_medio).toLocaleString('pt-BR')} kg</dd></div>
          <div><dt>Idade</dt><dd>{idade}</dd></div>
        </dl>
        <div className="preco-cartao">
          <div className="sub">{lote.lance_atual == null ? 'Lance inicial' : 'Lance atual'} · por cabeça</div>
          <div className="per">{brl(precoPorCabeca)}</div>
          <div className="sub">Total do lote <b>{brl(precoPorCabeca * lote.quantidade)}</b> · {plural(lote.qtd_lances, 'lance', 'lances')}</div>
        </div>
        <SelosCartao />
        <div className="actions">
          {encerrado || lote.status_publico !== 'aberto' || s === 'lidera' ? (
            <Link className="btn-secundario" href={href}>{s === 'lidera' ? 'Acompanhar lote' : 'Ver lote'}</Link>
          ) : (
            <Link className={`btn-lance${s === 'superado' ? ' btn-cobrir' : ''}`} href={href}>
              <span>{s === 'superado' ? 'Cobrir agora' : 'Dar lance'}</span>
              <small>{brl(lote.lance_minimo)}/cab</small>
            </Link>
          )}
        </div>
      </div>
    </article>
  );
}
