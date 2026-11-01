# -*- coding: utf-8 -*-
"""
月子（无畏契约解说，douyin-hushi）二路节目化效果分析

业务目标：
    该主播为虎牙在抖音签约的「虎视」主播，赛事期间做 OB 二路节目化内容
    （赛前炒热点、赛中解说、赛后延续话题）。本脚本用抖音端观时数据检验
    二路节目化前后的有效 ACU 变化趋势，并显式剥离直播时长（live_mins）影响。

输入：C:\\Users\\tiany\\Downloads\\虎视月子（无畏契约）观时数据_V2.csv
输出：月子_二路节目化效果分析_20261016.xlsx（多 sheet）+ 趋势图 PNG

口径说明：
    valid_acu  原始表字段，含义为「有效 ACU」（未在数据字典中确认分子分母）
    live_mins  当日直播时长（分钟）
    view_mins  当日总观看时长（分钟），与主播直播时长无关的总消费量
    valid_dau  原始表字段，含义为「有效 DAU」
    等效平均在线(人) = view_mins / live_mins，用于剥离直播时长对 ACU 的稀释
"""

import os
import numpy as np
import pandas as pd
from openpyxl import load_workbook
from openpyxl.styles import Font, Alignment, PatternFill, Border, Side

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Patch

plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei"]
plt.rcParams["axes.unicode_minus"] = False

RAW = r"C:\Users\tiany\Downloads\虎视月子（无畏契约）观时数据_V2.csv"
OUTDIR = r"C:\Users\tiany\Desktop\无畏契约主播潜力分析\月子二路节目化效果_20261016"
XLSX = os.path.join(OUTDIR, "月子_二路节目化效果分析_20261016.xlsx")
PNG = os.path.join(OUTDIR, "月子_有效ACU趋势_赛事期对比_20261016.png")

# ---------------------------------------------------------------- 期间划分
# 依据 is_big_match 与 match_name，把时间轴切成互斥的「赛事窗口 / 非赛事窗口」
PHASES = [
    ("2026-05-15", "2026-05-17", "基线_赛事前", "非赛事期"),
    ("2026-05-18", "2026-05-31", "赛事1_EWC预选赛+进化者第二幕+不服杯", "赛事期"),
    ("2026-06-06", "2026-06-21", "赛事2_伦敦大师赛", "赛事期"),
    ("2026-06-25", "2026-06-30", "非赛事_6月底", "非赛事期"),
    ("2026-07-02", "2026-07-12", "赛事3_EWC电竞世俱杯", "赛事期"),
    ("2026-07-13", "2026-08-23", "赛事4_VCTCN第二赛段", "赛事期"),
    ("2026-08-24", "2026-09-01", "非赛事_8月底至9月初", "非赛事期"),
    ("2026-09-03", "2026-09-13", "赛事5_进化者第三幕", "赛事期"),
    ("2026-09-15", "2026-09-23", "非赛事_9月中下旬", "非赛事期"),
    ("2026-09-24", "2026-10-07", "赛事6_上海冠军赛", "赛事期"),
    ("2026-10-08", "2026-10-11", "非赛事_10月(最新)", "非赛事期"),
]


def load_data():
    df = pd.read_csv(RAW, encoding="utf-8-sig", dtype={"match_name": "object"})
    df["dt"] = pd.to_datetime(df["dt"], format="%Y/%m/%d")
    df["week_start"] = pd.to_datetime(df["week_start"], format="%Y/%m/%d")
    return df


