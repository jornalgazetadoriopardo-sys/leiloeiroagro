'use client';
import { useEffect, useState } from 'react';

/**
 * "Agora" corrigido pelo relógio do servidor, atualizado a cada segundo.
 * No primeiro render usa o horário do servidor (sem divergência de hidratação).
 */
export function useAgora(servidorAgora: number): number {
  const [agora, setAgora] = useState(servidorAgora);
  useEffect(() => {
    const desvio = servidorAgora - Date.now();
    const tique = () => setAgora(Date.now() + desvio);
    tique();
    const id = setInterval(tique, 1000);
    return () => clearInterval(id);
  }, [servidorAgora]);
  return agora;
}
