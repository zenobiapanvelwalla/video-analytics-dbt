"""
Simulate two real-world pipeline events in the raw data, to verify that the
incremental fct_video_views handles them:

  1. A brand-new view that arrives late.
  2. A corrected re-send of an existing view (same view_id, new watch time).

After running this, `dbt build --select fct_video_views+` should:
  - insert the late view,
  - replace the corrected view (still exactly one row for that view_id).
"""

from datetime import datetime, timezone

import duckdb

con = duckdb.connect("framewise.duckdb")
now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")

columns = """customer_id, asset_id, viewer_id, view_started_at, view_ended_at,
             {watch}, startup_time_ms, rebuffer_count, rebuffer_duration_ms,
             playback_failed, error_code, device_type, browser, country, cdn"""

# 1. A late-arriving new view: copy an existing row under a new id.
con.execute(
    f"""insert into raw_player.video_views
        select 'view_late_0001', {columns.format(watch='watch_time_ms')}, ?
        from raw_player.video_views limit 1""",
    [now],
)

# 2. A corrected re-send of an existing view: same id, watch time changed.
corrected_id = con.execute("select min(view_id) from raw_player.video_views").fetchone()[0]
con.execute(
    f"""insert into raw_player.video_views
        select view_id, {columns.format(watch="'123456'")}, ?
        from raw_player.video_views where view_id = ? limit 1""",
    [now, corrected_id],
)

con.close()
print("Inserted late view:      view_late_0001")
print(f"Re-sent corrected view:  {corrected_id} (watch_time_ms -> 123456)")