-- 0003_views_functions.sql
-- Pricing-rule resolver and impact views

create or replace function public.get_pricing_rule(
  p_org_id uuid,
  p_product_id uuid,
  p_category_id uuid
)
returns table (
  org_id uuid,
  id uuid,
  scope text,
  category_id uuid,
  product_id uuid,
  mc_min_amount numeric,
  mc_target_pct numeric,
  round_to integer
)
language sql
stable
as $$
  select pr.org_id, pr.id, pr.scope, pr.category_id, pr.product_id, pr.mc_min_amount, pr.mc_target_pct, pr.round_to
  from public.pricing_rules pr
  where pr.org_id = p_org_id
    and (
      (pr.scope = 'product' and pr.product_id = p_product_id)
      or (pr.scope = 'category' and pr.category_id = p_category_id)
      or (pr.scope = 'global')
    )
  order by
    case pr.scope
      when 'product' then 1
      when 'category' then 2
      else 3
    end
  limit 1;
$$;

create or replace view public.v_actions_impact as
with latest_prices as (
  select distinct on (pp.org_id, pp.product_id, pp.sales_channel_id)
    pp.org_id,
    pp.product_id,
    pp.sales_channel_id,
    pp.price_current,
    pp.effective_from
  from public.product_prices pp
  order by pp.org_id, pp.product_id, pp.sales_channel_id, pp.effective_from desc
),
latest_costs as (
  select distinct on (pc.org_id, pc.product_id, pc.sales_channel_id)
    pc.org_id,
    pc.product_id,
    pc.sales_channel_id,
    pc.cost,
    pc.effective_from
  from public.product_costs pc
  order by pc.org_id, pc.product_id, pc.sales_channel_id, pc.effective_from desc
),
base as (
  select
    p.org_id,
    p.id as product_id,
    p.category_id,
    sc.id as sales_channel_id,
    lp.price_current,
    lc.cost,
    cf.vat_rate,
    cf.commission_pct,
    cf.commission_base,
    cf.payment_fee_pct,
    cf.commission_vat_pct,
    coalesce(pcv.units_per_month, 0) as units_per_month
  from public.products p
  join public.sales_channels sc on sc.org_id = p.org_id
  left join latest_prices lp
    on lp.org_id = p.org_id and lp.product_id = p.id and lp.sales_channel_id = sc.id
  left join latest_costs lc
    on lc.org_id = p.org_id and lc.product_id = p.id and lc.sales_channel_id = sc.id
  left join public.channel_fees cf
    on cf.org_id = p.org_id and cf.sales_channel_id = sc.id
  left join public.product_channel_volume pcv
    on pcv.org_id = p.org_id and pcv.product_id = p.id and pcv.sales_channel_id = sc.id
),
enriched as (
  select
    b.*,
    pr.id as pricing_rule_id,
    pr.scope as pricing_rule_scope,
    pr.mc_min_amount,
    pr.mc_target_pct,
    pr.round_to,
    case
      when b.commission_base = 'gross' then
        coalesce(b.commission_pct, 0)
        + coalesce(b.commission_pct, 0) * coalesce(b.commission_vat_pct, 0)
        + coalesce(b.payment_fee_pct, 0)
      when b.commission_base = 'net_of_vat' then
        (coalesce(b.commission_pct, 0) / nullif(1 + coalesce(b.vat_rate, 0), 0))
        + (coalesce(b.commission_pct, 0) / nullif(1 + coalesce(b.vat_rate, 0), 0)) * coalesce(b.commission_vat_pct, 0)
        + coalesce(b.payment_fee_pct, 0)
      else
        coalesce(b.payment_fee_pct, 0)
    end as fee_rate_on_gross
  from base b
  left join lateral public.get_pricing_rule(b.org_id, b.product_id, b.category_id) pr on true
),
calculated as (
  select
    e.*,
    case
      when e.cost is null then null
      when e.mc_target_pct is null then null
      when (1 - coalesce(e.fee_rate_on_gross, 0) - e.mc_target_pct) <= 0 then null
      else e.cost / (1 - coalesce(e.fee_rate_on_gross, 0) - e.mc_target_pct)
    end as target_price_raw,
    case
      when e.cost is null then null
      when e.mc_min_amount is null then null
      when (1 - coalesce(e.fee_rate_on_gross, 0)) <= 0 then null
      else (e.cost + e.mc_min_amount) / (1 - coalesce(e.fee_rate_on_gross, 0))
    end as min_amount_price_raw
  from enriched e
),
computed as (
  select
    c.*,
    greatest(c.target_price_raw, c.min_amount_price_raw) as suggested_raw,
    case
      when greatest(c.target_price_raw, c.min_amount_price_raw) is null then null
      when coalesce(c.round_to, 1) <= 1 then ceil(greatest(c.target_price_raw, c.min_amount_price_raw) * 100) / 100
      else ceil(greatest(c.target_price_raw, c.min_amount_price_raw) / c.round_to::numeric) * c.round_to::numeric
    end as price_suggested
  from calculated c
),
final as (
  select
    c.org_id,
    c.product_id,
    c.sales_channel_id,
    c.category_id,
    c.pricing_rule_id,
    c.pricing_rule_scope,
    c.price_current,
    c.cost,
    c.units_per_month,
    c.vat_rate,
    c.commission_pct,
    c.commission_base,
    c.payment_fee_pct,
    c.commission_vat_pct,
    c.fee_rate_on_gross,
    c.mc_min_amount,
    c.mc_target_pct,
    c.round_to,
    c.target_price_raw,
    c.min_amount_price_raw,
    c.price_suggested,
    (coalesce(c.price_current, 0) * coalesce(c.commission_pct, 0)) as commission_amount_current,
    (coalesce(c.price_current, 0) * coalesce(c.commission_pct, 0) * coalesce(c.commission_vat_pct, 0)) as vat_commission_amount_current,
    (coalesce(c.price_current, 0) * coalesce(c.payment_fee_pct, 0)) as payment_fee_amount_current,
    (
      coalesce(c.price_current, 0)
      - coalesce(c.cost, 0)
      - (coalesce(c.price_current, 0) * coalesce(c.commission_pct, 0))
      - (coalesce(c.price_current, 0) * coalesce(c.commission_pct, 0) * coalesce(c.commission_vat_pct, 0))
      - (coalesce(c.price_current, 0) * coalesce(c.payment_fee_pct, 0))
    ) as profit_unit,
    case
      when c.price_current is null or c.price_current = 0 then null
      else (
        (
          c.price_current
          - coalesce(c.cost, 0)
          - (c.price_current * coalesce(c.commission_pct, 0))
          - (c.price_current * coalesce(c.commission_pct, 0) * coalesce(c.commission_vat_pct, 0))
          - (c.price_current * coalesce(c.payment_fee_pct, 0))
        ) / c.price_current
      )
    end as net_margin_pct,
    (
      (
        coalesce(c.price_suggested, 0)
        - coalesce(c.cost, 0)
        - (coalesce(c.price_suggested, 0) * coalesce(c.commission_pct, 0))
        - (coalesce(c.price_suggested, 0) * coalesce(c.commission_pct, 0) * coalesce(c.commission_vat_pct, 0))
        - (coalesce(c.price_suggested, 0) * coalesce(c.payment_fee_pct, 0))
      )
      - (
        coalesce(c.price_current, 0)
        - coalesce(c.cost, 0)
        - (coalesce(c.price_current, 0) * coalesce(c.commission_pct, 0))
        - (coalesce(c.price_current, 0) * coalesce(c.commission_pct, 0) * coalesce(c.commission_vat_pct, 0))
        - (coalesce(c.price_current, 0) * coalesce(c.payment_fee_pct, 0))
      )
    ) * coalesce(c.units_per_month, 0) as delta_profit_month,
    case
      when c.price_current is null then 'MISSING_PRICE'
      when c.cost is null then 'MISSING_COST'
      when (
        coalesce(c.price_current, 0)
        - coalesce(c.cost, 0)
        - (coalesce(c.price_current, 0) * coalesce(c.commission_pct, 0))
        - (coalesce(c.price_current, 0) * coalesce(c.commission_pct, 0) * coalesce(c.commission_vat_pct, 0))
        - (coalesce(c.price_current, 0) * coalesce(c.payment_fee_pct, 0))
      ) < 0 then 'MARGIN_NEGATIVE'
      when c.price_suggested is not null and c.price_current is not null and c.price_suggested > c.price_current then 'RAISE_PRICE'
      else 'OK'
    end as action
  from computed c
)
select * from final;

