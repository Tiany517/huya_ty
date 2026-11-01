#!/usr/bin/env python3
"""Validate the anonymized cooperation-ACU review against local source files."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

import pandas as pd
from openpyxl import load_workbook


PROJECT_ROOT = Path(__file__).resolve().parents[1]
ARTIFACT_ROOT = PROJECT_ROOT / "artifacts" / "anonymous-summary"
REPORT_PATH = PROJECT_ROOT / "validation" / "validation-report.json"

WINDOWS = {
    "pre_month": ("2026-05-24", "2026-06-23"),
    "event_week": ("2026-06-24", "2026-06-30"),
    "post_month_including_event": ("2026-06-24", "2026-07-23"),
    "post_month_excluding_event": ("2026-07-01", "2026-07-30"),
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def check(checks: list[dict[str, object]], name: str, status: str, details: str) -> None:
    checks.append({"check": name, "status": status, "details": details})


def load_sources(source_dir: Path) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    data_dir = source_dir / "data"
    anchor = pd.read_csv(data_dir / "anchor_daily.csv", encoding="utf-8-sig", dtype={"r_lid": str})
    market = pd.read_csv(data_dir / "market_daily.csv", encoding="utf-8-sig")
    market_ex = pd.read_csv(data_dir / "market_exhh_daily.csv", encoding="utf-8-sig")
    for frame in (anchor, market, market_ex):
        frame["dt"] = pd.to_datetime(frame["dt"])
    return anchor, market, market_ex


def role_map(anchor: pd.DataFrame) -> tuple[dict[str, str], list[str]]:
    totals = anchor.groupby("r_lid")["valid_acu"].sum().sort_values(ascending=False)
    ordered = list(totals.items())
    labels = {identifier: f"anchor_{index:02d}" for index, (identifier, _) in enumerate(ordered, 1)}
    return labels, [identifier for identifier, _ in ordered[1:]]


def independent_daily(
    anchor: pd.DataFrame,
    market: pd.DataFrame,
    market_ex: pd.DataFrame,
) -> tuple[pd.DataFrame, dict[str, str], list[str]]:
    labels, five = role_map(anchor)
    ids = sorted(labels, key=labels.get)
    pivot = anchor.pivot_table(index="dt", columns="r_lid", values="valid_acu", aggfunc="mean")
    benchmark = market.set_index("dt").join(market_ex.set_index("dt"), how="outer").sort_index()
    pivot = pivot.reindex(benchmark.index)
    result = pd.DataFrame(index=benchmark.index)
    result.index.name = "date"
    for identifier in ids:
        result[labels[identifier]] = pivot[identifier]
    result["collaboration_five_total"] = pivot[five].fillna(0).sum(axis=1)
    result["observed_six_total"] = pivot[ids].fillna(0).sum(axis=1)
    result["non_cohort_excluding_five"] = benchmark["acu_ex5"]
    result["non_cohort_excluding_six"] = benchmark["acu_ex6"]
    result["all_platform"] = benchmark["acu_all"]
    result["all_platform_excluding_outlier"] = benchmark["acu_ex_hh"]
    result["non_cohort_excluding_six_and_outlier"] = benchmark["acu_ex6_hh"]
    result["platform_anchor_count"] = benchmark["anchor_cnt_all"]
    result["market_reconciliation_residual"] = (
        result["all_platform"]
        - result["non_cohort_excluding_six"]
        - result["observed_six_total"]
    )
    base = result["all_platform_excluding_outlier"].where(result["all_platform_excluding_outlier"].ne(0))
    result["six_share_excluding_outlier"] = result["observed_six_total"] / base
    result["five_share_excluding_outlier"] = result["collaboration_five_total"] / base
    return result.reset_index(), labels, five


def independent_window_avg(daily: pd.DataFrame, unit: str, start: str, end: str) -> float:
    selected = daily.loc[
        daily["date"].between(pd.Timestamp(start), pd.Timestamp(end)), unit
    ]
    days = (pd.Timestamp(end) - pd.Timestamp(start)).days + 1
    return float(selected.fillna(0).sum() / days)


def validate_sources(
    source_dir: Path,
    anchor: pd.DataFrame,
    market: pd.DataFrame,
    market_ex: pd.DataFrame,
    checks: list[dict[str, object]],
) -> None:
    source_ok = (
        len(anchor) == 608
        and anchor["r_lid"].nunique() == 6
        and anchor["dt"].min() == pd.Timestamp("2026-05-01")
        and anchor["dt"].max() == pd.Timestamp("2026-08-31")
        and not anchor.duplicated(["dt", "r_lid"]).any()
    )
    check(
        checks,
        "Anchor source grain and coverage",
        "pass" if source_ok else "fail",
        f"rows={len(anchor)}, anchors={anchor['r_lid'].nunique()}, dates={anchor['dt'].nunique()}, duplicate dt+anchor={int(anchor.duplicated(['dt','r_lid']).sum())}",
    )
    market_ok = (
        len(market) == len(market_ex) == 123
        and market["dt"].is_unique
        and market_ex["dt"].is_unique
        and set(market["dt"]) == set(market_ex["dt"])
    )
    check(
        checks,
        "Market benchmark grain and date parity",
        "pass" if market_ok else "fail",
        f"market daily={len(market)}, outlier-adjusted={len(market_ex)}, common dates={len(set(market['dt']) & set(market_ex['dt']))}",
    )
    manifest = pd.read_csv(ARTIFACT_ROOT / "source-manifest.csv", encoding="utf-8-sig")
    missing: list[str] = []
    mismatched: list[str] = []
    for row in manifest.itertuples(index=False):
        source = source_dir / row.relative_path
        if not source.exists():
            missing.append(row.relative_path)
        elif sha256(source) != row.sha256:
            mismatched.append(row.relative_path)
    check(
        checks,
        "Source manifest hashes",
        "pass" if len(manifest) == 5 and not missing and not mismatched else "fail",
        f"files={len(manifest)}, missing={missing}, hash mismatches={mismatched}",
    )


def validate_independent_metrics(
    daily: pd.DataFrame,
    expected: pd.DataFrame,
    checks: list[dict[str, object]],
) -> None:
    key_columns = ["date", "collaboration_five_total", "observed_six_total"]
    left = expected[key_columns].reset_index(drop=True)
    right = daily[key_columns].reset_index(drop=True)
    max_delta = float((left[key_columns[1:]] - right[key_columns[1:]]).abs().max().max())
    check(
        checks,
        "Daily aggregate series reconciliation",
        "pass" if max_delta <= 1e-9 else "fail",
        f"123 dates compared; maximum group-total difference={max_delta:.12f}",
    )

    summary = pd.read_csv(ARTIFACT_ROOT / "window_summary.csv", encoding="utf-8-sig")
    errors: list[float] = []
    for row in summary.itertuples(index=False):
        calculated = independent_window_avg(daily, row.unit, row.start_date, row.end_date)
        errors.append(abs(float(row.natural_day_daily_avg_acu) - calculated))
    check(
        checks,
        "Independent window-average recomputation",
        "pass" if max(errors) <= 1e-8 else "fail",
        f"compared {len(summary)} unit-window rows; maximum difference={max(errors):.12f}",
    )

    growth = pd.read_csv(ARTIFACT_ROOT / "growth_comparison.csv", encoding="utf-8-sig").set_index("unit")
    six = growth.loc["observed_six_total"]
    expected_six_pre = independent_window_avg(daily, "observed_six_total", *WINDOWS["pre_month"])
    expected_six_post_inc = independent_window_avg(
        daily, "observed_six_total", *WINDOWS["post_month_including_event"]
    )
    expected_six_post_ex = independent_window_avg(
        daily, "observed_six_total", *WINDOWS["post_month_excluding_event"]
    )
    growth_ok = (
        abs(float(six["pre_daily_avg_acu"]) - expected_six_pre) <= 1e-8
        and abs(float(six["post_including_event_daily_avg_acu"]) - expected_six_post_inc) <= 1e-8
        and abs(float(six["post_excluding_event_daily_avg_acu"]) - expected_six_post_ex) <= 1e-8
    )
    check(
        checks,
        "Six-anchor growth recomputation",
        "pass" if growth_ok else "fail",
        f"pre={expected_six_pre:.4f}, post-including={expected_six_post_inc:.4f}, post-excluding={expected_six_post_ex:.4f}",
    )


def validate_original_workbook(
    source_dir: Path,
    growth: pd.DataFrame,
    checks: list[dict[str, object]],
) -> None:
    workbook_path = next((source_dir / "output").glob("*.xlsx"))
    historical = pd.read_excel(workbook_path, sheet_name=2)
    historical = historical.set_index(historical.columns[0])
    generated = growth.set_index("unit")
    comparisons: list[float] = []
    for source_label, unit in (("6人合计", "observed_six_total"), ("合作5人组", "collaboration_five_total")):
        source_row = historical.loc[source_label]
        comparisons.extend(
            [
                abs(float(source_row.iloc[3]) - float(generated.loc[unit, "post_including_event_growth"])),
                abs(float(source_row.iloc[6]) - float(generated.loc[unit, "post_excluding_event_growth"])),
            ]
        )
    check(
        checks,
        "Historical workbook growth values reproduced",
        "pass" if max(comparisons) <= 5e-5 else "fail",
        f"four group-window growth values compared; maximum difference={max(comparisons):.12f}",
    )


def validate_reconciliation(daily: pd.DataFrame, checks: list[dict[str, object]]) -> None:
    residual = daily["market_reconciliation_residual"]
    failures = residual[residual.abs() > 0.11]
    facts = {
        "failure_dates": len(failures),
        "total_residual": float(failures.sum()),
        "max_abs_residual": float(failures.abs().max()),
    }
    check(
        checks,
        "Market-derived six-person total reconciles to source anchor sum",
        "known_issue"
        if facts["failure_dates"] == 13
        and abs(facts["total_residual"] - 14548.03) < 0.02
        else "fail",
        json.dumps(facts, ensure_ascii=False, sort_keys=True),
    )
    check(
        checks,
        "Original upstream SQL retained",
        "not_run",
        "No source SQL was included in the project folder; market exclusion logic cannot be rerun from the retained materials",
    )


def validate_artifacts(checks: list[dict[str, object]]) -> None:
    expected_shapes = {
        "daily_series.csv": (123, 20),
        "window_summary.csv": (52, 9),
        "growth_comparison.csv": (13, 12),
        "share_summary.csv": (4, 5),
        "reconciliation_failures.csv": (13, 4),
    }
    for name, shape in expected_shapes.items():
        path = ARTIFACT_ROOT / name
        frame = pd.read_csv(path, encoding="utf-8-sig")
        check(
            checks,
            f"Artifact shape: {name}",
            "pass" if frame.shape == shape else "fail",
            f"actual={frame.shape}, expected={shape}",
        )
        if name not in {"reconciliation_failures.csv"}:
            chinese = pd.read_csv(ARTIFACT_ROOT / name.replace(".csv", ".zh.csv"), encoding="utf-8-sig")
            check(
                checks,
                f"Bilingual shape parity: {name}",
                "pass" if chinese.shape == frame.shape else "fail",
                f"Chinese={chinese.shape}, English={frame.shape}",
            )

    for workbook_name in ("cooperation-acu-anonymous-en.xlsx", "cooperation-acu-anonymous-zh.xlsx"):
        workbook = load_workbook(ARTIFACT_ROOT / workbook_name, read_only=True, data_only=True)
        expected_sheets = 6
        check(
            checks,
            f"Anonymous workbook structure: {workbook_name}",
            "pass" if len(workbook.sheetnames) == expected_sheets else "fail",
            f"sheets={workbook.sheetnames}",
        )
        workbook.close()


def validate_privacy(checks: list[dict[str, object]]) -> None:
    blocked_header_pattern = re.compile(r"(?i)(^|,)(r_lid|r_owner|uid|主播uid|主播昵称)(,|$)")
    blocked_value_pattern = re.compile(r"^\d{10,}$")
    violations: list[str] = []
    for suffix in ("*.csv", "*.json", "*.md", "*.py"):
        for path in PROJECT_ROOT.rglob(suffix):
            text = path.read_text(encoding="utf-8-sig", errors="ignore")
            if suffix == "*.csv" and blocked_header_pattern.search(text.splitlines()[0]):
                violations.append(f"{path.relative_to(PROJECT_ROOT)}:blocked-header")
            for cell in text.splitlines():
                for token in cell.replace(',', ' ').split():
                    if blocked_value_pattern.fullmatch(token):
                        violations.append(f"{path.relative_to(PROJECT_ROOT)}:identifier-like-value")
                        break
    for path in ARTIFACT_ROOT.glob("*.xlsx"):
        workbook = load_workbook(path, read_only=True, data_only=True)
        for sheet in workbook.worksheets:
            for row in sheet.iter_rows(values_only=True):
                if any(isinstance(value, str) and blocked_value_pattern.fullmatch(value.strip()) for value in row):
                    violations.append(f"{path.name}:{sheet.title}:identifier-like-value")
                    break
        workbook.close()
    check(
        checks,
        "No source identifiers or nicknames in retained artifacts",
        "pass" if not violations else "fail",
        "No blocked headers or 10+ digit identifier values found" if not violations else "; ".join(violations),
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path)
    parser.add_argument("--write-report", action="store_true")
    args = parser.parse_args()

    checks: list[dict[str, object]] = []
    validate_artifacts(checks)
    validate_privacy(checks)
    daily_artifact = pd.read_csv(ARTIFACT_ROOT / "daily_series.csv", encoding="utf-8-sig", parse_dates=["date"])
    growth_artifact = pd.read_csv(ARTIFACT_ROOT / "growth_comparison.csv", encoding="utf-8-sig")
    if args.source_dir:
        source_dir = args.source_dir.resolve()
        anchor, market, market_ex = load_sources(source_dir)
        validate_sources(source_dir, anchor, market, market_ex, checks)
        daily, _, _ = independent_daily(anchor, market, market_ex)
        validate_independent_metrics(daily, daily_artifact, checks)
        validate_original_workbook(source_dir, growth_artifact, checks)
        validate_reconciliation(daily, checks)
    else:
        for name in (
            "Anchor source grain and coverage",
            "Market benchmark grain and date parity",
            "Source manifest hashes",
            "Daily aggregate series reconciliation",
            "Independent window-average recomputation",
            "Six-anchor growth recomputation",
            "Historical workbook growth values reproduced",
            "Market-derived six-person total reconciles to source anchor sum",
            "Original upstream SQL retained",
        ):
            check(checks, name, "not_run", "No --source-dir was supplied")

    summary = {
        "checks": len(checks),
        "passed": sum(item["status"] == "pass" for item in checks),
        "known_issues": sum(item["status"] == "known_issue" for item in checks),
        "not_run": sum(item["status"] == "not_run" for item in checks),
        "failed": sum(item["status"] == "fail" for item in checks),
    }
    overall = (
        "failed"
        if summary["failed"]
        else "incomplete"
        if summary["not_run"]
        else "complete_with_known_issues"
    )
    report = {
        "project": "molata-cooperation-acu-review",
        "overall_status": overall,
        "summary": summary,
        "checks": checks,
    }
    output = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.write_report:
        REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
        REPORT_PATH.write_text(output, encoding="utf-8")
    print(output)
    raise SystemExit(1 if summary["failed"] else 0)


if __name__ == "__main__":
    main()
