-- =====================================================================
-- Stub minimal de Supabase pour tester les migrations sur un Postgres
-- vierge (NE PAS appliquer sur un vrai projet Supabase, qui fournit déjà
-- tout ceci). Reproduit : les rôles d'API, la table auth.users et
-- auth.uid() qui lit l'identifiant de l'utilisateur dans le JWT.
-- =====================================================================
create role anon          nologin;
create role authenticated nologin;
create role service_role  nologin bypassrls;

create schema auth;
create table auth.users (
  id                  uuid primary key,
  email               text,
  raw_user_meta_data  jsonb
);

create function auth.uid()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;
