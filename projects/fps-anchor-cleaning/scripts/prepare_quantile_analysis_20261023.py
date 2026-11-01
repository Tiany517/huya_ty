from __future__ import annotations

import csv
import json
import math
from collections import Counter, defaultdict
from pathlib import Path


BASE_DIR = Path(r"C:\Users\tiany\Desktop\FPS主播清洗_20261023")
OUT_DIR = BASE_DIR / "outputs"
SUMMARY_CSV = OUT_DIR / "FPS正常主播_年度ACU分层与月均开播天数_修正版_20260101_20261020.csv"
DURATION_CSV = Path(r"C:\Users\tiany\Downloads\FPS主播年日均开播时长_最终明细_20261023.csv")
MAPPING_AUDIT_CSV = OUT_DIR / "FPS正常主播_昵称映射luid最终审计_修正版_20261023.csv"
JSON_OUT = OUT_DIR / "FPS头部腰部主播_开播时长分位数_月均10天门槛_20261023.json"

METRICS = [
    ("avg_daily_live_minutes", "年日均开播时长（分钟）", "开播时长分位标签"),
]


def quantile_linear(sorted_values: list[float], q: float) -> float:
    if not sorted_values:
        return math.nan
    if len(sorted_values) == 1:
        return sorted_values[0]
    pos = (len(sorted_values) - 1) * q
    lower = math.floor(pos)
    upper = math.ceil(pos)
    if lower == upper:
        return sorted_values[lower]
    weight = pos - lower
    return sorted_values[lower] * (1 - weight) + sorted_values[upper] * weight


def percentile_label(value: float, q25: float, q50: float, q75: float) -> str:
    if value < q25:
        return "低于25分位数"
    if value < q50:
        return "25至50分位数"
    if value < q75:
        return "50至75分位数"
    return "75分位数及以上"


