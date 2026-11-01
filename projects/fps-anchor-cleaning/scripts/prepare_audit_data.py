from __future__ import annotations

import csv
import hashlib
import json
import math
import re
from collections import Counter
from pathlib import Path

from explore_rules import CLUB_ALIASES, EVENT_TERMS, INPUT_PATH


PROJECT_DIR = Path(r"C:\Users\tiany\Desktop\FPS主播清洗_20261023")
OUTPUT_DIR = PROJECT_DIR / "outputs"
PLACEHOLDER_TERMS = ["我是一颗小虎牙"]
ORIGINAL_FIELDS = [
    "luid",
    "snick",
    "main_game_id",
    "main_game_name",
    "avg_daily_live_minutes",
]


def read_rows(path: Path) -> tuple[list[dict[str, object]], list[str]]:
    rows: list[dict[str, object]] = []
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.reader(handle)
        header = next(reader)
        for source_line, values in enumerate(reader, start=2):
            values = (values + [""] * 12)[:12]
            rows.append(
                {
                    "luid": values[0],
                    "snick": values[1],
                    "main_game_id": values[2],
                    "main_game_name": values[3],
                    "avg_daily_live_minutes": values[4],
                    "source_line": source_line,
                }
            )
    return rows, header


def compile_club_rules() -> list[dict[str, str]]:
    rules: list[dict[str, str]] = []
    for club_name, aliases in CLUB_ALIASES.items():
        for alias in aliases:
            if re.fullmatch(r"[A-Za-z0-9]{3,}", alias):
                pattern = rf"(?<![A-Za-z0-9]){re.escape(alias)}(?![A-Za-z0-9])"
                mode = "完整英文/数字代码，按词边界匹配"
                flags = 0
            elif re.fullmatch(r"[A-Z0-9]{1,2}", alias):
                if alias == "AG":
                    pattern = r"^AG"
                    mode = "AG 开头（All Gamers 常用账号前缀）"
                elif alias in {"WE", "IG", "TE", "AQ", "AT"}:
                    pattern = (
                        rf"^{re.escape(alias)}(?:$|[\u4e00-\u9fff]|"
                        r"[\s\-_.·・|丨/\\、，,])"
                    )
                    mode = "开头大写代码 + 中文或分隔符"
                else:
                    pattern = (
                        rf"^{re.escape(alias)}(?:$|[\s\-_.·・|丨/\\、，,])"
                    )
                    mode = "开头大写代码 + 分隔符"
                flags = 0
            else:
                pattern = re.escape(alias)
                mode = "俱乐部全称/中文名子串匹配"
                flags = re.IGNORECASE
            rules.append(
                {
                    "club_name": club_name,
                    "club_hit_term": alias,
                    "match_mode": mode,
                    "pattern": pattern,
                    "flags": str(int(flags)),
                }
            )
    return rules


CLUB_RULES = compile_club_rules()


def quantile(values: list[float], p: float) -> float:
    """Excel QUARTILE.INC / linear interpolation at (n-1)*p."""
    if not values:
        raise ValueError("empty array")
    pos = (len(values) - 1) * p
    lo = math.floor(pos)
    hi = min(lo + 1, len(values) - 1)
    frac = pos - lo
    return values[lo] * (1 - frac) + values[hi] * frac


def add_reason(existing: str, reason: str) -> str:
    return f"{existing}|{reason}" if existing else reason


