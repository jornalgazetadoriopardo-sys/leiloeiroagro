import { urlMidia } from '@/lib/lote';
import type { MidiaLote } from '@/lib/tipos';
import { IconePlay } from './Icones';

/** Vídeo (obrigatório), fotos e laudo de vistoria — seções 6.1 e 11.1. */
export function MidiasLote({ midias, numero }: { midias: MidiaLote[]; numero: string }) {
  const video = midias.find((m) => m.tipo === 'video');
  const fotos = midias.filter((m) => m.tipo === 'foto');
  const laudo = midias.find((m) => m.tipo === 'laudo');

  return (
    <>
      <div className="f-media" style={video ? { height: 'auto', background: '#000' } : undefined}>
        {video ? <Video url={video.url} /> : (
          <>
            <span className="play"><IconePlay cor="var(--accent)" /></span>
            Vídeo do lote em preparação
          </>
        )}
        <span className="tag">{numero}</span>
      </div>
      <div className="thumbs">
        {fotos.slice(0, 5).map((f, i) => (
          <a key={f.id} href={urlMidia(f.url)} target="_blank" rel="noreferrer" className="thumb-foto" aria-label={`Abrir foto ${i + 1}`}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={urlMidia(f.url)} alt={`Foto ${i + 1} do lote`} loading="lazy" />
          </a>
        ))}
        {fotos.length === 0 && <div>Fotos em breve</div>}
        {laudo ? (
          <a className="thumb-laudo" href={urlMidia(laudo.url)} target="_blank" rel="noreferrer">Laudo de vistoria (PDF)</a>
        ) : (
          <div>Laudo de vistoria em breve</div>
        )}
      </div>
    </>
  );
}

function Video({ url }: { url: string }) {
  // Piloto: YouTube não listado é aceito (seção 4.2). Depois: Cloudflare Stream ou arquivo.
  const yt = url.match(/(?:youtube\.com\/(?:watch\?v=|shorts\/|embed\/)|youtu\.be\/)([\w-]{11})/);
  if (yt) {
    return (
      <iframe className="video-lote" src={`https://www.youtube-nocookie.com/embed/${yt[1]}?rel=0`} title="Vídeo do lote"
        loading="lazy" allow="encrypted-media; picture-in-picture; fullscreen" allowFullScreen />
    );
  }
  return <video className="video-lote" src={urlMidia(url)} controls preload="metadata" playsInline />;
}
