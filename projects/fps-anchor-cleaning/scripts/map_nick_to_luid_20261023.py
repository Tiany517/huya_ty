from __future__ import annotations

import csv
import sys
from collections import Counter, defaultdict
from pathlib import Path


BASE_DIR = Path(r"C:\Users\tiany\Desktop\FPS主播清洗_20261023")
INPUT_CSV = Path(r"C:\Users\tiany\Downloads\FPS主播年日均开播时长_最终明细_20261023.csv")
MAP_CSV = BASE_DIR / "outputs" / "huya_nick_luid_map_20260101_20261020.csv"
OUT_DIR = BASE_DIR / "outputs"


def norm_name(value: str | None) -> str:
    return (value or "").strip()


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    csv.field_size_limit(min(sys.maxsize, 10**9))

    with INPUT_CSV.open("r", encoding="utf-8-sig", newline="") as f:
        input_rows = list(csv.DictReader(f))

    # 精确清洗昵称后，建立“昵称 -> 候选 luid 集合”。
    name_to_luids: dict[str, set[str]] = defaultdict(set)
    luid_to_names: dict[str, set[str]] = defaultdict(set)
    map_pair_cnt = 0
    with MAP_CSV.open("r", encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f):
            luid = (row.get("luid") or "").strip()
            snick = norm_name(row.get("snick"))
            if not luid or not snick:
                continue
            map_pair_cnt += 1
            name_to_luids[snick].add(luid)
            luid_to_names[luid].add(snick)

    input_name_cnt = Counter(norm_name(r.get("snick")) for r in input_rows)
    unique_names = sorted(n for n in input_name_cnt if n)

    status_counter: Counter[str] = Counter()
    matched_luids: set[str] = set()
    audit_rows: list[dict[str, object]] = []
    for snick in unique_names:
        candidates = sorted(name_to_luids.get(snick, set()))
        if not candidates:
            status = "unresolved"
        elif len(candidates) == 1:
            status = "resolved_unique"
            matched_luids.update(candidates)
        else:
            status = "ambiguous_multi_luid"
        status_counter[status] += 1
        audit_rows.append(
            {
                "snick": snick,
                "input_row_cnt": input_name_cnt[snick],
                "mapping_status": status,
                "candidate_luid_cnt": len(candidates),
                "candidate_luids": "|".join(candidates),
            }
        )

    audit_path = OUT_DIR / "FPS正常主播_昵称映射luid审计_20260101_20261020.csv"
    with audit_path.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "snick",
                "input_row_cnt",
                "mapping_status",
                "candidate_luid_cnt",
                "candidate_luids",
            ],
        )
        writer.writeheader()
        writer.writerows(audit_rows)

    resolved_name_path = OUT_DIR / "FPS正常主播_唯一识别昵称_20260101_20261020.csv"
    with resolved_name_path.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["snick", "luid"])
        for snick in unique_names:
            candidates = sorted(name_to_luids.get(snick, set()))
            if len(candidates) == 1:
                writer.writerow([snick, candidates[0]])

    resolved_luid_path = OUT_DIR / "FPS正常主播_唯一识别luid_20260101_20261020.csv"
    with resolved_luid_path.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["luid"])
        writer.writerows((luid,) for luid in sorted(matched_luids))

    multi_name_luid_cnt = sum(1 for names in luid_to_names.values() if len(names) > 1)
    resolved_input_rows = sum(
        input_name_cnt[snick]
        for snick in unique_names
        if len(name_to_luids.get(snick, set())) == 1
    )
    print(f"map_pairs={map_pair_cnt}")
    print(f"map_unique_names={len(name_to_luids)}")
    print(f"map_unique_luids={len(luid_to_names)}")
    print(f"input_rows={len(input_rows)}")
    print(f"input_unique_names={len(unique_names)}")
    print(f"resolved_unique_names={status_counter['resolved_unique']}")
    print(f"ambiguous_names={status_counter['ambiguous_multi_luid']}")
    print(f"unresolved_names={status_counter['unresolved']}")
    print(f"resolved_input_rows={resolved_input_rows}")
    print(f"resolved_unique_luids={len(matched_luids)}")
    print(f"luids_with_multiple_names={multi_name_luid_cnt}")
    print(f"audit_csv={audit_path}")
    print(f"resolved_name_csv={resolved_name_path}")
    print(f"resolved_luid_csv={resolved_luid_path}")


if __name__ == "__main__":
    main()
