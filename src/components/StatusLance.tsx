import type { LotePublico } from '@/lib/tipos';
import { IconeAlerta, IconeOk, IconePonto } from './Icones';

type Situacao = 'lidera' | 'superado' | 'sem_lance' | 'arrematado' | 'encerrado' | 'agendado';

/** Situação do usuário no lote. Status nunca só pela cor: sempre ícone + texto. */
export function situacao(lote: LotePublico, encerrado: boolean): Situacao {
  if (lote.status_publico === 'agendado' && !encerrado) return 'agendado';
  if (encerrado) return lote.voce_lidera ? 'arrematado' : 'encerrado';
  if (lote.voce_lidera) return 'lidera';
  if (lote.voce_deu_lance) return 'superado';
  return 'sem_lance';
}

export function LinhaStatus({ s }: { s: Situacao }) {
  switch (s) {
    case 'lidera': return <div className="st st-green"><IconeOk />Você está liderando</div>;
    case 'superado': return <div className="st st-orange"><IconeAlerta />Seu lance foi superado</div>;
    case 'arrematado': return <div className="st st-green"><IconeOk />Arrematado por você</div>;
    case 'encerrado': return <div className="st st-gray">Leilão encerrado</div>;
    case 'agendado': return <div className="st st-gray"><IconePonto />Abre em breve</div>;
    default: return <div className="st st-gray"><IconePonto />Você ainda não deu lance</div>;
  }
}

export function FaixaStatus({ s }: { s: Situacao }) {
  switch (s) {
    case 'lidera': return <div className="banner b-green"><IconeOk tamanho={20} />Você está liderando</div>;
    case 'superado': return <div className="banner b-orange"><IconeAlerta tamanho={20} />Seu lance foi superado</div>;
    case 'arrematado': return <div className="banner b-green"><IconeOk tamanho={20} />Lote arrematado por você</div>;
    case 'encerrado': return <div className="banner b-gray">Leilão encerrado</div>;
    default: return null;
  }
}
