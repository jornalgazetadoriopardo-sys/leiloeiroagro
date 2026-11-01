'use client';
import Link from 'next/link';
import { useActionState } from 'react';
import { IconeAlerta } from '@/components/Icones';
import { UFS } from '@/lib/brasil';
import { salvarLote } from '../acoes';

export interface LoteEditavel {
  id?: string;
  titulo?: string; categoria?: string; raca?: string; sexo?: string; quantidade?: number; peso_medio?: number;
  data_pesagem?: string; idade_min?: number | null; idade_max?: number | null;
  sanidade?: { vacinas?: string; vermifugacao?: string; observacoes?: string };
  cidade?: string; uf?: string; retirada_prazo?: number; frete?: string; tolerancia_quebra?: number | null;
  preco_inicial?: number; preco_reserva?: number | null; incremento?: number | null; vendedor_id?: string;
}

interface Props {
  lote: LoteEditavel;
  categorias: string[];
  vendedores: { id: string; nome: string; cidade: string | null }[];
  bloqueado: boolean;
}

/** Formulário do lote — campos da seção 6.1. As regras valem no servidor (salvar_lote). */
export function FormLote({ lote, categorias, vendedores, bloqueado }: Props) {
  const [estado, despachar, pendente] = useActionState(salvarLote, {});
  const v = (x: unknown) => (x == null ? '' : String(x));
  const erro = (c: string) => (estado.campo === c ? ' erro' : '');

  return (
    <form action={despachar} className="bloco">
      <h2>Dados do lote</h2>
      {bloqueado && <p className="msg-erro"><IconeAlerta />Lote aberto ou encerrado: os dados não podem mais ser alterados.</p>}
      <fieldset disabled={bloqueado} style={{ border: 0, padding: 0, margin: 0 }}>
        {lote.id && <input type="hidden" name="id" value={lote.id} />}
        <div className="grade-form">
          <div className={`campo largo${erro('vendedor_id')}`}>
            <label htmlFor="vendedor_id">Vendedor (oculto para os compradores)</label>
            <select id="vendedor_id" name="vendedor_id" defaultValue={v(lote.vendedor_id)} required>
              <option value="">Escolha…</option>
              {vendedores.map((x) => <option key={x.id} value={x.id}>{x.nome}{x.cidade ? ` · ${x.cidade}` : ''}</option>)}
            </select>
            <span className="ajuda"><Link href="/admin/vendedores/novo">+ Cadastrar novo vendedor</Link></span>
          </div>
          <div className={`campo largo${erro('titulo')}`}>
            <label htmlFor="titulo">Título</label>
            <input id="titulo" name="titulo" defaultValue={v(lote.titulo)} placeholder="Ex.: 30 garrotes Nelore" />
          </div>
          <div className={`campo${erro('categoria')}`}>
            <label htmlFor="categoria">Categoria</label>
            <select id="categoria" name="categoria" defaultValue={v(lote.categoria)}>
              <option value="">Escolha…</option>
              {categorias.map((c) => <option key={c} value={c} style={{ textTransform: 'capitalize' }}>{c}</option>)}
            </select>
          </div>
          <div className={`campo${erro('raca')}`}>
            <label htmlFor="raca">Raça ou cruzamento</label>
            <input id="raca" name="raca" defaultValue={v(lote.raca)} />
          </div>
          <div className={`campo${erro('sexo')}`}>
            <label htmlFor="sexo">Sexo</label>
            <select id="sexo" name="sexo" defaultValue={v(lote.sexo)}>
              <option value="">Escolha…</option>
              <option value="macho">Machos</option><option value="femea">Fêmeas</option><option value="misto">Machos e fêmeas</option>
            </select>
          </div>
          <div className={`campo${erro('quantidade')}`}>
            <label htmlFor="quantidade">Cabeças</label>
            <input id="quantidade" name="quantidade" inputMode="numeric" defaultValue={v(lote.quantidade)} />
          </div>
          <div className={`campo${erro('peso_medio')}`}>
            <label htmlFor="peso_medio">Peso médio (kg)</label>
            <input id="peso_medio" name="peso_medio" inputMode="decimal" defaultValue={v(lote.peso_medio)} />
          </div>
          <div className={`campo${erro('data_pesagem')}`}>
            <label htmlFor="data_pesagem">Data da pesagem</label>
            <input id="data_pesagem" name="data_pesagem" type="date" defaultValue={v(lote.data_pesagem)} />
          </div>
          <div className="campo">
            <label htmlFor="idade_min">Idade mínima (meses)</label>
            <input id="idade_min" name="idade_min" inputMode="numeric" defaultValue={v(lote.idade_min)} />
          </div>
          <div className={`campo${erro('idade_max')}`}>
            <label htmlFor="idade_max">Idade máxima (meses)</label>
            <input id="idade_max" name="idade_max" inputMode="numeric" defaultValue={v(lote.idade_max)} />
          </div>
          <div className="campo">
            <label htmlFor="vacinas">Vacinas</label>
            <input id="vacinas" name="vacinas" defaultValue={v(lote.sanidade?.vacinas)} placeholder="Ex.: aftosa e brucelose em dia" />
          </div>
          <div className="campo">
            <label htmlFor="vermifugacao">Vermifugação</label>
            <input id="vermifugacao" name="vermifugacao" defaultValue={v(lote.sanidade?.vermifugacao)} />
          </div>
          <div className="campo largo">
            <label htmlFor="observacoes">Observações de sanidade</label>
            <textarea id="observacoes" name="observacoes" defaultValue={v(lote.sanidade?.observacoes)} />
          </div>
          <div className={`campo${erro('cidade')}`}>
            <label htmlFor="cidade">Cidade de origem</label>
            <input id="cidade" name="cidade" defaultValue={v(lote.cidade)} />
          </div>
          <div className="campo">
            <label htmlFor="uf">UF</label>
            <select id="uf" name="uf" defaultValue={v(lote.uf)}>
              <option value="">—</option>{UFS.map((u) => <option key={u}>{u}</option>)}
            </select>
          </div>
          <div className="campo">
            <label htmlFor="retirada_prazo">Prazo de retirada (dias)</label>
            <input id="retirada_prazo" name="retirada_prazo" inputMode="numeric" defaultValue={v(lote.retirada_prazo)} placeholder="Padrão da leiloeira" />
          </div>
          <div className="campo">
            <label htmlFor="frete">Frete por conta do</label>
            <select id="frete" name="frete" defaultValue={v(lote.frete) || 'comprador'}>
              <option value="comprador">Comprador</option><option value="vendedor">Vendedor</option><option value="a_combinar">A combinar</option>
            </select>
          </div>
          <div className="campo">
            <label htmlFor="tolerancia_quebra">Tolerância de quebra (%)</label>
            <input id="tolerancia_quebra" name="tolerancia_quebra" inputMode="decimal" defaultValue={v(lote.tolerancia_quebra)} placeholder="Padrão da leiloeira" />
          </div>
          <div className={`campo${erro('preco_inicial')}`}>
            <label htmlFor="preco_inicial">Preço inicial por cabeça (R$)</label>
            <input id="preco_inicial" name="preco_inicial" inputMode="decimal" defaultValue={v(lote.preco_inicial)} />
          </div>
          <div className={`campo${erro('preco_reserva')}`}>
            <label htmlFor="preco_reserva">Preço de reserva (R$/cab, opcional)</label>
            <input id="preco_reserva" name="preco_reserva" inputMode="decimal" defaultValue={v(lote.preco_reserva)} />
            <span className="ajuda">Nunca aparece para o comprador.</span>
          </div>
          <div className="campo">
            <label htmlFor="incremento">Incremento mínimo (R$, opcional)</label>
            <input id="incremento" name="incremento" inputMode="decimal" defaultValue={v(lote.incremento)} placeholder="Padrão da leiloeira" />
          </div>
        </div>
        {estado.erro && <div className="msg-erro" role="alert" style={{ marginTop: 14 }}><IconeAlerta />{estado.erro}</div>}
        <button type="submit" className="btn-primary btn-bloco" disabled={pendente}>{pendente ? 'Salvando…' : 'Salvar lote'}</button>
      </fieldset>
    </form>
  );
}
