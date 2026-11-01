import type { Metadata } from 'next';
import { Suspense } from 'react';
import { FormEntrar } from './FormEntrar';
import { FormSenha } from './FormSenha';

export const metadata: Metadata = { title: 'Entrar – Pregão do Campo' };

// Passo 1 da seção 5.1. NEXT_PUBLIC_LOGIN_MODO:
//   "senha"  → celular + senha (testes, sem SMS) — padrão enquanto o SMS não está ligado
//   "codigo" → código por SMS ou WhatsApp (NEXT_PUBLIC_OTP_CANAL)
export default function Entrar() {
  const porCodigo = process.env.NEXT_PUBLIC_LOGIN_MODO === 'codigo';
  return (
    <main className="pagina-estreita">
      <Suspense fallback={<div className="skeleton" style={{ minHeight: 300 }} />}>
        {porCodigo
          ? <FormEntrar canal={process.env.NEXT_PUBLIC_OTP_CANAL === 'whatsapp' ? 'whatsapp' : 'sms'} />
          : <FormSenha />}
      </Suspense>
    </main>
  );
}
