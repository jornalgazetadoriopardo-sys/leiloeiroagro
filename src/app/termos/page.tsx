import type { Metadata } from 'next';
import Link from 'next/link';

export const metadata: Metadata = { title: 'Termos, regras e privacidade – Pregão do Campo' };

// VERSÃO PROVISÓRIA (0.1). A redação final é do advogado (guia, seções 8 e 14).
// Ao publicar a versão final, atualize cadastro.versao_documentos_legais.
export default function Termos() {
  return (
    <main className="pagina-estreita texto-legal">
      <div className="banner b-orange">Versão provisória (0.1) — texto final em revisão jurídica.</div>

      <h2 id="termos">Termos de uso</h2>
      <p>A plataforma organiza leilões de gado por tempo. Só pode dar lance quem tiver o cadastro verificado pela leiloeira.</p>
      <ul>
        <li>Você é responsável pelos lances feitos com seu cadastro, inclusive por pessoas a quem você der acesso.</li>
        <li>Comprador e vendedor conhecidos pela plataforma não podem fechar negócio por fora. Uma venda feita por fora
          com quem você conheceu aqui continua devendo comissão e multa, no prazo definido pela leiloeira.</li>
        <li>Dados de contato só são liberados entre as partes depois do pagamento.</li>
      </ul>

      <h2 id="regras">Regras do leilão</h2>
      <ul>
        <li>Todo lance é por cabeça. O total do lote é o lance vezes a quantidade de animais.</li>
        <li>Cada novo lance precisa superar o atual pelo menos no incremento mínimo informado no lote.</li>
        <li>Lance dado nos últimos minutos prorroga o fim do lote. O horário que vale é o do servidor.</li>
        <li>O lance automático cobre outros lances até o teto que você informar. O teto é secreto.</li>
        <li>Em empate, vence o lance registrado primeiro.</li>
        <li>O lance vencedor obriga a compra. Desistência gera multa e suspensão do cadastro.</li>
        <li>Se o preço de reserva não for atingido, o vendedor pode aceitar ou não o maior lance.</li>
      </ul>

      <h2 id="privacidade">Política de privacidade</h2>
      <ul>
        <li>Coletamos nome, CPF/CNPJ, celular, cidade, inscrição estadual, e-mail, referência e documentos para verificar
          seu cadastro e cumprir obrigações legais.</li>
        <li>Documentos ficam em armazenamento privado, acessível só à leiloeira.</li>
        <li>Nos lances, outros usuários veem apenas um código (ex.: Comprador #4821) e sua cidade.</li>
        <li>Avisos no WhatsApp só com sua autorização. Para cancelar, responda SAIR.</li>
        <li>Você pode pedir a exportação ou a exclusão dos seus dados, respeitando o que a lei exige guardar.</li>
      </ul>
      <p style={{ marginTop: 32 }}><Link href="/">Voltar ao início</Link></p>
    </main>
  );
}
