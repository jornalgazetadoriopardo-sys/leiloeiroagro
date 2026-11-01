import Link from 'next/link';
import { Suspense } from 'react';
import { dataHora, obterEquipe } from '@/lib/admin';
import { mascaraCpfCnpj } from '@/lib/brasil';
import { Carregando, Restrito } from '../Restrito';

// Fila de cadastros — seção 11.2
const FILTROS = [
  { id: 'pendente', rotulo: 'Para analisar' },
  { id: 'divergente', rotulo: 'Aguardando ajuste' },
  { id: 'verificado', rotulo: 'Verificados' },
  { id: 'outros', rotulo: 'Recusados / suspensos' },
  { id: 'incompleto', rotulo: 'Não terminaram' },
];

const ETIQUETA: Record<string, [string, string]> = {
  pendente: ['Pendente', 'st-cinza'], verificado: ['Verificado', 'st-verde'], divergente: ['Ajuste pedido', 'st-laranja'],
  recusado: ['Recusado', 'st-cinza'], suspenso: ['Suspenso', 'st-laranja'],
};

export default function Cadastros({ searchParams }: PageProps<'/admin/cadastros'>) {
  return <Suspense fallback={<Carregando />}><Conteudo searchParams={searchParams} /></Suspense>;
}

async function Conteudo({ searchParams }: { searchParams: PageProps<'/admin/cadastros'>['searchParams'] }) {
  const [e, sp] = await Promise.all([obterEquipe(), searchParams]);
  if (!e) return <Restrito />;
  const filtro = typeof sp.filtro === 'string' ? sp.filtro : 'pendente';

  let q = e.supabase.from('usuarios')
    .select('id, nome, celular, cpf_cnpj, cidade, uf, status_verificacao, cadastro_enviado_em, criado_em')
    .eq('tenant_id', e.tenant.id).order('cadastro_enviado_em', { ascending: true, nullsFirst: false }).limit(200);
  if (filtro === 'incompleto') q = q.is('cadastro_enviado_em', null);
  else if (filtro === 'outros') q = q.in('status_verificacao', ['recusado', 'suspenso']);
  else q = q.eq('status_verificacao', filtro).not('cadastro_enviado_em', 'is', null);
  const { data } = await q;

  return (
    <>
      <h1>Cadastros</h1>
      <p className="sub-titulo">Confira os documentos e decida: aprovar, pedir ajuste ou recusar.</p>
      {sp.ok && <div className="banner b-green" style={{ marginBottom: 14 }}>Decisão registrada. O usuário foi avisado.</div>}
      <div className="filtros-admin">
        {FILTROS.map((f) => <Link key={f.id} href={`/admin/cadastros?filtro=${f.id}`} className={f.id === filtro ? 'on' : ''}>{f.rotulo}</Link>)}
      </div>
      <div className="lista-admin">
        {(data ?? []).length === 0 && <div className="vazio">Nada aqui.</div>}
        {(data ?? []).map((u) => {
          const [rotulo, classe] = ETIQUETA[u.status_verificacao] ?? ['', ''];
          return (
            <Link key={u.id} href={`/admin/cadastros/${u.id}`} className="item-admin">
              <div className="principal">
                <b>{u.nome ?? 'Sem nome'}</b>
                <span>{u.cpf_cnpj ? mascaraCpfCnpj(u.cpf_cnpj) : 'CPF não informado'} · {u.cidade ? `${u.cidade}-${u.uf}` : '—'} · {u.celular}</span>
              </div>
              <span className="note">{u.cadastro_enviado_em ? `Enviado ${dataHora(u.cadastro_enviado_em)}` : `Criado ${dataHora(u.criado_em)}`}</span>
              <span className={`etiqueta ${classe}`}>{u.cadastro_enviado_em ? rotulo : 'Incompleto'}</span>
            </Link>
          );
        })}
      </div>
    </>
  );
}
