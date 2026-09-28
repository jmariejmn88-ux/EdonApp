"use client";

import { useActionState } from "react";
import {
  startTwoFactorAction,
  confirmTwoFactorAction,
  type SetupState,
} from "@/app/actions/security";

// Une seule action côté client, qui aiguille selon l'étape en cours.
async function setupAction(prev: SetupState, form: FormData): Promise<SetupState> {
  return prev.step === "password"
    ? startTwoFactorAction(prev, form)
    : confirmTwoFactorAction(prev, form);
}

export function TwoFactorSetup() {
  const [state, formAction, pending] = useActionState(setupAction, { step: "password" } as SetupState);

  if (state.step === "password") {
    return (
      <form action={formAction}>
        <label>
          Confirmez votre mot de passe
          <input name="password" type="password" autoComplete="current-password" required />
        </label>
        {state.error && <p className="error" role="alert">{state.error}</p>}
        <button type="submit" disabled={pending}>{pending ? "Préparation…" : "Activer"}</button>
      </form>
    );
  }

  return (
    <form action={formAction}>
      <p>
        1. Dans votre application d’authentification (Google Authenticator, Microsoft
        Authenticator, 2FAS…), ajoutez un compte avec cette clé :
      </p>
      <code className="secret" data-testid="totp-secret">{state.secret}</code>
      <p className="muted">
        Sur téléphone : <a href={state.totpURI}>ouvrir directement dans l’application</a>.
      </p>
      <p>2. Conservez ces codes de secours en lieu sûr (chacun utilisable une fois) :</p>
      <code className="secret">{state.backupCodes.join("  ")}</code>
      <label>
        3. Saisissez le code à 6 chiffres affiché
        <input name="code" inputMode="numeric" autoComplete="one-time-code" pattern="\d{6}" maxLength={6} required />
      </label>
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <button type="submit" disabled={pending}>{pending ? "Vérification…" : "Confirmer"}</button>
    </form>
  );
}
