// Session côté serveur (composants serveur et server actions).
import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { auth } from "./auth";

export async function getSession() {
  return auth.api.getSession({ headers: await headers() });
}

/** Renvoie la session ou redirige vers la page de connexion. */
export async function requireSession() {
  const session = await getSession();
  if (!session) redirect("/connexion");
  return session;
}
