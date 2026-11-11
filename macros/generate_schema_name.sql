{#
    Production builds into clean schema names (STAGING, MARTS, ...).
    Every other target (dev, CI) prefixes with the target schema, so developers
    and CI runs never collide with each other or with prod:
        prod -> marts
        dev  -> dbt_zenobia_marts
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set default_schema = target.schema -%}
    {%- if custom_schema_name is none -%}
        {{ default_schema }}
    {%- elif target.name == 'snowflake_prod' -%}
        {{ custom_schema_name | trim }}
    {%- else -%}
        {{ default_schema }}_{{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
