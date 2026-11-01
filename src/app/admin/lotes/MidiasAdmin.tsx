'use client';
import { useRouter } from 'next/navigation';
import { useRef, useState } from 'react';
import { IconeAlerta } from '@/components/Icones';
import { comprimirImagem } from '@/lib/imagem';
import { clienteNavegador } from '@/lib/supabase/client';
import { SUPABASE_URL } from '@/lib/supabase/config';

interface Midia { id: string; tipo: 'video' | 'foto' | 'laudo'; url: string; ordem: number }

const nomeArquivo = (tenantId: string, loteId: string, tipo: string, ext: string) =>
  `${tenantId}/${loteId}/${tipo}-${Date.now()}-${Math.random().toString(36).slice(2, 7)}.${ext}`;

const publica = (url: string) => /^https?:\/\//.test(url) ? url : `${SUPABASE_URL}/storage/v1/object/public/midias-lotes/${url}`;

/** Vídeo (arquivo ou link do YouTube), fotos e laudo do lote — seção 6.1. */
export function MidiasAdmin({ tenantId, loteId, midias, bloqueado }: { tenantId: string; loteId: string; midias: Midia[]; bloqueado: boolean }) {
  const router = useRouter();
  const [enviando, setEnviando] = useState<string | null>(null);
  const [erro, setErro] = useState('');
  const [youtube, setYoutube] = useState('');
  const fotos = midias.filter((m) => m.tipo === 'foto');

  async function registrar(tipo: Midia['tipo'], url: string) {
    const ordem = tipo === 'foto' ? fotos.length + 1 : 0;
    const { error } = await clienteNavegador().from('midias_lote').insert({ tenant_id: tenantId, lote_id: loteId, tipo, url, ordem });
    if (error) throw error;
  }

  async function enviar(tipo: Midia['tipo'], arquivos: FileList | null) {
    if (!arquivos?.length) return;
    setErro('');
    setEnviando(tipo);
    try {
      for (const original of Array.from(arquivos)) {
        const arquivo = tipo === 'foto' ? await comprimirImagem(original, 2000, 0.85) : original;
        const ext = (arquivo.name.split('.').pop() || 'bin').toLowerCase().replace(/[^a-z0-9]/g, '');
        const caminho = nomeArquivo(tenantId, loteId, tipo, ext);
        const { error } = await clienteNavegador().storage.from('midias-lotes').upload(caminho, arquivo, { contentType: arquivo.type });
        if (error) throw new Error(/size|large/i.test(error.message) ? 'Arquivo grande demais para o Supabase. Para vídeo, use um link do YouTube.' : error.message);
        await registrar(tipo, caminho);
      }
      router.refresh();
    } catch (e) {
      setErro(e instanceof Error ? e.message : 'Não foi possível enviar.');
    } finally {
      setEnviando(null);
    }
  }

  async function salvarYoutube() {
    if (!/(youtube\.com|youtu\.be)\//.test(youtube)) return setErro('Cole um link do YouTube (pode ser "não listado").');
    setEnviando('video');
    try { await registrar('video', youtube.trim()); setYoutube(''); router.refresh(); }
    catch { setErro('Não foi possível salvar o link.'); }
    finally { setEnviando(null); }
  }

  async function remover(m: Midia) {
    if (!window.confirm('Remover este arquivo do lote?')) return;
    await clienteNavegador().from('midias_lote').delete().eq('id', m.id);
    if (!/^https?:\/\//.test(m.url)) await clienteNavegador().storage.from('midias-lotes').remove([m.url]);
    router.refresh();
  }

  const botao = { bloqueado, enviando, enviar };

  return (
    <div className="bloco">
      <h2>Vídeo, fotos e laudo</h2>
      <p className="note">Obrigatórios para aprovar: 1 vídeo, pelo menos 3 fotos e o laudo de vistoria (PDF).</p>

      <h3 style={{ fontSize: 16, margin: '16px 0 6px' }}>Vídeo {midias.some((m) => m.tipo === 'video') ? '✓' : ''}</h3>
      <div className="acoes-linha" style={{ alignItems: 'center' }}>
        <BotaoArquivo {...botao} tipo="video" rotulo="Enviar arquivo de vídeo" accept="video/*" />
        <span className="note">ou</span>
        <input className="campo-inline" placeholder="Link do YouTube" value={youtube} onChange={(e) => setYoutube(e.target.value)} disabled={bloqueado} />
        <button type="button" className="btn-ghost" onClick={salvarYoutube} disabled={bloqueado || !youtube || enviando !== null}>Salvar link</button>
      </div>

      <h3 style={{ fontSize: 16, margin: '16px 0 6px' }}>Fotos ({fotos.length})</h3>
      <BotaoArquivo {...botao} tipo="foto" rotulo="Enviar fotos" accept="image/*" multiplo />

      <h3 style={{ fontSize: 16, margin: '16px 0 6px' }}>Laudo de vistoria {midias.some((m) => m.tipo === 'laudo') ? '✓' : ''}</h3>
      <BotaoArquivo {...botao} tipo="laudo" rotulo="Enviar laudo (PDF)" accept="application/pdf,image/*" />

      {erro && <div className="msg-erro" role="alert" style={{ marginTop: 12 }}><IconeAlerta />{erro}</div>}

      {midias.length > 0 && (
        <div className="midias-admin">
          {midias.map((m) => (
            <figure key={m.id}>
              {m.tipo === 'foto'
                // eslint-disable-next-line @next/next/no-img-element
                ? <img src={publica(m.url)} alt="Foto do lote" />
                : <a className="rotulo-midia" href={publica(m.url)} target="_blank" rel="noreferrer">{m.tipo === 'video' ? 'Vídeo' : 'Laudo'}</a>}
              <figcaption>
                <span>{m.tipo}</span>
                {!bloqueado && <button type="button" className="btn-link" style={{ minHeight: 32 }} onClick={() => remover(m)}>Remover</button>}
              </figcaption>
            </figure>
          ))}
        </div>
      )}
    </div>
  );
}

function BotaoArquivo({ tipo, rotulo, accept, multiplo, bloqueado, enviando, enviar }: {
  tipo: Midia['tipo']; rotulo: string; accept: string; multiplo?: boolean; bloqueado: boolean;
  enviando: string | null; enviar: (tipo: Midia['tipo'], arquivos: FileList | null) => Promise<void>;
}) {
  const ref = useRef<HTMLInputElement>(null);
  return (
    <>
      <input ref={ref} type="file" hidden accept={accept} multiple={multiplo}
        onChange={(e) => { void enviar(tipo, e.target.files); e.target.value = ''; }} />
      <button type="button" className="btn-ghost" disabled={bloqueado || enviando !== null} onClick={() => ref.current?.click()}>
        {enviando === tipo ? 'Enviando…' : rotulo}
      </button>
    </>
  );
}
