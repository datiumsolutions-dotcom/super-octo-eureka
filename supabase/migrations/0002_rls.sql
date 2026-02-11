-- 0002_rls.sql
-- Row-level security and membership helpers

create or replace function public.is_org_member(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.memberships m
    where m.org_id = p_org_id
      and m.user_id = auth.uid()
  );
$$;

create or replace function public.is_org_admin(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.memberships m
    where m.org_id = p_org_id
      and m.user_id = auth.uid()
      and m.role in ('owner', 'admin')
  );
$$;

alter table public.orgs enable row level security;
alter table public.memberships enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.sales_channels enable row level security;
alter table public.product_prices enable row level security;
alter table public.product_costs enable row level security;
alter table public.channel_fees enable row level security;
alter table public.product_channel_volume enable row level security;
alter table public.pricing_rules enable row level security;
alter table public.price_overrides enable row level security;

-- orgs policies
drop policy if exists orgs_select_member on public.orgs;
create policy orgs_select_member
  on public.orgs
  for select
  using (public.is_org_member(id));

drop policy if exists orgs_insert_authenticated on public.orgs;
create policy orgs_insert_authenticated
  on public.orgs
  for insert
  with check (auth.uid() is not null);

drop policy if exists orgs_update_admin on public.orgs;
create policy orgs_update_admin
  on public.orgs
  for update
  using (public.is_org_admin(id))
  with check (public.is_org_admin(id));

-- memberships policies
drop policy if exists memberships_select_self_or_admin on public.memberships;
create policy memberships_select_self_or_admin
  on public.memberships
  for select
  using (auth.uid() = user_id or public.is_org_admin(org_id));

drop policy if exists memberships_insert_self_or_admin on public.memberships;
create policy memberships_insert_self_or_admin
  on public.memberships
  for insert
  with check (auth.uid() = user_id or public.is_org_admin(org_id));

drop policy if exists memberships_update_admin on public.memberships;
create policy memberships_update_admin
  on public.memberships
  for update
  using (public.is_org_admin(org_id))
  with check (public.is_org_admin(org_id));

drop policy if exists memberships_delete_admin on public.memberships;
create policy memberships_delete_admin
  on public.memberships
  for delete
  using (public.is_org_admin(org_id));

-- Shared table policies: select for members, write for admins

drop policy if exists categories_select_member on public.categories;
create policy categories_select_member on public.categories for select using (public.is_org_member(org_id));
drop policy if exists categories_insert_admin on public.categories;
create policy categories_insert_admin on public.categories for insert with check (public.is_org_admin(org_id));
drop policy if exists categories_update_admin on public.categories;
create policy categories_update_admin on public.categories for update using (public.is_org_admin(org_id)) with check (public.is_org_admin(org_id));
drop policy if exists categories_delete_admin on public.categories;
create policy categories_delete_admin on public.categories for delete using (public.is_org_admin(org_id));

drop policy if exists products_select_member on public.products;
create policy products_select_member on public.products for select using (public.is_org_member(org_id));
drop policy if exists products_insert_admin on public.products;
create policy products_insert_admin on public.products for insert with check (public.is_org_admin(org_id));
drop policy if exists products_update_admin on public.products;
create policy products_update_admin on public.products for update using (public.is_org_admin(org_id)) with check (public.is_org_admin(org_id));
drop policy if exists products_delete_admin on public.products;
create policy products_delete_admin on public.products for delete using (public.is_org_admin(org_id));

drop policy if exists sales_channels_select_member on public.sales_channels;
create policy sales_channels_select_member on public.sales_channels for select using (public.is_org_member(org_id));
drop policy if exists sales_channels_insert_admin on public.sales_channels;
create policy sales_channels_insert_admin on public.sales_channels for insert with check (public.is_org_admin(org_id));
drop policy if exists sales_channels_update_admin on public.sales_channels;
create policy sales_channels_update_admin on public.sales_channels for update using (public.is_org_admin(org_id)) with check (public.is_org_admin(org_id));
drop policy if exists sales_channels_delete_admin on public.sales_channels;
create policy sales_channels_delete_admin on public.sales_channels for delete using (public.is_org_admin(org_id));

