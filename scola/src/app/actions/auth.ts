"use server";

import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { APIError } from "better-auth/api";
import { auth } from "@/lib/auth";

export type FormState = { error: string } | null;

function field(form: FormData, name: string) {
  const v = form.get(name);
  return typeof v === "string" ? v.trim() : "";
}

export async function signUpAction(_prev: FormState, form: FormData): Promise<FormState> {
  const name = field(form, "name");
  const email = field(form, "email").toLowerCase();
  const password = String(form.get("password") ?? "");
  if (!name || !email || !password) return { error: "Tous les champs sont obligatoires." };
  if (password.length < 10) return { error: "Le mot de passe doit contenir au moins 10 caractères." };

  try {
    await auth.api.signUpEmail({ body: { name, email, password }, headers: await headers() });
  } catch (e) {
    if (e instanceof APIError) return { error: "Inscription impossible avec ces informations." };
    throw e;
  }
  redirect("/onboarding");
}

export async function signInAction(_prev: FormState, form: FormData): Promise<FormState> {
  const email = field(form, "email").toLowerCase();
  const password = String(form.get("password") ?? "");
  if (!email || !password) return { error: "Email et mot de passe obligatoires." };

  let needsSecondFactor = false;
  try {
    const res = await auth.api.signInEmail({ body: { email, password }, headers: await headers() });
    needsSecondFactor = "twoFactorRedirect" in res && res.twoFactorRedirect === true;
  } catch (e) {
    if (e instanceof APIError) return { error: "Email ou mot de passe incorrect." };
    throw e;
  }
  redirect(needsSecondFactor ? "/connexion/2fa" : "/tableau-de-bord");
}

export async function verifyTotpAction(_prev: FormState, form: FormData): Promise<FormState> {
  const code = field(form, "code").replace(/\s/g, "");
  if (!/^\d{6}$/.test(code)) return { error: "Le code comporte 6 chiffres." };

  try {
    await auth.api.verifyTOTP({ body: { code }, headers: await headers() });
  } catch (e) {
    if (e instanceof APIError) return { error: "Code invalide ou expiré." };
    throw e;
  }
  redirect("/tableau-de-bord");
}

export async function signOutAction() {
  await auth.api.signOut({ headers: await headers() });
  redirect("/connexion");
}
