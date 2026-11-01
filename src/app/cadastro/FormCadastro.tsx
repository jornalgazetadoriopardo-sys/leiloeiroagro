'use client';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useRef, useState, useTransition } from 'react';
import { IconeAlerta, IconeOk } from '@/components/Icones';
import { enviarCadastro, type DadosCadastro } from '@/lib/acoes-conta';
import { cpfCnpjValido, mascaraCpfCnpj, UFS } from '@/lib/brasil';
import { comprimirImagem } from '@/lib/imagem';
import type { MeuCadastro } from '@/lib/sessao';
import { clienteNavegador } from '@/lib/supabase/client';

export interface DocumentoEnviado {
  id: string;
  tipo: string;
  status: 'enviado' | 'aprovado' | 'recusado';
  criado_em: string;
}

interface Props {
  tenantId: string;
  cadastro: MeuCadastro;
  documentos: DocumentoEnviado[];
  selfieObrigatoria: boolean;
}

const PASSOS = ['Seus dados', 'Documentos', 'Referência', 'Confirmação'] as const;

// Em qual passo cada campo aparece (para levar o usuário ao erro vindo do servidor)
const PASSO_DO_CAMPO: Record<string, number> = {
  nome: 0, cpf_cnpj: 0, cidade: 0, uf: 0, email: 0, inscricao_estadual: 0,
  documento_foto: 1, comprovante_endereco: 1, selfie: 1,
  referencia_bancaria: 2,
  aceite_termos: 3, aceite_regras: 3, aceite_privacidade: 3,
};

const MENSAGENS: Record<string, string> = {
  nome: 'Informe nome e sobrenome.',
  cpf_cnpj: 'CPF ou CNPJ inválido. Confira os números.',
  cidade: 'Informe a cidade.',
  uf: 'Escolha o estado.',
  email: 'E-mail inválido.',
  documento_foto: 'Envie um documento com foto.',
  comprovante_endereco: 'Envie um comprovante de endereço.',
  selfie: 'Envie uma selfie segurando o documento.',
  referencia_bancaria: 'Informe uma referência bancária ou comercial.',
  aceite_termos: 'É preciso aceitar os termos de uso.',
  aceite_regras: 'É preciso aceitar as regras do leilão.',
  aceite_privacidade: 'É preciso aceitar a política de privacidade.',
};

