#!/usr/bin/env bash
# Junta todas as migrações num arquivo único para colar no SQL Editor do Supabase.
# Uso: bash scripts/gerar-instalacao.sh
set -euo pipefail
cd "$(dirname "$0")/.."
saida=supabase/instalar-supabase.sql
{
  echo "-- Pregão do Campo — instalação completa do banco"
  echo "-- GERADO por scripts/gerar-instalacao.sh a partir de supabase/migrations. Não edite à mão."
  echo "-- Como usar: Supabase → SQL Editor → cole tudo → Run."
  echo "-- Antes: Database → Extensions → habilite pg_cron."
  for f in supabase/migrations/*.sql; do echo; echo "-- ===== $f ====="; cat "$f"; done
  echo
  echo "-- Leiloeira piloto"
  echo "insert into public.tenants (nome, subdominio) values ('Pregão do Campo', 'piloto') on conflict (subdominio) do nothing;"
} > "$saida"
echo "Gerado: $saida"
