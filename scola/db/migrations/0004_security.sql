-- =====================================================================
-- 0004_security.sql
-- Sécurité (cahier §30) : RBAC, rôles par défaut (§4), RLS sur toutes
-- les tables, protections anti-escalade, droits par colonne, garde-fous
-- financiers et branchement du journal d'audit (§29).
--
-- Rôles Postgres (voir 0000) :
--   scola_app      connexion de l'application  -> tables d'auth uniquement
--   authenticated  requête au nom d'un utilisateur -> accès filtré par RLS
--   propriétaire   migrations et tâches backend de confiance (webhook
--                  opérateur de paiement...) -> contourne la RLS
--
-- Convention : auth.uid() non nul = requête d'un utilisateur.
-- Les contrôles « métier » ci-dessous (confirmation, validation d'un
-- remboursement...) ne s'appliquent qu'à ce contexte ; le backend de
-- confiance (connexion propriétaire, sans utilisateur) n'y est pas soumis.
-- =====================================================================

-- =====================================================================
-- 1. Catalogue des permissions
-- =====================================================================
insert into public.permissions (code, module, description) values
  ('org.manage',        'organisation', 'Modifier l''organisation et ses établissements'),
  ('members.manage',    'organisation', 'Inviter, modifier et retirer des utilisateurs'),
  ('roles.manage',      'organisation', 'Créer et modifier des rôles personnalisés'),
  ('audit.read',        'organisation', 'Consulter le journal d''audit'),
  ('structure.write',   'etablissement','Gérer campus, années scolaires, niveaux et classes'),
  ('students.write',    'eleves',       'Gérer élèves, familles et tuteurs'),
  ('services.write',    'services',     'Gérer le catalogue, les abonnements et les centres de coûts/revenus'),
  ('invoices.write',    'facturation',  'Créer et modifier factures et échéanciers'),
  ('payments.write',    'paiements',    'Enregistrer des paiements et les rapprocher'),
  ('payments.confirm',  'paiements',    'Confirmer un paiement non espèces (Mobile Money, carte, virement...)'),
  ('refunds.write',     'paiements',    'Demander un remboursement'),
  ('refunds.approve',   'paiements',    'Valider et exécuter un remboursement'),
  ('treasury.read',     'tresorerie',   'Consulter la trésorerie et les comptes bancaires'),
  ('treasury.write',    'tresorerie',   'Saisir des mouvements de trésorerie'),
  ('treasury.manage',   'tresorerie',   'Gérer les caisses et comptes bancaires'),
  ('reports.read',      'reporting',    'Consulter les tableaux de bord et rapports');

-- =====================================================================
-- 2. Fonctions d'autorisation complémentaires
-- =====================================================================

-- Deux utilisateurs partagent-ils une organisation ? (visibilité des profils)
create or replace function app.shares_org(other uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.memberships me
    join public.memberships them on them.organization_id = me.organization_id
    where me.user_id = auth.uid() and me.status = 'active'
      and them.user_id = other and them.status = 'active'
  );
$$;

-- On ne peut accorder à un rôle qu'une permission que l'on détient.
create or replace function app.can_grant_permission(org uuid, perm_id int)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.permissions p
    where p.id = perm_id and app.has_permission(org, p.code)
  );
$$;

