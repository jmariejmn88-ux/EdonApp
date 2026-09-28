-- =====================================================================
-- 0002_domain.sql
-- Modèle de données métier (cahier des charges §28).
--
-- Règle de conception multi-tenant appliquée à TOUTES les tables :
--   * `organization_id not null` ;
--   * `unique (id, organization_id)` ;
--   * chaque référence vers une autre table métier est une FK composite
--     `(xxx_id, organization_id) -> xxx (id, organization_id)`.
-- Conséquence : la base refuse de lier deux lignes de tenants différents,
-- même si un attaquant connaît l'UUID d'une ligne d'un autre tenant
-- (les contrôles de FK ne passent pas par RLS, d'où cette garantie).
--
-- Montants : numeric(14,2). La devise par défaut est le XOF (FCFA).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Types énumérés
-- ---------------------------------------------------------------------
create type public.student_status      as enum ('active', 'inactive', 'graduated', 'left');
create type public.service_category    as enum ('tuition', 'ancillary', 'transport', 'canteen', 'supplies', 'extracurricular', 'other');
create type public.service_frequency   as enum ('one_time', 'monthly', 'termly', 'annual');
create type public.subscription_status as enum ('active', 'paused', 'ended');
create type public.invoice_status      as enum ('draft', 'issued', 'partially_paid', 'paid', 'overdue', 'cancelled');
create type public.installment_status  as enum ('pending', 'partially_paid', 'paid', 'overdue', 'cancelled');
create type public.payment_method      as enum ('mobile_money', 'card', 'bank_transfer', 'bank_deposit', 'cash', 'manual', 'other');
create type public.payment_status      as enum ('initiated', 'pending', 'succeeded', 'failed', 'cancelled', 'refunded', 'partially_refunded');
create type public.refund_status       as enum ('requested', 'approved', 'completed', 'rejected');
create type public.message_channel     as enum ('whatsapp', 'sms', 'email');
create type public.message_direction   as enum ('outbound', 'inbound');
create type public.message_status      as enum ('queued', 'sent', 'delivered', 'read', 'failed');
create type public.expense_kind        as enum ('direct', 'indirect');
create type public.expense_status      as enum ('draft', 'to_pay', 'paid', 'cancelled');
create type public.allocation_basis    as enum ('surface', 'headcount', 'revenue', 'fixed_percent', 'estimated_consumption');
create type public.budget_line_type    as enum ('revenue', 'expense');
create type public.cash_flow_direction as enum ('in', 'out');

-- =====================================================================
-- MODULE 01 — ÉTABLISSEMENTS
-- =====================================================================
create table public.schools (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references public.organizations (id) on delete cascade,
  name             text not null,
  logo_url         text,
  address          text,
  phone            text,
  email            text,
  currency         text not null default 'XOF',
  timezone         text not null default 'Africa/Abidjan',
  billing_rules    jsonb not null default '{}'::jsonb,
  reminder_rules   jsonb not null default '{}'::jsonb,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (id, organization_id)
);

create table public.campuses (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references public.organizations (id) on delete cascade,
  school_id        uuid not null,
  name             text not null,
  address          text,
  created_at       timestamptz not null default now(),
  unique (id, organization_id),
  foreign key (school_id, organization_id) references public.schools (id, organization_id) on delete cascade
);

create table public.academic_years (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references public.organizations (id) on delete cascade,
  school_id        uuid not null,
  name             text not null,              -- ex: '2026-2027'
  starts_on        date not null,
  ends_on          date not null,
  is_current       boolean not null default false,
  created_at       timestamptz not null default now(),
  unique (id, organization_id),
  check (ends_on > starts_on),
  foreign key (school_id, organization_id) references public.schools (id, organization_id) on delete cascade
);

-- Niveaux (6e, CM2...) regroupés par cycle (primaire, collège, lycée).
create table public.grades (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references public.organizations (id) on delete cascade,
  school_id        uuid not null,
  cycle            text,
  name             text not null,
  sort_order       int not null default 0,
  created_at       timestamptz not null default now(),
  unique (id, organization_id),
  foreign key (school_id, organization_id) references public.schools (id, organization_id) on delete cascade
);

create table public.classes (
  id                uuid primary key default gen_random_uuid(),
  organization_id   uuid not null references public.organizations (id) on delete cascade,
  school_id         uuid not null,
  campus_id         uuid,
  grade_id          uuid not null,
  academic_year_id  uuid not null,
  name              text not null,             -- ex: '6e B'
  capacity          int,
  created_at        timestamptz not null default now(),
  unique (id, organization_id),
  foreign key (school_id, organization_id)        references public.schools (id, organization_id) on delete cascade,
  foreign key (campus_id, organization_id)        references public.campuses (id, organization_id) on delete set null (campus_id),
  foreign key (grade_id, organization_id)         references public.grades (id, organization_id) on delete restrict,
  foreign key (academic_year_id, organization_id) references public.academic_years (id, organization_id) on delete restrict
);

-- =====================================================================
-- MODULE 02 — ÉLÈVES & FAMILLES
-- =====================================================================
create table public.families (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references public.organizations (id) on delete cascade,
  name             text not null,              -- ex: 'Famille KOUASSI'
  notes            text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (id, organization_id)
);

create table public.guardians (
  id                    uuid primary key default gen_random_uuid(),
  organization_id       uuid not null references public.organizations (id) on delete cascade,
  family_id             uuid not null,
  full_name             text not null,
  relationship          text,                  -- père, mère, tuteur...
  phone                 text,
  whatsapp              text,                  -- format E.164, ex: +2250700000000
  email                 text,
  address               text,
  is_financial_contact  boolean not null default false,
  whatsapp_opt_in       boolean not null default false,  -- consentement aux messages
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (id, organization_id),
  foreign key (family_id, organization_id) references public.families (id, organization_id) on delete cascade
);

create table public.students (
  id                     uuid primary key default gen_random_uuid(),
  organization_id        uuid not null references public.organizations (id) on delete cascade,
  school_id              uuid not null,
  family_id              uuid not null,
  class_id               uuid,
  financial_guardian_id  uuid,
  matricule              text not null,
  first_name             text not null,
  last_name              text not null,
  birth_date             date,
  status                 public.student_status not null default 'active',
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  unique (id, organization_id),
  unique (school_id, matricule),
  foreign key (school_id, organization_id)             references public.schools (id, organization_id) on delete restrict,
  foreign key (family_id, organization_id)             references public.families (id, organization_id) on delete restrict,
  foreign key (class_id, organization_id)              references public.classes (id, organization_id) on delete set null (class_id),
  foreign key (financial_guardian_id, organization_id) references public.guardians (id, organization_id) on delete set null (financial_guardian_id)
);

create index students_family_idx on public.students (family_id);
create index students_class_idx  on public.students (class_id);

-- =====================================================================
-- MODULE 08 (référentiel) — CENTRES DE REVENUS ET DE COÛTS
-- (déclarés tôt car référencés par les services et les dépenses)
-- =====================================================================
create table public.revenue_centers (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references public.organizations (id) on delete cascade,
  code             text not null,
  name             text not null,
  created_at       timestamptz not null default now(),
  unique (id, organization_id),
  unique (organization_id, code)
);

create table public.cost_centers (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references public.organizations (id) on delete cascade,
  code             text not null,              -- ex: 'CANTINE', 'TRANSPORT'
  name             text not null,
  created_at       timestamptz not null default now(),
  unique (id, organization_id),
  unique (organization_id, code)
);

-- =====================================================================
-- MODULE 03 — CATALOGUE DES SERVICES
-- =====================================================================
create table public.services (
  id                 uuid primary key default gen_random_uuid(),
  organization_id    uuid not null references public.organizations (id) on delete cascade,
  school_id          uuid not null,
  revenue_center_id  uuid,
  cost_center_id     uuid,
  name               text not null,
  category           public.service_category not null,
  price              numeric(14,2) not null check (price >= 0),
  currency           text not null default 'XOF',
  frequency          public.service_frequency not null default 'one_time',
  period_start       date,
  period_end         date,
  tax_rate           numeric(5,2) not null default 0 check (tax_rate >= 0),
  billing_conditions jsonb not null default '{}'::jsonb,
  is_active          boolean not null default true,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (id, organization_id),
  foreign key (school_id, organization_id)         references public.schools (id, organization_id) on delete cascade,
  foreign key (revenue_center_id, organization_id) references public.revenue_centers (id, organization_id) on delete set null (revenue_center_id),
  foreign key (cost_center_id, organization_id)    references public.cost_centers (id, organization_id) on delete set null (cost_center_id)
);

create table public.service_subscriptions (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references public.organizations (id) on delete cascade,
  student_id       uuid not null,
  service_id       uuid not null,
  starts_on        date not null,
  ends_on          date,
  custom_price     numeric(14,2) check (custom_price >= 0),
  status           public.subscription_status not null default 'active',
  created_at       timestamptz not null default now(),
  unique (id, organization_id),
  foreign key (student_id, organization_id) references public.students (id, organization_id) on delete restrict,
  foreign key (service_id, organization_id) references public.services (id, organization_id) on delete restrict
);

-- =====================================================================
-- MODULE 04 — FACTURATION  +  ÉCHÉANCIERS (§10)
-- =====================================================================
create table public.invoices (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references public.organizations (id) on delete cascade,
  school_id        uuid not null,
  student_id       uuid not null,
  family_id        uuid not null,
  number           text not null,              -- ex: 'SCOL-2026-0045'
  status           public.invoice_status not null default 'draft',
  issue_date       date not null default current_date,
  due_date         date,
  currency         text not null default 'XOF',
  subtotal         numeric(14,2) not null default 0,
  tax_total        numeric(14,2) not null default 0,
  total            numeric(14,2) not null default 0 check (total >= 0),
  amount_paid      numeric(14,2) not null default 0 check (amount_paid >= 0),
  balance          numeric(14,2) generated always as (total - amount_paid) stored,
  notes            text,
  created_by       uuid references auth.users (id),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (id, organization_id),
  unique (organization_id, number),
  foreign key (school_id, organization_id)  references public.schools (id, organization_id) on delete restrict,
  foreign key (student_id, organization_id) references public.students (id, organization_id) on delete restrict,
  foreign key (family_id, organization_id)  references public.families (id, organization_id) on delete restrict
);

create index invoices_family_idx  on public.invoices (family_id);
create index invoices_student_idx on public.invoices (student_id);
create index invoices_status_idx  on public.invoices (organization_id, status);

create table public.invoice_items (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references public.organizations (id) on delete cascade,
  invoice_id       uuid not null,
  service_id       uuid,
  description      text not null,
  quantity         numeric(10,2) not null default 1 check (quantity > 0),
  unit_price       numeric(14,2) not null check (unit_price >= 0),
  tax_rate         numeric(5,2) not null default 0,
  amount           numeric(14,2) generated always as (round(quantity * unit_price, 2)) stored,
  unique (id, organization_id),
  foreign key (invoice_id, organization_id) references public.invoices (id, organization_id) on delete cascade,
  foreign key (service_id, organization_id) references public.services (id, organization_id) on delete set null (service_id)
);

create table public.installments (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references public.organizations (id) on delete cascade,
  invoice_id       uuid not null,
  sequence         int not null,
  due_date         date not null,
  amount           numeric(14,2) not null check (amount > 0),
  amount_paid      numeric(14,2) not null default 0 check (amount_paid >= 0),
  balance          numeric(14,2) generated always as (amount - amount_paid) stored,
  status           public.installment_status not null default 'pending',
  unique (id, organization_id),
  unique (invoice_id, sequence),
  foreign key (invoice_id, organization_id) references public.invoices (id, organization_id) on delete cascade
);

create index installments_due_idx on public.installments (organization_id, due_date) where status in ('pending', 'partially_paid', 'overdue');


-- Suite du modèle (paiements, remboursements, relances, charges,
-- fournisseurs, budget, trésorerie) : migration suivante, à venir.
