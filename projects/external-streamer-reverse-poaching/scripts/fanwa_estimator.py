#!/usr/bin/env python3
"""Auditable, side-effect-free copy of the historical fanwa model.

The source scripts blended external-platform signals with manually chosen
benchmark accounts and caps. This module preserves that model for forensic and
continuation work. It is not a fitted or validated predictive model.
"""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any


CATEGORY_HOURLY_RATES: dict[str, list[float]] = {
    "王者荣耀": [0.20, 0.18, 0.15, 0.13, 0.12, 0.10, 0.08, 0.04],
    "英雄联盟": [0.32, 0.28, 0.24, 0.20, 0.18, 0.16, 0.12, 0.10],
    "绝地求生": [0.22, 0.20, 0.18, 0.16, 0.14, 0.12, 0.10, 0.08],
    "主机游戏": [0.35, 0.30, 0.28, 0.25, 0.20, 0.18, 0.14, 0.08],
    "户外品类": [0.20, 0.15, 0.12, 0.10, 0.08, 0.06, 0.04, 0.02],
    "DOTA2": [0.58, 0.45, 0.36, 0.28, 0.24, 0.20, 0.18, 0.10],
    "DOTA1": [0.48, 0.32, 0.27, 0.24, 0.20, 0.18, 0.15, 0.08],
    "炉石传说": [0.45, 0.38, 0.22, 0.16, 0.14, 0.12, 0.10, 0.08],
    "我的世界": [0.48, 0.35, 0.24, 0.18, 0.16, 0.14, 0.10, 0.08],
    "全品类": [0.30, 0.26, 0.23, 0.20, 0.18, 0.16, 0.12, 0.08],
    "问道": [0.75, 0.65, 0.54, 0.36, 0.28, 0.16, 0.12, 0.10],
    "逆水寒手游": [0.32, 0.26, 0.22, 0.20, 0.16, 0.14, 0.08, 0.04],
    "CS2": [0.54, 0.48, 0.32, 0.24, 0.20, 0.18, 0.16, 0.08],
    "DNF": [1.28, 0.98, 0.85, 0.78, 0.64, 0.55, 0.42, 0.30],
    "云顶": [0.15, 0.13, 0.12, 0.11, 0.10, 0.08, 0.06, 0.04],
    "吃鸡手游": [0.20, 0.16, 0.14, 0.12, 0.10, 0.08, 0.06, 0.04],
    "穿越火线": [0.22, 0.16, 0.16, 0.12, 0.10, 0.08, 0.06, 0.04],
    "火影手游": [0.20, 0.18, 0.16, 0.15, 0.14, 0.12, 0.08, 0.04],
    "狼人杀": [0.78, 0.75, 0.68, 0.54, 0.46, 0.34, 0.28, 0.10],
    "无畏契约": [0.28, 0.24, 0.20, 0.18, 0.16, 0.14, 0.12, 0.10],
    "永劫无间": [0.32, 0.28, 0.25, 0.22, 0.18, 0.16, 0.12, 0.10],
    "Apex": [0.32, 0.28, 0.25, 0.22, 0.18, 0.16, 0.12, 0.10],
    "三角洲行动": [0.58, 0.50, 0.42, 0.36, 0.24, 0.18, 0.12, 0.08],
}

CATEGORY_ALIASES: dict[str, str] = {
    "天天吃鸡": "绝地求生",
    "虎牙吃鸡": "绝地求生",
    "吃鸡行动": "绝地求生",
    "主机其他游戏": "主机游戏",
    "其他主机游戏": "主机游戏",
    "户外": "户外品类",
    "炉石战棋": "炉石传说",
    "我的世界：传奇": "我的世界",
    "我的世界：地下城": "我的世界",
    "我的世界地下城": "我的世界",
    "问道手游": "问道",
    "问道电脑版": "问道",
    "DNF手游": "DNF",
    "地下城与勇士": "DNF",
    "云顶之弈": "云顶",
    "lol云顶之弈": "云顶",
    "天天吃鸡手机版": "吃鸡手游",
    "和平精英": "吃鸡手游",
    "火影忍者手游": "火影手游",
    "天天狼人杀": "狼人杀",
    "永劫无间手游": "永劫无间",
    "Apex英雄": "Apex",
}

