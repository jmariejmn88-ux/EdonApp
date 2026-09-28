import { ActionForm } from "@/components/ActionForm";
import { verifyTotpAction } from "@/app/actions/auth";

export default function DeuxFacteursPage() {
  return (
    <div className="card narrow">
      <h1>Code de vérification</h1>
      <p className="muted">
        Saisissez le code à 6 chiffres affiché par votre application d’authentification.
      </p>
      <ActionForm action={verifyTotpAction} submitLabel="Vérifier" pendingLabel="Vérification…">
        <label>
          Code
          <input name="code" inputMode="numeric" autoComplete="one-time-code" pattern="\d{6}" maxLength={6} required />
        </label>
      </ActionForm>
    </div>
  );
}
