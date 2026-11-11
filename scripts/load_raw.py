"""
Load generated CSVs into the warehouse's RAW layer, the way a managed ingestion
tool (Fivetran / Airbyte) would: every column lands as a string, and dbt's
staging layer is responsible for casting and cleaning.

Targets:
  duckdb     -> local file (default: framewise.duckdb), schema "raw"
  snowflake  -> RAW.PLATFORM / RAW.PLAYER schemas (run snowflake/setup.sql first)

Usage:
    python scripts/load_raw.py --target duckdb
    python scripts/load_raw.py --target snowflake     # reads SNOWFLAKE_* env vars
"""

from __future__ import annotations

import argparse
import csv
import os
from pathlib import Path

# table name -> (source schema, csv file)
TABLES = {
    "customers": ("platform", "customers.csv"),
    "plan_changes": ("platform", "plan_changes.csv"),
    "video_assets": ("platform", "video_assets.csv"),
    "video_views": ("player", "video_views.csv"),
}


def header(path: Path) -> list[str]:
    with path.open() as f:
        return next(csv.reader(f))


def load_duckdb(data_dir: Path, db_path: str) -> None:
    import duckdb

    con = duckdb.connect(db_path)
    for table, (schema, file) in TABLES.items():
        path = data_dir / file
        raw_schema = f"raw_{schema}"
        con.execute(f"create schema if not exists {raw_schema}")
        con.execute(
            f"create or replace table {raw_schema}.{table} as "
            f"select * from read_csv('{path.as_posix()}', header=true, all_varchar=true)"
        )
        n = con.execute(f"select count(*) from {raw_schema}.{table}").fetchone()[0]
        print(f"  {raw_schema}.{table:<14} {n:>9,} rows")
    con.close()


def load_snowflake(data_dir: Path) -> None:
    import snowflake.connector

    con = snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        private_key_file=os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"],
        role=os.environ.get("SNOWFLAKE_LOADER_ROLE", "LOADER"),
        warehouse=os.environ.get("SNOWFLAKE_LOADER_WAREHOUSE", "LOADING_WH"),
        database="RAW",
    )
    cur = con.cursor()
    try:
        for table, (schema, file) in TABLES.items():
            path = (data_dir / file).resolve()
            cols = ", ".join(f"{c} varchar" for c in header(path))
            fq = f"RAW.{schema.upper()}.{table.upper()}"
            cur.execute(f"create or replace table {fq} ({cols})")
            # Table stages (@%TABLE) resolve against the current schema.
            cur.execute(f"use schema RAW.{schema.upper()}")
            cur.execute(f"put 'file://{path.as_posix()}' @%{table.upper()} overwrite = true")
            cur.execute(
                f"copy into {fq} from @%{table.upper()} "
                "file_format = (type = csv skip_header = 1 field_optionally_enclosed_by = '\"' "
                "empty_field_as_null = true) purge = true"
            )
            n = cur.execute(f"select count(*) from {fq}").fetchone()[0]
            print(f"  {fq:<28} {n:>9,} rows")
    finally:
        cur.close()
        con.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", choices=["duckdb", "snowflake"], default="duckdb")
    parser.add_argument("--data-dir", type=Path, default=Path("data"))
    parser.add_argument("--duckdb-path", default=os.environ.get("DUCKDB_PATH", "framewise.duckdb"))
    args = parser.parse_args()

    if args.target == "duckdb":
        load_duckdb(args.data_dir, args.duckdb_path)
    else:
        load_snowflake(args.data_dir)


if __name__ == "__main__":
    main()
