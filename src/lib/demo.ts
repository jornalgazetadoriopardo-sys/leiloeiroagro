import type { LotePublico } from './tipos';

// Dados de demonstração (os mesmos lotes do protótipo). Usados só quando o
// Supabase não está configurado, para o app abrir em desenvolvimento.
type Base = Omit<LotePublico, 'id' | 'tenant_id' | 'leilao_id' | 'termina_em' | 'abre_em' | 'lance_minimo' | 'total_atual' | 'incremento' | 'status_publico' | 'prorrogado' | 'voce_deu_lance'> & { fimEmMin: number };

const base: Base[] = [
  { numero: 1, titulo: '30 garrotes Nelore', categoria: 'garrotes', raca: 'Nelore', sexo: 'macho', quantidade: 30, peso_medio: 268, data_pesagem: '2026-10-25', idade_min: 12, idade_max: 14, sanidade: { vacinas: 'Vacinas em dia' }, cidade: 'Mococa', uf: 'SP', retirada_prazo: 5, frete: 'comprador', preco_inicial: 2600, lance_atual: 2910, qtd_lances: 14, participantes: 6, vendedor_rotulo: 'Fazenda #128 · Mococa-SP', voce_lidera: false, fimEmMin: 2.7 },
  { numero: 2, titulo: '18 novilhas Nelore', categoria: 'novilhas', raca: 'Nelore', sexo: 'femea', quantidade: 18, peso_medio: 290, data_pesagem: '2026-10-24', idade_min: 18, idade_max: 20, sanidade: {}, cidade: 'Casa Branca', uf: 'SP', retirada_prazo: 5, frete: 'comprador', preco_inicial: 2900, lance_atual: 3150, qtd_lances: 9, participantes: 4, vendedor_rotulo: 'Fazenda #342 · Casa Branca-SP', voce_lidera: true, fimEmMin: 72 },
  { numero: 3, titulo: '40 bezerros desmamados anelorados', categoria: 'bezerros', raca: 'Anelorado', sexo: 'macho', quantidade: 40, peso_medio: 195, data_pesagem: '2026-10-26', idade_min: 7, idade_max: 8, sanidade: {}, cidade: 'Tambaú', uf: 'SP', retirada_prazo: 5, frete: 'comprador', preco_inicial: 2100, lance_atual: 2380, qtd_lances: 21, participantes: 8, vendedor_rotulo: 'Fazenda #517 · Tambaú-SP', voce_lidera: false, fimEmMin: 185 },
  { numero: 4, titulo: '12 vacas Girolando em lactação', categoria: 'vacas', raca: 'Girolando', sexo: 'femea', quantidade: 12, peso_medio: 480, data_pesagem: '2026-10-23', idade_min: 48, idade_max: 72, sanidade: {}, cidade: 'São Sebastião da Grama', uf: 'SP', retirada_prazo: 5, frete: 'comprador', preco_inicial: 6000, lance_atual: 6400, qtd_lances: 3, participantes: 2, vendedor_rotulo: 'Fazenda #209 · São Sebastião da Grama-SP', voce_lidera: false, fimEmMin: 28 * 60 },
  { numero: 5, titulo: '25 bois magros Nelore', categoria: 'boi magro', raca: 'Nelore', sexo: 'macho', quantidade: 25, peso_medio: 380, data_pesagem: '2026-10-27', idade_min: 24, idade_max: 26, sanidade: {}, cidade: 'Divinolândia', uf: 'SP', retirada_prazo: 5, frete: 'comprador', preco_inicial: 3400, lance_atual: 3720, qtd_lances: 7, participantes: 3, vendedor_rotulo: 'Fazenda #861 · Divinolândia-SP', voce_lidera: false, fimEmMin: 5 * 60 + 20 },
  { numero: 6, titulo: '20 bezerras Angus × Nelore', categoria: 'bezerras', raca: 'Angus × Nelore', sexo: 'femea', quantidade: 20, peso_medio: 210, data_pesagem: '2026-10-26', idade_min: 8, idade_max: 9, sanidade: {}, cidade: 'Vargem Grande do Sul', uf: 'SP', retirada_prazo: 5, frete: 'comprador', preco_inicial: 2650, lance_atual: null, qtd_lances: 0, participantes: 0, vendedor_rotulo: 'Fazenda #733 · Vargem Grande do Sul-SP', voce_lidera: false, fimEmMin: 51 * 60 },
];

export function lotesDemo(agora: number): LotePublico[] {
  return base.map(({ fimEmMin, ...l }, i) => ({
    ...l,
    id: `demo-${i + 1}`,
    tenant_id: 'demo',
    leilao_id: null,
    incremento: 20,
    lance_minimo: l.lance_atual == null ? l.preco_inicial : l.lance_atual + 20,
    total_atual: (l.lance_atual ?? 0) * l.quantidade,
    abre_em: new Date(agora - 86_400_000).toISOString(),
    termina_em: new Date(agora + fimEmMin * 60_000).toISOString(),
    status_publico: 'aberto',
    prorrogado: false,
    voce_deu_lance: l.voce_lidera || i === 0 || i === 2,
  }));
}
