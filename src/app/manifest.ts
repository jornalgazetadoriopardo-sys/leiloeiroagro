import type { MetadataRoute } from 'next';

// PWA: pode ser "instalado" na tela inicial (seção 4.1)
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'Pregão do Campo – Leilão de gado online',
    short_name: 'Pregão do Campo',
    description: 'Leilão de gado por tempo, com lotes vistoriados e cadastro verificado.',
    lang: 'pt-BR',
    start_url: '/',
    display: 'standalone',
    background_color: '#F3F4F0',
    theme_color: '#1F3D2B',
    icons: [
      { src: '/icone.svg', sizes: 'any', type: 'image/svg+xml', purpose: 'any' },
      { src: '/icone-192.png', sizes: '192x192', type: 'image/png' },
      { src: '/icone-512.png', sizes: '512x512', type: 'image/png' },
    ],
  };
}
