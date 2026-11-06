with source as (
    select * from {{ source('platform', 'video_assets')}}
), 
renames as (
    select
        cast(asset_id as varchar)               as asset_id,
        cast(customer_id as varchar)            as customer_id,
        lower(trim(status))                     as asset_status,
        cast(duration_seconds as integer)       as duration_seconds,
        lower(trim(max_resolution))             as max_resolution,
        cast(created_at as timestamp)             as created_at,
        cast(deleted_at as timestamp)           as deleted_at,
        deleted_at is not null                  as is_deleted,
        cast(_loaded_at as timestamp)           as loaded_at
    from source
)

select * from renames