export function FormCadastro({ tenantId, cadastro, documentos, selfieObrigatoria }: Props) {
  const router = useRouter();
  const [passo, setPasso] = useState(0);
  const [erros, setErros] = useState<string[]>([]);
  const [msgGeral, setMsgGeral] = useState('');
  const [enviando, iniciar] = useTransition();
  const [dados, setDados] = useState<DadosCadastro>({
    nome: cadastro.nome ?? '',
    cpf_cnpj: cadastro.cpf_cnpj ? mascaraCpfCnpj(cadastro.cpf_cnpj) : '',
    cidade: cadastro.cidade ?? '',
    uf: cadastro.uf ?? '',
    inscricao_estadual: cadastro.inscricao_estadual ?? '',
    email: cadastro.email ?? '',
    referencia_bancaria: cadastro.referencia_bancaria ?? '',
    aceite_termos: false,
    aceite_regras: false,
    aceite_privacidade: false,
    optin_whatsapp: cadastro.optin_whatsapp,
  });
  const [docs, setDocs] = useState(documentos);
  const temDoc = (tipo: string) => docs.some((d) => d.tipo === tipo && d.status !== 'recusado');
  const muda = <K extends keyof DadosCadastro>(k: K, v: DadosCadastro[K]) => {
    setDados((d) => ({ ...d, [k]: v }));
    setErros((e) => e.filter((x) => x !== k));
  };

  function validarPasso(p: number): string[] {
    const f: string[] = [];
    if (p === 0) {
      if (!/\S+\s+\S+/.test(dados.nome.trim())) f.push('nome');
      if (!cpfCnpjValido(dados.cpf_cnpj)) f.push('cpf_cnpj');
      if (dados.cidade.trim().length < 2) f.push('cidade');
      if (!dados.uf) f.push('uf');
      if (dados.email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(dados.email.trim())) f.push('email');
    }
    if (p === 1) {
      if (!temDoc('documento_foto')) f.push('documento_foto');
      if (!temDoc('comprovante_endereco')) f.push('comprovante_endereco');
      if (selfieObrigatoria && !temDoc('selfie')) f.push('selfie');
    }
    if (p === 2 && dados.referencia_bancaria.trim().length < 5) f.push('referencia_bancaria');
    if (p === 3) {
      if (!dados.aceite_termos) f.push('aceite_termos');
      if (!dados.aceite_regras) f.push('aceite_regras');
      if (!dados.aceite_privacidade) f.push('aceite_privacidade');
    }
    return f;
  }

  function avancar() {
    const f = validarPasso(passo);
    setErros(f);
    setMsgGeral('');
    if (f.length === 0) {
      setPasso((p) => p + 1);
      window.scrollTo({ top: 0 });
    }
  }

  function enviar() {
    const f = validarPasso(3);
    setErros(f);
    if (f.length) return;
    iniciar(async () => {
      const r = await enviarCadastro(dados);
      if (r.ok) {
        router.replace('/conta?enviado=1');
        router.refresh();
        return;
      }
      setMsgGeral(r.mensagem ?? 'Não foi possível enviar.');
      if (r.campos?.length) {
        setErros(r.campos);
        setPasso(Math.min(...r.campos.map((c) => PASSO_DO_CAMPO[c] ?? 3)));
      }
    });
  }

  const erro = (k: string) => erros.includes(k);

  return (
    <div className="cartao">
      <ol className="passos" aria-hidden="true">
        {PASSOS.map((p, i) => <li key={p} className={i <= passo ? 'feito' : ''} />)}
      </ol>
      <div className="passo-rotulo">Passo {passo + 1} de {PASSOS.length} · {PASSOS[passo]}</div>

      {cadastro.status_verificacao === 'divergente' && cadastro.observacao_analise && passo === 0 && (
        <div className="banner b-orange" style={{ marginTop: 14, alignItems: 'flex-start' }}>
          <IconeAlerta tamanho={20} />
          <span>A leiloeira pediu um ajuste: {cadastro.observacao_analise}</span>
        </div>
      )}

      {passo === 0 && (
        <>
          <h1 style={{ marginTop: 10 }}>Seus dados</h1>
          <p className="intro">Usamos estes dados só para verificar seu cadastro. Outros compradores não veem.</p>
          <Campo id="nome" rotulo="Nome completo" erro={erro('nome')}>
            <input id="nome" autoComplete="name" value={dados.nome} onChange={(e) => muda('nome', e.target.value)} />
          </Campo>
          <Campo id="cpf_cnpj" rotulo="CPF ou CNPJ" erro={erro('cpf_cnpj')}>
            <input id="cpf_cnpj" inputMode="numeric" value={dados.cpf_cnpj} placeholder="000.000.000-00"
              onChange={(e) => muda('cpf_cnpj', mascaraCpfCnpj(e.target.value))} />
          </Campo>
          <div className="linha-2">
            <Campo id="cidade" rotulo="Cidade" erro={erro('cidade')}>
              <input id="cidade" autoComplete="address-level2" value={dados.cidade} onChange={(e) => muda('cidade', e.target.value)} />
            </Campo>
            <Campo id="uf" rotulo="UF" erro={erro('uf')}>
              <select id="uf" value={dados.uf} onChange={(e) => muda('uf', e.target.value)}>
                <option value="">—</option>
                {UFS.map((u) => <option key={u}>{u}</option>)}
              </select>
            </Campo>
          </div>
          <Campo id="inscricao_estadual" rotulo="Inscrição estadual de produtor" ajuda="Se tiver." erro={false}>
            <input id="inscricao_estadual" value={dados.inscricao_estadual} onChange={(e) => muda('inscricao_estadual', e.target.value)} />
          </Campo>
          <Campo id="email" rotulo="E-mail" ajuda="Opcional. Para receber recibos e documentos." erro={erro('email')}>
            <input id="email" type="email" autoComplete="email" inputMode="email" value={dados.email} onChange={(e) => muda('email', e.target.value)} />
          </Campo>
        </>
      )}

      {passo === 1 && (
        <>
          <h1 style={{ marginTop: 10 }}>Documentos</h1>
          <p className="intro">Tire uma foto nítida ou envie um PDF. Os arquivos ficam guardados com acesso só da leiloeira.</p>
          <EnvioDocumento tipo="documento_foto" titulo="Documento com foto" descricao="RG, CNH ou carteira profissional"
            tenantId={tenantId} usuarioId={cadastro.id} docs={docs} erro={erro('documento_foto')}
            aoEnviar={(d) => { setDocs((x) => [...x, d]); setErros((e) => e.filter((k) => k !== d.tipo)); }} />
          <EnvioDocumento tipo="comprovante_endereco" titulo="Comprovante de endereço" descricao="Conta de luz, água ou telefone recente"
            tenantId={tenantId} usuarioId={cadastro.id} docs={docs} erro={erro('comprovante_endereco')}
            aoEnviar={(d) => { setDocs((x) => [...x, d]); setErros((e) => e.filter((k) => k !== d.tipo)); }} />
          <EnvioDocumento tipo="selfie" titulo={selfieObrigatoria ? 'Selfie com o documento' : 'Selfie com o documento (opcional)'}
            descricao="Foto do seu rosto segurando o documento" tenantId={tenantId} usuarioId={cadastro.id} docs={docs}
            erro={erro('selfie')} camera
            aoEnviar={(d) => { setDocs((x) => [...x, d]); setErros((e) => e.filter((k) => k !== d.tipo)); }} />
        </>
      )}

      {passo === 2 && (
        <>
          <h1 style={{ marginTop: 10 }}>Referência</h1>
          <p className="intro">Uma referência bancária ou comercial ajuda a aprovar seu cadastro mais rápido.</p>
          <Campo id="referencia_bancaria" rotulo="Referência bancária ou comercial" erro={erro('referencia_bancaria')}
            ajuda="Ex.: Banco do Brasil, agência 1234, cliente desde 2010. Ou uma casa agropecuária onde você compra.">
            <textarea id="referencia_bancaria" value={dados.referencia_bancaria} onChange={(e) => muda('referencia_bancaria', e.target.value)} />
          </Campo>
        </>
      )}

      {passo === 3 && (
        <>
          <h1 style={{ marginTop: 10 }}>Confirmação</h1>
          <p className="intro">Leia e aceite para enviar seu cadastro para análise.</p>
          <Aceite marcado={dados.aceite_termos} erro={erro('aceite_termos')} onChange={(v) => muda('aceite_termos', v)}>
            Li e aceito os <Link href="/termos#termos" target="_blank">termos de uso</Link>.
          </Aceite>
          <Aceite marcado={dados.aceite_regras} erro={erro('aceite_regras')} onChange={(v) => muda('aceite_regras', v)}>
            Li e aceito as <Link href="/termos#regras" target="_blank">regras do leilão</Link>. Sei que o lance vencedor obriga a compra.
          </Aceite>
          <Aceite marcado={dados.aceite_privacidade} erro={erro('aceite_privacidade')} onChange={(v) => muda('aceite_privacidade', v)}>
            Li e aceito a <Link href="/termos#privacidade" target="_blank">política de privacidade</Link>.
          </Aceite>
          <Aceite marcado={dados.optin_whatsapp} erro={false} onChange={(v) => muda('optin_whatsapp', v)}>
            <b>Quero receber avisos no WhatsApp</b> (lance coberto, fim do lote, arremate e cadastro aprovado).
            Você pode cancelar quando quiser respondendo SAIR.
          </Aceite>
        </>
      )}

      <div role="alert" aria-live="assertive">
        {erros.length > 0 && (
          <div className="msg-erro" style={{ marginTop: 16 }}>
            <IconeAlerta />
            <span>{erros.map((k) => MENSAGENS[k] ?? 'Confira os dados.').filter((m, i, a) => a.indexOf(m) === i).join(' ')}</span>
          </div>
        )}
        {msgGeral && erros.length === 0 && <div className="msg-erro" style={{ marginTop: 16 }}><IconeAlerta />{msgGeral}</div>}
      </div>

      <div className="navegacao">
        {passo > 0 && (
          <button type="button" className="btn-ghost" onClick={() => { setPasso((p) => p - 1); setErros([]); }}>Voltar</button>
        )}
        {passo < PASSOS.length - 1 ? (
          <button type="button" className="btn-primary" onClick={avancar}>Continuar</button>
        ) : (
          <button type="button" className="btn-primary" onClick={enviar} disabled={enviando}>
            {enviando ? 'Enviando…' : 'Enviar cadastro'}
          </button>
        )}
      </div>
    </div>
  );
}

