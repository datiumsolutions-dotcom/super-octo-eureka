-- 0001_init.sql
-- Base multi-tenant schema for pricing SaaS

create extension if not exists pgcrypto;

create table if not exists public.orgs (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.memberships (
  org_id uuid not null references public.orgs(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'admin', 'member')),
  created_at timestamptz not null default now(),
  primary key (org_id, user_id)
);

create table if not exists public.categories (
  org_id uuid not null references public.orgs(id) on delete cascade,
  id uuid not null default gen_random_uuid(),
  name text not null,
  primary key (org_id, id),
  unique (org_id, name)
);

create table if not exists public.products (
  org_id uuid not null references public.orgs(id) on delete cascade,
  id uuid not null default gen_random_uuid(),
  name text not null,
  category_id uuid,
  is_active boolean not null default true,
  primary key (org_id, id),
  constraint products_category_fk
    foreign key (org_id, category_id)
    references public.categories(org_id, id)
    on delete set null
);

create table if not exists public.sales_channels (
  org_id uuid not null references public.orgs(id) on delete cascade,
  id uuid not null default gen_random_uuid(),
  name text not null,
  primary key (org_id, id),
  unique (org_id, name)
);

create table if not exists public.product_prices (
  org_id uuid not null references public.orgs(id) on delete cascade,
  product_id uuid not null,
  sales_channel_id uuid not null,
  price_current numeric(12,2) not null check (price_current >= 0),
  effective_from date not null,
  primary key (org_id, product_id, sales_channel_id, effective_from),
  constraint product_prices_product_fk
    foreign key (org_id, product_id)
    references public.products(org_id, id)
    on delete cascade,
  constraint product_prices_channel_fk
    foreign key (org_id, sales_channel_id)
    references public.sales_channels(org_id, id)
    on delete cascade
);

create table if not exists public.product_costs (
  org_id uuid not null references public.orgs(id) on delete cascade,
  product_id uuid not null,
  sales_channel_id uuid not null,
  cost numeric(12,2) not null check (cost >= 0),
  cost_source text not null check (cost_source in ('manual', 'import')),
  effective_from date not null,
  primary key (org_id, product_id, sales_channel_id, effective_from),
  constraint product_costs_product_fk
    foreign key (org_id, product_id)
    references public.products(org_id, id)
    on delete cascade,
  constraint product_costs_channel_fk
    foreign key (org_id, sales_channel_id)
    references public.sales_channels(org_id, id)
    on delete cascade
);

create table if not exists public.channel_fees (
  org_id uuid not null references public.orgs(id) on delete cascade,
  sales_channel_id uuid not null,
  vat_rate numeric(6,4) not null default 0.21,
  commission_pct numeric(6,4) not null default 0,
  commission_base text not null check (commission_base in ('net_of_vat', 'gross')),
  payment_fee_pct numeric(6,4) not null default 0,
  commission_vat_pct numeric(6,4) not null default 0.21,
  primary key (org_id, sales_channel_id),
  constraint channel_fees_channel_fk
    foreign key (org_id, sales_channel_id)
    references public.sales_channels(org_id, id)
    on delete cascade
);

create table if not exists public.product_channel_volume (
  org_id uuid not null references public.orgs(id) on delete cascade,
  product_id uuid not null,
  sales_channel_id uuid not null,
  units_per_month integer not null default 0 check (units_per_month >= 0),
  primary key (org_id, product_id, sales_channel_id),
  constraint product_channel_volume_product_fk
    foreign key (org_id, product_id)
    references public.products(org_id, id)
    on delete cascade,
  constraint product_channel_volume_channel_fk
    foreign key (org_id, sales_channel_id)
    references public.sales_channels(org_id, id)
    on delete cascade
);

create table if not exists public.pricing_rules (
  org_id uuid not null references public.orgs(id) on delete cascade,
  id uuid not null default gen_random_uuid(),
  scope text not null check (scope in ('global', 'category', 'product')),
  category_id uuid,
  product_id uuid,
  mc_min_amount numeric(12,2),
  mc_target_pct numeric(6,4),
  round_to integer not null default 1 check (round_to > 0),
  primary key (org_id, id),
  constraint pricing_rules_category_fk
    foreign key (org_id, category_id)
    references public.categories(org_id, id)
    on delete cascade,
  constraint pricing_rules_product_fk
    foreign key (org_id, product_id)
    references public.products(org_id, id)
    on delete cascade,
  constraint pricing_rules_scope_targets_chk check (
    (scope = 'global' and category_id is null and product_id is null)
    or (scope = 'category' and category_id is not null and product_id is null)
    or (scope = 'product' and category_id is null and product_id is not null)
  )
);

create unique index if not exists pricing_rules_one_global_per_org_uq
  on public.pricing_rules (org_id)
  where scope = 'global';

create unique index if not exists pricing_rules_one_per_category_uq
  on public.pricing_rules (org_id, category_id)
  where scope = 'category';

create unique index if not exists pricing_rules_one_per_product_uq
  on public.pricing_rules (org_id, product_id)
  where scope = 'product';

create table if not exists public.price_overrides (
  org_id uuid not null references public.orgs(id) on delete cascade,
  product_id uuid not null,
  sales_channel_id uuid not null,
  location_id uuid,
  proposed_price numeric(12,2) not null check (proposed_price >= 0),
  is_enabled boolean not null default true,
  note text,
  updated_at timestamptz not null default now(),
  constraint price_overrides_product_fk
    foreign key (org_id, product_id)
    references public.products(org_id, id)
    on delete cascade,
  constraint price_overrides_channel_fk
    foreign key (org_id, sales_channel_id)
    references public.sales_channels(org_id, id)
    on delete cascade,
  unique nulls not distinct (org_id, product_id, sales_channel_id, location_id)
);

-- Indexes to support multi-tenant access and historical lookups
create index if not exists memberships_user_id_idx on public.memberships (user_id);

create index if not exists categories_org_id_idx on public.categories (org_id);
create index if not exists products_org_id_idx on public.products (org_id);
create index if not exists products_org_category_idx on public.products (org_id, category_id);
create index if not exists sales_channels_org_id_idx on public.sales_channels (org_id);

create index if not exists product_prices_org_product_channel_effective_idx
  on public.product_prices (org_id, product_id, sales_channel_id, effective_from desc);
create index if not exists product_costs_org_product_channel_effective_idx
  on public.product_costs (org_id, product_id, sales_channel_id, effective_from desc);

create index if not exists channel_fees_org_id_idx on public.channel_fees (org_id);
create index if not exists product_channel_volume_org_id_idx on public.product_channel_volume (org_id);
create index if not exists pricing_rules_org_scope_idx on public.pricing_rules (org_id, scope);
create index if not exists price_overrides_org_product_channel_idx
  on public.price_overrides (org_id, product_id, sales_channel_id, location_id);
