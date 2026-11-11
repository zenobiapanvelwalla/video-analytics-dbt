{#
    Snowflake only: tag every query dbt runs with the model name
    (e.g. "dbt_fct_video_views"), so warehouse spend can be attributed to
    individual models in ACCOUNT_USAGE.QUERY_HISTORY.
    See snowflake/cost_monitoring.sql.
#}
{% macro set_query_tag() -%}
    {%- set new_query_tag = 'dbt_' ~ model.name -%}
    {%- set original_query_tag = get_current_query_tag() -%}
    {%- do run_query("alter session set query_tag = '{}'".format(new_query_tag)) -%}
    {{ return(original_query_tag) }}
{%- endmacro %}
