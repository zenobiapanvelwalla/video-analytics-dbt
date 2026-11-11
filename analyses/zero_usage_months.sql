-- Months billed with no usage: revenue that only exists because of the billing grid.
-- Run: dbt show --select zero_usage_months

select
    count(*)               as zero_usage_months,
    sum(total_billed_usd)  as base_fees_billed
from {{ ref('fct_monthly_billing') }}
where view_count = 0