// Linha da view public.lotes_publicos (supabase/migrations/..._motor_lances.sql)
export type StatusPublico = 'agendado' | 'aberto' | 'encerrado';

export interface LotePublico {
  id: string;
  tenant_id: string;
  leilao_id: string | null;
  numero: number | null;
  titulo: string;
  categoria: string;
  raca: string;
  sexo: 'macho' | 'femea' | 'misto';
  quantidade: number;
  peso_medio: number;
  data_pesagem: string; // AAAA-MM-DD
  idade_min: number | null;
  idade_max: number | null;
  sanidade: { vacinas?: string; vermifugacao?: string; observacoes?: string };
  cidade: string;
  uf: string;
  retirada_prazo: number;
  frete: 'comprador' | 'vendedor' | 'a_combinar';
  tolerancia_quebra: number | null;
  preco_inicial: number;
  incremento: number;
  lance_atual: number | null;
  qtd_lances: number;
  lance_minimo: number;
  total_atual: number;
  abre_em: string | null;
  termina_em: string | null;
  prorrogado: boolean;
  status_publico: StatusPublico;
  participantes: number;
  vendedor_rotulo: string;
  voce_lidera: boolean;
  voce_deu_lance: boolean;
}

export interface Tenant {
  id: string;
  nome: string;
  subdominio: string;
  cor_destaque: string;
  logo_url: string | null;
}

export type StatusVerificacao = 'pendente' | 'verificado' | 'divergente' | 'recusado' | 'suspenso';

export interface MidiaLote {
  id: string;
  tipo: 'video' | 'foto' | 'laudo';
  url: string;
  ordem: number;
}

// Linha da view public.lances_publicos (anônima)
export interface LancePublico {
  id: string;
  seq: number;
  valor_por_cabeca: number;
  criado_em: string;
  rotulo: string;
  e_meu: boolean;
}

export interface ConfigPublica {
  incremento: number;
  botoes: number[];
  janelaMin: number;
}

/** Quem está vendo a página: decide o que o painel de lance oferece. */
export type Visitante = 'visitante' | 'sem_cadastro' | 'cadastro_incompleto' | StatusVerificacao;
