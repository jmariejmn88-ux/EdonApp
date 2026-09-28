import { redirect } from "next/navigation";
import { requireSession } from "@/lib/session";
import { getDashboard, formatFcfa } from "@/lib/dashboard";
import { signOutAction } from "@/app/actions/auth";

export const dynamic = "force-dynamic";

export default async function TableauDeBordPage() {
  const session = await requireSession();
  const orgs = await getDashboard(session.user.id);

  if (orgs.length === 0) redirect("/onboarding");

  // Cahier §30 : double authentification obligatoire pour les comptes sensibles.
  if (orgs.some((o) => o.sensitive) && !session.user.twoFactorEnabled) {
    redirect("/securite?obligatoire=1");
  }

  return (
    <>
      <div className="row">
        <h1>Tableau de bord</h1>
        <form action={signOutAction}>
          <button type="submit" className="secondary">Se déconnecter</button>
        </form>
      </div>
      <p className="muted">Connecté en tant que {session.user.name} ({session.user.email})</p>

      {orgs.map((o) => {
        const rate = o.billed > 0 ? Math.round((o.collected / o.billed) * 100) : 0;
        return (
          <section key={o.id} className="card" style={{ marginTop: 16 }}>
            <div className="row">
              <h2 style={{ margin: 0 }}>{o.name}</h2>
              <span className="muted">{o.roleName}</span>
            </div>
            <div className="stats" style={{ marginTop: 16 }}>
              <div className="stat"><div className="muted">Élèves</div><div className="value">{o.students}</div></div>
              <div className="stat"><div className="muted">Facturé</div><div className="value">{formatFcfa(o.billed)}</div></div>
              <div className="stat"><div className="muted">Encaissé</div><div className="value">{formatFcfa(o.collected)}</div></div>
              <div className="stat"><div className="muted">Reste à recouvrer</div><div className="value">{formatFcfa(o.billed - o.collected)}</div></div>
              <div className="stat"><div className="muted">Taux de recouvrement</div><div className="value">{rate} %</div></div>
            </div>
          </section>
        );
      })}

      <p className="muted" style={{ marginTop: 24 }}>
        <a href="/securite">Sécurité du compte</a>
      </p>
    </>
  );
}
