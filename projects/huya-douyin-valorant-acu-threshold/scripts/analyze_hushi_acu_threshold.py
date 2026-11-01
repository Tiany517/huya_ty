# -*- coding: utf-8 -*-
"""
虎视虎啸（抖音）无畏契约主播池：月日均ACU达标主播盘点

业务问题：
    池子里有多少主播的月日均ACU曾达到 2000 / 3000 / 4000 / 5000 以上？是谁、哪个月达到的？
    并输出带数值标签的时间趋势折线图。

输入：C:\\Users\\tiany\\Downloads\\虎视虎啸无畏契约主播情况.csv
     字段 mth, anchor_id, nickname, acu_type, total_dau, valid_dau, valid_acu, view_mins, rnk
口径：沿用原表 valid_acu 字段，表为「主播 × 月」粒度，即该主播该月的日均有效ACU（未重算、未改名）
     达标定义：该主播在某个月的 valid_acu ≥ 阈值，即视为「曾经达到过」
     同一主播跨月昵称会变（如莫拉塔/谢尔比·李），按 anchor_id 归并，展示名取最近一次昵称
"""

import os
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patheffects as pe
from openpyxl import load_workbook
from openpyxl.styles import Font, Alignment, PatternFill, Border, Side

plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei"]
plt.rcParams["axes.unicode_minus"] = False

RAW = r"C:\Users\tiany\Downloads\虎视虎啸无畏契约主播情况.csv"
OUTDIR = r"C:\Users\tiany\Desktop\无畏契约主播潜力分析\虎视虎啸_月日均ACU达标_20261016"
XLSX = os.path.join(OUTDIR, "虎视虎啸_月日均ACU达标主播_20261016.xlsx")
PNG1 = os.path.join(OUTDIR, "图1_达标主播月日均ACU趋势_20261016.png")
PNG2 = os.path.join(OUTDIR, "图2_每月达标主播数与最高ACU_20261016.png")
THRESHOLDS = [2000, 3000, 4000, 5000]


def load():
    df = pd.read_csv(RAW, encoding="utf-8-sig", dtype={"anchor_id": "object", "nickname": "object"})
    df["nickname"] = df["nickname"].astype(str).str.strip()
    df = df.sort_values(["anchor_id", "mth"]).reset_index(drop=True)
    latest = df.groupby("anchor_id")["nickname"].last()
    df["展示名"] = df["anchor_id"].map(latest)
    return df


def build(df):
    months = sorted(df["mth"].unique())
    mx = df.groupby("anchor_id")["valid_acu"].max()
    winners = {t: mx[mx >= t].sort_values(ascending=False).index.tolist() for t in THRESHOLDS}

    rows = []
    for t in THRESHOLDS:
        for a in winners[t]:
            g = df[df["anchor_id"] == a].sort_values("mth")
            hit = g[g["valid_acu"] >= t]
            rows.append({
                "阈值": f"≥{t}", "anchor_id": a, "主播展示名": g["展示名"].iloc[-1],
                "池内分层": g["acu_type"].iloc[-1], "出现月份数": len(g),
                "峰值月日均ACU": round(g["valid_acu"].max(), 1),
                "峰值月份": g.loc[g["valid_acu"].idxmax(), "mth"],
                "达阈月份数": len(hit),
                "达阈月份明细": "；".join(f"{r['mth']}({r['valid_acu']:.0f})" for _, r in hit.iterrows()),
            })
    winner_tbl = pd.DataFrame(rows)
    piv = df.pivot_table(index="mth", columns="展示名", values="valid_acu").reindex(months)

    cnt = []
    for m, g in df.groupby("mth"):
        d = {"月份": m, "池内主播数": len(g), "最高月日均ACU": round(g["valid_acu"].max(), 1)}
        for t in THRESHOLDS:
            d[f"≥{t}人数"] = int((g["valid_acu"] >= t).sum())
        cnt.append(d)
    cnt = pd.DataFrame(cnt).sort_values("月份").reset_index(drop=True)
    return months, winners, winner_tbl, piv, cnt


