{#
    Playback sessions from the player SDK.

    Cleaning done here (and only here):
      1. Deduplicate: the pipeline is at-least-once, so a view_id can arrive
         more than once. Keep the most recently loaded copy.
      2. Standardize: upper-case country codes; missing device type -> 'unknown'.
      3. Cast every column from the raw VARCHAR landing format.
#}

with source as (

    select * from {{ source('player', 'video_views') }}
    where true {{ limit_data_in_dev('cast(view_started_at as timestamp)') }}

),
deduplicated as (

    select *
    from source
    qualify row_number() over (
        partition by view_id
        order by cast(_loaded_at as timestamp) desc
    ) = 1

), renamed as (

    select
        -- ids
        cast(view_id as varchar)                            as view_id,
        cast(customer_id as varchar)                        as customer_id,
        cast(asset_id as varchar)                           as asset_id,
        cast(viewer_id as varchar)                          as viewer_id,

        -- timestamps
        cast(view_started_at as timestamp)                  as view_started_at,
        cast(view_ended_at as timestamp)                    as view_ended_at,
        cast(_loaded_at as timestamp)                       as loaded_at,

        -- playback quality measures
        cast(watch_time_ms as bigint)                       as watch_time_ms,
        cast(startup_time_ms as bigint)                     as startup_time_ms,
        cast(rebuffer_count as integer)                     as rebuffer_count,
        cast(rebuffer_duration_ms as bigint)                as rebuffer_duration_ms,
        cast(playback_failed as boolean)                    as is_playback_failed,
        nullif(trim(error_code), '')                        as error_code,

        -- dimensions
        coalesce(nullif(lower(trim(device_type)), ''), 'unknown') as device_type,
        lower(trim(browser))                                as browser,
        upper(trim(country))                                as country_code,
        lower(trim(cdn))                                    as cdn

    from deduplicated
)

select * from renamed