function Campo({ id, rotulo, ajuda, erro, children }: { id: string; rotulo: string; ajuda?: string; erro: boolean; children: React.ReactNode }) {
  return (
    <div className={`campo${erro ? ' erro' : ''}`}>
      <label htmlFor={id}>{rotulo}</label>
      {ajuda && <span className="ajuda">{ajuda}</span>}
      {children}
    </div>
  );
}

function Aceite({ marcado, erro, onChange, children }: { marcado: boolean; erro: boolean; onChange: (v: boolean) => void; children: React.ReactNode }) {
  return (
    <label className={`aceite${erro ? ' erro' : ''}`}>
      <input type="checkbox" checked={marcado} onChange={(e) => onChange(e.target.checked)} />
      <span>{children}</span>
    </label>
  );
}

function EnvioDocumento({ tipo, titulo, descricao, tenantId, usuarioId, docs, erro, camera, aoEnviar }: {
  tipo: string; titulo: string; descricao: string; tenantId: string; usuarioId: string;
  docs: DocumentoEnviado[]; erro: boolean; camera?: boolean; aoEnviar: (d: DocumentoEnviado) => void;
}) {
  const entrada = useRef<HTMLInputElement>(null);
  const [estado, setEstado] = useState<'parado' | 'enviando' | 'falhou'>('parado');
  const enviado = docs.filter((d) => d.tipo === tipo && d.status !== 'recusado').at(-1);
  const recusado = !enviado && docs.some((d) => d.tipo === tipo && d.status === 'recusado');

  async function escolher(e: React.ChangeEvent<HTMLInputElement>) {
    const original = e.target.files?.[0];
    e.target.value = '';
    if (!original) return;
    if (original.size > 10 * 1024 * 1024) { setEstado('falhou'); return; }
    setEstado('enviando');
    try {
      const arquivo = await comprimirImagem(original);
      const ext = (arquivo.name.split('.').pop() || 'jpg').toLowerCase().replace(/[^a-z0-9]/g, '');
      const caminho = `${tenantId}/${usuarioId}/${tipo}-${Date.now()}.${ext}`;
      const supabase = clienteNavegador();
      const up = await supabase.storage.from('documentos').upload(caminho, arquivo, { contentType: arquivo.type, upsert: false });
      if (up.error) throw up.error;
      const { data, error } = await supabase.from('documentos')
        .insert({ tenant_id: tenantId, dono_id: usuarioId, tipo, arquivo_url: caminho })
        .select('id, tipo, status, criado_em').single();
      if (error) throw error;
      aoEnviar(data as DocumentoEnviado);
      setEstado('parado');
    } catch {
      setEstado('falhou');
    }
  }

  return (
    <div className="doc" style={erro ? { borderColor: 'var(--orange)' } : undefined}>
      <div>
        <b>{titulo}</b>
        <span>{descricao}</span>
        {enviado && <div className="msg-ok" style={{ marginTop: 6 }}><IconeOk />Enviado</div>}
        {recusado && <div className="msg-erro" style={{ marginTop: 6 }}><IconeAlerta />Recusado: envie outro</div>}
        {estado === 'falhou' && <div className="msg-erro" style={{ marginTop: 6 }}><IconeAlerta />Não foi possível enviar (máx. 10 MB). Tente de novo.</div>}
      </div>
      <input ref={entrada} type="file" hidden accept="image/*,application/pdf" capture={camera ? 'user' : undefined} onChange={escolher} />
      <button type="button" className="btn-ghost" disabled={estado === 'enviando'} onClick={() => entrada.current?.click()}>
        {estado === 'enviando' ? 'Enviando…' : enviado ? 'Trocar' : 'Enviar foto ou PDF'}
      </button>
    </div>
  );
}
