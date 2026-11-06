-- Full SCD2 plan history for one customer.
-- Run: dbt show --select customer_plan_history --vars '{customer_id: cus_00012}'

select
    plan_sequence,
    plan_name,
    change_type,
    valid_from,
    valid_to,
    is_current
from {{ ref('dim_customer_plan_history') }}
where customer_id = '{{ var("customer_id", "cus_00001") }}'
order by plan_sequence