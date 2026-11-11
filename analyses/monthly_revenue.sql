-- Revenue by month: base vs overage, with completeness flag.
-- Run: dbt show --select monthly_revenue --limit 12

select
    billing_month,
    count(*)                                              as customers,
    sum(case when overage_fee_usd > 0 then 1 else 0 end)  as with_overage,
    sum(base_fee_usd)                                     as base_revenue,
    sum(overage_fee_usd)                                  as overage_revenue,
    sum(total_billed_usd)                                 as total_revenue,
    bool_and(is_complete_month)                           as complete
from {{ ref('fct_monthly_billing') }}
group by 1
order by 1
