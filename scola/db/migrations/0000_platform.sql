-- =====================================================================
-- 0000_platform.sql
-- Plateforme : rôles Postgres, tables d'authentification (Better Auth)
-- et identification de l'utilisateur courant.
--
-- Rôles :
--   scola_app      rôle de connexion de l'application Next.js. Seul, il
--                  n'accède qu'aux tables d'authentification (utilisées
--                  par Better Auth). NOINHERIT : il n'hérite PAS des
--                  droits de `authenticated`.
--   authenticated  rôle des requêtes faites au nom d'un utilisateur.
--                  L'application l'endosse dans chaque transaction :
--                    set local role authenticated;
--                    select set_config('app.user_id', '<uuid>', true);
--                  Les règles RLS (0004) s'appliquent alors.
--
-- Conséquence : une requête métier qui oublie d'endosser `authenticated`
-- échoue (permission refusée) au lieu de tout voir.
--
-- Le mot de passe de scola_app n'est pas dans ce fichier : après la
-- première migration, l'exécuter une fois (voir README) :
--   alter role scola_app with login password '...';
-- =====================================================================

-- ---------------------------------------------------------------------
-- Rôles (idempotent : les rôles sont communs à tout le serveur Postgres)
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'scola_app') then
    create role scola_app nologin noinherit;
  end if;
end;
$$;

grant authenticated to scola_app;

grant usage on schema public to authenticated, scola_app;

-- ---------------------------------------------------------------------
-- Tables d'authentification (format attendu par Better Auth 1.7)
-- Correspondance modèle Better Auth -> table :
--   user -> auth.users, session -> auth.sessions, account -> auth.accounts,
--   verification -> auth.verifications, twoFactor -> auth.two_factors
-- Identifiants UUID générés par Postgres (option generateId: "uuid").
-- ---------------------------------------------------------------------
create schema if not exists auth;

create table auth.users (
  id                  uuid primary key default gen_random_uuid(),
  name                text not null,
  email               text not null unique,
  email_verified      boolean not null default false,
  image               text,
  two_factor_enabled  boolean default false,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create table auth.sessions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  token       text not null unique,
  expires_at  timestamptz not null,
  ip_address  text,
  user_agent  text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index sessions_user_idx on auth.sessions (user_id);

create table auth.accounts (
  id                        uuid primary key default gen_random_uuid(),
  user_id                   uuid not null references auth.users (id) on delete cascade,
  account_id                text not null,
  provider_id               text not null,
  access_token              text,
  refresh_token             text,
  id_token                  text,
  access_token_expires_at   timestamptz,
  refresh_token_expires_at  timestamptz,
  scope                     text,
  password                  text,              -- empreinte du mot de passe (jamais en clair)
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);
create index accounts_user_idx on auth.accounts (user_id);

create table auth.verifications (
  id          uuid primary key default gen_random_uuid(),
  identifier  text not null,
  value       text not null,
  expires_at  timestamptz not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index verifications_identifier_idx on auth.verifications (identifier);

-- Double authentification (TOTP), cahier §30 « MFA pour comptes sensibles ».
create table auth.two_factors (
  id                         uuid primary key default gen_random_uuid(),
  user_id                    uuid not null references auth.users (id) on delete cascade,
  secret                     text not null,
  backup_codes               text not null,
  verified                   boolean,
  failed_verification_count  integer,
  locked_until               timestamptz
);
create index two_factors_user_idx on auth.two_factors (user_id);

-- ---------------------------------------------------------------------
-- Droits sur le schéma auth
--   * scola_app (Better Auth) : lecture/écriture des tables d'auth ;
--   * authenticated : AUCUN accès aux tables (mots de passe, jetons de
--     session...), seulement l'usage du schéma pour appeler auth.uid().
-- ---------------------------------------------------------------------
revoke all on all tables in schema auth from public;
grant usage on schema auth to scola_app, authenticated;
grant select, insert, update, delete on all tables in schema auth to scola_app;

-- ---------------------------------------------------------------------
-- Utilisateur courant
-- Lu dans le paramètre de transaction `app.user_id`, posé par
-- l'application après avoir vérifié la session Better Auth.
-- ---------------------------------------------------------------------
create or replace function auth.uid()
returns uuid
language sql stable
as $$
  select nullif(current_setting('app.user_id', true), '')::uuid;
$$;

revoke all on function auth.uid() from public;
grant execute on function auth.uid() to authenticated, scola_app;
