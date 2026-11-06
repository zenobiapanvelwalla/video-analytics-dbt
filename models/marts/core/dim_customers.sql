with customers as (

    select * from {{ ref('stg_platform__customers') }}

),

plan_history as (

    select * from {{ ref('dim_customer_plan_history') }}

),

current_plan as (

    select customer_id, plan_name, valid_from
    from plan_history
    where is_current

),

plan_stats as (

    select
        customer_id,
        count(*) - 1                                                as plan_change_count,
        sum(case when change_type = 'upgrade' then 1 else 0 end)   as upgrade_count,
        sum(case when change_type = 'downgrade' then 1 else 0 end) as downgrade_count,
        max(case when plan_sequence = 1 then plan_name end)        as initial_plan_name
    from plan_history
    group by customer_id

),

assets as (

    select
        customer_id,
        count(*)                as asset_count,
        min(created_at)         as first_asset_created_at
    from {{ ref('stg_platform__video_assets') }}
    group by customer_id

)

select
    cast(customers.customer_id as varchar)              as customer_id,
    cast(customers.company_name as varchar)             as company_name,
    cast(customers.industry as varchar)                 as industry,
    cast(customers.region as varchar)                   as region,
    cast(customers.signed_up_at as timestamp)           as signed_up_at,
    cast(current_plan.plan_name as varchar)             as current_plan_name,
    cast(current_plan.valid_from as timestamp)          as current_plan_started_at,
    cast(plan_stats.initial_plan_name as varchar)       as initial_plan_name,
    cast(plan_stats.plan_change_count as integer)       as plan_change_count,
    cast(plan_stats.upgrade_count as integer)           as upgrade_count,
    cast(plan_stats.downgrade_count as integer)         as downgrade_count,
    cast(coalesce(assets.asset_count, 0) as integer)    as asset_count,
    cast(assets.first_asset_created_at as timestamp)    as first_asset_created_at
from customers
left join current_plan
    on customers.customer_id = current_plan.customer_id
left join plan_stats
    on customers.customer_id = plan_stats.customer_id
left join assets
    on customers.customer_id = assets.customer_id