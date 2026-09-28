"use server";

import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { APIError } from "better-auth/api";
import { auth } from "@/lib/auth";

export type SetupState =
  | { step: "password"; error?: string }
  | { step: "confirm"; totpURI: string; secret: string; backupCodes: string[]; error?: string };

/** Étape 1 : mot de passe confirmé -> clé TOTP et codes de secours. */
export async function startTwoFactorAction(_prev: SetupState, form: FormData): Promise<SetupState> {
  const password = String(form.get("password") ?? "");
  if (!password) return { step: "password", error: "Mot de passe obligatoire." };

  try {
    const res = await auth.api.enableTwoFactor({ body: { password }, headers: await headers() });
    if (!("totpURI" in res)) return { step: "password", error: "Méthode d'authentification inattendue." };
    const secret = new URL(res.totpURI).searchParams.get("secret") ?? "";
    return { step: "confirm", totpURI: res.totpURI, secret, backupCodes: res.backupCodes };
  } catch (e) {
    if (e instanceof APIError) return { step: "password", error: "Mot de passe incorrect." };
    throw e;
  }
}

/** Étape 2 : premier code valide -> double authentification activée. */
export async function confirmTwoFactorAction(prev: SetupState, form: FormData): Promise<SetupState> {
  if (prev.step !== "confirm") return { step: "password" };
  const code = String(form.get("code") ?? "").replace(/\s/g, "");
  if (!/^\d{6}$/.test(code)) return { ...prev, error: "Le code comporte 6 chiffres." };

  try {
    await auth.api.verifyTOTP({ body: { code }, headers: await headers() });
  } catch (e) {
    if (e instanceof APIError) return { ...prev, error: "Code invalide ou expiré." };
    throw e;
  }
  redirect("/tableau-de-bord");
}
