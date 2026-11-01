'use client';
import { useEffect, useState } from 'react';
import { clienteNavegador } from '@/lib/supabase/client';
import { supabaseConfigurado } from '@/lib/supabase/config';
import type { LotePublico } from '@/lib/tipos';

// Estado publicado por app.publicar_lote() no canal "lote:<id>"
interface EstadoBroadcast {
  status: LotePublico['status_publico'];
  lance_atual: number | null;
  total: number;
  lance_minimo: number;
  qtd_lances: number;
  termina_em: string;
  prorrogado: boolean;
  lider_codigo: number | null;
}

/**
 * Mantém o lote atualizado em tempo real (Supabase Realtime Broadcast).
 * O cronômetro é só visual: quem decide prazo e lance é o servidor.
 */
export function useEstadoLote(inicial: LotePublico, meuCodigo: number | null, demo: boolean): LotePublico {
  const [lote, setLote] = useState(inicial);

  useEffect(() => {
    if (demo || !supabaseConfigurado) return;
    const supabase = clienteNavegador();
    const canal = supabase
      .channel(`lote:${inicial.id}`)
      .on('broadcast', { event: 'estado' }, ({ payload }: { payload: EstadoBroadcast }) => {
        setLote((atual) => {
          const lidera = meuCodigo != null && payload.lider_codigo === meuCodigo;
          return {
            ...atual,
            status_publico: payload.status,
            lance_atual: payload.lance_atual,
            total_atual: payload.total,
            lance_minimo: payload.lance_minimo,
            qtd_lances: payload.qtd_lances,
            termina_em: payload.termina_em,
            prorrogado: payload.prorrogado,
            voce_lidera: lidera,
            voce_deu_lance: atual.voce_deu_lance || lidera,
          };
        });
      })
      .subscribe();
    return () => {
      supabase.removeChannel(canal);
    };
  }, [inicial.id, meuCodigo, demo]);

  return lote;
}
