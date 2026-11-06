{#- Convert a millisecond column to minutes, rounded to 2 decimal places. -#}
{% macro ms_to_minutes(column_name) -%}
    round(cast({{ column_name }} as double) / 60000.0, 2)
{%- endmacro %}