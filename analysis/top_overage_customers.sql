-- Largest overage charges in complete months.
-- Run: dbt show --select top_overage_customers --limit 10

select
    customer_id,
    billing_month,
    plan_name,
    delivered_minutes,
    included_delivery_minutes,
    overage_fee_usd,
    total_billed_usd
from {{ ref('fct_monthly_billing') }}
where is_complete_month
order by overage_fee_usd desc