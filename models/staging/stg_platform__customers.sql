with source as (
    select * from {{ source('platform', 'customers')}}
),
renamed as (
    select
        cast(customer_id as varchar) as customer_id,
        cast(company_name as varchar) as company_name,
        lower(trim(industry)) as industry,
        upper(trim(region)) as region,
        cast(signup_at as timestamp) as signed_up_at,
        cast(_loaded_at as timestamp) as loaded_at
    from source
)

select * from renamed