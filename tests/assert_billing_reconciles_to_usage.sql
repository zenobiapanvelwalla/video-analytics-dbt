-- Every delivered minute in daily usage must show up in monthly billing.
-- Catches fan-out (duplicated rows) or dropped rows in the billing joins.

with usage_total as (
    select sum(delivered_minutes) as minutes
    from {{ ref('fct_daily_customer_usage') }}
),

billing_total as (
    select sum(delivered_minutes) as minutes
    from {{ ref('fct_monthly_billing') }}
)

select
    usage_total.minutes   as usage_minutes,
    billing_total.minutes as billed_minutes
from usage_total
cross join billing_total
where abs(usage_total.minutes - billing_total.minutes) > 1