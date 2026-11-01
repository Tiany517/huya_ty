# -*- coding: utf-8 -*-
"""按 actual_view_mins 计算每月观时贡献率拐点（主口径=全网）"""
import sys

import numpy as np
import pandas as pd

sys.path.insert(0, r"C:\Users\tiany\Desktop\无畏契约观时贡献率拐点_20261015\scripts")
import knee_lib as K

SRC = (r"C:\Users\tiany\Desktop\无畏契约观时贡献率拐点_20261015\data"
       r"\无畏契约观时贡献率_1至9月_清洗版.csv")
COL = "actual_view_mins"


def load():
    df = pd.read_csv(SRC, encoding="utf-8-sig", dtype=str)
    df[COL] = pd.to_numeric(df[COL], errors="coerce")
    for c in ["juhe_vaild_acu", "live_days", "live_mins", "gift_value"]:
        df[c] = pd.to_numeric(df[c], errors="coerce")
    return df


def pv_desc(sub):
    pv = np.sort(sub[COL].dropna().to_numpy(dtype=float))[::-1]
    return pv[pv > 0]


def main():
    df = load()
    rows, caprows = [], []
    for m, g in df.groupby("month"):
        for scope, sub in [("全网", g),
                           ("站外", g[g["pcode"] != "huya"]),
                           ("站内", g[g["pcode"] == "huya"])]:
            pv = pv_desc(sub)
            if pv.size < 50:
                continue
            tot = pv.sum()
            kl = K.knee(pv, log=True)
            kn = K.knee(pv, log=False)
            ks = K.knee(pv, log=True, smooth=51)
            rows.append({
                "month": m, "scope": scope, "样本主播数": pv.size,
                "当月总观时(万小时)": round(tot / 60 / 1e4, 1),
                "主口径_名次": kl["knee_rank"],
                "主口径_累计贡献率": round(kl["knee_cum_share"], 4),
                "主口径_阈值(小时)": round(kl["knee_pv"] / 60, 1),
                "线性_名次": kn["knee_rank"],
                "线性_累计贡献率": round(kn["knee_cum_share"], 4),
                "平滑51_名次": ks["knee_rank"],
                "平滑51_累计贡献率": round(ks["knee_cum_share"], 4),
            })
            if scope == "全网":
                for cap in [500, 1000, 2000, 3000, 5000, 10000]:
                    if cap >= pv.size:
                        continue
                    k = K.knee(pv[:cap], log=True)
                    caprows.append({"month": m, "截断到前N名": cap,
                                    "拐点名次": k["knee_rank"],
                                    "累计贡献率": round(k["knee_cum_share"], 3)})

    res = pd.DataFrame(rows)
    print("=== A. 全网：每月拐点（主口径=对数归一化最大偏离）===")
    q = res[res["scope"] == "全网"].copy()
    print(q.to_string(index=False))

    print("\n=== B. 跨月稳定性（全网）===")
    for col in ["主口径_名次", "主口径_累计贡献率", "主口径_阈值(小时)",
                "线性_名次", "线性_累计贡献率", "平滑51_名次"]:
        s = q[col]
        print(f"  {col}: {s.min()} ~ {s.max()} | 均值 {s.mean():.2f} | 中位 {s.median():.2f}")

    print("\n=== C. 站外 / 站内 对照（主口径）===")
    o = res[res["scope"] != "全网"][["month", "scope", "样本主播数", "主口径_名次",
                                     "主口径_累计贡献率", "主口径_阈值(小时)"]]
    print(o.pivot(index="month", columns="scope").to_string())

    print("\n=== D. 端点敏感性（全网，主口径）===")
    c = pd.DataFrame(caprows).pivot(index="month", columns="截断到前N名", values="拐点名次")
    print(c.to_string())

    print("\n=== E. 全网 TopN 累计观时贡献率 ===")
    tr = []
    for m, g in df.groupby("month"):
        pv = pv_desc(g)
        tot = pv.sum()
        r = {"month": m,
             "总观时(万小时)": round(tot / 60 / 1e4, 1)}
        for n in [10, 30, 50, 100, 200, 500, 1000, 2000]:
            r[f"Top{n}"] = f"{pv[:n].sum() / tot:.1%}" if n <= pv.size else "-"
        tr.append(r)
    print(pd.DataFrame(tr).to_string(index=False))

    import os
    os.makedirs(K.OUT, exist_ok=True)
    res.to_csv(os.path.join(K.OUT, "拐点结果_按实际观时.csv"), index=False, encoding="utf-8-sig")
    pd.DataFrame(tr).to_csv(os.path.join(K.OUT, "TopN覆盖率_按实际观时.csv"), index=False, encoding="utf-8-sig")
    print("\n已写出中间结果到:", K.OUT)


if __name__ == "__main__":
    main()
