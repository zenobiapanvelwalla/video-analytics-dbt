{#- Fails for every row where the column is negative. Nulls pass. -#}
{% test is_non_negative(model, column_name) %}

select {{ column_name }}
from {{ model }}
where {{ column_name }} < 0

{% endtest %}