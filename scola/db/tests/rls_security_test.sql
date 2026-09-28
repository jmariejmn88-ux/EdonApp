-- =====================================================================
-- Tests d'intrusion de 0004_security.sql (RLS, RBAC, garde-fous).
-- On se connecte successivement comme différents utilisateurs (rôle
-- Postgres `authenticated` + identifiant dans le paramètre app.user_id,
-- comme le fait l'application) et on tente ce qui doit être interdit.
-- Tout est exécuté dans une transaction annulée à la fin.
-- =====================================================================
\set ON_ERROR_STOP 1
\pset tuples_only on
\pset format unaligned
begin;

-- ---------------------------------------------------------------------
-- Outils de test
-- ---------------------------------------------------------------------
create schema tests;

create function tests.expect(label text, ok boolean)
returns void language plpgsql as $$
begin
  if not coalesce(ok, false) then raise exception 'FAIL : %', label; end if;
  raise notice 'PASS : %', label;
end $$;

-- Vérifie qu'une instruction est refusée, et si `reason` est fourni, que
-- c'est bien pour ce motif (évite qu'un test passe pour une autre raison).
create function tests.expect_error(label text, stmt text, reason text default null)
returns void language plpgsql as $$
begin
  execute stmt;
  raise exception 'FAIL (aurait dû être refusé) : %', label;
exception
  when raise_exception then raise;
  when others then
    if reason is not null and position(reason in sqlerrm) = 0 then
      raise exception 'FAIL (refusé pour une autre raison) : % -> %', label, sqlerrm;
    end if;
    raise notice 'PASS refusé : % (%)', label, sqlerrm;
end $$;

-- Nombre de lignes réellement touchées par une modification.
create function tests.affected(stmt text)
returns bigint language plpgsql as $$
declare n bigint;
begin
  execute stmt;
  get diagnostics n = row_count;
  return n;
end $$;

grant usage on schema tests to authenticated, scola_app;
grant execute on all functions in schema tests to authenticated, scola_app;

-- ---------------------------------------------------------------------
-- Utilisateurs
-- ---------------------------------------------------------------------
\set uA '''aaaaaaaa-0000-0000-0000-000000000001'''
\set uC '''aaaaaaaa-0000-0000-0000-000000000002'''
\set uF '''aaaaaaaa-0000-0000-0000-000000000003'''
\set uM '''aaaaaaaa-0000-0000-0000-000000000004'''
\set uY '''aaaaaaaa-0000-0000-0000-000000000005'''
\set uB '''bbbbbbbb-0000-0000-0000-000000000001'''
\set uX '''cccccccc-0000-0000-0000-000000000001'''

insert into auth.users (id, email, name) values
  (:uA, 'directeur.a@test', 'Directeur A'), (:uC, 'caissier.a@test', 'Caissier A'),
  (:uF, 'compta.a@test', 'Comptable A'),    (:uM, 'gestion.a@test', 'Gestionnaire A'),
  (:uY, 'nouveau.a@test', 'Nouveau A'),     (:uB, 'directeur.b@test', 'Directeur B'),
  (:uX, 'sans.ecole@test', 'Sans école');

-- Des données de connexion sensibles, comme les créerait Better Auth.
insert into auth.accounts (user_id, account_id, provider_id, password)
  values (:uA, :uA, 'credential', 'empreinte-du-mot-de-passe');
insert into auth.sessions (user_id, token, expires_at)
  values (:uA, 'jeton-de-session-secret', now() + interval '1 day');

select tests.expect('profil créé automatiquement à l''inscription (nom repris)',
  (select full_name = 'Directeur A' and email = 'directeur.a@test' from profiles where id = :uA));

-- ---------------------------------------------------------------------
-- Inscription de deux écoles via la RPC publique
-- ---------------------------------------------------------------------
set role authenticated;
select set_config('app.user_id', :uA, false) as _sub \gset
select public.create_organization('Groupe A', 'École A') as org_a \gset
select set_config('app.user_id', :uB, false) as _sub \gset
select public.create_organization('Groupe B', 'École B') as org_b \gset
reset role;

select id as school_a   from schools where organization_id = :'org_a' \gset
select id as director_a from roles where organization_id = :'org_a' and code = 'director' \gset
select id as cashier_a  from roles where organization_id = :'org_a' and code = 'cashier' \gset
select id as finance_a  from roles where organization_id = :'org_a' and code = 'finance' \gset

