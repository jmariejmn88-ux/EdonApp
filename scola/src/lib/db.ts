// Accès à la base Postgres (Neon).
//
// L'application se connecte avec le rôle `scola_app` (DATABASE_URL).
// Seul, ce rôle ne voit que les tables de connexion (schéma `auth`),
// utilisées par Better Auth. Pour lire ou écrire des données métier,
// passer par withUser() : la transaction endosse le rôle `authenticated`
// et indique l'utilisateur, ce qui active les règles RLS.

import { Pool, type PoolClient } from "pg";
import { drizzle, type NodePgDatabase } from "drizzle-orm/node-postgres";

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  throw new Error("DATABASE_URL manquant (connexion du rôle scola_app).");
}

// Une seule pool par processus (évite d'en recréer à chaque rechargement en dev).
const globalForDb = globalThis as unknown as { scolaPool?: Pool };
export const pool = globalForDb.scolaPool ?? new Pool({ connectionString, max: 10 });
if (process.env.NODE_ENV !== "production") globalForDb.scolaPool = pool;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type UserDb = NodePgDatabase;

/**
 * Exécute `fn` au nom de l'utilisateur `userId`, dans une transaction où
 * les règles RLS s'appliquent. L'identifiant doit venir d'une session
 * Better Auth vérifiée côté serveur, jamais d'une donnée envoyée par le
 * navigateur.
 */
export async function withUser<T>(userId: string, fn: (db: UserDb) => Promise<T>): Promise<T> {
  if (!UUID.test(userId)) throw new Error("Identifiant utilisateur invalide.");

  const client: PoolClient = await pool.connect();
  try {
    await client.query("begin");
    await client.query("set local role authenticated");
    await client.query("select set_config('app.user_id', $1, true)", [userId]);
    const result = await fn(drizzle(client));
    await client.query("commit");
    return result;
  } catch (err) {
    await client.query("rollback");
    throw err;
  } finally {
    client.release();
  }
}
