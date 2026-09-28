-- =====================================================================
-- 0001_foundation.sql
-- Socle : tenancy (organisations), utilisateurs, RBAC, journal d'audit.
--
-- Modèle multi-tenant : une `organization` est la racine d'isolation
-- (le « compte entreprise » du cahier des charges, qui peut porter un ou
-- plusieurs établissements). Toute donnée métier porte un
-- `organization_id` ; l'isolation est garantie par RLS (voir 0003).
-- =====================================================================

create extension if not exists pgcrypto;

-- Les fonctions utilitaires de sécurité vivent dans un schéma dédié,
-- sur lequel les rôles applicatifs n'ont que des droits d'exécution ciblés.
create schema if not exists app;

-- ---------------------------------------------------------------------
-- Types énumérés
-- ---------------------------------------------------------------------
create type public.membership_status as enum ('active', 'invited', 'suspended');

-- ---------------------------------------------------------------------
-- Organisations (racine d'isolation / tenant)
-- ---------------------------------------------------------------------
create table public.organizations (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  slug        text unique,
  country     text not null default 'CI',
  currency    text not null default 'XOF',
  plan        text not null default 'starter',   -- starter | business | enterprise
  status      text not null default 'active',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Profils utilisateurs (1-1 avec auth.users, table gérée par Better Auth)
-- ---------------------------------------------------------------------
create table public.profiles (
  id                 uuid primary key references auth.users (id) on delete cascade,
  full_name          text,
  email              text,
  phone              text,
  is_platform_admin  boolean not null default false,  -- Administrateur SaaS
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- RBAC : catalogue de permissions, rôles, liaison rôle<->permission
-- ---------------------------------------------------------------------
create table public.permissions (
  id           serial primary key,
  code         text not null unique,          -- ex: 'payments.write'
  module       text not null,
  description  text
);

-- Un rôle appartient à une organisation (rôles personnalisables par
-- établissement, cf. cahier §6 « rôles et permissions »).
create table public.roles (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references public.organizations (id) on delete cascade,
  code             text not null,              -- ex: 'director', 'cashier'
  name             text not null,
  description      text,
  is_system        boolean not null default false,
  created_at       timestamptz not null default now(),
  unique (organization_id, code),
  unique (id, organization_id)                 -- cible des FK composites
);

create table public.role_permissions (
  role_id        uuid not null references public.roles (id) on delete cascade,
  permission_id  int  not null references public.permissions (id) on delete cascade,
  primary key (role_id, permission_id)
);

-- Appartenance d'un utilisateur à une organisation, avec un rôle.
create table public.memberships (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users (id) on delete cascade,
  organization_id  uuid not null references public.organizations (id) on delete cascade,
  role_id          uuid not null,
  status           public.membership_status not null default 'active',
  created_at       timestamptz not null default now(),
  unique (user_id, organization_id),
  -- FK composite : le rôle doit appartenir à la MÊME organisation que
  -- l'appartenance. Empêche d'attribuer un rôle d'un autre tenant.
  foreign key (role_id, organization_id)
    references public.roles (id, organization_id) on delete restrict
);

create index memberships_user_idx on public.memberships (user_id);
create index memberships_org_idx  on public.memberships (organization_id);

-- ---------------------------------------------------------------------
-- Journal d'audit (règle d'or financière, cahier §29)
-- Append-only : aucune écriture directe par les clients (voir 0003).
-- ---------------------------------------------------------------------
create table public.audit_log (
  id               bigint generated always as identity primary key,
  organization_id  uuid,
  table_name       text not null,
  record_id        uuid,
  action           text not null,              -- INSERT | UPDATE | DELETE
  old_data         jsonb,
  new_data         jsonb,
  changed_by       uuid,                        -- auth.uid() au moment de l'opération
  reason           text,                        -- motif (renseigné via app.set_audit_reason)
  changed_at       timestamptz not null default now()
);

create index audit_log_org_idx    on public.audit_log (organization_id, changed_at desc);
create index audit_log_record_idx on public.audit_log (table_name, record_id);

-- =====================================================================
-- Fonctions de sécurité
-- SECURITY DEFINER + search_path verrouillé : elles lisent `memberships`
-- sans être elles-mêmes soumises à RLS, ce qui évite toute récursion
-- dans les politiques et empêche le détournement via search_path.
-- =====================================================================

create or replace function app.is_platform_admin()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select is_platform_admin from public.profiles where id = auth.uid()),
    false
  );
$$;

create or replace function app.is_org_member(org uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.memberships
    where user_id = auth.uid()
      and organization_id = org
      and status = 'active'
  );
$$;

create or replace function app.has_permission(org uuid, perm text)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select app.is_platform_admin() or exists (
    select 1
    from public.memberships m
    join public.role_permissions rp on rp.role_id = m.role_id
    join public.permissions p       on p.id = rp.permission_id
    where m.user_id = auth.uid()
      and m.organization_id = org
      and m.status = 'active'
      and p.code = perm
  );
$$;

-- ---------------------------------------------------------------------
-- Motif d'une modification (cahier §29 : ancienne valeur, nouvelle
-- valeur, utilisateur, date, MOTIF). L'application appelle
-- `select app.set_audit_reason('...')` dans la même transaction avant
-- la modification ; le trigger d'audit le recopie.
-- ---------------------------------------------------------------------
create or replace function app.set_audit_reason(reason text)
returns void
language sql
set search_path = public, pg_temp
as $$
  select set_config('app.audit_reason', reason, true);
$$;

-- Trigger d'audit générique : enregistre toute création / modification /
-- suppression avec l'état avant et après.
create or replace function app.audit()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_org uuid;
begin
  if tg_op = 'DELETE' then
    v_old := to_jsonb(old);
  elsif tg_op = 'UPDATE' then
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
  else
    v_new := to_jsonb(new);
  end if;

  v_org := coalesce((v_new ->> 'organization_id'), (v_old ->> 'organization_id'))::uuid;

  -- Tables sans colonne organization_id : on retrouve l'organisation.
  if v_org is null and tg_table_name = 'organizations' then
    v_org := coalesce((v_new ->> 'id'), (v_old ->> 'id'))::uuid;
  elsif v_org is null and tg_table_name = 'role_permissions' then
    select organization_id into v_org
    from public.roles
    where id = coalesce((v_new ->> 'role_id'), (v_old ->> 'role_id'))::uuid;
  end if;

  insert into public.audit_log
    (organization_id, table_name, record_id, action, old_data, new_data, changed_by, reason)
  values
    (v_org,
     tg_table_name,
     coalesce((v_new ->> 'id'), (v_old ->> 'id'))::uuid,
     tg_op,
     v_old,
     v_new,
     auth.uid(),
     nullif(current_setting('app.audit_reason', true), ''));

  return coalesce(new, old);
end;
$$;

-- Mise à jour automatique de updated_at.
create or replace function app.touch_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger organizations_touch before update on public.organizations
  for each row execute function app.touch_updated_at();
create trigger profiles_touch before update on public.profiles
  for each row execute function app.touch_updated_at();

-- Création automatique du profil à l'inscription d'un utilisateur.
create or replace function app.handle_new_user()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, coalesce(new.name, ''));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function app.handle_new_user();

-- Changement d'email dans Better Auth : le profil suit.
create or replace function app.sync_user_email()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  update public.profiles set email = new.email where id = new.id;
  return new;
end;
$$;

create trigger on_auth_user_email_changed
  after update of email on auth.users
  for each row
  when (new.email is distinct from old.email)
  execute function app.sync_user_email();
