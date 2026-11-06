select
    cast(asset_id as varchar)               as asset_id,
    cast(customer_id as varchar)            as customer_id,
    cast(asset_status as varchar)           as asset_status,
    cast(duration_seconds as integer)       as duration_seconds,
    cast(max_resolution as varchar)         as max_resolution,
    cast(created_at as timestamp)           as created_at,
    cast(deleted_at as timestamp)           as deleted_at,
    cast(is_deleted as boolean)             as is_deleted
from {{ ref('stg_platform__video_assets') }}