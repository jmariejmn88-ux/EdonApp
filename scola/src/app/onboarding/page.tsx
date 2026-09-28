import { ActionForm } from "@/components/ActionForm";
import { createSchoolAction } from "@/app/actions/school";
import { requireSession } from "@/lib/session";

export const dynamic = "force-dynamic";

export default async function OnboardingPage() {
  const session = await requireSession();
  return (
    <div className="card narrow">
      <h1>Bienvenue, {session.user.name}</h1>
      <p className="muted">Créez votre établissement. Vous en serez le directeur.</p>
      <ActionForm action={createSchoolAction} submitLabel="Créer l'établissement" pendingLabel="Création…">
        <label>
          Organisation ou groupe scolaire
          <input name="orgName" placeholder="Groupe scolaire Les Palmiers" maxLength={120} required />
        </label>
        <label>
          Premier établissement
          <input name="schoolName" placeholder="Collège Les Palmiers – Cocody" maxLength={120} required />
        </label>
      </ActionForm>
    </div>
  );
}
