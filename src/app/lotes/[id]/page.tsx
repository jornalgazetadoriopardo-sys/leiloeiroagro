import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { Suspense } from 'react';
import { Cabecalho } from '@/components/Cabecalho';
import { SelosConfianca } from '@/components/Selos';
import { MidiasLote } from '@/components/MidiasLote';
import { PainelLance } from '@/components/PainelLance';
import { brl, diaMes, faixaIdade, FRETE, plural } from '@/lib/formato';
import { carregarLote } from '@/lib/lote';
import type { LotePublico, StatusVerificacao } from '@/lib/tipos';

export const metadata: Metadata = { title: 'Lote – Pregão do Campo' };

// Página do lote — seção 11.1 (2)
export default function PaginaDoLote({ params }: PageProps<'/lotes/[id]'>) {
  return (
    <Suspense fallback={<main className="wrap" style={{ paddingTop: 32 }}><div className="skeleton" style={{ minHeight: 480 }} /></main>}>
      <Conteudo params={params} />
    </Suspense>
  );
}

async function Conteudo({ params }: { params: PageProps<'/lotes/[id]'>['params'] }) {
  const { id } = await params;
  const dados = await carregarLote(id);
  if (!dados) notFound();
  const { lote, tenant, visitante } = dados;
  const numero = `Lote ${String(lote.numero ?? '').padStart(2, '0')}`;
  const statusCabecalho = ['visitante', 'sem_cadastro', 'cadastro_incompleto'].includes(visitante) ? null : (visitante as StatusVerificacao);

  return (
    <>
      {dados.demo && <div className="demo-aviso" role="note">Modo demonstração: dados ilustrativos.</div>}
      <Cabecalho nome={tenant?.nome ?? 'Pregão do Campo'} status={statusCabecalho} />
      <main className="wrap" style={{ paddingTop: 12, paddingBottom: 48 }}>
        <Link href="/#lotes" className="voltar">‹ Todos os lotes</Link>
        <div className="lote-grid">
          <div className="f-lot lote-midia">
            <MidiasLote midias={dados.midias} numero={numero} />
            <div className="f-info" style={{ paddingBottom: 18 }}>
              <h1 style={{ margin: 0, fontWeight: 800, fontSize: 26, lineHeight: 1.15 }}>{lote.titulo}</h1>
              <p className="where">{lote.cidade} – {lote.uf} · Vendedor: {lote.vendedor_rotulo.split(' · ')[0]}</p>
            </div>
          </div>
          <div className="lote-painel">
            <PainelLance lote={lote} historico={dados.historico} meuTeto={dados.meuTeto} config={dados.config}
              visitante={visitante} meuCodigo={dados.meuCodigo} servidorAgora={dados.servidorAgora} demo={dados.demo} />
          </div>
          <div className="f-lot lote-info">
            <div className="f-info" style={{ paddingTop: 4 }}>
              <SelosConfianca />
              <FichaTecnica lote={lote} />
            </div>
          </div>
        </div>
      </main>
    </>
  );
}

const SEXO = { macho: 'Machos', femea: 'Fêmeas', misto: 'Machos e fêmeas' } as const;

function FichaTecnica({ lote }: { lote: LotePublico }) {
  const s = lote.sanidade ?? {};
  return (
    <>
      <dl>
        <div><dt>Categoria</dt><dd style={{ textTransform: 'capitalize' }}>{lote.categoria}</dd></div>
        <div><dt>Raça</dt><dd>{lote.raca}</dd></div>
        <div><dt>Quantidade</dt><dd>{plural(lote.quantidade, 'cabeça', 'cabeças')}</dd></div>
        <div><dt>Sexo</dt><dd>{SEXO[lote.sexo]}</dd></div>
        <div><dt>Peso médio</dt><dd>{Number(lote.peso_medio).toLocaleString('pt-BR')} kg · balança em {diaMes(lote.data_pesagem)}</dd></div>
        <div><dt>Idade</dt><dd>{faixaIdade(lote.idade_min, lote.idade_max)}</dd></div>
      </dl>
      <div className="ficha-sec">
        <dl>
          <div><dt>Vacinas</dt><dd>{s.vacinas || 'Ver laudo'}</dd></div>
          <div><dt>Vermifugação</dt><dd>{s.vermifugacao || 'Ver laudo'}</dd></div>
          {s.observacoes && <div style={{ gridColumn: '1 / -1' }}><dt>Observações</dt><dd>{s.observacoes}</dd></div>}
        </dl>
      </div>
      <div className="ficha-sec">
        <dl>
          <div><dt>Origem</dt><dd>{lote.cidade} – {lote.uf}</dd></div>
          <div><dt>Retirada</dt><dd>Até {lote.retirada_prazo} dias · {FRETE[lote.frete]}</dd></div>
          <div><dt>Quebra de peso aceita</dt><dd>{lote.tolerancia_quebra != null ? `até ${Number(lote.tolerancia_quebra).toLocaleString('pt-BR')}%` : 'Conforme regras'}</dd></div>
          <div><dt>Incremento mínimo</dt><dd>{brl(lote.incremento)}/cab</dd></div>
          <div><dt>Documentos</dt><dd>GTA e nota fiscal na venda</dd></div>
          <div><dt>Pagamento</dt><dd>À vista, conforme instruções após o arremate</dd></div>
        </dl>
      </div>
    </>
  );
}
