"use client";

import { startTransition, useActionState } from "react";
import type { FormState } from "@/app/actions/auth";

type Props = {
  action: (prev: FormState, form: FormData) => Promise<FormState>;
  submitLabel: string;
  pendingLabel?: string;
  children: React.ReactNode;
};

export function ActionForm({ action, submitLabel, pendingLabel, children }: Props) {
  const [state, formAction, pending] = useActionState(action, null);

  // Envoi manuel plutôt que <form action> : React 19 vide le formulaire après
  // une action de formulaire, ce qui ferait perdre l'email saisi en cas d'erreur.
  function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const data = new FormData(e.currentTarget);
    startTransition(() => formAction(data));
  }

  return (
    <form onSubmit={onSubmit}>
      {children}
      {state?.error && <p className="error" role="alert">{state.error}</p>}
      <button type="submit" disabled={pending}>
        {pending ? (pendingLabel ?? "Veuillez patienter…") : submitLabel}
      </button>
    </form>
  );
}
