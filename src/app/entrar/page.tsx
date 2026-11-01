import type { Metadata } from 'next';
import { FormEntrar } from './FormEntrar';

export const metadata: Metadata = { title: 'Entrar – Pregão do Campo' };

// Passo 1 da seção 5.1: celular + código de confirmação
export default function Entrar() {
  return (
    <main className="pagina-estreita">
      <FormEntrar canal={process.env.NEXT_PUBLIC_OTP_CANAL === 'whatsapp' ? 'whatsapp' : 'sms'} />
    </main>
  );
}
