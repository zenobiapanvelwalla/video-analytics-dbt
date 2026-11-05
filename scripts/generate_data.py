"""
Generate synthetic raw data for "Framewise", a fictional video API company.

Produces CSVs that mimic what lands in a warehouse from:
  - the production app database (customers, plan changes, video assets)
  - the player SDK event pipeline (video views / playback sessions)

The data intentionally contains real-world mess so the dbt staging layer
has something to clean up:
  - duplicate view rows (at-least-once delivery, re-sent with a later _loaded_at)
  - late-arriving events (loaded up to 2 days after the view ended)
  - inconsistent casing in country codes
  - missing device types
  - a CDN incident window with elevated playback failures

Usage:
    python scripts/generate_data.py --views 200000 --out data/
"""

from __future__ import annotations

import argparse
import csv
import math
import random
from datetime import datetime, timedelta, timezone
from itertools import accumulate
from pathlib import Path

PLANS = ["starter", "growth", "scale", "enterprise"]
INDUSTRIES = ["edtech", "media", "fitness", "creator_tools", "ecommerce", "fintech", "healthcare"]
REGIONS = ["NA", "EMEA", "APAC", "LATAM"]
DEVICES = [("desktop", 0.42), ("mobile", 0.38), ("tablet", 0.08), ("tv", 0.12)]
BROWSERS = {
    "desktop": [("chrome", 0.65), ("safari", 0.15), ("firefox", 0.1), ("edge", 0.1)],
    "mobile": [("ios_app", 0.45), ("android_app", 0.35), ("mobile_safari", 0.12), ("chrome_mobile", 0.08)],
    "tablet": [("ios_app", 0.6), ("android_app", 0.4)],
    "tv": [("roku", 0.4), ("apple_tv", 0.3), ("android_tv", 0.3)],
}
COUNTRIES = [("US", 0.38), ("GB", 0.09), ("DE", 0.07), ("IN", 0.1), ("BR", 0.07),
             ("CA", 0.06), ("FR", 0.05), ("JP", 0.05), ("AU", 0.04), ("MX", 0.04), ("NG", 0.05)]
CDNS = [("cdn_a", 0.5), ("cdn_b", 0.35), ("cdn_c", 0.15)]
RESOLUTIONS = [("720p", 0.25), ("1080p", 0.55), ("1440p", 0.05), ("2160p", 0.15)]
ERROR_CODES = ["MEDIA_ERR_NETWORK", "MEDIA_ERR_DECODE", "MANIFEST_LOAD_ERROR", "DRM_LICENSE_ERROR"]

TS_FMT = "%Y-%m-%d %H:%M:%S"


def pick(rng: random.Random, weighted: list[tuple[str, float]]) -> str:
    values, weights = zip(*weighted)
    return rng.choices(values, weights=weights, k=1)[0]


def ts(dt: datetime) -> str:
    return dt.strftime(TS_FMT)


