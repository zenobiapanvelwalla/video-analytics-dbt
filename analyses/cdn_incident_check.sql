-- Hourly failure rate for one CDN, on deduplicated data. Compare with
-- scripts/find_cdn_incident.py (raw data): the incident hours should match.
-- Run: dbt show --select cdn_incident_check --limit 10
--      dbt show --select cdn_incident_check --vars '{cdn: cdn_a, min_views: 5}'

select
    date_trunc('hour', view_started_at)                         as hour_utc,
    count(*)                                                    as views,
    sum(case when is_playback_failed then 1 else 0 end)         as failed,
    round(100.0 * avg(case when is_playback_failed then 1 else 0 end), 1) as failure_pct
from {{ ref('stg_player__video_views') }}
where cdn = '{{ var("cdn", "cdn_b") }}'
group by 1
having count(*) >= {{ var("min_views", 10) }}
order by failure_pct desc, views desc