// Configuration Better Auth (côté serveur).
// Les tables du schéma `auth` portent les noms par défaut de Better Auth
// (migration 0005) : aucune correspondance à déclarer ici.

import { betterAuth } from "better-auth";
import { nextCookies } from "better-auth/next-js";
import { twoFactor } from "better-auth/plugins/two-factor";
import { pool } from "./db";

export const auth = betterAuth({
  appName: "Scola",
  database: pool,
  emailAndPassword: { enabled: true, minPasswordLength: 10 },
  advanced: { database: { generateId: "uuid" } },
  plugins: [twoFactor({ issuer: "Scola" }), nextCookies()],
});