-- On ne peut attribuer (ou retirer) qu'un rôle dont TOUTES les
-- permissions sont déjà les siennes : un gestionnaire des membres ne
-- peut ni se fabriquer un directeur, ni rétrograder quelqu'un de plus
-- privilégié que lui.
create or replace function app.can_assign_role(p_role uuid, org uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select app.has_permission(org, 'members.manage')
    and exists (select 1 from public.roles where id = p_role and organization_id = org)
    and not exists (
      select 1
      from public.role_permissions rp
      join public.permissions p on p.id = rp.permission_id
      where rp.role_id = p_role
        and not app.has_permission(org, p.code)
    );
$$;

-- =====================================================================
-- 3. Rôles par défaut (cahier §4) et création d'une organisation
-- =====================================================================
create or replace function app.create_default_roles(org uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  r record;
begin
  for r in
    select * from (values
      ('director',    'Fondateur / Directeur',
        'Accès complet à l''établissement',
        array['org.manage','members.manage','roles.manage','audit.read','structure.write',
              'students.write','services.write','invoices.write','payments.write',
              'payments.confirm','refunds.write','refunds.approve','treasury.read',
              'treasury.write','treasury.manage','reports.read']),
      ('finance',     'Responsable financier / comptable',
        'Facturation, paiements, rapprochement, trésorerie, rapports',
        array['audit.read','services.write','invoices.write','payments.write','payments.confirm',
              'refunds.write','refunds.approve','treasury.read','treasury.write',
              'treasury.manage','reports.read']),
      ('cashier',     'Caissier',
        'Encaissements, reçus, recherche parent/élève, rapprochements',
        array['payments.write','refunds.write']),
      ('admin_staff', 'Responsable administratif',
        'Élèves, familles, services, échéanciers, factures',
        array['structure.write','students.write','services.write','invoices.write','reports.read'])
    ) as t(code, name, description, perms)
  loop
    with new_role as (
      insert into public.roles (organization_id, code, name, description, is_system)
      values (org, r.code, r.name, r.description, true)
      returning id
    )
    insert into public.role_permissions (role_id, permission_id)
    select new_role.id, p.id
    from new_role
    join public.permissions p on p.code = any (r.perms);
  end loop;
end;
$$;

-- Point d'entrée de l'inscription d'une école (appel RPC depuis l'app) :
-- crée l'organisation, son premier établissement, les rôles par défaut,
-- et fait de l'appelant son directeur.
create or replace function public.create_organization(p_org_name text, p_school_name text)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_org    uuid;
  v_role   uuid;
begin
  if v_uid is null then
    raise exception 'Authentification requise' using errcode = 'insufficient_privilege';
  end if;
  if coalesce(btrim(p_org_name), '') = '' or coalesce(btrim(p_school_name), '') = '' then
    raise exception 'Nom d''organisation et d''établissement obligatoires' using errcode = 'check_violation';
  end if;

  insert into public.organizations (name) values (btrim(p_org_name)) returning id into v_org;
  insert into public.schools (organization_id, name) values (v_org, btrim(p_school_name));

  perform app.create_default_roles(v_org);

  select id into v_role from public.roles where organization_id = v_org and code = 'director';
  insert into public.memberships (user_id, organization_id, role_id) values (v_uid, v_org, v_role);

  return v_org;
end;
$$;

-- =====================================================================
-- 4. Garde-fous métier
-- =====================================================================

-- Horodatage de l'auteur : un utilisateur ne peut pas signer au nom
-- d'un autre. À l'insertion la colonne vaut auth.uid() ; ensuite elle
-- ne change plus.
create or replace function app.stamp_actor()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  col text := tg_argv[0];
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null then
      new := jsonb_populate_record(new, jsonb_build_object(col, auth.uid()));
    end if;
  else
    new := jsonb_populate_record(new, jsonb_build_object(col, to_jsonb(old) -> col));
  end if;
  return new;
end;
$$;

create trigger invoices_stamp_actor before insert or update on public.invoices
  for each row execute function app.stamp_actor('created_by');
create trigger payments_stamp_actor before insert or update on public.payments
  for each row execute function app.stamp_actor('recorded_by');
create trigger payment_allocations_stamp_actor before insert or update on public.payment_allocations
  for each row execute function app.stamp_actor('created_by');
create trigger refunds_stamp_actor before insert or update on public.refunds
  for each row execute function app.stamp_actor('requested_by');
create trigger treasury_transactions_stamp_actor before insert on public.treasury_transactions
  for each row execute function app.stamp_actor('recorded_by');

-- Statuts calculés : 'paid', 'partially_paid' et 'overdue' ne sont posés
-- que par le recalcul (0003). Un utilisateur ne peut que passer en
-- brouillon / émise / annulée, et pas annuler ce qui a déjà été payé.
create or replace function app.guard_computed_status()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if current_setting('app.recomputing', true) = 'on' then
    return new;
  end if;

  if tg_op = 'UPDATE' and new.status is not distinct from old.status then
    return new;
  end if;

  if tg_table_name = 'invoices' then
    if new.status not in ('draft', 'issued', 'cancelled') then
      raise exception 'Statut de facture « % » calculé automatiquement : saisie manuelle interdite', new.status
        using errcode = 'check_violation';
    end if;
    if tg_op = 'UPDATE' and new.status = 'draft' and old.status <> 'draft' then
      raise exception 'Une facture émise ne peut pas repasser en brouillon' using errcode = 'check_violation';
    end if;
    if new.status = 'cancelled' and new.amount_paid > 0 then
      raise exception 'Facture % partiellement payée : rembourser ou désaffecter avant d''annuler', new.number
        using errcode = 'check_violation';
    end if;
  else  -- installments
    if new.status not in ('pending', 'cancelled') then
      raise exception 'Statut d''échéance « % » calculé automatiquement : saisie manuelle interdite', new.status
        using errcode = 'check_violation';
    end if;
    if new.status = 'cancelled' and new.amount_paid > 0 then
      raise exception 'Échéance déjà payée en partie : annulation interdite' using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

create trigger invoices_guard_status before insert or update of status on public.invoices
  for each row execute function app.guard_computed_status();
create trigger installments_guard_status before insert or update of status on public.installments
  for each row execute function app.guard_computed_status();

-- Le total d'une facture / d'une échéance ne descend jamais sous ce qui
-- a déjà été payé.
alter table public.invoices
  add constraint invoices_paid_le_total check (amount_paid <= total);
alter table public.installments
  add constraint installments_paid_le_amount check (amount_paid <= amount);

-- Seule une facture en brouillon peut être supprimée (sinon : annulation).
create or replace function app.guard_invoice_delete()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if old.status <> 'draft' then
    raise exception 'Facture % émise : suppression interdite, utiliser l''annulation', old.number
      using errcode = 'check_violation';
  end if;
  return old;
end;
$$;

create trigger invoices_guard_delete before delete on public.invoices
  for each row execute function app.guard_invoice_delete();

-- Transitions sensibles réservées à certaines permissions.
create or replace function app.guard_payment_confirmation()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  -- Un paiement non espèces ne peut être marqué « réussi » que par le
  -- webhook de l'opérateur (hors API) ou par un utilisateur habilité.
  -- Empêche un caissier de déclarer encaissé un Mobile Money fictif.
  if auth.uid() is not null
     and new.status = 'succeeded'
     and (tg_op = 'INSERT' or old.status is distinct from 'succeeded')
     and new.method <> 'cash'
     and not app.has_permission(new.organization_id, 'payments.confirm') then
    raise exception 'Permission payments.confirm requise pour confirmer un paiement %', new.method
      using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

create trigger payments_guard_confirmation before insert or update of status on public.payments
  for each row execute function app.guard_payment_confirmation();

-- Remboursements : demande -> validation par une AUTRE personne habilitée
-- -> exécution. Principe des quatre yeux sur les sorties d'argent.
create or replace function app.guard_refund_workflow()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    return new;   -- backend de confiance
  end if;

  if tg_op = 'INSERT' then
    if new.status <> 'requested' then
      raise exception 'Un remboursement est créé à l''état « requested »' using errcode = 'check_violation';
    end if;
    new.approved_by := null;
    new.completed_at := null;
    return new;
  end if;

  if new.status is not distinct from old.status then
    -- Pas de modification du montant ou du paiement après la demande.
    if new.amount is distinct from old.amount or new.payment_id is distinct from old.payment_id then
      raise exception 'Remboursement déjà demandé : montant et paiement non modifiables' using errcode = 'check_violation';
    end if;
    return new;
  end if;

  if not app.has_permission(new.organization_id, 'refunds.approve') then
    raise exception 'Permission refunds.approve requise' using errcode = 'insufficient_privilege';
  end if;

  if old.status = 'requested' and new.status = 'approved' then
    if old.requested_by = auth.uid() then
      raise exception 'Le demandeur ne peut pas valider son propre remboursement' using errcode = 'insufficient_privilege';
    end if;
    new.approved_by := auth.uid();
  elsif old.status = 'requested' and new.status = 'rejected' then
    new.approved_by := auth.uid();
  elsif old.status = 'approved' and new.status = 'completed' then
    new.completed_at := coalesce(new.completed_at, now());
  else
    raise exception 'Transition de remboursement interdite : % -> %', old.status, new.status
      using errcode = 'check_violation';
  end if;

  if new.amount is distinct from old.amount or new.payment_id is distinct from old.payment_id then
    raise exception 'Montant et paiement d''un remboursement non modifiables' using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger refunds_guard_workflow before insert or update on public.refunds
  for each row execute function app.guard_refund_workflow();

-- =====================================================================
-- 5. Journal d'audit : branchement des triggers
-- =====================================================================
do $$
declare
  t text;
begin
  foreach t in array array[
    'organizations', 'memberships', 'roles', 'role_permissions',
    'schools', 'families', 'guardians', 'students',
    'services', 'service_subscriptions',
    'invoices', 'invoice_items', 'installments',
    'payments', 'payment_allocations', 'refunds',
    'cash_accounts', 'bank_accounts', 'treasury_transactions'
  ] loop
    execute format(
      'create trigger %I after insert or update or delete on public.%I
         for each row execute function app.audit()',
      t || '_audit', t);
  end loop;
end;
$$;

-- =====================================================================
-- 6. RLS : tables métier (organisation + permission par module)
-- Lecture : membre actif de l'organisation (ou permission dédiée pour
-- les données de trésorerie). Écriture : permission du module.
-- =====================================================================
do $$
declare
  r record;
  read_rule text;
