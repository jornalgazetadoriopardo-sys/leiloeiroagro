import { Suspense } from 'react';
import { Cabecalho } from '@/components/Cabecalho';
import { GradeLotes } from '@/components/GradeLotes';
import { IconeRelogio } from '@/components/Icones';
import { PainelDestaque } from '@/components/PainelDestaque';
import { carregarCatalogo } from '@/lib/catalogo';

// Página inicial — seção 11.1 (1) do guia; layout do protótipo docs/prototipo/index.html
export default function Inicio() {
  return (
    <Suspense fallback={<Esqueleto />}>
      <Conteudo />
    </Suspense>
  );
}

async function Conteudo() {
  const { demo, tenant, lotes, servidorAgora, usuario } = await carregarCatalogo();
  const abertos = lotes.filter((l) => l.status_publico === 'aberto');
  const destaque = abertos[0]; // o que fecha primeiro
  const grade = lotes.filter((l) => l.id !== destaque?.id);
  const props = { servidorAgora, meuCodigo: usuario?.codigo ?? null, demo };

  return (
    <>
      {demo && (
        <div className="demo-aviso" role="note">
          Modo demonstração: configure o Supabase (.env.local) para ver os lotes reais.
        </div>
      )}
      <Cabecalho nome={tenant?.nome ?? 'Pregão do Campo'} status={usuario?.status ?? null} />
      <main>
        <section className="wrap hero">
          <h1>Lance de onde estiver. O cronômetro fecha o negócio.</h1>
          <p>
            Lotes vistoriados, compradores e vendedores verificados. Cada lote fica aberto por um prazo; se alguém der
            lance nos últimos 3 minutos, o prazo se estende.
          </p>
          <div className="steps">
            <div className="step"><span className="num">1</span><div><b>Cadastro verificado</b><span>CPF ou CNPJ, inscrição de produtor e referência bancária. Só quem passa pela análise pode dar lance.</span></div></div>
            <div className="step"><span className="num">2</span><div><b>Confira o lote</b><span>Vídeo, pesagem recente, idade, sanidade e laudo de vistoria de técnico credenciado.</span></div></div>
            <div className="step"><span className="num">3</span><div><b>Dê seu lance</b><span>Lance por cabeça, manual ou automático até o seu teto. Avisamos no WhatsApp se alguém cobrir.</span></div></div>
          </div>
        </section>

        {destaque && (
          <section id="destaque" className="wrap" style={{ paddingTop: 16, paddingBottom: 40 }}>
            <div className="sec-head">
              <h2>Encerrando agora</h2>
              <span className="chip chip-orange"><IconeRelogio tamanho={14} />Fecha primeiro</span>
            </div>
            <PainelDestaque lote={destaque} {...props} />
          </section>
        )}

        <section id="lotes" className="wrap" style={{ paddingTop: 16, paddingBottom: 48 }}>
          {lotes.length === 0 ? (
            <>
              <div className="sec-head"><h2>Leilões abertos</h2></div>
              <div className="vazio">Nenhum leilão aberto no momento. Volte em breve.</div>
            </>
          ) : (
            <GradeLotes lotes={grade} {...props} />
          )}
        </section>

        <Regras />
      </main>
    </>
  );
}

function Regras() {
  return (
    <section id="regras" className="rules">
      <div className="wrap" style={{ paddingTop: 40, paddingBottom: 48 }}>
        <h2 style={{ margin: '0 0 20px', fontWeight: 700, fontSize: 26 }}>Regras do lance</h2>
        <div className="rules-grid">
          <div><b>Valor por cabeça</b><span>Todo lance é por animal. O total do lote é calculado na hora. Incremento mínimo de R$ 20.</span></div>
          <div><b>Prorrogação automática</b><span>Lance nos últimos 3 minutos estende o prazo para 3 minutos de novo. Ninguém ganha no último segundo.</span></div>
          <div><b>Lance é compromisso</b><span>O lance vencedor obriga a compra. Desistência gera multa e suspensão do cadastro.</span></div>
          <div><b>Pagamento à vista</b><span>Depois do arremate, a leiloeira envia as instruções de pagamento. Os dados de contato entre comprador e vendedor só são liberados depois do pagamento confirmado.</span></div>
          <div><b>Conferência na entrega</b><span>Pesagem na origem com tolerância de quebra definida no lote. Contestação até 48 h após o recebimento.</span></div>
          <div><b>Avisos no WhatsApp</b><span>Avisamos quando seu lance for coberto e quando faltarem 3 minutos para o fim.</span></div>
        </div>
      </div>
    </section>
  );
}

function Esqueleto() {
  return (
    <main className="wrap" style={{ paddingTop: 48 }} aria-busy="true">
      <div className="skeleton" style={{ minHeight: 120, marginBottom: 24 }} />
      <div className="skeleton" style={{ minHeight: 360 }} />
    </main>
  );
}
