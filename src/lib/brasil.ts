export const UFS = ['AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS', 'MG', 'PA', 'PB', 'PR',
  'PE', 'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO'] as const;

export const soDigitos = (v: string) => v.replace(/\D/g, '');

/** (19) 99999-9999 */
export function mascaraCelular(v: string): string {
  const d = soDigitos(v).slice(0, 11);
  if (d.length <= 2) return d.length ? `(${d}` : '';
  if (d.length <= 6) return `(${d.slice(0, 2)}) ${d.slice(2)}`;
  if (d.length <= 10) return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`;
  return `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`;
}

/** 000.000.000-00 ou 00.000.000/0000-00 */
export function mascaraCpfCnpj(v: string): string {
  const d = soDigitos(v).slice(0, 14);
  if (d.length <= 11) {
    return d.replace(/(\d{3})(\d)/, '$1.$2').replace(/(\d{3})(\d)/, '$1.$2').replace(/(\d{3})(\d{1,2})$/, '$1-$2');
  }
  return d.replace(/^(\d{2})(\d)/, '$1.$2').replace(/^(\d{2})\.(\d{3})(\d)/, '$1.$2.$3')
    .replace(/\.(\d{3})(\d)/, '.$1/$2').replace(/(\d{4})(\d{1,2})$/, '$1-$2');
}

/** Mesma regra de app.cpf_cnpj_valido (o servidor valida de novo). */
export function cpfCnpjValido(v: string): boolean {
  const d = soDigitos(v);
  if (!(d.length === 11 || d.length === 14) || /^(\d)\1+$/.test(d)) return false;
  const n = d.split('').map(Number);
  if (d.length === 11) {
    for (const k of [0, 1]) {
      let soma = 0;
      for (let i = 0; i < 9 + k; i++) soma += n[i] * (10 + k - i);
      const dv = ((soma * 10) % 11) % 10;
      if (dv !== n[9 + k]) return false;
    }
    return true;
  }
  const calc = (pesos: number[]) => {
    const soma = pesos.reduce((s, p, i) => s + n[i] * p, 0);
    return soma % 11 < 2 ? 0 : 11 - (soma % 11);
  };
  return calc([5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]) === n[12] && calc([6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]) === n[13];
}
