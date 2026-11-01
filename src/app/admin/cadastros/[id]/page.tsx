import Link from 'next/link';
import { notFound } from 'next/navigation';
import { Suspense } from 'react';
import { dataHora, obterEquipe } from '@/lib/admin';
import { mascaraCpfCnpj } from '@/lib/brasil';
import { analisarCadastro } from '../../acoes';
import { FormAcao } from '../../componentes';
import { Carregando, Restrito } from '../../Restrito';

const TIPO_DOC: Record<string, string> = {
  documento_foto: 'Documento com foto', comprovante_endereco: 'Comprovante de endereço', selfie: 'Selfie com documento',
};

export default function DetalheCadastro({ params }: PageProps<'/admin/cadastros/[id]'>) {
  return <Suspense fallback={<Carregando />}><Conteudo params={params} /></Suspense>;
}

async function Conteudo({ params }: { params: PageProps<'/admin/cadastros/[id]'>['params'] }) {
  const [e, { id }] = await Promise.all([obterEquipe(), params]);
  if (!e) return <Restrito />;
  const { data: u } = await e.supabase.from('usuarios').select('*').eq('id', id).eq('tenant_id', e.tenant.id).maybeSingle();
  if (!u) notFound();

  const [{ data: docs }, { data: hist }, { data: consent }] = await Promise.all([
    e.supabase.from('documentos').select('id, tipo, arquivo_url, status, criado_em').eq('dono_id', id).order('criado_em'),
    e.supabase.from('verificacoes').select('tipo, resultado, observacao, criado_em').eq('usuario_id', id).order('criado_em', { ascending: false }),
    e.supabase.from('consentimentos').select('tipo, versao, criado_em').eq('usuario_id', id).order('criado_em', { ascending: false }),
  ]);
  // Links temporários (10 min) para os documentos privados — seção 14
  const links = await Promise.all((docs ?? []).map(async (d) => {
    const { data } = await e.supabase.storage.from('documentos').createSignedUrl(d.arquivo_url, 600);
    return { ...d, url: data?.signedUrl ?? null };
  }));
  const podeDecidir = e.admin && u.cadastro_enviado_em && ['pendente', 'divergente', 'verificado', 'recusado'].includes(u.status_verificacao);

  return (
    <>
      <Link href="/admin/cadastros" className="voltar">‹ Cadastros</Link>
      <h1>{u.nome ?? 'Sem nome'}</h1>
      <p className="sub-titulo">Comprador #{u.codigo_publico} · status: <b>{u.status_verificacao}</b></p>
      <div className="duas-colunas">
        <div>
          <div className="bloco">
            <h2>Dados</h2>
            <dl className="dados-lista" style={{ marginTop: 0 }}>
              <div><dt>CPF/CNPJ</dt><dd>{u.cpf_cnpj ? mascaraCpfCnpj(u.cpf_cnpj) : '—'}</dd></div>
              <div><dt>Celular</dt><dd>{u.celular}</dd></div>
              <div><dt>Cidade</dt><dd>{u.cidade ?? '—'} – {u.uf ?? ''}</dd></div>
              <div><dt>Inscrição estadual</dt><dd>{u.inscricao_estadual ?? '—'}</dd></div>
              <div><dt>E-mail</dt><dd>{u.email ?? '—'}</dd></div>
              <div><dt>Referência bancária/comercial</dt><dd style={{ whiteSpace: 'pre-wrap' }}>{u.referencia_bancaria ?? '—'}</dd></div>
              <div><dt>Avisos no WhatsApp</dt><dd>{u.optin_whatsapp ? 'Autorizou' : 'Não autorizou'}</dd></div>
              <div><dt>Enviado em</dt><dd>{dataHora(u.cadastro_enviado_em)}</dd></div>
            </dl>
          </div>
          <div className="bloco">
            <h2>Documentos</h2>
            {links.length === 0 && <p className="note">Nenhum documento enviado.</p>}
            {links.map((d) => (
              <div key={d.id} className="doc-admin">
                <div><b>{TIPO_DOC[d.tipo] ?? d.tipo}</b><div className="note">{dataHora(d.criado_em)}</div></div>
                {d.url ? <a className="btn-ghost" href={d.url} target="_blank" rel="noreferrer">Abrir</a> : <span className="note">Arquivo indisponível</span>}
              </div>
            ))}
          </div>
        </div>
        <div>
          <div className="bloco">
            <h2>Decisão</h2>
            {!e.admin && <p className="note">Só o administrador aprova cadastros.</p>}
            {!u.cadastro_enviado_em && <p className="note">O usuário ainda não terminou o cadastro.</p>}
            {podeDecidir && (
              <>
                <FormAcao acao={analisarCadastro} botao="Aprovar cadastro" classeBotao="btn-aprovar">
                  <input type="hidden" name="usuario_id" value={u.id} />
                  <input type="hidden" name="decisao" value="aprovar" />
                </FormAcao>
                <FormAcao acao={analisarCadastro} botao="Pedir ajuste" classeBotao="btn-ghost btn-bloco" className="campo">
                  <input type="hidden" name="usuario_id" value={u.id} />
                  <input type="hidden" name="decisao" value="pedir_ajuste" />
                  <label htmlFor="obs-ajuste">O que precisa ajustar? (o usuário vê esta mensagem)</label>
                  <textarea id="obs-ajuste" name="observacao" placeholder="Ex.: comprovante de endereço ilegível, envie outro." />
                </FormAcao>
                <FormAcao acao={analisarCadastro} botao="Recusar cadastro" classeBotao="btn-perigo btn-bloco" className="campo"
                  confirmar="Recusar este cadastro?">
                  <input type="hidden" name="usuario_id" value={u.id} />
                  <input type="hidden" name="decisao" value="recusar" />
                  <label htmlFor="obs-recusa">Motivo da recusa</label>
                  <textarea id="obs-recusa" name="observacao" />
                </FormAcao>
              </>
            )}
          </div>
          <div className="bloco">
            <h2>Histórico</h2>
            {(hist ?? []).map((h, i) => (
              <div key={i} className="doc-admin"><div><b>{h.resultado}</b> · {h.tipo}<div className="note">{h.observacao}</div></div><span className="note">{dataHora(h.criado_em)}</span></div>
            ))}
            {(consent ?? []).length > 0 && (
              <p className="note" style={{ marginTop: 10 }}>
                Aceites: {(consent ?? []).map((c) => `${c.tipo} (v${c.versao}, ${dataHora(c.criado_em)})`).join(' · ')}
              </p>
            )}
          </div>
        </div>
      </div>
    </>
  );
}