select tests.expect('4 rôles système créés pour l''école A',
  (select count(*) = 4 from roles where organization_id = :'org_a' and is_system));
select tests.expect('le créateur est directeur de l''école A',
  (select role_id = :'director_a' from memberships where user_id = :uA));

-- ---------------------------------------------------------------------
-- Le directeur A prépare son école
-- ---------------------------------------------------------------------
set role authenticated;
select set_config('app.user_id', :uA, false) as _sub \gset

insert into families (organization_id, name) values (:'org_a', 'Famille KOUASSI') returning id as family_a \gset
insert into students (organization_id, school_id, family_id, matricule, first_name, last_name)
  values (:'org_a', :'school_a', :'family_a', 'M001', 'Jean', 'KOUASSI') returning id as student_a \gset
insert into cash_accounts (organization_id, school_id, name)
  values (:'org_a', :'school_a', 'Caisse principale') returning id as cash_a \gset
insert into bank_accounts (organization_id, school_id, name, account_number_masked)
  values (:'org_a', :'school_a', 'Banque', 'CI93 **** 1234');
insert into invoices (organization_id, school_id, student_id, family_id, number, status, total, due_date)
  values (:'org_a', :'school_a', :'student_a', :'family_a', 'SCOL-2026-0045', 'issued', 300000, '2026-12-31')
  returning id as invoice_a \gset

-- Équipe : caissier, comptable, et un gestionnaire des membres avec un
-- rôle personnalisé (members.manage + students.write).
insert into memberships (user_id, organization_id, role_id) values
  (:uC, :'org_a', :'cashier_a'),
  (:uF, :'org_a', :'finance_a');
insert into roles (organization_id, code, name) values (:'org_a', 'manager', 'Gestionnaire')
  returning id as manager_a \gset
insert into role_permissions (role_id, permission_id)
  select :'manager_a', id from permissions where code in ('members.manage', 'students.write');
insert into memberships (user_id, organization_id, role_id) values (:uM, :'org_a', :'manager_a');

select tests.expect('directeur : voit sa facture', (select count(*) = 1 from invoices));

-- =====================================================================
-- A. Isolation entre écoles : le directeur de l'école B attaque l'école A
-- =====================================================================
select set_config('app.user_id', :uB, false) as _sub \gset

select tests.expect('B ne voit aucun élève de A',      (select count(*) = 0 from students  where organization_id = :'org_a'));
select tests.expect('B ne voit aucune famille de A',   (select count(*) = 0 from families  where organization_id = :'org_a'));
select tests.expect('B ne voit aucune facture de A',   (select count(*) = 0 from invoices  where organization_id = :'org_a'));
select tests.expect('B ne voit pas l''organisation A', (select count(*) = 0 from organizations where id = :'org_a'));
select tests.expect('B ne voit aucun membre de A',     (select count(*) = 0 from memberships where organization_id = :'org_a'));
select tests.expect('B ne voit pas le profil du directeur A', (select count(*) = 0 from profiles where id = :uA));
select tests.expect('B ne voit pas le journal d''audit de A', (select count(*) = 0 from audit_log where organization_id = :'org_a'));

select tests.expect_error('B insère un élève dans A',
  format($$insert into students (organization_id, school_id, family_id, matricule, first_name, last_name)
           values (%L, %L, %L, 'HACK', 'X', 'Y')$$, :'org_a', :'school_a', :'family_a'), 'row-level security');
select tests.expect_error('B enregistre un faux paiement dans A',
  format($$insert into payments (organization_id, school_id, family_id, reference, method, amount, status)
           values (%L, %L, %L, 'PAY-HACK', 'cash', 1, 'succeeded')$$, :'org_a', :'school_a', :'family_a'), 'row-level security');
select tests.expect_error('B s''ajoute comme directeur de A',
  format($$insert into memberships (user_id, organization_id, role_id) values (%L, %L, %L)$$,
         :uB, :'org_a', :'director_a'), 'row-level security');
select tests.expect('B modifie une facture de A : 0 ligne touchée',
  tests.affected(format($$update invoices set total = 1 where id = %L$$, :'invoice_a')) = 0);
