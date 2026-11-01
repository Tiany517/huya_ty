# -*- coding: utf-8 -*-
"""评估最终名单用 >=3 / >=4 / >=5 个月达标哪个更合适（边际剔除分析）。

门槛：个人观时贡献率 >= 0.2%（分母=当月全网）
"""
import numpy as np
import pandas as pd

SRC = (r"C:\Users\tiany\Desktop\无畏契约观时贡献率拐点_20261015\data"
       r"\无畏契约观时贡献率_1至9月_清洗版.csv")
THR = 0.002


def load():
    df = pd.read_csv(SRC, encoding="utf-8-sig", dtype=str)
    df["avm"] = pd.to_numeric(df["actual_view_mins"], errors="coerce")
    df = df[df["avm"] > 0].copy()
    df["key"] = df["pcode"].astype(str) + "|" + df["r_lid"].astype(str)
    m = df.groupby(["month", "key"], as_index=False).agg(
        avm=("avm", "sum"), pcode=("pcode", "first"), owner=("r_owner", "first"))
    m["share"] = m["avm"] / m.groupby("month")["avm"].transform("sum")
    return m


if __name__ == "__main__":
    m = load()
    grand = m["avm"].sum()
    g = m.groupby("key", as_index=False).agg(
        pcode=("pcode", "first"), owner=("owner", "last"),
        mp=("month", "nunique"), mh=("share", lambda s: int((s >= THR).sum())),
        max_share=("share", "max"), hours=("avm", lambda s: s.sum() / 60))

    print("=== 各档位名单规模与价值 ===")
    rows = []
    for k in (2, 3, 4, 5, 6):
        s = g[g["mh"] >= k]
        rows.append({"档位": f">={k}个月", "人数": len(s),
                     "名单观时(万小时)": round(s["hours"].sum() / 1e4, 0),
                     "占9个月总观时": f"{s['hours'].sum() / (grand / 60):.2%}",
                     "人均观时(万小时)": round(s["hours"].mean() / 1e4, 1),
                     "人均观时中位(万小时)": round(s["hours"].median() / 1e4, 1)})
    print(pd.DataFrame(rows).to_string(index=False))

    print("\n=== 边际剔除：砍掉的人值多少 ===")
    for hi, lo in ((5, 4), (4, 3), (3, 2)):
        cut = g[(g["mh"] == lo)]
        keep = g[g["mh"] >= hi]
        print(f"从 >={hi} 放宽到 >={lo}，多纳入 {len(cut)} 人："
              f"合计 {cut['hours'].sum() / 1e4:.0f} 万小时 = 9个月总观时的 "
              f"{cut['hours'].sum() / (grand / 60):.2%}，"
              f"人均 {cut['hours'].mean() / 1e4:.1f} 万小时")
    print("\n=== 被 >5 剔除的 11 人明细（mh==4）===")
    c = g[g["mh"] == 4].sort_values("hours", ascending=False)
    show = c[["pcode", "owner", "mp", "mh", "max_share", "hours"]].copy()
    show["hours"] = (show["hours"] / 1e4).round(1)
    show["max_share"] = (show["max_share"] * 100).round(3)
    print(show.to_string(index=False))
    print("\n=== 被 >4 剔除的 19 人明细（mh==3）===")
    c3 = g[g["mh"] == 3].sort_values("hours", ascending=False)
    show3 = c3[["pcode", "owner", "mp", "mh", "max_share", "hours"]].copy()
    show3["hours"] = (show3["hours"] / 1e4).round(1)
    show3["max_share"] = (show3["max_share"] * 100).round(3)
    print(show3.to_string(index=False))

    print("\n=== 达标率视角（mh / 出现月数）===")
    sel = g[g["mh"] >= 3].copy()
    sel["达标率"] = sel["mh"] / sel["mp"]
    print(sel.groupby("mh")["达标率"].describe()[["count", "min", "50%", "max"]].round(2).to_string())

    print("\n=== 风险：达标<3 个月但单月曾 >=0.5% 的主播（潜在误杀）===")
    risk = g[(g["mh"] < 3) & (g["max_share"] >= 0.005)].sort_values("max_share", ascending=False)
    r = risk[["pcode", "owner", "mp", "mh", "max_share", "hours"]].copy()
    r["max_share"] = (r["max_share"] * 100).round(2)
    r["hours"] = (r["hours"] / 1e4).round(1)
    print(f"共 {len(risk)} 人，合计 9 个月观时 {risk['hours'].sum() / 1e4:.0f} 万小时 "
          f"= 总观时的 {risk['hours'].sum() / (grand / 60):.2%}")
    print(r.head(25).to_string(index=False))

    print("\n=== 风险：达标>=3 但强度很低的人（每月刚好过线）===")
    low = sel[sel["max_share"] < 0.003].sort_values("hours")
    lo = low[["pcode", "owner", "mp", "mh", "max_share", "hours"]].copy()
    lo["max_share"] = (lo["max_share"] * 100).round(3)
    lo["hours"] = (lo["hours"] / 1e4).round(1)
    print(f"共 {len(low)} 人（名单占比 {len(low)/len(sel):.0%}），"
          f"合计观时 {low['hours'].sum() / 1e4:.0f} 万小时 = 名单观时的 "
          f"{low['hours'].sum() / sel['hours'].sum():.1%}")
    print(lo.head(20).to_string(index=False))
