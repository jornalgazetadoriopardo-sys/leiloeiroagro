// Formatação no padrão do guia: pt-BR, BRL, fuso America/Sao_Paulo.
export const FUSO = 'America/Sao_Paulo';

/** "R$ 2.930" (sem centavos quando o valor é inteiro). */
export function brl(valor: number | null | undefined): string {
  if (valor == null) return '—';
  const inteiro = Number.isInteger(Number(valor));
  return 'R$ ' + Number(valor).toLocaleString('pt-BR', {
    minimumFractionDigits: inteiro ? 0 : 2,
    maximumFractionDigits: inteiro ? 0 : 2,
  });
}

export function plural(n: number, um: string, varios: string): string {
  return `${n} ${n === 1 ? um : varios}`;
}

const pad = (n: number) => String(n).padStart(2, '0');

/** Tempo restante no formato do protótipo: "2d 04h", "3h 12min", "02:41". */
export function tempoRestante(ms: number): string {
  if (ms <= 0) return 'Encerrado';
  const s = Math.floor(ms / 1000);
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (d > 0) return `${d}d ${pad(h)}h`;
  if (h > 0) return `${h}h ${pad(m)}min`;
  return `${pad(m)}:${pad(s % 60)}`;
}

/** "25/10" */
export function diaMes(dataIso: string): string {
  const [, mes, dia] = dataIso.slice(0, 10).split('-');
  return `${dia}/${mes}`;
}

export function faixaIdade(min: number | null, max: number | null): string {
  if (min == null && max == null) return '—';
  const emAnos = (min ?? 0) >= 36;
  const f = (v: number) => (emAnos ? Math.round(v / 12) : v);
  const un = emAnos ? 'anos' : 'meses';
  if (min != null && max != null && min !== max) return `${f(min)} a ${f(max)} ${un}`;
  return `${f((min ?? max)!)} ${un}`;
}

export const FRETE: Record<string, string> = {
  comprador: 'frete do comprador',
  vendedor: 'frete do vendedor',
  a_combinar: 'frete a combinar',
};
