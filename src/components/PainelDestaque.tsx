'use client';
import Link from 'next/link';
import { brl, diaMes, faixaIdade, FRETE, plural, tempoRestante } from '@/lib/formato';
import type { LotePublico } from '@/lib/tipos';
import { IconePlay } from './Icones';
import { SelosConfianca } from './Selos';
import { FaixaStatus, situacao } from './StatusLance';
import { useEstadoLote } from './useEstadoLote';
import { useAgora } from './useRelogio';

interface Props {
  lote: LotePublico;
  servidorAgora: number;
  meuCodigo: number | null;
  demo: boolean;
}

const DEZ_MIN = 10 * 60_000;

export function PainelDestaque({ lote: inicial, servidorAgora, meuCodigo, demo }: Props) {
  const lote = useEstadoLote(inicial, meuCodigo, demo);
  const agora = useAgora(servidorAgora);
  const ms = lote.termina_em ? new Date(lote.termina_em).getTime() - agora : 0;
  const encerrado = lote.status_publico === 'encerrado' || ms <= 0;
  const s = situacao(lote, encerrado);
  const numero = `Lote ${String(lote.numero ?? '').padStart(2, '0')}`;

  return (
    <div className="featured">
      <div className="f-lot">
        <div className="f-media">
          <span className="play"><IconePlay cor="var(--accent)" /></span>
          Vídeo do lote no curral
          <span className="tag">{numero}</span>
        </div>
        <div className="thumbs">
          <div>Foto da pesagem</div>
          <div>Lote de perfil</div>
          <div>Laudo de vistoria (PDF)</div>
        </div>
        <div className="f-info">
          <h3>{lote.titulo}</h3>
          <p className="where">{lote.cidade} – {lote.uf} · Vendedor: {lote.vendedor_rotulo.split(' · ')[0]}</p>
          <dl>
            <div><dt>Quantidade</dt><dd>{plural(lote.quantidade, 'cabeça', 'cabeças')}</dd></div>
            <div><dt>Raça</dt><dd>{lote.raca}</dd></div>
            <div><dt>Peso médio</dt><dd>{Number(lote.peso_medio).toLocaleString('pt-BR')} kg · balança em {diaMes(lote.data_pesagem)}</dd></div>
            <div><dt>Idade</dt><dd>{faixaIdade(lote.idade_min, lote.idade_max)}</dd></div>
            <div><dt>Sanidade</dt><dd>{lote.sanidade?.vacinas ?? 'Ver laudo'} · GTA na venda</dd></div>
            <div><dt>Retirada</dt><dd>Até {lote.retirada_prazo} dias · {FRETE[lote.frete]}</dd></div>
          </dl>
          <SelosConfianca />
        </div>
      </div>

      <div className="panel">
        <div role="status" aria-live="polite"><FaixaStatus s={s} /></div>

        <div>
          <div className="row-between">
            <span className="label upper">Termina em</span>
            {lote.prorrogado && !encerrado && <span className="ext">Prorrogado +3 min</span>}
          </div>
          <div className="clock" style={!encerrado && ms < DEZ_MIN ? { color: 'var(--orange)' } : undefined}>
            {tempoRestante(ms)}
          </div>
        </div>

        <div className="price-block">
          <div className="label">Lance atual por cabeça</div>
          <div className="big-price">{lote.lance_atual == null ? 'Sem lances' : brl(lote.lance_atual)}</div>
          <div className="small">
            Total do lote {brl(lote.total_atual)} · {plural(lote.qtd_lances, 'lance', 'lances')} · {plural(lote.participantes, 'participante', 'participantes')}
          </div>
        </div>

        <div>
          {encerrado ? (
            <Link className="btn-secundario" href={`/lotes/${lote.id}`}>Ver resultado</Link>
          ) : (
            <Link className={`btn-lance${s === 'superado' ? ' btn-cobrir' : ''}`} href={`/lotes/${lote.id}`}>
              <span>{s === 'superado' ? 'Cobrir agora' : s === 'lidera' ? 'Acompanhar lote' : 'Dar lance'}</span>
              {s !== 'lidera' && <small>{brl(lote.lance_minimo)}/cab</small>}
            </Link>
          )}
          <div className="hint">
            Lance mínimo agora: {brl(lote.lance_minimo)}/cab · total {brl(lote.lance_minimo * lote.quantidade)}
          </div>
        </div>

        <div className="note">Lance é compromisso: o lance vencedor obriga a compra.</div>
      </div>
    </div>
  );
}
