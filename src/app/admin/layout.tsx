import type { Metadata } from 'next';
import Link from 'next/link';
import { Suspense } from 'react';
import { IconeMartelo } from '@/components/Icones';
import { NavAdmin } from './componentes';

export const metadata: Metadata = { title: 'Painel da leiloeira – Pregão do Campo' };

// Painel do admin — seção 11.2 (computador primeiro, mas funciona no celular)
export default function LayoutAdmin({ children }: LayoutProps<'/admin'>) {
  return (
    <>
      <header>
        <div className="wrap top">
          <Link href="/admin" className="brand" style={{ color: 'var(--ink)' }}>
            <IconeMartelo tamanho={26} style={{ color: 'var(--accent)' }} />Painel da leiloeira
          </Link>
          <Link href="/" className="btn-ghost">Ver o site</Link>
        </div>
        <div className="wrap"><Suspense fallback={<nav className="nav-admin" style={{ minHeight: 47 }} />}><NavAdmin /></Suspense></div>
      </header>
      <main className="wrap admin">{children}</main>
    </>
  );
}
