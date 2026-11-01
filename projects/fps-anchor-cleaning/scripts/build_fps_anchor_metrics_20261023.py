from __future__ import annotations

import csv
import base64
import sys
from collections import Counter, defaultdict
from pathlib import Path


BASE_DIR = Path(r"C:\Users\tiany\Desktop\FPS主播清洗_20261023")
INPUT_CSV = Path(r"C:\Users\tiany\Downloads\FPS主播年日均开播时长_最终明细_20261023.csv")
OUT_DIR = BASE_DIR / "outputs"
DETAIL_MAP_CSV = OUT_DIR / "huya_nick_b64_luid_latestdt_20260101_20261020.csv"
DIM_INFO_CSV = OUT_DIR / "huya_dim_ayyuid_info_20261022_b64.csv"
ANNUAL_CSV = OUT_DIR / "huya_anchor_annual_acu_livedays_20260101_20261020.csv"
MONTHLY_CSV = OUT_DIR / "huya_anchor_monthly_livedays_20260101_20261020.csv"

MONTHS = [f"2026-{m:02d}" for m in range(1, 11)]


def norm_text(value: str | None) -> str:
    return (value or "").strip()


def decode_b64_text(value: str | None) -> str:
    encoded = norm_text(value)
    if not encoded:
        return ""
    return base64.b64decode(encoded).decode("utf-8").strip()


def choose_detail_candidate(candidates: list[dict[str, str]]) -> tuple[dict[str, str], str]:
    max_dt = max(c["latest_dt"] for c in candidates)
    latest = [c for c in candidates if c["latest_dt"] == max_dt]
    if len(candidates) == 1:
        return candidates[0], "detail_unique"
    if len(latest) == 1:
        return latest[0], "detail_latest_dt"
    # 同一昵称在最后一天仍对应多个 ID 时，保留可复现的确定性规则：取最大 luid。
    return max(latest, key=lambda c: int(c["luid"]) if c["luid"].isdigit() else -1), "detail_latest_tie_max_luid"


def choose_dim_candidate(candidates: list[dict[str, str]]) -> tuple[dict[str, str], str]:
    if len(candidates) == 1:
        return candidates[0], "dim_current_unique"
    max_create_time = max(c["create_time"] for c in candidates)
    latest = [c for c in candidates if c["create_time"] == max_create_time]
    if len(latest) == 1:
        return latest[0], "dim_current_latest_create_time"
    return max(latest, key=lambda c: int(c["luid"]) if c["luid"].isdigit() else -1), "dim_current_latest_tie_max_luid"


