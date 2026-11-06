-- The fact table must contain exactly the deduplicated staging views.
-- Guards the incremental logic: a bad lookback window would silently drop rows.

select
    (select count(*) from {{ ref('stg_player__video_views') }}) as staging_views,
    (select count(*) from {{ ref('fct_video_views') }})         as fact_views
where (select count(*) from {{ ref('stg_player__video_views') }})
   != (select count(*) from {{ ref('fct_video_views') }})