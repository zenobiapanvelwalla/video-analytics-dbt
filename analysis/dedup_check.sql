-- How many duplicate events staging removed.
-- Run: dbt show --select dedup_check

select
    (select count(*) from {{ source('player', 'video_views') }})  as raw_rows,
    (select count(*) from {{ ref('stg_player__video_views') }})  as staged_rows,
    (select count(*) from {{ source('player', 'video_views') }})
  - (select count(*) from {{ ref('stg_player__video_views') }})  as duplicates_removed