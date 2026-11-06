-- total_billed_usd must always equal base fee + overage fee.

select *
from {{ ref('fct_monthly_billing') }}
where total_billed_usd != base_fee_usd + overage_fee_usd