# -*- coding: utf-8 -*-
"""拐点计算的公共函数（供各脚本复用）"""
import numpy as np
import pandas as pd

SRC = r"C:\Users\tiany\Downloads\无畏契约行业ACU份额_全网主播价值预测口径_1至9月份.csv"
OUT = r"C:\Users\tiany\Desktop\无畏契约观时贡献率拐点_20261015\output"
PC = ["huya", "douyin_web", "bilibili", "douyu", "kuaishou"]
NUM_COLS = ["juhe_vaild_acu", "live_days", "live_mins", "gift_user", "gift_value",
            "predict_acu", "predict_viewhours", "predict_laxin", "predict_yingshou",
            "predict_pay_year", "rnk"]


def minmax(a):
    a = np.asarray(a, dtype=float)
    rng = a[-1] - a[0]
    if rng == 0:
        return np.zeros_like(a)
    return (a - a[0]) / rng


def curve(pv):
    pv = np.asarray(pv, dtype=float)
    x = np.arange(1, pv.size + 1)
    y = np.cumsum(pv) / pv.sum()
    return x, y


def knee(pv, log=True, smooth=None):
    x, y = curve(pv)
    if log:
        u, v = np.log(x), np.log(y)
    else:
        u, v = x.astype(float), y
    D = minmax(v) - minmax(u)
    if smooth:
        D = pd.Series(D).rolling(smooth, center=True, min_periods=1).mean().to_numpy()
    i = int(np.argmax(D))
    return {"knee_rank": int(x[i]), "knee_cum_share": float(y[i]),
            "knee_pv": float(pv[i]), "max_dev": float(D[i]), "n": int(pv.size)}


def load():
    df = pd.read_csv(SRC, encoding="utf-8-sig", dtype=str)
    dt = pd.to_datetime(df["dt"], errors="coerce")
    df["mth"] = dt.dt.strftime("%Y-%m")
    df = df[df["mth"].notna() & df["pcode"].isin(PC)].copy()
    for c in NUM_COLS:
        df[c] = pd.to_numeric(df[c], errors="coerce")
    return df


def pv_desc(sub):
    pv = np.sort(sub["predict_viewhours"].dropna().to_numpy(dtype=float))[::-1]
    return pv[pv > 0]
