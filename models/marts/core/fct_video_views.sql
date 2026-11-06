{#
    Grain: one row per playback session (view_id).

    Incremental: each run re-processes the last N days of loaded data
    (var incremental_lookback_days) and merges on view_id, so late-arriving and
    re-sent events are picked up without duplicates. Full refresh rebuilds all.
#}

{{
    config(
        materialized='incremental',
        unique_key='view_id',
        incremental_strategy=('merge' if target.type == 'snowflake' else 'delete+insert'),
        on_schema_change='fail',
        cluster_by=(['view_date'] if target.type == 'snowflake' else none)
    )
}}

with views as (

    select * from {{ ref('stg_player__video_views') }}

    {% if is_incremental() %}
    where loaded_at >= (
        select {{ dbt.dateadd('day', -1 * var('incremental_lookback_days'), 'max(loaded_at)') }}
        from {{ this }}
    )
    {% endif %}

)

select
    cast(view_id as varchar)                    as view_id,
    cast(customer_id as varchar)                as customer_id,
    cast(asset_id as varchar)                   as asset_id,
    cast(viewer_id as varchar)                  as viewer_id,
    cast(view_started_at as timestamp)          as view_started_at,
    cast(view_ended_at as timestamp)            as view_ended_at,
    cast(view_started_at as date)               as view_date,
    cast(watch_time_ms as bigint)               as watch_time_ms,
    cast(startup_time_ms as bigint)             as startup_time_ms,
    cast(rebuffer_count as integer)             as rebuffer_count,
    cast(rebuffer_duration_ms as bigint)        as rebuffer_duration_ms,
    -- Share of the session spent stalled. Null when nothing was watched.
    cast(
        case
            when watch_time_ms + rebuffer_duration_ms > 0
            then rebuffer_duration_ms * 1.0 / (watch_time_ms + rebuffer_duration_ms)
        end as double
    )                                           as rebuffer_ratio,
    cast(rebuffer_count > 0 as boolean)         as had_rebuffering,
    cast(is_playback_failed as boolean)         as is_playback_failed,
    cast(error_code as varchar)                 as error_code,
    cast(device_type as varchar)                as device_type,
    cast(browser as varchar)                    as browser,
    cast(country_code as varchar)               as country_code,
    cast(cdn as varchar)                        as cdn,
    cast(loaded_at as timestamp)                as loaded_at
from views