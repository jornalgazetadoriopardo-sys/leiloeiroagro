import type { Metadata } from 'next';
import Link from 'next/link';
import { redirect } from 'next/navigation';
import { Suspense } from 'react';
import { Cabecalho } from '@/components/Cabecalho';
import { IconeAlerta, IconeCadeado, IconeEscudo, IconeRelogio, IconeX } from '@/components/Icones';
import { sair } from '@/lib/acoes-conta';
import { mascaraCelular, mascaraCpfCnpj } from '@/lib/brasil';
import { obterEquipe } from '@/lib/admin';
import { obterSessao, type MeuCadastro } from '@/lib/sessao';

export const metadata: Metadata = { title: 'Minha conta – Pregão do Campo' };

// Seção 11.1 (7): cadastro e status da verificação
export default function Conta(props: PageProps<'/conta'>) {
  return (
    <Suspense fallback={<main className="pagina-estreita"><div className="skeleton" style={{ minHeight: 320 }} /></main>}>
      <Conteudo searchParams={props.searchParams} />
    </Suspense>
  );
}

async function Conteudo({ searchParams }: { searchParams: PageProps<'/conta'>['searchParams'] }) {
  const [{ tenant, logado, cadastro }, params] = await Promise.all([obterSessao(), searchParams]);
  if (!logado || !cadastro) redirect('/entrar');
  const equipe = await obterEquipe();
  if (!cadastro.cadastro_enviado_em && !equipe) redirect('/cadastro');

  return (
    <>
      <Cabecalho nome={tenant?.nome ?? 'Pregão do Campo'} status={cadastro.status_verificacao} />
      <main className="pagina-estreita">
        <div className="cartao">
          {params.enviado && (
            <div className="banner b-green" style={{ marginBottom: 18 }}>Cadastro enviado. Obrigado!</div>
          )}
          <h1>Minha conta</h1>
          <Situacao c={cadastro} />
          <dl className="dados-lista">
            <div><dt>Nome</dt><dd>{cadastro.nome}</dd></div>
            <div><dt>CPF/CNPJ</dt><dd>{cadastro.cpf_cnpj ? mascaraCpfCnpj(cadastro.cpf_cnpj) : '—'}</dd></div>
            <div><dt>Celular</dt><dd>{mascaraCelular(cadastro.celular.replace(/^\+55/, ''))}</dd></div>
            <div><dt>Cidade</dt><dd>{cadastro.cidade} – {cadastro.uf}</dd></div>
            <div><dt>Seu código nos lances</dt><dd>Comprador #{cadastro.codigo_publico}</dd></div>
            <div><dt>Avisos no WhatsApp</dt><dd>{cadastro.optin_whatsapp ? 'Ativados' : 'Desativados'}</dd></div>
          </dl>
          {equipe && <Link className="btn-aprovar btn-bloco" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', marginTop: 20 }} href="/admin">Abrir painel da leiloeira</Link>}
          <form action={sair}>
            <button className="btn-ghost btn-bloco" type="submit">Sair</button>
          </form>
        </div>
        <p style={{ textAlign: 'center', marginTop: 20 }}><Link href="/">Ver leilões abertos</Link></p>
      </main>
    </>
  );
}

// Status — seção 5.2 (ícone + texto)
function Situacao({ c }: { c: MeuCadastro }) {
  switch (c.status_verificacao) {
    case 'verificado':
      return <div className="banner b-green" style={{ marginTop: 16 }}><IconeEscudo tamanho={20} />Cadastro verificado. Você já pode dar lances.</div>;
    case 'pendente':
      return (
        <div className="banner b-gray" style={{ marginTop: 16, alignItems: 'flex-start' }}>
          <IconeRelogio tamanho={20} />
          <span>Cadastro em análise. Avisaremos {c.optin_whatsapp ? 'no WhatsApp' : 'aqui'} quando terminar.</span>
        </div>
      );
    case 'divergente':
      return (
        <div style={{ marginTop: 16 }}>
          <div className="banner b-orange" style={{ alignItems: 'flex-start' }}>
            <IconeAlerta tamanho={20} />
            <span>A leiloeira pediu um ajuste{c.observacao_analise ? `: ${c.observacao_analise}` : '.'}</span>
          </div>
          <Link className="btn-primary btn-bloco" href="/cadastro">Corrigir cadastro</Link>
        </div>
      );
    case 'recusado':
      return <div className="banner b-gray" style={{ marginTop: 16 }}><IconeX tamanho={20} />Cadastro não aprovado.{c.observacao_analise ? ` ${c.observacao_analise}` : ''}</div>;
    case 'suspenso':
      return <div className="banner b-orange" style={{ marginTop: 16 }}><IconeCadeado tamanho={20} />Cadastro suspenso. Fale com a leiloeira.</div>;
  }
}
