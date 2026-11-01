import Link from 'next/link';
import { notFound } from 'next/navigation';
import { Suspense } from 'react';
import { dataHora, obterEquipe, paraLocalBrasilia, STATUS_LOTE } from '@/lib/admin';
import { brl } from '@/lib/formato';
import { agendarLeilao, incluirLote } from '../../acoes';
import { FormAcao } from '../../componentes';
import { Carregando, Restrito } from '../../Restrito';
import { FormLeilao } from '../FormLeilao';

export default function DetalheLeilao({ params, searchParams }: PageProps<'/admin/leiloes/[id]'>) {
  return <Suspense fallback={<Carregando />}><Conteudo params={params} searchParams={searchParams} /></Suspense>;
}

async function Conteudo({ params, searchParams }: Pick<PageProps<'/admin/leiloes/[id]'>, 'params' | 'searchParams'>) {
  const [e, { id }, sp] = await Promise.all([obterEquipe(), params, searchParams]);
  if (!e) return <Restrito />;
  const { data: leilao } = await e.supabase.from('leiloes').select('*').eq('id', id).eq('tenant_id', e.tenant.id).maybeSingle();
  if (!leilao) notFound();
  const [{ data: doLeilao }, { data: prontos }] = await Promise.all([
    e.supabase.from('lotes').select('id, numero, ordem, titulo, quantidade, preco_inicial, status, termina_em').eq('leilao_id', id).order('ordem'),
    e.supabase.from('lotes').select('id, titulo, quantidade, preco_inicial').eq('tenant_id', e.tenant.id).eq('status', 'aprovado').is('leilao_id', null),
  ]);
  const montagem = ['rascunho', 'agendado'].includes(leilao.status);
  const intervaloMin = (() => {
    const m = String(leilao.intervalo_fechamento ?? '').match(/(\d+):(\d+):(\d+)/);
    return m ? Number(m[1]) * 60 + Number(m[2]) : 2;
  })();

  return (
    <>
      <Link href="/admin/leiloes" className="voltar">‹ Leilões</Link>
      <h1>{leilao.titulo}</h1>
      <p className="sub-titulo">Status: <b>{leilao.status}</b> · abre {dataHora(leilao.abre_em)} · 1º lote fecha {dataHora(leilao.primeiro_fechamento_em)}</p>
      {sp.salvo && <div className="banner b-green" style={{ marginBottom: 14 }}>Leilão salvo.</div>}
      <div className="duas-colunas">
        <div>
          <div className="bloco">
            <h2>Lotes neste leilão ({(doLeilao ?? []).length})</h2>
            {(doLeilao ?? []).length === 0 && <p className="note">Inclua lotes prontos ao lado.</p>}
            <div className="lista-admin">
              {(doLeilao ?? []).map((l) => (
                <div key={l.id} className="item-admin">
                  <div className="principal">
                    <b>{l.ordem}. {l.titulo}</b>
                    <span>{l.quantidade} cab · inicial {brl(Number(l.preco_inicial))}/cab{l.termina_em ? ` · fecha ${dataHora(l.termina_em)}` : ''}</span>
                  </div>
                  <span className={`etiqueta ${STATUS_LOTE[l.status]?.classe}`}>{STATUS_LOTE[l.status]?.rotulo ?? l.status}</span>
                  {montagem && ['aprovado', 'agendado'].includes(l.status) && (
                    <FormAcao acao={incluirLote} botao="Retirar" classeBotao="btn-ghost">
                      <input type="hidden" name="lote_id" value={l.id} />
                    </FormAcao>
                  )}
                </div>
              ))}
            </div>
            {montagem && (doLeilao ?? []).length > 0 && (
              <FormAcao acao={agendarLeilao} botao={leilao.status === 'agendado' ? 'Reagendar horários' : 'Agendar leilão'} classeBotao="btn-aprovar"
                confirmar="Agendar? Os lotes abrem sozinhos no horário de abertura.">
                <input type="hidden" name="leilao_id" value={leilao.id} />
              </FormAcao>
            )}
          </div>
          {montagem && (
            <div className="bloco">
              <h2>Lotes prontos para incluir</h2>
              {(prontos ?? []).length === 0 && <p className="note">Nenhum lote aprovado sem leilão. <Link href="/admin/lotes?filtro=preparacao">Ver lotes em preparação</Link></p>}
              <div className="lista-admin">
                {(prontos ?? []).map((l) => (
                  <div key={l.id} className="item-admin">
                    <div className="principal"><b>{l.titulo}</b><span>{l.quantidade} cab · inicial {brl(Number(l.preco_inicial))}/cab</span></div>
                    <FormAcao acao={incluirLote} botao="Incluir" classeBotao="btn-primary">
                      <input type="hidden" name="lote_id" value={l.id} />
                      <input type="hidden" name="leilao_id" value={leilao.id} />
                    </FormAcao>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
        {montagem
          ? <FormLeilao leilao={{ id: leilao.id, titulo: leilao.titulo, descricao: leilao.descricao, abre: paraLocalBrasilia(leilao.abre_em), fecha: paraLocalBrasilia(leilao.primeiro_fechamento_em), intervaloMin }} />
          : <div className="bloco"><h2>Leilão em andamento ou encerrado</h2><p className="note">Acompanhe em <Link href="/admin/ao-vivo">Ao vivo</Link>.</p></div>}
      </div>
    </>
  );
}