ACU_REFERENCE = [15900.0, 3755.0, 1800.0]
PAY_BREAKPOINTS = [100_000, 250_000, 500_000, 1_000_000, 1_500_000, 2_000_000, 2_500_000]


def _number(row: Mapping[str, Any], key: str, default: float = 0.0) -> float:
    value = row.get(key, default)
    if value is None or str(value).strip() in {"", "\\N", "nan", "None"}:
        return default
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _strict_number(row: Mapping[str, Any], key: str) -> float:
    value = row[key]
    if value is None or str(value).strip() in {"", "\\N", "nan", "None"}:
        raise ValueError(f"Non-numeric value for {key}")
    return float(value)


def _ratio_score(value: float, references: list[float]) -> float:
    score = sum(value / reference * target for reference, target in zip(references, ACU_REFERENCE))
    return score / 3.0


def category_hourly_rates(category: str) -> list[float]:
    normalized = CATEGORY_ALIASES.get(category, category)
    return CATEGORY_HOURLY_RATES.get(normalized, CATEGORY_HOURLY_RATES["全品类"])


def piecewise_pay(viewer_hours: float, rates: list[float]) -> float:
    """Apply the original cumulative marginal hourly-rate schedule."""
    if viewer_hours <= 0:
        return 0.0
    total = 0.0
    lower = 0.0
    for upper, rate in zip(PAY_BREAKPOINTS, rates):
        if viewer_hours <= upper:
            return total + (viewer_hours - lower) * rate
        total += (upper - lower) * rate
        lower = upper
    return total + (viewer_hours - PAY_BREAKPOINTS[-1]) * rates[-1]


def predict_monthly_pay(predicted_acu: float, category: str) -> float:
    # Historical assumption: 20 live days and 5.5 hours per live day.
    viewer_hours = predicted_acu * 20 * 5.5
    return piecewise_pay(viewer_hours, category_hourly_rates(category))


def predict_revenue(row: Mapping[str, Any]) -> float:
    # The original script returned zero for the whole row if any input was
    # missing or nonnumeric. Preserve that behavior rather than partly scoring.
    try:
        acu = _strict_number(row, "predict_acu")
        gift_user = _strict_number(row, "gift_user")
        gift_value = _strict_number(row, "gift_value")
        return acu * 8 * 0.2 + gift_user * 50 * 0.2 + gift_value * 0.6
    except (KeyError, TypeError, ValueError):
        return 0.0


def _douyu_rising(row: Mapping[str, Any]) -> float:
    avg_ref = [47.0, 12.0, 5.0]
    danmu_ref = [13_000.0, 3_600.0, 1_540.0]
    dingyue_ref = [14_642.0, 5_174.0, 1_993.0]
    danmu_only_ref = [16_834.0, 4_905.0, 2_338.0]
    danmu_new_ref = [2_990.0, 734.0, 276.0]

    avg_com_acu = min(_ratio_score(_number(row, "avg_com"), avg_ref), 50_000)
    danmu_acu = min(_ratio_score(_number(row, "danmu"), danmu_ref), 50_000)
    dingyue_acu = min(_ratio_score(max(_number(row, "dingyue_add"), 0), dingyue_ref), 50_000)
    dingyue_acu = min(dingyue_acu, (avg_com_acu + danmu_acu) * 0.8)
    danmu_only_acu = min(_ratio_score(_number(row, "danmu_only"), danmu_only_ref), 100_000)
    danmu_only_acu = min(danmu_only_acu, (avg_com_acu + danmu_acu) * 0.8)
    danmu_new_acu = min(_ratio_score(_number(row, "danmu_new"), danmu_new_ref), 100_000)
    # Preserve the historical expression, including its unusual cap source.
    danmu_new_acu = min(danmu_only_acu, (avg_com_acu + danmu_acu) * 0.8)
    score = (
        avg_com_acu * 0.45
        + danmu_acu * 0.15
        + dingyue_acu * 0.05
        + danmu_only_acu * 0.20
        + danmu_new_acu * 0.15
    )
    return round(score * 1.4 / 50) * 50


