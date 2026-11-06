{#- Fails for values that are not exactly two upper-case characters (e.g. ISO country codes). -#}
{% test is_two_letter_upper_code(model, column_name) %}

select {{ column_name }}
from {{ model }}
where {{ column_name }} is not null
  and (length({{ column_name }}) != 2 or {{ column_name }} != upper({{ column_name }}))

{% endtest %}