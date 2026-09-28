-- =====================================================================
-- 0003_payments_treasury.sql
-- MODULE 05 — Paiements, rapprochement (§11, §12)
-- MODULE 09 — Trésorerie (§22)
--
-- Mêmes règles multi-tenant que 0002 : organization_id partout et
-- FK composites (id, organization_id).
--
-- Principes :
--   * Les montants payés des factures et échéances ne sont jamais saisis
--     à la main : ils sont recalculés à partir des affectations de
--     paiements réussis (source unique de vérité).
--   * Un paiement réussi n'est plus modifiable sur ses champs financiers
--     (montant, moyen, compte...) : on corrige par un remboursement
--     (règle d'or, §29).
--   * Les soldes de caisse et de banque sont calculés (vue), pas stockés.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Comptes de trésorerie
-- ---------------------------------------------------------------------
create table public.cash_accounts (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references public.organizations (id) on delete cascade,
  school_id        uuid not null,
  name             text not null,              -- ex: 'Caisse principale'
  currency         text not null default 'XOF',
  opening_balance  numeric(14,2) not null default 0,
  is_active        boolean not null default true,
  created_at       timestamptz not null default now(),
  unique (id, organization_id),
  foreign key (school_id, organization_id) references public.schools (id, organization_id) on delete restrict
);

-- Pas de numéro de compte complet en base : seulement un libellé masqué.
create table public.bank_accounts (
  id                     uuid primary key default gen_random_uuid(),
  organization_id        uuid not null references public.organizations (id) on delete cascade,
  school_id              uuid not null,
  name                   text not null,
  bank_name              text,
  account_number_masked  text,                 -- ex: 'CI93 **** **** 1234'
  currency               text not null default 'XOF',
  opening_balance        numeric(14,2) not null default 0,
  is_active              boolean not null default true,
  created_at             timestamptz not null default now(),
  unique (id, organization_id),
  foreign key (school_id, organization_id) references public.schools (id, organization_id) on delete restrict
);

-- ---------------------------------------------------------------------
-- Paiements
-- ---------------------------------------------------------------------
create table public.payments (
  id                  uuid primary key default gen_random_uuid(),
  organization_id     uuid not null references public.organizations (id) on delete cascade,
  school_id           uuid not null,
  family_id           uuid not null,
  student_id          uuid,
  reference           text not null,           -- ex: 'PAY-2026-000245'
  external_reference  text,                    -- référence opérateur / banque
  method              public.payment_method not null,
  operator            text,                    -- ex: 'Orange Money', 'Wave'
  amount              numeric(14,2) not null check (amount > 0),
  currency            text not null default 'XOF',
  status              public.payment_status not null default 'initiated',
  paid_at             timestamptz,
  payer_name          text,
  payer_phone         text,
  cash_account_id     uuid,
  bank_account_id     uuid,
  recorded_by         uuid references auth.users (id),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (id, organization_id),
  unique (organization_id, reference),
  check (cash_account_id is null or bank_account_id is null),
  foreign key (school_id, organization_id)       references public.schools (id, organization_id) on delete restrict,
  foreign key (family_id, organization_id)       references public.families (id, organization_id) on delete restrict,
  foreign key (student_id, organization_id)      references public.students (id, organization_id) on delete restrict,
  foreign key (cash_account_id, organization_id) references public.cash_accounts (id, organization_id) on delete restrict,
  foreign key (bank_account_id, organization_id) references public.bank_accounts (id, organization_id) on delete restrict
);

-- Une même transaction opérateur ne peut être enregistrée qu'une fois
-- (protège contre le double encaissement d'un webhook rejoué).
create unique index payments_external_ref_uidx
  on public.payments (organization_id, method, external_reference)
  where external_reference is not null;

create index payments_family_idx on public.payments (family_id);
create index payments_status_idx on public.payments (organization_id, status, paid_at desc);

-- ---------------------------------------------------------------------
-- Rapprochement : affectation d'un paiement à une facture / échéance
-- ---------------------------------------------------------------------
create table public.payment_allocations (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references public.organizations (id) on delete cascade,
  payment_id       uuid not null,
  invoice_id       uuid not null,
  installment_id   uuid,
  amount           numeric(14,2) not null check (amount > 0),
  created_by       uuid references auth.users (id),
  created_at       timestamptz not null default now(),
  unique (id, organization_id),
  foreign key (payment_id, organization_id)     references public.payments (id, organization_id) on delete restrict,
  foreign key (invoice_id, organization_id)     references public.invoices (id, organization_id) on delete restrict,
  foreign key (installment_id, organization_id) references public.installments (id, organization_id) on delete restrict
);

create index payment_allocations_payment_idx     on public.payment_allocations (payment_id);
create index payment_allocations_invoice_idx     on public.payment_allocations (invoice_id);
create index payment_allocations_installment_idx on public.payment_allocations (installment_id);

-- ---------------------------------------------------------------------
-- Remboursements
-- ---------------------------------------------------------------------
create table public.refunds (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references public.organizations (id) on delete cascade,
  payment_id       uuid not null,
  amount           numeric(14,2) not null check (amount > 0),
  reason           text not null,
  status           public.refund_status not null default 'requested',
  requested_by     uuid references auth.users (id),
  approved_by      uuid references auth.users (id),
  completed_at     timestamptz,
  created_at       timestamptz not null default now(),
  unique (id, organization_id),
  foreign key (payment_id, organization_id) references public.payments (id, organization_id) on delete restrict
);

-- ---------------------------------------------------------------------
-- Mouvements de trésorerie (entrées / sorties)
-- ---------------------------------------------------------------------
create table public.treasury_transactions (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references public.organizations (id) on delete cascade,
  direction        public.cash_flow_direction not null,
  amount           numeric(14,2) not null check (amount > 0),
  currency         text not null default 'XOF',
  cash_account_id  uuid,
  bank_account_id  uuid,
  category         text not null,              -- ex: 'parent_payment', 'refund', 'supplier'
  payment_id       uuid,
  refund_id        uuid,
  occurred_on      date not null default current_date,
  description      text,
  recorded_by      uuid references auth.users (id),
  created_at       timestamptz not null default now(),
  unique (id, organization_id),
  -- exactement un compte : caisse OU banque
  check ((cash_account_id is null) <> (bank_account_id is null)),
  foreign key (cash_account_id, organization_id) references public.cash_accounts (id, organization_id) on delete restrict,
  foreign key (bank_account_id, organization_id) references public.bank_accounts (id, organization_id) on delete restrict,
  foreign key (payment_id, organization_id)      references public.payments (id, organization_id) on delete restrict,
  foreign key (refund_id, organization_id)       references public.refunds (id, organization_id) on delete restrict
);

create index treasury_tx_org_date_idx on public.treasury_transactions (organization_id, occurred_on desc);
-- Un paiement / remboursement ne génère qu'un seul mouvement automatique.
create unique index treasury_tx_payment_uidx on public.treasury_transactions (payment_id) where payment_id is not null and refund_id is null;
create unique index treasury_tx_refund_uidx  on public.treasury_transactions (refund_id)  where refund_id is not null;

-- =====================================================================
-- Logique de rapprochement
-- =====================================================================

-- Statuts de paiement qui comptent comme argent reçu.
create or replace function app.is_collected(s public.payment_status)
returns boolean
language sql immutable
as $$
  select s in ('succeeded', 'partially_refunded');
$$;

-- Recalcule le montant payé et le statut d'une échéance.
create or replace function app.recompute_installment(p_installment uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_paid numeric(14,2);
begin
  if p_installment is null then
    return;
  end if;

  select coalesce(sum(a.amount), 0) into v_paid
  from public.payment_allocations a
  join public.payments p on p.id = a.payment_id
  where a.installment_id = p_installment
    and app.is_collected(p.status);

  update public.installments i
  set amount_paid = v_paid,
      status = case
        when i.status = 'cancelled'  then 'cancelled'
        when v_paid >= i.amount      then 'paid'
        when v_paid > 0              then 'partially_paid'
        when i.due_date < current_date then 'overdue'
        else 'pending'
      end::public.installment_status
  where i.id = p_installment;

  if exists (select 1 from public.installments where id = p_installment and amount_paid > amount) then
    raise exception 'Affectation refusée : le montant payé dépasse le montant de l''échéance %', p_installment
      using errcode = 'check_violation';
  end if;
end;
$$;

-- Recalcule le montant payé et le statut d'une facture.
create or replace function app.recompute_invoice(p_invoice uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_paid numeric(14,2);
begin
  if p_invoice is null then
    return;
  end if;

  select coalesce(sum(a.amount), 0) into v_paid
  from public.payment_allocations a
  join public.payments p on p.id = a.payment_id
  where a.invoice_id = p_invoice
    and app.is_collected(p.status);

  update public.invoices f
  set amount_paid = v_paid,
      status = case
        when f.status in ('draft', 'cancelled') then f.status
        when v_paid >= f.total                  then 'paid'
        when v_paid > 0                         then 'partially_paid'
        when f.due_date < current_date          then 'overdue'
        else 'issued'
      end::public.invoice_status
  where f.id = p_invoice;

  if exists (select 1 from public.invoices where id = p_invoice and amount_paid > total) then
    raise exception 'Affectation refusée : le montant payé dépasse le total de la facture %', p_invoice
      using errcode = 'check_violation';
  end if;
end;
$$;

-- Contrôles d'une affectation avant écriture.
create or replace function app.check_allocation()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_payment_amount numeric(14,2);
  v_allocated      numeric(14,2);
begin
  -- L'échéance doit appartenir à la facture indiquée.
  if new.installment_id is not null and not exists (
    select 1 from public.installments
    where id = new.installment_id and invoice_id = new.invoice_id
  ) then
    raise exception 'L''échéance % n''appartient pas à la facture %', new.installment_id, new.invoice_id
      using errcode = 'check_violation';
  end if;

  -- On ne peut pas affecter plus que le montant du paiement.
  select amount into v_payment_amount from public.payments where id = new.payment_id for update;

  select coalesce(sum(amount), 0) into v_allocated
  from public.payment_allocations
  where payment_id = new.payment_id
    and id <> new.id;

  if v_allocated + new.amount > v_payment_amount then
    raise exception 'Affectation refusée : % déjà affectés + % dépassent le paiement de %',
      v_allocated, new.amount, v_payment_amount
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger payment_allocations_check
  before insert or update on public.payment_allocations
  for each row execute function app.check_allocation();

-- Après toute modification d'affectation : recalcul des soldes concernés.
create or replace function app.after_allocation_change()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform app.recompute_installment(old.installment_id);
    perform app.recompute_invoice(old.invoice_id);
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    perform app.recompute_installment(new.installment_id);
    perform app.recompute_invoice(new.invoice_id);
  end if;
  return null;
end;
$$;

create trigger payment_allocations_recompute
  after insert or update or delete on public.payment_allocations
  for each row execute function app.after_allocation_change();

-- =====================================================================
-- Règles sur les paiements
-- =====================================================================

-- Un paiement encaissé est figé sur ses champs financiers.
create or replace function app.guard_payment_update()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  -- Un paiement entièrement remboursé est définitif.
  if old.status = 'refunded' and new is distinct from old then
    raise exception 'Paiement % remboursé : aucune modification possible', old.reference
      using errcode = 'check_violation';
  end if;

  if app.is_collected(old.status) and (
       new.amount          is distinct from old.amount
    or new.currency        is distinct from old.currency
    or new.method          is distinct from old.method
    or new.family_id       is distinct from old.family_id
    or new.cash_account_id is distinct from old.cash_account_id
    or new.bank_account_id is distinct from old.bank_account_id
    or new.organization_id is distinct from old.organization_id
  ) then
    raise exception 'Paiement % déjà encaissé : champs financiers non modifiables, passer par un remboursement', old.reference
      using errcode = 'check_violation';
  end if;

  -- Un paiement encaissé ne redevient pas « en attente » ou « échoué ».
  if app.is_collected(old.status)
     and new.status not in ('succeeded', 'partially_refunded', 'refunded') then
    raise exception 'Transition de statut interdite : % -> %', old.status, new.status
      using errcode = 'check_violation';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create trigger payments_guard
  before update on public.payments
  for each row execute function app.guard_payment_update();

-- Pas de suppression d'un paiement encaissé.
create or replace function app.guard_payment_delete()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if app.is_collected(old.status) or old.status = 'refunded' then
    raise exception 'Paiement % encaissé : suppression interdite', old.reference
      using errcode = 'check_violation';
  end if;
  return old;
end;
$$;

create trigger payments_guard_delete
  before delete on public.payments
  for each row execute function app.guard_payment_delete();

-- Changement de statut d'un paiement : recalcul des factures touchées et
-- mouvement de trésorerie automatique à l'encaissement.
create or replace function app.after_payment_status_change()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  r record;
begin
  if new.status is distinct from old.status then
    for r in
      select distinct invoice_id, installment_id
      from public.payment_allocations
      where payment_id = new.id
    loop
      perform app.recompute_installment(r.installment_id);
      perform app.recompute_invoice(r.invoice_id);
    end loop;

    if new.status = 'succeeded'
       and not app.is_collected(old.status)
       and (new.cash_account_id is not null or new.bank_account_id is not null) then
      insert into public.treasury_transactions
        (organization_id, direction, amount, currency, cash_account_id, bank_account_id,
         category, payment_id, occurred_on, description, recorded_by)
      values
        (new.organization_id, 'in', new.amount, new.currency, new.cash_account_id, new.bank_account_id,
         'parent_payment', new.id, coalesce(new.paid_at, now())::date,
         'Paiement ' || new.reference, auth.uid());
    end if;
  end if;
  return null;
end;
$$;

create trigger payments_status_change
  after update of status on public.payments
  for each row execute function app.after_payment_status_change();

-- Un paiement créé directement « réussi » (ex: espèces au guichet)
-- génère aussi son mouvement de trésorerie.
create or replace function app.after_payment_insert()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if new.status = 'succeeded'
     and (new.cash_account_id is not null or new.bank_account_id is not null) then
    insert into public.treasury_transactions
      (organization_id, direction, amount, currency, cash_account_id, bank_account_id,
       category, payment_id, occurred_on, description, recorded_by)
    values
      (new.organization_id, 'in', new.amount, new.currency, new.cash_account_id, new.bank_account_id,
       'parent_payment', new.id, coalesce(new.paid_at, now())::date,
       'Paiement ' || new.reference, auth.uid());
  end if;
  return null;
end;
$$;

create trigger payments_insert_treasury
  after insert on public.payments
  for each row execute function app.after_payment_insert();

-- =====================================================================
-- Remboursements
-- =====================================================================

-- Le total remboursé ne peut pas dépasser le paiement, et seul un
-- paiement encaissé peut être remboursé.
create or replace function app.check_refund()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_payment  public.payments%rowtype;
  v_refunded numeric(14,2);
begin
  select * into v_payment from public.payments where id = new.payment_id for update;

  if not app.is_collected(v_payment.status) and v_payment.status <> 'refunded' then
    raise exception 'Seul un paiement encaissé peut être remboursé (statut actuel : %)', v_payment.status
      using errcode = 'check_violation';
  end if;

  select coalesce(sum(amount), 0) into v_refunded
  from public.refunds
  where payment_id = new.payment_id
    and status <> 'rejected'
    and id <> new.id;

  if new.status <> 'rejected' and v_refunded + new.amount > v_payment.amount then
    raise exception 'Remboursement refusé : % déjà remboursés + % dépassent le paiement de %',
      v_refunded, new.amount, v_payment.amount
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger refunds_check
  before insert or update on public.refunds
  for each row execute function app.check_refund();

-- Remboursement effectué : statut du paiement + mouvement de sortie.
-- Effet sur les créances :
--   * remboursement total : le paiement passe à 'refunded', ses
--     affectations ne comptent plus, les factures redeviennent dues ;
--   * remboursement partiel : le paiement reste compté ; pour rouvrir la
--     part remboursée, l'application réduit l'affectation concernée
--     (opération tracée par l'audit).
create or replace function app.after_refund_completed()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_payment  public.payments%rowtype;
  v_refunded numeric(14,2);
begin
  if new.status = 'completed' and (tg_op = 'INSERT' or old.status is distinct from 'completed') then
    select * into v_payment from public.payments where id = new.payment_id;

    select coalesce(sum(amount), 0) into v_refunded
    from public.refunds
    where payment_id = new.payment_id and status = 'completed';

    update public.payments
    set status = case when v_refunded >= v_payment.amount then 'refunded' else 'partially_refunded' end::public.payment_status
    where id = new.payment_id;

    if v_payment.cash_account_id is not null or v_payment.bank_account_id is not null then
      insert into public.treasury_transactions
        (organization_id, direction, amount, currency, cash_account_id, bank_account_id,
         category, payment_id, refund_id, occurred_on, description, recorded_by)
      values
        (new.organization_id, 'out', new.amount, v_payment.currency,
         v_payment.cash_account_id, v_payment.bank_account_id,
         'refund', new.payment_id, new.id, coalesce(new.completed_at, now())::date,
         'Remboursement ' || v_payment.reference, auth.uid());
    end if;
  end if;
  return null;
end;
$$;

create trigger refunds_completed
  after insert or update of status on public.refunds
  for each row execute function app.after_refund_completed();

-- =====================================================================
-- Soldes de trésorerie (calculés)
-- security_invoker : la vue applique les droits (RLS) de l'utilisateur
-- qui l'interroge, pas ceux de son propriétaire.
-- =====================================================================
create view public.treasury_account_balances
with (security_invoker = true)
as
select
  'cash'::text as account_type,
  c.id         as account_id,
  c.organization_id,
  c.school_id,
  c.name,
  c.currency,
  c.opening_balance
    + coalesce(sum(case t.direction when 'in' then t.amount else -t.amount end), 0) as balance
from public.cash_accounts c
left join public.treasury_transactions t on t.cash_account_id = c.id
group by c.id
union all
select
  'bank'::text,
  b.id,
  b.organization_id,
  b.school_id,
  b.name,
  b.currency,
  b.opening_balance
    + coalesce(sum(case t.direction when 'in' then t.amount else -t.amount end), 0)
from public.bank_accounts b
left join public.treasury_transactions t on t.bank_account_id = b.id
group by b.id;
