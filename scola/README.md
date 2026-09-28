# Scola — pilotage financier et recouvrement scolaire

Socle technique du SaaS décrit dans le cahier des charges v1.0 (marché initial : Côte d'Ivoire).

Stack cible : **Next.js + PostgreSQL (Neon) + Drizzle + Better Auth**, déploiement Vercel.

> 🔐 **Connexion : Better Auth auto-hébergé** (email + mot de passe, double
> authentification TOTP). Tables dans le schéma `auth` aux noms par défaut de Better Auth
> (`0000` + `0005`). Configuration : `src/lib/auth.ts` ; accès aux données : `withUser()`
> dans `src/lib/db.ts`. Test de bout en bout : `npm run test:auth` (13/13).

> ✅ **Base Neon en place (branche `dev`).** Les 6 migrations sont appliquées sur le projet
> Neon « Scola » (branche `dev`, Postgres 18) et le contrôle de sécurité y passe (13/13).
> La branche `production` n'a pas encore été touchée. L'application Next.js n'existe pas encore.

## État d'avancement

| Élément | État |
|---|---|
| `0001_foundation.sql` — organisations, profils, rôles/permissions, appartenances, journal d'audit, fonctions de sécurité | ✅ |
| `0002_domain.sql` — établissements, élèves/familles, centres de coûts/revenus, services, factures, échéances | ✅ |
| `0003_payments_treasury.sql` — caisses, comptes bancaires, paiements, rapprochement paiement → facture → échéance, remboursements, mouvements et soldes de trésorerie | ✅ |
| `0004_security.sql` — permissions, rôles par défaut, RLS sur toutes les tables, anti-escalade, droits par colonne, garde-fous, audit branché | ✅ |
| Relances WhatsApp, charges, fournisseurs, budget | ⏳ à faire |
| Application Next.js (connexion, dashboard) | ⏳ à faire |

## Rôles Postgres et connexion de l'application

| Rôle | Utilisé par | Accès |
|---|---|---|
| propriétaire (fourni par Neon) | migrations, tâches backend de confiance (webhooks) | tout, contourne la RLS |
| `scola_app` | l'application Next.js | **uniquement** les tables de connexion (`auth.*`) pour Better Auth |
| `authenticated` | chaque requête faite au nom d'un utilisateur | données métier filtrées par la RLS ; aucun accès à `auth.*` |

Pour une requête métier, l'application ouvre une transaction, endosse le rôle
`authenticated` et indique l'utilisateur vérifié par Better Auth
(`set_config('app.user_id', ...)`). Si elle oublie cette étape, la requête est
refusée : c'est sûr par défaut.

Après la première migration, donner un mot de passe à `scola_app` (une seule fois) :

```sql
alter role scola_app with login password '...';
```

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
- Connexion de l'application sans utilisateur identifié : aucun accès aux données métier.
- Mots de passe, jetons de session et secrets 2FA (`auth.*`) invisibles des requêtes utilisateur.

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

Sur une base Postgres 16 **jetable** (jamais sur la base de production) :

```bash
DATABASE_URL_OWNER=postgres://... npm run db:migrate   # applique db/migrations dans l'ordre
psql -f db/tests/payments_treasury_test.sql   # 17 vérifications
psql -f db/tests/rls_security_test.sql        # 76 vérifications
```

Les scripts tournent dans une transaction annulée à la fin. `rls_security_test.sql`
se connecte successivement comme directeur, caissier, comptable, gestionnaire,
directeur d'une autre école, compte sans école et connexion applicative sans
utilisateur, et vérifie que
chaque tentative interdite est refusée **pour le bon motif**.

## Test de bout en bout de la connexion

`scripts/test-auth.ts` utilise le vrai Better Auth et `withUser()` sur une base jetable
(migrations appliquées, rôle `scola_app` avec un mot de passe) :

```bash
DATABASE_URL=postgres://scola_app:...@localhost/... \
BETTER_AUTH_SECRET=$(openssl rand -base64 32) BETTER_AUTH_URL=http://localhost:3000 \
npm run test:auth
```

Il vérifie : inscription (UUID, profil créé, mot de passe haché), refus d'un mauvais mot de
passe, session retrouvée depuis le cookie, création d'école au nom de l'utilisateur,
isolation entre écoles, connexion applicative sans utilisateur refusée, identifiant non
UUID refusé, mots de passe invisibles des requêtes utilisateur, activation de la double
authentification puis second facteur exigé à la connexion suivante.

## Contrôle rapide sur Neon (sans psql)

`db/tests/smoke_check.sql` est **une seule instruction SQL** : on peut la coller dans
l'éditeur SQL de Neon (ou la lancer via le connecteur Neon) avec la connexion
propriétaire. Elle crée des données de test, tente 13 attaques (école contre école,
caissier, mots de passe, droits administrateur, statuts calculés, audit, connexion
applicative seule), puis **annule tout**. Le résultat s'affiche dans le message final :
`CONTRÔLE TERMINÉ : 13/13 OK (données de test annulées)`. Ce message apparaît comme une
« erreur » : c'est voulu, c'est ce qui annule les données de test.

Depuis l'environnement de développement cloud, le port Postgres (5432) est bloqué :
les migrations ont été appliquées via le connecteur Neon, chaque fichier étant exécuté
comme un bloc unique (`do ... execute ...`), sans modification du SQL.

## Points de vigilance pour la suite

- **Toute nouvelle table doit activer la RLS**, définir ses politiques et accorder
  explicitement ses droits à `authenticated` (sans droits, elle reste inaccessible).
- `app.set_audit_reason()` (motif d'une modification) est dans le schéma `app`, non
  exposé par l'API : prévoir une RPC publique ou l'appeler depuis le backend.
- Portail parent : pas encore d'accès (les parents ne sont pas des membres) ; il
  nécessitera des politiques dédiées limitées à leur famille.
- Remboursement partiel : la créance ne se rouvre pas seule, l'application doit
  réduire l'affectation concernée (opération tracée).
- **Neon Auth** a été activé par Vercel sur le projet (schéma `neon_auth`). Scola utilise
  son propre Better Auth (schéma `auth`), notamment parce que Neon Auth ne propose pas
  encore la double authentification exigée au §30 : Neon Auth est inutilisé et pourra
  être désactivé.
- **Région** : le projet Neon est en `aws-us-east-2` (Ohio). La région ne se change pas
  après création : à décider avant la production (proximité, loi ivoirienne / ARTCI).
