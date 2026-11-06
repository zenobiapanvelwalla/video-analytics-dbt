{#
    Turns the plan change log into a Slowly Changing Dimension (Type 2):
    one row per customer per plan period, with [valid_from, valid_to) ranges.

    valid_to is exclusive and null for the current plan, so "which plan was
    this customer on at time T?" is:
        valid_from <= T and (valid_to > T or valid_to is null)
#}

with plan_changes as (

    select * from {{ ref('stg_platform__plan_changes') }}

),

plans as (

    select * from {{ ref('plans') }}

),

periods as (

    select
        customer_id,
        plan_name,
        changed_at                                              as valid_from,
        lead(changed_at) over (
            partition by customer_id order by changed_at
        )                                                       as valid_to,
        lag(plan_name) over (
            partition by customer_id order by changed_at
        )                                                       as previous_plan_name,
        row_number() over (
            partition by customer_id order by changed_at
        )                                                       as plan_sequence
    from plan_changes

),

final as (

    select
        periods.customer_id || '-' || cast(periods.plan_sequence as varchar)
                                                                as customer_plan_key,
        periods.customer_id,
        periods.plan_sequence,
        periods.plan_name,
        periods.previous_plan_name,
        case
            when periods.previous_plan_name is null then 'new'
            when plans.plan_rank > previous_plans.plan_rank then 'upgrade'
            when plans.plan_rank < previous_plans.plan_rank then 'downgrade'
            else 'no_change'
        end                                                     as change_type,
        plans.monthly_base_fee_usd,
        plans.included_delivery_minutes,
        plans.overage_usd_per_1k_minutes,
        periods.valid_from,
        periods.valid_to,
        periods.valid_to is null                                as is_current
    from periods
    inner join plans
        on periods.plan_name = plans.plan_name
    left join plans as previous_plans
        on periods.previous_plan_name = previous_plans.plan_name

)

-- Explicit casts: Step 7 adds a contract that locks these types.
select
    cast(customer_plan_key as varchar)                  as customer_plan_key,
    cast(customer_id as varchar)                        as customer_id,
    cast(plan_sequence as integer)                      as plan_sequence,
    cast(plan_name as varchar)                          as plan_name,
    cast(previous_plan_name as varchar)                 as previous_plan_name,
    cast(change_type as varchar)                        as change_type,
    cast(monthly_base_fee_usd as decimal(18, 2))        as monthly_base_fee_usd,
    cast(included_delivery_minutes as bigint)           as included_delivery_minutes,
    cast(overage_usd_per_1k_minutes as decimal(18, 2))  as overage_usd_per_1k_minutes,
    cast(valid_from as timestamp)                       as valid_from,
    cast(valid_to as timestamp)                         as valid_to,
    cast(is_current as boolean)                         as is_current
from final