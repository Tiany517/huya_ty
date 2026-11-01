#!/usr/bin/env python3
"""Build safe aggregate artifacts for the user-profile review.

The source folder contains raw user identifiers. This script never writes a
source row. It exports reviewed TGI tables, aggregates user-profile sample
labels, records source hashes, and captures static SQL defects.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import pandas as pd


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = PROJECT_ROOT / "artifacts" / "anonymous-summary"


TGI_FILES = [
    {
        "source": Path("苹果安卓鸿蒙用户用户画像/tgi_all_pairs.csv"),
        "cn": Path("tgi/device-all-pairs.csv"),
        "en": Path("tgi/device-all-pairs.en.csv"),
        "en_headers": [
            "dimension",
            "value",
            "harmony_pct",
            "apple_pct",
            "harmony_users",
            "ios_users",
            "comparison",
            "tgi",
            "android_pct",
            "android_users",
        ],
    },
    {
        "source": Path("苹果安卓鸿蒙用户用户画像/tgi_hm_vs_pg.csv"),
        "cn": Path("tgi/device-harmony-vs-ios.csv"),
        "en": Path("tgi/device-harmony-vs-ios.en.csv"),
        "en_headers": [
            "dimension",
            "value",
            "harmony_pct",
            "apple_pct",
            "harmony_users",
            "ios_users",
            "comparison",
            "tgi",
        ],
    },
    {
        "source": Path("苹果安卓鸿蒙用户用户画像/tgi_hm_vs_az.csv"),
        "cn": Path("tgi/device-harmony-vs-android.csv"),
        "en": Path("tgi/device-harmony-vs-android.en.csv"),
        "en_headers": [
            "dimension",
            "value",
            "harmony_pct",
            "android_pct",
            "harmony_users",
            "android_users",
            "comparison",
            "tgi",
        ],
    },
    {
        "source": Path("苹果安卓鸿蒙用户用户画像/tgi_az_vs_pg.csv"),
        "cn": Path("tgi/device-android-vs-ios.csv"),
        "en": Path("tgi/device-android-vs-ios.en.csv"),
        "en_headers": [
            "dimension",
            "value",
            "android_pct",
            "apple_pct",
            "android_users",
            "ios_users",
            "comparison",
            "tgi",
        ],
    },
    {
        "source": Path("snooker_tgi_analysis_v2/tgi_full.csv"),
        "cn": Path("tgi/snooker-watchers-v2.csv"),
        "en": Path("tgi/snooker-watchers-v2.en.csv"),
        "en_headers": [
            "dimension",
            "value",
            "target_pct",
            "control_pct",
            "target_users",
            "control_users",
            "tgi",
        ],
    },
    {
        "source": Path("世锦赛观看用户画像分析/tgi_full.csv"),
        "cn": Path("tgi/world-championship-watchers.csv"),
        "en": Path("tgi/world-championship-watchers.en.csv"),
        "en_headers": [
            "dimension",
            "value",
            "target_pct",
            "control_pct",
            "target_users",
            "control_users",
            "tgi",
        ],
    },
    {
        "source": Path("wc_10min_user_profile_analysis/tgi_full.csv"),
        "cn": Path("tgi/world-championship-viewers-10min.csv"),
        "en": Path("tgi/world-championship-viewers-10min.en.csv"),
        "en_headers": [
            "dimension",
            "value",
            "target_pct",
            "control_pct",
            "target_users",
            "control_users",
            "tgi",
        ],
    },
]


REPORT_PATHS = {
    "苹果安卓鸿蒙用户用户画像/鸿蒙安卓苹果三组用户画像对比分析报告.docx": "reports/device-profile-three-groups-legacy.docx",
    "苹果安卓鸿蒙用户用户画像/鸿蒙安卓苹果三组用户画像对比分析报告_V2.docx": "reports/device-profile-harmony-vs-android-v2.docx",
    "斯诺克世锦赛用户画像TGI分析报告_1779168440.docx": "reports/snooker-world-championship-tgi.docx",
    "wc_10min_user_profile_analysis/世锦赛10分钟以上观看用户画像分析报告.docx": "reports/world-championship-viewers-10min.docx",
}

SQL_PATHS = {
    "用户画像取数/鸿蒙安卓和苹果用户的画像.sql": "sql/鸿蒙安卓和苹果用户的画像.sql",
    "用户画像取数/观看过世锦赛和未观看过世锦赛的画像.sql": "sql/观看过世锦赛和未观看过世锦赛的画像.sql",
    "用户画像取数/观看过世锦赛且单日观看时长最长的用户.sql": "sql/观看过世锦赛且单日观看时长最长的用户.sql",
}


def write_csv(frame: pd.DataFrame, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(path, index=False, encoding="utf-8-sig", lineterminator="\n")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def copy_tgi_tables(source_dir: Path, output_dir: Path) -> list[dict[str, object]]:
    records: list[dict[str, object]] = []
    for spec in TGI_FILES:
        source_path = source_dir / spec["source"]
        frame = pd.read_csv(source_path, encoding="utf-8-sig")
        if len(frame.columns) != len(spec["en_headers"]):
            raise ValueError(f"Unexpected column count in {source_path}")
        write_csv(frame, output_dir / spec["cn"])
        english = frame.copy()
        english.columns = spec["en_headers"]
        write_csv(english, output_dir / spec["en"])
        records.append(
            {
                "source": str(spec["source"]),
                "repository_path_cn": "projects/user-profile-analysis/" + spec["cn"].as_posix(),
                "repository_path_en": "projects/user-profile-analysis/" + spec["en"].as_posix(),
                "rows": len(frame),
                "columns": len(frame.columns),
                "sha256": sha256(source_path),
            }
        )
    return records


def mode_or_unknown(series: pd.Series) -> str:
    values = series.dropna().astype(str).str.strip()
    values = values[values.ne("")]
    return values.mode().iloc[0] if not values.empty else "未知"


def numeric_values(frame: pd.DataFrame, column: str) -> pd.Series:
    if column not in frame.columns:
        return pd.Series(float("nan"), index=frame.index, dtype="float64")
    return pd.to_numeric(frame[column], errors="coerce")


def cluster_frame(frame: pd.DataFrame, group: str | None = None) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    groups = list(frame.groupby("cluster_name", sort=False))
    for cluster_name, part in groups:
        age = numeric_values(part, "age")
        wealth = numeric_values(part, "wealth_score")
        price = numeric_values(part, "device_marketed_price")
        gender = part["gender"] if "gender" in part.columns else pd.Series("", index=part.index)
        app_category = (
            part["app_level_1_category"]
            if "app_level_1_category" in part.columns
            else pd.Series("", index=part.index)
        )
        game_like = part["game_like"] if "game_like" in part.columns else pd.Series("", index=part.index)
        rows.append(
            {
                "用户组": group or "",
                "聚类名称": cluster_name,
                "聚类人数": len(part),
                "组内占比%": round(len(part) / len(frame) * 100, 2),
                "聚类样本总数": len(frame),
                "平均年龄": round(age.mean(), 2),
                "男性占比%": round(gender.eq("男").mean() * 100, 2),
                "财富评分均值": round(wealth.mean(), 3),
                "设备均价": round(price.mean(), 1) if price.notna().any() else "",
                "Top1 App一级分类": mode_or_unknown(app_category),
                "Top1 游戏偏好": mode_or_unknown(game_like),
            }
        )
    return pd.DataFrame(rows)


CLUSTER_EN_HEADERS = [
    "user_group",
    "cluster_name",
    "cluster_users",
    "within_group_share_pct",
    "cluster_sample_users",
    "average_age",
    "male_share_pct",
    "average_wealth_score",
    "average_device_price",
    "top_app_level_1",
    "top_game_preference",
]


def write_bilingual_frame(frame: pd.DataFrame, cn: Path, en: Path, en_headers: list[str]) -> None:
    write_csv(frame, cn)
    english = frame.copy()
    if len(english.columns) != len(en_headers):
        raise ValueError(f"Column count mismatch for {cn}")
    english.columns = en_headers
    write_csv(english, en)


def build_cluster_outputs(source_dir: Path, output_dir: Path) -> dict[str, object]:
    device_book = source_dir / "苹果安卓鸿蒙用户用户画像" / "鸿蒙安卓苹果三组用户画像对比分析数据.xlsx"
    wc_book = source_dir / "wc_10min_user_profile_analysis" / "世锦赛10分钟以上观看用户画像分析数据.xlsx"

    device_sheet_map = {
        "鸿蒙": "鸿蒙聚类标签",
        "安卓": "安卓聚类标签",
        "苹果": "苹果聚类标签",
    }
    device_parts: list[pd.DataFrame] = []
    device_samples: dict[str, dict[str, int]] = {}
    for group, sheet in device_sheet_map.items():
        raw = pd.read_excel(device_book, sheet_name=sheet, engine="openpyxl")
        device_samples[group] = {
            "rows": len(raw),
            "unique_users": int(raw["user_ukey"].nunique()),
        }
        device_parts.append(cluster_frame(raw, group))
    device_clusters = pd.concat(device_parts, ignore_index=True)
    write_bilingual_frame(
        device_clusters,
        output_dir / "clusters/device-groups.csv",
        output_dir / "clusters/device-groups.en.csv",
        CLUSTER_EN_HEADERS,
    )

    wc_labels = pd.read_excel(wc_book, sheet_name="目标组聚类标签", engine="openpyxl")
    wc_clusters = cluster_frame(wc_labels)
    write_bilingual_frame(
        wc_clusters,
        output_dir / "clusters/world-championship-10min.csv",
        output_dir / "clusters/world-championship-10min.en.csv",
        CLUSTER_EN_HEADERS,
    )

    kmeans = pd.read_excel(wc_book, sheet_name="KMeans模型评估", engine="openpyxl")
    write_bilingual_frame(
        kmeans,
        output_dir / "clusters/world-championship-10min-kmeans.csv",
        output_dir / "clusters/world-championship-10min-kmeans.en.csv",
        ["k", "sse", "sse_decline_pct", "silhouette_score"],
    )

    price = pd.read_excel(wc_book, sheet_name="设备价格分层", engine="openpyxl")
    write_bilingual_frame(
        price,
        output_dir / "clusters/world-championship-10min-device-price-tiers.csv",
        output_dir / "clusters/world-championship-10min-device-price-tiers.en.csv",
        ["price_tier", "target_users", "target_pct", "control_users", "control_pct"],
    )

    processed_path = source_dir / "snooker_charts_V2" / "processed_data_v2.csv"
    processed = pd.read_csv(processed_path, encoding="utf-8-sig")
    identifier = processed.columns[0]
    processed_rows: list[dict[str, object]] = []
    for cluster_id, part in processed.groupby("cluster", sort=True):
        processed_rows.append(
            {
                "聚类编号": int(cluster_id),
                "行数": len(part),
                "占文件行数%": round(len(part) / len(processed) * 100, 2),
                "文件总行数": len(processed),
                "唯一标识数": int(processed[identifier].nunique()),
                "平均年龄": round(pd.to_numeric(part["age_filled"], errors="coerce").mean(), 2),
                "男性占比%": round(part["gender_filled"].eq("男").mean() * 100, 2),
                "财富评分均值": round(pd.to_numeric(part["wealth_score"], errors="coerce").mean(), 3),
                "设备均价": round(pd.to_numeric(part["device_price_filled"], errors="coerce").mean(), 1),
                "Top1 App一级分类": mode_or_unknown(part["app_level_1_category"]),
                "Top1 游戏偏好": mode_or_unknown(part["game_like"]),
                "可复现状态": "与报告聚类不可勾稽",
            }
        )
    processed_clusters = pd.DataFrame(processed_rows)
    write_bilingual_frame(
        processed_clusters,
        output_dir / "clusters/snooker-unreconciled-cluster-generation.csv",
        output_dir / "clusters/snooker-unreconciled-cluster-generation.en.csv",
        [
            "cluster_id",
            "rows",
            "share_of_file_rows_pct",
            "file_rows",
            "unique_identifiers",
            "average_age",
            "male_share_pct",
            "average_wealth_score",
            "average_device_price",
            "top_app_level_1",
            "top_game_preference",
            "reproducibility_status",
        ],
    )

    return {
        "device_samples": device_samples,
        "world_championship_10min_sample": {
            "rows": len(wc_labels),
            "unique_users": int(wc_labels["user_ukey"].nunique()),
        },
        "snooker_processed": {
            "rows": len(processed),
            "unique_identifiers": int(processed[identifier].nunique()),
            "cluster_rows": len(processed_clusters),
        },
    }


def classify_source(relative_path: Path) -> tuple[str, str]:
    name = relative_path.name
    suffix = relative_path.suffix.lower()
    safe_tgi = {
        "tgi_all_pairs.csv",
        "tgi_hm_vs_pg.csv",
        "tgi_hm_vs_az.csv",
        "tgi_az_vs_pg.csv",
        "tgi_full.csv",
    }
    if suffix == ".sql":
        return "included_sql", "复制到项目 sql/ 并做静态审查"
    if suffix == ".docx":
        return "included_report", "检查文本和 XML 后保留审计报告"
    if name in safe_tgi:
        if relative_path.parts[0] == "snooker_tgi_analysis":
            return "excluded_duplicate", "与 snooker_tgi_analysis_v2 数据内容重复"
        return "included_aggregate", "已导出到 artifacts/anonymous-summary/tgi"
    if name == "processed_data_v2.csv":
        return "excluded_user_level", "首列含伪匿名用户标识；仅导出聚类汇总"
    if name == "各设备用户画像数据.csv":
        return "excluded_user_level", "含 user_ukey 和设备用户明细"
    if suffix == ".xlsx":
        return "excluded_workbook", "含 user_ukey 聚类标签工作表；仅提取匿名汇总表"
    if suffix == ".png":
        return "excluded_generated_chart", "报告已嵌入最终图表；不重复上传全部生成图"
    return "reviewed_excluded", "未作为独立迁移资产"


def build_source_manifest(source_dir: Path, output_dir: Path, report_rows: list[dict[str, object]]) -> None:
    rows: list[dict[str, object]] = []
    outputs_by_name = {report["source"]: report for report in report_rows}
    for path in sorted(p for p in source_dir.rglob("*") if p.is_file()):
        relative = path.relative_to(source_dir)
        classification, rationale = classify_source(relative)
        repository_path = ""
        if relative.as_posix() in outputs_by_name:
            repository_path = outputs_by_name[relative.as_posix()]["repository_path_cn"]
        elif relative.as_posix() in REPORT_PATHS:
            repository_path = "projects/user-profile-analysis/" + REPORT_PATHS[relative.as_posix()]
        elif relative.as_posix() in SQL_PATHS:
            repository_path = "projects/user-profile-analysis/" + SQL_PATHS[relative.as_posix()]
        rows.append(
            {
                "来源相对路径": relative.as_posix(),
                "字节数": path.stat().st_size,
                "SHA256": sha256(path),
                "分类": classification,
                "处理方式": rationale,
                "仓库路径": repository_path,
            }
        )
    frame = pd.DataFrame(rows)
    write_bilingual_frame(
        frame,
        output_dir / "source-manifest.csv",
        output_dir / "source-manifest.en.csv",
        [
            "source_relative_path",
            "bytes",
            "sha256",
            "classification",
            "handling",
            "repository_path",
        ],
    )


def build_sql_audit(source_dir: Path, output_dir: Path) -> None:
    sql_dir = source_dir / "用户画像取数"
    device = (sql_dir / "鸿蒙安卓和苹果用户的画像.sql").read_text(encoding="utf-8-sig")
    watched = (sql_dir / "观看过世锦赛和未观看过世锦赛的画像.sql").read_text(encoding="utf-8-sig")
    longest = (sql_dir / "观看过世锦赛且单日观看时长最长的用户.sql").read_text(encoding="utf-8-sig")

    records = [
        {
            "SQL文件": "鸿蒙安卓和苹果用户的画像.sql",
            "检查项": "产品枚举拼写",
            "状态": "失败",
            "证据": "过滤条件使用 huya_andriod，CASE 使用 huya_android",
            "影响": "按存储 SQL 运行会把 Android 映射为其他或被过滤；现存输出无法仅凭该文件复现",
        },
        {
            "SQL文件": "鸿蒙安卓和苹果用户的画像.sql",
            "检查项": "用户级画像归属",
            "状态": "失败",
            "证据": "31 天日表仅按 user_ukey 关联，最终 distinct 不能保证每个用户只选一个画像快照",
            "影响": "属性可能随日期变化并导致重复或任意归属；人口占比的分母需要固定用户粒度",
        },
        {
            "SQL文件": "观看过世锦赛和未观看过世锦赛的画像.sql",
            "检查项": "注释年份",
            "状态": "失败",
            "证据": "日期为 2026 年，但目标组注释写 2025 年世锦赛",
            "影响": "版本语义不清楚，结果可能被误接到错误赛事",
        },
        {
            "SQL文件": "观看过世锦赛和未观看过世锦赛的画像.sql",
            "检查项": "比较窗口",
            "状态": "失败",
            "证据": "目标组为 2026-04-18 至 05-06，对照组为 04-18 至 05-04",
            "影响": "两组观察窗不一致，控制组缺少两天行为机会",
        },
        {
            "SQL文件": "观看过世锦赛且单日观看时长最长的用户.sql",
            "检查项": "CTE 定义",
            "状态": "失败",
            "证据": "第二个分支引用 ot_watch_longest_duration_user，但文件中没有定义",
            "影响": "该分支不能按原文执行",
        },
        {
            "SQL文件": "观看过世锦赛且单日观看时长最长的用户.sql",
            "检查项": "指标定义",
            "状态": "失败",
            "证据": "文件名写“单日观看时长最长”，实现却对全期间 watch_duration 求和后取第 1 行",
            "影响": "用户问题与 SQL 指标不一致，不能解释为单日最长观看",
        },
        {
            "SQL文件": "观看过世锦赛且单日观看时长最长的用户.sql",
            "检查项": "分组标签",
            "状态": "失败",
            "证据": "两个 union all 分支都把 user_type 写成“世锦赛期间观看时间最长的用户”",
            "影响": "目标组与对照组无法区分",
        },
        {
            "SQL文件": "观看过世锦赛且单日观看时长最长的用户.sql",
            "检查项": "watch_duration 单位与语义",
            "状态": "未执行",
            "证据": "缺少该表的字段字典；既有记忆中的 user_duration 规则不能直接替代本表字段",
            "影响": "排序方向可能正确，但分钟/秒/毫秒和会话口径未确认",
        },
    ]
    assert "huya_andriod" in device and "huya_android" in device
    assert "2025年世锦赛期间" in watched
    assert "2026-05-04" in watched and "2026-05-06" in watched
    assert "ot_watch_longest_duration_user" in longest
    assert "sum(b.watch_duration)" in longest
    assert longest.count("'世锦赛期间观看时间最长的用户' as user_type") == 2
    frame = pd.DataFrame(records)
    write_bilingual_frame(
        frame,
        output_dir / "sql-static-audit.csv",
        output_dir / "sql-static-audit.en.csv",
        ["sql_file", "check", "status", "evidence", "impact"],
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", required=True, type=Path)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    source_dir = args.source_dir.resolve()
    output_dir = args.output_dir.resolve()
    if not source_dir.is_dir():
        raise SystemExit(f"Source directory does not exist: {source_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)

    tgi_records = copy_tgi_tables(source_dir, output_dir)
    cluster_summary = build_cluster_outputs(source_dir, output_dir)
    build_source_manifest(source_dir, output_dir, tgi_records)
    build_sql_audit(source_dir, output_dir)

    summary = {
        "project": "user-profile-analysis",
        "tgi_tables": tgi_records,
        "cohorts": {
            "device": {"harmony": 172312, "android": 390718, "ios": 145179},
            "snooker_watchers_v2": {"target": 1072, "control": 2676},
            "world_championship_watchers": {"target": 208206, "control": 366543},
            "world_championship_viewers_10min": {"target": 192764, "control": 395788},
        },
        **cluster_summary,
        "privacy": {
            "raw_user_identifier_values_exported": False,
            "raw_user_level_rows_exported": False,
            "aggregate_only": True,
        },
    }
    (output_dir / "project-summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