begin
  for r in
    select * from (values
      ('schools',               'org.manage',       null),
      ('campuses',              'structure.write',  null),
      ('academic_years',        'structure.write',  null),
      ('grades',                'structure.write',  null),
      ('classes',               'structure.write',  null),
      ('families',              'students.write',   null),
      ('guardians',             'students.write',   null),
      ('students',              'students.write',   null),
      ('revenue_centers',       'services.write',   null),
      ('cost_centers',          'services.write',   null),
      ('services',              'services.write',   null),
      ('service_subscriptions', 'services.write',   null),
      ('invoices',              'invoices.write',   null),
      ('invoice_items',         'invoices.write',   null),
      ('installments',          'invoices.write',   null),
      ('payments',              'payments.write',   null),
      ('payment_allocations',   'payments.write',   null),
      ('refunds',               'refunds.write',    null),
      ('cash_accounts',         'treasury.manage',  null),
      ('bank_accounts',         'treasury.manage',  'treasury.read'),
      ('treasury_transactions', 'treasury.write',   'treasury.read')
    ) as t(tbl, write_perm, read_perm)
  loop
    read_rule := case
      when r.read_perm is null then 'app.is_org_member(organization_id) or app.is_platform_admin()'
      else format('app.has_permission(organization_id, %L)', r.read_perm)
    end;

    execute format('alter table public.%I enable row level security', r.tbl);

    execute format('create policy %I on public.%I for select to authenticated using (%s)',
                   r.tbl || '_select', r.tbl, read_rule);
    execute format('create policy %I on public.%I for insert to authenticated with check (app.has_permission(organization_id, %L))',
                   r.tbl || '_insert', r.tbl, r.write_perm);
    execute format('create policy %I on public.%I for update to authenticated using (app.has_permission(organization_id, %L)) with check (app.has_permission(organization_id, %L))',
                   r.tbl || '_update', r.tbl, r.write_perm, r.write_perm);
    execute format('create policy %I on public.%I for delete to authenticated using (app.has_permission(organization_id, %L))',
                   r.tbl || '_delete', r.tbl, r.write_perm);
  end loop;