select tests.expect('B supprime un élève de A : 0 ligne touchée',
  tests.affected(format($$delete from students where id = %L$$, :'student_a')) = 0);

-- =====================================================================
-- B. Utilisateur connecté sans école, puis connexion applicative
-- =====================================================================
select set_config('app.user_id', :uX, false) as _sub \gset
select tests.expect('compte sans école : ne voit aucun élève',      (select count(*) = 0 from students));
select tests.expect('compte sans école : ne voit aucune organisation', (select count(*) = 0 from organizations));

-- Données de connexion : jamais lisibles par une requête utilisateur.
select tests.expect_error('requête utilisateur lit les mots de passe', $$select * from auth.accounts$$, 'permission denied');
select tests.expect_error('requête utilisateur lit les jetons de session', $$select * from auth.sessions$$, 'permission denied');
select tests.expect_error('requête utilisateur lit la table des comptes', $$select * from auth.users$$, 'permission denied');
select tests.expect_error('requête utilisateur lit les secrets 2FA', $$select * from auth.two_factors$$, 'permission denied');

-- La connexion de l'application SANS endosser un utilisateur : aucun
-- accès aux données métier (sûr par défaut si le code oublie l'étape).
reset role;
select set_config('app.user_id', '', false) as _sub \gset
set role scola_app;
select tests.expect_error('connexion applicative lit les élèves',    $$select * from students$$, 'permission denied');
select tests.expect_error('connexion applicative lit les paiements', $$select * from payments$$, 'permission denied');
select tests.expect_error('connexion applicative crée une école',    $$select public.create_organization('X', 'Y')$$, 'permission denied');
select tests.expect_error('connexion applicative écrit dans l''audit',
  $$insert into audit_log (table_name, action) values ('x', 'INSERT')$$, 'permission denied');
select tests.expect('connexion applicative : accède aux tables d''auth (Better Auth)',
  (select count(*) = 7 from auth.users));

-- Rôle utilisateur endossé mais aucun utilisateur identifié.
set role authenticated;
select tests.expect('rôle utilisateur sans identifiant : ne voit aucun élève', (select count(*) = 0 from students));
select tests.expect('rôle utilisateur sans identifiant : ne voit aucune organisation', (select count(*) = 0 from organizations));
select tests.expect_error('rôle utilisateur sans identifiant crée une école',
  $$select public.create_organization('X', 'Y')$$, 'Authentification requise');

-- =====================================================================
-- C. Caissier
-- =====================================================================
select set_config('app.user_id', :uC, false) as _sub \gset

select tests.expect('caissier : voit l''élève', (select count(*) = 1 from students));

-- Paiement espèces encaissé au guichet, en essayant de signer au nom du directeur.
insert into payments (organization_id, school_id, family_id, student_id, reference, method, amount, status, cash_account_id, recorded_by)
  values (:'org_a', :'school_a', :'family_a', :'student_a', 'PAY-2026-000245', 'cash', 100000, 'succeeded', :'cash_a', :uA)
  returning id as payment_cash \gset
insert into payment_allocations (organization_id, payment_id, invoice_id, amount)
  values (:'org_a', :'payment_cash', :'invoice_a', 100000);

select tests.expect('caissier : encaissement espèces rapproché, solde 200 000',
  (select balance = 200000 from invoices where id = :'invoice_a'));
select tests.expect('signature forcée : recorded_by = le caissier, pas le directeur',
  (select recorded_by = :uC from payments where id = :'payment_cash'));

select tests.expect_error('caissier déclare un Mobile Money « réussi »',
  format($$insert into payments (organization_id, school_id, family_id, reference, method, amount, status)
           values (%L, %L, %L, 'PAY-OM-1', 'mobile_money', 50000, 'succeeded')$$, :'org_a', :'school_a', :'family_a'), 'payments.confirm');
insert into payments (organization_id, school_id, family_id, reference, method, amount, status)
  values (:'org_a', :'school_a', :'family_a', 'PAY-OM-2', 'mobile_money', 50000, 'pending')
  returning id as payment_om \gset
select tests.expect_error('caissier passe un Mobile Money en attente à « réussi »',
  format($$update payments set status = 'succeeded' where id = %L$$, :'payment_om'), 'payments.confirm');

select tests.expect('caissier : ne voit pas les mouvements de trésorerie', (select count(*) = 0 from treasury_transactions));
select tests.expect('caissier : ne voit pas les comptes bancaires',       (select count(*) = 0 from bank_accounts));
select tests.expect('caissier : ne voit pas le journal d''audit',         (select count(*) = 0 from audit_log));
select tests.expect('caissier : ne voit pas les autres membres',          (select count(*) = 1 from memberships));

select tests.expect_error('caissier écrit directement le montant payé d''une facture',
  format($$update invoices set amount_paid = 300000 where id = %L$$, :'invoice_a'), 'permission denied for table invoices');
select tests.expect_error('caissier saisit un mouvement de trésorerie',
  format($$insert into treasury_transactions (organization_id, direction, amount, cash_account_id, category)
           values (%L, 'out', 1000, %L, 'autre')$$, :'org_a', :'cash_a'), 'row-level security');
select tests.expect_error('caissier crée un remboursement déjà « exécuté »',
  format($$insert into refunds (organization_id, payment_id, amount, reason, status)
           values (%L, %L, 100000, 'x', 'completed')$$, :'org_a', :'payment_cash'), 'requested');

-- Demande de remboursement légitime (en essayant de la signer au nom d'un autre).
insert into refunds (organization_id, payment_id, amount, reason, requested_by)
  values (:'org_a', :'payment_cash', 100000, 'Départ de l''élève', :uF)
  returning id as refund_1 \gset
select tests.expect('demande de remboursement signée par le caissier',
  (select requested_by = :uC from refunds where id = :'refund_1'));
select tests.expect_error('caissier valide sa propre demande',
  format($$update refunds set status = 'approved' where id = %L$$, :'refund_1'), 'refunds.approve');

-- =====================================================================
-- D. Directeur : garde-fous financiers et données sensibles
-- =====================================================================
select set_config('app.user_id', :uA, false) as _sub \gset

select tests.expect_error('directeur force le statut « payée »',
  format($$update invoices set status = 'paid' where id = %L$$, :'invoice_a'), 'calculé automatiquement');
select tests.expect_error('directeur écrit le montant payé',
  format($$update invoices set amount_paid = 300000 where id = %L$$, :'invoice_a'), 'permission denied for table invoices');
select tests.expect_error('directeur crée une facture déjà payée',
  format($$insert into invoices (organization_id, school_id, student_id, family_id, number, status, total)
           values (%L, %L, %L, %L, 'SCOL-FAKE', 'paid', 1000)$$, :'org_a', :'school_a', :'student_a', :'family_a'), 'calculé automatiquement');
select tests.expect_error('directeur baisse le total sous le montant payé',
  format($$update invoices set total = 50000 where id = %L$$, :'invoice_a'), 'invoices_paid_le_total');
select tests.expect_error('directeur annule une facture partiellement payée',
  format($$update invoices set status = 'cancelled' where id = %L$$, :'invoice_a'), 'partiellement payée');
select tests.expect_error('directeur supprime une facture émise',
  format($$delete from invoices where id = %L$$, :'invoice_a'), 'suppression interdite');
select tests.expect_error('directeur modifie un mouvement de trésorerie',
  $$update treasury_transactions set amount = 1$$, 'permission denied');
select tests.expect_error('directeur supprime une ligne du journal d''audit',
  $$delete from audit_log$$, 'permission denied');
select tests.expect_error('directeur écrit dans le journal d''audit',
  format($$insert into audit_log (organization_id, table_name, action) values (%L, 'x', 'INSERT')$$, :'org_a'), 'permission denied');
select tests.expect_error('directeur s''octroie le statut administrateur SaaS',
  format($$update profiles set is_platform_admin = true where id = %L$$, :uA), 'permission denied for table profiles');
select tests.expect_error('directeur change le forfait de son abonnement',
  format($$update organizations set plan = 'enterprise' where id = %L$$, :'org_a'), 'permission denied for table organizations');
select tests.expect('directeur : suppression d''un rôle système sans effet',
  tests.affected(format($$delete from roles where id = %L$$, :'cashier_a')) = 0);
select tests.expect('directeur : modification de sa propre appartenance sans effet',
  tests.affected(format($$update memberships set status = 'suspended' where user_id = %L$$, :uA)) = 0);

select tests.expect('directeur : modifie son nom (autorisé)',
  tests.affected(format($$update profiles set full_name = 'Directeur A' where id = %L$$, :uA)) = 1);
select tests.expect('directeur : solde de caisse = 100 000',
  (select balance = 100000 from treasury_account_balances where account_id = :'cash_a'));
select tests.expect('journal d''audit : paiement tracé avec son auteur réel (caissier)',
  (select count(*) = 1 from audit_log
   where table_name = 'payments' and action = 'INSERT' and record_id = :'payment_cash'::uuid and changed_by = :uC));
select tests.expect('journal d''audit : tentative de remboursement tracée',
  (select count(*) >= 1 from audit_log where table_name = 'refunds' and record_id = :'refund_1'::uuid));

-- =====================================================================
-- E. Gestionnaire des membres : pas d'escalade de privilèges
-- =====================================================================
select set_config('app.user_id', :uM, false) as _sub \gset

select tests.expect_error('gestionnaire nomme un nouveau directeur',
  format($$insert into memberships (user_id, organization_id, role_id) values (%L, %L, %L)$$,
         :uY, :'org_a', :'director_a'), 'row-level security');
select tests.expect_error('gestionnaire donne le rôle comptable (droits qu''il n''a pas)',
  format($$insert into memberships (user_id, organization_id, role_id) values (%L, %L, %L)$$,
         :uY, :'org_a', :'finance_a'), 'row-level security');
select tests.expect('gestionnaire promeut le caissier directeur : 0 ligne touchée',
  tests.affected(format($$update memberships set role_id = %L where user_id = %L$$, :'director_a', :uC)) = 0);
select tests.expect('gestionnaire retire le directeur : 0 ligne touchée',
  tests.affected(format($$delete from memberships where user_id = %L$$, :uA)) = 0);
select tests.expect_error('gestionnaire crée un rôle',
  format($$insert into roles (organization_id, code, name) values (%L, 'boss', 'Boss')$$, :'org_a'), 'row-level security');
select tests.expect_error('gestionnaire ajoute payments.confirm à son propre rôle',
  format($$insert into role_permissions (role_id, permission_id)
           select %L, id from permissions where code = 'payments.confirm'$$, :'manager_a'), 'row-level security');
select tests.expect('gestionnaire invite un collègue avec un rôle ≤ au sien (autorisé)',
  tests.affected(format($$insert into memberships (user_id, organization_id, role_id) values (%L, %L, %L)$$,
                        :uY, :'org_a', :'manager_a')) = 1);

-- Un roles.manage ne peut accorder que ce qu'il possède : le comptable
-- (roles.manage absent) ne peut rien accorder du tout.
select set_config('app.user_id', :uF, false) as _sub \gset
select tests.expect_error('comptable ajoute org.manage au rôle gestionnaire',
  format($$insert into role_permissions (role_id, permission_id)
           select %L, id from permissions where code = 'org.manage'$$, :'manager_a'), 'row-level security');

select tests.expect('comptable confirme le Mobile Money en attente (autorisé)',
  tests.affected(format($$update payments set status = 'succeeded', paid_at = now() where id = %L$$, :'payment_om')) = 1);

-- =====================================================================
-- F. Remboursement à quatre yeux
-- =====================================================================
select tests.expect('comptable valide la demande du caissier',
  tests.affected(format($$update refunds set status = 'approved' where id = %L$$, :'refund_1')) = 1);
select tests.expect('approved_by = le comptable',
  (select approved_by = :uF from refunds where id = :'refund_1'));
select tests.expect_error('comptable modifie le montant après validation',
  format($$update refunds set amount = 1 where id = %L$$, :'refund_1'), 'non modifiables');
select tests.expect('comptable exécute le remboursement',
  tests.affected(format($$update refunds set status = 'completed' where id = %L$$, :'refund_1')) = 1);
select tests.expect('paiement remboursé, créance rouverte (solde 300 000)',
  (select p.status = 'refunded' and i.balance = 300000
   from payments p, invoices i where p.id = :'payment_cash' and i.id = :'invoice_a'));
select tests.expect('caisse revenue à 0 après la sortie',
  (select balance = 0 from treasury_account_balances where account_id = :'cash_a'));

reset role;
rollback;
\echo 'Tous les tests de sécurité sont passés.'
