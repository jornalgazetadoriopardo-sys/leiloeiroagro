import type { Metadata, Viewport } from 'next';
import { Archivo, Inter } from 'next/font/google';
import './globals.css';

// Archivo: títulos, números e cronômetro. Inter: texto (seção 12).
const archivo = Archivo({ variable: '--font-archivo', subsets: ['latin'], weight: ['500', '600', '700', '800'] });
const inter = Inter({ variable: '--font-inter', subsets: ['latin'], weight: ['400', '500', '600', '700'] });

export const metadata: Metadata = {
  title: 'Pregão do Campo – Leilão de gado online',
  description: 'Leilão de gado por tempo, com lotes vistoriados e compradores e vendedores verificados.',
  applicationName: 'Pregão do Campo',
  appleWebApp: { capable: true, title: 'Pregão do Campo', statusBarStyle: 'default' },
};

export const viewport: Viewport = {
  themeColor: '#1F3D2B',
  width: 'device-width',
  initialScale: 1,
};

export default function RootLayout({ children }: LayoutProps<'/'>) {
  return (
    <html lang="pt-BR" className={`${archivo.variable} ${inter.variable}`}>
      <body>{children}</body>
    </html>
  );
}
