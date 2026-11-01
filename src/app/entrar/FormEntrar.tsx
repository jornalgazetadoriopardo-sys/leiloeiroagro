'use client';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import { IconeAlerta } from '@/components/Icones';
import { iniciarCadastro } from '@/lib/acoes-conta';
import { mascaraCelular, soDigitos } from '@/lib/brasil';
import { clienteNavegador } from '@/lib/supabase/client';
import { supabaseConfigurado } from '@/lib/supabase/config';

type Canal = 'sms' | 'whatsapp';

export function FormEntrar({ canal }: { canal: Canal }) {
  const router = useRouter();
  const [etapa, setEtapa] = useState<'celular' | 'codigo'>('celular');
  const [celular, setCelular] = useState('');
  const [codigo, setCodigo] = useState('');
  const [erro, setErro] = useState('');
  const [aguardando, iniciar] = useTransition();
  const telefone = '+55' + soDigitos(celular);
  const meio = canal === 'whatsapp' ? 'WhatsApp' : 'SMS';

  function enviarCodigo(e: React.FormEvent) {
    e.preventDefault();
    setErro('');
    if (soDigitos(celular).length !== 11) {
      setErro('Informe o celular com DDD, por exemplo (19) 99999-8888.');
      return;
    }
    if (!supabaseConfigurado) {
      setErro('O sistema ainda não está ligado ao banco de dados.');
      return;
    }
    iniciar(async () => {
      const { error } = await clienteNavegador().auth.signInWithOtp({ phone: telefone, options: { channel: canal } });
      if (error) {
        setErro(error.status === 429
          ? 'Muitas tentativas. Espere um minuto e tente de novo.'
          : 'Não conseguimos enviar o código. Confira o número e tente de novo.');
        return;
      }
      setEtapa('codigo');
    });
  }

  function confirmarCodigo(e: React.FormEvent) {
    e.preventDefault();
    setErro('');
    if (soDigitos(codigo).length !== 6) {
      setErro('O código tem 6 números.');
      return;
    }
    iniciar(async () => {
      const { error } = await clienteNavegador().auth.verifyOtp({ phone: telefone, token: soDigitos(codigo), type: 'sms' });
      if (error) {
        setErro('Código incorreto ou vencido. Confira ou peça um novo.');
        return;
      }
      const r = await iniciarCadastro();
      if (!r.ok || !r.destino) {
        setErro(r.mensagem ?? 'Não foi possível entrar agora.');
        return;
      }
      router.replace(r.destino);
      router.refresh();
    });
  }

  return (
    <div className="cartao">
      {etapa === 'celular' ? (
        <form onSubmit={enviarCodigo} noValidate>
          <h1>Entrar</h1>
          <p className="intro">Informe seu celular. Vamos mandar um código por {meio} para confirmar que é você.</p>
          <div className={`campo${erro ? ' erro' : ''}`}>
            <label htmlFor="celular">Celular com DDD</label>
            <input id="celular" type="tel" inputMode="numeric" autoComplete="tel-national" placeholder="(19) 99999-8888"
              value={celular} onChange={(e) => setCelular(mascaraCelular(e.target.value))} aria-describedby="erro-entrar" />
          </div>
          <Erro texto={erro} />
          <button className="btn-primary btn-bloco" type="submit" disabled={aguardando}>
            {aguardando ? 'Enviando…' : 'Receber código'}
          </button>
          <p className="note" style={{ marginTop: 16 }}>
            Ao continuar você concorda em receber o código neste número. <Link href="/termos#privacidade">Privacidade</Link>
          </p>
        </form>
      ) : (
        <form onSubmit={confirmarCodigo} noValidate>
          <h1>Digite o código</h1>
          <p className="intro">Mandamos um código de 6 números por {meio} para <b>{celular}</b>.</p>
          <div className={`campo${erro ? ' erro' : ''}`}>
            <label htmlFor="codigo">Código</label>
            <input id="codigo" className="codigo-otp" type="text" inputMode="numeric" autoComplete="one-time-code"
              maxLength={6} value={codigo} onChange={(e) => setCodigo(soDigitos(e.target.value).slice(0, 6))}
              aria-describedby="erro-entrar" autoFocus />
          </div>
          <Erro texto={erro} />
          <button className="btn-primary btn-bloco" type="submit" disabled={aguardando}>
            {aguardando ? 'Confirmando…' : 'Confirmar e entrar'}
          </button>
          <div className="row-between" style={{ marginTop: 12 }}>
            <button type="button" className="btn-link" onClick={() => { setEtapa('celular'); setCodigo(''); setErro(''); }}>
              Trocar número
            </button>
            <button type="button" className="btn-link" disabled={aguardando} onClick={enviarCodigo}>
              Mandar outro código
            </button>
          </div>
        </form>
      )}
    </div>
  );
}

function Erro({ texto }: { texto: string }) {
  return (
    <div id="erro-entrar" role="alert" aria-live="assertive" style={{ marginTop: texto ? 10 : 0 }}>
      {texto && <div className="msg-erro"><IconeAlerta />{texto}</div>}
    </div>
  );
}
