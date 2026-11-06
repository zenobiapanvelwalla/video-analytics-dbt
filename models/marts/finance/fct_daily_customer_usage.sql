{#
    Grain: one row per customer per day with at least one view.

    Each day is attributed to the plan the customer was on at the END of that
    day (point-in-time join against the SCD2 plan history). Because SCD2 ranges
    are contiguous and non-overlapping, exactly one plan period matches.
#}

with views as (

    select * from {{ ref('fct_video_views') }}

),

plan_history as (

    select * from {{ ref('dim_customer_plan_history') }}

),

daily as (

    select
        customer_id,
        view_date                                                   as usage_date,
        count(*)                                                    as view_count,
        count(distinct viewer_id)                                   as unique_viewer_count,
        sum(case when is_playback_failed then 1 else 0 end)         as failed_view_count,
        sum(watch_time_ms)                                          as watch_time_ms,
        sum(rebuffer_duration_ms)                                   as rebuffer_duration_ms
    from views
    group by customer_id, view_date

)

select
    cast(daily.customer_id || '-' || cast(daily.usage_date as varchar) as varchar)
                                                        as customer_usage_day_key,
    cast(daily.customer_id as varchar)                  as customer_id,
    cast(daily.usage_date as date)                      as usage_date,
    cast(plan_history.plan_name as varchar)             as plan_name,
    cast(daily.view_count as bigint)                    as view_count,
    cast(daily.unique_viewer_count as bigint)           as unique_viewer_count,
    cast(daily.failed_view_count as bigint)             as failed_view_count,
    cast(daily.watch_time_ms as bigint)                 as watch_time_ms,
    cast({{ ms_to_minutes('daily.watch_time_ms') }} as decimal(18, 2))
                                                        as delivered_minutes,
    cast(daily.rebuffer_duration_ms as bigint)          as rebuffer_duration_ms
from daily
left join plan_history
    on daily.customer_id = plan_history.customer_id
    and plan_history.valid_from < {{ dbt.dateadd('day', 1, 'cast(daily.usage_date as timestamp)') }}
    and (
        plan_history.valid_to >= {{ dbt.dateadd('day', 1, 'cast(daily.usage_date as timestamp)') }}
        or plan_history.valid_to is null
    )