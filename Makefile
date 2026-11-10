export DBT_PROFILES_DIR := .

.PHONY: setup data build freshness docs metrics clean all

setup:            ## Install Python dependencies
	pip install -r requirements.txt

data:             ## Generate synthetic raw data and load it into DuckDB
	python scripts/generate_data.py --out data
	python scripts/load_raw.py --target duckdb

build:            ## Build and test every model (seeds, models, tests, unit tests)
	dbt build

freshness:        ## Check source freshness
	dbt source freshness

docs:             ## Generate and serve the dbt docs site (lineage graph)
	dbt docs generate && dbt docs serve

metrics:          ## Validate the semantic layer and run a sample metric query
	mf validate-configs
	mf query --metrics total_views,playback_failure_rate,rebuffer_percentage,median_startup_time_ms --group-by view__cdn
	mf query --metrics playback_failure_rate,total_views \
         --group-by metric_time__day,view__cdn \
         --where "{{ Dimension('view__cdn') }} = 'cdn_b'" \
         --order -playback_failure_rate \
         --limit 5 # Find your incident
# 	Quality by CDN. This shows cdn_c has noticeably slower startup
	mf query --metrics total_views,playback_failure_rate,median_startup_time_ms,p95_startup_time_ms,rebuffer_percentage \
         --group-by view__cdn
# 	Is mobile verse?
	mf query --metrics total_views,playback_failure_rate,median_startup_time_ms,p95_startup_time_ms,rebuffer_percentage \
         --group-by view__cdn
# 	Failure rate by plan. MetricFlow joins video_views to customers for you through the customer entity
	mf query --metrics playback_failure_rate,total_views --group-by customer__current_plan_name
# 	Revenue by month, complete months only
	mf query --metrics revenue,overage_revenue,overage_share_of_revenue \
         --group-by metric_time__month \
         --where "{{ Dimension('customer_month__is_complete_month') }}"
# 	See the SQL MetricFlow writes. Add --explain to any query
	mf query --metrics playback_failure_rate --group-by customer__current_plan_name --explain

clean:
	dbt clean && rm -rf data logs *.duckdb

all: data build freshness metrics