def build_daily(df):
    """同一 dt 出现多行（同一天多场赛事）时按指标一致性校验后去重合并。"""
    metric_cols = ["total_dau", "valid_dau", "valid_acu", "view_mins",
                   "avg_view_mins", "live_mins", "is_big_match"]
    dup_days = df.groupby("dt").size()
    dup_days = dup_days[dup_days > 1]
    conflict = []
    for d in dup_days.index:
        sub = df[df["dt"] == d]
        if sub[metric_cols].drop_duplicates().shape[0] != 1:
            conflict.append(d.strftime("%Y-%m-%d"))

    agg = df.groupby("dt", as_index=False).agg(
        week_start=("week_start", "first"),
        is_big_match=("is_big_match", "max"),
        match_name=("match_name", lambda s: " / ".join(sorted({x for x in s if isinstance(x, str)})) or "无"),
        total_dau=("total_dau", "first"),
        valid_dau=("valid_dau", "first"),
        valid_acu=("valid_acu", "first"),
        view_mins=("view_mins", "first"),
        avg_view_mins=("avg_view_mins", "first"),
        live_mins=("live_mins", "first"),
    )

    agg["期别"] = np.where(agg["is_big_match"] == 1, "赛事期", "非赛事期")

    def tag_phase(d):
        for s, e, label, kind in PHASES:
            if pd.Timestamp(s) <= d <= pd.Timestamp(e):
                return label
        return "未归类"

    agg["阶段"] = agg["dt"].map(tag_phase)
    agg["阶段类型"] = agg["阶段"].map({p[2]: p[3] for p in PHASES}).fillna(agg["期别"])
    agg["直播小时"] = agg["live_mins"] / 60
    agg["总观看时长_万分钟"] = agg["view_mins"] / 10000
    agg["等效平均在线_按直播时长"] = agg["view_mins"] / agg["live_mins"]
    agg["每有效用户观看分钟"] = agg["view_mins"] / agg["valid_dau"]
    agg["有效DAU占DAU比"] = agg["valid_dau"] / agg["total_dau"]
    agg["有效ACU占有效DAU比"] = agg["valid_acu"] / agg["valid_dau"]
    return agg.sort_values("dt").reset_index(drop=True), dup_days, conflict


def window_summary(daily, phases, title_col="阶段"):
    rows = []
    prev_acu = np.nan
    for s, e, label, kind in phases:
        sub = daily[(daily["dt"] >= pd.Timestamp(s)) & (daily["dt"] <= pd.Timestamp(e))]
        if sub.empty:
            continue
        acu = sub["valid_acu"].mean()
        rows.append({
            title_col: label,
            "期别": kind,
            "起止": f"{s} ~ {e}",
            "开播天数": int(sub["dt"].nunique()),
            "直播时长合计_分钟": int(sub["live_mins"].sum()),
            "日均直播时长_分钟": round(sub["live_mins"].mean(), 1),
            "有效ACU均值": round(acu, 1),
            "有效ACU中位数": round(sub["valid_acu"].median(), 1),
            "有效ACU最大": round(sub["valid_acu"].max(), 1),
            "总观看时长_万分钟": round(sub["view_mins"].sum() / 10000, 1),
            "日均总观看时长_万分钟": round(sub["view_mins"].mean() / 10000, 1),
            "等效平均在线_按直播时长": round(sub["view_mins"].sum() / sub["live_mins"].sum(), 1),
            "日均有效DAU": round(sub["valid_dau"].mean(), 0),
            "相对上一窗口ACU变化": ("" if np.isnan(prev_acu) else f"{acu / prev_acu - 1:+.1%}"),
        })
        prev_acu = acu
    return pd.DataFrame(rows)


def live_mins_strata(daily):
    bins = [0, 120, 240, 360, 480, 10 ** 9]
    labels = ["≤2小时", "2~4小时", "4~6小时", "6~8小时", ">8小时"]
    d = daily.copy()
    d["直播时长档"] = pd.cut(d["live_mins"], bins=bins, labels=labels, right=True)
    out = []
    for kind in ["赛事期", "非赛事期"]:
        sub = d[d["期别"] == kind]
        for lab in labels:
            s = sub[sub["直播时长档"] == lab]
            if s.empty:
                continue
            out.append({
                "期别": kind,
                "直播时长档": lab,
                "天数": len(s),
                "直播时长均值_分钟": round(s["live_mins"].mean(), 1),
                "有效ACU均值": round(s["valid_acu"].mean(), 1),
                "等效平均在线": round(s["view_mins"].sum() / s["live_mins"].sum(), 1),
                "日均总观看时长_万分钟": round(s["view_mins"].mean() / 10000, 1),
            })
    return pd.DataFrame(out)


