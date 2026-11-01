import { IconeEscudo, IconeVistoria } from './Icones';

// Selos de confiança. Só afirmações verdadeiras na Fase 1: cadastro verificado,
// vistoria e regras no servidor. (Conta garantia é Fase 2 — seção 9.2.)
const SELOS = [
  { Icone: IconeEscudo, titulo: 'Vendedor verificado', texto: 'Documentos e cadastro conferidos pela leiloeira.' },
  { Icone: IconeVistoria, titulo: 'Lote vistoriado', texto: 'Técnico credenciado confere os animais e emite laudo.' },
  { Icone: IconeEscudo, titulo: 'Compradores verificados', texto: 'Só quem passa pela análise pode dar lance.' },
];

/** Bloco "Compre com tranquilidade" (página do lote e destaque). */
export function SelosConfianca() {
  return (
    <section className="selos" aria-label="Garantias deste lote">
      <h2 className="selos-titulo">Compre com tranquilidade</h2>
      <ul>
        {SELOS.map(({ Icone, titulo, texto }) => (
          <li key={titulo}>
            <span className="selo-icone"><Icone tamanho={22} /></span>
            <div><b>{titulo}</b><span>{texto}</span></div>
          </li>
        ))}
      </ul>
    </section>
  );
}

/** Versão compacta para o cartão do lote. */
export function SelosCartao() {
  return (
    <div className="selos-cartao">
      <span><IconeEscudo tamanho={16} />Vendedor verificado</span>
      <span><IconeVistoria tamanho={16} />Lote vistoriado</span>
    </div>
  );
}
