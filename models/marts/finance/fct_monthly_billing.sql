{#
    Grain: one row per customer per calendar month, from the customer's signup
    month (or the start of usage data, whichever is later) through the current month.
    Customers with zero usage still appear, because they still pay the base fee.

    Billing rules (simplified):
      - Plan = the plan in effect at the end of the month (no proration).
      - base fee + overage on delivered minutes above the plan's included minutes.
#}

with usage as (

    select * from {{ ref('fct_daily_customer_usage') }}

),

customers as (

    select customer_id, signed_up_at from {{ ref('dim_customers') }}

),

plan_history as (

    select * from {{ ref('dim_customer_plan_history') }}

),

data_window as (

    select
        min(usage_date) as first_usage_date,
        {{ dbt.date_trunc('month', 'max(usage_date)') }} as last_month_start
    from usage

),

months as (

    select distinct cast({{ dbt.date_trunc('month', 'date_day') }} as date) as billing_month
    from {{ ref('metricflow_time_spine') }}
    cross join data_window
    where date_day >= cast({{ dbt.date_trunc('month', 'data_window.first_usage_date') }} as date)
      and date_day <= cast(data_window.last_month_start as date)

),

customer_months as (

    select
        customers.customer_id,
        months.billing_month,
        cast({{ dbt.dateadd('month', 1, 'months.billing_month') }} as timestamp) as next_month_start
    from customers
    cross join months
    where customers.signed_up_at < cast({{ dbt.dateadd('month', 1, 'months.billing_month') }} as timestamp)

),

monthly_usage as (

    select
        customer_id,
        cast({{ dbt.date_trunc('month', 'usage_date') }} as date)  as billing_month,
        sum(view_count)                                             as view_count,
        sum(delivered_minutes)                                      as delivered_minutes
    from usage
    group by 1, 2

),

priced as (

    select
        customer_months.customer_id,
        customer_months.billing_month,
        plan_history.plan_name,
        coalesce(monthly_usage.view_count, 0)                       as view_count,
        coalesce(monthly_usage.delivered_minutes, 0)                as delivered_minutes,
        plan_history.included_delivery_minutes,
        plan_history.monthly_base_fee_usd                           as base_fee_usd,
        plan_history.overage_usd_per_1k_minutes,
        case
            when coalesce(monthly_usage.delivered_minutes, 0) > plan_history.included_delivery_minutes
            then coalesce(monthly_usage.delivered_minutes, 0) - plan_history.included_delivery_minutes
            else 0
        end                                                         as overage_minutes,
        customer_months.next_month_start
    from customer_months
    -- plan in effect at the end of the month
    inner join plan_history
        on customer_months.customer_id = plan_history.customer_id
        and plan_history.valid_from < customer_months.next_month_start
        and (
            plan_history.valid_to >= customer_months.next_month_start
            or plan_history.valid_to is null
        )
    left join monthly_usage
        on customer_months.customer_id = monthly_usage.customer_id
        and customer_months.billing_month = monthly_usage.billing_month

),

final as (

    select
        priced.*,
        round(overage_minutes / 1000.0 * overage_usd_per_1k_minutes, 2) as overage_fee_usd
    from priced

)

select
    cast(final.customer_id || '-' || cast(final.billing_month as varchar) as varchar)
                                                            as customer_month_key,
    cast(final.customer_id as varchar)                      as customer_id,
    cast(final.billing_month as date)                       as billing_month,
    cast(final.plan_name as varchar)                        as plan_name,
    cast(final.view_count as bigint)                        as view_count,
    cast(final.delivered_minutes as decimal(18, 2))         as delivered_minutes,
    cast(final.included_delivery_minutes as bigint)         as included_delivery_minutes,
    cast(final.overage_minutes as decimal(18, 2))           as overage_minutes,
    cast(final.base_fee_usd as decimal(18, 2))              as base_fee_usd,
    cast(final.overage_fee_usd as decimal(18, 2))           as overage_fee_usd,
    cast(final.base_fee_usd + final.overage_fee_usd as decimal(18, 2))
                                                            as total_billed_usd,
    -- A month is reportable once it has closed AND is fully inside the data window.
    cast(
        final.next_month_start <= {{ dbt.current_timestamp() }}
        and final.billing_month >= data_window.first_usage_date
        as boolean
    )                                                       as is_complete_month
from final
cross join data_window