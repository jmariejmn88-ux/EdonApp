-- =====================================================================
-- Contrôle rapide de la sécurité, en UNE seule instruction SQL.
--
-- Utilisable là où psql n'est pas disponible : éditeur SQL de Neon,
-- connecteur Neon... Crée des données de test, tente des intrusions,
-- puis lève volontairement une exception finale qui ANNULE TOUT : rien
-- n'est conservé dans la base. Le résultat s'affiche dans le message
-- d'erreur final : « CONTRÔLE TERMINÉ : n/n OK ... ».
--
-- À lancer avec la connexion propriétaire, après les migrations.
-- =====================================================================
do $check$
declare
  uA uuid := gen_random_uuid();   -- directeur école A
  uC uuid := gen_random_uuid();   -- caissier école A
  uB uuid := gen_random_uuid();   -- directeur école B
  orgA uuid; orgB uuid; schoolA uuid; familyA uuid; studentA uuid;
  cashA uuid; invoiceA uuid; paymentA uuid; cashierRole uuid;
  n int;
  ok int := 0;
  total int := 0;
  results text[] := '{}';
begin
  -- Le propriétaire s'accorde temporairement le droit d'endosser les rôles
  -- applicatifs (annulé avec le reste à la fin).
  execute format('grant authenticated, scola_app to %I', current_user);

  -- 1. Migrations et RLS
  total := total + 1;
  select count(*) into n from public._migrations;
  if n >= 6 then ok := ok + 1; results := array_append(results, format('OK migrations appliquées (%s)', n));
  else results := array_append(results, format('ÉCHEC migrations appliquées (%s)', n)); end if;

  total := total + 1;
  select count(*) into n from pg_tables
  where schemaname = 'public' and tablename <> '_migrations' and not rowsecurity;
  if n = 0 then ok := ok + 1; results := array_append(results, 'OK RLS active sur toutes les tables');
  else results := array_append(results, format('ÉCHEC %s table(s) sans RLS', n)); end if;

  -- Données : trois utilisateurs (le profil est créé automatiquement).
  insert into auth."user" (id, email, name) values
    (uA, 'controle.a.' || uA || '@test', 'Directeur A'),
    (uC, 'controle.c.' || uC || '@test', 'Caissier A'),
    (uB, 'controle.b.' || uB || '@test', 'Directeur B');
  insert into auth.account ("userId", "accountId", "providerId", password)
    values (uA, uA::text, 'credential', 'empreinte');

  -- Le directeur A inscrit son école et la prépare.
  perform set_config('app.user_id', uA::text, true);
  execute 'set local role authenticated';
  orgA := public.create_organization('Contrôle A', 'École A');
  select id into schoolA from public.schools where organization_id = orgA;
  insert into public.families (organization_id, name) values (orgA, 'Famille KOUASSI') returning id into familyA;
  insert into public.students (organization_id, school_id, family_id, matricule, first_name, last_name)
    values (orgA, schoolA, familyA, 'M001', 'Jean', 'KOUASSI') returning id into studentA;
  insert into public.cash_accounts (organization_id, school_id, name)
    values (orgA, schoolA, 'Caisse') returning id into cashA;
  insert into public.invoices (organization_id, school_id, student_id, family_id, number, status, total, due_date)
    values (orgA, schoolA, studentA, familyA, 'SCOL-2026-0045', 'issued', 300000, current_date + 90)
    returning id into invoiceA;
  select id into cashierRole from public.roles where organization_id = orgA and code = 'cashier';
  insert into public.memberships (user_id, organization_id, role_id) values (uC, orgA, cashierRole);

  -- 2. Le directeur B (autre école) attaque l'école A.
  perform set_config('app.user_id', uB::text, true);
  orgB := public.create_organization('Contrôle B', 'École B');

  total := total + 1;
  select count(*) into n from public.students where organization_id = orgA;
  if n = 0 then ok := ok + 1; results := array_append(results, 'OK école B ne voit aucun élève de A');
  else results := array_append(results, 'ÉCHEC école B voit des élèves de A'); end if;

  total := total + 1;
  begin
    insert into public.students (organization_id, school_id, family_id, matricule, first_name, last_name)
      values (orgA, schoolA, familyA, 'HACK', 'X', 'Y');
    results := array_append(results, 'ÉCHEC école B a pu créer un élève dans A');
  exception when others then
    ok := ok + 1; results := array_append(results, 'OK école B ne peut pas écrire dans A');
  end;

  -- 3. Le caissier de A.
  perform set_config('app.user_id', uC::text, true);

  total := total + 1;
  insert into public.payments (organization_id, school_id, family_id, student_id, reference, method, amount, status, cash_account_id)
    values (orgA, schoolA, familyA, studentA, 'PAY-2026-000245', 'cash', 100000, 'succeeded', cashA)
    returning id into paymentA;
  insert into public.payment_allocations (organization_id, payment_id, invoice_id, amount)
    values (orgA, paymentA, invoiceA, 100000);
  select count(*) into n from public.invoices where id = invoiceA and balance = 200000;
  if n = 1 then ok := ok + 1; results := array_append(results, 'OK paiement 100 000 rapproché, solde 200 000 (§12)');
  else results := array_append(results, 'ÉCHEC rapprochement du paiement'); end if;

  total := total + 1;
  begin
    insert into public.payments (organization_id, school_id, family_id, reference, method, amount, status)
      values (orgA, schoolA, familyA, 'PAY-OM-1', 'mobile_money', 50000, 'succeeded');
    results := array_append(results, 'ÉCHEC caissier a confirmé un Mobile Money');
  exception when others then
    ok := ok + 1; results := array_append(results, 'OK caissier ne peut pas confirmer un Mobile Money');
  end;

  total := total + 1;
  begin
    perform 1 from auth.account;
    results := array_append(results, 'ÉCHEC requête utilisateur lit les mots de passe');
  exception when insufficient_privilege then
    ok := ok + 1; results := array_append(results, 'OK mots de passe invisibles des requêtes utilisateur');
  end;

  -- 4. Le directeur A : garde-fous.
  perform set_config('app.user_id', uA::text, true);

  total := total + 1;
  begin
    update public.profiles set is_platform_admin = true where id = uA;
    results := array_append(results, 'ÉCHEC directeur devenu administrateur SaaS');
  exception when insufficient_privilege then
    ok := ok + 1; results := array_append(results, 'OK impossible de se donner les droits administrateur SaaS');
  end;

  total := total + 1;
  begin
    update public.invoices set status = 'paid' where id = invoiceA;
    results := array_append(results, 'ÉCHEC facture mise à « payée » à la main');
  exception when others then
    ok := ok + 1; results := array_append(results, 'OK statut « payée » non modifiable à la main');
  end;

  total := total + 1;
  begin
    delete from public.audit_log;
    results := array_append(results, 'ÉCHEC journal d''audit effaçable');
  exception when insufficient_privilege then
    ok := ok + 1; results := array_append(results, 'OK journal d''audit non effaçable');
  end;

  -- 5. Requête sans utilisateur, puis connexion applicative seule.
  perform set_config('app.user_id', '', true);

  total := total + 1;
  begin
    perform public.create_organization('X', 'Y');
    results := array_append(results, 'ÉCHEC école créée sans utilisateur');
  exception when insufficient_privilege then
    ok := ok + 1; results := array_append(results, 'OK aucune action sans utilisateur identifié');
  end;

  execute 'set local role scola_app';
  total := total + 1;
  begin
    perform 1 from public.students;
    results := array_append(results, 'ÉCHEC connexion applicative lit les élèves');
  exception when insufficient_privilege then
    ok := ok + 1; results := array_append(results, 'OK connexion applicative seule : aucune donnée métier');
  end;

  -- 6. Audit (lu en propriétaire).
  execute 'reset role';
  total := total + 1;
  select count(*) into n from public.audit_log
  where table_name = 'payments' and action = 'INSERT' and record_id = paymentA and changed_by = uC;
  if n = 1 then ok := ok + 1; results := array_append(results, 'OK paiement tracé dans l''audit avec son auteur réel');
  else results := array_append(results, 'ÉCHEC traçabilité du paiement'); end if;

  -- Fin : on annule tout en levant une exception qui porte le résultat.
  raise exception E'CONTRÔLE TERMINÉ : %/% OK (données de test annulées)\n%',
    ok, total, array_to_string(results, E'\n');
end
$check$;
