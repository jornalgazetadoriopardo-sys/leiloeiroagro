import type { LotePublico } from '@/lib/tipos';
import { IconeAlerta, IconeOk, IconePonto, IconeRelogio } from './Icones';

export type Situacao = 'lidera' | 'superado' | 'sem_lance' | 'arrematado' | 'encerrado' | 'agendado';

/** Situação do usuário no lote. Status nunca só pela cor: sempre ícone + texto. */
export function situacao(lote: LotePublico, encerrado: boolean): Situacao {
  if (lote.status_publico === 'agendado' && !encerrado) return 'agendado';
  if (encerrado) return lote.voce_lidera ? 'arrematado' : 'encerrado';
  if (lote.voce_lidera) return 'lidera';
  if (lote.voce_deu_lance) return 'superado';
  return 'sem_lance';
}

const TEXTO: Record<Situacao, { titulo: string; detalhe: string; classe: string }> = {
  lidera: { titulo: 'Você está liderando', detalhe: 'Se ninguém cobrir até o fim, o lote é seu.', classe: 'sit-lidera' },
  superado: { titulo: 'Seu lance foi coberto', detalhe: 'Outro comprador passou à frente. Cubra para voltar a liderar.', classe: 'sit-superado' },
  arrematado: { titulo: 'Você arrematou este lote', detalhe: 'Enviaremos as instruções de pagamento.', classe: 'sit-lidera' },
  encerrado: { titulo: 'Leilão encerrado', detalhe: 'Este lote não recebe mais lances.', classe: 'sit-encerrado' },
  agendado: { titulo: 'Abre em breve', detalhe: 'Os lances começam no horário de abertura.', classe: 'sit-neutra' },
  sem_lance: { titulo: 'Você ainda não deu lance', detalhe: '', classe: 'sit-neutra' },
};

function Icone({ s, tamanho }: { s: Situacao; tamanho: number }) {
  if (s === 'lidera' || s === 'arrematado') return <IconeOk tamanho={tamanho} />;
  if (s === 'superado') return <IconeAlerta tamanho={tamanho} />;
  if (s === 'agendado') return <IconeRelogio tamanho={tamanho} />;
  return <IconePonto tamanho={tamanho} />;
}

/** Faixa grande do painel de lance (página do lote e destaque). */
export function FaixaStatus({ s }: { s: Situacao }) {
  if (s === 'sem_lance') return null;
  const t = TEXTO[s];
  return (
    <div className={`faixa-sit ${t.classe}`}>
      <Icone s={s} tamanho={28} />
      <div><b>{t.titulo}</b><span>{t.detalhe}</span></div>
    </div>
  );
}

/** Tarja de situação no topo do cartão do lote. */
export function TarjaStatus({ s }: { s: Situacao }) {
  const t = TEXTO[s];
  return <div className={`tarja-sit ${t.classe}`}><Icone s={s} tamanho={18} />{t.titulo}</div>;
}
