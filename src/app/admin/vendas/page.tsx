import Link from 'next/link';
import { Suspense } from 'react';
import { agoraMs, dataHora, obterEquipe } from '@/lib/admin';
import { brl } from '@/lib/formato';
import { confirmarPagamento } from '../acoes';
import { FormAcao } from '../componentes';
import { Carregando, Restrito } from '../Restrito';

type Pessoa = { nome: string | null; celular: string; cidade: string | null; uf: string | null } | null;

// Pós-venda — seção 11.2 (piloto: pagamento confirmado manualmente, seção 9.1)
export default function Vendas({ searchParams }: PageProps<'/admin/vendas'>) {
  return <Suspense fallback={<Carregando />}><Conteudo searchParams={searchParams} /></Suspense>;
}

async function Conteudo({ searchParams }: { searchParams: PageProps<'/admin/vendas'>['searchParams'] }) {
  const [e, sp] = await Promise.all([obterEquipe(), searchParams]);
  if (!e) return <Restrito />;
  const pagas = sp.filtro === 'pagas';
  const [{ data: vendas }, { data: naoVendidos }] = await Promise.all([
    e.supabase.from('vendas')
      .select('id, total, comissao_comprador, comissao_vendedor, valor_por_cabeca, quantidade, status, pagamento_ate, criado_em, lote:lotes(id, numero, titulo), comprador:usuarios!vendas_comprador_id_fkey(nome, celular, cidade, uf), vendedor:usuarios!vendas_vendedor_id_fkey(nome, celular, cidade, uf)')
      .eq('tenant_id', e.tenant.id).in('status', pagas ? ['pago', 'concluida'] : ['aguardando_pagamento', 'em_atraso'])
      .order('criado_em', { ascending: false }),
    e.supabase.from('lotes').select('id, numero, titulo, lance_atual, preco_reserva, consulta_vendedor_status, consulta_vendedor_ate')
      .eq('tenant_id', e.tenant.id).eq('status', 'nao_vendido').eq('consulta_vendedor_status', 'pendente'),
  ]);
  const agora = agoraMs();

  return (
    <>
      <h1>Pós-venda</h1>
      <p className="sub-titulo">Arremates aguardando pagamento. Confirme quando o PIX ou a transferência cair.</p>
      <div className="filtros-admin">
        <Link href="/admin/vendas" className={!pagas ? 'on' : ''}>Aguardando pagamento</Link>
        <Link href="/admin/vendas?filtro=pagas" className={pagas ? 'on' : ''}>Pagas</Link>
      </div>
      {(naoVendidos ?? []).length > 0 && !pagas && (
        <div className="bloco" style={{ marginBottom: 14 }}>
          <h2>Reserva não atingida — aguardando o vendedor</h2>
          {(naoVendidos ?? []).map((l) => (
            <p key={l.id} className="note">{l.titulo}: maior lance {brl(Number(l.lance_atual))}/cab (reserva {brl(Number(l.preco_reserva))}). Prazo até {dataHora(l.consulta_vendedor_ate)}.</p>
          ))}
        </div>
      )}
      <div className="lista-admin">
        {(vendas ?? []).length === 0 && <div className="vazio">Nada aqui.</div>}
        {(vendas ?? []).map((v) => {
          const lote = v.lote as unknown as { id: string; numero: number | null; titulo: string };
          const comp = v.comprador as unknown as Pessoa;
          const vend = v.vendedor as unknown as Pessoa;
          const atrasado = v.pagamento_ate && new Date(v.pagamento_ate).getTime() < agora;
          const cobrar = Number(v.total) + Number(v.comissao_comprador);
          return (
            <div key={v.id} className="bloco" style={{ marginTop: 0 }}>
              <div className="row-between">
                <b style={{ fontSize: 17 }}>{lote.numero ? `Lote ${String(lote.numero).padStart(2, '0')} · ` : ''}{lote.titulo}</b>
                {pagas ? <span className="etiqueta st-verde">Pago</span>
                  : <span className={`etiqueta ${atrasado ? 'st-laranja' : 'st-cinza'}`}>{atrasado ? 'Em atraso' : `Pagar até ${dataHora(v.pagamento_ate)}`}</span>}
              </div>
              <dl className="dados-lista" style={{ gridTemplateColumns: 'repeat(auto-fit,minmax(180px,1fr))' }}>
                <div><dt>Comprador</dt><dd>{comp?.nome}<br /><span className="note">{comp?.celular} · {comp?.cidade}-{comp?.uf}</span></dd></div>
                <div><dt>Vendedor</dt><dd>{vend?.nome}<br /><span className="note">{vend?.celular}</span></dd></div>
                <div><dt>Arremate</dt><dd>{brl(Number(v.valor_por_cabeca))}/cab × {v.quantidade} = {brl(Number(v.total))}</dd></div>
                <div><dt>Cobrar do comprador</dt><dd className="valor">{brl(cobrar)}</dd><span className="note">inclui comissão {brl(Number(v.comissao_comprador))}</span></div>
                <div><dt>Repassar ao vendedor</dt><dd>{brl(Number(v.total) - Number(v.comissao_vendedor))}</dd><span className="note">desconta comissão {brl(Number(v.comissao_vendedor))}</span></div>
              </dl>
              {!pagas && e.admin && (
                <FormAcao acao={confirmarPagamento} botao="Marcar como pago" classeBotao="btn-aprovar"
                  confirmar={`Confirmar o recebimento de ${brl(cobrar)}?`} className="campo">
                  <input type="hidden" name="venda_id" value={v.id} />
                  <label htmlFor={`obs-${v.id}`}>Referência do pagamento (opcional)</label>
                  <input id={`obs-${v.id}`} name="observacao" placeholder="Ex.: PIX recebido em 05/11, comprovante no WhatsApp" />
                </FormAcao>
              )}
            </div>
          );
        })}
      </div>
    </>
  );
}