def main() -> None:
    csv.field_size_limit(min(sys.maxsize, 10**9))
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    with INPUT_CSV.open("r", encoding="utf-8-sig", newline="") as f:
        input_rows = list(csv.DictReader(f))
    for row in input_rows:
        row["snick"] = norm_text(row.get("snick"))

    detail_luid_dt: dict[str, dict[str, str]] = defaultdict(dict)
    with DETAIL_MAP_CSV.open("r", encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f):
            snick = decode_b64_text(row.get("snick_b64"))
            luid = norm_text(row.get("luid"))
            latest_dt = norm_text(row.get("latest_dt"))
            if snick and luid:
                old_dt = detail_luid_dt[snick].get(luid, "")
                if latest_dt > old_dt:
                    detail_luid_dt[snick][luid] = latest_dt
    detail_by_name: dict[str, list[dict[str, str]]] = {
        snick: [{"luid": luid, "latest_dt": latest_dt} for luid, latest_dt in luids.items()]
        for snick, luids in detail_luid_dt.items()
    }

    dim_luid_info: dict[str, dict[str, dict[str, str]]] = defaultdict(dict)
    with DIM_INFO_CSV.open("r", encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f):
            snick = decode_b64_text(row.get("snick_b64"))
            luid = norm_text(row.get("luid"))
            if snick and luid:
                candidate = {
                    "luid": luid,
                    "roomid": norm_text(row.get("roomid")),
                    "create_time": norm_text(row.get("create_time")),
                }
                old = dim_luid_info[snick].get(luid)
                if old is None or candidate["create_time"] > old["create_time"]:
                    dim_luid_info[snick][luid] = candidate
    dim_by_name: dict[str, list[dict[str, str]]] = {
        snick: list(luids.values()) for snick, luids in dim_luid_info.items()
    }

    input_name_cnt = Counter(row["snick"] for row in input_rows if row["snick"])
    name_resolution: dict[str, dict[str, object]] = {}
    audit_rows: list[dict[str, object]] = []
    resolution_counter: Counter[str] = Counter()

    for snick in sorted(input_name_cnt):
        detail_candidates = detail_by_name.get(snick, [])
        dim_candidates = dim_by_name.get(snick, [])
        selected_luid = ""
        selected_latest_dt = ""
        selected_roomid = ""
        selected_create_time = ""
        source = ""

        if detail_candidates:
            chosen, status = choose_detail_candidate(detail_candidates)
            selected_luid = chosen["luid"]
            selected_latest_dt = chosen["latest_dt"]
            source = "dm_huya_ayyuid_detail_day_20260101_20261020"
        elif dim_candidates:
            chosen, status = choose_dim_candidate(dim_candidates)
            selected_luid = chosen["luid"]
            selected_roomid = chosen["roomid"]
            selected_create_time = chosen["create_time"]
            source = "dim_huya_ayyuid_info_20261022"
        else:
            status = "unresolved"
            source = ""

        resolution_counter[status] += 1
        name_resolution[snick] = {
            "luid": selected_luid,
            "mapping_status": status,
            "mapping_source": source,
        }
        audit_rows.append(
            {
                "snick": snick,
                "input_row_cnt": input_name_cnt[snick],
                "mapping_status": status,
                "mapping_source": source,
                "selected_luid": selected_luid,
                "selected_latest_dt": selected_latest_dt,
                "selected_roomid": selected_roomid,
                "selected_create_time": selected_create_time,
                "detail_candidate_cnt": len(detail_candidates),
                "detail_candidate_luids": "|".join(
                    f"{c['luid']}@{c['latest_dt']}" for c in sorted(detail_candidates, key=lambda x: (x["latest_dt"], x["luid"]), reverse=True)
                ),
                "dim_candidate_cnt": len(dim_candidates),
                "dim_candidate_luids": "|".join(
                    f"{c['luid']}@{c['create_time']}" for c in sorted(dim_candidates, key=lambda x: (x["create_time"], x["luid"]), reverse=True)
                ),
            }
        )

    audit_path = OUT_DIR / "FPS正常主播_昵称映射luid最终审计_修正版_20261023.csv"
    with audit_path.open("w", encoding="utf-8-sig", newline="") as f:
        fieldnames = [
            "snick",
            "input_row_cnt",
            "mapping_status",
            "mapping_source",
            "selected_luid",
            "selected_latest_dt",
            "selected_roomid",
            "selected_create_time",
            "detail_candidate_cnt",
            "detail_candidate_luids",
            "dim_candidate_cnt",
            "dim_candidate_luids",
        ]
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(audit_rows)

    annual_by_luid: dict[str, dict[str, str]] = {}
    with ANNUAL_CSV.open("r", encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f):
            annual_by_luid[norm_text(row.get("luid"))] = row

    monthly_by_luid_month: dict[tuple[str, str], dict[str, str]] = {}
    with MONTHLY_CSV.open("r", encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f):
            monthly_by_luid_month[(norm_text(row.get("luid")), norm_text(row.get("mth")))] = row

    # 同一 luid 可能对应多个输入昵称，汇总时保留输入昵称数和最近出现昵称。
    input_by_luid: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in input_rows:
        res = name_resolution.get(row["snick"])
        if res and res["luid"]:
            input_by_luid[str(res["luid"])].append(row)

    anchor_rows: list[dict[str, object]] = []
    monthly_rows: list[dict[str, object]] = []
    for luid, rows in input_by_luid.items():
        names = sorted({r["snick"] for r in rows})
        display_name = max(
            names,
            key=lambda n: (
                max((c["latest_dt"] for c in detail_by_name.get(n, [])), default=""),
                n,
            ),
        )
        game_pairs = Counter((r["main_game_id"], r["main_game_name"]) for r in rows)
        main_game_id, main_game_name = sorted(game_pairs.items(), key=lambda x: (-x[1], x[0]))[0][0]
        mapping_status = str(name_resolution[display_name]["mapping_status"])
        mapping_source = str(name_resolution[display_name]["mapping_source"])

        annual = annual_by_luid.get(luid)
        avg_acu = float(annual["avg_daily_acu"]) if annual and norm_text(annual.get("avg_daily_acu")) else 0.0
        total_live_days = int(float(annual["live_day_cnt"])) if annual and norm_text(annual.get("live_day_cnt")) else 0
        total_live_hours = float(annual["total_live_hours"]) if annual and norm_text(annual.get("total_live_hours")) else 0.0
        acu_type = "头部主播" if avg_acu >= 2000 else ("腰部主播" if avg_acu >= 100 else "尾部主播")

        month_counts: dict[str, int] = {}
        for mth in MONTHS:
            rec = monthly_by_luid_month.get((luid, mth))
            live_day_cnt = int(float(rec["live_day_cnt"])) if rec and norm_text(rec.get("live_day_cnt")) else 0
            live_hours = float(rec["live_hours"]) if rec and norm_text(rec.get("live_hours")) else 0.0
            month_counts[mth] = live_day_cnt
            monthly_rows.append(
                {
                    "mth": mth,
                    "luid": luid,
                    "snick": display_name,
                    "main_game_id": main_game_id,
                    "main_game_name": main_game_name,
                    "acu_type": acu_type,
                    "live_day_cnt": live_day_cnt,
                    "live_hours": live_hours,
                    "is_observed_month": 1 if rec else 0,
                }
            )

        active_month_cnt = sum(1 for v in month_counts.values() if v > 0)
        anchor_rows.append(
            {
                "luid": luid,
                "snick": display_name,
                "resolved_snick_cnt": len(names),
                "resolved_snick_list": "|".join(names),
                "mapping_status": mapping_status,
                "mapping_source": mapping_source,
                "main_game_id": main_game_id,
                "main_game_name": main_game_name,
                "avg_daily_acu_2026": round(avg_acu, 6),
                "acu_type": acu_type,
                "total_live_day_cnt": total_live_days,
                "active_month_cnt": active_month_cnt,
                "avg_monthly_live_days_10months": round(total_live_days / 10.0, 6),
                "avg_monthly_live_days_active_months": round(total_live_days / active_month_cnt, 6) if active_month_cnt else 0.0,
                "total_live_hours_2026": round(total_live_hours, 6),
                "annual_metric_match": 1 if annual else 0,
            }
        )

    anchor_rows.sort(key=lambda r: (-float(r["avg_daily_acu_2026"]), str(r["luid"])))
    monthly_rows.sort(key=lambda r: (str(r["luid"]), str(r["mth"])))

    summary_path = OUT_DIR / "FPS正常主播_年度ACU分层与月均开播天数_修正版_20260101_20261020.csv"
    with summary_path.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(anchor_rows[0].keys()) if anchor_rows else [])
        writer.writeheader()
        writer.writerows(anchor_rows)

    monthly_path = OUT_DIR / "FPS正常主播_每月开播天数明细_修正版_20260101_20261020.csv"
    with monthly_path.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(monthly_rows[0].keys()) if monthly_rows else [])
        writer.writeheader()
        writer.writerows(monthly_rows)

    unresolved_rows = [r for r in audit_rows if r["mapping_status"] == "unresolved"]
    unresolved_path = OUT_DIR / "FPS正常主播_昵称仍未识别_修正版_20261023.csv"
    with unresolved_path.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(audit_rows[0].keys()) if audit_rows else [])
        writer.writeheader()
        writer.writerows(unresolved_rows)

    print(f"input_rows={len(input_rows)}")
    print(f"input_unique_names={len(input_name_cnt)}")
    print(f"resolved_unique_names={len(input_name_cnt) - resolution_counter['unresolved']}")
    print(f"unresolved_unique_names={resolution_counter['unresolved']}")
    print(f"resolved_unique_luids={len(anchor_rows)}")
    print(f"monthly_rows={len(monthly_rows)}")
    for status, cnt in sorted(resolution_counter.items()):
        print(f"status_{status}={cnt}")
    print(f"audit_csv={audit_path}")
    print(f"summary_csv={summary_path}")
    print(f"monthly_csv={monthly_path}")
    print(f"unresolved_csv={unresolved_path}")


if __name__ == "__main__":
    main()
