-- =====================================================================
-- Tests de 0003_payments_treasury.sql
-- À lancer sur une base jetable après les migrations (voir README).
-- Chaque vérification affiche PASS ou lève une erreur.
-- =====================================================================
\set ON_ERROR_STOP 1
\pset tuples_only on
\pset format unaligned
begin;

-- Vérifie qu'une instruction est refusée par la base.
create function pg_temp.expect_error(label text, stmt text)
returns void language plpgsql as $$
begin
  execute stmt;
  raise exception 'FAIL (aurait dû être refusé) : %', label;
exception
  when raise_exception then raise;          -- notre propre FAIL
  when others then raise notice 'PASS refusé : % (%)', label, sqlerrm;
end $$;

create function pg_temp.expect(label text, ok boolean)
returns void language plpgsql as $$
begin
  if not coalesce(ok, false) then raise exception 'FAIL : %', label; end if;
  raise notice 'PASS : %', label;
end $$;

-- ---------------------------------------------------------------------
-- Données : organisation A (école, famille KOUASSI, Jean en 6e B) et
-- organisation B (un autre tenant).
-- ---------------------------------------------------------------------
insert into organizations (id, name) values
  ('a0000000-0000-0000-0000-000000000000', 'Groupe A'),
  ('b0000000-0000-0000-0000-000000000000', 'Groupe B');

insert into schools (id, organization_id, name) values
  ('a1000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000000', 'École A'),
  ('b1000000-0000-0000-0000-000000000000', 'b0000000-0000-0000-0000-000000000000', 'École B');

insert into families (id, organization_id, name) values
  ('a2000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000000', 'Famille KOUASSI'),
  ('b2000000-0000-0000-0000-000000000000', 'b0000000-0000-0000-0000-000000000000', 'Famille B');

insert into students (id, organization_id, school_id, family_id, matricule, first_name, last_name) values
  ('a3000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000000',
   'a1000000-0000-0000-0000-000000000000', 'a2000000-0000-0000-0000-000000000000', 'M001', 'Jean', 'KOUASSI');

insert into cash_accounts (id, organization_id, school_id, name) values
  ('a4000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000000',
   'a1000000-0000-0000-0000-000000000000', 'Caisse principale');

-- Facture de scolarité : 300 000 restant, dont l'échéance d'octobre de 100 000.
insert into invoices (id, organization_id, school_id, student_id, family_id, number, status, total, due_date) values
  ('a5000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000000',
   'a1000000-0000-0000-0000-000000000000', 'a3000000-0000-0000-0000-000000000000',
   'a2000000-0000-0000-0000-000000000000', 'SCOL-2026-0045', 'issued', 300000, '2026-12-31');

insert into installments (id, organization_id, invoice_id, sequence, due_date, amount) values
  ('a6000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000000',
   'a5000000-0000-0000-0000-000000000000', 1, '2026-10-31', 100000),
  ('a6000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000000',
   'a5000000-0000-0000-0000-000000000000', 2, '2026-11-30', 200000);

-- ---------------------------------------------------------------------
-- 1. Scénario du cahier §12 : paiement 100 000 -> solde 300 000 -> 200 000
-- ---------------------------------------------------------------------
insert into payments (id, organization_id, school_id, family_id, student_id, reference, method, amount, status, cash_account_id) values
  ('a7000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000000',
   'a1000000-0000-0000-0000-000000000000', 'a2000000-0000-0000-0000-000000000000',
   'a3000000-0000-0000-0000-000000000000', 'PAY-2026-000245', 'cash', 100000, 'pending',
   'a4000000-0000-0000-0000-000000000000');

insert into payment_allocations (organization_id, payment_id, invoice_id, installment_id, amount) values
  ('a0000000-0000-0000-0000-000000000000', 'a7000000-0000-0000-0000-000000000000',
   'a5000000-0000-0000-0000-000000000000', 'a6000000-0000-0000-0000-000000000001', 100000);

select pg_temp.expect('paiement en attente : solde facture inchangé (300 000)',
  (select balance = 300000 from invoices where number = 'SCOL-2026-0045'));

update payments set status = 'succeeded', paid_at = now() where reference = 'PAY-2026-000245';

select pg_temp.expect('paiement réussi : nouveau solde facture 200 000',
  (select balance = 200000 and status = 'partially_paid' from invoices where number = 'SCOL-2026-0045'));
select pg_temp.expect('échéance d''octobre soldée',
  (select status = 'paid' and balance = 0 from installments where id = 'a6000000-0000-0000-0000-000000000001'));
select pg_temp.expect('mouvement de trésorerie créé automatiquement (+100 000)',
  (select count(*) = 1 and sum(amount) = 100000 from treasury_transactions where payment_id = 'a7000000-0000-0000-0000-000000000000'));
