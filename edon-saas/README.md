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
| Paiements, remboursements, relances WhatsApp, charges, fournisseurs, budget, trésorerie | ⏳ à faire |
| RLS + triggers d'audit + rôles par défaut | ⏳ à faire |
| Application Next.js (connexion, dashboard) | ⏳ à faire |

Les deux migrations ont été appliquées avec succès sur un Postgres 16 local.

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
