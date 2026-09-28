"use server";

import { sql } from "drizzle-orm";
import { redirect } from "next/navigation";
import { withUser } from "@/lib/db";
import { requireSession } from "@/lib/session";
import type { FormState } from "./auth";

export async function createSchoolAction(_prev: FormState, form: FormData): Promise<FormState> {
  const session = await requireSession();
  const orgName = String(form.get("orgName") ?? "").trim();
  const schoolName = String(form.get("schoolName") ?? "").trim();
  if (!orgName || !schoolName) return { error: "Les deux noms sont obligatoires." };
  if (orgName.length > 120 || schoolName.length > 120) return { error: "Nom trop long (120 caractères maximum)." };

  await withUser(session.user.id, (db) =>
    db.execute(sql`select public.create_organization(${orgName}, ${schoolName})`));
  redirect("/tableau-de-bord");
}
