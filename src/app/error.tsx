'use client';

// Falha inesperada (ex.: internet caiu ou banco indisponível): mensagem simples e botão para tentar de novo.
export default function Erro({ reset }: { error: Error; reset: () => void }) {
  return (
    <main className="pagina-estreita">
      <div className="cartao">
        <h1>Não foi possível carregar</h1>
        <p className="intro">Verifique sua internet e tente de novo.</p>
        <button className="btn-primary btn-bloco" type="button" onClick={reset}>Tentar de novo</button>
      </div>
    </main>
  );
}
