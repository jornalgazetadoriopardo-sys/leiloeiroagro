// Banco de teste: sobe um Postgres temporário (ou usa TEST_DATABASE_URL),
// aplica o stub do Supabase e todas as migrações em ordem.
import { execFileSync, spawn } from 'node:child_process';
import { mkdtempSync, readdirSync, readFileSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const aqui = path.dirname(fileURLToPath(import.meta.url));
const raiz = path.resolve(aqui, '..');

function binPg(nome) {
  if (process.env.PG_BIN) return path.join(process.env.PG_BIN, nome);
  for (const v of ['17', '16', '15']) {
    const p = `/usr/lib/postgresql/${v}/bin/${nome}`;
    if (existsSync(p)) return p;
  }
  return nome; // no PATH
}

export async function subirBanco() {
  let url = process.env.TEST_DATABASE_URL;
  let parar = async () => {};

  if (!url) {
    // Como root, o Postgres roda como o usuário "postgres", que precisa
    // enxergar a pasta: por isso usa /tmp (ou PG_TEST_DIR), e não $TMPDIR.
    const root = process.getuid?.() === 0;
    const base = process.env.PG_TEST_DIR || (root ? '/tmp' : tmpdir());
    const dir = mkdtempSync(path.join(base, 'pregao-pg-'));
    const dados = path.join(dir, 'dados');
    const porta = 55000 + Math.floor(Math.random() * 5000);
    const opcoesUsuario = root ? { uid: uidPostgres(), gid: gidPostgres() } : {};
    if (opcoesUsuario.uid !== undefined) execFileSync('chown', ['-R', 'postgres:postgres', dir]);
    execFileSync(binPg('initdb'), ['-D', dados, '-U', 'postgres', '-A', 'trust', '--no-sync', '-E', 'UTF8'], { stdio: ['ignore', 'ignore', 'inherit'], ...opcoesUsuario });
    const proc = spawn(binPg('postgres'), ['-D', dados, '-p', String(porta), '-k', dir, '-c', 'listen_addresses=', '-c', 'fsync=off'], { stdio: 'ignore', ...opcoesUsuario });
    url = `postgresql://postgres@/postgres?host=${encodeURIComponent(dir)}&port=${porta}`;
    await esperarPronto(url);
    parar = async () => {
      proc.kill('SIGINT');
      await new Promise((r) => proc.once('exit', r));
      rmSync(dir, { recursive: true, force: true });
    };
  }

  const admin = new pg.Client({ connectionString: url });
  await admin.connect();
  await admin.query(readFileSync(path.join(aqui, 'stub_supabase.sql'), 'utf8'));
  const migracoes = readdirSync(path.join(raiz, 'migrations')).filter((f) => f.endsWith('.sql')).sort();
  for (const m of migracoes) {
    try {
      await admin.query(readFileSync(path.join(raiz, 'migrations', m), 'utf8'));
    } catch (e) {
      throw new Error(`Falha na migração ${m}: ${e.message}`);
    }
  }
  return { url, admin, parar: async () => { await admin.end(); await parar(); } };
}

function uidPostgres() { return Number(execFileSync('id', ['-u', 'postgres']).toString().trim()); }
function gidPostgres() { return Number(execFileSync('id', ['-g', 'postgres']).toString().trim()); }

async function esperarPronto(url) {
  for (let i = 0; i < 100; i++) {
    const c = new pg.Client({ connectionString: url });
    try { await c.connect(); await c.end(); return; } catch { await new Promise((r) => setTimeout(r, 100)); }
  }
  throw new Error('Postgres de teste não subiu');
}
