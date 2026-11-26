"""Build reusable major-event day input from event-cycle statistics.

The unit of selection is one registered event cycle, never an individual traffic
day. This avoids treating a historic peak day as a whole event and avoids the
old top-10%-traffic rule that omitted mid-sized live events.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import statistics
from collections import defaultdict
from pathlib import Path


GAME_ID_ALIASES = {"无畏契约": "5937", "王者万象棋": "8127"}


def normalize_gameid(value: object) -> str:
    raw = str(value or "").strip()
    if not raw:
        raise ValueError("gameid is empty")
    return GAME_ID_ALIASES.get(raw, raw)


def percentile(values: list[float], probability: float) -> float:
    ordered = sorted(values)
    if not ordered:
        raise ValueError("cannot calculate a percentile from an empty sample")
    if len(ordered) == 1:
        return ordered[0]
    position = (len(ordered) - 1) * probability
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    weight = position - lower
    return ordered[lower] * (1 - weight) + ordered[upper] * weight


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def load_cycles(path: Path) -> list[dict]:
    rows = read_csv(path)
    if not rows:
        raise ValueError(f"empty event-cycle source: {path}")
    required = {"gameid", "match_id", "match_name", "observed_days", "mean_event_dau"}
    missing = required - set(rows[0])
    if missing:
        raise ValueError(f"event-cycle source missing columns: {sorted(missing)}")

    cycles: dict[tuple[str, str], dict] = {}
    for row in rows:
        gameid = normalize_gameid(row["gameid"])
        match_id = str(row["match_id"]).strip()
        key = (gameid, match_id)
        observed_days = int(float(row["observed_days"] or 0))
        mean_dau = float(row["mean_event_dau"] or 0)
        cycle = {
            "gameid": gameid,
            "match_id": match_id,
            "match_name": str(row["match_name"]).strip(),
            "mapped_start": str(row.get("mapped_start", "")).strip(),
            "mapped_end": str(row.get("mapped_end", "")).strip(),
            "observed_days": observed_days,
            "mean_event_dau": mean_dau,
        }
        if key in cycles and cycles[key] != cycle:
            raise ValueError(f"conflicting duplicate event-cycle key: {key}")
        cycles[key] = cycle
    return sorted(cycles.values(), key=lambda row: (row["gameid"], row["match_id"]))


def classify_cycles(cycles: list[dict], materiality_ratio: float = 0.05) -> list[dict]:
    """Return every cycle annotated with selected/excluded status and threshold.

    The rules are deliberately category-relative:
    - A cycle must have an observed day and positive mean associated-event DAU.
    - Its mean DAU must clear 5% of the category's largest observed event mean.
    - With at least four observed cycles, it must also clear a Tukey lower fence
      on log(mean event DAU), which removes unusually low long-tail events.
    """
    if not 0 <= materiality_ratio < 1:
        raise ValueError("materiality_ratio must be in [0, 1)")
    grouped: dict[str, list[dict]] = defaultdict(list)
    for cycle in cycles:
        grouped[cycle["gameid"]].append(dict(cycle))

    output: list[dict] = []
    for gameid, items in grouped.items():
        observed = [row for row in items if row["observed_days"] > 0 and row["mean_event_dau"] > 0]
        max_mean = max((row["mean_event_dau"] for row in observed), default=0.0)
        materiality_floor = max_mean * materiality_ratio if len(observed) >= 2 else 0.0
        tukey_fence = None
        if len(observed) >= 4:
            logs = [math.log(row["mean_event_dau"]) for row in observed]
            q1 = percentile(logs, 0.25)
            q3 = percentile(logs, 0.75)
            tukey_fence = math.exp(q1 - 1.5 * (q3 - q1))
        threshold = max(materiality_floor, tukey_fence or 0.0)

        for row in items:
            row["category_max_mean_event_dau"] = max_mean
            row["materiality_floor"] = materiality_floor
            row["tukey_lower_fence"] = tukey_fence
            row["selection_threshold"] = threshold
            observable = row["observed_days"] > 0 and row["mean_event_dau"] > 0
            selected = observable and row["mean_event_dau"] >= threshold
            row["status"] = "selected" if selected else "excluded_low_scale" if observable else "excluded_unobserved"
            if selected:
                row["reason"] = "赛事周期日均DAU达到品类相对下限"
            elif observable:
                row["reason"] = "赛事周期日均DAU低于品类相对下限"
            else:
                row["reason"] = "该赛事周期没有可观察观看日"
            output.append(row)
    return sorted(output, key=lambda row: (row["gameid"], -row["mean_event_dau"], row["match_id"]))


def load_event_days(path: Path, cycles: list[dict]) -> tuple[list[dict], dict]:
    rows = read_csv(path)
    if not rows:
        raise ValueError(f"empty event-day source: {path}")
    required = {"dt", "gameid", "match_id", "match_name"}
    missing = required - set(rows[0])
    if missing:
        raise ValueError(f"event-day source missing columns: {sorted(missing)}")
    by_key = {(row["gameid"], row["match_id"]): row for row in cycles}
    selected: list[dict] = []
    seen: set[tuple[str, str, str]] = set()
    unmatched = 0
    for row in rows:
        gameid = normalize_gameid(row["gameid"])
        match_id = str(row["match_id"]).strip()
        cycle = by_key.get((gameid, match_id))
        if not cycle:
            unmatched += 1
            continue
        if cycle["status"] != "selected":
            continue
        normalized = {
            "dt": str(row["dt"]).strip(),
            "gameid": gameid,
            "match_id": match_id,
            "match_name": cycle["match_name"] or str(row["match_name"]).strip(),
        }
        key = (normalized["dt"], gameid, match_id)
        if key in seen:
            continue
        seen.add(key)
        selected.append(normalized)
    return sorted(selected, key=lambda row: (row["dt"], row["gameid"], row["match_id"])), {
        "rawEventDayRows": len(rows),
        "selectedEventDayRows": len(selected),
        "unmatchedRawEventDayRows": unmatched,
    }


def build_metadata(cycles: list[dict], days: list[dict], source_stats: dict, materiality_ratio: float) -> dict:
    selected_days: dict[str, set[str]] = defaultdict(set)
    for row in days:
        selected_days[row["gameid"]].add(row["dt"])
    categories: dict[str, dict] = {}
    for row in cycles:
        category = categories.setdefault(
            row["gameid"],
            {
                "maxMeanEventDau": row["category_max_mean_event_dau"],
                "materialityFloor": row["materiality_floor"],
                "tukeyLowerFence": row["tukey_lower_fence"],
                "selectionThreshold": row["selection_threshold"],
                "selectedEvents": [],
                "excludedLowEvents": [],
                "excludedUnobservedEvents": [],
                "selectedDayCount": 0,
            },
        )
        event = {
            "matchId": row["match_id"],
            "matchName": row["match_name"],
            "period": f"{row['mapped_start']}—{row['mapped_end']}",
            "observedDays": row["observed_days"],
            "meanEventDau": row["mean_event_dau"],
        }
        if row["status"] == "selected":
            category["selectedEvents"].append(event)
        elif row["status"] == "excluded_low_scale":
            category["excludedLowEvents"].append(event)
        else:
            category["excludedUnobservedEvents"].append(event)
        category["selectedDayCount"] = len(selected_days[row["gameid"]])

    return {
        "rule": "按单赛事周期识别；剔除低于品类最大赛事日均5%的赛事；赛事数不少于4时叠加log日均的Tukey下限",
        "materialityRatio": materiality_ratio,
        "unit": "赛事关联主播整日覆盖DAU，APP四端，不含鸿蒙；不等同精确比赛时段DAU",
        "source": source_stats,
        "categories": categories,
        "counts": {
            "categoriesWithCycles": len(categories),
            "selectedEvents": sum(1 for row in cycles if row["status"] == "selected"),
            "excludedLowEvents": sum(1 for row in cycles if row["status"] == "excluded_low_scale"),
            "excludedUnobservedEvents": sum(1 for row in cycles if row["status"] == "excluded_unobserved"),
            "selectedDays": len(days),
        },
    }


def write_csv(path: Path, rows: list[dict], columns: list[str]) -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns)
        writer.writeheader()
        writer.writerows(rows)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(event_days: Path, event_cycles: Path, output_dir: Path, materiality_ratio: float = 0.05) -> dict:
    if output_dir.exists() and any(output_dir.iterdir()):
        raise ValueError(f"output directory must be new or empty: {output_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)
    cycles = classify_cycles(load_cycles(event_cycles), materiality_ratio)
    days, day_stats = load_event_days(event_days, cycles)
    metadata = build_metadata(
        cycles,
        days,
        {
            "eventDays": {"path": str(event_days), "sha256": sha256(event_days)},
            "eventCycles": {"path": str(event_cycles), "sha256": sha256(event_cycles)},
            **day_stats,
        },
        materiality_ratio,
    )
    write_csv(output_dir / "major_event_days.csv", days, ["dt", "gameid", "match_id", "match_name"])
    write_csv(
        output_dir / "major_event_cycles.csv",
        cycles,
        [
            "gameid", "match_id", "match_name", "mapped_start", "mapped_end", "observed_days",
            "mean_event_dau", "category_max_mean_event_dau", "materiality_floor",
            "tukey_lower_fence", "selection_threshold", "status", "reason",
        ],
    )
    (output_dir / "major_event_manifest.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return metadata


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--event-days", type=Path, required=True)
    parser.add_argument("--event-cycles", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--materiality-ratio", type=float, default=0.05)
    args = parser.parse_args()
    print(json.dumps(run(args.event_days, args.event_cycles, args.output_dir, args.materiality_ratio), ensure_ascii=False))


if __name__ == "__main__":
    main()
