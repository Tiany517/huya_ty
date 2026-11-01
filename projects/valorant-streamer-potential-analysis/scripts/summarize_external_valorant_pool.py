from __future__ import annotations

import os
from pathlib import Path

import pandas as pd


SOURCE = Path(
    os.environ.get(
        "VALORANT_EXTERNAL_POOL_WORKBOOK",
        r"C:\Users\tiany\Desktop\无畏契约份额增长\无畏契约主播潜力分析\无畏契约行业主播反挖情况_并入虎牙9月ACU_20261010.xlsx",
    )
)
OUT_DIR = Path(__file__).resolve().parents[1] / "artifacts"
TIERS = ["头部", "颈部", "腰部", "尾部"]
TIERS_EN = {"头部": "head", "颈部": "neck", "腰部": "waist", "尾部": "tail"}


def main() -> None:
    frame = pd.read_excel(SOURCE, sheet_name="9月份")
    frame = frame[frame["平台"].notna()].copy()
    frame["主播等级"] = frame["主播等级"].fillna("未标注")

    grouped = (
        frame.groupby("平台", as_index=False)
        .agg(
            rows=("主播uid", "size"),
            unique_anchor_ids=("主播uid", lambda s: s.astype(str).nunique()),
            **{
                name: ("主播等级", lambda s, name=name: int((s == name).sum()))
                for name in TIERS
            },
        )
        .sort_values("platform" if "platform" in frame.columns else "平台")
    )

    rows_zh = []
    rows_en = []
    for row in grouped.to_dict(orient="records"):
        ranked = sorted([(tier, int(row[tier])) for tier in TIERS], key=lambda x: -x[1])
        note_zh = f"最大层级={ranked[0][0]}；头部{int(row['头部'])}、颈部{int(row['颈部'])}、腰部{int(row['腰部'])}"
        note_en = (
            f"largest_tier={TIERS_EN[ranked[0][0]]}; head={int(row['头部'])}, "
            f"neck={int(row['颈部'])}, waist={int(row['腰部'])}"
        )
        rows_zh.append(
            {
                "平台": row["平台"],
                "快照行数": int(row["rows"]),
                "唯一主播ID数": int(row["unique_anchor_ids"]),
                "头部": int(row["头部"]),
                "颈部": int(row["颈部"]),
                "腰部": int(row["腰部"]),
                "尾部": int(row["尾部"]),
                "说明": note_zh,
            }
        )
        rows_en.append(
            {
                "platform": row["平台"],
                "snapshot_rows": int(row["rows"]),
                "unique_anchor_ids": int(row["unique_anchor_ids"]),
                "head": int(row["头部"]),
                "neck": int(row["颈部"]),
                "waist": int(row["腰部"]),
                "tail": int(row["尾部"]),
                "note": note_en,
            }
        )

    all_row = {
        "平台": "all",
        "快照行数": len(frame),
        "唯一主播ID数": int(frame["主播uid"].astype(str).nunique()),
        **{tier: int((frame["主播等级"] == tier).sum()) for tier in TIERS},
        "说明": "2026-09-30 快照；表内各平台记录汇总",
    }
    rows_zh.append(all_row)
    rows_en.append(
        {
            "platform": "all",
            "snapshot_rows": len(frame),
            "unique_anchor_ids": int(frame["主播uid"].astype(str).nunique()),
            "head": int((frame["主播等级"] == "头部").sum()),
            "neck": int((frame["主播等级"] == "颈部").sum()),
            "waist": int((frame["主播等级"] == "腰部").sum()),
            "tail": int((frame["主播等级"] == "尾部").sum()),
            "note": "2026-09-30 snapshot; pooled across platforms",
        }
    )

    pd.DataFrame(rows_zh).to_csv(
        OUT_DIR / "external-valorant-pool-202609-summary.csv",
        index=False,
        encoding="utf-8-sig",
    )
    pd.DataFrame(rows_en).to_csv(
        OUT_DIR / "external-valorant-pool-202609-summary.en.csv",
        index=False,
        encoding="utf-8-sig",
    )

    print(
        {
            "rows": len(frame),
            "unique_anchor_ids": int(frame["主播uid"].astype(str).nunique()),
            "duplicate_rows": len(frame) - int(frame["主播uid"].astype(str).nunique()),
        }
    )


if __name__ == "__main__":
    main()
