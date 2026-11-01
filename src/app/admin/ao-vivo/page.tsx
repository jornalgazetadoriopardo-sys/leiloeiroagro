import Link from 'next/link';
import { Suspense } from 'react';
import { agoraMs, dataHora, obterEquipe } from '@/lib/admin';
import { brl, tempoRestante } from '@/lib/formato';
import { AtualizarSozinho } from '../componentes';
import { Carregando, Restrito } from '../Restrito';

// Ao vivo — seção 11.2: liderando, nº de lances, prorrogado
export default function AoVivo() {
  return <Suspense fallback={<Carregando />}><Conteudo /></Suspense>;
}

async function Conteudo() {
  const e = await obterEquipe();
  if (!e) return <Restrito />;
  const { data } = await e.supabase.from('lotes')
    .select('id, numero, titulo, quantidade, lance_atual, preco_inicial, preco_reserva, qtd_lances, termina_em, prorrogado, qtd_prorrogacoes, status, lider:usuarios!lotes_lider_id_fkey(nome, codigo_publico, cidade, uf)')
    .eq('tenant_id', e.tenant.id).in('status', ['aberto', 'agendado']).order('termina_em');
  const agora = agoraMs();

  return (
    <>
      <div className="row-between">
        <div><h1>Ao vivo</h1><p className="sub-titulo">Lotes abertos e agendados, do que fecha primeiro.</p></div>
        <AtualizarSozinho segundos={10} />
      </div>
      <div className="lista-admin">
        {(data ?? []).length === 0 && <div className="vazio">Nenhum lote aberto ou agendado.</div>}
        {(data ?? []).map((l) => {
          const lider = l.lider as unknown as { nome: string | null; codigo_publico: number; cidade: string | null; uf: string | null } | null;
          const ms = l.termina_em ? new Date(l.termina_em).getTime() - agora : 0;
          const reservaOk = l.preco_reserva == null || (l.lance_atual ?? 0) >= Number(l.preco_reserva);
          return (
            <Link key={l.id} href={`/admin/lotes/${l.id}`} className="item-admin">
              <div className="principal">
                <b>{l.numero ? `Lote ${String(l.numero).padStart(2, '0')} · ` : ''}{l.titulo}</b>
                <span>
                  {lider ? `Liderando: ${lider.nome ?? 'sem nome'} (#${lider.codigo_publico}${lider.cidade ? ` · ${lider.cidade}-${lider.uf}` : ''})` : 'Sem lances'}
                  {' · '}{l.qtd_lances} lance(s){l.preco_reserva != null ? (reservaOk ? ' · reserva atingida' : ' · abaixo da reserva') : ''}
                </span>
              </div>
              <div style={{ textAlign: 'right' }}>
                <div className="valor">{brl(Number(l.lance_atual ?? l.preco_inicial))}/cab</div>
                <div className="note">total {brl(Number(l.lance_atual ?? 0) * l.quantidade)}</div>
              </div>
              {l.status === 'agendado'
                ? <span className="etiqueta st-azul">Agendado · fecha {dataHora(l.termina_em)}</span>
                : <span className={`etiqueta ${ms < 600_000 ? 'st-laranja' : 'st-verde'}`}>{tempoRestante(ms)}</span>}
              {l.prorrogado && <span className="etiqueta st-laranja">Prorrogado {l.qtd_prorrogacoes}×</span>}
            </Link>
          );
        })}
      </div>
      <p className="note" style={{ marginTop: 14 }}>Para cancelar um lote (com motivo), abra o lote.</p>
    </>
  );
}