create or replace view public.v_actions_plan_impact as
select
  v.org_id,
  v.product_id,
  v.sales_channel_id,
  v.category_id,
  v.pricing_rule_id,
  v.pricing_rule_scope,
  v.price_current,
  v.price_suggested,
  po.proposed_price as override_price,
  coalesce(po.is_enabled, false) as override_is_enabled,
  case
    when po.is_enabled and po.proposed_price is not null then po.proposed_price
    else v.price_suggested
  end as price_plan,
  v.cost,
  v.units_per_month,
  v.vat_rate,
  v.commission_pct,
  v.commission_base,
  v.payment_fee_pct,
  v.commission_vat_pct,
  v.fee_rate_on_gross,
  v.mc_min_amount,
  v.mc_target_pct,
  v.round_to,
  v.profit_unit,
  v.net_margin_pct,
  (
    (
      coalesce(
        case
          when po.is_enabled and po.proposed_price is not null then po.proposed_price
          else v.price_suggested
        end,
        0
      )
      - coalesce(v.cost, 0)
      - (coalesce(
          case
            when po.is_enabled and po.proposed_price is not null then po.proposed_price
            else v.price_suggested
          end,
          0
        ) * coalesce(v.commission_pct, 0))
      - (coalesce(
          case
            when po.is_enabled and po.proposed_price is not null then po.proposed_price
            else v.price_suggested
          end,
          0
        ) * coalesce(v.commission_pct, 0) * coalesce(v.commission_vat_pct, 0))
      - (coalesce(
          case
            when po.is_enabled and po.proposed_price is not null then po.proposed_price
            else v.price_suggested
          end,
          0
        ) * coalesce(v.payment_fee_pct, 0))
    )
    - v.profit_unit
  ) * coalesce(v.units_per_month, 0) as delta_profit_month_plan,
  v.action,
  po.note,
  po.updated_at as override_updated_at
from public.v_actions_impact v
left join public.price_overrides po
  on po.org_id = v.org_id
  and po.product_id = v.product_id
  and po.sales_channel_id = v.sales_channel_id
  and po.location_id is null;
