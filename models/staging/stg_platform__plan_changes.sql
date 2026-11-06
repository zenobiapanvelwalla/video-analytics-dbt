with source as (
    select * from {{ source('platform', 'plan_changes') }}
),
renamed as (
    select
        cast(plan_change_id as varchar) as plan_change_id,
        cast(customer_id as varchar) as customer_id,
        lower(trim(plan_name)) as plan_name,
        cast(changed_at as timestamp) as changed_at,
    from source
)

select * from renamed