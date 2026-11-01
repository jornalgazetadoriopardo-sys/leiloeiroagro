import Link from 'next/link';
import { Suspense } from 'react';
import { obterEquipe, PENDENCIA, STATUS_LOTE } from '@/lib/admin';
import { brl } from '@/lib/formato';
import { Carregando, Restrito } from '../Restrito';

const FILTROS = [
  { id: 'preparacao', rotulo: 'Em preparação', status: ['rascunho', 'em_vistoria'] },
  { id: 'prontos', rotulo: 'Prontos', status: ['aprovado'] },
  { id: 'leilao', rotulo: 'Agendados / abertos', status: ['agendado', 'aberto'] },
  { id: 'encerrados', rotulo: 'Encerrados', status: ['encerrado', 'vendido', 'nao_vendido', 'aguardando_pagamento', 'pago_em_garantia', 'concluido'] },
  { id: 'cancelados', rotulo: 'Cancelados', status: ['cancelado'] },
];

export default function Lotes({ searchParams }: PageProps<'/admin/lotes'>) {
  return <Suspense fallback={<Carregando />}><Conteudo searchParams={searchParams} /></Suspense>;
}

async function Conteudo({ searchParams }: { searchParams: PageProps<'/admin/lotes'>['searchParams'] }) {
  const [e, sp] = await Promise.all([obterEquipe(), searchParams]);
  if (!e) return <Restrito />;
  const filtro = FILTROS.find((f) => f.id === sp.filtro) ?? FILTROS[0];
  const { data: lotes } = await e.supabase.from('lotes')
    .select('id, numero, titulo, quantidade, preco_inicial, cidade, uf, status, criado_em')
    .eq('tenant_id', e.tenant.id).in('status', filtro.status).order('criado_em', { ascending: false }).limit(200);
  const pend = await Promise.all((lotes ?? []).map(async (l) =>
    ['rascunho', 'em_vistoria'].includes(l.status)
      ? ((await e.supabase.rpc('pendencias_lote', { p_lote_id: l.id })).data as string[] | null) ?? []
      : []));

  return (
    <>
      <div className="row-between" style={{ alignItems: 'flex-start' }}>
        <div><h1>Lotes</h1><p className="sub-titulo">Cadastre, envie mídias e aprove para entrar num leilão.</p></div>
        <Link href="/admin/lotes/novo" className="btn-primary" style={{ padding: '0 20px' }}>+ Novo lote</Link>
      </div>
      <div className="filtros-admin">
        {FILTROS.map((f) => <Link key={f.id} href={`/admin/lotes?filtro=${f.id}`} className={f.id === filtro.id ? 'on' : ''}>{f.rotulo}</Link>)}
      </div>
      <div className="lista-admin">
        {(lotes ?? []).length === 0 && <div className="vazio">Nenhum lote aqui.</div>}
        {(lotes ?? []).map((l, i) => {
          const st = STATUS_LOTE[l.status];
          return (
            <Link key={l.id} href={`/admin/lotes/${l.id}`} className="item-admin">
              <div className="principal">
                <b>{l.numero ? `Lote ${String(l.numero).padStart(2, '0')} · ` : ''}{l.titulo}</b>
                <span>{l.cidade}-{l.uf} · inicial {brl(Number(l.preco_inicial))}/cab</span>
              </div>
              {pend[i].length > 0
                ? pend[i].map((p) => <span key={p} className="etiqueta st-laranja">{PENDENCIA[p]}</span>)
                : <span className={`etiqueta ${st?.classe}`}>{st?.rotulo ?? l.status}</span>}
            </Link>
          );
        })}
      </div>
    </>
  );
}