def write_csv(path: Path, header: list[str], rows: list[list]) -> None:
    with path.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)
    print(f"  wrote {len(rows):>8,} rows -> {path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--customers", type=int, default=150)
    parser.add_argument("--assets", type=int, default=3000)
    parser.add_argument("--views", type=int, default=200_000)
    parser.add_argument("--days", type=int, default=180)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--out", type=Path, default=Path("data"))
    args = parser.parse_args()

    rng = random.Random(args.seed)
    args.out.mkdir(parents=True, exist_ok=True)

    # Window ends "now" so source freshness checks behave like production.
    end = datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)
    start = end - timedelta(days=args.days)

    # ---------------------------------------------------------------- customers
    # Customer size follows a heavy-tailed distribution; plan tier tracks size.
    customers = []
    sizes = sorted((rng.paretovariate(1.2) for _ in range(args.customers)), reverse=True)
    for i, size in enumerate(sizes):
        cid = f"cus_{i + 1:05d}"
        # ~70% signed up before the window, the rest during it
        if rng.random() < 0.7:
            signup = start - timedelta(days=rng.randint(1, 900))
        else:
            signup = start + timedelta(days=rng.randint(0, args.days - 14))
        signup += timedelta(seconds=rng.randint(0, 86_399))
        customers.append({
            "customer_id": cid,
            "company_name": f"Customer {i + 1:05d} Inc",
            "industry": rng.choice(INDUSTRIES),
            "region": pick(rng, [(r, w) for r, w in zip(REGIONS, [0.5, 0.3, 0.15, 0.05])]),
            "signup_at": signup,
            "size": size,
        })

    # ------------------------------------------------------------ plan changes
    # Initial plan by size rank, then 0-2 later changes (mostly upgrades).
    plan_rows = []
    pc_id = 0
    n = len(customers)
    for rank, c in enumerate(customers):
        pct = rank / n
        tier = 3 if pct < 0.04 else 2 if pct < 0.15 else 1 if pct < 0.45 else 0
        tier = max(0, tier - (1 if rng.random() < 0.3 else 0))  # some start lower and upgrade
        t = c["signup_at"]
        pc_id += 1
        plan_rows.append([f"pc_{pc_id:06d}", c["customer_id"], PLANS[tier], ts(t)])
        for _ in range(rng.choice([0, 0, 1, 1, 2])):
            t = t + timedelta(days=rng.randint(20, 200), seconds=rng.randint(0, 86_399))
            if t >= end:
                break
            tier = min(3, tier + 1) if rng.random() < 0.8 else max(0, tier - 1)
            pc_id += 1
            plan_rows.append([f"pc_{pc_id:06d}", c["customer_id"], PLANS[tier], ts(t)])
        c["current_tier"] = tier

    write_csv(args.out / "plan_changes.csv",
              ["plan_change_id", "customer_id", "plan_name", "changed_at"], plan_rows)

    write_csv(args.out / "customers.csv",
              ["customer_id", "company_name", "industry", "region", "signup_at", "_loaded_at"],
              [[c["customer_id"], c["company_name"], c["industry"], c["region"],
                ts(c["signup_at"]), ts(end - timedelta(minutes=rng.randint(5, 120)))]
               for c in customers])

    # ------------------------------------------------------------------ assets
    weights = [c["size"] for c in customers]
    assets = []
    for i in range(args.assets):
        c = rng.choices(customers, weights=weights, k=1)[0]
        created_from = max(c["signup_at"], start - timedelta(days=365))
        span = max(1, int((end - created_from).total_seconds()) - 3600)
        created = created_from + timedelta(seconds=rng.randint(0, span))
        status = "errored" if rng.random() < 0.02 else "ready"
        deleted = created + timedelta(days=rng.randint(1, 120)) if rng.random() < 0.05 else None
        if deleted and deleted > end:
            deleted = None
        duration = int(min(7200, max(15, rng.lognormvariate(math.log(420), 0.9))))
        assets.append({
            "asset_id": f"ast_{i + 1:06d}",
            "customer_id": c["customer_id"],
            "created_at": created,
            "duration_seconds": duration if status == "ready" else None,
            "max_resolution": pick(rng, RESOLUTIONS) if status == "ready" else None,
            "status": status,
            "deleted_at": deleted,
        })

    write_csv(args.out / "video_assets.csv",
              ["asset_id", "customer_id", "created_at", "duration_seconds",
               "max_resolution", "status", "deleted_at", "_loaded_at"],
              [[a["asset_id"], a["customer_id"], ts(a["created_at"]), a["duration_seconds"],
                a["max_resolution"], a["status"], ts(a["deleted_at"]) if a["deleted_at"] else "",
                ts(end - timedelta(minutes=rng.randint(5, 120)))]
               for a in assets])

    # ------------------------------------------------------------------- views
    playable = [a for a in assets if a["status"] == "ready"]
    asset_weights = [next(c["size"] for c in customers if c["customer_id"] == a["customer_id"]) ** 0.8
                     * rng.random() for a in playable]

    # A 6-hour CDN incident ~3 weeks ago: cdn_b failures spike.
    incident_start = end - timedelta(days=21, hours=rng.randint(0, 23))
    incident_end = incident_start + timedelta(hours=6)

    asset_cum = list(accumulate(asset_weights))  # precompute: choices() with cum_weights is O(log n)
    view_rows = []
    for i in range(args.views):
        a = rng.choices(playable, cum_weights=asset_cum, k=1)[0]
        lo = max(a["created_at"], start)
        hi = min(a["deleted_at"] or end, end)
        if hi <= lo:
            continue
        started = lo + timedelta(seconds=rng.randint(0, int((hi - lo).total_seconds())))

        device = pick(rng, DEVICES)
        browser = pick(rng, BROWSERS[device])
        country = pick(rng, COUNTRIES)
        cdn = pick(rng, CDNS)

        fail_p = 0.012 + (0.01 if device == "tv" else 0)
        if cdn == "cdn_b" and incident_start <= started < incident_end:
            fail_p = 0.35
        failed = rng.random() < fail_p

        if failed:
            startup_ms = None
            watch_ms = 0
            rebuf_n, rebuf_ms = 0, 0
            error = rng.choice(ERROR_CODES)
        else:
            base = 850 * (1.35 if device == "mobile" else 1.0) * (1.25 if cdn == "cdn_c" else 1.0)
            startup_ms = int(min(30_000, rng.lognormvariate(math.log(base), 0.55)))
            completion = min(1.0, rng.betavariate(1.2, 1.8) * 1.3)
            watch_ms = int(a["duration_seconds"] * 1000 * completion)
            lam = 0.25 * (2.0 if device == "mobile" else 1.0) * (1.6 if cdn == "cdn_c" else 1.0) \
                * (watch_ms / 300_000)
            rebuf_n = sum(1 for _ in range(10) if rng.random() < lam / 10)
            rebuf_ms = min(int(sum(rng.expovariate(1 / 1500) for _ in range(rebuf_n))),
                           max(0, watch_ms // 2))
            error = ""

        ended = started + timedelta(milliseconds=(startup_ms or 3000) + watch_ms + rebuf_ms)
        delay = timedelta(days=rng.uniform(1, 2)) if rng.random() < 0.005 \
            else timedelta(minutes=rng.uniform(1, 30))
        loaded = min(ended + delay, end)
        if ended > end:
            continue

        row = [
            f"view_{i + 1:08d}", a["customer_id"], a["asset_id"], f"viewer_{rng.randint(1, 60_000):06d}",
            ts(started), ts(ended), watch_ms, startup_ms if startup_ms is not None else "",
            rebuf_n, rebuf_ms, str(failed).lower(), error,
            "" if rng.random() < 0.01 else device, browser,
            country.lower() if rng.random() < 0.03 else country,
            cdn, ts(loaded),
        ]
        view_rows.append(row)

        # At-least-once delivery: ~0.5% of events are re-sent later.
        if rng.random() < 0.005:
            dup = list(row)
            dup[-1] = ts(min(loaded + timedelta(minutes=rng.randint(1, 90)), end))
            view_rows.append(dup)

    rng.shuffle(view_rows)
    write_csv(args.out / "video_views.csv",
              ["view_id", "customer_id", "asset_id", "viewer_id", "view_started_at", "view_ended_at",
               "watch_time_ms", "startup_time_ms", "rebuffer_count", "rebuffer_duration_ms",
               "playback_failed", "error_code", "device_type", "browser", "country", "cdn", "_loaded_at"],
              view_rows)

    print(f"\nCDN incident window (cdn_b): {ts(incident_start)} -> {ts(incident_end)}")


if __name__ == "__main__":
    main()
