// Parcours complet dans un vrai navigateur (Chromium), sur l'application
// lancée en local (npm run build && npm start) et une base jetable.
//
//   APP_URL=http://localhost:3000 npx tsx scripts/e2e-browser.ts

import { chromium, type Page } from "playwright";
import { createOTP } from "@better-auth/utils/otp";
import { base32 } from "@better-auth/utils/base32";

const APP = process.env.APP_URL ?? "http://localhost:3000";
const stamp = Date.now();
const directeur = { name: "Awa Koné", email: `awa.${stamp}@test.ci`, password: "palmiers-2026-secret" };
const autre = { name: "Yao N'Guessan", email: `yao.${stamp}@test.ci`, password: "baobab-2026-secret" };

let passed = 0;
let failed = 0;
function check(label: string, ok: boolean, detail = "") {
  if (ok) passed++;
  else failed++;
  console.log(`${ok ? "PASS" : "FAIL"} : ${label}${detail ? ` (${detail})` : ""}`);
}
const path = (page: Page) => new URL(page.url()).pathname + new URL(page.url()).search;

async function totpFrom(secretB32: string) {
  const secret = new TextDecoder().decode(base32.decode(secretB32.trim()));
  return createOTP(secret).totp();
}

async function signUpAndCreateSchool(page: Page, u: typeof directeur, school: string) {
  await page.goto(`${APP}/inscription`);
  await page.fill('input[name="name"]', u.name);
  await page.fill('input[name="email"]', u.email);
  await page.fill('input[name="password"]', u.password);
  await Promise.all([page.waitForURL("**/onboarding"), page.click('button[type="submit"]')]);
  await page.fill('input[name="orgName"]', `Groupe ${school}`);
  await page.fill('input[name="schoolName"]', school);
  // Un directeur est toujours renvoyé vers l'activation obligatoire de la 2FA.
  await Promise.all([page.waitForURL("**/securite?obligatoire=1"), page.click('button[type="submit"]')]);
}

async function enableTwoFactor(page: Page, password: string) {
  await page.fill('input[name="password"]', password);
  await page.click('button[type="submit"]');
  const secret = await page.locator('[data-testid="totp-secret"]').innerText();
  await page.fill('input[name="code"]', await totpFrom(secret));
  await Promise.all([page.waitForURL("**/tableau-de-bord"), page.click('button[type="submit"]')]);
  return secret;
}

async function main() {
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH ?? "/opt/pw-browsers/chromium" });
  const ctxA = await browser.newContext();
  const page = await ctxA.newPage();

  // 1. Inscription + création de l'école -> 2FA imposée au directeur
  await signUpAndCreateSchool(page, directeur, "Collège Les Palmiers");
  check("directeur redirigé vers l'activation obligatoire de la 2FA", path(page) === "/securite?obligatoire=1", path(page));

  // 2. Accès au tableau de bord bloqué tant que la 2FA n'est pas active
  await page.goto(`${APP}/tableau-de-bord`);
  check("tableau de bord inaccessible sans 2FA", path(page) === "/securite?obligatoire=1", path(page));

  // 3. Activation de la 2FA
  const secret = await enableTwoFactor(page, directeur.password);
  const body = await page.locator("main").innerText();
  check("tableau de bord affiché après activation", body.includes("Tableau de bord") && body.includes("Groupe Collège Les Palmiers"));
  check("rôle affiché : directeur", body.includes("Fondateur / Directeur"));

  // 4. Déconnexion puis accès direct refusé
  await Promise.all([page.waitForURL("**/connexion"), page.click('button:has-text("Se déconnecter")')]);
  check("déconnexion", path(page) === "/connexion");
  await page.goto(`${APP}/tableau-de-bord`);
  check("page protégée sans session -> connexion", path(page) === "/connexion", path(page));

  // 5. Mauvais mot de passe
  await page.fill('input[name="email"]', directeur.email);
  await page.fill('input[name="password"]', "pas-le-bon-mot-de-passe");
  await page.click('button[type="submit"]');
  await page.locator('p.error[role="alert"]').waitFor();
  check("mauvais mot de passe : message d'erreur", (await page.locator('p.error[role="alert"]').innerText()).includes("incorrect"));

  // 6. Bon mot de passe -> second facteur exigé
  await page.fill('input[name="password"]', directeur.password);
  await page.click('button[type="submit"]');
  await page.waitForURL("**/connexion/2fa", { timeout: 15000 }).catch(async () => {
    console.log("   état :", path(page), "|", await page.locator("main").innerText());
  });
  check("connexion : second facteur exigé", path(page) === "/connexion/2fa");

  await page.fill('input[name="code"]', "000000");
  await page.click('button[type="submit"]');
  await page.locator('p.error[role="alert"]').waitFor();
  check("code 2FA erroné refusé", (await page.locator('p.error[role="alert"]').innerText()).includes("invalide"));

  await page.fill('input[name="code"]', await totpFrom(secret));
  await Promise.all([page.waitForURL("**/tableau-de-bord"), page.click('button[type="submit"]')]);
  check("code 2FA valide -> tableau de bord", path(page) === "/tableau-de-bord");

  // 7. Un autre directeur ne voit que sa propre école
  const ctxB = await browser.newContext();
  const pageB = await ctxB.newPage();
  await signUpAndCreateSchool(pageB, autre, "École Le Baobab");
  await enableTwoFactor(pageB, autre.password);
  const bodyB = await pageB.locator("main").innerText();
  check("second directeur : voit son école", bodyB.includes("Groupe École Le Baobab"));
  check("second directeur : ne voit pas l'autre école", !bodyB.includes("Les Palmiers"));

  await browser.close();
}

main()
  .catch((e) => { failed++; console.error("ERREUR :", e instanceof Error ? e.message.split("\n")[0] : e); })
  .finally(() => {
    console.log(`\n${passed} PASS, ${failed} FAIL`);
    process.exit(failed ? 1 : 0);
  });