def estimate_douyu(row: Mapping[str, Any], rising: bool = False) -> float:
    if rising:
        return _douyu_rising(row)
    avg_ref = [47.0, 12.0, 5.0]
    danmu_ref = [13_000.0, 3_600.0, 1_540.0]
    dingyue_ref = [16_242.0, 6_084.0, 2_800.0]
    danmu_only_ref = [19_600.0, 4_300.0, 815.0]
    danmu_new_ref = [2_487.0, 815.0, 276.0]

    avg_com_acu = min(_ratio_score(_number(row, "avg_com"), avg_ref), 70_000)
    danmu_acu = min(_ratio_score(_number(row, "danmu"), danmu_ref), 70_000)
    dingyue_acu = min(_ratio_score(max(_number(row, "dingyue_add"), 0), dingyue_ref), 40_000)
    dingyue_acu = min(dingyue_acu, (avg_com_acu + danmu_acu) * 0.7)
    danmu_only_acu = min(_ratio_score(_number(row, "danmu_only"), danmu_only_ref), 50_000)
    danmu_only_acu = min(danmu_only_acu, (avg_com_acu + danmu_acu) * 0.7)
    danmu_new_acu = min(_ratio_score(_number(row, "danmu_new"), danmu_new_ref), 50_000)
    # Preserve the historical expression, including its unusual cap source.
    danmu_new_acu = min(danmu_only_acu, (avg_com_acu + danmu_acu) * 0.7)
    score = (
        avg_com_acu * 0.4
        + danmu_acu * 0.3
        + dingyue_acu * 0.05
        + danmu_only_acu * 0.15
        + danmu_new_acu * 0.10
    )
    scale = 1.2 if row.get("r_category") == "DOTA2" else 1.0
    return round(score * scale / 50) * 50


def _bilibili_rising(row: Mapping[str, Any]) -> float:
    avg_ref = [26.0, 9.0, 4.0]
    danmu_ref = [3_713.0, 1_404.0, 616.0]
    dingyue_ref = [33_547.0, 9_487.0, 6_081.0]
    danmu_only_ref = [8_510.0, 3_987.0, 1_415.0]
    danmu_new_ref = [1_750.0, 1_059.0, 708.0]

    avg_com_acu = min(_ratio_score(_number(row, "avg_com"), avg_ref), 100_000)
    danmu_acu = min(_ratio_score(_number(row, "danmu"), danmu_ref), 100_000)
    dingyue_acu = min(_ratio_score(max(_number(row, "dingyue_add"), 0), dingyue_ref), 100_000)
    danmu_only_acu = min(_ratio_score(_number(row, "danmu_only"), danmu_only_ref), 100_000)
    danmu_new_acu = min(_ratio_score(_number(row, "danmu_new"), danmu_new_ref), 100_000)
    # Preserve the historical expression, including its unusual cap source.
    danmu_new_acu = min(danmu_only_acu, (avg_com_acu + danmu_acu) * 0.8)
    score = (
        avg_com_acu * 0.15
        + danmu_acu * 0.15
        + dingyue_acu * 0.15
        + danmu_only_acu * 0.35
        + danmu_new_acu * 0.20
    )
    return round(score * 0.7 / 50) * 50


