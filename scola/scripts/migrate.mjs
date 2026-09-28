// Applique les migrations SQL de db/migrations dans l'ordre.
//
//   DATABASE_URL_OWNER=postgres://...  npm run db:migrate
//
// Utilise la connexion PROPRIÉTAIRE (celle fournie par Neon), jamais
// celle de l'application (scola_app). Chaque fichier est appliqué dans
// une transaction : en cas d'erreur, il n'est pas appliqué du tout.
// Les fichiers déjà appliqués sont notés dans public._migrations.

import { readdir, readFile } from "node:fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import pg from "pg";

const url = process.env.DATABASE_URL_OWNER;
if (!url) {
  console.error("DATABASE_URL_OWNER manquant (connexion propriétaire de la base).");
  process.exit(1);
}

const dir = join(dirname(fileURLToPath(import.meta.url)), "..", "db", "migrations");
const files = (await readdir(dir)).filter((f) => f.endsWith(".sql")).sort();

const client = new pg.Client({ connectionString: url });
await client.connect();

try {
  await client.query(`
    create table if not exists public._migrations (
      name        text primary key,
      applied_at  timestamptz not null default now()
    )`);
  const { rows } = await client.query("select name from public._migrations");
  const applied = new Set(rows.map((r) => r.name));

  let count = 0;
  for (const file of files) {
    if (applied.has(file)) continue;
    const sql = await readFile(join(dir, file), "utf8");
    process.stdout.write(`→ ${file} ... `);
    try {
      await client.query("begin");
      await client.query(sql);
      await client.query("insert into public._migrations (name) values ($1)", [file]);
      await client.query("commit");
      console.log("ok");
      count++;
    } catch (err) {
      await client.query("rollback");
      console.log("ÉCHEC");
      throw err;
    }
  }
  console.log(count ? `${count} migration(s) appliquée(s).` : "Base déjà à jour.");
} finally {
  await client.end();
}