def quality_report(df, daily, dup_days, conflict):
    full_range = pd.date_range(daily["dt"].min(), daily["dt"].max(), freq="D")
    missing = sorted(set(full_range) - set(daily["dt"]))
    ratio = (df["valid_dau"] / df["total_dau"]).round(6).unique()
    identity = np.allclose(df["view_mins"], df["valid_acu"] * df["avg_view_mins"], rtol=1e-9)
    rows = [
        ("原始行数", len(df)),
        ("去重后自然日行数", len(daily)),
        ("重复日期行数（同日多场赛事）", len(dup_days)),
        ("重复日期明细", ", ".join(f"{d:%Y-%m-%d}({n}行)" for d, n in dup_days.items())),
        ("重复行关键指标是否完全一致", "一致" if not conflict else f"存在冲突：{conflict}"),
        ("日期范围", f"{daily['dt'].min():%Y-%m-%d} ~ {daily['dt'].max():%Y-%m-%d}"),
        ("区间内未出现日期数", len(missing)),
        ("未出现日期", ", ".join(f"{d:%Y-%m-%d}" for d in missing)),
        ("valid_dau/total_dau 取值", ", ".join(str(x) for x in ratio)),
        ("view_mins ≡ valid_acu × avg_view_mins", "成立（全表精确相等）" if identity else "不成立"),
        ("live_mins 取值（分钟）", ", ".join(str(int(x)) for x in sorted(df["live_mins"].unique()))),
        ("赛事期天数", int((daily["期别"] == "赛事期").sum())),
        ("非赛事期天数", int((daily["期别"] == "非赛事期").sum())),
        ("未归类天数", int((daily["阶段"] == "未归类").sum())),
    ]
    return pd.DataFrame(rows, columns=["检查项", "结果"])


def caliber_table():
    rows = [
        ("数据来源文件", RAW),
        ("平台标识", "douyin-hushi（虎牙在抖音签约的虎视主播，抖音端观时数据）"),
        ("样本范围", "单主播 anchor_id=59475730286（月子（无畏契约解说））；单日粒度"),
        ("时间范围", "2026-05-15 ~ 2026-10-11（文件内实际可取数止于 2026-10-11）"),
        ("赛事期判定", "is_big_match = 1，且与 match_name 标注的赛事日程逐日核对"),
        ("非赛事期判定", "is_big_match = 0"),
        ("valid_acu", "沿用原始表字段，未做任何重命名/换算；分子分母需业务方确认"),
        ("live_mins", "当日直播时长（分钟），原始表字段"),
        ("view_mins", "当日总观看时长（分钟），与直播时长无关的总消费量"),
        ("等效平均在线_按直播时长", "view_mins / live_mins，用于剥离直播时长差异后的规模口径（自建，非原始表字段）"),
        ("聚合方式", "窗口内 有效ACU 取算术均值；规模类指标取合计；等效平均在线取 Σview_mins / Σlive_mins"),
        ("去重规则", "同一 dt 多行（同日多场赛事）指标一致，按 dt 保留 1 行，match_name 合并展示"),
    ]
    return pd.DataFrame(rows, columns=["口径项", "说明"])


def period_overall(daily):
    rows = []
    for kind in ["赛事期", "非赛事期", "全部"]:
        sub = daily if kind == "全部" else daily[daily["期别"] == kind]
        rows.append({
            "期别": kind,
            "开播天数": len(sub),
            "天数占比": f"{len(sub) / len(daily):.1%}",
            "直播时长合计_分钟": int(sub["live_mins"].sum()),
            "日均直播时长_分钟": round(sub["live_mins"].mean(), 1),
            "有效ACU均值": round(sub["valid_acu"].mean(), 1),
            "有效ACU中位数": round(sub["valid_acu"].median(), 1),
            "有效ACU_P25": round(sub["valid_acu"].quantile(0.25), 1),
            "有效ACU_P75": round(sub["valid_acu"].quantile(0.75), 1),
            "总观看时长_万分钟": round(sub["view_mins"].sum() / 10000, 1),
            "日均总观看时长_万分钟": round(sub["view_mins"].mean() / 10000, 1),
            "等效平均在线_按直播时长": round(sub["view_mins"].sum() / sub["live_mins"].sum(), 1),
            "日均有效DAU": round(sub["valid_dau"].mean(), 0),
        })
    return pd.DataFrame(rows)


