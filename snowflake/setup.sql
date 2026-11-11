-- =============================================================================
-- Snowflake account setup for the Framewise analytics stack
-- Run once as ACCOUNTADMIN (or SECURITYADMIN + SYSADMIN for the relevant parts).
--
-- Design:
--   RAW        database  - landed data, written only by LOADER
--   ANALYTICS  database  - dbt output, written only by TRANSFORMER
--   REPORTER   role      - read-only on ANALYTICS.MARTS (BI tools, AI agents)
--   Separate warehouses per workload so cost is attributable and isolated.
-- =============================================================================

use role sysadmin;

-- Warehouses: XS, aggressive auto-suspend, so idle time costs nothing.
create warehouse if not exists loading_wh
  warehouse_size = xsmall auto_suspend = 60 auto_resume = true initially_suspended = true
  comment = 'Ingestion (Fivetran / load scripts)';

create warehouse if not exists transforming_wh
  warehouse_size = xsmall auto_suspend = 60 auto_resume = true initially_suspended = true
  comment = 'dbt runs (dev, CI, prod)';

create warehouse if not exists reporting_wh
  warehouse_size = xsmall auto_suspend = 60 auto_resume = true initially_suspended = true
  comment = 'BI tools and semantic-layer / agent queries';

create database if not exists raw;
create schema if not exists raw.platform;
create schema if not exists raw.player;

create database if not exists analytics;

-- -----------------------------------------------------------------------------
-- Roles
-- -----------------------------------------------------------------------------
use role securityadmin;

create role if not exists loader;
create role if not exists transformer;
create role if not exists reporter;

grant role loader      to role sysadmin;
grant role transformer to role sysadmin;
grant role reporter    to role sysadmin;

-- LOADER: owns raw data
grant usage on warehouse loading_wh to role loader;
grant usage on database raw to role loader;
grant usage, create table, create stage on all schemas in database raw to role loader;
grant usage, create table, create stage on future schemas in database raw to role loader;

-- TRANSFORMER: reads raw, builds analytics
grant usage on warehouse transforming_wh to role transformer;
grant usage on database raw to role transformer;
grant usage on all schemas in database raw to role transformer;
grant usage on future schemas in database raw to role transformer;
grant select on all tables in database raw to role transformer;
grant select on future tables in database raw to role transformer;
grant usage, create schema on database analytics to role transformer;

-- REPORTER: read-only on curated marts. dbt grants (see dbt_project.yml) keep
-- these in sync on every run, so new models are covered automatically.
grant usage on warehouse reporting_wh to role reporter;
grant usage on database analytics to role reporter;

-- Example users (replace names / use key-pair auth in real life)
-- create user dbt_ci   default_role = transformer default_warehouse = transforming_wh ...;
-- grant role transformer to user dbt_ci;

-- -----------------------------------------------------------------------------
-- Cost guardrails
-- -----------------------------------------------------------------------------
use role accountadmin;

create resource monitor if not exists monthly_credit_cap
  with credit_quota = 20
  frequency = monthly
  start_timestamp = immediately
  triggers
    on 75 percent do notify
    on 100 percent do suspend
    on 110 percent do suspend_immediate;

alter warehouse loading_wh      set resource_monitor = monthly_credit_cap;
alter warehouse transforming_wh set resource_monitor = monthly_credit_cap;
alter warehouse reporting_wh    set resource_monitor = monthly_credit_cap;

-- Kill runaway queries (e.g. a bad cross join in dev) after 30 minutes.
alter warehouse transforming_wh set statement_timeout_in_seconds = 1800;

-- -----------------------------------------------------------------------------
-- Reporter needs USAGE on the schemas dbt creates (dbt's grants cover tables only)
-- -----------------------------------------------------------------------------
use role securityadmin;
grant usage on future schemas in database analytics to role reporter;

-- -----------------------------------------------------------------------------
-- Service user for dbt and the loader: key-pair auth only, no password
-- -----------------------------------------------------------------------------
create user if not exists dbt_service
  type = service
  default_role = transformer
  default_warehouse = transforming_wh
  rsa_public_key = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEArbzgTHa2SQ6e1pTNf81PGq37kTnQvDv/mVEcbeOm/NumfS2RX9XKoSnm94hxvUDCKOIR/aCS+iakvac45tEOSeSimla6qhzU0AwaQtB5TGRAnlvWfPrqXhaVE0EczTRgl8xH+g+4EzadUSQ/7lAqv+VFxZCQmrSdByXmMSmEbpXEFrFOK65ZBEheZXn94NuwG3phStXhBITN/0v/gf1UAkRXQxpUiY6wmWcLnYSUpFSkj5ZaKZi2AhKS5zXT0/qkXcnnY5o7TvQRUcPRdfjjCT+kYjeK7lDfzhQ0khePePn80wgB9ZzxM+O981cCnaUhf9YCO9whpYK7eGJ69MmEpwIDAQAB'
  comment = 'dbt runs and raw data loads';

grant role loader      to user dbt_service;
grant role transformer to user dbt_service;
