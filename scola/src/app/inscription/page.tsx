import Link from "next/link";
import { ActionForm } from "@/components/ActionForm";
import { signUpAction } from "@/app/actions/auth";

export default function InscriptionPage() {
  return (
    <div className="card narrow">
      <h1>Créer un compte</h1>
      <ActionForm action={signUpAction} submitLabel="Créer mon compte" pendingLabel="Création…">
        <label>
          Nom complet
          <input name="name" autoComplete="name" required />
        </label>
        <label>
          Email
          <input name="email" type="email" autoComplete="email" required />
        </label>
        <label>
          Mot de passe (10 caractères minimum)
          <input name="password" type="password" autoComplete="new-password" minLength={10} required />
        </label>
      </ActionForm>
      <p className="muted">
        Déjà inscrit ? <Link href="/connexion">Se connecter</Link>
      </p>
    </div>
  );
}