def plot_trend(months, piv, path):
    cols = sorted(piv.columns, key=lambda c: -np.nan_to_num(piv[c].max()))
    cols = [c for c in cols if np.nan_to_num(piv[c].max()) >= 2000]
    fig, ax = plt.subplots(figsize=(15.5, 8.2))
    colors = ["#1F4E79", "#C00000", "#2E8B57", "#ED7D31", "#7030A0"]
    # 标签错位放置，避免数值接近时（如6月2533/2530、5月1379/1362）互相遮挡
    offsets = [(0, 12), (-20, -7), (20, -7), (0, -19), (0, 12)]
    xs = list(range(len(months)))
    for i, c in enumerate(cols):
        y = piv[c].reindex(months).values
        ax.plot(xs, y, marker="o", ms=6, lw=2.0, color=colors[i % len(colors)], label=c)
        for x, v in zip(xs, y):
            if not np.isnan(v):
                ax.annotate(f"{v:.0f}", (x, v), textcoords="offset points", xytext=offsets[i % len(offsets)],
                            ha="center", fontsize=10, color=colors[i % len(colors)], fontweight="bold",
                            path_effects=[pe.withStroke(linewidth=3, foreground="white")])
    for t, ls in zip(THRESHOLDS, [":", "--", "-.", (0, (5, 1))]):
        ax.axhline(t, color="#999999", lw=1.1, linestyle=ls, alpha=0.9)
        ax.annotate(f"{t}", (len(months) - 0.55, t), xytext=(6, -3), textcoords="offset points",
                    fontsize=9, color="#666666")
    ax.set_xticks(xs)
    ax.set_xticklabels(months)
    ax.set_ylabel("月日均有效ACU（人）")
    ax.set_xlabel("月份")
    ax.set_title("虎视虎啸（抖音）无畏契约主播池：月日均ACU曾达2000+的主播趋势\n（数字＝当月月日均有效ACU；断点＝该月无该主播记录；灰线为2000/3000/4000/5000阈值）",
                 fontsize=13.5)
    ax.grid(alpha=0.25, linestyle=":")
    ax.legend(loc="upper left", frameon=False, fontsize=10)
    ax.set_ylim(0, float(np.nanmax(piv[cols].values)) * 1.12)
    fig.subplots_adjust(left=0.07, right=0.975, top=0.85, bottom=0.085)
    fig.savefig(path, dpi=170, bbox_inches="tight")
    plt.close(fig)


def plot_counts(cnt, path):
    fig, axes = plt.subplots(1, 2, figsize=(15.5, 6.4), gridspec_kw={"wspace": 0.22})
    ax, ax2 = axes
    xs = list(range(len(cnt)))
    colors = ["#1F4E79", "#C00000", "#2E8B57", "#ED7D31"]
    for t, c in zip(THRESHOLDS, colors):
        y = cnt[f"≥{t}人数"].values
        ax.plot(xs, y, marker="o", ms=6, lw=2, color=c, label=f"≥{t}")
        for x, v in zip(xs, y):
            ax.annotate(f"{v}", (x, v), textcoords="offset points", xytext=(0, 9), ha="center",
                        fontsize=9.5, color=c, fontweight="bold",
                        path_effects=[pe.withStroke(linewidth=3, foreground="white")])
    ax.set_xticks(xs)
    ax.set_xticklabels(cnt["月份"], rotation=45)
    ax.set_ylabel("当月达标主播数（个）")
    ax.set_ylim(-0.3, 4.2)
    ax.set_title("每月达标主播数（按阈值）", fontsize=12.5)
    ax.grid(alpha=0.25, linestyle=":")
    ax.legend(frameon=False)

    y = cnt["最高月日均ACU"].values
    ax2.plot(xs, y, marker="s", ms=6, lw=2, color="#7030A0", label="池内最高月日均ACU")
    for x, v in zip(xs, y):
        ax2.annotate(f"{v:.0f}", (x, v), textcoords="offset points", xytext=(0, 9), ha="center",
                     fontsize=9.5, color="#7030A0", fontweight="bold",
                     path_effects=[pe.withStroke(linewidth=3, foreground="white")])
    for t in THRESHOLDS:
        ax2.axhline(t, color="#999999", lw=1, linestyle=":", alpha=0.8)
        ax2.annotate(f"{t}", (len(cnt) - 0.6, t), xytext=(6, -3), textcoords="offset points",
                     fontsize=9, color="#666666")
    ax2.set_xticks(xs)
    ax2.set_xticklabels(cnt["月份"], rotation=45)
    ax2.set_ylabel("月日均有效ACU（人）")
    ax2.set_title("池内最高月日均ACU 逐月变化", fontsize=12.5)
    ax2.grid(alpha=0.25, linestyle=":")
    ax2.legend(frameon=False)
    ax2.set_ylim(bottom=0)
    fig.subplots_adjust(left=0.06, right=0.985, top=0.88, bottom=0.14)
    fig.savefig(path, dpi=170, bbox_inches="tight")
    plt.close(fig)


