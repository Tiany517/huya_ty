#!/usr/bin/env python3
"""Independently test candidate selection rules against archived workbooks."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import pandas as pd

from compare_fanwa_versions import ROLE_PATTERNS, find_input, stable_ids


CSV_COLUMNS = [
    "mth",
    "pcode",
    "r_category",
    "r_lid",
    "kuaishou_avg_acu",
    "kuaishou_live_mins",
    "actual_days",
]


def workbook_ids(source_dir: Path, role: str) -> set[str]:
    path = find_input(source_dir, role, ROLE_PATTERNS[role])
    frame = pd.read_excel(path, sheet_name=0)
    id_column = next(column for column in ("r_lid", "lid") if column in frame.columns)
    return set(stable_ids(frame[id_column].tolist()))


def monthly_panel(path: Path) -> pd.DataFrame:
    frame = pd.read_csv(
        path,
        usecols=CSV_COLUMNS,
        dtype={"r_lid": str, "mth": str, "pcode": str, "r_category": str},
    )
    frame = frame[frame["pcode"].eq("kuaishou") & frame["r_category"].eq("王者荣耀")].copy()
    for column in ("kuaishou_avg_acu", "kuaishou_live_mins", "actual_days"):
        frame[column] = pd.to_numeric(frame[column], errors="coerce")
    frame["acu_days"] = frame["kuaishou_avg_acu"] * frame["actual_days"]
    grouped = (
        frame.groupby(["r_lid", "mth"], as_index=False)
        .agg(acu_days=("acu_days", "sum"), days=("actual_days", "sum"), live_mins=("kuaishou_live_mins", "sum"))
        .assign(month_acu=lambda data: data["acu_days"] / data["days"], daily_live=lambda data: data["live_mins"] / data["days"])
    )
    panel = grouped.pivot(index="r_lid", columns="mth", values=["month_acu", "daily_live", "days"])
    panel.columns = [f"{metric}_{month}" for metric, month in panel.columns]
    return panel.reset_index()


def comparison(predicted: set[str], actual: set[str]) -> dict[str, int]:
    return {
        "predicted": len(predicted),
        "actual": len(actual),
        "overlap": len(predicted & actual),
        "predicted_only": len(predicted - actual),
        "actual_only": len(actual - predicted),
    }


def rule_variants(frame: pd.DataFrame) -> dict[str, set[str]]:
    variants: dict[str, set[str]] = {}
    months = ("2026-05", "2026-06", "2026-07")
    complete = frame.dropna(subset=[f"month_acu_{month}" for month in months] + [f"daily_live_{month}" for month in months])
    acu = {month: complete[f"month_acu_{month}"] for month in months}
    live = {month: complete[f"daily_live_{month}"] for month in months}
    decline = (acu["2026-07"] < acu["2026-06"]) & (acu["2026-06"] < acu["2026-05"])
    first_decline = acu["2026-06"] < acu["2026-05"]
    second_decline = acu["2026-07"] < acu["2026-06"]
    any_decline = first_decline | second_decline
    endpoint_decline = acu["2026-07"] < acu["2026-05"]
    above_100 = (acu["2026-05"] > 100) & (acu["2026-06"] > 100) & (acu["2026-07"] > 100)
    live_80_chain = (live["2026-06"] / live["2026-05"] >= 0.8) & (live["2026-07"] / live["2026-06"] >= 0.8)
    live_80_endpoint = live["2026-07"] / live["2026-05"] >= 0.8
    variants["decline_5_7_live80_chain"] = set(complete.loc[decline & live_80_chain, "r_lid"])
    variants["decline_5_7_live80_endpoint"] = set(complete.loc[decline & live_80_endpoint, "r_lid"])
    endpoint_candidates = complete.loc[decline & live_80_endpoint].sort_values("month_acu_2026-05", ascending=False)
    variants["decline_5_7_live80_endpoint_top50_by_may_acu"] = set(endpoint_candidates.head(50)["r_lid"])
    variants["decline_5_7_live80_endpoint_top53_by_may_acu"] = set(endpoint_candidates.head(53)["r_lid"])
    variants["acu100_decline_5_7"] = set(complete.loc[above_100 & decline, "r_lid"])
    variants["acu100_live80_chain_no_acu_decline"] = set(complete.loc[above_100 & live_80_chain, "r_lid"])
    variants["acu100_first_decline"] = set(complete.loc[above_100 & first_decline, "r_lid"])
    variants["acu100_second_decline"] = set(complete.loc[above_100 & second_decline, "r_lid"])
    variants["acu100_any_decline"] = set(complete.loc[above_100 & any_decline, "r_lid"])
    variants["acu100_endpoint_decline"] = set(complete.loc[above_100 & endpoint_decline, "r_lid"])
    variants["acu100_decline_5_7_live80_chain"] = set(complete.loc[above_100 & decline & live_80_chain, "r_lid"])
    variants["acu100_decline_5_7_live80_endpoint"] = set(complete.loc[above_100 & decline & live_80_endpoint, "r_lid"])

    months4 = ("2026-04", "2026-05", "2026-06", "2026-07")
    required4 = [f"month_acu_{month}" for month in months4] + [f"daily_live_{month}" for month in months4]
    if not set(required4).issubset(frame.columns):
        return variants
    complete4 = frame.dropna(subset=required4)
    acu4 = {month: complete4[f"month_acu_{month}"] for month in months4}
    live4 = {month: complete4[f"daily_live_{month}"] for month in months4}
    decline4 = (acu4["2026-07"] < acu4["2026-06"]) & (acu4["2026-06"] < acu4["2026-05"]) & (acu4["2026-05"] < acu4["2026-04"])
    live_50_chain = (live4["2026-05"] / live4["2026-04"] >= 0.5) & (live4["2026-06"] / live4["2026-05"] >= 0.5) & (live4["2026-07"] / live4["2026-06"] >= 0.5)
    above_100_4 = pd.Series(True, index=complete4.index)
    for month in months4:
        above_100_4 &= acu4[month] > 100
    variants["decline_4_7_live50_chain"] = set(complete4.loc[decline4 & live_50_chain, "r_lid"])
    variants["acu100_decline_4_7_live50_chain"] = set(complete4.loc[above_100_4 & decline4 & live_50_chain, "r_lid"])
    return variants


def feature_profile(frame: pd.DataFrame, ids: set[str]) -> dict[str, object]:
    selected = frame[frame["r_lid"].isin(ids)].copy()
    profile: dict[str, object] = {"requested": len(ids), "found": int(len(selected))}
    for month in ("2026-04", "2026-05", "2026-06", "2026-07"):
        column = f"month_acu_{month}"
        if column in selected.columns:
            values = pd.to_numeric(selected[column], errors="coerce").dropna()
            profile[f"acu_{month}_min"] = round(float(values.min()), 6) if len(values) else None
            profile[f"acu_{month}_median"] = round(float(values.median()), 6) if len(values) else None
    ratios = []
    for left, right in (("2026-05", "2026-04"), ("2026-06", "2026-05"), ("2026-07", "2026-06")):
        left_column = f"daily_live_{left}"
        right_column = f"daily_live_{right}"
        if left_column in selected.columns and right_column in selected.columns:
            ratio = selected[left_column] / selected[right_column]
            ratios.extend(ratio.dropna().tolist())
    profile["minimum_adjacent_live_ratio"] = round(float(min(ratios)), 6) if ratios else None
    ratios_5_7 = []
    for left, right in (("2026-06", "2026-05"), ("2026-07", "2026-06")):
        left_column = f"daily_live_{left}"
        right_column = f"daily_live_{right}"
        if left_column in selected.columns and right_column in selected.columns:
            ratios_5_7.extend((selected[left_column] / selected[right_column]).dropna().tolist())
    profile["minimum_adjacent_live_ratio_5_7"] = round(float(min(ratios_5_7)), 6) if ratios_5_7 else None
    if all(f"month_acu_{month}" in selected.columns for month in ("2026-05", "2026-06", "2026-07")):
        may = selected["month_acu_2026-05"]
        june = selected["month_acu_2026-06"]
        july = selected["month_acu_2026-07"]
        profile["all_auc_over_100"] = int(((may > 100) & (june > 100) & (july > 100)).sum())
        profile["strict_decline_5_7"] = int(((may > june) & (june > july)).sum())
        profile["first_decline_5_6"] = int((may > june).sum())
        profile["second_decline_6_7"] = int((june > july).sum())
        profile["endpoint_decline_5_7"] = int((may > july).sum())
    return profile


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", required=True, type=Path)
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")

    v1 = monthly_panel(args.source_dir / "快手王者荣耀主播反挖数据_加上快手ACU数据_全量.csv")
    v2 = monthly_panel(args.source_dir / "快手王者荣耀主播反挖数据_加上快手ACU数据_全量_V2.csv")
    actual_sets = {role: workbook_ids(args.source_dir, role) for role in ROLE_PATTERNS}
    v1_variants = rule_variants(v1)
    report = {
        "source_panels": {"v1_unique_anchors": len(v1), "v2_unique_anchors": len(v2)},
        "v1_rules": {name: comparison(ids, actual_sets["old_5_7_conditioned"]) for name, ids in v1_variants.items()},
        "v1_rules_vs_initial": {name: comparison(ids, actual_sets["initial_5_7_model"]) for name, ids in v1_variants.items()},
        "v2_rules": {name: comparison(ids, actual_sets["v2_5_7_conditioned"]) for name, ids in rule_variants(v2).items()},
        "actual_sets": {role: len(ids) for role, ids in actual_sets.items()},
        "actual_profiles": {
            "initial_5_7_model": feature_profile(v1, actual_sets["initial_5_7_model"]),
            "old_5_7_conditioned": feature_profile(v1, actual_sets["old_5_7_conditioned"]),
            "v2_5_7_conditioned": feature_profile(v2, actual_sets["v2_5_7_conditioned"]),
            "v2_4_7_50pct": feature_profile(v2, actual_sets["v2_4_7_50pct"]),
        },
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
