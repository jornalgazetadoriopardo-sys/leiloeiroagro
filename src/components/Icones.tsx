// Ícones de traço (SVG), sem emoji — seção 12. Sempre decorativos (aria-hidden):
// o texto ao lado é que comunica o status.
import type { SVGProps } from 'react';

type P = SVGProps<SVGSVGElement> & { tamanho?: number };

function Traco({ tamanho = 16, children, strokeWidth = 2.5, ...p }: P) {
  return (
    <svg aria-hidden="true" width={tamanho} height={tamanho} viewBox="0 0 24 24" fill="none" stroke="currentColor"
      strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round" {...p}>
      {children}
    </svg>
  );
}

export const IconeEscudo = (p: P) => <Traco {...p}><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" /><path d="M9 12l2 2 4-4" /></Traco>;
export const IconeRelogio = (p: P) => <Traco {...p}><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></Traco>;
export const IconeOk = (p: P) => <Traco {...p}><circle cx="12" cy="12" r="9" /><path d="M8 12l3 3 5-6" /></Traco>;
export const IconeAlerta = (p: P) => <Traco {...p}><path d="M10.3 3.9L1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z" /><path d="M12 9v4" /><path d="M12 17h.01" /></Traco>;
export const IconePonto = (p: P) => <Traco {...p}><circle cx="12" cy="12" r="9" /></Traco>;
export const IconeX = (p: P) => <Traco {...p}><circle cx="12" cy="12" r="9" /><path d="M15 9l-6 6M9 9l6 6" /></Traco>;
export const IconeCadeado = (p: P) => <Traco {...p}><rect x="5" y="11" width="14" height="10" rx="2" /><path d="M8 11V7a4 4 0 0 1 8 0v4" /></Traco>;
export const IconeVistoria = (p: P) => <Traco {...p}><path d="M9 11l3 3L22 4" /><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11" /></Traco>;
export const IconeMartelo = (p: P) => <Traco strokeWidth={2} {...p}><path d="M14 13l-7.5 7.5a2.12 2.12 0 0 1-3-3L11 10" /><path d="M16 16l6-6" /><path d="M8 8l6-6" /><path d="M9 7l8 8" /><path d="M21 11l-8-8" /></Traco>;

export function IconePlay({ tamanho = 26, cor = 'currentColor' }: { tamanho?: number; cor?: string }) {
  return <svg aria-hidden="true" width={tamanho} height={tamanho} viewBox="0 0 24 24" fill={cor}><path d="M8 5v14l11-7z" /></svg>;
}