def to_excel(tables, path):
    with pd.ExcelWriter(path, engine="openpyxl") as w:
        for s, d in tables.items():
            d.to_excel(w, sheet_name=s[:31], index=False)
    wb = load_workbook(path)
    fill = PatternFill("solid", fgColor="DCE6F1")
    thin = Side(style="thin", color="BFBFBF")
    bd = Border(left=thin, right=thin, top=thin, bottom=thin)
    for ws in wb.worksheets:
        for c in ws[1]:
            c.font = Font(name="楷体", size=11, bold=True)
            c.fill = fill
            c.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
            c.border = bd
        for row in ws.iter_rows(min_row=2):
            for c in row:
                num = isinstance(c.value, (int, float)) and not isinstance(c.value, bool)
                c.font = Font(name="Calibri" if num else "楷体", size=10)
                c.border = bd
                if num:
                    c.number_format = "#,##0.0" if isinstance(c.value, float) else "#,##0"
                else:
                    c.alignment = Alignment(vertical="center", wrap_text=True)
        for i, col in enumerate(ws.iter_cols(min_row=1, max_row=1), start=1):
            vals = [len(str(ws.cell(row=r, column=i).value or "")) for r in range(1, min(ws.max_row, 80) + 1)]
            ws.column_dimensions[col[0].column_letter].width = min(max(max(vals) * 1.3 + 4, 10), 52)
        ws.freeze_panes = "A2"
    wb.save(path)


def main():
    os.makedirs(OUTDIR, exist_ok=True)
    df = load()
    months, winners, winner_tbl, piv, cnt = build(df)

    pooled = sorted({a for t in THRESHOLDS for a in winners[t]})
    winner_pivot = df[df["anchor_id"].isin(pooled)].pivot_table(
        index="mth", columns="展示名", values="valid_acu").round(1).reset_index()

    qual = pd.DataFrame([
        ("数据来源", RAW),
        ("样本范围", f"虎视虎啸（抖音）无畏契约主播池，{df['anchor_id'].nunique()} 个主播，{len(df)} 条 主播×月 记录"),
        ("时间范围", f"{min(months)} ~ {max(months)}，共 {len(months)} 个月"),
        ("月度池内主播数", f"{df.groupby('mth').size().min()} ~ {df.groupby('mth').size().max()} 个（池子逐月变动，读达标人数时要连分母一起看）"),
        ("指标口径", "沿用原表 valid_acu 字段（未重算、未改名）；表为 主播×月 粒度，即该主播该月的日均有效ACU"),
        ("达标定义", "该主播在某月 valid_acu ≥ 阈值，即记为「曾经达到过」；按 anchor_id 去重统计人数"),
        ("昵称处理", "同一主播跨月昵称会变（如莫拉塔、谢尔比·李），按 anchor_id 归并，展示名取最近一次昵称"),
        ("缺失月份", "某主播某月无记录则不参与该月计算，折线图在该处断开"),
        ("分层字段", "acu_type 为原表自带分层（头部/腰部/尾部），随月份可能变化，名单中取最近一次"),
        ("待确认", "原表未提供数据字典，valid_acu 的分子分母需业务方确认；若「月日均ACU」另有定义需重算"),
    ], columns=["口径项", "说明"])

    detail = df[["mth", "anchor_id", "nickname", "展示名", "acu_type", "valid_acu", "total_dau", "valid_dau", "view_mins", "rnk"]].copy()
    detail = detail.rename(columns={"mth": "月份", "nickname": "原表昵称", "acu_type": "池内分层",
                                   "valid_acu": "月日均有效ACU", "total_dau": "总DAU", "valid_dau": "有效DAU",
                                   "view_mins": "观看时长(分钟)", "rnk": "池内当月排名"})

    tables = {
        "01_达标主播名单": winner_tbl,
        "02_达标主播逐月ACU": winner_pivot,
        "03_每月达标主播数": cnt,
        "04_全部主播月度明细": detail,
        "05_口径说明": qual,
    }
    to_excel(tables, XLSX)
    plot_trend(months, piv, PNG1)
    plot_counts(cnt, PNG2)

    pd.set_option("display.width", 240)
    pd.set_option("display.max_columns", 30)
    print("=== 达标主播名单 ===")
    print(winner_tbl.to_string(index=False))
    print("\n=== 达标主播逐月ACU ===")
    print(winner_pivot.to_string(index=False))
    print("\n=== 每月达标主播数 ===")
    print(cnt.to_string(index=False))
    print("\n=== 空值检查（条数） ===")
    print(df[["valid_acu", "total_dau", "valid_dau", "view_mins"]].isna().sum().to_string())
    print(f"\n输出：{XLSX}\n输出：{PNG1}\n输出：{PNG2}")


if __name__ == "__main__":
    main()
