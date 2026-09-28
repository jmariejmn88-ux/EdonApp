# EdonApp SaaS — pilotage financier et recouvrement scolaire

Socle technique du SaaS décrit dans le cahier des charges v1.0 (marché initial : Côte d'Ivoire).

Stack : **Next.js + Supabase** (Postgres, Auth, RLS), déploiement Vercel.

> ℹ️ La base de données est sécurisée (RLS active, testée) mais **n'a pas encore été
> appliquée sur un vrai projet Supabase** : les tests tournent sur un Postgres 16 local
> avec un stub du schéma `auth`. L'application Next.js n'existe pas encore.

## État d'avancement

| Élément | État |
|---|---|
| `0001_foundation.sql` — organisations, profils, rôles/permissions, appartenances, journal d'audit, fonctions de sécurité | ✅ |
| `0002_domain.sql` — établissements, élèves/familles, centres de coûts/revenus, services, factures, échéances | ✅ |
| `0003_payments_treasury.sql` — caisses, comptes bancaires, paiements, rapprochement paiement → facture → échéance, remboursements, mouvements et soldes de trésorerie | ✅ |
| `0004_security.sql` — permissions, rôles par défaut, RLS sur toutes les tables, anti-escalade, droits par colonne, garde-fous, audit branché | ✅ |
| Relances WhatsApp, charges, fournisseurs, budget | ⏳ à faire |
| Application Next.js (connexion, dashboard) | ⏳ à faire |

## Rôles par défaut (cahier §4)

Créés automatiquement pour chaque nouvelle école par `create_organization()`.
Ce sont des rôles système : ni modifiables ni supprimables. Une école peut créer
ses propres rôles en plus.

| Rôle | Permissions |
|---|---|
| **Fondateur / Directeur** | tout |
| **Responsable financier** | facturation, paiements (+ confirmation), remboursements (+ validation), trésorerie, services, rapports, audit |
| **Caissier** | enregistrer des paiements et les rapprocher, demander un remboursement |
| **Responsable administratif** | structure (classes, niveaux...), élèves/familles, services, factures, rapports |

L'**administrateur SaaS** (`profiles.is_platform_admin`) n'est attribuable que par le
backend : aucun utilisateur ne peut modifier ce champ.

## Sécurité appliquée par la base

**Isolation entre écoles**
- RLS sur toutes les tables : un utilisateur ne voit et ne modifie que les données des
  organisations dont il est membre actif.
- FK composites `(id, organization_id)` : impossible de lier deux lignes d'écoles
  différentes, même en connaissant un UUID.
- Visiteur non connecté (`anon`) : aucun accès aux tables.

**Anti-escalade de privilèges**
- On ne peut attribuer (ou retirer) qu'un rôle dont on possède déjà toutes les permissions.
- On ne peut ajouter à un rôle qu'une permission que l'on possède.
- Personne ne modifie sa propre appartenance.
- Droits par colonne : `is_platform_admin`, le forfait (`plan`) et les montants payés
  des factures ne sont jamais modifiables par un utilisateur.

**Règles financières**
- Montants payés des factures/échéances recalculés à partir des paiements encaissés ;
  les statuts « payée », « partiellement payée », « en retard » ne se saisissent pas.
- Sur-affectation refusée ; le total d'une facture ne descend jamais sous ce qui est payé.
- Paiement encaissé figé (montant, moyen, compte, famille), ni supprimable ni
  repassable en « échoué » ; paiement entièrement remboursé définitif.
- Un paiement non espèces (Mobile Money, carte, virement) ne peut être déclaré
  « réussi » que par le webhook opérateur ou un utilisateur ayant `payments.confirm`.
- Remboursement à quatre yeux : demande → validation par une autre personne
  (`refunds.approve`) → exécution.
- Une facture émise ne se supprime pas (annulation seulement, et pas si déjà payée).
- Trésorerie en ajout seul (on corrige par un mouvement inverse) ; soldes calculés.
- Transaction opérateur (`external_reference`) enregistrable une seule fois.
- L'auteur d'une opération (`recorded_by`, `requested_by`...) est toujours
  l'utilisateur connecté : impossible de signer au nom d'un autre.

**Audit (cahier §29)**
- Toute création / modification / suppression sur les tables métier, financières et
  de sécurité est tracée : ancienne valeur, nouvelle valeur, auteur, date, motif.
- Journal en lecture seule (permission `audit.read`), aucune écriture ni suppression.

## Lancer les tests

Sur un Postgres 16 **jetable** (jamais sur un vrai projet Supabase) :

```bash
psql -f supabase/tests/00_supabase_stub.sql      # rôles anon/authenticated, auth.users, auth.uid()
for f in supabase/migrations/*.sql; do psql -v ON_ERROR_STOP=1 -f "$f"; done
psql -f supabase/tests/payments_treasury_test.sql   # 17 vérifications
psql -f supabase/tests/rls_security_test.sql        # 66 vérifications
```

Les scripts tournent dans une transaction annulée à la fin. `rls_security_test.sql`
se connecte successivement comme directeur, caissier, comptable, gestionnaire,
directeur d'une autre école, compte sans école et visiteur anonyme, et vérifie que
chaque tentative interdite est refusée **pour le bon motif**.

## Points de vigilance pour la suite

- **Toute nouvelle table doit activer la RLS** et définir ses politiques : Supabase
  accorde par défaut des droits aux rôles `anon`/`authenticated` sur les nouvelles tables.
- `app.set_audit_reason()` (motif d'une modification) est dans le schéma `app`, non
  exposé par l'API : prévoir une RPC publique ou l'appeler depuis le backend.
- Portail parent : pas encore d'accès (les parents ne sont pas des membres) ; il
  nécessitera des politiques dédiées limitées à leur famille.
- Remboursement partiel : la créance ne se rouvre pas seule, l'application doit
  réduire l'affectation concernée (opération tracée).