end;
$$;

-- =====================================================================
-- 7. RLS : tables de sécurité
-- =====================================================================

-- Organisations : lecture par les membres, modification par org.manage.
-- Création uniquement via create_organization(), suppression par le
-- backend de confiance (connexion propriétaire).
alter table public.organizations enable row level security;
create policy organizations_select on public.organizations for select to authenticated
  using (app.is_org_member(id) or app.is_platform_admin());
create policy organizations_update on public.organizations for update to authenticated
  using (app.has_permission(id, 'org.manage'))
  with check (app.has_permission(id, 'org.manage'));

-- Profils : soi-même et ses collègues ; modification de son propre profil.
alter table public.profiles enable row level security;
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or app.shares_org(id) or app.is_platform_admin());
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- Catalogue des permissions : lecture seule.
alter table public.permissions enable row level security;
create policy permissions_select on public.permissions for select to authenticated
  using (true);

-- Rôles : lecture par les membres ; rôles système non modifiables.
alter table public.roles enable row level security;
create policy roles_select on public.roles for select to authenticated
  using (app.is_org_member(organization_id) or app.is_platform_admin());
create policy roles_insert on public.roles for insert to authenticated
  with check (app.has_permission(organization_id, 'roles.manage') and not is_system);
create policy roles_update on public.roles for update to authenticated
  using (app.has_permission(organization_id, 'roles.manage') and not is_system)
  with check (app.has_permission(organization_id, 'roles.manage') and not is_system);
create policy roles_delete on public.roles for delete to authenticated
  using (app.has_permission(organization_id, 'roles.manage') and not is_system);

-- Permissions d'un rôle : on ne donne que ce que l'on possède.
alter table public.role_permissions enable row level security;
create policy role_permissions_select on public.role_permissions for select to authenticated
  using (exists (
    select 1 from public.roles r
    where r.id = role_id and (app.is_org_member(r.organization_id) or app.is_platform_admin())
  ));
create policy role_permissions_insert on public.role_permissions for insert to authenticated
  with check (exists (
    select 1 from public.roles r
    where r.id = role_id
      and not r.is_system
      and app.has_permission(r.organization_id, 'roles.manage')
      and app.can_grant_permission(r.organization_id, permission_id)
  ));
