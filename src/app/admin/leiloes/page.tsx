import Link from 'next/link';
import { Suspense } from 'react';
import { dataHora, obterEquipe } from '@/lib/admin';
import { Carregando, Restrito } from '../Restrito';
import { FormLeilao } from './FormLeilao';

const ST: Record<string, [string, string]> = {
  rascunho: ['Em montagem', 'st-cinza'], agendado: ['Agendado', 'st-azul'], aberto: ['Aberto', 'st-verde-forte'],
  encerrado: ['Encerrado', 'st-cinza'], cancelado: ['Cancelado', 'st-cinza'],
};

export default function Leiloes() {
  return <Suspense fallback={<Carregando />}><Conteudo /></Suspense>;
}

async function Conteudo() {
  const e = await obterEquipe();
  if (!e) return <Restrito />;
  const { data } = await e.supabase.from('leiloes').select('id, titulo, abre_em, primeiro_fechamento_em, status, lotes(count)')
    .eq('tenant_id', e.tenant.id).order('criado_em', { ascending: false }).limit(100);
  return (
    <>
      <h1>Leilões</h1>
      <p className="sub-titulo">Crie o leilão, inclua os lotes prontos e agende.</p>
      <div className="duas-colunas">
        <div className="lista-admin">
          {(data ?? []).length === 0 && <div className="vazio">Nenhum leilão ainda.</div>}
          {(data ?? []).map((l) => {
            const [rotulo, classe] = ST[l.status] ?? [l.status, 'st-cinza'];
            const qtd = (l.lotes as unknown as { count: number }[])?.[0]?.count ?? 0;
            return (
              <Link key={l.id} href={`/admin/leiloes/${l.id}`} className="item-admin">
                <div className="principal"><b>{l.titulo}</b><span>{qtd} lote(s) · abre {dataHora(l.abre_em)} · 1º fecha {dataHora(l.primeiro_fechamento_em)}</span></div>
                <span className={`etiqueta ${classe}`}>{rotulo}</span>
              </Link>
            );
          })}
        </div>
        <FormLeilao />
      </div>
    </>
  );
}
