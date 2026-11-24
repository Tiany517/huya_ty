from __future__ import annotations

import json
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parent
DATA = ROOT / "dashboard_data_multidim_20261123.json"
OLD = ROOT / "dashboard_data_bigdata_20261123.json"


def main() -> None:
    data = json.loads(DATA.read_text(encoding="utf-8"))
    old = json.loads(OLD.read_text(encoding="utf-8"))
    meta = data["meta"]

    category_keys = [(r[0], r[1]) for r in data["categoryDaily"]]
    anchor_weekly_keys = [(r[0], r[1], r[3], r[4]) for r in data["anchorWeekly"]]
    anchor_daily_keys = [(r[0], r[1]) for r in data["anchorDaily"]]

    weeks = meta["weeks"]
    starts = [meta["weekRanges"][w]["start"] for w in weeks]
    old_week_index = {w: i for i, w in enumerate(old["meta"]["weeks"])}
    old_start = {w: old["meta"]["weekRanges"][w]["start"] for w in old["meta"]["weeks"]}
    focus = {"英雄联盟", "王者荣耀", "CS2", "体育", "户外", "无畏契约"}

    old_sum = defaultdict(lambda: [0.0, 0.0, 0.0, 0.0])
    for row in old["anchors"]:
        key = (old_start[old["meta"]["weeks"][row[1]]], row[0])
        old_sum[key][0] += row[4]
        old_sum[key][1] += row[5]
        old_sum[key][2] += row[6]
        old_sum[key][3] += row[12]

    new_sum = defaultdict(lambda: [0.0, 0.0, 0.0, 0.0])
    for row in data["anchorWeekly"]:
        category = meta["categories"][row[1]]["name"]
        key = (starts[row[0]], category)
        new_sum[key][0] += row[5]
        new_sum[key][1] += row[6]
        new_sum[key][2] += row[7]
        new_sum[key][3] += row[13]

    reconciliation = {}
    for category in focus:
        for week_start in starts:
            key = (week_start, category)
            reconciliation[key] = [
                round(new_sum[key][i] - old_sum[key][i], 6)
                for i in range(4)
            ]

    daily_w47 = defaultdict(lambda: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
    for row in data["anchorDaily"]:
        if row[0] < "2026-11-16":
            continue
        item = daily_w47[row[1]]
        item[0] += row[2]
        item[1] += row[3]
        item[2] += row[4]
        item[3] += row[6]
        item[4] += row[7]
        item[5] += row[8]
    weekly_w47 = defaultdict(lambda: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
    for row in data["anchorWeekly"]:
        if row[0] != 5:
            continue
        item = weekly_w47[row[4]]
        item[0] += row[5]
        item[1] += row[6]
        item[2] += row[7]
        item[3] += row[13]
        item[4] += row[14]
        item[5] += row[15]
    daily_anchor_deltas = {
        idx: [round(daily_w47[idx][i] - weekly_w47[idx][i], 6) for i in range(6)]
        for idx in daily_w47
    }

    sample_anchor = next(
        (
            idx
            for idx, item in enumerate(meta["anchors"])
            if item["id"] == "333393123"
        ),
        None,
    )
    sample_week = next(
        row
        for row in data["anchorWeekly"]
        if row[0] == 5 and row[4] == sample_anchor
    )
    sample_interaction_rate = (
        sample_week[15] / sample_week[5] if sample_week[5] else 0
    )
    interaction_over_dau_rows = sum(
        1 for row in data["anchorWeekly"] if row[5] > 0 and row[15] > row[5]
    )

    diagnostics = {
        "categoryRows": len(category_keys),
        "categoryUnique": len(set(category_keys)) == len(category_keys),
        "anchorWeeklyRows": len(anchor_weekly_keys),
        "anchorWeeklyUnique": len(set(anchor_weekly_keys)) == len(anchor_weekly_keys),
        "anchorDailyRows": len(anchor_daily_keys),
        "anchorDailyUnique": len(set(anchor_daily_keys)) == len(anchor_daily_keys),
        "groupCategoryCounts": Counter(meta["categories"][i]["group"] for i in range(len(meta["categories"]))),
        "focusReconciliationMaxAbs": [
            max(abs(values[i]) for values in reconciliation.values())
            for i in range(4)
        ],
        "dailyWeeklyW47MaxAbs": [
            max((abs(values[i]) for values in daily_anchor_deltas.values()), default=0)
            for i in range(6)
        ],
        "roomIdPopulated": sum(1 for a in meta["anchors"] if a["roomid"]),
        "nicknamePopulated": sum(1 for a in meta["anchors"] if a["name"]),
        "anchorCount": len(meta["anchors"]),
        "sampleAnchorInteractionRateW47": round(sample_interaction_rate, 8),
        "interactionOverDauRows": interaction_over_dau_rows,
        "eventStatus": meta["eventStatus"],
        "anchorDailyStatus": meta["anchorDailyStatus"],
        "dataBytes": DATA.stat().st_size,
    }
    checks = {
        "uniqueKeys": diagnostics["categoryUnique"] and diagnostics["anchorWeeklyUnique"] and diagnostics["anchorDailyUnique"],
        "focusReconciles": all(v == 0 for v in diagnostics["focusReconciliationMaxAbs"][:3]) and diagnostics["focusReconciliationMaxAbs"][3] < 0.01,
        "dailyReconcilesWeekly": all(v == 0 for v in diagnostics["dailyWeeklyW47MaxAbs"]),
        "searchableAnchorKeys": diagnostics["roomIdPopulated"] / max(diagnostics["anchorCount"], 1) > 0.9
        and diagnostics["nicknamePopulated"] / max(diagnostics["anchorCount"], 1) > 0.99,
        "interactionRateComputable": 0 < diagnostics["sampleAnchorInteractionRateW47"] < 1,
    }
    print(json.dumps({"checks": checks, "diagnostics": diagnostics}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
