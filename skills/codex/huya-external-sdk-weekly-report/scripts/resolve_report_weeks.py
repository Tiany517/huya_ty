#!/usr/bin/env python3
"""Resolve the latest completed Monday-Sunday reporting window."""

from __future__ import annotations

import argparse
import datetime as dt
import json
from zoneinfo import ZoneInfo


def resolve(run_date: dt.date) -> dict[str, str]:
    current_monday = run_date - dt.timedelta(days=run_date.weekday())
    report_start = current_monday - dt.timedelta(days=7)
    report_end = report_start + dt.timedelta(days=6)
    comparison_start = report_start - dt.timedelta(days=7)
    comparison_end = report_start - dt.timedelta(days=1)

    return {
        "run_date": run_date.isoformat(),
        "report_week_start": report_start.isoformat(),
        "report_week_end": report_end.isoformat(),
        "comparison_week_start": comparison_start.isoformat(),
        "comparison_week_end": comparison_end.isoformat(),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--run-date",
        type=dt.date.fromisoformat,
        help="Execution date in YYYY-MM-DD; defaults to today in Asia/Shanghai",
    )
    parser.add_argument("--format", choices=("json", "text"), default="json")
    args = parser.parse_args()

    run_date = args.run_date or dt.datetime.now(ZoneInfo("Asia/Shanghai")).date()
    result = resolve(run_date)
    if args.format == "json":
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        for key, value in result.items():
            print(f"{key}={value}")


if __name__ == "__main__":
    main()
