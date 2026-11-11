-- =============================================================================
-- Cost monitoring queries. dbt tags every query with a query_tag
-- (see dbt_project.yml), so spend can be attributed to individual models.
-- Requires access to SNOWFLAKE.ACCOUNT_USAGE (data lags up to ~45 min).
-- =============================================================================
use role accountadmin;
use warehouse reporting_wh;

-- 1. Credits by warehouse, last 30 days
select
    warehouse_name,
    sum(credits_used)                       as credits,
    sum(credits_used_compute)               as compute_credits,
    sum(credits_used_cloud_services)        as cloud_services_credits
from snowflake.account_usage.warehouse_metering_history
where start_time >= dateadd(day, -30, current_timestamp())
group by 1
order by credits desc;

-- 2. Slowest dbt models over the last 7 days (by total elapsed time)
select
    query_tag,
    count(*)                                as runs,
    round(sum(total_elapsed_time) / 1000 / 60, 1) as total_minutes,
    round(avg(total_elapsed_time) / 1000, 1)      as avg_seconds,
    sum(bytes_scanned) / power(1024, 3)          as gb_scanned
from snowflake.account_usage.query_history
where start_time >= dateadd(day, -7, current_timestamp())
  and query_tag like 'dbt_%'
  and warehouse_name = 'TRANSFORMING_WH'
group by 1
order by total_minutes desc
limit 20;

-- 3. Queries with poor partition pruning (candidates for clustering / incremental)
select
    query_tag,
    partitions_scanned,
    partitions_total,
    round(partitions_scanned / nullif(partitions_total, 0) * 100, 1) as pct_scanned,
    total_elapsed_time / 1000 as seconds
from snowflake.account_usage.query_history
where start_time >= dateadd(day, -7, current_timestamp())
  and query_tag like 'dbt_%'
  and partitions_total > 100
order by pct_scanned desc, seconds desc
limit 20;
