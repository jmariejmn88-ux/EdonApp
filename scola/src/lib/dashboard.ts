// Données du tableau de bord, lues au nom de l'utilisateur (RLS active).
import { sql } from "drizzle-orm";
import { withUser } from "./db";

export type OrgSummary = {
  id: string;
  name: string;
  roleName: string;
  students: number;
  billed: number;      // total facturé (factures émises, hors brouillons et annulées)
  collected: number;   // total encaissé
  sensitive: boolean;  // rôle exigeant la double authentification (§30)
};

export async function getDashboard(userId: string): Promise<OrgSummary[]> {
  const res = await withUser(userId, (db) =>
    db.execute(sql`
      select
        o.id,
        o.name,
        r.name as role_name,
        (select count(*) from public.students s where s.organization_id = o.id)::int as students,
        (select coalesce(sum(i.total), 0) from public.invoices i
          where i.organization_id = o.id and i.status not in ('draft', 'cancelled'))::float8 as billed,
        (select coalesce(sum(i.amount_paid), 0) from public.invoices i
          where i.organization_id = o.id and i.status not in ('draft', 'cancelled'))::float8 as collected,
        (app.has_permission(o.id, 'members.manage')
          or app.has_permission(o.id, 'payments.confirm')
          or app.has_permission(o.id, 'refunds.approve')) as sensitive
      from public.memberships m
      join public.organizations o on o.id = m.organization_id
      join public.roles r on r.id = m.role_id
      where m.user_id = auth.uid() and m.status = 'active'
      order by o.name`));

  return res.rows.map((r) => ({
    id: String(r.id),
    name: String(r.name),
    roleName: String(r.role_name),
    students: Number(r.students),
    billed: Number(r.billed),
    collected: Number(r.collected),
    sensitive: Boolean(r.sensitive),
  }));
}

export function formatFcfa(amount: number) {
  return new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 0 }).format(amount) + " FCFA";
}