drop policy if exists product_prices_select_member on public.product_prices;
create policy product_prices_select_member on public.product_prices for select using (public.is_org_member(org_id));
drop policy if exists product_prices_insert_admin on public.product_prices;
create policy product_prices_insert_admin on public.product_prices for insert with check (public.is_org_admin(org_id));
drop policy if exists product_prices_update_admin on public.product_prices;
create policy product_prices_update_admin on public.product_prices for update using (public.is_org_admin(org_id)) with check (public.is_org_admin(org_id));
drop policy if exists product_prices_delete_admin on public.product_prices;
create policy product_prices_delete_admin on public.product_prices for delete using (public.is_org_admin(org_id));

drop policy if exists product_costs_select_member on public.product_costs;
create policy product_costs_select_member on public.product_costs for select using (public.is_org_member(org_id));
drop policy if exists product_costs_insert_admin on public.product_costs;
create policy product_costs_insert_admin on public.product_costs for insert with check (public.is_org_admin(org_id));
drop policy if exists product_costs_update_admin on public.product_costs;
create policy product_costs_update_admin on public.product_costs for update using (public.is_org_admin(org_id)) with check (public.is_org_admin(org_id));
drop policy if exists product_costs_delete_admin on public.product_costs;
create policy product_costs_delete_admin on public.product_costs for delete using (public.is_org_admin(org_id));

drop policy if exists channel_fees_select_member on public.channel_fees;
create policy channel_fees_select_member on public.channel_fees for select using (public.is_org_member(org_id));
drop policy if exists channel_fees_insert_admin on public.channel_fees;
create policy channel_fees_insert_admin on public.channel_fees for insert with check (public.is_org_admin(org_id));
drop policy if exists channel_fees_update_admin on public.channel_fees;
create policy channel_fees_update_admin on public.channel_fees for update using (public.is_org_admin(org_id)) with check (public.is_org_admin(org_id));
drop policy if exists channel_fees_delete_admin on public.channel_fees;
create policy channel_fees_delete_admin on public.channel_fees for delete using (public.is_org_admin(org_id));

drop policy if exists product_channel_volume_select_member on public.product_channel_volume;
create policy product_channel_volume_select_member on public.product_channel_volume for select using (public.is_org_member(org_id));
drop policy if exists product_channel_volume_insert_admin on public.product_channel_volume;
create policy product_channel_volume_insert_admin on public.product_channel_volume for insert with check (public.is_org_admin(org_id));
drop policy if exists product_channel_volume_update_admin on public.product_channel_volume;
create policy product_channel_volume_update_admin on public.product_channel_volume for update using (public.is_org_admin(org_id)) with check (public.is_org_admin(org_id));
drop policy if exists product_channel_volume_delete_admin on public.product_channel_volume;
create policy product_channel_volume_delete_admin on public.product_channel_volume for delete using (public.is_org_admin(org_id));

drop policy if exists pricing_rules_select_member on public.pricing_rules;
create policy pricing_rules_select_member on public.pricing_rules for select using (public.is_org_member(org_id));
drop policy if exists pricing_rules_insert_admin on public.pricing_rules;
create policy pricing_rules_insert_admin on public.pricing_rules for insert with check (public.is_org_admin(org_id));
drop policy if exists pricing_rules_update_admin on public.pricing_rules;
create policy pricing_rules_update_admin on public.pricing_rules for update using (public.is_org_admin(org_id)) with check (public.is_org_admin(org_id));
drop policy if exists pricing_rules_delete_admin on public.pricing_rules;
create policy pricing_rules_delete_admin on public.pricing_rules for delete using (public.is_org_admin(org_id));

drop policy if exists price_overrides_select_member on public.price_overrides;
create policy price_overrides_select_member on public.price_overrides for select using (public.is_org_member(org_id));
drop policy if exists price_overrides_insert_admin on public.price_overrides;
create policy price_overrides_insert_admin on public.price_overrides for insert with check (public.is_org_admin(org_id));
drop policy if exists price_overrides_update_admin on public.price_overrides;
create policy price_overrides_update_admin on public.price_overrides for update using (public.is_org_admin(org_id)) with check (public.is_org_admin(org_id));
drop policy if exists price_overrides_delete_admin on public.price_overrides;
create policy price_overrides_delete_admin on public.price_overrides for delete using (public.is_org_admin(org_id));
