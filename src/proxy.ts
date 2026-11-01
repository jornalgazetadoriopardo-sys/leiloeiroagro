import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';
import { SUPABASE_ANON_KEY, SUPABASE_URL, supabaseConfigurado } from '@/lib/supabase/config';

// Renova a sessão do Supabase (cookies) a cada requisição. Não decide
// permissões: quem protege os dados é o RLS no banco.
export async function proxy(request: NextRequest) {
  let resposta = NextResponse.next({ request });
  if (!supabaseConfigurado) return resposta;

  const supabase = createServerClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll: (lista) => {
        lista.forEach(({ name, value }) => request.cookies.set(name, value));
        resposta = NextResponse.next({ request });
        lista.forEach(({ name, value, options }) => resposta.cookies.set(name, value, options));
      },
    },
  });
  await supabase.auth.getUser();
  return resposta;
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|icon.svg|icone|manifest.webmanifest|.*\\.(?:svg|png|jpg|jpeg|webp)$).*)'],
};