def main() -> None:
    with SUMMARY_CSV.open("r", encoding="utf-8-sig", newline="") as f:
        rows = list(csv.DictReader(f))

    for row in rows:
        row["avg_daily_acu_2026"] = float(row.get("avg_daily_acu_2026") or 0)
        row["total_live_day_cnt"] = int(float(row.get("total_live_day_cnt") or 0))
        row["active_month_cnt"] = int(float(row.get("active_month_cnt") or 0))
        row["avg_monthly_live_days_10months"] = float(row.get("avg_monthly_live_days_10months") or 0)
        row["avg_monthly_live_days_active_months"] = float(row.get("avg_monthly_live_days_active_months") or 0)
        row["total_live_hours_2026"] = float(row.get("total_live_hours_2026") or 0)

    # 昵称映射审计表给出清洗后昵称对应的真实 luid；用它将原明细的日均开播时长挂回主播。
    name_to_luid: dict[str, str] = {}
    with MAPPING_AUDIT_CSV.open("r", encoding="utf-8-sig", newline="") as f:
        for item in csv.DictReader(f):
            snick = (item.get("snick") or "").strip()
            luid = (item.get("selected_luid") or "").strip()
            if snick and luid:
                name_to_luid[snick] = luid

    duration_by_luid: dict[str, list[float]] = defaultdict(list)
    with DURATION_CSV.open("r", encoding="utf-8-sig", newline="") as f:
        for item in csv.DictReader(f):
            snick = (item.get("snick") or "").strip()
            luid = name_to_luid.get(snick)
            raw_duration = (item.get("avg_daily_live_minutes") or "").strip()
            if luid and raw_duration:
                duration_by_luid[luid].append(float(raw_duration))

    duration_join_matched = 0
    duration_join_fallback = 0
    for row in rows:
        durations = duration_by_luid.get(row["luid"], [])
        if durations:
            row["avg_daily_live_minutes"] = max(durations)
            duration_join_matched += 1
        else:
            days = float(row["total_live_day_cnt"])
            row["avg_daily_live_minutes"] = row["total_live_hours_2026"] * 60 / days if days > 0 else 0.0
            duration_join_fallback += 1

    pre_filter_rows = [r for r in rows if r["acu_type"] in {"头部主播", "腰部主播"}]
    selected_rows = [r for r in pre_filter_rows if r["avg_monthly_live_days_10months"] >= 10]
    group_counts = Counter((r["main_game_name"], r["acu_type"]) for r in selected_rows)
    category_counts = Counter(r["main_game_name"] for r in selected_rows)
    main_categories = {name for name, cnt in category_counts.items() if cnt >= 5}

    summary_rows: list[dict[str, object]] = []
    count_rows: list[dict[str, object]] = []
    thresholds: dict[tuple[str, str, str], dict[str, float]] = {}

    ordered_categories = sorted(main_categories, key=lambda x: (-category_counts[x], x))
    for category in ordered_categories:
        for tier in ("头部主播", "腰部主播"):
            group = [r for r in selected_rows if r["main_game_name"] == category and r["acu_type"] == tier]
            if not group:
                continue
            for metric_key, metric_name, _ in METRICS:
                values = sorted(float(r[metric_key]) for r in group)
                p25 = quantile_linear(values, 0.25)
                p50 = quantile_linear(values, 0.50)
                p75 = quantile_linear(values, 0.75)
                thresholds[(category, tier, metric_key)] = {"p25": p25, "p50": p50, "p75": p75}
                summary_rows.append(
                    {
                        "main_game_name": category,
                        "acu_type": tier,
                        "anchor_cnt": len(group),
                        "metric": metric_name,
                        "p25": p25,
                        "p50": p50,
                        "p75": p75,
                        "min": values[0],
                        "max": values[-1],
                    }
                )
                count_rows.append(
                    {
                        "main_game_name": category,
                        "acu_type": tier,
                        "anchor_cnt": len(group),
                        "metric": metric_name,
                        "below_p25_cnt": sum(v < p25 for v in values),
                        "below_p50_cnt": sum(v < p50 for v in values),
                        "below_p75_cnt": sum(v < p75 for v in values),
                    }
                )

    head_waist_rows: list[dict[str, object]] = []
    for row in selected_rows:
        output = {
            "luid": row["luid"],
            "snick": row["snick"],
            "main_game_id": row["main_game_id"],
            "main_game_name": row["main_game_name"],
            "avg_daily_acu_2026": row["avg_daily_acu_2026"],
            "avg_daily_live_minutes": row["avg_daily_live_minutes"],
            "acu_type": row["acu_type"],
            "total_live_day_cnt": row["total_live_day_cnt"],
            "active_month_cnt": row["active_month_cnt"],
            "avg_monthly_live_days_10months": row["avg_monthly_live_days_10months"],
            "avg_monthly_live_days_active_months": row["avg_monthly_live_days_active_months"],
            "total_live_hours_2026": row["total_live_hours_2026"],
            "is_main_category": 1 if row["main_game_name"] in main_categories else 0,
            "category_tier_anchor_cnt": group_counts[(row["main_game_name"], row["acu_type"])],
        }
        for metric_key, _, label_name in METRICS:
            threshold = thresholds.get((row["main_game_name"], row["acu_type"], metric_key))
            if threshold:
                output[label_name] = percentile_label(float(row[metric_key]), threshold["p25"], threshold["p50"], threshold["p75"])
            else:
                output[label_name] = "不适用：品类层级样本少于5人"
        head_waist_rows.append(output)

    tier_order = {"头部主播": 0, "腰部主播": 1}
    head_waist_rows.sort(
        key=lambda r: (
            0 if r["is_main_category"] else 1,
            str(r["main_game_name"]),
            tier_order[str(r["acu_type"])],
            -float(r["avg_daily_live_minutes"]),
            str(r["luid"]),
        )
    )

    full_rows = [
        {
            "luid": r["luid"],
            "snick": r["snick"],
            "main_game_id": r["main_game_id"],
            "main_game_name": r["main_game_name"],
            "avg_daily_acu_2026": r["avg_daily_acu_2026"],
            "avg_daily_live_minutes": r["avg_daily_live_minutes"],
            "acu_type": r["acu_type"],
            "total_live_day_cnt": r["total_live_day_cnt"],
            "active_month_cnt": r["active_month_cnt"],
            "avg_monthly_live_days_10months": r["avg_monthly_live_days_10months"],
            "avg_monthly_live_days_active_months": r["avg_monthly_live_days_active_months"],
            "total_live_hours_2026": r["total_live_hours_2026"],
        }
        for r in sorted(rows, key=lambda x: (-float(x["avg_daily_acu_2026"]), str(x["luid"])))
    ]

    notes = [
        ["口径项", "说明"],
        ["时间范围", "2026-01-01 至 2026-10-20"],
        ["主播范围", f"上一版正常 FPS 主播清洗后识别出的真实 luid；原头部和腰部 {len(pre_filter_rows)} 人"],
        ["开播活跃门槛", "月均开播天数（2026年1-10月）>= 10 天；低于10天的主播不进入分位数和明细"],
        ["筛选后样本", f"保留 {len(selected_rows)} 人，剔除月均开播天数低于10天的 {len(pre_filter_rows) - len(selected_rows)} 人"],
        ["主要品类", "在筛选后的头部和腰部主播中，该主品类合计至少 5 人"],
        ["头部主播", "2026年年度日均 ACU >= 2000"],
        ["腰部主播", "100 <= 2026年年度日均 ACU < 2000"],
        ["年度日均 ACU", "先在主播 x 日计算 avg(acu)，再对该主播 live_mins > 0 的实际开播日求平均"],
        ["年日均开播时长", "使用上一版清洗明细的年日均开播分钟数；按昵称映射到真实 luid 后关联，缺失时才用年度开播小时×60÷开播天数补算"],
        ["月均开播天数", "2026年1-10月总实际开播天数除以10，未开播月份按0天参与平均"],
        ["分位数方法", "组内线性插值四分位数；P25、P50、P75 分别对应 25%、50%、75% 分位"],
        ["低于人数", "严格小于对应分位数的不同主播人数"],
        ["标签规则", "低于P25=低于25分位数；P25至P50=25至50分位数；P50至P75=50至75分位数；不低于P75=75分位数及以上"],
        ["小样本处理", "筛选后的头部+腰部合计不足5人的品类不进入分位数汇总，但仍保留在头部腰部明细中"],
        ["审计字段", "已从交付明细删除映射状态、候选ID、别名列表、年度指标匹配标记等内部审计字段"],
    ]

    payload = {
        "quantiles": summary_rows,
        "below_counts": count_rows,
        "head_waist_detail": head_waist_rows,
        "full_detail": full_rows,
        "notes": notes,
        "meta": {
            "full_anchor_cnt": len(rows),
            "head_waist_cnt": len(selected_rows),
            "head_waist_before_activity_filter_cnt": len(pre_filter_rows),
            "excluded_low_live_days_cnt": len(pre_filter_rows) - len(selected_rows),
            "duration_join_matched_anchor_cnt": duration_join_matched,
            "duration_join_fallback_anchor_cnt": duration_join_fallback,
            "main_category_cnt": len(main_categories),
            "main_categories": ordered_categories,
        },
    }
    JSON_OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    print(json.dumps(payload["meta"], ensure_ascii=False))
    print(f"quantile_rows={len(summary_rows)}")
    print(f"count_rows={len(count_rows)}")
    print(f"head_waist_rows={len(head_waist_rows)}")
    print(f"full_rows={len(full_rows)}")
    print(f"json_out={JSON_OUT}")


if __name__ == "__main__":
    main()
