from __future__ import annotations

import os
from pathlib import Path

import numpy as np
import pandas as pd


XLSX = Path(
    os.environ.get(
        "VALORANT_EXTERNAL_POOL_SOURCE_WORKBOOK",
        r"C:\Users\tiany\Desktop\无畏契约份额增长\无畏契约主播潜力分析\无畏契约行业主播反挖情况.xlsx",
    )
)
HUYA_CSV = Path(
    os.environ.get(
        "HUYA_VALORANT_SEPTEMBER_ACU_CSV",
        r"C:\Users\tiany\Downloads\无畏契约主播9月份日均ACU_未剔除赛事日.csv",
    )
)
OUTPUT = Path(
    os.environ.get(
        "VALORANT_EXTERNAL_POOL_OUTPUT",
        r"C:\Users\tiany\Desktop\无畏契约份额增长\无畏契约主播潜力分析\无畏契约行业主播反挖情况_并入虎牙9月ACU_20261010.xlsx",
    )
)


def main() -> None:
    if OUTPUT.exists() and os.environ.get("VALORANT_EXTERNAL_POOL_OVERWRITE") != "1":
        raise RuntimeError(
            "Output workbook already exists. Set VALORANT_EXTERNAL_POOL_OVERWRITE=1 "
            "only after confirming the target and backup."
        )

    existing = pd.read_excel(XLSX, sheet_name="9月份")
    huya = pd.read_csv(HUYA_CSV)
    base_columns = list(existing.columns)

    existing = existing.rename(columns={"排名": "原排名"})
    added = pd.DataFrame(index=huya.index)
    for column in base_columns:
        added[column] = np.nan
    added = added.rename(columns={"排名": "原排名"})
    added["日期"] = "2026-09-30"
    added["平台"] = "huya"
    added["主播名"] = huya["nickname"].astype(str)
    added["主播uid"] = huya["luid"].astype("int64").astype(str)
    added["全网品类"] = "无畏契约"
    added["虎牙品类"] = "无畏契约"
    added["有效acu"] = huya["acu_avg"]
    added["开播天数"] = huya["live_days"]
    added["主播分层"] = huya["acu_type"]

    existing["开播天数"] = np.nan
    existing["主播分层"] = np.nan
    combined = pd.concat([existing, added[list(existing.columns)]], ignore_index=True)
    combined["有效acu"] = pd.to_numeric(combined["有效acu"], errors="coerce")
    combined = combined.sort_values(
        "有效acu", ascending=False, na_position="last", kind="mergesort"
    ).reset_index(drop=True)
    combined["排名"] = np.arange(1, len(combined) + 1)

    preserved = {
        sheet: pd.read_excel(XLSX, sheet_name=sheet) for sheet in ["数据源", "筛选"]
    }
    with pd.ExcelWriter(OUTPUT, engine="openpyxl") as writer:
        preserved["数据源"].to_excel(writer, sheet_name="数据源", index=False)
        preserved["筛选"].to_excel(writer, sheet_name="筛选", index=False)
        combined.to_excel(writer, sheet_name="9月份", index=False)

    print(
        {
            "source_rows": len(existing),
            "huya_rows": len(huya),
            "combined_rows": len(combined),
            "output": str(OUTPUT),
        }
    )


if __name__ == "__main__":
    main()
