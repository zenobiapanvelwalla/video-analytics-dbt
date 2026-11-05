"""
Find the planted CDN incident in the raw data: the hours with the highest
playback failure rate for one CDN.

Hours with very few views are excluded: 1 failure out of 2 views is "50%",
but that's noise, not an incident.

This is the "answer key" for checking the semantic-layer metrics in Step 8.

Usage:
    python scripts/find_cdn_incident.py
    python scripts/find_cdn_incident.py --cdn cdn_a --top 5 --min-views 15
"""

import argparse

import duckdb


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cdn", default="cdn_b", help="CDN to inspect")
    parser.add_argument("--top", type=int, default=8, help="Number of hours to show")
    parser.add_argument("--min-views", type=int, default=10,
                        help="Ignore hours with fewer views than this")
    parser.add_argument("--db", default="framewise.duckdb", help="DuckDB file path")
    args = parser.parse_args()

    con = duckdb.connect(args.db, read_only=True)
    rows = con.execute(
        """
        select
            strftime(date_trunc('hour', cast(view_started_at as timestamp)),
                     '%a %b %d, %Y  %H:00') as hour_utc,
            count(*) as views,
            sum(case when playback_failed = 'true' then 1 else 0 end) as failed,
            round(100.0 * avg(case when playback_failed = 'true' then 1 else 0 end), 1)
                as failure_pct
        from raw_player.video_views
        where cdn = ?
        group by 1
        having count(*) >= ?
        order by failure_pct desc, views desc
        limit ?
        """,
        [args.cdn, args.min_views, args.top],
    ).fetchall()
    con.close()

    print(f"\nTop {args.top} hours by failure rate for {args.cdn} "
          f"(hours with at least {args.min_views} views):\n")
    print(f"{'Hour (UTC)':<26}{'Views':>7}{'Failed':>8}{'Failure %':>11}")
    print("-" * 52)
    for hour, views, failed, pct in rows:
        print(f"{hour:<26}{views:>7}{failed:>8}{pct:>10.1f}%")


if __name__ == "__main__":
    main()