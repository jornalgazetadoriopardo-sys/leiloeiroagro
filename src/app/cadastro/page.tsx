import type { Metadata } from 'next';
import { redirect } from 'next/navigation';
import { Suspense } from 'react';
import { obterSessao } from '@/lib/sessao';
import { criarClienteServidor } from '@/lib/supabase/server';
import { FormCadastro, type DocumentoEnviado } from './FormCadastro';

export const metadata: Metadata = { title: 'Cadastro – Pregão do Campo' };

// Passos 2 a 6 da seção 5.1
export default function Cadastro() {
  return (
    <main className="pagina-estreita">
      <Suspense fallback={<div className="skeleton" style={{ minHeight: 420 }} />}>
        <Conteudo />
      </Suspense>
    </main>
  );
}

async function Conteudo() {
  const { tenant, logado, cadastro } = await obterSessao();
  if (!logado || !tenant || !cadastro) redirect('/entrar');
  const podeEditar = cadastro.status_verificacao === 'divergente'
    || (cadastro.status_verificacao === 'pendente' && !cadastro.cadastro_enviado_em);
  if (!podeEditar) redirect('/conta');

  const supabase = await criarClienteServidor();
  const [{ data: docs }, { data: cfg }] = await Promise.all([
    supabase.from('documentos').select('id, tipo, status, criado_em').eq('dono_id', cadastro.id).order('criado_em'),
    supabase.from('configuracoes').select('valor').eq('tenant_id', tenant.id).eq('chave', 'cadastro.selfie_obrigatoria').maybeSingle(),
  ]);
  let selfieObrigatoria = cfg?.valor === true;
  if (!cfg) {
    const { data: padrao } = await supabase.from('configuracoes_padrao').select('valor').eq('chave', 'cadastro.selfie_obrigatoria').single();
    selfieObrigatoria = padrao?.valor === true;
  }

  return (
    <FormCadastro
      tenantId={tenant.id}
      cadastro={cadastro}
      documentos={(docs ?? []) as DocumentoEnviado[]}
      selfieObrigatoria={selfieObrigatoria}
    />
  );
}
