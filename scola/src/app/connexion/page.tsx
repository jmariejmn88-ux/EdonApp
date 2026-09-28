import Link from "next/link";
import { ActionForm } from "@/components/ActionForm";
import { signInAction } from "@/app/actions/auth";

export default function ConnexionPage() {
  return (
    <div className="card narrow">
      <h1>Connexion</h1>
      <ActionForm action={signInAction} submitLabel="Se connecter" pendingLabel="Connexion…">
        <label>
          Email
          <input name="email" type="email" autoComplete="email" required />
        </label>
        <label>
          Mot de passe
          <input name="password" type="password" autoComplete="current-password" required />
        </label>
      </ActionForm>
      <p className="muted">
        Pas encore de compte ? <Link href="/inscription">Créer un compte</Link>
      </p>
    </div>
  );
}
