from __future__ import annotations

import argparse
import base64
import csv
import gzip
import hashlib
import html
import json
import math
import statistics
import subprocess
import sys
from collections import defaultdict
from datetime import date, datetime, timedelta
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent

METRIC_RULES = {
    "platformDau": {"label": "平台 DAU", "pct": 0.05, "min_abs": 5000},
    "dau": {"label": "内容生态 DAU", "pct": 0.05, "min_abs": 5000},
    "revenue": {"label": "打赏流水", "pct": 0.10, "min_abs": 5000},
    "payUsers": {"label": "打赏人数", "pct": 0.10, "min_abs": 50},
    "attributionUsers": {"label": "归属用户数", "pct": 0.05, "min_abs": 5000},
    "liveAnchors": {"label": "开播主播数", "pct": 0.10, "min_abs": 10},
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build a one-page daily anomaly report from dashboard JSON.")
    parser.add_argument("--data", type=Path, required=True, help="dashboard_data_<run>.json")
    parser.add_argument("--platform-daily-csv", type=Path, help="CSV with dt,platform_dau from the official platform-active table.")
    parser.add_argument("--validation-report", type=Path, help="Dashboard validation report; status must be passed.")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--run-name", default="latest")
    parser.add_argument("--report-date", help="YYYY-MM-DD; defaults to the latest category date.")
    parser.add_argument("--baseline-count", type=int, default=4)
    parser.add_argument("--top-n", type=int, default=20)
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--smoke-test", action="store_true", help="Render the report in headless Chrome/Edge.")
    return parser.parse_args()


def parse_number(value, default=0.0) -> float:
    if value is None or value == "":
        return default
    try:
        number = float(value)
    except (TypeError, ValueError):
        return default
    return number if math.isfinite(number) else default


def median(values: list[float]) -> float:
    return float(statistics.median(values)) if values else 0.0


def pct_change(current: float, baseline: float) -> float | None:
    if baseline == 0:
        return None if current == 0 else math.copysign(math.inf, current)
    return (current - baseline) / abs(baseline)


def safe_div(numerator: float, denominator: float) -> float | None:
    return numerator / denominator if denominator else None


def robust_z(current: float, baseline_values: list[float], baseline: float) -> float:
    if len(baseline_values) < 2:
        return 0.0
    deviations = [abs(value - baseline) for value in baseline_values]
    mad = median(deviations)
    scale = mad * 1.4826
    if scale == 0:
        scale = float(statistics.pstdev(baseline_values))
    if scale == 0:
        scale = max(abs(baseline) * 0.02, 1.0)
    return (current - baseline) / scale


def confidence_level(values: list[float], baseline: float) -> str:
    if len(values) < 4:
        return "low"
    if baseline == 0:
        return "low" if any(value != 0 for value in values) else "high"
    cv = float(statistics.pstdev(values)) / abs(baseline)
    if cv <= 0.15:
        return "high"
    if cv <= 0.30:
        return "medium"
    return "low"


def classify_change(metric: str, current: float, baseline_values: list[float]) -> dict:
    rule = METRIC_RULES[metric]
    baseline = median(baseline_values)
    delta = current - baseline
    pct = pct_change(current, baseline)
    z = robust_z(current, baseline_values, baseline)
    confidence = confidence_level(baseline_values, baseline)
    severity = "正常"
    if abs(delta) >= rule["min_abs"]:
        if pct is None:
            severity = "高"
        else:
            abs_pct = abs(pct)
            if abs_pct >= rule["pct"] * 3 or (abs_pct >= rule["pct"] * 1.5 and abs(z) >= 3):
                severity = "高"
            elif abs_pct >= rule["pct"] or abs(z) >= 2.5:
                severity = "中"
    direction = "上升" if delta > 0 else "下降" if delta < 0 else "基本持平"
    if severity != "正常" and confidence == "low":
        severity = "中" if severity == "高" else severity
    return {
        "metric": metric,
        "label": rule["label"],
        "current": current,
        "baseline": baseline,
        "delta": delta,
        "changePct": pct,
        "robustZ": z,
        "confidence": confidence,
        "severity": severity,
        "direction": direction,
    }


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_platform_daily(path: Path | None) -> dict[str, float]:
    if path is None:
        return {}
    if not path.exists() or path.stat().st_size == 0:
        raise ValueError(f"platform daily CSV missing or empty: {path}")
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        headers = set(reader.fieldnames or [])
        if not {"dt", "platform_dau"}.issubset(headers):
            raise ValueError("platform daily CSV must contain dt,platform_dau")
        result = {}
        for row in reader:
            dt_value = (row.get("dt") or "").strip()
            if dt_value:
                date.fromisoformat(dt_value)
                if dt_value in result:
                    raise ValueError(f"platform daily CSV has duplicate dt: {dt_value}")
                value = parse_number(row.get("platform_dau"))
                if value <= 0:
                    raise ValueError(f"platform daily CSV has non-positive platform_dau: {dt_value}")
                result[dt_value] = value
    if not result:
        raise ValueError("platform daily CSV has no rows")
    return result


def build_visualization_payload(data: dict, platform_daily: dict[str, float], report_date: date) -> dict:
    """构造日报自由分析画布的轻量日级数据，供前端按日/周/月/季度聚合。"""
    meta = data["meta"]
    columns = {name: index for index, name in enumerate(meta["categoryColumns"])}
    groups = [
        {"id": str(index), "name": name}
        for index, name in enumerate(meta["contentGroups"])
    ]
    category_index = {str(item["id"]): index for index, item in enumerate(meta["categories"])}
    categories = [
        {"id": str(item["id"]), "name": item["name"], "group": int(item["group"])}
        for item in meta["categories"]
    ]
    dates = sorted({row[columns["date"]] for row in data["categoryDaily"]})
    date_index = {value: index for index, value in enumerate(dates)}
    rows = []
    for row in data["categoryDaily"]:
        category_id = str(meta["categories"][int(row[columns["category"]])]["id"])
        rows.append([
            date_index[row[columns["date"]]],
            category_index[category_id],
            int(row[columns["group"]]),
            parse_number(row[columns["dau"]]),
        ])
    platform = [
        [dt_value, parse_number(platform_daily[dt_value])]
        for dt_value in sorted(platform_daily)
        if dt_value in date_index or dt_value <= report_date.isoformat()
    ]
    return {
        "reportDate": report_date.isoformat(),
        "availableStart": dates[0] if dates else "",
        "availableEnd": dates[-1] if dates else "",
        "defaultScope": "platform" if platform else "total",
        "defaultGranularity": "day",
        "defaultChartType": "line",
        "granularities": ["day", "week", "month", "quarter"],
        "groups": groups,
        "categories": categories,
        "dates": dates,
        "platform": platform,
        "rows": rows,
    }


def previous_weekdays(report_date: date, count: int) -> list[date]:
    dates = []
    cursor = report_date - timedelta(days=7)
    while len(dates) < count:
        dates.append(cursor)
        cursor -= timedelta(days=7)
    return list(reversed(dates))


def format_number(value: float | int | None, digits: int = 0) -> str:
    if value is None:
        return "—"
    if not math.isfinite(float(value)):
        return "—"
    if digits:
        return f"{float(value):,.{digits}f}"
    return f"{float(value):,.0f}"


def format_pct(value: float | None) -> str:
    if value is None or not math.isfinite(value):
        return "—"
    return f"{value * 100:+.1f}%"


def format_pct_abs(value: float | None) -> str:
    if value is None or not math.isfinite(value):
        return "—"
    return f"{abs(value) * 100:.1f}%"


def format_delta(value: float | None) -> str:
    if value is None or not math.isfinite(value):
        return "—"
    return f"{value:+,.0f}"


def tier_for_acu(acu: float | None) -> str:
    if acu is None:
        return "未知"
    if acu >= 2000:
        return "头部"
    if acu >= 100:
        return "腰部"
    return "尾部"


def build_daily_series(data: dict) -> tuple[dict, dict, dict, dict]:
    meta = data["meta"]
    columns = {name: index for index, name in enumerate(meta["categoryColumns"])}
    categories = meta["categories"]
    groups = meta["contentGroups"]
    daily = defaultdict(lambda: {
        "rows": 0,
        "dau": 0.0,
        "revenue": 0.0,
        "payUsers": 0.0,
        "attributionUsers": 0.0,
        "liveAnchors": 0.0,
    })
    by_category = defaultdict(dict)
    by_group = defaultdict(dict)
    for row in data["categoryDaily"]:
        dt_value = row[columns["date"]]
        category_idx = int(row[columns["category"]])
        group_idx = int(row[columns["group"]])
        values = {
            "dau": parse_number(row[columns["dau"]]),
            "revenue": parse_number(row[columns["revenue"]]),
            "payUsers": parse_number(row[columns["payUsers"]]),
            "attributionUsers": parse_number(row[columns["attributionUsers"]]),
            "liveAnchors": parse_number(row[columns["liveAnchors"]]),
        }
        target = daily[dt_value]
        target["rows"] += 1
        for metric, value in values.items():
            target[metric] += value
        target["liveAnchors"] = max(target["liveAnchors"], parse_number(row[columns["totalLiveAnchors"]]))
        by_category[dt_value][category_idx] = values
        group = by_group[dt_value].setdefault(group_idx, {
            "dau": 0.0,
            "revenue": 0.0,
            "payUsers": 0.0,
            "attributionUsers": 0.0,
            "liveAnchors": 0.0,
            "rows": 0,
        })
        group["rows"] += 1
        for metric in ("dau", "revenue", "payUsers", "attributionUsers", "liveAnchors"):
            group[metric] += values[metric]
    return dict(daily), {k: dict(v) for k, v in by_category.items()}, {k: dict(v) for k, v in by_group.items()}, {
        "categories": categories,
        "groups": groups,
    }


def rank_daily_categories(
    report_date: date,
    baseline_dates: list[date],
    by_category: dict,
    meta_dimensions: dict,
    top_n: int,
) -> list[dict]:
    categories = meta_dimensions["categories"]
    groups = meta_dimensions["groups"]
    current = by_category.get(report_date.isoformat(), {})
    all_ids = set(current)
    for baseline_date in baseline_dates:
        all_ids.update(by_category.get(baseline_date.isoformat(), {}))
    root_delta = 0.0
    rows = []
    for category_idx in all_ids:
        current_values = current.get(category_idx, {})
        current_dau = parse_number(current_values.get("dau"))
        baseline_values = [
            parse_number(by_category.get(item.isoformat(), {}).get(category_idx, {}).get("dau"))
            for item in baseline_dates
        ]
        baseline_dau = median(baseline_values)
        delta = current_dau - baseline_dau
        root_delta += delta
        change = classify_change("dau", current_dau, baseline_values)
        category = categories[category_idx]
        rows.append({
            **change,
            "id": str(category["id"]),
            "name": category["name"],
            "group": groups[int(category["group"])],
            "currentRevenue": parse_number(current_values.get("revenue")),
            "baselineRevenue": median([
                parse_number(by_category.get(item.isoformat(), {}).get(category_idx, {}).get("revenue"))
                for item in baseline_dates
            ]),
        })
    for row in rows:
        row["contributionShare"] = row["delta"] / abs(root_delta) if root_delta else None
    rows.sort(key=lambda item: abs(item["delta"]), reverse=True)
    return rows[:top_n]


def aggregate_weekly_rows(data: dict) -> dict:
    meta = data["meta"]
    columns = {name: index for index, name in enumerate(meta["anchorColumns"])}
    weeks = meta["weeks"]
    if len(weeks) < 2:
        return {"available": False, "weeks": weeks}
    current_week_idx = len(weeks) - 1
    previous_week_idx = current_week_idx - 1
    current_week = weeks[current_week_idx]
    previous_week = weeks[previous_week_idx]

    def blank():
        return {
            "dau": 0.0,
            "revenue": 0.0,
            "payUsers": 0.0,
            "attributionUsers": 0.0,
            "interactionUsers": 0.0,
            "liveDays": 0.0,
            "acuSum": 0.0,
            "acuDays": 0.0,
            "rows": 0,
        }

    category = {current_week_idx: defaultdict(blank), previous_week_idx: defaultdict(blank)}
    guild = {current_week_idx: defaultdict(blank), previous_week_idx: defaultdict(blank)}
    anchor = {current_week_idx: defaultdict(blank), previous_week_idx: defaultdict(blank)}
    tier = {current_week_idx: defaultdict(blank), previous_week_idx: defaultdict(blank)}
    anchor_meta = {}
    for row in data["anchorWeekly"]:
        week_idx = int(row[columns["week"]])
        if week_idx not in (current_week_idx, previous_week_idx):
            continue
        category_idx = int(row[columns["category"]])
        guild_idx = int(row[columns["guild"]])
        anchor_idx = int(row[columns["anchor"]])
        acu = parse_number(row[columns["acuSum"]]) / parse_number(row[columns["acuDays"]], 1) if parse_number(row[columns["acuDays"]]) else None
        tier_name = tier_for_acu(acu)
        metrics = {
            "dau": parse_number(row[columns["dau"]]),
            "revenue": parse_number(row[columns["revenue"]]),
            "payUsers": parse_number(row[columns["payUsers"]]),
            "attributionUsers": parse_number(row[columns["attributionUsers"]]),
            "interactionUsers": parse_number(row[columns["interactionUsers"]]),
            "liveDays": parse_number(row[columns["liveDays"]]),
            "acuSum": parse_number(row[columns["acuSum"]]),
            "acuDays": parse_number(row[columns["acuDays"]]),
            "rows": 1,
        }
        targets = [
            (category[week_idx][category_idx], category[week_idx][category_idx]),
            (guild[week_idx][guild_idx], guild[week_idx][guild_idx]),
            (anchor[week_idx][(anchor_idx, category_idx, guild_idx)], anchor[week_idx][(anchor_idx, category_idx, guild_idx)]),
            (tier[week_idx][tier_name], tier[week_idx][tier_name]),
        ]
        for target, _ in targets:
            for key, value in metrics.items():
                target[key] += value
        anchor_meta[(anchor_idx, category_idx, guild_idx)] = {
            "anchorIdx": anchor_idx,
            "categoryIdx": category_idx,
            "guildIdx": guild_idx,
            "currentTier": tier_name,
        }
    return {
        "available": True,
        "weeks": weeks,
        "currentWeek": current_week,
        "previousWeek": previous_week,
        "category": category,
        "guild": guild,
        "anchor": anchor,
        "tier": tier,
        "anchorMeta": anchor_meta,
        "currentWeekIdx": current_week_idx,
        "previousWeekIdx": previous_week_idx,
    }


def weekly_rows_for(
    weekly: dict,
    collection: str,
    current_idx: int,
    previous_idx: int,
    meta: dict,
    key_formatter,
    label_formatter,
) -> list[dict]:
    current = weekly[collection][current_idx]
    previous = weekly[collection][previous_idx]
    keys = set(current) | set(previous)
    rows = []
    root_delta = 0.0
    for key in keys:
        current_values = current.get(key, {})
        previous_values = previous.get(key, {})
        current_dau = parse_number(current_values.get("dau"))
        previous_dau = parse_number(previous_values.get("dau"))
        delta = current_dau - previous_dau
        root_delta += delta
        previous_interactions = parse_number(previous_values.get("interactionUsers"))
        current_interactions = parse_number(current_values.get("interactionUsers"))
        row = {
            "_key": key,
            "metrics": key_formatter(key) if callable(key_formatter) else key_formatter,
            "label": label_formatter(key, meta),
            "currentDau": current_dau,
            "previousDau": previous_dau,
            "delta": delta,
            "changePct": pct_change(current_dau, previous_dau),
            "currentRevenue": parse_number(current_values.get("revenue")),
            "previousRevenue": parse_number(previous_values.get("revenue")),
            "revenueDelta": parse_number(current_values.get("revenue")) - parse_number(previous_values.get("revenue")),
            "currentPayUsers": parse_number(current_values.get("payUsers")),
            "previousPayUsers": parse_number(previous_values.get("payUsers")),
            "currentAttributionUsers": parse_number(current_values.get("attributionUsers")),
            "previousAttributionUsers": parse_number(previous_values.get("attributionUsers")),
            "currentInteractionUsers": current_interactions,
            "previousInteractionUsers": previous_interactions,
            "currentInteractionRate": safe_div(current_interactions, current_dau),
            "previousInteractionRate": safe_div(previous_interactions, previous_dau),
            "currentLiveDays": parse_number(current_values.get("liveDays")),
            "previousLiveDays": parse_number(previous_values.get("liveDays")),
        }
        rows.append(row)
    for row in rows:
        row["contributionShare"] = row["delta"] / abs(root_delta) if root_delta else None
    rows.sort(key=lambda item: abs(item["delta"]), reverse=True)
    return rows


def build_alerts(platform_changes: list[dict], category_ranked: list[dict], tier_rows: list[dict]) -> list[dict]:
    alerts = []
    for change in platform_changes:
        if change["severity"] != "正常":
            alerts.append({
                "priority": "高" if change["severity"] == "高" else "中",
                "type": change["label"],
                "title": f"{change['label']}{change['direction']} {format_pct_abs(change['changePct'])}",
                "detail": f"本期 {format_number(change['current'])}，同星期基线 {format_number(change['baseline'])}，变化 {format_delta(change['delta'])}。",
            })
    for row in category_ranked[:5]:
        if row["severity"] == "正常":
            continue
        alerts.append({
            "priority": "高" if row["severity"] == "高" else "中",
            "type": "品类",
            "title": f"{row['name']} 的 DAU {row['direction']} {format_pct_abs(row['changePct'])}",
            "detail": f"当前 {format_number(row['current'])}，同星期基线 {format_number(row['baseline'])}，变化 {format_delta(row['delta'])}。",
        })
    for row in tier_rows:
        if row["label"] in ("头部", "腰部", "尾部") and abs(row["delta"]) > 0:
            alerts.append({
                "priority": "中",
                "type": "主播层级",
                "title": f"{row['label']}主播周 DAU {format_delta(row['delta'])}",
                "detail": f"{row['currentWeek']} vs {row['previousWeek']}，变化 {format_pct(row['changePct'])}。",
            })
            break
    priority_order = {"高": 0, "中": 1, "低": 2}
    alerts.sort(key=lambda item: priority_order.get(item["priority"], 9))
    return alerts[:8]


def conclusion_text(
    platform_changes: dict[str, dict],
    category_ranked: list[dict],
    tier_rows: list[dict],
    baseline_count: int,
) -> list[str]:
    results = []
    dau = platform_changes.get("platformDau")
    live = platform_changes.get("liveAnchors")
    revenue = platform_changes.get("revenue")
    pay = platform_changes.get("payUsers")
    if dau:
        results.append(
            f"平台 DAU 为 {format_number(dau['current'])}，较过去 {baseline_count} 个同星期基线中位数变化 {format_pct(dau['changePct'])}。"
        )
    if dau and live:
        if dau["delta"] < 0 and live["delta"] < 0 and live["severity"] != "正常":
            results.append("平台 DAU 与开播主播数同时下降，优先检查供给减少及头部主播停播。")
        elif dau["delta"] < 0:
            results.append("平台 DAU 下降但开播主播数未同步下降，优先检查内容吸引力、推荐分发和单主播流失。")
    negative_categories = [row for row in category_ranked if row["delta"] < 0]
    if negative_categories:
        top = negative_categories[0]
        results.append(
            f"内容生态最大拖累为{top['name']}（{top['group']}），DAU 变化 {format_delta(top['delta'])}，变化率 {format_pct(top['changePct'])}。"
        )
    if revenue and pay:
        if revenue["delta"] > 0 and pay["severity"] == "正常":
            results.append("打赏流水上升，但打赏人数变化不显著，需结合 ARPPU 和大额付费集中度判断。")
        elif revenue["delta"] > 0 and pay["delta"] < 0 and pay["severity"] != "正常":
            results.append("流水上升而打赏人数下降，显示收入可能向少数高付费用户集中。")
        elif revenue["delta"] < 0 and pay["delta"] < 0 and pay["severity"] != "正常":
            results.append("流水与打赏人数同步下降，需同时检查流量和付费转化。")
    if tier_rows:
        largest = max(tier_rows, key=lambda item: abs(item["delta"]))
        results.append(f"最新完整周的主播层级中，{largest['label']}主播的 DAU 变化最大，变化值为 {format_delta(largest['delta'])}。")
    return results[:4]


def render_table(rows: list[dict], columns: list[tuple[str, callable]], empty_text: str = "暂无数据") -> str:
    if not rows:
        return f'<div class="empty">{html.escape(empty_text)}</div>'
    headers = "".join(f"<th>{html.escape(label)}</th>" for label, _ in columns)
    body = []
    for row in rows:
        cells = []
        for _, getter in columns:
            value = getter(row)
            if isinstance(value, tuple):
                text_value, css_class = value
            else:
                text_value, css_class = value, ""
            cells.append(f'<td class="{html.escape(css_class)}">{html.escape(str(text_value))}</td>')
        body.append("<tr>" + "".join(cells) + "</tr>")
    return f"<div class=\"table-wrap\"><table><thead><tr>{headers}</tr></thead><tbody>{''.join(body)}</tbody></table></div>"


def severity_cell(row: dict) -> tuple[str, str]:
    severity = row.get("severity", "正常")
    display = "低" if severity == "正常" else severity
    return display, f"badge severity-{display}"


def severity_rule_lines() -> list[str]:
    return [
        "级别口径说明",
        "1. 基数为过去 4 个相同星期的中位数；异常分 = 变化值 / (1.4826 × MAD)，MAD 为这 4 个历史值相对中位数的绝对偏差中位数。",
        "2. 平台 DAU、内容生态 DAU、归属用户数：最小绝对变化 5,000；变化率 ≥5% 为中，≥15% 为高。",
        "3. 打赏流水：最小绝对变化 5,000 元，变化率 ≥10% 为中、≥30% 为高；打赏人数：最小绝对变化 50 人，变化率 ≥10% 为中、≥30% 为高。",
        "4. 开播主播数：最小绝对变化 10 人，变化率 ≥10% 为中、≥30% 为高。",
        "5. 变化率达到中级线的 3 倍，或达到中级线的 1.5 倍且异常分绝对值 ≥3，也判为高；异常分绝对值 ≥2.5，也判为中。",
        "6. 基线少于 4 个点，或历史变异系数大于 30%，视为低把握，级别为高时降为中；变异系数 15%–30% 为中把握，≤15% 为高把握。",
        "7. 未达到中级别条件的显示为低（正常）。级别用于异动优先级，不等同于统计显著性。",
    ]


def render_html(report: dict, visualization_payload: dict) -> str:
    metrics = report["platformMetrics"]
    cards = []
    for metric in metrics:
        metric_label = f"{metric['label']}（日）"
        cards.append(f"""
        <article class="kpi-card {html.escape(metric['severity'])}">
          <div class="kpi-label">{html.escape(metric_label)}</div>
          <div class="kpi-value">{html.escape(format_number(metric['current']))}</div>
          <div class="kpi-meta">过去 4 个同星期中位数（日） {html.escape(format_number(metric['baseline']))}</div>
          <div class="kpi-change">变化 {html.escape(format_delta(metric['delta']))}<span>{html.escape(format_pct(metric['changePct']))}</span></div>
        </article>
        """)
    conclusion_items = "".join(f"<li>{html.escape(item)}</li>" for item in report["conclusions"])
    alert_items = "".join(
        f"<article class=\"alert-item {html.escape(item['priority'])}\"><span>{html.escape(item['priority'])}</span><div><strong>{html.escape(item['title'])}</strong><p>{html.escape(item['detail'])}</p></div></article>"
        for item in report["alerts"]
    ) or '<div class="empty">未触发重点异动阈值</div>'

    category_columns = [
        ("品类", lambda row: row["name"]),
        ("内容大类", lambda row: row["group"]),
        ("报告日 DAU（日）", lambda row: format_number(row["current"])),
        ("过去 4 个同星期中位数（日）", lambda row: format_number(row["baseline"])),
        ("变化值", lambda row: (format_delta(row["delta"]), "delta-down" if row["delta"] < 0 else "delta-up")),
        ("变化率", lambda row: format_pct(row["changePct"])),
        ("贡献占比", lambda row: format_pct(row.get("contributionShare"))),
        ("级别", severity_cell),
    ]
    guild_columns = [
        ("公会", lambda row: row["label"]),
        ("最新完整周 DAU（7 日求和）", lambda row: format_number(row["currentDau"])),
        ("上一完整周 DAU（7 日求和）", lambda row: format_number(row["previousDau"])),
        ("变化值", lambda row: (format_delta(row["delta"]), "delta-down" if row["delta"] < 0 else "delta-up")),
        ("变化率", lambda row: format_pct(row["changePct"])),
        ("互动人数", lambda row: format_number(row["currentInteractionUsers"])),
        ("互动率", lambda row: format_pct(row["currentInteractionRate"])),
    ]
    tier_columns = [
        ("主播层级", lambda row: row["label"]),
        ("最新完整周 DAU（7 日求和）", lambda row: format_number(row["currentDau"])),
        ("上一完整周 DAU（7 日求和）", lambda row: format_number(row["previousDau"])),
        ("变化值", lambda row: (format_delta(row["delta"]), "delta-down" if row["delta"] < 0 else "delta-up")),
        ("变化率", lambda row: format_pct(row["changePct"])),
        ("互动人数", lambda row: format_number(row["currentInteractionUsers"])),
        ("互动率", lambda row: format_pct(row["currentInteractionRate"])),
    ]
    anchor_columns = [
        ("主播", lambda row: row["label"]),
        ("品类 / 公会", lambda row: row["pathLabel"]),
        ("最新完整周 DAU（7 日求和）", lambda row: format_number(row["currentDau"])),
        ("上一完整周 DAU（7 日求和）", lambda row: format_number(row["previousDau"])),
        ("变化值", lambda row: (format_delta(row["delta"]), "delta-down" if row["delta"] < 0 else "delta-up")),
        ("变化率", lambda row: format_pct(row["changePct"])),
        ("互动人数", lambda row: format_number(row["currentInteractionUsers"])),
        ("互动率", lambda row: format_pct(row["currentInteractionRate"])),
    ]
    warning_items = "".join(f"<li>{html.escape(item)}</li>" for item in report["warnings"]) or "<li>无</li>"
    severity_rule_html = "<br>".join(html.escape(item) for item in severity_rule_lines())
    visualization_json = json.dumps(visualization_payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    visualization_gzip = base64.b64encode(gzip.compress(visualization_json, compresslevel=9, mtime=0)).decode("ascii")
    visualization_template = (SCRIPT_DIR.parent / "assets" / "daily_alert_visualization.js").read_text(encoding="utf-8")
    visualization_script = visualization_template.replace(
        "__DEFAULT_SCOPE__", json.dumps(visualization_payload["defaultScope"])
    )
    gen_time = report["generatedAt"].replace("T", " ")
    return f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>虎牙生态监控异动日报 {html.escape(report['reportDate'])}</title>
  <style>
    :root {{ --ink:#162235; --muted:#65748b; --line:rgba(255,255,255,.62); --bg:#f4f7fb; --card:rgba(255,255,255,.62); --blue:#2563eb; --red:#c93d4b; --green:#16815e; --amber:#a05c00; --glass:rgba(255,255,255,.54); --glass-strong:rgba(255,255,255,.76); --glass-stroke:rgba(255,255,255,.78); --liquid-shadow:0 18px 50px rgba(48,74,116,.12); }}
    * {{ box-sizing:border-box; }}
    body {{ margin:0; overflow-x:hidden; background:radial-gradient(circle at 8% 0%,rgba(133,180,255,.28),transparent 32%),radial-gradient(circle at 94% 10%,rgba(247,182,214,.23),transparent 28%),linear-gradient(180deg,#f2f7ff 0,#f8fbff 42%,#f5f8fd 100%); color:var(--ink); font-family:"Microsoft YaHei","PingFang SC",Arial,sans-serif; }}
    body::before,body::after {{ content:""; position:fixed; z-index:0; width:420px; height:420px; border-radius:50%; filter:blur(34px); pointer-events:none; opacity:.5; animation:liquidFloat 18s ease-in-out infinite alternate; }}
    body::before {{ left:-150px; top:8vh; background:radial-gradient(circle,rgba(105,165,255,.34),rgba(255,255,255,0)); }}
    body::after {{ right:-170px; top:36vh; background:radial-gradient(circle,rgba(248,160,205,.28),rgba(255,255,255,0)); animation-delay:-7s; }}
    @keyframes liquidFloat {{ from {{ transform:translate3d(0,-12px,0) scale(.94); }} to {{ transform:translate3d(28px,24px,0) scale(1.08); }} }}
    main {{ position:relative; z-index:1; width:min(1420px,calc(100% - 40px)); margin:0 auto; padding:34px 0 56px; }}
    .hero {{ display:flex; justify-content:space-between; gap:24px; align-items:flex-end; margin-bottom:22px; }}
    h1 {{ margin:6px 0 8px; font-size:34px; letter-spacing:-.5px; }}
    .eyebrow {{ color:var(--blue); font-weight:700; letter-spacing:.12em; font-size:12px; }}
    .subtitle {{ color:var(--muted); line-height:1.7; }}
    .stamp {{ min-width:250px; padding:16px 18px; border:1px solid var(--glass-stroke); border-radius:18px; background:var(--glass); box-shadow:var(--liquid-shadow); backdrop-filter:blur(24px) saturate(165%); -webkit-backdrop-filter:blur(24px) saturate(165%); }}
    .stamp strong {{ display:block; margin-bottom:6px; }}
    .stamp span {{ display:block; color:var(--muted); font-size:13px; line-height:1.7; }}
    .kpis {{ display:grid; grid-template-columns:repeat(5,minmax(0,1fr)); gap:14px; margin:20px 0; }}
    .kpi-card {{ position:relative; overflow:hidden; padding:18px; border-radius:18px; border:1px solid var(--glass-stroke); background:linear-gradient(145deg,rgba(255,255,255,.78),rgba(255,255,255,.46)); box-shadow:var(--liquid-shadow); backdrop-filter:blur(24px) saturate(165%); -webkit-backdrop-filter:blur(24px) saturate(165%); transition:transform .24s ease,box-shadow .24s ease; }}
    .kpi-card:hover {{ transform:translateY(-3px); box-shadow:0 24px 58px rgba(48,74,116,.16); }}
    .kpi-card:after {{ content:""; position:absolute; inset:0 auto 0 0; width:4px; background:#cbd5e1; }}
    .kpi-card.高:after {{ background:var(--red); }} .kpi-card.中:after {{ background:var(--amber); }}
    .kpi-label {{ color:var(--muted); font-size:13px; }}
    .kpi-value {{ margin:9px 0 7px; font-size:30px; font-weight:800; font-variant-numeric:tabular-nums; }}
    .kpi-meta,.kpi-change {{ color:var(--muted); font-size:12px; }}
    .kpi-change span {{ margin-left:10px; font-weight:700; color:var(--ink); }}
    .grid-two {{ display:grid; grid-template-columns:1.15fr .85fr; gap:18px; margin-top:18px; }}
    section {{ margin-top:18px; border:1px solid var(--glass-stroke); border-radius:20px; background:linear-gradient(145deg,rgba(255,255,255,.72),rgba(255,255,255,.48)); box-shadow:var(--liquid-shadow); overflow:hidden; backdrop-filter:blur(26px) saturate(165%); -webkit-backdrop-filter:blur(26px) saturate(165%); }}
    .section-head {{ padding:18px 20px 15px; border-bottom:1px solid rgba(255,255,255,.5); display:flex; justify-content:space-between; align-items:center; gap:16px; background:linear-gradient(90deg,rgba(255,255,255,.34),rgba(255,255,255,.08)); }}
    .section-head h2 {{ margin:0; font-size:18px; }} .section-head p {{ margin:0; color:var(--muted); font-size:12px; }}
    .section-body {{ padding:18px 20px 20px; }}
    .conclusions {{ margin:0; padding-left:22px; line-height:1.9; }}
    .alert-list {{ display:grid; gap:10px; }}
    .alert-item {{ display:grid; grid-template-columns:42px 1fr; gap:12px; padding:13px 14px; border-radius:14px; background:rgba(255,255,255,.55); border:1px solid rgba(255,255,255,.72); box-shadow:0 8px 22px rgba(48,74,116,.05); }}
    .alert-item>span {{ display:grid; place-items:center; width:34px; height:34px; border-radius:10px; color:#fff; background:var(--amber); font-weight:800; }}
    .alert-item.高>span {{ background:var(--red); }}
    .alert-item strong {{ font-size:14px; }} .alert-item p {{ margin:4px 0 0; color:var(--muted); font-size:12px; line-height:1.6; }}
    .table-wrap {{ overflow:auto; }}
    table {{ width:100%; border-collapse:collapse; font-size:13px; font-variant-numeric:tabular-nums; }}
    th {{ position:sticky; top:0; z-index:1; padding:11px 12px; text-align:left; color:#53627a; background:rgba(244,248,255,.78); border-bottom:1px solid rgba(255,255,255,.7); white-space:nowrap; backdrop-filter:blur(16px); -webkit-backdrop-filter:blur(16px); }}
    td {{ padding:11px 12px; border-bottom:1px solid #edf1f6; white-space:nowrap; }}
    tbody tr:hover {{ background:#f8fbff; }}
    .delta-down {{ color:var(--red); font-weight:700; }} .delta-up {{ color:var(--green); font-weight:700; }}
    .badge {{ display:inline-flex; padding:3px 8px; border-radius:99px; font-size:12px; font-weight:700; }}
    .severity-高 {{ color:#9f1f2e; background:#fee8eb; }} .severity-中 {{ color:#965600; background:#fff1d6; }} .severity-低 {{ color:#3f5b77; background:#edf3f8; }}
    .empty {{ padding:22px; color:var(--muted); text-align:center; background:#f8fafc; border-radius:12px; }}
    .notes {{ display:grid; grid-template-columns:1fr 1fr; gap:18px; }}
    .notes ul {{ margin:0; padding-left:20px; line-height:1.85; color:#4f6076; }}
    .visualization-head-tools {{ display:flex; align-items:center; gap:8px; flex-wrap:wrap; }}
    .visualization-controls {{ display:grid; grid-template-columns:minmax(210px,1.5fr) repeat(3,minmax(120px,.7fr)); gap:10px; padding:16px 20px; border-bottom:1px solid rgba(255,255,255,.52); background:rgba(255,255,255,.2); }}
    .visualization-control {{ display:flex; flex-direction:column; gap:6px; }}
    .visualization-control label {{ color:var(--muted); font-size:11px; font-weight:700; }}
    .visualization-control select {{ width:100%; min-height:38px; padding:8px 10px; color:var(--ink); font:inherit; font-size:12px; font-weight:700; border:1px solid rgba(255,255,255,.78); border-radius:12px; outline:none; background:rgba(255,255,255,.64); box-shadow:inset 0 1px 0 rgba(255,255,255,.8),0 8px 20px rgba(48,74,116,.07); backdrop-filter:blur(18px); -webkit-backdrop-filter:blur(18px); }}
    .chart-type-tabs {{ display:flex; gap:4px; padding:4px; border-radius:13px; background:rgba(235,241,250,.7); }}
    .chart-type-tabs button {{ flex:1; border:0; border-radius:10px; padding:8px 10px; background:transparent; color:var(--muted); font-size:12px; font-weight:800; }}
    .chart-type-tabs button.active {{ color:#2458b5; background:rgba(255,255,255,.88); box-shadow:0 6px 16px rgba(48,74,116,.1),inset 0 1px 0 #fff; }}
    .visualization-stage {{ padding:16px 20px 20px; }}
    .visualization-breadcrumb {{ display:flex; gap:8px; align-items:center; margin-bottom:10px; color:var(--muted); font-size:12px; flex-wrap:wrap; }}
    .visualization-breadcrumb button {{ border:0; padding:2px 7px; border-radius:8px; color:#315fae; background:rgba(255,255,255,.7); font:inherit; font-weight:700; }}
    .visualization-chart {{ min-height:340px; border-radius:16px; padding:10px; background:linear-gradient(145deg,rgba(255,255,255,.48),rgba(255,255,255,.2)); border:1px solid rgba(255,255,255,.5); }}
    .visualization-chart svg {{ display:block; width:100%; height:330px; overflow:visible; }}
    .visualization-chart .axis {{ fill:#718096; font-size:11px; }}
    .visualization-chart .grid {{ stroke:rgba(121,143,175,.18); }}
    .visualization-chart .line-path {{ fill:none; stroke:#2878df; stroke-width:3; stroke-linecap:round; stroke-linejoin:round; filter:drop-shadow(0 4px 7px rgba(40,120,223,.18)); }}
    .visualization-chart .dot {{ fill:#fff; stroke:#2878df; stroke-width:2.4; }}
    .visualization-chart .bar {{ fill:url(#barGradient); rx:7; }}
    .visualization-chart .stack-segment {{ cursor:pointer; transition:opacity .18s ease; }}
    .visualization-chart .stack-segment:hover {{ opacity:.76; }}
    .visualization-legend {{ display:flex; gap:8px 14px; flex-wrap:wrap; margin:8px 4px 0; color:var(--muted); font-size:11px; }}
    .visualization-legend span {{ display:inline-flex; align-items:center; gap:6px; }}
    .visualization-legend i {{ width:9px; height:9px; border-radius:3px; display:inline-block; }}
    .visualization-empty {{ min-height:300px; display:grid; place-items:center; color:var(--muted); }}
    footer {{ margin-top:22px; color:var(--muted); font-size:12px; line-height:1.8; }}
    @media (max-width:1100px) {{ .kpis {{ grid-template-columns:repeat(3,1fr); }} .grid-two {{ grid-template-columns:1fr; }} .visualization-controls {{ grid-template-columns:1fr 1fr; }} }}
    @media (max-width:720px) {{ main {{ width:min(100% - 24px,1420px); padding-top:22px; }} .hero {{ display:block; }} .stamp {{ margin-top:16px; }} h1 {{ font-size:27px; }} .kpis {{ grid-template-columns:1fr 1fr; }} .notes,.visualization-controls {{ grid-template-columns:1fr; }} .section-head {{ align-items:flex-start; flex-direction:column; }} }}
    @media (prefers-reduced-motion: reduce) {{ *,*::before,*::after {{ animation-duration:.01ms!important; animation-iteration-count:1!important; transition-duration:.01ms!important; scroll-behavior:auto!important; }} }}
  </style>
</head>
<body>
<main>
  <header class="hero">
    <div>
      <div class="eyebrow">ECOSYSTEM DAILY PULSE</div>
      <h1>虎牙生态监控异动日报</h1>
      <div class="subtitle">数据日期 {html.escape(report['reportDate'])}｜日报自动生成，关注异常幅度、同星期基线、贡献值和主播层级归因。</div>
    </div>
    <div class="stamp">
      <strong>平台 DAU 口径</strong>
      <span>来源：{html.escape(report['platformMetricMode'])}</span>
      <span>基线：过去 {report['baselineCount']} 个相同星期中位数</span>
      <span>生成：{html.escape(gen_time)}</span>
    </div>
  </header>
  <div class="kpis">{''.join(cards)}</div>
  <div class="grid-two">
    <section><div class="section-head"><h2>今日结论</h2><p>自动事实摘要</p></div><div class="section-body"><ul class="conclusions">{conclusion_items}</ul></div></section>
    <section><div class="section-head"><h2>重点异动</h2><p>按严重度排序</p></div><div class="section-body"><div class="alert-list">{alert_items}</div></div></section>
  </div>
  <section class="visualization-space" data-visualization-canvas="true">
    <div class="section-head">
      <div><h2>自由分析画布</h2><p>默认展示大盘 DAU 趋势，可切换粒度、图表类型和内容层级</p></div>
      <div class="visualization-head-tools"><span class="badge severity-低">DAU 日均口径</span></div>
    </div>
    <div class="visualization-controls">
      <div class="visualization-control"><label for="visualizationScope">分析范围</label><select id="visualizationScope"></select></div>
      <div class="visualization-control"><label for="visualizationGranularity">时间粒度</label><select id="visualizationGranularity"><option value="day">按日</option><option value="week">按周</option><option value="month">按月</option><option value="quarter">按季度</option></select></div>
      <div class="visualization-control"><label for="visualizationRange">时间范围</label><select id="visualizationRange"><option value="all">全部可用日期</option><option value="90">近 90 天</option><option value="30">近 30 天</option></select></div>
      <div class="visualization-control"><label>图表类型</label><div class="chart-type-tabs" id="visualizationChartType"><button type="button" data-chart-type="line" class="active">折线</button><button type="button" data-chart-type="bar">柱状</button><button type="button" data-chart-type="stack">100% 堆积</button></div></div>
    </div>
    <div class="visualization-stage">
      <div class="visualization-breadcrumb" id="visualizationBreadcrumb"></div>
      <div class="visualization-chart" id="visualizationChart"><div class="visualization-empty">正在准备图表数据...</div></div>
      <div class="visualization-legend" id="visualizationLegend"></div>
    </div>
  </section>
  <section><div class="section-head"><h2>品类 Top20</h2><p>按报告日 DAU 变化绝对值排序｜计数指标可比较，用户可能跨品类重叠</p></div>{render_table(report['categoryTop20'], category_columns)}</section>
  <section><div class="section-head"><h2>公会 Top20</h2><p>{html.escape(report['weeklyComparison'])}｜主播周表路径归因</p></div>{render_table(report['guildTop20'], guild_columns)}</section>
  <div class="grid-two">
    <section><div class="section-head"><h2>主播层级</h2><p>按当前完整周 ACU 划分</p></div>{render_table(report['tierRows'], tier_columns)}</section>
    <section><div class="section-head"><h2>数据与口径提示</h2><p>解读前先看限制</p></div><div class="section-body"><ul class="conclusions">{warning_items}</ul></div></section>
  </div>
  <section><div class="section-head"><h2>主播 Top20</h2><p>按主播 + 品类 + 公会路径的周 DAU 变化排序</p></div>{render_table(report['anchorTop20'], anchor_columns)}</section>
  <footer>输入文件：{html.escape(report['inputs']['data'])}<br>说明：平台 DAU 使用官方平台活跃用户表；品类、公会、主播数据仅用于归因，不直接相加成平台去重用户。互动率仅用于相对趋势，互动人数跨场次可能重叠。<br><br>{severity_rule_html}</footer>
</main>
<script id="visualization-data-gzip" type="text/plain">{visualization_gzip}</script>
<script>
{visualization_script}
</script>
</body>
</html>
"""


def render_markdown(report: dict) -> str:
    lines = [
        f"# 虎牙生态监控异动日报｜{report['reportDate']}",
        "",
        f"- 平台 DAU 口径：{report['platformMetricMode']}",
        f"- 基线：过去 {report['baselineCount']} 个相同星期中位数",
        f"- 最新完整周比较：{report['weeklyComparison']}",
        "",
        "## 今日结论",
        "",
    ]
    lines.extend(f"- {item}" for item in report["conclusions"])
    lines += ["", "## 平台指标", "", "| 指标 | 报告日值 | 过去 4 个同星期中位数（日） | 变化值 | 变化率 | 级别 |", "|---|---:|---:|---:|---:|---|"]
    for row in report["platformMetrics"]:
        lines.append(
            f"| {row['label']} | {format_number(row['current'])} | {format_number(row['baseline'])} | {format_delta(row['delta'])} | {format_pct(row['changePct'])} | {row['severity']} |"
        )
    for title, key, columns in (
        ("品类 Top20", "categoryTop20", [("品类", "name"), ("报告日 DAU（日）", "current"), ("过去 4 个同星期中位数（日）", "baseline"), ("变化值", "delta"), ("变化率", "changePct")]),
        ("公会 Top20", "guildTop20", [("公会", "label"), ("最新完整周 DAU（7 日求和）", "currentDau"), ("上一完整周 DAU（7 日求和）", "previousDau"), ("变化值", "delta"), ("变化率", "changePct")]),
        ("主播 Top20", "anchorTop20", [("主播", "label"), ("路径", "pathLabel"), ("最新完整周 DAU（7 日求和）", "currentDau"), ("上一完整周 DAU（7 日求和）", "previousDau"), ("变化值", "delta"), ("变化率", "changePct")]),
    ):
        lines += ["", f"## {title}", ""]
        lines.append("| " + " | ".join(label for label, _ in columns) + " |")
        lines.append("|" + "|".join("---" for _ in columns) + "|")
        for row in report[key]:
            rendered = []
            for _, field in columns:
                value = row.get(field)
                if field in {"changePct"}:
                    rendered.append(format_pct(value))
                elif field in {"current", "baseline", "delta", "currentDau", "previousDau"}:
                    rendered.append(format_delta(value) if field == "delta" else format_number(value))
                else:
                    rendered.append(str(value))
            lines.append("| " + " | ".join(rendered) + " |")
    lines += ["", "## 口径提示", ""]
    lines.extend(f"- {item}" for item in report["warnings"])
    lines += ["", "## 级别口径说明", ""]
    lines.extend(f"- {item}" for item in severity_rule_lines()[1:])
    lines += ["", f"生成时间：{report['generatedAt']}"]
    return "\n".join(lines) + "\n"


def all_numbers_finite(value) -> bool:
    if isinstance(value, float):
        return math.isfinite(value)
    if isinstance(value, dict):
        return all(all_numbers_finite(item) for item in value.values())
    if isinstance(value, list):
        return all(all_numbers_finite(item) for item in value)
    return True


def main() -> int:
    args = parse_args()
    data_path = args.data.resolve()
    data = json.loads(data_path.read_text(encoding="utf-8"))
    meta = data["meta"]
    latest_category_date = max(row[0] for row in data["categoryDaily"])
    report_date = date.fromisoformat(args.report_date or latest_category_date)
    baseline_dates = previous_weekdays(report_date, args.baseline_count)
    daily, by_category, _, dimensions = build_daily_series(data)
    platform_daily = load_platform_daily(args.platform_daily_csv.resolve() if args.platform_daily_csv else None)
    visualization_payload = build_visualization_payload(data, platform_daily, report_date)

    current_category = daily.get(report_date.isoformat())
    if current_category is None:
        raise SystemExit(f"report date not found in categoryDaily: {report_date.isoformat()}")
    baseline_days = [daily.get(item.isoformat(), {}) for item in baseline_dates]
    baseline_count = sum(1 for item in baseline_days if item)
    if baseline_count == 0:
        raise SystemExit("no same-weekday baseline dates available")

    platform_values = [platform_daily.get(item.isoformat(), 0.0) for item in baseline_dates]
    platform_available = report_date.isoformat() in platform_daily and all(value > 0 for value in platform_values)
    if platform_available:
        platform_metric = classify_change("platformDau", platform_daily[report_date.isoformat()], platform_values)
        platform_mode = "官方平台活跃用户表（huya Android/iOS/iPad/Pad，剔除黑名单用户）"
    else:
        platform_metric = classify_change("dau", parse_number(current_category.get("dau")), [parse_number(item.get("dau")) for item in baseline_days])
        platform_metric["label"] = "平台 DAU（品类合计口径）"
        platform_mode = "品类整体合计（用户跨品类可能重叠，仅作内容生态近似）"

    platform_changes = {
        "platformDau": platform_metric,
        "revenue": classify_change("revenue", parse_number(current_category.get("revenue")), [parse_number(item.get("revenue")) for item in baseline_days]),
        "payUsers": classify_change("payUsers", parse_number(current_category.get("payUsers")), [parse_number(item.get("payUsers")) for item in baseline_days]),
        "attributionUsers": classify_change("attributionUsers", parse_number(current_category.get("attributionUsers")), [parse_number(item.get("attributionUsers")) for item in baseline_days]),
        "liveAnchors": classify_change("liveAnchors", parse_number(current_category.get("liveAnchors")), [parse_number(item.get("liveAnchors")) for item in baseline_days]),
    }
    category_ranked = rank_daily_categories(report_date, baseline_dates, by_category, dimensions, args.top_n)
    weekly = aggregate_weekly_rows(data)
    guild_rows = []
    tier_rows = []
    anchor_rows = []
    weekly_comparison = "周数据不足"
    if weekly["available"]:
        meta_dimensions = {
            "guilds": meta["guilds"],
            "categories": meta["categories"],
            "anchors": meta["anchors"],
        }
        current_idx = weekly["currentWeekIdx"]
        previous_idx = weekly["previousWeekIdx"]
        guild_rows = weekly_rows_for(weekly, "guild", current_idx, previous_idx, meta_dimensions, lambda key: key, lambda key, _: meta_dimensions["guilds"][key])
        tier_rows = weekly_rows_for(weekly, "tier", current_idx, previous_idx, meta_dimensions, lambda key: key, lambda key, _: key)
        anchor_rows = weekly_rows_for(weekly, "anchor", current_idx, previous_idx, meta_dimensions, lambda key: key, lambda key, _: meta_dimensions["anchors"][key[0]]["name"])
        for row in anchor_rows:
            key = row["_key"]
            category_name = meta_dimensions["categories"][key[1]]["name"]
            guild_name = meta_dimensions["guilds"][key[2]]
            row["pathLabel"] = f"{category_name} / {guild_name}"
        order = {"头部": 0, "腰部": 1, "尾部": 2, "未知": 3}
        tier_rows.sort(key=lambda row: order.get(row["label"], 9))
        for row in tier_rows + guild_rows + anchor_rows:
            row["currentWeek"] = weekly["currentWeek"]
            row["previousWeek"] = weekly["previousWeek"]
        weekly_comparison = f"{weekly['currentWeek']} vs {weekly['previousWeek']}"
    else:
        weekly_comparison = "最新仅有一个完整周，暂不做周环比"

    alerts = build_alerts(list(platform_changes.values()), category_ranked, tier_rows)
    conclusions = conclusion_text(platform_changes, category_ranked, tier_rows, baseline_count)
    alerts = alerts[:8]
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    suffix = args.run_name
    html_path = output_dir / f"daily_alert_report_{suffix}.html"
    json_path = output_dir / f"daily_alert_report_{suffix}.json"
    md_path = output_dir / f"daily_alert_report_{suffix}.md"
    smoke_path = output_dir / f"daily_alert_smoke_report_{suffix}.json"
    manifest_path = output_dir / f"daily_alert_manifest_{suffix}.json"
    targets = [html_path, json_path, md_path, manifest_path]
    if args.smoke_test:
        targets.append(smoke_path)
    conflicts = [str(path) for path in targets if path.exists()]
    if conflicts and not args.overwrite:
        raise SystemExit("refusing to overwrite daily report outputs: " + ", ".join(conflicts))

    checks = {
        "reportDateAvailable": report_date.isoformat() in daily,
        "baselineDatesEnough": baseline_count >= min(2, args.baseline_count),
        "platformDauAvailable": platform_available,
        "categoryRowsPresent": bool(category_ranked),
        "weeklyComparisonAvailable": weekly["available"],
        "topTablesPopulated": bool(category_ranked and guild_rows and anchor_rows),
        "visualizationDataAvailable": bool(visualization_payload["rows"]),
    }
    if args.validation_report:
        source_validation = json.loads(args.validation_report.read_text(encoding="utf-8"))
        checks["sourceValidationPassed"] = (
            source_validation.get("status") == "passed"
            and all(source_validation.get("checks", {}).values())
        )
    warnings = [
        "平台 DAU 使用官方活跃用户表；品类 DAU、归属用户和互动人数可能跨品类重叠，不能直接相加成全站去重用户。",
        "品类、公会、主播 Top20 使用贡献值绝对值排序；低基数对象即使变化率很高，也可能只是小样本波动。",
        "互动率 = 互动人数 / DAU，仅用于相对趋势；互动人数跨场次可能重叠。",
        "主播周表只覆盖最新完整自然周；主播日和公会归因不替代平台总盘。",
    ]
    if not platform_available:
        warnings.insert(0, "未提供完整的官方平台 DAU CSV，本次改用品类合计近似；该结果不应作为全站 DAU 对外发布。")
    if meta.get("eventStatus") == "pending":
        warnings.append("赛事支付属性仍为 pending，本次日报不使用赛事用户筛选解释 DAU、归属用户或互动变化。")
    low_confidence = [row["label"] for row in platform_changes.values() if row["confidence"] == "low"]
    if low_confidence:
        warnings.append("以下指标的基线波动较大，异动等级已降级处理：" + "、".join(low_confidence) + "。")

    report = {
        "status": "pending",
        "reportDate": report_date.isoformat(),
        "generatedAt": datetime.now().astimezone().isoformat(timespec="seconds"),
        "baselineCount": baseline_count,
        "baselineDates": [item.isoformat() for item in baseline_dates if item.isoformat() in daily],
        "platformMetricMode": platform_mode,
        "inputs": {"data": str(data_path)},
        "sourceMeta": {
            "sourceLatestPartition": meta.get("sourceLatestPartition"),
            "aggregateStartDate": meta.get("aggregateStartDate"),
            "aggregateEndDate": meta.get("aggregateEndDate"),
            "anchorStartDate": meta.get("anchorStartDate"),
            "anchorEndDate": meta.get("anchorEndDate"),
            "eventStatus": meta.get("eventStatus"),
        },
        "platformMetrics": [platform_changes[key] for key in ("platformDau", "revenue", "payUsers", "attributionUsers", "liveAnchors")],
        "categoryTop20": category_ranked,
        "guildTop20": guild_rows[: args.top_n],
        "tierRows": tier_rows,
        "anchorTop20": anchor_rows[: args.top_n],
        "weeklyComparison": weekly_comparison,
        "alerts": alerts,
        "conclusions": conclusions,
        "warnings": warnings,
        "visualizationMeta": {
            "defaultScope": visualization_payload["defaultScope"],
            "availableStart": visualization_payload["availableStart"],
            "availableEnd": visualization_payload["availableEnd"],
            "rowCount": len(visualization_payload["rows"]),
            "platformPointCount": len(visualization_payload["platform"]),
        },
        "checks": checks,
    }
    html_text = render_html(report, visualization_payload)
    checks["htmlContainsCoreSections"] = all(token in html_text for token in ("虎牙生态监控异动日报", "自由分析画布", "品类 Top20", "公会 Top20", "主播 Top20", "级别口径说明"))
    if args.smoke_test:
        node = "node"
        smoke_cmd = [
            node,
            str(SCRIPT_DIR / "smoke_test_dashboard.mjs"),
            "--html", str(html_path),
            "--report", str(smoke_path),
        ]
        html_path.write_text(html_text, encoding="utf-8")
        try:
            subprocess.run(
                smoke_cmd,
                check=True,
                text=True,
                capture_output=True,
                encoding="utf-8",
                errors="replace",
            )
            smoke = json.loads(smoke_path.read_text(encoding="utf-8"))
            checks["browserSmokePassed"] = smoke.get("status") == "passed"
        except (subprocess.CalledProcessError, OSError, json.JSONDecodeError) as exc:
            checks["browserSmokePassed"] = False
            warnings.append(f"浏览器冒烟失败：{exc}")
    checks["allNumbersFinite"] = all_numbers_finite(report)
    report["checks"] = checks
    report["status"] = "passed" if all(checks.values()) else "failed"
    if not report["status"] == "passed":
        warnings.append("日报存在未通过检查项，不应替换桌面最新日报。")

    html_path.write_text(render_html(report, visualization_payload), encoding="utf-8")
    json_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    md_path.write_text(render_markdown(report), encoding="utf-8")
    manifest = {
        "status": report["status"],
        "reportDate": report["reportDate"],
        "generatedAt": report["generatedAt"],
        "inputs": {
            "data": {"path": str(data_path), "bytes": data_path.stat().st_size, "sha256": sha256(data_path)},
            **({"platformDailyCsv": {"path": str(args.platform_daily_csv.resolve()), "bytes": args.platform_daily_csv.stat().st_size, "sha256": sha256(args.platform_daily_csv)}} if args.platform_daily_csv else {}),
            **({"validationReport": {"path": str(args.validation_report.resolve()), "bytes": args.validation_report.stat().st_size, "sha256": sha256(args.validation_report)}} if args.validation_report else {}),
        },
        "outputs": {
            "html": {"path": str(html_path), "bytes": html_path.stat().st_size, "sha256": sha256(html_path)},
            "json": {"path": str(json_path), "bytes": json_path.stat().st_size, "sha256": sha256(json_path)},
            "markdown": {"path": str(md_path), "bytes": md_path.stat().st_size, "sha256": sha256(md_path)},
            **({"browserSmoke": {"path": str(smoke_path), "bytes": smoke_path.stat().st_size, "sha256": sha256(smoke_path)}} if smoke_path.exists() else {}),
        },
        "checks": checks,
    }
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "status": report["status"],
        "reportDate": report["reportDate"],
        "html": str(html_path),
        "json": str(json_path),
        "markdown": str(md_path),
        "manifest": str(manifest_path),
        "checks": checks,
        "alerts": alerts,
    }, ensure_ascii=False, indent=2))
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
