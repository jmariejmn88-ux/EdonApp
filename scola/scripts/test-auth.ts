// Test de bout en bout : Better Auth + withUser() + RLS, sur une base
// jetable où les migrations sont appliquées.
//
//   DATABASE_URL=postgres://scola_app:...@localhost/... \
//   BETTER_AUTH_SECRET=... BETTER_AUTH_URL=http://localhost:3000 \
//   npx tsx scripts/test-auth.ts

import { sql } from "drizzle-orm";
import { createOTP } from "@better-auth/utils/otp";
import { base32 } from "@better-auth/utils/base32";
import { auth } from "../src/lib/auth";
import { pool, withUser } from "../src/lib/db";

let passed = 0;
let failed = 0;
function check(label: string, ok: boolean, detail = "") {
  if (ok) passed++;
  else failed++;
  console.log(`${ok ? "PASS" : "FAIL"} : ${label}${detail ? ` (${detail})` : ""}`);
}
async function refused(label: string, fn: () => Promise<unknown>, reason: string) {
  try {
    await fn();
    check(label, false, "aurait dû être refusé");
  } catch (e) {
    // Drizzle enveloppe l'erreur Postgres : le motif réel est dans `cause`.
    const err = e as Error & { cause?: Error };
    const msg = [err.message, err.cause?.message].filter(Boolean).join(" | ");
    check(label, msg.includes(reason), err.cause?.message ?? err.message);
  }
}

const stamp = Date.now();
const directeur = { name: "Directeur A", email: `directeur.${stamp}@test.ci`, password: "motdepasse-A-123" };
const autre = { name: "Directeur B", email: `autre.${stamp}@test.ci`, password: "motdepasse-B-456" };

// Connexion : renvoie le cookie de session posé par Better Auth.
async function signIn(email: string, password: string) {
  const res = await auth.api.signInEmail({ body: { email, password }, asResponse: true });
  const cookie = (res.headers.getSetCookie?.() ?? []).map((c) => c.split(";")[0]).join("; ");
  return { res, cookie, body: await res.json().catch(() => null) };
}

async function main() {
  // 1. Inscription
  const a = await auth.api.signUpEmail({ body: directeur });
  const b = await auth.api.signUpEmail({ body: autre });
  check("inscription : identifiant UUID généré par Postgres", /^[0-9a-f-]{36}$/.test(a.user.id), a.user.id);

  const profil = await withUser(a.user.id, (db) =>
    db.execute(sql`select full_name from public.profiles where id = ${a.user.id}`));
  check("profil métier créé automatiquement", profil.rows[0]?.full_name === "Directeur A");

  const hash = await pool.query(`select password from account where "userId" = $1`, [a.user.id]);
  check("mot de passe stocké sous forme d'empreinte", !!hash.rows[0]?.password && hash.rows[0].password !== directeur.password);

  // 2. Connexion
  const bad = await signIn(directeur.email, "mauvais-mot-de-passe");
  check("mauvais mot de passe refusé", bad.res.status === 401, `statut ${bad.res.status}`);

  const good = await signIn(directeur.email, directeur.password);
  const session = await auth.api.getSession({ headers: new Headers({ cookie: good.cookie }) });
  check("session retrouvée à partir du cookie", session?.user.id === a.user.id);

  // 3. Données métier au nom de l'utilisateur de la session
  const orgId = await withUser(session!.user.id, async (db) => {
    const r = await db.execute(sql`select public.create_organization('Groupe A', 'École A') as id`);
    return r.rows[0].id as string;
  });
  check("création de l'école au nom de l'utilisateur connecté", typeof orgId === "string");

  const vuParA = await withUser(a.user.id, (db) => db.execute(sql`select id from public.organizations`));
  const vuParB = await withUser(b.user.id, (db) => db.execute(sql`select id from public.organizations`));
  check("le directeur A voit son école", vuParA.rows.length === 1);
  check("le directeur B ne voit pas l'école de A", vuParB.rows.length === 0);

  // 4. Sécurité par défaut
  await refused("connexion applicative sans withUser : aucune donnée métier",
    () => pool.query("select * from public.students"), "permission denied");
  await refused("withUser refuse un identifiant qui n'est pas un UUID",
    () => withUser("1 or 1=1", async () => null), "invalide");
  await refused("requête utilisateur : mots de passe invisibles",
    () => withUser(a.user.id, (db) => db.execute(sql`select password from auth.account`)), "permission denied");

  // 5. Double authentification (TOTP)
  const headers = new Headers({ cookie: good.cookie });
  const enabled = await auth.api.enableTwoFactor({ body: { password: directeur.password }, headers });
  if (!("totpURI" in enabled)) throw new Error("Méthode TOTP attendue");
  const secretB32 = new URL(enabled.totpURI).searchParams.get("secret")!;
  const secret = new TextDecoder().decode(base32.decode(secretB32));
  const code = await createOTP(secret).totp();
  await auth.api.verifyTOTP({ body: { code }, headers });
  const flag = await pool.query(`select "twoFactorEnabled" from "user" where id = $1`, [a.user.id]);
  check("double authentification activée après un code valide", flag.rows[0]?.twoFactorEnabled === true);

  const again = await signIn(directeur.email, directeur.password);
  check("connexion suivante : second facteur exigé",
    again.body?.twoFactorRedirect === true, JSON.stringify(again.body));
}

main()
  .catch((e) => { failed++; console.error("ERREUR :", e); })
  .finally(async () => {
    await pool.end();
    console.log(`\n${passed} PASS, ${failed} FAIL`);
    process.exit(failed ? 1 : 0);
  });
