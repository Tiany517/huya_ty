# -*- coding: utf-8 -*-
"""为新增三列做口径探针：ACU分层、预测ACUvs实际ACU、开播稳定阈值敏感性。"""
import numpy as np
import pandas as pd

SRC = (r"C:\Users\tiany\Desktop\无畏契约观时贡献率拐点_20261015\data"
       r"\无畏契约观时贡献率_1至9月_清洗版.csv")
THR = 0.002
RULES = [(10, 30), (12, 48), (15, 40), (15, 60), (20, 60), (20, 80), (22, 100)]


def build():
    d = pd.read_csv(SRC, encoding="utf-8-sig", dtype=str)
    for c in ["actual_view_mins", "juhe_vaild_acu", "predict_acu", "predict_viewhours",
              "predict_yingshou", "live_days", "live_mins"]:
        d[c] = pd.to_numeric(d[c], errors="coerce")
    d = d[d["actual_view_mins"] > 0].copy()
    d["key"] = d["pcode"].astype(str) + "|" + d["r_lid"].astype(str)
    d = d.drop_duplicates(subset=["month", "key", "actual_view_mins"])
    m = d.groupby(["month", "key"], as_index=False).agg(avm=("actual_view_mins", "sum"))
    m["share"] = m["avm"] / m.groupby("month")["avm"].transform("sum")
    g = m.groupby("key", as_index=False).agg(mh=("share", lambda s: int((s >= THR).sum())))
    sel = set(g.loc[g["mh"] >= 3, "key"])
    s = d[d["key"].isin(sel)].copy()
    s["hit"] = (s["actual_view_mins"]
                / s.groupby("month")["actual_view_mins"].transform("sum")) >= THR
    return s, g[g["mh"] >= 3]


if __name__ == "__main__":
    s, sel = build()
    print("样本：89人名单明细行数 =", len(s))
    print("\n=== 1) ACU分层 ===")
    a = s.groupby("key", as_index=False).agg(
        n2k=("juhe_vaild_acu", lambda x: int((x >= 2000).sum())),
        n100=("juhe_vaild_acu", lambda x: int((x >= 100).sum())),
        ac_med=("juhe_vaild_acu", "median"), ac_mean=("juhe_vaild_acu", "mean"))
    print("有效ACU>=2000 的月份数分布:", a["n2k"].value_counts().sort_index().to_dict())
    print("有效ACU>=100 的月份数分布:", a["n100"].value_counts().sort_index().to_dict())
    a["层级"] = np.where(a["n2k"] >= 3, "头部", np.where(a["n100"] >= 3, "腰部", "尾部"))
    print("分层结果:", a["层级"].value_counts().to_dict())
    print("层级×达标月份数交叉:")
    a2 = a.merge(sel, on="key")
    print(pd.crosstab(a2["层级"], a2["mh"]).to_string())

    print("\n=== 2) 预测ACU > 实际ACU ===")
    cmp = s[s["predict_acu"].notna() & s["juhe_vaild_acu"].notna()].copy()
    cmp["gt"] = cmp["predict_acu"] > cmp["juhe_vaild_acu"]
    c = cmp.groupby("key").agg(cmp_m=("gt", "size"), gt_m=("gt", "sum"),
                               pac_mean=("predict_acu", "mean"), ac_mean=("juhe_vaild_acu", "mean"))
    c["主口径_均值"] = c["pac_mean"] > c["ac_mean"]
    c["次口径_多数月"] = c["gt_m"] / c["cmp_m"] >= 0.5
    print("可比主播数:", len(c))
    print("主口径(均值: 预测>实际) 命中:", int(c["主口径_均值"].sum()))
    print("次口径(多数月份命中) 命中:", int(c["次口径_多数月"].sum()))
    print("两种口径不一致:", int((c["主口径_均值"] != c["次口径_多数月"]).sum()))
    print("逐月命中率分布:", (c["gt_m"] / c["cmp_m"]).round(2).value_counts().sort_index().to_dict())

    print("\n=== 3) 开播稳定阈值敏感性 ===")
    rows = []
    per = s.copy()
    per["hours"] = per["live_mins"] / 60
    for days, hrs in RULES:
        per["stab"] = (per["live_days"] >= days) & (per["hours"] >= hrs)
        k = per.groupby("key").agg(stab_m=("stab", "sum"), mp=("month", "nunique"))
        k["stab_m"] = k["stab_m"].where(k["mp"] >= k["stab_m"])  # 未出现月不计
        row = {"规则": f"天数≥{days} 且 时长≥{hrs}h",
               "稳定月数中位": k["stab_m"].median(),
               "≥8个月": int((k["stab_m"] >= 8).sum()),
               "≥7个月": int((k["stab_m"] >= 7).sum()),
               "≥6个月": int((k["stab_m"] >= 6).sum()),
               "≥5个月": int((k["stab_m"] >= 5).sum()),
               "≥4个月": int((k["stab_m"] >= 4).sum()),
               "≤3个月": int((k["stab_m"] <= 3).sum())}
        rows.append(row)
    t = pd.DataFrame(rows)
    print(t.to_string(index=False))

    print("\n=== 推荐阈值 (天数≥15 且 时长≥60h) 详解 ===")
    per["stab"] = (per["live_days"] >= 15) & (per["hours"] >= 60)
    k = per.groupby("key").agg(stab_m=("stab", "sum"), mp=("month", "nunique"),
                               ld_med=("live_days", "median"), hr_med=("hours", "median"))
    k = k.merge(sel, on="key")
    print("稳定月数分布:", k["stab_m"].value_counts().sort_index().to_dict())
    k["稳定分层"] = np.where(k["stab_m"] >= 6, "稳定", np.where(k["stab_m"] >= 4, "较稳定", "不稳定"))
    print("稳定分层:", k["稳定分层"].value_counts().to_dict())
    print("\n稳定分层 × 达标月份数:")
    print(pd.crosstab(k["稳定分层"], k["mh"]).to_string())
    print("\n达标≥5个月但开播不稳定(≤3个月稳定)的主播:")
    bad = k[(k["mh"] >= 5) & (k["stab_m"] <= 3)].sort_values("mh", ascending=False)
    print(bad[["key", "mh", "stab_m", "ld_med", "hr_med"]].to_string(index=False))
    print("\n达标≥5个月且开播稳定(<6个月稳定)的主播:")
    bad2 = k[(k["mh"] >= 5) & (k["stab_m"] < 6)].sort_values("stab_m")
    print(bad2[["key", "mh", "stab_m", "ld_med", "hr_med"]].to_string(index=False))