def write_csv(path: Path, rows: list[dict[str, object]], fields: list[str]) -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    rows, header = read_rows(INPUT_PATH)
    source_hash = hashlib.sha256(INPUT_PATH.read_bytes()).hexdigest()

    event_terms_cf = [(term, term.casefold()) for term in EVENT_TERMS]
    placeholder_terms_cf = [(term, term.casefold()) for term in PLACEHOLDER_TERMS]
    compiled_clubs = [
        {**rule, "regex": re.compile(rule["pattern"], int(rule["flags"]))}
        for rule in CLUB_RULES
    ]

    for row in rows:
        name = str(row["snick"]).strip()
        row["name_for_match"] = name

        event_hits = [term for term, term_cf in event_terms_cf if term_cf in name.casefold()]
        event_hits = sorted(set(event_hits), key=lambda value: (-len(value), value))
        row["is_event_anchor"] = int(bool(event_hits))
        row["event_hit_term"] = "|".join(event_hits)

        placeholder_hits = [
            term for term, term_cf in placeholder_terms_cf if term_cf in name.casefold()
        ]
        if not name:
            placeholder_hits.append("空白/占位昵称")
        row["is_placeholder_nickname"] = int(bool(placeholder_hits))
        row["placeholder_hit_term"] = "|".join(placeholder_hits)

        club_hits = []
        for rule in compiled_clubs:
            if rule["regex"].search(name):
                club_hits.append(rule)
        unique_clubs = sorted({rule["club_name"] for rule in club_hits})
        unique_terms = sorted({rule["club_hit_term"] for rule in club_hits})
        unique_modes = sorted({rule["match_mode"] for rule in club_hits})
        row["is_club_anchor"] = int(bool(club_hits))
        row["club_name"] = "|".join(unique_clubs)
        row["club_hit_term"] = "|".join(unique_terms)
        row["club_match_mode"] = "|".join(unique_modes)

        duration_text = str(row["avg_daily_live_minutes"]).strip()
        try:
            duration = float(duration_text)
        except ValueError:
            duration = math.nan
        row["duration_value"] = duration
        row["is_low_activity"] = int(math.isfinite(duration) and duration < 30)

        missing_fields = [field for field in ORIGINAL_FIELDS if not str(row[field]).strip()]
        if missing_fields or not math.isfinite(duration):
            row["is_data_quality_error"] = 1
            row["data_quality_note"] = "关键字段为空: " + ",".join(missing_fields)
        else:
            row["is_data_quality_error"] = 0
            row["data_quality_note"] = ""

    threshold_base = [
        float(row["duration_value"])
        for row in rows
        if not row["is_data_quality_error"]
        and not row["is_placeholder_nickname"]
        and not row["is_event_anchor"]
        and not row["is_club_anchor"]
        and not row["is_low_activity"]
    ]
    threshold_base.sort()
    q1 = quantile(threshold_base, 0.25)
    q3 = quantile(threshold_base, 0.75)
    iqr = q3 - q1
    high_threshold = q3 + 3 * iqr

    for row in rows:
        high_eligible = (
            not row["is_data_quality_error"]
            and not row["is_placeholder_nickname"]
            and not row["is_event_anchor"]
            and not row["is_club_anchor"]
            and not row["is_low_activity"]
        )
        row["is_high_outlier"] = int(
            high_eligible and float(row["duration_value"]) > high_threshold
        )

    sequential_counts: dict[str, int] = {}
    remaining = [row.copy() for row in rows]

    def apply_stage(stage_name: str, predicate) -> None:
        nonlocal remaining
        before = len(remaining)
        removed = [row for row in remaining if predicate(row)]
        sequential_counts[stage_name] = len(removed)
        remaining = [row for row in remaining if not predicate(row)]
        sequential_counts[f"{stage_name}__before"] = before

    apply_stage("数据质量异常", lambda row: bool(row["is_data_quality_error"]))
    apply_stage("空白/占位昵称", lambda row: bool(row["is_placeholder_nickname"]))
    apply_stage("赛事/内容账号", lambda row: bool(row["is_event_anchor"]))
    apply_stage("俱乐部电竞主播", lambda row: bool(row["is_club_anchor"]))
    apply_stage("低开播主播（<30分钟/日）", lambda row: bool(row["is_low_activity"]))
    apply_stage("高异常主播（>高值阈值）", lambda row: bool(row["is_high_outlier"]))

    reason_order = [
        "数据质量异常",
        "空白/占位昵称",
        "赛事/内容账号",
        "俱乐部电竞主播",
        "低开播主播（<30分钟/日）",
        "高异常主播（>高值阈值）",
    ]

    for row in rows:
        flag_by_reason = {
            "数据质量异常": row["is_data_quality_error"],
            "空白/占位昵称": row["is_placeholder_nickname"],
            "赛事/内容账号": row["is_event_anchor"],
            "俱乐部电竞主播": row["is_club_anchor"],
            "低开播主播（<30分钟/日）": row["is_low_activity"],
            "高异常主播（>高值阈值）": row["is_high_outlier"],
        }
        reasons = [reason for reason in reason_order if flag_by_reason[reason]]
        row["final_exclusion_reason"] = reasons[0] if reasons else ""
        row["all_exclusion_reasons"] = "|".join(reasons)
        row["is_kept"] = int(not reasons)
        row["avg_daily_live_hours"] = (
            float(row["duration_value"]) / 60 if math.isfinite(float(row["duration_value"])) else ""
        )

    detail_fields = ORIGINAL_FIELDS + [
        "source_line",
        "is_event_anchor",
        "event_hit_term",
        "is_club_anchor",
        "club_name",
        "club_hit_term",
        "is_placeholder_nickname",
        "placeholder_hit_term",
        "is_data_quality_error",
        "data_quality_note",
        "is_low_activity",
        "is_high_outlier",
        "is_kept",
        "final_exclusion_reason",
        "all_exclusion_reasons",
        "avg_daily_live_hours",
    ]

    kept = [row for row in rows if row["is_kept"]]
    excluded = [row for row in rows if not row["is_kept"]]

    raw_rule_counts = {
        "数据质量异常": sum(int(row["is_data_quality_error"]) for row in rows),
        "空白/占位昵称": sum(int(row["is_placeholder_nickname"]) for row in rows),
        "赛事/内容账号": sum(int(row["is_event_anchor"]) for row in rows),
        "俱乐部电竞主播": sum(int(row["is_club_anchor"]) for row in rows),
        "低开播主播（<30分钟/日）": sum(int(row["is_low_activity"]) for row in rows),
        "高异常主播（>高值阈值）": sum(int(row["is_high_outlier"]) for row in rows),
    }

    rule_notes = {
        "数据质量异常": "主品类、品类名称、时长或luid缺失，单独保留，不进入统计。",
        "空白/占位昵称": "空白昵称，或昵称包含“我是一颗小虎牙”。",
        "赛事/内容账号": "昵称命中赛事、联赛、官方、活动、解说、二路、回放、集锦、电竞等内容词。",
        "俱乐部电竞主播": "命中已核对俱乐部全称、中文简称或收紧后的英文缩写规则。",
        "低开播主播（<30分钟/日）": "严格小于30分钟/日；等于30分钟不剔除。",
        "高异常主播（>高值阈值）": f"在高值阈值 {high_threshold:.6f} 分钟/日（{high_threshold/60:.4f}小时/日）以上；等于阈值不剔除。",
    }

    rule_rows = []
    for rule in reason_order:
        before = sequential_counts[f"{rule}__before"]
        removed = sequential_counts[rule]
        rule_rows.append(
            {
                "rule_name": rule,
                "raw_flag_hit_count": raw_rule_counts[rule],
                "before_rule_count": before,
                "sequential_removed_count": removed,
                "removal_rate_before_rule": removed / before if before else 0,
                "rule_note": rule_notes[rule],
            }
        )

    threshold_rows = [
        {"metric": "IQR统计样本数", "value": len(threshold_base), "unit": "人"},
        {"metric": "Q1", "value": q1, "unit": "分钟/日"},
        {"metric": "Q3", "value": q3, "unit": "分钟/日"},
        {"metric": "IQR", "value": iqr, "unit": "分钟/日"},
        {"metric": "高值阈值 Q3 + 3×IQR", "value": high_threshold, "unit": "分钟/日"},
        {"metric": "高值阈值（小时）", "value": high_threshold / 60, "unit": "小时/日"},
        {"metric": "高异常影响人数", "value": sequential_counts["高异常主播（>高值阈值）"], "unit": "人"},
        {"metric": "最终保留人数", "value": len(kept), "unit": "人"},
        {"metric": "最终剔除人数", "value": len(excluded), "unit": "人"},
    ]

    club_audit = []
    for row in rows:
        if not row["is_club_anchor"]:
            continue
        modes = str(row["club_match_mode"])
        terms = str(row["club_hit_term"])
        ambiguous_short = any(
            re.fullmatch(r"[A-Z0-9]{1,2}", term) for term in terms.split("|")
        )
        club_audit.append(
            {
                **{field: row[field] for field in ORIGINAL_FIELDS},
                "source_line": row["source_line"],
                "club_name": row["club_name"],
                "club_hit_term": row["club_hit_term"],
                "club_match_mode": modes,
                "short_code_requires_review": int(ambiguous_short),
                "review_result": (
                    "通过：短代码仅在收紧后的独立前缀/词边界命中"
                    if ambiguous_short
                    else "通过：俱乐部全称或高置信代码命中"
                ),
            }
        )

    data_quality = [
        {
            **{field: row[field] for field in ORIGINAL_FIELDS},
            "source_line": row["source_line"],
            "data_quality_note": row["data_quality_note"],
            "handling": "保留在异常记录中，不参与阈值计算和最终保留明细",
        }
        for row in rows
        if row["is_data_quality_error"]
    ]

    club_rule_rows = [
        {
            "club_name": rule["club_name"],
            "alias": rule["club_hit_term"],
            "match_mode": rule["match_mode"],
            "source_type": "联网核对 + 用户示例/公开电竞俱乐部常用名",
        }
        for rule in CLUB_RULES
    ]

    event_rule_rows = [
        {"rule_type": "赛事/内容词", "term": term, "match_mode": "昵称包含，忽略英文大小写"}
        for term in EVENT_TERMS
    ] + [
        {"rule_type": "占位昵称", "term": term, "match_mode": "昵称包含"}
        for term in PLACEHOLDER_TERMS
    ]

    summary_rows = [
        {"metric": "输入文件", "value": str(INPUT_PATH), "unit": ""},
        {"metric": "输入文件SHA256", "value": source_hash, "unit": ""},
        {"metric": "CSV表头实际列数", "value": len(header), "unit": "列"},
        {"metric": "原始数据行数", "value": len(rows), "unit": "行"},
        {"metric": "低开播固定门槛", "value": 30, "unit": "分钟/日"},
        {"metric": "高值阈值规则", "value": "Q3 + 3×IQR；不设负下限", "unit": ""},
    ] + threshold_rows

    write_csv(OUTPUT_DIR / "fps_anchor_kept_20261023.csv", kept, detail_fields)
    write_csv(OUTPUT_DIR / "fps_anchor_excluded_20261023.csv", excluded, detail_fields)
    write_csv(
        OUTPUT_DIR / "fps_anchor_rule_summary_20261023.csv",
        summary_rows,
        ["metric", "value", "unit"],
    )
    write_csv(
        OUTPUT_DIR / "fps_anchor_rule_hits_20261023.csv",
        rule_rows,
        ["rule_name", "raw_flag_hit_count", "before_rule_count", "sequential_removed_count", "removal_rate_before_rule", "rule_note"],
    )
    write_csv(
        OUTPUT_DIR / "fps_anchor_club_audit_20261023.csv",
        club_audit,
        ORIGINAL_FIELDS + ["source_line", "club_name", "club_hit_term", "club_match_mode", "short_code_requires_review", "review_result"],
    )
    write_csv(
        OUTPUT_DIR / "fps_anchor_data_quality_20261023.csv",
        data_quality,
        ORIGINAL_FIELDS + ["source_line", "data_quality_note", "handling"],
    )
    write_csv(
        OUTPUT_DIR / "fps_anchor_club_rules_20261023.csv",
        club_rule_rows,
        ["club_name", "alias", "match_mode", "source_type"],
    )
    write_csv(
        OUTPUT_DIR / "fps_anchor_event_rules_20261023.csv",
        event_rule_rows,
        ["rule_type", "term", "match_mode"],
    )

    summary_json = {
        "input_path": str(INPUT_PATH),
        "input_sha256": source_hash,
        "rows": len(rows),
        "kept": len(kept),
        "excluded": len(excluded),
        "raw_rule_counts": raw_rule_counts,
        "sequential_counts": {rule: sequential_counts[rule] for rule in reason_order},
        "thresholds": {
            "iqr_base_rows": len(threshold_base),
            "q1": q1,
            "q3": q3,
            "iqr": iqr,
            "high_threshold_minutes": high_threshold,
            "high_threshold_hours": high_threshold / 60,
        },
        "data_quality_rows": len(data_quality),
        "club_hit_rows": len(club_audit),
        "detected_luid_prefix_collisions": {
            "note": "原始CSV部分luid为科学计数法，存在不可逆精度损失；source_line用于行级追溯。",
            "unique_raw_luid": len({str(row["luid"]).strip() for row in rows}),
            "duplicate_rows_by_raw_luid": len(rows) - len({str(row["luid"]).strip() for row in rows}),
        },
    }
    (OUTPUT_DIR / "fps_anchor_build_summary_20261023.json").write_text(
        json.dumps(summary_json, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps(summary_json, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
