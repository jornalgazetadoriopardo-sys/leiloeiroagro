import Link from 'next/link';
import type { StatusVerificacao } from '@/lib/tipos';
import { IconeAlerta, IconeCadeado, IconeEscudo, IconeMartelo, IconeRelogio, IconeX } from './Icones';

// Status do cadastro — seção 5.2 (ícone + texto, nunca só cor)
const STATUS: Record<StatusVerificacao, { rotulo: string; classe: string; Icone: typeof IconeEscudo }> = {
  verificado: { rotulo: 'Comprador verificado', classe: 'chip chip-green', Icone: IconeEscudo },
  pendente:   { rotulo: 'Cadastro em análise', classe: 'chip chip-gray', Icone: IconeRelogio },
  divergente: { rotulo: 'Cadastro precisa de ajuste', classe: 'chip chip-orange', Icone: IconeAlerta },
  recusado:   { rotulo: 'Cadastro recusado', classe: 'chip chip-dark', Icone: IconeX },
  suspenso:   { rotulo: 'Cadastro suspenso', classe: 'chip chip-orange', Icone: IconeCadeado },
};

export function Cabecalho({ nome, status }: { nome: string; status: StatusVerificacao | null }) {
  const st = status ? STATUS[status] : null;
  return (
    <header>
      <div className="wrap top">
        <Link href="/" className="brand" style={{ color: 'var(--ink)' }}>
          <IconeMartelo tamanho={30} style={{ color: 'var(--accent)' }} />
          {nome}
        </Link>
        <nav aria-label="Principal">
          <a href="#lotes">Leilões abertos</a>
          <a href="#regras">Como funciona</a>
          <Link href="/vender">Vender meu lote</Link>
        </nav>
        <div className="account">
          {st && <span className={st.classe}><st.Icone tamanho={14} />{st.rotulo}</span>}
          <Link className="btn-ghost" href={status ? '/conta' : '/entrar'}>{status ? 'Minha conta' : 'Entrar'}</Link>
        </div>
      </div>
    </header>
  );
}
