'use client';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useActionState, useEffect } from 'react';
import { IconeAlerta, IconeOk } from '@/components/Icones';
import type { EstadoForm } from './acoes';

const ABAS = [
  { href: '/admin', rotulo: 'Início' },
  { href: '/admin/cadastros', rotulo: 'Cadastros' },
  { href: '/admin/lotes', rotulo: 'Lotes' },
  { href: '/admin/leiloes', rotulo: 'Leilões' },
  { href: '/admin/ao-vivo', rotulo: 'Ao vivo' },
  { href: '/admin/vendas', rotulo: 'Pós-venda' },
];

export function NavAdmin() {
  const caminho = usePathname();
  return (
    <nav className="nav-admin" aria-label="Painel">
      {ABAS.map((a) => {
        const ativo = a.href === '/admin' ? caminho === '/admin' : caminho.startsWith(a.href);
        return <Link key={a.href} href={a.href} className={ativo ? 'ativo' : ''} aria-current={ativo ? 'page' : undefined}>{a.rotulo}</Link>;
      })}
    </nav>
  );
}

/** Formulário ligado a uma Server Action, com mensagem de erro/sucesso e confirmação opcional. */
export function FormAcao({ acao, botao, classeBotao = 'btn-primary', confirmar, children, className }: {
  acao: (estado: EstadoForm, f: FormData) => Promise<EstadoForm>;
  botao: string;
  classeBotao?: string;
  confirmar?: string;
  children?: React.ReactNode;
  className?: string;
}) {
  const [estado, despachar, pendente] = useActionState(acao, {});
  return (
    <form action={despachar} className={className}
      onSubmit={(e) => { if (confirmar && !window.confirm(confirmar)) e.preventDefault(); }}>
      {children}
      {estado.erro && <div className="msg-erro" role="alert" style={{ marginTop: 10 }}><IconeAlerta />{estado.erro}</div>}
      {estado.ok && <div className="msg-ok" role="status" style={{ marginTop: 10 }}><IconeOk />{estado.ok}</div>}
      <button type="submit" className={classeBotao} disabled={pendente} style={{ marginTop: 10 }}>{pendente ? 'Aguarde…' : botao}</button>
    </form>
  );
}

/** Recarrega a página de tempos em tempos (tela "Ao vivo"). */
export function AtualizarSozinho({ segundos = 10 }: { segundos?: number }) {
  const router = useRouter();
  useEffect(() => {
    const id = setInterval(() => router.refresh(), segundos * 1000);
    return () => clearInterval(id);
  }, [router, segundos]);
  return <span className="note">Atualiza a cada {segundos} s</span>;
}
