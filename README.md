# Pregão do Campo

Leilão online de gado **por tempo**, com compradores e vendedores verificados.
Especificação completa: [`docs/GUIA-SISTEMA-LEILAO.md`](docs/GUIA-SISTEMA-LEILAO.md).
Protótipo visual: [`docs/prototipo/index.html`](docs/prototipo/index.html).
Andamento: [`docs/ROADMAP-FASE-1.md`](docs/ROADMAP-FASE-1.md).

## Estrutura

| Pasta | Conteúdo |
|---|---|
| `src/app` | Next.js 16 (App Router, PWA) |
| `src/components` | Componentes da interface |
| `src/lib` | Formatação, catálogo, clientes Supabase |
| `supabase/migrations` | Banco multi-tenant, RLS e motor de lances (SQL) |
| `supabase/tests` | Testes do motor contra um Postgres real |

## Rodar localmente

```bash
npm install
cp .env.example .env.local   # já aponta para o projeto Supabase do piloto
npm run dev                  # http://localhost:3000
```

## Testes

```bash
npm run test:db   # sobe um Postgres temporário, aplica as migrações e roda os testes do motor
npm test          # typecheck + lint + test:db
```

`test:db` precisa dos binários do PostgreSQL 15+ (`initdb`, `postgres`). Para usar um banco
existente e vazio: `TEST_DATABASE_URL=postgres://... npm run test:db`.

## Banco no Supabase

1. Crie o projeto (plano Pro, seção 4.2) e habilite a extensão **pg_cron** (Database → Extensions).
2. `npx supabase login && npx supabase link --project-ref <ref>`
3. `npx supabase db push` aplica `supabase/migrations`.
4. Crie a leiloeira: `insert into tenants (nome, subdominio) values ('Nome da leiloeira', 'piloto');`

O relógio (`processar_relogio`) roda pelo pg_cron a cada 5 s: abre lotes agendados, encerra os vencidos
e expira consultas ao vendedor. Lances após o término são recusados mesmo que o relógio atrase.