def post_event_retention(daily, overall):
    """赛事结束后紧邻的非赛事窗口水位：用「赛后非赛事窗口 ACU / 前一赛事窗口 ACU」做热度保持率代理。"""
    pairs = [
        ("赛事2_伦敦大师赛", "06-21", "非赛事_6月底"),
        ("赛事4_VCTCN第二赛段", "08-23", "非赛事_8月底至9月初"),
        ("赛事5_进化者第三幕", "09-13", "非赛事_9月中下旬"),
        ("赛事6_上海冠军赛", "10-07", "非赛事_10月(最新)"),
    ]
    rows = []
    for ev, end_md, post in pairs:
        ev_row = overall[overall["阶段"] == ev].iloc[0]
        post_row = overall[overall["阶段"] == post].iloc[0]
        first_day = daily[daily["dt"] > f"2026-{end_md}"].sort_values("dt").head(1)
        rows.append({
            "赛事窗口": ev,
            "赛事结束日": f"2026-{end_md}",
            "紧邻赛后的非赛事窗口": post,
            "赛事期有效ACU均值": ev_row["有效ACU均值"],
            "赛后非赛事期有效ACU均值": post_row["有效ACU均值"],
            "赛后ACU保持率": f"{post_row['有效ACU均值'] / ev_row['有效ACU均值']:.1%}",
            "赛事期日均直播_分钟": ev_row["日均直播时长_分钟"],
            "赛后日均直播_分钟": post_row["日均直播时长_分钟"],
            "赛事结束首个开播日": first_day["dt"].dt.strftime("%Y-%m-%d").iloc[0] if len(first_day) else "",
            "首个开播日有效ACU": round(first_day["valid_acu"].iloc[0], 1) if len(first_day) else np.nan,
            "首个开播日直播时长_分钟": int(first_day["live_mins"].iloc[0]) if len(first_day) else np.nan,
        })
    return pd.DataFrame(rows)


def monthly_summary(daily):
    rows = []
    for m in sorted(daily["dt"].dt.to_period("M").unique()):
        sub = daily[daily["dt"].dt.to_period("M") == m]
        rows.append({
            "月份": str(m),
            "开播天数": len(sub),
            "赛事期天数": int((sub["期别"] == "赛事期").sum()),
            "日均直播时长_分钟": round(sub["live_mins"].mean(), 1),
            "有效ACU均值": round(sub["valid_acu"].mean(), 1),
            "赛事期ACU均值": round(sub[sub["期别"] == "赛事期"]["valid_acu"].mean(), 1) if (sub["期别"] == "赛事期").any() else np.nan,
            "非赛事期ACU均值": round(sub[sub["期别"] == "非赛事期"]["valid_acu"].mean(), 1) if (sub["期别"] == "非赛事期").any() else np.nan,
            "日均总观看时长_万分钟": round(sub["view_mins"].mean() / 10000, 1),
            "等效平均在线_按直播时长": round(sub["view_mins"].sum() / sub["live_mins"].sum(), 1),
        })
    return pd.DataFrame(rows)


def matched_duration_compare(daily, overall, pairs):
    """live_mins 为 60 分钟整数倍，可直接按相同直播时长做精确匹配，剥离时长差异后再比 ACU。"""
    rows = []
    for a, b in pairs:
        ra = overall[overall["阶段"] == a].iloc[0]
        rb = overall[overall["阶段"] == b].iloc[0]
        sa = daily[daily["阶段"] == a]
        sb = daily[daily["阶段"] == b]
        common = sorted(set(sa["live_mins"]).intersection(set(sb["live_mins"])))
        ma = sa[sa["live_mins"].isin(common)]
        mb = sb[sb["live_mins"].isin(common)]
        rows.append({
            "对比": f"{a} vs {b}",
            "共同直播时长档_分钟": ", ".join(str(int(x)) for x in common) or "无重叠",
            "A_匹配后天数": len(ma), "A_匹配后ACU均值": round(ma["valid_acu"].mean(), 1) if len(ma) else np.nan,
            "B_匹配后天数": len(mb), "B_匹配后ACU均值": round(mb["valid_acu"].mean(), 1) if len(mb) else np.nan,
            "匹配后ACU倍数(B/A)": round(mb["valid_acu"].mean() / ma["valid_acu"].mean(), 2) if len(ma) and len(mb) else np.nan,
            "未匹配_A全窗口ACU": ra["有效ACU均值"], "未匹配_B全窗口ACU": rb["有效ACU均值"],
            "未匹配ACU倍数(B/A)": round(rb["有效ACU均值"] / ra["有效ACU均值"], 2),
        })
    return pd.DataFrame(rows)


