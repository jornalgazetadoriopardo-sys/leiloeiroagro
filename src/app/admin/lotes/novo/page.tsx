import Link from 'next/link';
import { Suspense } from 'react';
import { obterEquipe } from '@/lib/admin';
import { Carregando, Restrito } from '../../Restrito';
import { opcoesLote } from '../dados';
import { FormLote } from '../FormLote';

export default function NovoLote({ searchParams }: PageProps<'/admin/lotes/novo'>) {
  return <Suspense fallback={<Carregando />}><Conteudo searchParams={searchParams} /></Suspense>;
}

async function Conteudo({ searchParams }: { searchParams: PageProps<'/admin/lotes/novo'>['searchParams'] }) {
  const [e, sp] = await Promise.all([obterEquipe(), searchParams]);
  if (!e) return <Restrito />;
  const { categorias, vendedores } = await opcoesLote(e);
  const vendedor = typeof sp.vendedor === 'string' ? sp.vendedor : undefined;
  return (
    <>
      <Link href="/admin/lotes" className="voltar">‹ Lotes</Link>
      <h1>Novo lote</h1>
      <p className="sub-titulo">Depois de salvar você envia o vídeo, as fotos e o laudo.</p>
      {vendedores.length === 0 && (
        <div className="banner b-orange" style={{ marginBottom: 14 }}>
          Cadastre primeiro o vendedor. <Link href="/admin/vendedores/novo" style={{ marginLeft: 8 }}>Cadastrar vendedor</Link>
        </div>
      )}
      <div style={{ maxWidth: 860 }}>
        <FormLote lote={{ vendedor_id: vendedor, data_pesagem: new Date().toISOString().slice(0, 10) }} categorias={categorias} vendedores={vendedores} bloqueado={false} />
      </div>
    </>
  );
}
