'use server';
import { refresh } from 'next/cache';
import { redirect } from 'next/navigation';
import { deLocalBrasilia, obterEquipe } from '@/lib/admin';

export interface EstadoForm {
  erro?: string;
  campo?: string;
  ok?: string;
}

type Resultado = { ok: boolean; codigo?: string; mensagem?: string; [k: string]: unknown };

async function equipe() {
  const e = await obterEquipe();
  if (!e) throw new Error('Acesso restrito à equipe da leiloeira.');
  return e;
}

async function rpc(nome: string, args: Record<string, unknown>): Promise<Resultado> {
  const { supabase } = await equipe();
  const { data, error } = await supabase.rpc(nome, args);
  if (error) return { ok: false, mensagem: 'Erro ao falar com o servidor. Tente de novo.' };
  return data as Resultado;
}

const texto = (f: FormData, k: string) => String(f.get(k) ?? '').trim();

/** "2.600" → "2600"; "2.600,50" → "2600.50"; "3,5" → "3.5"; "2600.5" → "2600.5" */
function numeroBR(v: string): string {
  const s = v.replace(/[^\d.,]/g, '');
  if (s.includes(',')) return s.replace(/\./g, '').replace(',', '.');
  if (/^\d{1,3}(\.\d{3})+$/.test(s)) return s.replace(/\./g, '');
  return s;
}

// ---------------------------------------------------------------- cadastros
export async function analisarCadastro(_: EstadoForm, f: FormData): Promise<EstadoForm> {
  const r = await rpc('analisar_cadastro', {
    p_usuario_id: texto(f, 'usuario_id'), p_decisao: texto(f, 'decisao'), p_observacao: texto(f, 'observacao') || null,
  });
  if (!r.ok) return { erro: r.mensagem ?? 'Não foi possível salvar.' };
  redirect('/admin/cadastros?ok=1');
}

// ---------------------------------------------------------------- vendedores e lotes
export async function criarVendedor(_: EstadoForm, f: FormData): Promise<EstadoForm> {
  const { tenant } = await equipe();
  const r = await rpc('criar_vendedor', {
    p_tenant_id: tenant.id,
    p_dados: { nome: texto(f, 'nome'), celular: texto(f, 'celular'), cidade: texto(f, 'cidade'), uf: texto(f, 'uf'),
      cpf_cnpj: texto(f, 'cpf_cnpj'), fazenda: texto(f, 'fazenda'), exibir_nome: f.get('exibir_nome') === 'on' },
  });
  if (!r.ok) return { erro: r.mensagem, campo: r.codigo };
  redirect(`/admin/lotes/novo?vendedor=${r.usuario_id}`);
}

export async function salvarLote(_: EstadoForm, f: FormData): Promise<EstadoForm> {
  const { tenant } = await equipe();
  const id = texto(f, 'id') || null;
  const dados = Object.fromEntries(
    ['titulo', 'categoria', 'raca', 'sexo', 'quantidade', 'peso_medio', 'data_pesagem', 'idade_min', 'idade_max', 'cidade', 'uf',
      'retirada_prazo', 'frete', 'tolerancia_quebra', 'preco_inicial', 'preco_reserva', 'incremento', 'vendedor_id']
      .map((k) => [k, texto(f, k).replace(/^R\$\s*/, '')]),
  );
  for (const k of ['preco_inicial', 'preco_reserva', 'incremento', 'peso_medio', 'tolerancia_quebra']) {
    dados[k] = numeroBR(dados[k]);
  }
  const r = await rpc('salvar_lote', {
    p_tenant_id: tenant.id, p_lote_id: id,
    p_dados: { ...dados, sanidade: { vacinas: texto(f, 'vacinas'), vermifugacao: texto(f, 'vermifugacao'), observacoes: texto(f, 'observacoes') } },
  });
  if (!r.ok) return { erro: r.mensagem, campo: r.codigo };
  redirect(`/admin/lotes/${r.lote_id}?salvo=1`);
}

export async function aprovarLote(_: EstadoForm, f: FormData): Promise<EstadoForm> {
  const r = await rpc('aprovar_lote', { p_lote_id: texto(f, 'lote_id') });
  if (!r.ok) return { erro: r.mensagem };
  refresh();
  return { ok: 'Lote aprovado. Agora ele pode entrar num leilão.' };
}

export async function cancelarLote(_: EstadoForm, f: FormData): Promise<EstadoForm> {
  const r = await rpc('cancelar_lote', { p_lote_id: texto(f, 'lote_id'), p_motivo: texto(f, 'motivo') });
  if (!r.ok) return { erro: r.mensagem };
  refresh();
  return { ok: 'Lote cancelado.' };
}

// ---------------------------------------------------------------- leilões
export async function salvarLeilao(_: EstadoForm, f: FormData): Promise<EstadoForm> {
  const { tenant, supabase } = await equipe();
  const id = texto(f, 'id');
  const titulo = texto(f, 'titulo');
  const abre = deLocalBrasilia(texto(f, 'abre_em'));
  const fecha = deLocalBrasilia(texto(f, 'primeiro_fechamento_em'));
  const intervalo = Number(texto(f, 'intervalo_min') || '2');
  if (!titulo) return { erro: 'Informe o nome do leilão.', campo: 'titulo' };
  if (!abre || !fecha) return { erro: 'Informe abertura e primeiro fechamento.', campo: 'abre_em' };
  if (new Date(fecha) <= new Date(abre)) return { erro: 'O fechamento precisa ser depois da abertura.', campo: 'primeiro_fechamento_em' };
  if (!(intervalo >= 0 && intervalo <= 60)) return { erro: 'Intervalo entre lotes de 0 a 60 minutos.', campo: 'intervalo_min' };
  const linha = { tenant_id: tenant.id, titulo, descricao: texto(f, 'descricao') || null, abre_em: abre,
    primeiro_fechamento_em: fecha, intervalo_fechamento: `${intervalo} minutes` };
  const q = id
    ? supabase.from('leiloes').update(linha).eq('id', id).in('status', ['rascunho', 'agendado']).select('id').single()
    : supabase.from('leiloes').insert(linha).select('id').single();
  const { data, error } = await q;
  if (error || !data) return { erro: 'Não foi possível salvar (leilão já aberto?).' };
  redirect(`/admin/leiloes/${data.id}?salvo=1`);
}

export async function incluirLote(_: EstadoForm, f: FormData): Promise<EstadoForm> {
  const r = await rpc('definir_leilao_do_lote', { p_lote_id: texto(f, 'lote_id'), p_leilao_id: texto(f, 'leilao_id') || null });
  if (!r.ok) return { erro: r.mensagem };
  refresh();
  return {};
}

export async function agendarLeilao(_: EstadoForm, f: FormData): Promise<EstadoForm> {
  const r = await rpc('agendar_leilao', { p_leilao_id: texto(f, 'leilao_id') });
  if (!r.ok) return { erro: r.mensagem ?? 'Não foi possível agendar.' };
  refresh();
  return { ok: `Leilão agendado com ${r.lotes_agendados} lote(s). Os lotes abrem sozinhos no horário.` };
}

// ---------------------------------------------------------------- pós-venda
export async function confirmarPagamento(_: EstadoForm, f: FormData): Promise<EstadoForm> {
  const r = await rpc('confirmar_pagamento', { p_venda_id: texto(f, 'venda_id'), p_observacao: texto(f, 'observacao') || null });
  if (!r.ok) return { erro: r.mensagem };
  refresh();
  return { ok: 'Pagamento confirmado.' };
}
