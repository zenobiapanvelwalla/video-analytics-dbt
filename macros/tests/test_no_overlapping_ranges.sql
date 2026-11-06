{#-
    For SCD Type 2 tables: within each partition, validity ranges must not overlap.
    valid_to is exclusive; a null valid_to means "current".
-#}
{% test no_overlapping_ranges(model, partition_by, lower_bound, upper_bound) %}

with ranges as (
    select
        {{ partition_by }} as partition_key,
        {{ lower_bound }} as lower_bound,
        {{ upper_bound }} as upper_bound,
        lead({{ lower_bound }}) over (
            partition by {{ partition_by }} order by {{ lower_bound }}
        ) as next_lower_bound
    from {{ model }}
)

select *
from ranges
where next_lower_bound is not null
  and (upper_bound is null or upper_bound > next_lower_bound)

{% endtest %}