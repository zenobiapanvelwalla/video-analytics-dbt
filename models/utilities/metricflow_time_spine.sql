{#
    Daily date spine: one row per calendar day. Used to build the
    customer x month billing grid.
    Portable across Snowflake and DuckDB (no warehouse-specific functions).
#}

with digits as (

    select 0 as d union all select 1 union all select 2 union all select 3 union all select 4
    union all select 5 union all select 6 union all select 7 union all select 8 union all select 9

),

numbers as (

    select ones.d + 10 * tens.d + 100 * hundreds.d + 1000 * thousands.d as n
    from digits as ones
    cross join digits as tens
    cross join digits as hundreds
    cross join digits as thousands

)

select cast({{ dbt.dateadd('day', 'n', "cast('2023-01-01' as date)") }} as date) as date_day
from numbers
where n < 365 * 7   -- 2023-01-01 through 2029-12-31