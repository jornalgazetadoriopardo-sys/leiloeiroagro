import Link from 'next/link';

export function Restrito() {
  return (
    <div className="cartao" style={{ maxWidth: 520, margin: '24px auto' }}>
      <h1>Acesso restrito</h1>
      <p className="intro">Esta área é só para a equipe da leiloeira. Entre com uma conta de admin ou operador.</p>
      <Link className="btn-primary btn-bloco" href="/entrar?voltar=/admin">Entrar</Link>
    </div>
  );
}

export function Carregando() {
  return <div className="skeleton" style={{ minHeight: 320, marginTop: 24 }} />;
}