create policy role_permissions_delete on public.role_permissions for delete to authenticated
  using (exists (
    select 1 from public.roles r
    where r.id = role_id
      and not r.is_system
      and app.has_permission(r.organization_id, 'roles.manage')
  ));

-- Appartenances : on voit la sienne ; les gestionnaires voient toutes
-- celles de l'organisation. Personne ne modifie sa propre appartenance
-- (ni auto-promotion, ni verrouillage accidentel du dernier directeur).
alter table public.memberships enable row level security;
create policy memberships_select on public.memberships for select to authenticated
  using (user_id = auth.uid()
         or app.has_permission(organization_id, 'members.manage'));
create policy memberships_insert on public.memberships for insert to authenticated
  with check (user_id <> auth.uid() and app.can_assign_role(role_id, organization_id));
create policy memberships_update on public.memberships for update to authenticated
  using (user_id <> auth.uid() and app.can_assign_role(role_id, organization_id))
  with check (user_id <> auth.uid() and app.can_assign_role(role_id, organization_id));
create policy memberships_delete on public.memberships for delete to authenticated
  using (user_id <> auth.uid() and app.can_assign_role(role_id, organization_id));

-- Journal d'audit : lecture avec audit.read, aucune écriture client.
alter table public.audit_log enable row level security;
create policy audit_log_select on public.audit_log for select to authenticated
  using (app.has_permission(organization_id, 'audit.read')
         or (organization_id is null and app.is_platform_admin()));

-- =====================================================================
-- 8. Privilèges (GRANT) — deuxième barrière, indépendante de la RLS
-- =====================================================================

-- Point de départ : aucun droit pour les clients.
revoke all on all tables    in schema public from public, authenticated, scola_app;
revoke all on all sequences in schema public from public, authenticated, scola_app;

-- Tables métier : CRUD, filtré par la RLS.
grant select, insert, update, delete on
  public.schools, public.campuses, public.academic_years, public.grades, public.classes,
  public.families, public.guardians, public.students,
  public.revenue_centers, public.cost_centers, public.services, public.service_subscriptions,
  public.invoice_items,
  public.payments, public.payment_allocations, public.refunds,
  public.cash_accounts, public.bank_accounts
to authenticated;

-- Factures et échéances : les montants payés ne sont jamais écrits par
-- un client (ils sont recalculés) -> droits par colonne.
grant select, delete on public.invoices, public.installments to authenticated;
grant insert (id, organization_id, school_id, student_id, family_id, number, status,
              issue_date, due_date, currency, subtotal, tax_total, total, notes)
  on public.invoices to authenticated;
grant update (school_id, student_id, family_id, number, status,
              issue_date, due_date, currency, subtotal, tax_total, total, notes)
  on public.invoices to authenticated;
grant insert (id, organization_id, invoice_id, sequence, due_date, amount, status)
  on public.installments to authenticated;
grant update (sequence, due_date, amount, status)
  on public.installments to authenticated;

-- Trésorerie : journal en ajout seul ; on corrige par un mouvement inverse.
grant select, insert on public.treasury_transactions to authenticated;
grant select on public.treasury_account_balances to authenticated;

-- Sécurité.
grant select on public.organizations to authenticated;
grant update (name, slug, country, currency) on public.organizations to authenticated;  -- pas plan / status

grant select on public.profiles to authenticated;
grant update (full_name, phone) on public.profiles to authenticated;                    -- jamais is_platform_admin

grant select on public.permissions to authenticated;
grant select, insert, update, delete on public.roles, public.memberships to authenticated;
grant select, insert, delete on public.role_permissions to authenticated;
grant select on public.audit_log to authenticated;                                       -- lecture seule

-- Fonctions : le schéma app n'est pas exposé par l'API ; seules les
-- fonctions utilisées par les politiques RLS sont exécutables.
revoke all on all functions in schema app from public;
grant usage on schema app to authenticated;
grant execute on function
  app.is_platform_admin(),
  app.is_org_member(uuid),
  app.has_permission(uuid, text),
  app.shares_org(uuid),
  app.can_grant_permission(uuid, int),
  app.can_assign_role(uuid, uuid),
  app.set_audit_reason(text),
  app.is_collected(public.payment_status)   -- utilisée par les garde-fous des paiements
to authenticated;

revoke all on function public.create_organization(text, text) from public, scola_app;
grant execute on function public.create_organization(text, text) to authenticated;
