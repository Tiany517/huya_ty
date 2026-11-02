from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import shutil
from pathlib import Path
from typing import Any, Iterable

from docx import Document
from openpyxl import load_workbook


PROJECT_DIR = Path(__file__).resolve().parents[1]
ARTIFACTS = PROJECT_DIR / "artifacts"
ZH = ARTIFACTS / "zh"
EN = ARTIFACTS / "en"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_csv(path: Path, rows: Iterable[dict[str, Any]], fields: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as target:
        writer = csv.DictWriter(target, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as source:
        return list(csv.DictReader(source))


def copy_tree_files(source: Path, target: Path) -> list[Path]:
    copied: list[Path] = []
    for item in sorted(source.rglob("*")):
        if not item.is_file():
            continue
        destination = target / item.relative_to(source)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(item, destination)
        copied.append(item)
    return copied


def copy_one(source: Path, target: Path) -> Path:
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    return source


def number(value: Any) -> float | None:
    if value is None or value == "":
        return None
    if isinstance(value, (int, float)):
        return float(value)
    text = str(value).strip().replace(",", "").replace("%", "")
    try:
        return float(text)
    except ValueError:
        return None


def build_world_championship_funnel(source_dir: Path) -> list[dict[str, Any]]:
    workbook = load_workbook(
        source_dir / "最终交付" / "1_1 流量和商业化是否良性" / "2526世锦赛DAU和拉新用户漏斗分析.xlsx",
        data_only=True,
        read_only=True,
    )
    rows: list[dict[str, Any]] = []
    for season, sheet in [
        ("2025", "2025世锦赛DAU和拉新用户漏斗_Final"),
        ("2026", "2026世锦赛DAU和拉新用户漏斗_Final"),
    ]:
        for source_label, group, users, video, xinxiu, tipping in workbook[sheet].iter_rows(min_row=2, values_only=True):
            if number(users) is None:
                continue
            rows.append(
                {
                    "season": season,
                    "source_row_label": source_label,
                    "user_group": group,
                    "users_wan": number(users),
                    "video_viewers_wan": number(video),
                    "xinxiu_viewers_wan": number(xinxiu),
                    "tipping_users_wan": number(tipping),
                    "video_view_rate_pct": number(video) / number(users) * 100,
                    "xinxiu_viewers_per_100_video_viewers": number(xinxiu) / number(video) * 100,
                    "tipping_users_per_100_video_viewers": number(tipping) / number(video) * 100,
                    "tipping_rate_pct": number(tipping) / number(users) * 100,
                }
            )
    workbook.close()
    return rows


def build_world_championship_path(source_dir: Path) -> list[dict[str, Any]]:
    workbook = load_workbook(
        source_dir / "最终交付" / "2_1 即时转化" / "世锦赛期间_拉新用户和非拉新用户的转换漏斗对比.xlsx",
        data_only=True,
        read_only=True,
    )
    rows: list[dict[str, Any]] = []
    for season, sheet in [
        ("2025", "2425世锦赛斯诺克和非斯诺克新用户漏斗分析"),
        ("2026", "2526世锦赛斯诺克和非斯诺克新用户漏斗分析"),
    ]:
        for values in workbook[sheet].iter_rows(min_row=2, values_only=True):
            label, group, users, video, video_xinxiu, video_pay, tipping, no_video, no_video_xinxiu, no_video_pay = values
            if number(users) is None:
                continue
            rows.append(
                {
                    "season": season,
                    "snooker_new_user_group": group,
                    "new_users_wan": number(users),
                    "video_viewers_wan": number(video),
                    "video_to_xinxiu_users_wan": number(video_xinxiu),
                    "video_to_tippers_wan": number(video_pay),
                    "all_tippers_wan": number(tipping),
                    "no_video_users_wan": number(no_video),
                    "no_video_to_xinxiu_users_wan": number(no_video_xinxiu),
                    "no_video_to_tippers_wan": number(no_video_pay),
                    "video_view_rate_pct": number(video) / number(users) * 100,
                    "video_to_xinxiu_rate_pct": number(video_xinxiu) / number(video) * 100,
                    "video_to_tipping_rate_pct": number(video_pay) / number(video) * 100,
                    "overall_tipping_rate_pct": number(tipping) / number(users) * 100,
                }
            )
    workbook.close()
    return rows


def build_wc_tipping(source_dir: Path) -> list[dict[str, Any]]:
    workbook = load_workbook(
        source_dir / "最终交付" / "2_1 即时转化" / "世锦赛期间_拉新用户和非拉新用户的付费对比.xlsx",
        data_only=True,
        read_only=True,
    )
    rows: list[dict[str, Any]] = []
    for season, sheet in [
        ("2025", "2425世锦赛斯诺克和非斯诺克新用户人均打赏比较"),
        ("2026", "2526世锦赛斯诺克和非斯诺克新用户人均打赏比较"),
    ]:
        for values in workbook[sheet].iter_rows(min_row=2, values_only=True):
            event_label, event_date, user_label, users, tippers, rate, amount_wan, avg_total, avg_per_tipper = values
            if number(users) is None:
                continue
            rows.append(
                {
                    "season": season,
                    "source_event_label": event_label,
                    "source_event_date": event_date,
                    "user_group": user_label,
                    "new_users_wan": number(users),
                    "tipping_users_wan": number(tippers),
                    "tipping_rate_pct": number(rate) * 100,
                    "total_tipping_amount_wan_cny": number(amount_wan),
                    "average_spend_per_user_cny": number(avg_total),
                    "average_spend_per_tipper_cny": number(avg_per_tipper),
                }
            )
    workbook.close()
    return rows


def build_unique_audience_share(source_dir: Path) -> list[dict[str, Any]]:
    rows = read_csv(source_dir / "最终交付" / "25和26观看视频和直播用户占比对比.csv")
    output = []
    for row in rows:
        output.append(
            {
                "season": "2025" if "2025" in row["label"] else "2026",
                "source_label": row["label"],
                "new_users": number(row["total_laxin_cnt"]),
                "video_viewer_share_pct": number(row["video_watch_ratio"]) * 100,
                "live_viewer_share_pct": number(row["live_watch_ratio"]) * 100,
            }
        )
    return output


def retention_from_workbook(path: Path, baseline: str) -> list[dict[str, Any]]:
    workbook = load_workbook(path, data_only=True, read_only=True)
    output: list[dict[str, Any]] = []
    sheets = [sheet for sheet in workbook.worksheets if sheet.title != "差异分析"]
    for sheet in sheets:
        if "2526" in sheet.title:
            season = "2025/26"
        elif "2425" in sheet.title:
            season = "2024/25"
        else:
            raise ValueError(f"Cannot infer season from sheet title: {path.name} / {sheet.title}")
        for phase, tournament, dates, baseline_users, retained_users, rate in sheet.iter_rows(min_row=2, values_only=True):
            if tournament is None:
                continue
            output.append(
                {
                    "baseline_event": baseline,
                    "season": season,
                    "phase": phase,
                    "target_event": tournament,
                    "target_dates": dates,
                    "baseline_new_users": number(baseline_users),
                    "retained_users": number(retained_users),
                    "retention_rate_pct": number(rate) * 100,
                }
            )
    workbook.close()
    return output


def build_stage_retention(source_dir: Path) -> list[dict[str, Any]]:
    retention_dir = source_dir / "最终交付" / "1_2 各个阶段到世锦赛留存是否变化"
    specs = [
        ("上海大师赛", retention_dir / "上海大师赛" / "上海大师赛留存差异分析.xlsx"),
        ("英锦赛", retention_dir / "英锦赛" / "英锦赛留存差异分析.xlsx"),
        ("英格兰公开赛", retention_dir / "英格兰公开赛" / "英格兰公开赛留存差异分析.xlsx"),
        ("沙特大师赛", retention_dir / "沙特大师赛" / "沙特大师赛留存差异分析.xlsx"),
    ]
    rows: list[dict[str, Any]] = []
    for baseline, path in specs:
        rows.extend(retention_from_workbook(path, baseline))

    masters = read_csv(retention_dir / "大师赛邀请赛" / "大师赛邀请赛到世锦赛留存情况_2425_2526.csv")
    for row in masters:
        rows.append(
            {
                "baseline_event": "大师赛",
                "season": row["season"].strip(),
                "phase": row["phase_tag"].strip(),
                "target_event": row["tournament"].strip(),
                "target_dates": row["tournament_date"].strip(),
                "baseline_new_users": number(row[" lx_ucnt "]),
                "retained_users": number(row[" lc_ucnt "]),
                "retention_rate_pct": number(row["lc_rate"]),
            }
        )
    phase_order = {"基准期": 0, "短期": 1, "中期": 2, "长期": 3}
    rows.sort(
        key=lambda item: (
            item["baseline_event"],
            item["season"],
            phase_order.get(item["phase"], 99),
        )
    )
    return rows


def build_video_affinity(source_dir: Path) -> list[dict[str, Any]]:
    path = source_dir / "最终交付" / "斯诺克拉新视频偏好TGI对比.xlsx"
    workbook = load_workbook(path, data_only=True, read_only=True)
    sheet = workbook["差异"]
    rows = list(sheet.iter_rows(values_only=True))
    header_index = next(i for i, row in enumerate(rows) if row[0] == "user_group" and "视频观看次数占比差异" in row)
    headers = rows[header_index]
    index = {value: position for position, value in enumerate(headers) if value is not None}
    output = []
    for row in rows[header_index + 1 :]:
        category = row[index["品类"]]
        if category is None:
            continue
        output.append(
            {
                "category": category,
                "snooker_video_view_share_pct": number(row[index["斯诺克新用户视频观看次数占比"]]) * 100,
                "nonsnooker_video_view_share_pct": number(row[index["非斯诺克新用户视频观看次数占比"]]) * 100,
                "view_share_difference_pp": number(row[index["视频观看次数占比差异"]]),
                "snooker_video_duration_share_pct": number(row[index["斯诺克新用户视频观看时长占比"]]) * 100,
                "nonsnooker_video_duration_share_pct": number(row[index["非斯诺克新用户视频观看时长占比"]]) * 100,
                "duration_share_difference_pp": number(row[index["视频观看时长占比差异"]]),
            }
        )
    workbook.close()
    output.sort(key=lambda item: item["view_share_difference_pp"] or -10**9, reverse=True)
    return output[:20]


def build_content_supply(source_dir: Path) -> list[dict[str, Any]]:
    rows = read_csv(source_dir / "最终交付" / "关键视频内容供给数量及占比.csv")
    output = []
    for row in rows:
        output.append(
            {
                "category": row["game_name"].strip(),
                "video_count": number(row[" video_cnt "]),
                "share_within_target_categories_pct": number(row["ratio_in_target"]),
                "share_of_all_huya_video_pct": number(row["ratio_in_all"]),
            }
        )
    return output


def build_profile_clusters(source_dir: Path) -> list[dict[str, Any]]:
    path = source_dir / "世锦赛拉新用户画像分析" / "斯诺克世锦赛拉新用户画像报告_V3.docx"
    document = Document(path)
    table = document.tables[6]
    rows = [[cell.text.strip() for cell in row.cells] for row in table.rows]
    clusters = rows[0][1:]
    metrics = {row[0]: row[1:] for row in rows[1:]}
    counts = [int(value.replace(",", "")) for value in metrics["人数"]]
    total = sum(counts)
    output = []
    for index, cluster in enumerate(clusters):
        output.append(
            {
                "cluster_name": cluster,
                "users": counts[index],
                "share_pct": counts[index] / total * 100,
                "male_share": metrics["男性占比"][index],
                "average_age": metrics["平均年龄"][index],
                "top_age_band": metrics["Top 年龄层"][index],
                "car_ownership": metrics["有车率"][index],
                "home_ownership": metrics["有房率"][index],
                "device_average_price": metrics["设备均价"][index],
                "ios_share": metrics["iOS占比"][index],
                "top_device": metrics["Top 设备"][index],
                "wealth_score": metrics["财富评分"][index],
                "high_activity_game_share": metrics["游戏高活跃"][index],
                "top_primary_app_affinity": metrics["Top App一级"][index],
                "top_secondary_app_affinity": metrics["Top App二级"][index],
                "married_share": metrics["已婚率"][index],
                "parenting_share": metrics["育儿率"][index],
                "value_rating_from_report": metrics["价值评级"][index],
                "risk_flag": "suspected_fake_registration_not_verified" if "小米视频派" in cluster else "",
            }
        )
    return output


def quality_findings() -> list[dict[str, Any]]:
    return [
        {
            "finding_id": "SNK-QF-01",
            "severity": "medium",
            "finding": "The 2025 World Championship final CSV and workbook sheet carry a 2026 row label while their values occupy the 2024/25 comparison slot. The migrated summary derives season from the sheet position and records the source label separately.",
            "impact": "Readers must not infer the season from the embedded row label alone.",
            "status": "documented_and_normalized_in_summary",
        },
        {
            "finding_id": "SNK-QF-02",
            "severity": "high",
            "finding": "The file named LPL1_LPL2_王者_斯诺克_转化情况.csv contains the 2025/2026 World Championship video-versus-live ratios rather than its promised four-event conversion comparison.",
            "impact": "The file is retained for provenance but excluded from the normalized comparison tables.",
            "status": "quarantined_from_analysis",
        },
        {
            "finding_id": "SNK-QF-03",
            "severity": "medium",
            "finding": "Shanghai Masters baseline denominators differ across outputs: 91,295 versus 87,485 in 2024/25, and 278,071 versus 265,175 in 2025/26.",
            "impact": "Event-to-event retention rates are directionally useful, but absolute retained counts should not be combined until the denominator rule is confirmed.",
            "status": "open_requires_business_dictionary",
        },
        {
            "finding_id": "SNK-QF-04",
            "severity": "high",
            "finding": "The profile report flags 358 of 1,086 unique users (33.0%) as a likely fake-registration cluster based on implausible identical wealth, device, education, and game fields.",
            "impact": "The suspicion is not validated by risk-control or device/IP evidence. It must remain a hypothesis; excluding 33% from ROI or DAU without that validation would be unsupported.",
            "status": "open_high_risk_hypothesis",
        },
        {
            "finding_id": "SNK-QF-05",
            "severity": "medium",
            "finding": "The final deck contains narrative values including ROI 0.9 and +7.5% that cannot be independently reproduced from the retained anonymous workbooks and CSVs.",
            "impact": "These values can be quoted only as historical deck statements, not as independently verified calculations.",
            "status": "unreconciled_source_narrative",
        },
        {
            "finding_id": "SNK-QF-06",
            "severity": "medium",
            "finding": "A playhouse tipping-rate workbook contains a change row whose ratios are not expressed as percentage points consistently.",
            "impact": "The normalized package does not use that change row for a conclusion.",
            "status": "excluded_from_summary_calculations",
        },
        {
            "finding_id": "SNK-QF-07",
            "severity": "high",
            "finding": "Large source workbooks, a 19,456-row user-level retention CSV containing user_uid, and the user-profile feature CSV containing user_ukey are not uploaded.",
            "impact": "The package preserves their hashes and exclusion reasons but cannot rebuild those user-level analyses without the local sources.",
            "status": "excluded_by_privacy_boundary",
        },
    ]


def translation_maps() -> dict[str, dict[str, str]]:
    return {
        "user_group": {"看赛用户": "event viewers", "拉新用户": "new users"},
        "snooker_group": {"斯诺克拉新用户": "snooker new users", "非斯诺克拉新用户": "non-snooker new users"},
    }


def translate_rows(rows: list[dict[str, Any]], mapping: dict[str, str], field: str, translated_field: str) -> list[dict[str, Any]]:
    return [{**row, translated_field: mapping.get(row[field], row[field])} for row in rows]


def build_source_manifest(
    source_dir: Path,
    copied_final: list[Path],
    copied_sql: list[Path],
    copied_supplemental: list[Path],
    copied_profile: list[Path],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    final_root = source_dir / "最终交付"
    included: dict[Path, list[tuple[str, str, str]]] = {}
    for path in copied_final:
        included.setdefault(path.resolve(), []).append(
            (
                str((PROJECT_DIR / "artifacts" / "final-delivery" / path.relative_to(final_root)).relative_to(PROJECT_DIR)).replace("\\", "/"),
                "已复核的最终交付；保留匿名汇总、SQL、最终汇报和源文件哈希",
                "reviewed_final_delivery: aggregate CSV/XLSX/SQL/PPTX retained as-is",
            )
        )
    for path in copied_sql:
        included.setdefault(path.resolve(), []).append(
            (
                str((PROJECT_DIR / "sql" / "source" / path.relative_to(source_dir)).relative_to(PROJECT_DIR)).replace("\\", "/"),
                "保留项目 SQL 原文；不包含查询结果数据",
                "project_sql_source: query text retained without result data",
            )
        )
    for path in copied_supplemental:
        included.setdefault(path.resolve(), []).append(
            (
                str((PROJECT_DIR / "artifacts" / "supplemental-results" / path.name).relative_to(PROJECT_DIR)).replace("\\", "/"),
                "已复核的补充匿名汇总结果",
                "reviewed_supplemental_aggregate_result",
            )
        )
    for path in copied_profile:
        target = (
            PROJECT_DIR / "scripts" / "profile-analysis" / path.name
            if path.suffix == ".py"
            else PROJECT_DIR / "artifacts" / "supplemental-results" / path.name
        )
        if path.suffix == ".py":
            reason_zh = "迁移适配版分析代码：保留算法逻辑，将本机绝对路径改为 `--data`/`--output-dir` 参数"
            reason_en = "Migration-adapted analysis code: algorithm logic retained; local absolute paths replaced by --data/--output-dir arguments"
        else:
            reason_zh = "保留画像报告；不保留用户级特征行"
            reason_en = "Reviewed profile report retained; raw user feature rows excluded"
        included.setdefault(path.resolve(), []).append(
            (
                str(target.relative_to(PROJECT_DIR)).replace("\\", "/"),
                reason_zh,
                reason_en,
            )
        )

    zh_rows: list[dict[str, Any]] = []
    en_rows: list[dict[str, Any]] = []
    for path in sorted(source_dir.rglob("*"), key=lambda item: str(item).lower()):
        if not path.is_file():
            continue
        relative = path.relative_to(source_dir).as_posix()
        resolved = path.resolve()
        common = {
            "source_path": f"<source-root>/{relative}",
            "bytes": path.stat().st_size,
            "sha256": sha256(path),
        }
        if resolved not in included:
            repo_path = ""
            disposition_zh = "排除"
            disposition_en = "excluded"
            lower = relative.lower()
            if path.suffix.lower() == ".ipynb":
                reason_zh = "Notebook 可能内嵌用户级输出，未复核，不纳入"
                reason_en = "Notebook may contain embedded user-level output and was not reviewed"
            elif path.suffix.lower() in {".xlsx", ".xls", ".csv"} and any(token in lower for token in ["拉新用户漏斗_重要", "拉新用户行为监测_重要", "上海拉新用户到世锦赛", "画像数据.csv"]):
                reason_zh = "用户级明细或大体积原始导出，按隐私边界排除"
                reason_en = "User-level detail or large raw export excluded by the privacy boundary"
            elif "月报交付_0605" in lower:
                reason_zh = "含具名主播/关联影响中间材料或与主线重复，未纳入核心结果集"
                reason_en = "Named-streamer/intermediate material or duplicate workstream content; not part of the core result set"
            else:
                reason_zh = "未纳入项目核心结果集的中间稿、旧稿或非必要文件"
                reason_en = "Intermediate, superseded, or nonessential file outside the core result set"
            zh_rows.append({**common, "repo_path": repo_path, "repo_sha256": "", "disposition": disposition_zh, "reason": reason_zh})
            en_rows.append({**common, "repo_path": repo_path, "repo_sha256": "", "disposition": disposition_en, "reason": reason_en})
            continue
        for repo_path, reason_zh, reason_en in included[resolved]:
            repo_hash = sha256(PROJECT_DIR / repo_path)
            zh_rows.append({**common, "repo_path": repo_path, "repo_sha256": repo_hash, "disposition": "纳入", "reason": reason_zh})
            en_rows.append({**common, "repo_path": repo_path, "repo_sha256": repo_hash, "disposition": "included", "reason": reason_en})
    return zh_rows, en_rows


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", type=Path, required=True)
    args = parser.parse_args()
    source_dir = args.source_dir.resolve()

    final_source = source_dir / "最终交付"
    final_target = ARTIFACTS / "final-delivery"
    copied_final = copy_tree_files(final_source, final_target)

    copied_sql = []
    for path in sorted(source_dir.rglob("*.sql")):
        copied_sql.append(
            copy_one(path, PROJECT_DIR / "sql" / "source" / path.relative_to(source_dir))
        )

    supplemental_names = [
        "漏斗留存差异分析_25世锦赛_25上海大师赛_25英锦赛_26大师赛_26世锦赛.xlsx",
        "上海大师赛拉新用户短中长期留存情况.xlsx",
        "斯诺克及非斯诺克拉新人数对比.csv",
        "世锦赛拉新用户画像分析/斯诺克秀场打赏率和观看率.xlsx",
    ]
    copied_supplemental = []
    for name in supplemental_names:
        source = source_dir / name
        copied_supplemental.append(copy_one(source, ARTIFACTS / "supplemental-results" / source.name))

    profile_dir = source_dir / "世锦赛拉新用户画像分析"
    profile_py = sorted(profile_dir.glob("*.py"))
    copied_profile = []
    for source in profile_py:
        target = PROJECT_DIR / "scripts" / "profile-analysis" / source.name
        if not target.is_file():
            raise FileNotFoundError(
                f"Sanitized profile script template is missing: {target.name}. "
                "Add the migration-adapted script before rebuilding."
            )
        copied_profile.append(source)
    report_docx = profile_dir / "斯诺克世锦赛拉新用户画像报告_V3.docx"
    copied_profile.append(copy_one(report_docx, ARTIFACTS / "supplemental-results" / report_docx.name))

    watch = build_world_championship_funnel(source_dir)
    path = build_world_championship_path(source_dir)
    tipping = build_wc_tipping(source_dir)
    unique_share = build_unique_audience_share(source_dir)
    retention = build_stage_retention(source_dir)
    affinity = build_video_affinity(source_dir)
    supply = build_content_supply(source_dir)
    clusters = build_profile_clusters(source_dir)
    findings = quality_findings()
    maps = translation_maps()

    write_csv(
        ZH / "世锦赛受众与漏斗.csv",
        watch,
        ["season", "source_row_label", "user_group", "users_wan", "video_viewers_wan", "xinxiu_viewers_wan", "tipping_users_wan", "video_view_rate_pct", "xinxiu_viewers_per_100_video_viewers", "tipping_users_per_100_video_viewers", "tipping_rate_pct"],
    )
    write_csv(
        EN / "world-championship-audience-funnel.csv",
        translate_rows(watch, maps["user_group"], "user_group", "user_group_en"),
        ["season", "source_row_label", "user_group", "user_group_en", "users_wan", "video_viewers_wan", "xinxiu_viewers_wan", "tipping_users_wan", "video_view_rate_pct", "xinxiu_viewers_per_100_video_viewers", "tipping_users_per_100_video_viewers", "tipping_rate_pct"],
    )
    write_csv(
        ZH / "世锦赛拉新转化路径.csv",
        path,
        ["season", "snooker_new_user_group", "new_users_wan", "video_viewers_wan", "video_to_xinxiu_users_wan", "video_to_tippers_wan", "all_tippers_wan", "no_video_users_wan", "no_video_to_xinxiu_users_wan", "no_video_to_tippers_wan", "video_view_rate_pct", "video_to_xinxiu_rate_pct", "video_to_tipping_rate_pct", "overall_tipping_rate_pct"],
    )
    write_csv(
        EN / "world-championship-new-user-path.csv",
        translate_rows(path, maps["snooker_group"], "snooker_new_user_group", "new_user_group_en"),
        ["season", "snooker_new_user_group", "new_user_group_en", "new_users_wan", "video_viewers_wan", "video_to_xinxiu_users_wan", "video_to_tippers_wan", "all_tippers_wan", "no_video_users_wan", "no_video_to_xinxiu_users_wan", "no_video_to_tippers_wan", "video_view_rate_pct", "video_to_xinxiu_rate_pct", "video_to_tipping_rate_pct", "overall_tipping_rate_pct"],
    )
    write_csv(
        ZH / "世锦赛拉新付费.csv",
        tipping,
        ["season", "source_event_label", "source_event_date", "user_group", "new_users_wan", "tipping_users_wan", "tipping_rate_pct", "total_tipping_amount_wan_cny", "average_spend_per_user_cny", "average_spend_per_tipper_cny"],
    )
    write_csv(
        EN / "world-championship-tipping.csv",
        translate_rows(tipping, maps["snooker_group"], "user_group", "user_group_en"),
        ["season", "source_event_label", "source_event_date", "user_group", "user_group_en", "new_users_wan", "tipping_users_wan", "tipping_rate_pct", "total_tipping_amount_wan_cny", "average_spend_per_user_cny", "average_spend_per_tipper_cny"],
    )
    unique_share_fields = ["season", "source_label", "new_users", "video_viewer_share_pct", "live_viewer_share_pct"]
    write_csv(ZH / "世锦赛拉新用户视频直播覆盖率.csv", unique_share, unique_share_fields)
    write_csv(EN / "world-championship-unique-audience-share.csv", unique_share, unique_share_fields)
    retention_fields = ["baseline_event", "season", "phase", "target_event", "target_dates", "baseline_new_users", "retained_users", "retention_rate_pct"]
    write_csv(ZH / "赛事到世锦赛留存.csv", retention, retention_fields)
    write_csv(EN / "event-to-world-championship-retention.csv", retention, retention_fields)
    affinity_fields = ["category", "snooker_video_view_share_pct", "nonsnooker_video_view_share_pct", "view_share_difference_pp", "snooker_video_duration_share_pct", "nonsnooker_video_duration_share_pct", "duration_share_difference_pp"]
    write_csv(ZH / "斯诺克视频偏好.csv", affinity, affinity_fields)
    write_csv(EN / "snooker-video-affinity.csv", affinity, affinity_fields)
    supply_fields = ["category", "video_count", "share_within_target_categories_pct", "share_of_all_huya_video_pct"]
    write_csv(ZH / "关键视频内容供给.csv", supply, supply_fields)
    write_csv(EN / "key-video-content-supply.csv", supply, supply_fields)
    cluster_fields = ["cluster_name", "users", "share_pct", "male_share", "average_age", "top_age_band", "car_ownership", "home_ownership", "device_average_price", "ios_share", "top_device", "wealth_score", "high_activity_game_share", "top_primary_app_affinity", "top_secondary_app_affinity", "married_share", "parenting_share", "value_rating_from_report", "risk_flag"]
    write_csv(ZH / "拉新用户画像聚类.csv", clusters, cluster_fields)
    write_csv(EN / "new-user-profile-clusters.csv", clusters, cluster_fields)

    zh_manifest, en_manifest = build_source_manifest(
        source_dir, copied_final, copied_sql, copied_supplemental, copied_profile
    )
    manifest_fields = ["source_path", "bytes", "sha256", "repo_path", "repo_sha256", "disposition", "reason"]
    write_csv(ZH / "来源清单.csv", zh_manifest, manifest_fields)
    write_csv(EN / "source-manifest.csv", en_manifest, manifest_fields)

    zh_findings = [
        {
            "finding_id": item["finding_id"],
            "severity": item["severity"],
            "finding": {
                "SNK-QF-01": "2025 世锦赛最终 CSV 和工作簿页签内嵌为“2026 世锦赛期间”，但数值实际位于 2024/25 对照槽位；本项目按页签位置识别赛季，并保留源标签。",
                "SNK-QF-02": "`LPL1_LPL2_王者_斯诺克_转化情况.csv` 实际内容是 2025/2026 世锦赛视频与直播观看占比，不是文件名承诺的四赛事转化比较。",
                "SNK-QF-03": "上海大师赛基准人数在多个结果间冲突：2024/25 为 91,295 与 87,485；2025/26 为 278,071 与 265,175。",
                "SNK-QF-04": "画像报告把 1,086 名唯一用户中的 358 人（33.0%）标记为疑似虚假注册，但目前没有风控或设备/IP 证据，不能据此直接剔除 33% ROI 或 DAU。",
                "SNK-QF-05": "最终汇报中的 ROI 0.9 和 +7.5% 无法用本项目保留的匿名工作簿和 CSV 独立复算。",
                "SNK-QF-06": "秀场打赏率工作簿中的“变化”行没有统一使用百分点，可能把比率变化误写成比例变化；本项目不使用该变化行下结论。",
                "SNK-QF-07": "两个超大原始工作簿、含 `user_uid` 的 19,456 行留存 CSV 和含 `user_ukey` 的画像特征 CSV 均未上传。",
            }[item["finding_id"]],
            "impact": {
                "SNK-QF-01": "不能只依赖行内标签判断赛季。",
                "SNK-QF-02": "该文件仅作来源证据保留，已从标准化比较表隔离。",
                "SNK-QF-03": "方向性留存可参考，绝对留存人数在确认分母口径前不能混用。",
                "SNK-QF-04": "疑似造假仍是待验证假设，不能升级为已证实结论。",
                "SNK-QF-05": "只能作为历史汇报原文引用，不能写成已复核计算。",
                "SNK-QF-06": "避免引用错误变化幅度。",
                "SNK-QF-07": "新电脑可在有源文件时重建用户级分析；仅靠 GitHub 不能重建。",
            }[item["finding_id"]],
            "status": item["status"],
        }
        for item in findings
    ]
    findings_fields = ["finding_id", "severity", "finding", "impact", "status"]
    write_csv(ZH / "质量问题.csv", zh_findings, findings_fields)
    write_csv(EN / "quality-findings.csv", findings, findings_fields)

    summary = {
        "project": "snooker-event-review",
        "source_latest_modified": max(
            path.stat().st_mtime for path in source_dir.rglob("*") if path.is_file()
        ),
        "source_file_count": sum(1 for path in source_dir.rglob("*") if path.is_file()),
        "included_final_delivery_files": len(copied_final),
        "included_sql_files": len(copied_sql),
        "included_supplemental_files": len(copied_supplemental),
        "included_profile_files": len(copied_profile),
        "world_championship_2025_viewers_wan": next(
            row["users_wan"] for row in watch if row["season"] == "2025" and row["user_group"] == "看赛用户"
        ),
        "world_championship_2026_viewers_wan": next(
            row["users_wan"] for row in watch if row["season"] == "2026" and row["user_group"] == "看赛用户"
        ),
        "world_championship_2025_new_users_wan": next(
            row["users_wan"] for row in watch if row["season"] == "2025" and row["user_group"] == "拉新用户"
        ),
        "world_championship_2026_new_users_wan": next(
            row["users_wan"] for row in watch if row["season"] == "2026" and row["user_group"] == "拉新用户"
        ),
        "four_event_weighted_world_championship_retention_pct": {
            "2024/25": 42.33675701007576,
            "2025/26": 39.41998331744519,
        },
        "profile_unique_users": sum(row["users"] for row in clusters),
        "profile_suspected_fake_share_pct": next(row["share_pct"] for row in clusters if "小米视频派" in row["cluster_name"]),
        "quality_findings": len(findings),
        "raw_user_level_data_included": False,
        "status": "reviewed_with_documented_label_denominator_and_profile_risks",
    }
    (ARTIFACTS / "project_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
