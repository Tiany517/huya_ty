from __future__ import annotations

import argparse
import csv
import hashlib
import json
import shutil
import subprocess
import sys
from datetime import date, datetime
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent

REQUIRED_HEADERS = {
    "category": {
        "dt", "gameid", "game_name", "content_group", "dau", "daily_revenue",
        "daily_pay_user_cnt", "arppu", "avg_view_mins", "attribution_user_cnt",
        "live_anchor_cnt", "group_live_anchor_cnt", "total_live_anchor_cnt",
    },
    "anchor_weekly": {
        "week_start", "gameid", "game_name", "content_group", "guild_name", "luid",
        "roomid", "snick", "dau_sum", "revenue_sum", "pay_sum", "live_sum",
        "acu_sum", "acu_days", "view_sum", "view_days", "attribution_sum",
        "interaction_cnt_sum", "interaction_user_sum", "live_days",
    },
    "anchor_daily": {
        "dt", "gameid", "content_group", "guild_name", "luid", "snick", "roomid",
        "dau", "daily_revenue", "daily_pay_user_cnt", "is_live", "live_mins", "avg_acu",
        "avg_view_mins", "attribution_user_cnt", "interaction_cnt", "interaction_user_cnt",
    },
    "event": {
        "dt", "week_start", "gameid", "game_name", "content_group", "guild_name",
        "luid", "snick", "user_event_type", "revenue", "pay_user_cnt",
    },
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_csv(path: Path, required: set[str]) -> list[dict[str, str]]:
    if not path.exists() or path.stat().st_size == 0:
        raise ValueError(f"missing or empty CSV: {path}")
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        headers = set(reader.fieldnames or [])
        missing = sorted(required - headers)
        if missing:
            raise ValueError(f"{path.name} missing columns: {', '.join(missing)}")
        rows = list(reader)
    if not rows:
        raise ValueError(f"CSV has no data rows: {path}")
    return rows


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate inputs and rebuild the ecology dashboard.")
    parser.add_argument("--category-csv", type=Path, required=True)
    parser.add_argument("--anchor-weekly-csv", type=Path, required=True)
    parser.add_argument("--anchor-daily-csv", type=Path, required=True)
    parser.add_argument("--event-csv", type=Path)
    parser.add_argument("--template", type=Path, default=SCRIPT_DIR / "dashboard_template_multidim.html")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--run-name", default=datetime.now().strftime("%Y%m%d_%H%M%S"))
    parser.add_argument("--source-latest-partition")
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--smoke-test", action="store_true", help="Render the HTML in headless Chrome/Edge after validation.")
    parser.add_argument("--daily-report", action="store_true", help="Build the one-page daily anomaly report from the validated dashboard data.")
    parser.add_argument("--platform-daily-csv", type=Path, help="Required with --daily-report: official dt,platform_dau CSV.")
    return parser.parse_args()


def run(command: list[str]) -> str:
    proc = subprocess.run(
        command,
        text=True,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"command failed ({proc.returncode}): {' '.join(command)}\n"
            f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
        )
    return proc.stdout


def main() -> int:
    args = parse_args()
    if args.daily_report and not args.platform_daily_csv:
        raise SystemExit("--daily-report requires --platform-daily-csv")
    category_rows = read_csv(args.category_csv, REQUIRED_HEADERS["category"])
    weekly_rows = read_csv(args.anchor_weekly_csv, REQUIRED_HEADERS["anchor_weekly"])
    daily_rows = read_csv(args.anchor_daily_csv, REQUIRED_HEADERS["anchor_daily"])
    event_rows = None
    if args.event_csv:
        event_rows = read_csv(args.event_csv, REQUIRED_HEADERS["event"])

    week_starts = sorted({row["week_start"].strip() for row in weekly_rows if row["week_start"].strip()})
    parsed_weeks = [date.fromisoformat(value) for value in week_starts]
    if not parsed_weeks:
        raise SystemExit("anchor weekly CSV has no week_start values")
    if any(value.weekday() != 0 for value in parsed_weeks):
        raise SystemExit("all week_start values must be Mondays")
    if any((current - previous).days != 7 for previous, current in zip(parsed_weeks, parsed_weeks[1:])):
        raise SystemExit("week_start values must be consecutive 7-day intervals")

    aggregate_dates = sorted({row["dt"].strip() for row in category_rows if row["dt"].strip()})
    if not aggregate_dates:
        raise SystemExit("category CSV has no dt values")
    latest_partition = args.source_latest_partition or aggregate_dates[-1]
    date.fromisoformat(latest_partition)

    if not args.template.exists():
        raise SystemExit(f"dashboard template not found: {args.template}")

    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    data_path = output_dir / f"dashboard_data_{args.run_name}.json"
    html_path = output_dir / f"ecology_dashboard_{args.run_name}.html"
    report_path = output_dir / f"validation_report_{args.run_name}.json"
    manifest_path = output_dir / f"run_manifest_{args.run_name}.json"
    daily_html_path = output_dir / f"daily_alert_report_{args.run_name}.html"
    daily_json_path = output_dir / f"daily_alert_report_{args.run_name}.json"
    daily_md_path = output_dir / f"daily_alert_report_{args.run_name}.md"
    daily_manifest_path = output_dir / f"daily_alert_manifest_{args.run_name}.json"
    daily_smoke_path = output_dir / f"daily_alert_smoke_report_{args.run_name}.json"
    event_path = args.event_csv.resolve() if args.event_csv else output_dir / "event_user_revenue_missing.csv"

    targets = [data_path, html_path, report_path, manifest_path]
    if args.daily_report:
        targets.extend([daily_html_path, daily_json_path, daily_md_path, daily_manifest_path])
        if args.smoke_test:
            targets.append(daily_smoke_path)
    conflicts = [str(path) for path in targets if path.exists()]
    if conflicts and not args.overwrite:
        raise SystemExit("refusing to overwrite existing outputs: " + ", ".join(conflicts))

    build_data_cmd = [
        sys.executable,
        str(SCRIPT_DIR / "build_dashboard_data_multidim.py"),
        "--category-csv", str(args.category_csv.resolve()),
        "--anchor-weekly-csv", str(args.anchor_weekly_csv.resolve()),
        "--anchor-daily-csv", str(args.anchor_daily_csv.resolve()),
        "--event-csv", str(event_path),
        "--output", str(data_path),
        "--week-start", ",".join(week_starts),
        "--source-latest-partition", latest_partition,
    ]
    build_output = run(build_data_cmd)
    build_dashboard_cmd = [
        sys.executable,
        str(SCRIPT_DIR / "build_dashboard.py"),
        str(args.template.resolve()),
        str(data_path),
        str(html_path),
    ]
    dashboard_output = run(build_dashboard_cmd)
    verify_cmd = [
        sys.executable,
        str(SCRIPT_DIR / "verify_dashboard_package.py"),
        "--data", str(data_path),
        "--report", str(report_path),
    ]
    verify_output = run(verify_cmd)
    smoke_report_path = output_dir / f"browser_smoke_report_{args.run_name}.json"
    smoke_output = None
    if args.smoke_test:
        node = shutil.which("node")
        if not node:
            raise RuntimeError("--smoke-test requires Node.js on PATH")
        smoke_cmd = [
            node,
            str(SCRIPT_DIR / "smoke_test_dashboard.mjs"),
            "--html", str(html_path),
            "--report", str(smoke_report_path),
        ]
        smoke_output = json.loads(run(smoke_cmd))

    report = json.loads(report_path.read_text(encoding="utf-8"))
    daily_report = None
    daily_cmd = None
    if args.daily_report:
        daily_cmd = [
            sys.executable,
            str(SCRIPT_DIR / "build_daily_alert_report.py"),
            "--data", str(data_path),
            "--platform-daily-csv", str(args.platform_daily_csv.resolve()),
            "--validation-report", str(report_path),
            "--output-dir", str(output_dir),
            "--run-name", args.run_name,
        ]
        if args.smoke_test:
            daily_cmd.append("--smoke-test")
        if args.overwrite:
            daily_cmd.append("--overwrite")
        daily_output = run(daily_cmd)
        daily_report = json.loads(daily_json_path.read_text(encoding="utf-8"))

    combined_status = report["status"]
    if daily_report is not None and daily_report.get("status") != "passed":
        combined_status = "failed"
    manifest = {
        "runName": args.run_name,
        "status": combined_status,
        "sourceLatestPartition": latest_partition,
        "aggregateStartDate": aggregate_dates[0],
        "aggregateEndDate": aggregate_dates[-1],
        "anchorWeeks": week_starts,
        "rowCounts": {
            "categoryInput": len(category_rows),
            "anchorWeeklyInput": len(weekly_rows),
            "anchorDailyInput": len(daily_rows),
            "eventInput": len(event_rows) if event_rows is not None else 0,
        },
        "inputs": {},
        "outputs": {},
        "commands": {
            "buildData": build_data_cmd,
            "buildDashboard": build_dashboard_cmd,
            "verify": verify_cmd,
            **({"browserSmokeTest": smoke_cmd} if args.smoke_test else {}),
            **({"buildDailyReport": daily_cmd} if daily_cmd else {}),
        },
        "validation": report,
        "browserSmokeTest": smoke_output,
        **({"dailyReport": daily_report} if daily_report is not None else {}),
    }
    for label, path in {
        "categoryCsv": args.category_csv,
        "anchorWeeklyCsv": args.anchor_weekly_csv,
        "anchorDailyCsv": args.anchor_daily_csv,
        **({"eventCsv": args.event_csv} if args.event_csv else {}),
        **({"platformDailyCsv": args.platform_daily_csv} if args.platform_daily_csv else {}),
        "template": args.template,
    }.items():
        resolved = path.resolve()
        manifest["inputs"][label] = {"path": str(resolved), "bytes": resolved.stat().st_size, "sha256": sha256(resolved)}
    output_paths = {"dataJson": data_path, "dashboardHtml": html_path, "validationReport": report_path}
    if args.smoke_test and smoke_report_path.exists():
        output_paths["browserSmokeReport"] = smoke_report_path
    if args.daily_report:
        output_paths.update({
            "dailyReportHtml": daily_html_path,
            "dailyReportJson": daily_json_path,
            "dailyReportMarkdown": daily_md_path,
            "dailyReportManifest": daily_manifest_path,
        })
        if args.smoke_test and daily_smoke_path.exists():
            output_paths["dailyReportSmokeReport"] = daily_smoke_path
    for label, path in output_paths.items():
        manifest["outputs"][label] = {"path": str(path), "bytes": path.stat().st_size, "sha256": sha256(path)}
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(json.dumps({
        "status": combined_status,
        "runName": args.run_name,
        "outputDir": str(output_dir),
        "dataJson": str(data_path),
        "dashboardHtml": str(html_path),
        "validationReport": str(report_path),
        **({"browserSmokeReport": str(smoke_report_path)} if args.smoke_test else {}),
        **({"dailyReportHtml": str(daily_html_path), "dailyReportJson": str(daily_json_path)} if args.daily_report else {}),
        "runManifest": str(manifest_path),
        "validation": report["diagnostics"],
    }, ensure_ascii=False, indent=2))
    return 0 if combined_status == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
