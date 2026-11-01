#!/usr/bin/env python3
"""Compare candidate sets across historical Kuaishou reverse-poaching workbooks."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any
import sys

import pandas as pd


ROLE_PATTERNS = {
    "initial_5_7_model": "快手王者荣耀主播_ACU连续三个月下降且开播时长稳定_含虎牙预测*.xlsx",
    "old_5_7_columns": "快手王者荣耀主播_旧版全量_按指定列名_5-7月筛选结果.xlsx",
    "old_5_7_conditioned": "快手王者荣耀主播_筛选_ACU均大于100且连续下降且开播稳定_全量信息.xlsx",
    "v2_5_7_columns": "快手王者荣耀主播_V2_按指定列名排列_5-7月筛选结果.xlsx",
    "v2_4_7_50pct": "快手王者荣耀主播_V2筛选_4-7月ACU连续下降_开播比例50%_按指定列名.xlsx",
    "v2_5_7_conditioned": "快手王者荣耀主播_V2筛选_5-7月ACU均大于100且连续下降且开播稳定_全量信息.xlsx",
}


def find_input(source_dir: Path, role: str, pattern: str) -> Path:
    matches = sorted(source_dir.glob(pattern))
    if len(matches) != 1:
        raise ValueError(f"Expected one workbook for {role}, found {len(matches)}")
    return matches[0]


def stable_ids(values: list[Any]) -> list[str]:
    ids = [str(value).strip() for value in values if pd.notna(value) and str(value).strip()]
    return ids


def profile(source_dir: Path) -> dict[str, Any]:
    datasets: dict[str, dict[str, Any]] = {}
    id_sets: dict[str, set[str]] = {}
    for role, pattern in ROLE_PATTERNS.items():
        path = find_input(source_dir, role, pattern)
        workbook = pd.ExcelFile(path)
        candidate_sheet = workbook.sheet_names[0]
        frame = pd.read_excel(path, sheet_name=candidate_sheet)
        id_column = next(column for column in ("r_lid", "lid") if column in frame.columns)
        ids = stable_ids(frame[id_column].tolist())
        id_sets[role] = set(ids)
        condition_counts: dict[str, int] = {}
        if "是否符合条件" in frame.columns:
            condition_counts = {str(key): int(value) for key, value in frame["是否符合条件"].value_counts(dropna=False).items()}
        elif "判断" in frame.columns:
            condition_counts = {str(key): int(value) for key, value in frame["判断"].value_counts(dropna=False).items()}
        datasets[role] = {
            "file": path.name,
            "bytes": path.stat().st_size,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest().upper(),
            "candidate_sheet": candidate_sheet,
            "data_rows": int(len(frame)),
            "unique_ids": int(len(id_sets[role])),
            "duplicate_id_rows": int(len(ids) - len(id_sets[role])),
            "condition_counts": condition_counts,
        }

    transitions = []
    ordered_roles = list(ROLE_PATTERNS)
    for left, right in zip(ordered_roles, ordered_roles[1:]):
        left_ids = id_sets[left]
        right_ids = id_sets[right]
        transitions.append(
            {
                "from": left,
                "to": right,
                "overlap": len(left_ids & right_ids),
                "dropped": len(left_ids - right_ids),
                "added": len(right_ids - left_ids),
            }
        )
    all_pairs = []
    for position, left in enumerate(ordered_roles):
        for right in ordered_roles[position + 1 :]:
            all_pairs.append(
                {
                    "left": left,
                    "right": right,
                    "overlap": len(id_sets[left] & id_sets[right]),
                    "left_only": len(id_sets[left] - id_sets[right]),
                    "right_only": len(id_sets[right] - id_sets[left]),
                }
            )
    return {"datasets": datasets, "adjacent_transitions": transitions, "pairwise_overlap": all_pairs}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", required=True, type=Path)
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")
    print(json.dumps(profile(args.source_dir), ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
