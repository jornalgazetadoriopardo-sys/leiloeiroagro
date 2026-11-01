'use client';
import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { useState, useTransition } from 'react';
import { IconeAlerta } from '@/components/Icones';
import { iniciarCadastro } from '@/lib/acoes-conta';
import { mascaraCelular, soDigitos } from '@/lib/brasil';
import { clienteNavegador } from '@/lib/supabase/client';
import { supabaseConfigurado } from '@/lib/supabase/config';

// LOGIN DE TESTE: celular + senha, sem SMS. A conta usa um e-mail interno
// derivado do celular (nenhum e-mail é enviado). Antes do lançamento, trocar
// para o login por código (NEXT_PUBLIC_LOGIN_MODO=codigo).
const emailInterno = (digitos: string) => `${digitos}@celular.pregaodocampo.com.br`;

// Mensagens claras para os erros do Supabase Auth (o código entre parênteses ajuda no suporte)
function mensagemCadastro(codigo: string | undefined, texto: string): string {
  switch (codigo) {
    case 'user_already_exists':
    case 'email_exists':
      return 'Este celular já tem conta. Toque em "Já tenho conta" e entre com a senha.';
    case 'weak_password':
      return 'Senha fraca. Use pelo menos 6 caracteres, misturando letras e números.';
    case 'email_address_not_authorized':
    case 'over_email_send_rate_limit':
      return 'O Supabase está tentando enviar e-mail de confirmação. Desative "Confirm email" em Authentication → Sign In / Providers → Email.';
    case 'signup_disabled':
    case 'email_provider_disabled':
      return 'Cadastro desativado no Supabase. Ative "Allow new users to sign up" e o provedor Email em Authentication.';
    case 'email_address_invalid':
      return 'O Supabase recusou o endereço interno da conta (email_address_invalid).';
    default:
      return `Não foi possível criar a conta (${codigo ?? texto}).`;
  }
}

export function FormSenha() {
  const router = useRouter();
  const voltarParam = useSearchParams().get('voltar');
  const voltar = voltarParam && /^\/(?!\/)/.test(voltarParam) ? voltarParam : null;
  const [criar, setCriar] = useState(false);
  const [celular, setCelular] = useState('');
  const [senha, setSenha] = useState('');
  const [verSenha, setVerSenha] = useState(false);
  const [erro, setErro] = useState('');
  const [aguardando, iniciar] = useTransition();

  function enviar(e: React.FormEvent) {
    e.preventDefault();
    setErro('');
    const digitos = '55' + soDigitos(celular);
    if (soDigitos(celular).length !== 11) return setErro('Informe o celular com DDD, por exemplo (19) 99999-8888.');
    if (senha.length < 6) return setErro('A senha precisa ter pelo menos 6 caracteres.');
    if (!supabaseConfigurado) return setErro('O sistema ainda não está ligado ao banco de dados.');

    iniciar(async () => {
      const auth = clienteNavegador().auth;
      if (criar) {
        const { data, error } = await auth.signUp({
          email: emailInterno(digitos),
          password: senha,
          options: { data: { celular: '+' + digitos } },
        });
        if (error) {
          setErro(mensagemCadastro(error.code, error.message));
          return;
        }
        if (!data.session) {
          setErro('Conta criada, mas o Supabase está pedindo confirmação por e-mail. Desative "Confirm email" em Authentication → Sign In / Providers → Email.');
          return;
        }
      } else {
        const { error } = await auth.signInWithPassword({ email: emailInterno(digitos), password: senha });
        if (error) {
          setErro(error.code === 'invalid_credentials' ? 'Celular ou senha incorretos.'
            : error.code === 'email_not_confirmed' ? 'Conta ainda não confirmada. Desative "Confirm email" no Supabase e crie a conta de novo.'
            : `Não foi possível entrar (${error.code ?? error.message}).`);
          return;
        }
      }
      const r = await iniciarCadastro();
      if (!r.ok || !r.destino) {
        setErro(r.mensagem ?? 'Não foi possível entrar agora.');
        return;
      }
      router.replace(r.destino === '/conta' && voltar ? voltar : r.destino);
      router.refresh();
    });
  }

  return (
    <form className="cartao" onSubmit={enviar} noValidate>
      <h1>{criar ? 'Criar conta' : 'Entrar'}</h1>
      <p className="intro">{criar ? 'Use seu celular e escolha uma senha.' : 'Entre com seu celular e sua senha.'}</p>
      <div className={`campo${erro && !soDigitos(celular) ? ' erro' : ''}`}>
        <label htmlFor="celular">Celular com DDD</label>
        <input id="celular" type="tel" inputMode="numeric" autoComplete="tel-national" placeholder="(19) 99999-8888"
          value={celular} onChange={(e) => setCelular(mascaraCelular(e.target.value))} />
      </div>
      <div className="campo">
        <label htmlFor="senha">{criar ? 'Escolha uma senha' : 'Senha'}</label>
        {criar && <span className="ajuda">Pelo menos 6 caracteres.</span>}
        <div className="senha-linha">
          <input id="senha" type={verSenha ? 'text' : 'password'} autoComplete={criar ? 'new-password' : 'current-password'}
            value={senha} onChange={(e) => setSenha(e.target.value)} />
          <button type="button" className="btn-ghost" onClick={() => setVerSenha((v) => !v)} aria-pressed={verSenha}>
            {verSenha ? 'Ocultar' : 'Mostrar'}
          </button>
        </div>
      </div>
      <div role="alert" aria-live="assertive" style={{ marginTop: erro ? 12 : 0 }}>
        {erro && <div className="msg-erro"><IconeAlerta />{erro}</div>}
      </div>
      <button className="btn-primary btn-bloco" type="submit" disabled={aguardando}>
        {aguardando ? 'Aguarde…' : criar ? 'Criar conta' : 'Entrar'}
      </button>
      <button type="button" className="btn-secundario" style={{ marginTop: 12 }} onClick={() => { setCriar((c) => !c); setErro(''); }}>
        {criar ? 'Já tenho conta' : 'Primeira vez? Criar conta'}
      </button>
      {!criar && <p className="note" style={{ marginTop: 14 }}>Esqueceu a senha? Fale com a leiloeira.</p>}
      <p className="note" style={{ marginTop: 8 }}>
        Versão de teste: o código por SMS será ativado antes do lançamento. <Link href="/termos#privacidade">Privacidade</Link>
      </p>
    </form>
  );
}
