'use client';
import { createBrowserClient } from '@supabase/ssr';
import { SUPABASE_ANON_KEY, SUPABASE_URL } from './config';

let cliente: ReturnType<typeof createBrowserClient> | undefined;

/** Cliente Supabase do navegador (realtime, login). Um por aba. */
export function clienteNavegador() {
  cliente ??= createBrowserClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  return cliente;
}
