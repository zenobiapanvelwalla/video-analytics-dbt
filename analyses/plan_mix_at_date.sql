-- How many customers were on each plan N days ago (point-in-time query on SCD2).
-- Run: dbt show --select plan_mix_at_date --vars '{days_ago: 90}'

select
    plan_name,
    count(*) as customers
from {{ ref('dim_customer_plan_history') }}
where valid_from <= current_date - interval {{ var("days_ago", 60) }} day
  and (valid_to > current_date - interval {{ var("days_ago", 60) }} day or valid_to is null)
group by 1
order by 2 desc