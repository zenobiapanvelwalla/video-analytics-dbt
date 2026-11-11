{#
    Restrict large models to recent data when building in a personal Snowflake
    dev schema. Keeps dev runs fast and warehouse spend low; prod and CI are
    unaffected.

    Usage (inside a WHERE clause):
        where true {{ limit_data_in_dev('view_started_at') }}
#}
{% macro limit_data_in_dev(column_name, days=var('dev_lookback_days')) -%}
    {%- if target.name == 'snowflake_dev' -%}
        and {{ column_name }} >= {{ dbt.dateadd('day', -1 * days, dbt.current_timestamp()) }}
    {%- endif -%}
{%- endmacro %}