def to_excel(tables, path):
    with pd.ExcelWriter(path, engine="openpyxl") as w:
        for sheet, df in tables.items():
            df.to_excel(w, sheet_name=sheet[:31], index=False)
    wb = load_workbook(path)
    head_fill = PatternFill("solid", fgColor="DCE6F1")
    thin = Side(style="thin", color="BFBFBF")
    border = Border(left=thin, right=thin, top=thin, bottom=thin)
    for ws in wb.worksheets:
        for c in ws[1]:
            c.font = Font(name="楷体", size=11, bold=True)
            c.fill = head_fill
            c.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
            c.border = border
        for row in ws.iter_rows(min_row=2):
            for c in row:
                num = isinstance(c.value, (int, float)) and not isinstance(c.value, bool)
                c.font = Font(name="Calibri" if num else "楷体", size=10)
                c.border = border
                if num:
                    c.number_format = "#,##0.0" if isinstance(c.value, float) else "#,##0"
                else:
                    c.alignment = Alignment(vertical="center", wrap_text=True)
        for i, col in enumerate(ws.iter_cols(min_row=1, max_row=1), start=1):
            vals = [len(str(ws.cell(row=r, column=i).value or "")) for r in range(1, min(ws.max_row, 60) + 1)]
            ws.column_dimensions[col[0].column_letter].width = min(max(max(vals) * 1.4 + 4, 10), 60)
        ws.freeze_panes = "A2"
    wb.save(path)


def plot_trend(daily, path):
    fig, axes = plt.subplots(2, 1, figsize=(15, 8.5), sharex=True,
                             gridspec_kw={"height_ratios": [3, 1.2], "hspace": 0.12})
    ax, ax2 = axes
    for s, e, label, kind in PHASES:
        if kind == "赛事期":
            ax.axvspan(pd.Timestamp(s), pd.Timestamp(e), color="#F4C7C3", alpha=0.45, lw=0)
            ax2.axvspan(pd.Timestamp(s), pd.Timestamp(e), color="#F4C7C3", alpha=0.45, lw=0)
    ax.plot(daily["dt"], daily["valid_acu"], marker="o", ms=3.5, lw=1.2, color="#1F4E79", label="有效ACU（原始字段）")
    ax.plot(daily["dt"], daily["等效平均在线_按直播时长"], marker="s", ms=3, lw=1.1,
            color="#ED7D31", linestyle="--", label="等效平均在线＝总观看时长÷直播时长（剥离直播时长）")
    ax.set_ylabel("人数")
    ax.set_title("月子（无畏契约解说，douyin-hushi）有效ACU趋势｜粉色区间＝大赛事期（is_big_match=1）", fontsize=13)
    ax.grid(alpha=0.25, linestyle=":")
    ax.legend(loc="upper left", frameon=False)
    ax.set_ylim(bottom=0)
    ax2.bar(daily["dt"], daily["live_mins"] / 60, width=0.8, color="#8FAADC")
    ax2.set_ylabel("直播时长\n(小时)")
    ax2.grid(alpha=0.25, linestyle=":", axis="y")
    ax2.set_xlabel("日期")
    fig.autofmt_xdate(rotation=45)
    fig.subplots_adjust(left=0.07, right=0.99, top=0.93, bottom=0.13)
    fig.savefig(path, dpi=170, bbox_inches="tight")
    plt.close(fig)