def estimate_bilibili(row: Mapping[str, Any], rising: bool = False) -> float:
    if rising:
        return _bilibili_rising(row)
    avg_ref = [26.0, 9.0, 4.0]
    danmu_ref = [5_027.0, 1_404.0, 616.0]
    dingyue_ref = [32_000.0, 19_487.0, 11_716.0]
    danmu_only_ref = [1_200.0, 2_914.0, 1_415.0]
    danmu_new_ref = [2_683.0, 780.0, 460.0]

    avg_com_acu = min(_ratio_score(_number(row, "avg_com"), avg_ref), 50_000)
    danmu_acu = min(_ratio_score(_number(row, "danmu"), danmu_ref), 50_000)
    dingyue_acu = min(_ratio_score(max(_number(row, "dingyue_add"), 0), dingyue_ref), 40_000)
    dingyue_acu = min(dingyue_acu, (avg_com_acu + danmu_acu) * 0.8)
    danmu_only_acu = min(_ratio_score(_number(row, "danmu_only"), danmu_only_ref), 50_000)
    danmu_only_acu = min(danmu_only_acu, (avg_com_acu + danmu_acu) * 0.8)
    danmu_new_acu = min(_ratio_score(_number(row, "danmu_new"), danmu_new_ref), 50_000)
    # Preserve the historical expression, including its unusual cap source.
    danmu_new_acu = min(danmu_only_acu, (avg_com_acu + danmu_acu) * 0.8)
    score = (
        avg_com_acu * 0.4
        + danmu_acu * 0.3
        + dingyue_acu * 0.05
        + danmu_only_acu * 0.15
        + danmu_new_acu * 0.10
    )
    return round(score * 0.38 / 50) * 50


def _series_score(row: Mapping[str, Any], prefix: str, cap_first: float, cap_other: float) -> float:
    pieces = []
    for suffix in ("0", "10", "20", "30"):
        value = _number(row, f"{prefix}_{suffix}")
        cap = cap_first if suffix == "0" else cap_other
        pieces.append(min(_ratio_score(value, [28_000.0, 9_000.0, 3_800.0]), cap))
    return pieces[0] * 0.1 + pieces[1] * 0.35 + pieces[2] * 0.35 + pieces[3] * 0.2


def estimate_douyin(row: Mapping[str, Any]) -> float:
    online = _series_score(row, "online", 100_000, 150_000)
    online_users = _series_score(row, "onlineu", 100_000, 150_000)
    average_online = 0.3 * online + 0.7 * online_users
    fans = _number(row, "fans")
    fan_score = 0.0
    if fans > 10:
        fan_total = min(_ratio_score(fans, [9_000_000.0, 1_500_000.0, 850_000.0]), 150_000)
        fan_add = min(
            _ratio_score(max(_number(row, "fans_add"), 0), [300_000.0, 75_000.0, 38_000.0]),
            150_000,
        )
        fan_score = fan_total * 0.4 + fan_add * 0.6
        score = average_online * 0.9 + fan_score * 0.1
    else:
        score = average_online
    return round(score * 0.83 / 10) * 10


def estimate_kuaishou(row: Mapping[str, Any]) -> float:
    danmu_ref = [17_000.0, 3_800.0, 1_850.0]
    cap = 100_000.0
    pieces = []
    for suffix in ("0", "10", "20", "30"):
        value = _number(row, f"onlineu_{suffix}")
        pieces.append(min(_ratio_score(value, danmu_ref), cap))
    score = pieces[0] * 0.1 + pieces[1] * 0.35 + pieces[2] * 0.35 + pieces[3] * 0.2
    # The latest archived script applied three cumulative scale factors.
    return round(score * 0.8 * 0.85 * 0.85 / 50) * 50


def estimate_acu_and_rising(row: Mapping[str, Any], platform: str) -> tuple[float, float]:
    if platform == "douyu":
        return estimate_douyu(row), estimate_douyu(row, rising=True)
    if platform == "bilibili":
        return estimate_bilibili(row), estimate_bilibili(row, rising=True)
    if platform == "douyin_web":
        value = estimate_douyin(row)
        return value, value
    if platform == "kuaishou":
        value = estimate_kuaishou(row)
        return value, value
    raise ValueError(f"Unsupported platform: {platform}")
