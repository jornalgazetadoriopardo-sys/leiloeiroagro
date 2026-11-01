import Link from 'next/link';
import { Suspense } from 'react';
import { obterEquipe } from '@/lib/admin';
import { UFS } from '@/lib/brasil';
import { criarVendedor } from '../../acoes';
import { FormAcao } from '../../componentes';
import { Carregando, Restrito } from '../../Restrito';

export default function NovoVendedor() {
  return <Suspense fallback={<Carregando />}><Conteudo /></Suspense>;
}

async function Conteudo() {
  const e = await obterEquipe();
  if (!e) return <Restrito />;
  return (
    <>
      <Link href="/admin/lotes/novo" className="voltar">‹ Novo lote</Link>
      <h1>Novo vendedor</h1>
      <p className="sub-titulo">Cadastrado pela leiloeira. O vendedor não precisa entrar no sistema nesta fase.</p>
      <FormAcao acao={criarVendedor} botao="Salvar vendedor" classeBotao="btn-primary btn-bloco" className="bloco">
        <div className="grade-form" style={{ maxWidth: 760 }}>
          <div className="campo largo"><label htmlFor="nome">Nome completo</label><input id="nome" name="nome" /></div>
          <div className="campo"><label htmlFor="celular">Celular com DDD</label><input id="celular" name="celular" inputMode="tel" /></div>
          <div className="campo"><label htmlFor="cpf_cnpj">CPF ou CNPJ (opcional)</label><input id="cpf_cnpj" name="cpf_cnpj" inputMode="numeric" /></div>
          <div className="campo"><label htmlFor="cidade">Cidade</label><input id="cidade" name="cidade" /></div>
          <div className="campo"><label htmlFor="uf">UF</label><select id="uf" name="uf" defaultValue=""><option value="">—</option>{UFS.map((u) => <option key={u}>{u}</option>)}</select></div>
          <div className="campo largo"><label htmlFor="fazenda">Nome da fazenda</label><input id="fazenda" name="fazenda" /></div>
          <label className="aceite largo"><input type="checkbox" name="exibir_nome" /><span>Vendedor autoriza mostrar o nome da fazenda (senão aparece como &quot;Fazenda #128&quot;).</span></label>
        </div>
      </FormAcao>
    </>
  );
}