def main():
    os.makedirs(OUTDIR, exist_ok=True)
    df = load_data()
    daily, dup_days, conflict = build_daily(df)

    detail = daily[["dt", "week_start", "期别", "阶段", "match_name", "live_mins", "直播小时",
                    "valid_acu", "等效平均在线_按直播时长", "total_dau", "valid_dau", "每有效用户观看分钟",
                    "总观看时长_万分钟", "avg_view_mins"]].copy()
    detail["dt"] = detail["dt"].dt.strftime("%Y-%m-%d")
    detail["week_start"] = detail["week_start"].dt.strftime("%Y-%m-%d")
    detail = detail.rename(columns={
        "dt": "日期", "week_start": "周起始", "match_name": "赛事名称(合并)",
        "live_mins": "直播时长(分钟)", "valid_acu": "有效ACU",
        "total_dau": "总DAU", "valid_dau": "有效DAU", "avg_view_mins": "原始字段avg_view_mins",
    })
    for c in ["有效ACU", "等效平均在线_按直播时长", "直播小时", "每有效用户观看分钟",
              "总观看时长_万分钟", "原始字段avg_view_mins"]:
        detail[c] = detail[c].round(2)

    untagged = daily[daily["阶段"] == "未归类"]
    if not untagged.empty:
        print("【警告】存在未归入任何窗口的日期：", ", ".join(untagged["dt"].dt.strftime("%Y-%m-%d")))

    windows = window_summary(daily, PHASES)
    overall = pd.concat([period_overall(daily).assign(阶段="【整体】赛事期/非赛事期").rename(columns={"期别": "期别"}), windows], ignore_index=True)

    race = windows[windows["期别"] == "赛事期"].reset_index(drop=True)
    race["相对首个赛事窗口ACU倍数"] = (race["有效ACU均值"] / race.loc[0, "有效ACU均值"]).round(2)
    race["相对首个赛事窗口观看时长倍数"] = (race["日均总观看时长_万分钟"] / race.loc[0, "日均总观看时长_万分钟"]).round(2)

    non = windows[windows["期别"] == "非赛事期"].reset_index(drop=True)
    non["相对基线(5/15-5/17)ACU倍数"] = (non["有效ACU均值"] / non.loc[0, "有效ACU均值"]).round(2)
    non["相对基线观看时长倍数"] = (non["日均总观看时长_万分钟"] / non.loc[0, "日均总观看时长_万分钟"]).round(2)

    strata = live_mins_strata(daily)
    qual = quality_report(df, daily, dup_days, conflict)
    cal = caliber_table()
    retention = post_event_retention(daily, overall)
    monthly = monthly_summary(daily)
    matched = matched_duration_compare(daily, overall, [
        ("赛事1_EWC预选赛+进化者第二幕+不服杯", "赛事6_上海冠军赛"),
        ("赛事2_伦敦大师赛", "赛事6_上海冠军赛"),
        ("基线_赛事前", "非赛事_10月(最新)"),
        ("非赛事_6月底", "非赛事_10月(最新)"),
        ("非赛事_8月底至9月初", "非赛事_10月(最新)"),
    ])

    # 相关性：直播时长 与 有效ACU（原始 & 分层内）
    corr_rows = []
    for name, sub in [("全部日期", daily),
                      ("赛事期", daily[daily["期别"] == "赛事期"]),
                      ("非赛事期", daily[daily["期别"] == "非赛事期"])]:
        if len(sub) > 2:
            corr_rows.append({
                "子样本": name, "天数": len(sub),
                "Pearson(直播时长,有效ACU)": round(sub["live_mins"].corr(sub["valid_acu"]), 3),
                "Spearman(直播时长,有效ACU)": round(sub["live_mins"].corr(sub["valid_acu"], method="spearman"), 3),
                "Pearson(直播时长,等效平均在线)": round(sub["live_mins"].corr(sub["等效平均在线_按直播时长"]), 3),
            })
    corr = pd.DataFrame(corr_rows)

    tables = {
        "01_每日明细": detail,
        "09_赛事期vs非赛事期": period_overall(daily),
        "02_各窗口汇总": overall,
        "03_赛事窗口对比": race,
        "04_非赛事窗口对比": non,
        "05_直播时长分层": strata,
        "10_同直播时长匹配对比": matched,
        "11_赛事后热度保持率": retention,
        "12_月度水位": monthly,
        "06_直播时长与ACU相关性": corr,
        "07_数据质量检查": qual,
        "08_口径说明": cal,
    }
    to_excel(tables, XLSX)
    plot_trend(daily, PNG)

    pd.set_option("display.width", 220)
    pd.set_option("display.max_columns", 40)
    print("=== 数据质量 ===")
    print(qual.to_string(index=False))
    print("\n=== 各窗口汇总 ===")
    print(overall.to_string(index=False))
    print("\n=== 赛事窗口对比 ===")
    print(race.to_string(index=False))
    print("\n=== 非赛事窗口对比 ===")
    print(non.to_string(index=False))
    print("\n=== 直播时长分层 ===")
    print(strata.to_string(index=False))
    print("\n=== 相关性 ===")
    print(corr.to_string(index=False))
    print("\n=== 赛事期 vs 非赛事期（整体） ===")
    print(period_overall(daily).to_string(index=False))
    print("\n=== 同直播时长匹配对比 ===")
    print(matched.to_string(index=False))
    print("\n=== 赛事后热度保持率 ===")
    print(retention.to_string(index=False))
    print("\n=== 月度水位 ===")
    print(monthly.to_string(index=False))
    print(f"\n输出：{XLSX}\n输出：{PNG}")


if __name__ == "__main__":
    main()
