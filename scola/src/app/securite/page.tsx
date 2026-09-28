import { requireSession } from "@/lib/session";
import { TwoFactorSetup } from "@/components/TwoFactorSetup";

export const dynamic = "force-dynamic";

export default async function SecuritePage({
  searchParams,
}: {
  searchParams: Promise<{ obligatoire?: string }>;
}) {
  const session = await requireSession();
  const { obligatoire } = await searchParams;

  return (
    <div className="card narrow">
      <h1>Double authentification</h1>
      {session.user.twoFactorEnabled ? (
        <p>✅ La double authentification est active sur votre compte.</p>
      ) : (
        <>
          {obligatoire && (
            <p className="notice">
              Votre rôle donne accès à des opérations sensibles (paiements, remboursements,
              gestion des membres). La double authentification est obligatoire pour continuer.
            </p>
          )}
          <TwoFactorSetup />
        </>
      )}
      <p className="muted" style={{ marginTop: 16 }}>
        <a href="/tableau-de-bord">Retour au tableau de bord</a>
      </p>
    </div>
  );
}
