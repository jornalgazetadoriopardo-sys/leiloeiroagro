import Link from 'next/link';
import { Suspense } from 'react';
import { obterEquipe } from '@/lib/admin';
import { Carregando, Restrito } from './Restrito';

export default function InicioAdmin() {
  return <Suspense fallback={<Carregando />}><Conteudo /></Suspense>;
}

async function Conteudo() {
  const e = await obterEquipe();
  if (!e) return <Restrito />;
  const { data } = await e.supabase.rpc('resumo_painel', { p_tenant_id: e.tenant.id });
  const r = (data ?? {}) as Record<string, number>;
  const cartoes = [
    { href: '/admin/cadastros', n: r.cadastros_pendentes, rotulo: 'cadastros para analisar', alerta: r.cadastros_pendentes > 0 },
    { href: '/admin/lotes?filtro=preparacao', n: r.lotes_preparacao, rotulo: 'lotes em preparação', alerta: false },
    { href: '/admin/leiloes', n: r.lotes_aprovados, rotulo: 'lotes prontos para leilão', alerta: false },
    { href: '/admin/ao-vivo', n: r.lotes_abertos, rotulo: 'lotes abertos agora', alerta: false },
    { href: '/admin/vendas', n: r.vendas_aguardando, rotulo: 'vendas aguardando pagamento', alerta: r.vendas_aguardando > 0 },
  ];
  return (
    <>
      <h1>Olá, {e.usuario.nome?.split(' ')[0] ?? 'equipe'}</h1>
      <p className="sub-titulo">{e.tenant.nome} · {e.admin ? 'Administrador' : 'Operador'}</p>
      <div className="resumo">
        {cartoes.map((c) => (
          <Link key={c.href} href={c.href} className={c.alerta ? 'alerta' : ''}>
            <b>{c.n ?? 0}</b><span>{c.rotulo}</span>
          </Link>
        ))}
      </div>
      <div className="bloco" style={{ marginTop: 20 }}>
        <h2>Como montar um leilão</h2>
        <ol style={{ margin: 0, paddingLeft: 20, lineHeight: 1.8, color: 'var(--ink2)' }}>
          <li><Link href="/admin/lotes/novo">Cadastre o lote</Link> e envie vídeo, 3 fotos e o laudo.</li>
          <li>Toque em <b>Aprovar lote</b> quando não faltar nada.</li>
          <li><Link href="/admin/leiloes">Crie o leilão</Link>, inclua os lotes aprovados e toque em <b>Agendar</b>.</li>
          <li>Os lotes abrem e fecham sozinhos. Acompanhe em <Link href="/admin/ao-vivo">Ao vivo</Link>.</li>
          <li>Depois do arremate, confirme o pagamento em <Link href="/admin/vendas">Pós-venda</Link>.</li>
        </ol>
      </div>
    </>
  );
}
