# EdonApp SaaS — pilotage financier et recouvrement scolaire

Socle technique du SaaS décrit dans le cahier des charges v1.0 (marché initial : Côte d'Ivoire).

Stack : **Next.js + Supabase** (Postgres, Auth, RLS), déploiement Vercel.

> ⚠️ **Travail en cours — ne pas déployer en l'état.**
> La RLS (isolation entre établissements) n'est **pas encore activée** : sans elle,
> tout utilisateur connecté pourrait lire les données de toutes les organisations.

## État d'avancement

| Élément | État |
|---|---|
| `0001_foundation.sql` — organisations, profils, rôles/permissions, appartenances, journal d'audit, fonctions de sécurité | ✅ |
| `0002_domain.sql` — établissements, élèves/familles, centres de coûts/revenus, services, factures, échéances | ✅ |
| `0003_payments_treasury.sql` — caisses, comptes bancaires, paiements, rapprochement paiement → facture → échéance, remboursements, mouvements et soldes de trésorerie | ✅ |
| Relances WhatsApp, charges, fournisseurs, budget | ⏳ à faire |
| RLS + triggers d'audit + rôles par défaut | ⏳ à faire |
| Application Next.js (connexion, dashboard) | ⏳ à faire |

Les trois migrations s'appliquent sans erreur sur un Postgres 16 local.

## Paiements et trésorerie : règles appliquées par la base

- Le montant payé d'une facture ou d'une échéance n'est **jamais saisi** : il est
  recalculé à partir des affectations de paiements encaissés.
- Impossible d'affecter plus que le montant d'un paiement, ou plus que le montant
  d'une échéance / d'une facture.
- Un paiement encaissé est **figé** (montant, moyen, compte, famille) et ne peut être
  ni supprimé ni repassé en « échoué » : on corrige par un remboursement.
- Un paiement entièrement remboursé est définitif.
- Une même transaction opérateur (`external_reference`) ne peut être enregistrée
  qu'une fois (protège contre un webhook rejoué).
- Un encaissement ou un remboursement crée automatiquement le mouvement de caisse /
  banque ; les soldes sont calculés (vue `treasury_account_balances`), jamais stockés.
- Pas de numéro de compte bancaire complet en base (champ masqué uniquement).

## Lancer les tests

Sur une base Postgres jetable, avec un stub du schéma `auth` de Supabase
(table `auth.users` et fonction `auth.uid()`), appliquer les migrations dans
l'ordre puis :

```bash
psql -f supabase/tests/payments_treasury_test.sql
```

Le script tourne dans une transaction annulée à la fin et affiche `PASS` pour
chaque vérification (scénario du cahier §12, tentatives de fraude, remboursement).

## Principes de sécurité déjà en place

- **Isolation par organisation** : chaque table métier porte `organization_id`.
- **FK composites `(id, organization_id)`** : la base refuse de lier des lignes de
  deux organisations différentes, même si l'UUID est connu (testé sur les rôles).
- **Audit** : trigger générique qui enregistre l'ancienne et la nouvelle valeur,
  l'utilisateur, la date et le motif (cahier §29).
- **Fonctions de sécurité** en `SECURITY DEFINER` avec `search_path` verrouillé.

## Points de vigilance pour la suite

- Empêcher un utilisateur de modifier son propre champ `profiles.is_platform_admin`
  (sinon escalade de privilèges) : n'autoriser la mise à jour que des colonnes
  `full_name` et `phone`.
- `audit_log` doit rester en lecture seule pour les clients.
