import Link from 'next/link';
import { notFound } from 'next/navigation';
import { Suspense } from 'react';
import { obterEquipe, PENDENCIA, STATUS_LOTE } from '@/lib/admin';
import { aprovarLote, cancelarLote } from '../../acoes';
import { FormAcao } from '../../componentes';
import { Carregando, Restrito } from '../../Restrito';
import { opcoesLote } from '../dados';
import { FormLote, type LoteEditavel } from '../FormLote';
import { MidiasAdmin } from '../MidiasAdmin';

export default function EditarLote({ params, searchParams }: PageProps<'/admin/lotes/[id]'>) {
  return <Suspense fallback={<Carregando />}><Conteudo params={params} searchParams={searchParams} /></Suspense>;
}

async function Conteudo({ params, searchParams }: Pick<PageProps<'/admin/lotes/[id]'>, 'params' | 'searchParams'>) {
  const [e, { id }, sp] = await Promise.all([obterEquipe(), params, searchParams]);
  if (!e) return <Restrito />;
  const { data: lote } = await e.supabase.from('lotes').select('*').eq('id', id).eq('tenant_id', e.tenant.id).maybeSingle();
  if (!lote) notFound();
  const [{ data: midias }, { data: pend }, opcoes] = await Promise.all([
    e.supabase.from('midias_lote').select('id, tipo, url, ordem').eq('lote_id', id).order('tipo').order('ordem'),
    e.supabase.rpc('pendencias_lote', { p_lote_id: id }),
    opcoesLote(e),
  ]);
  const st = STATUS_LOTE[lote.status];
  const editavel = ['rascunho', 'em_vistoria', 'aprovado', 'agendado'].includes(lote.status);
  const pendencias = (pend ?? []) as string[];

  return (
    <>
      <Link href="/admin/lotes" className="voltar">‹ Lotes</Link>
      <div className="row-between" style={{ alignItems: 'flex-start' }}>
        <div>
          <h1>{lote.titulo}</h1>
          <p className="sub-titulo"><span className={`etiqueta ${st?.classe}`}>{st?.rotulo ?? lote.status}</span>
            {lote.status !== 'rascunho' && <> · <Link href={`/lotes/${lote.id}`}>ver no site</Link></>}</p>
        </div>
      </div>
      {sp.salvo && <div className="banner b-green" style={{ marginBottom: 14 }}>Lote salvo.</div>}
      {lote.motivo_cancelamento && <div className="banner b-gray" style={{ marginBottom: 14 }}>Cancelado: {lote.motivo_cancelamento}</div>}
      <div className="duas-colunas">
        <FormLote lote={lote as LoteEditavel} categorias={opcoes.categorias} vendedores={opcoes.vendedores} bloqueado={!editavel} />
        <div>
          {['rascunho', 'em_vistoria'].includes(lote.status) && (
            <div className="bloco">
              <h2>Aprovação</h2>
              {pendencias.length > 0
                ? <div className="acoes-linha" style={{ marginBottom: 6 }}>{pendencias.map((p) => <span key={p} className="etiqueta st-laranja">{PENDENCIA[p]}</span>)}</div>
                : <p className="msg-ok">Tudo pronto para aprovar.</p>}
              <FormAcao acao={aprovarLote} botao="Aprovar lote" classeBotao="btn-aprovar">
                <input type="hidden" name="lote_id" value={lote.id} />
              </FormAcao>
            </div>
          )}
          {lote.status === 'aprovado' && (
            <div className="bloco"><h2>Pronto</h2><p className="note">Inclua este lote num leilão em <Link href="/admin/leiloes">Leilões</Link>.</p></div>
          )}
          <MidiasAdmin tenantId={e.tenant.id} loteId={lote.id} midias={midias ?? []} bloqueado={!editavel} />
          {e.admin && [...['rascunho', 'em_vistoria', 'aprovado', 'agendado', 'aberto']].includes(lote.status) && (
            <div className="bloco">
              <h2>Cancelar lote</h2>
              <FormAcao acao={cancelarLote} botao="Cancelar lote" classeBotao="btn-perigo btn-bloco" className="campo"
                confirmar="Cancelar este lote? Quem deu lance será avisado.">
                <input type="hidden" name="lote_id" value={lote.id} />
                <label htmlFor="motivo">Motivo (fica registrado)</label>
                <textarea id="motivo" name="motivo" />
              </FormAcao>
            </div>
          )}
        </div>
      </div>
    </>
  );
}