select pg_temp.expect('solde de caisse = 100 000',
  (select balance = 100000 from treasury_account_balances where account_id = 'a4000000-0000-0000-0000-000000000000'));

-- ---------------------------------------------------------------------
-- 2. Tentatives qui doivent être refusées
-- ---------------------------------------------------------------------
select pg_temp.expect_error('modifier le montant d''un paiement encaissé (100 000 -> 120 000)',
  $$update payments set amount = 120000 where reference = 'PAY-2026-000245'$$);

select pg_temp.expect_error('repasser un paiement encaissé en « échoué »',
  $$update payments set status = 'failed' where reference = 'PAY-2026-000245'$$);

select pg_temp.expect_error('supprimer un paiement encaissé',
  $$delete from payments where reference = 'PAY-2026-000245'$$);

select pg_temp.expect_error('affecter plus que le montant du paiement',
  $$insert into payment_allocations (organization_id, payment_id, invoice_id, amount)
    values ('a0000000-0000-0000-0000-000000000000', 'a7000000-0000-0000-0000-000000000000',
            'a5000000-0000-0000-0000-000000000000', 1)$$);

select pg_temp.expect_error('affecter une échéance d''une autre facture',
  $$insert into invoices (id, organization_id, school_id, student_id, family_id, number, status, total)
    values ('a5000000-0000-0000-0000-000000000009', 'a0000000-0000-0000-0000-000000000000',
            'a1000000-0000-0000-0000-000000000000', 'a3000000-0000-0000-0000-000000000000',
            'a2000000-0000-0000-0000-000000000000', 'SCOL-2026-0099', 'issued', 50000);
    insert into payments (id, organization_id, school_id, family_id, reference, method, amount, status)
    values ('a7000000-0000-0000-0000-000000000009', 'a0000000-0000-0000-0000-000000000000',
            'a1000000-0000-0000-0000-000000000000', 'a2000000-0000-0000-0000-000000000000',
            'PAY-X', 'cash', 50000, 'succeeded');
    insert into payment_allocations (organization_id, payment_id, invoice_id, installment_id, amount)
    values ('a0000000-0000-0000-0000-000000000000', 'a7000000-0000-0000-0000-000000000009',
            'a5000000-0000-0000-0000-000000000009', 'a6000000-0000-0000-0000-000000000002', 1000)$$);

select pg_temp.expect_error('rattacher un paiement du tenant A à la famille du tenant B',
  $$insert into payments (organization_id, school_id, family_id, reference, method, amount)
    values ('a0000000-0000-0000-0000-000000000000', 'a1000000-0000-0000-0000-000000000000',
            'b2000000-0000-0000-0000-000000000000', 'PAY-CROSS', 'cash', 1000)$$);

select pg_temp.expect_error('enregistrer deux fois la même transaction opérateur',
  $$insert into payments (organization_id, school_id, family_id, reference, external_reference, method, amount)
    values ('a0000000-0000-0000-0000-000000000000', 'a1000000-0000-0000-0000-000000000000',
            'a2000000-0000-0000-0000-000000000000', 'PAY-W1', 'OM-123', 'mobile_money', 5000),
           ('a0000000-0000-0000-0000-000000000000', 'a1000000-0000-0000-0000-000000000000',
            'a2000000-0000-0000-0000-000000000000', 'PAY-W2', 'OM-123', 'mobile_money', 5000)$$);

select pg_temp.expect_error('rembourser plus que le paiement',
  $$insert into refunds (organization_id, payment_id, amount, reason)
    values ('a0000000-0000-0000-0000-000000000000', 'a7000000-0000-0000-0000-000000000000', 100001, 'test')$$);

-- ---------------------------------------------------------------------
-- 3. Remboursement total : la créance se rouvre, la caisse diminue,
--    et le paiement devient définitif.
-- ---------------------------------------------------------------------
insert into refunds (organization_id, payment_id, amount, reason, status, completed_at) values
  ('a0000000-0000-0000-0000-000000000000', 'a7000000-0000-0000-0000-000000000000',
   100000, 'Départ de l''élève', 'completed', now());

select pg_temp.expect('paiement passé en « refunded »',
  (select status = 'refunded' from payments where reference = 'PAY-2026-000245'));
select pg_temp.expect('créance rouverte : solde facture revenu à 300 000',
  (select balance = 300000 from invoices where number = 'SCOL-2026-0045'));
select pg_temp.expect('solde de caisse revenu à 0',
  (select balance = 0 from treasury_account_balances where account_id = 'a4000000-0000-0000-0000-000000000000'));

select pg_temp.expect_error('réactiver un paiement remboursé',
  $$update payments set status = 'succeeded' where reference = 'PAY-2026-000245'$$);

rollback;
\echo 'Tous les tests sont passés.'
