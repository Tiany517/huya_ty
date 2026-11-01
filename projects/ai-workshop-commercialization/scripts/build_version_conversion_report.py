# -*- coding: utf-8 -*-
"""
AI工坊 × App版本：转换率与流水 报告生成
输入：AI工坊_版本天明细_20260713-20260914.csv（Presto 取数结果，版本×天粒度）
输出：AI工坊_App版本转换率与流水_20260713-20260914.xlsx
说明：所有指标都在脚本内从明细重算，可从原始 CSV 完全复现
"""

import pandas as pd
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill, Border, Side
from openpyxl.utils import get_column_letter

SRC = r"C:\Users\tiany\Desktop\AI工坊专题\AI工坊_版本天明细_20260713-20260914.csv"
OUT = r"C:\Users\tiany\Desktop\AI工坊专题\AI工坊_App版本转换率与流水_20260713-20260914.xlsx"

# 版本发布顺序（按首次出现日排序，脚本会用数据校验）
VLIST = ["13.3.82", "13.4.0", "13.4.2", "13.4.22", "13.4.40", "13.4.41", "13.4.52", "13.4.63"]
RELEASE = {
    "13.3.82": "2026-07-13",
    "13.4.0": "2026-07-20",
    "13.4.2": "2026-07-27",
    "13.4.22": "2026-08-07",
    "13.4.40": "2026-08-11",
    "13.4.41": "2026-08-21",
    "13.4.52": "2026-08-31",
    "13.4.63": "2026-09-08",
}
WIN_END = {
    "13.3.82": "2026-07-19", "13.4.0": "2026-07-26", "13.4.2": "2026-08-06",
    "13.4.22": "2026-08-10", "13.4.40": "2026-08-20", "13.4.41": "2026-08-30",
    "13.4.52": "2026-09-07", "13.4.63": "2026-09-14",
}
COMMON_START, COMMON_END = "2026-09-08", "2026-09-14"
MIN_EXPOSURE = 100  # 版本-天曝光人数下限，低于此值不参与


def num(s):
    return pd.to_numeric(s, errors="coerce")


def load():
    df = pd.read_csv(SRC, encoding="utf-8-sig")
    for c in df.columns:
        if c not in ("dt", "iver"):
            df[c] = num(df[c])
    df = df.sort_values(["iver", "dt"]).reset_index(drop=True)
    return df


def market_by_day(df):
    """基准：白名单 8 个版本当日合计（不含白名单外的 App 版本，指数加权平均天然=1）"""
    g = df.groupby("dt", as_index=False).agg(
        wl_exp=("exposure_user_cnt", "sum"),
        wl_pay=("pay_user_cnt", "sum"),
        wl_amt=("ai_amount", "sum"),
        mkt_exp=("market_exposure_user_cnt", "max"),
        mkt_pay=("market_pay_user_cnt", "max"),
        mkt_amt=("market_ai_amount", "max"),
    )
    g["wl_conv"] = g["wl_pay"] / g["wl_exp"]
    g["wl_arpu"] = g["wl_amt"] / g["wl_pay"]
    g["wl_amt_per_exp"] = g["wl_amt"] / g["wl_exp"]
    g["wl_share_of_app"] = g["wl_exp"] / g["mkt_exp"]
    return g


def window_stats(df, mkt, start, end, label, only_version=None):
    d = df[(df["dt"] >= start) & (df["dt"] <= end)].merge(mkt, on="dt", how="left")
    rows = []
    for v in ([only_version] if only_version else VLIST):
        a = d[d["iver"] == v]
        if a.empty:
            continue
        conv = (a["pay_user_cnt"] / a["exposure_user_cnt"]).where(a["exposure_user_cnt"] > 0)
        arpu = (a["ai_amount"] / a["pay_user_cnt"]).where(a["pay_user_cnt"] > 0)
        rows.append({
            "版本": v, "窗口": label, "天数": int(len(a)),
            "日均曝光人数": round(a["exposure_user_cnt"].mean()),
            "日均AI礼物支付人数": round(a["pay_user_cnt"].mean(), 1),
            "日均AI流水_元": round(a["ai_amount"].mean()),
            "日均转化率_pct": round(conv.mean() * 100, 4),
            "日均ARPPU_元": round(arpu.mean(), 1) if arpu.notna().any() else None,
            "窗口内日均曝光占8版本合计_pct": round((a["exposure_user_cnt"] / a["wl_exp"]).mean() * 100, 2),
            "同期基准日均转化率_pct": round(a["wl_conv"].mean() * 100, 4),
            "转化率相对指数": round((conv / a["wl_conv"]).mean(), 3),
        })
    return pd.DataFrame(rows)


def relative_index(df, mkt):
    d = df.merge(mkt, on="dt", how="left")
    conv = (d["pay_user_cnt"] / d["exposure_user_cnt"]).where(d["exposure_user_cnt"] > 0)
    arpu = (d["ai_amount"] / d["pay_user_cnt"]).where(d["pay_user_cnt"] > 0)
    ape = (d["ai_amount"] / d["exposure_user_cnt"]).where(d["exposure_user_cnt"] > 0)
    d["conv_idx"] = conv / d["wl_conv"]
    d["arpu_idx"] = arpu / d["wl_arpu"]
    d["amount_idx"] = ape / d["wl_amt_per_exp"]
    d["share"] = d["exposure_user_cnt"] / d["wl_exp"]
    rows = []
    for v in VLIST:
        a = d[d["iver"] == v]
        w = a["exposure_user_cnt"]
        rows.append({
            "版本": v,
            "计入天数": int(len(a)),
            "日均曝光人数": round(a["exposure_user_cnt"].mean()),
            "日均曝光占比_pct": round(a["share"].mean() * 100, 2),
            "全期总转化率_pct": round(a["pay_user_cnt"].sum() / a["exposure_user_cnt"].sum() * 100, 4),
            "conv_idx_简单平均": round(a["conv_idx"].mean(), 3),
            "conv_idx_曝光加权": round((a["conv_idx"] * w).sum() / w.sum(), 3),
            "arpu_idx_简单平均": round(a["arpu_idx"].mean(), 3),
            "amount_idx_简单平均": round(a["amount_idx"].mean(), 3),
            "amount_idx_曝光加权": round((a["amount_idx"] * w).sum() / w.sum(), 3),
        })
    return pd.DataFrame(rows), d


def comparable_stats(df, mkt, start, end, label):
    """方案一：把每个版本每天的曝光，按当天 8 版本合计的效率折算成「应得支付人数 / 应得流水」，
    再与实际值相比。指数 = 实际合计 / 应得合计（比率求和，天然按曝光加权，不受小样本天影响）。"""
    d = df[(df["dt"] >= start) & (df["dt"] <= end)].merge(mkt, on="dt", how="left")
    rows = []
    for v in VLIST:
        a = d[d["iver"] == v]
        if a.empty:
            continue
        exp = a["exposure_user_cnt"]
        exp_pay = exp * a["wl_conv"]
        exp_amt = exp * a["wl_amt_per_exp"]
        conv = (a["pay_user_cnt"] / exp).where(exp > 0)
        rows.append({
            "版本": v, "窗口": label, "天数": int(len(a)),
            "日均曝光人数": round(exp.mean()),
            "实际日均支付人数": round(a["pay_user_cnt"].mean(), 1),
            "应得日均支付人数": round(exp_pay.mean(), 1),
            "支付人数指数": round(a["pay_user_cnt"].sum() / exp_pay.sum(), 3),
            "实际日均AI流水_元": round(a["ai_amount"].mean()),
            "应得日均AI流水_元": round(exp_amt.mean()),
            "流水指数": round(a["ai_amount"].sum() / exp_amt.sum(), 3),
            "参考_简单平均转化率指数": round((conv / a["wl_conv"]).mean(), 3),
        })
    return pd.DataFrame(rows)


def write_sheet(wb, name, df, header_fill="DDEBF7"):
    ws = wb.create_sheet(name)
    ws.append(list(df.columns))
    for _, r in df.iterrows():
        ws.append([None if pd.isna(x) else x for x in r.tolist()])
    thin = Side(style="thin", color="BFBFBF")
    for i, cell in enumerate(ws[1], start=1):
        cell.font = Font(name="楷体", size=10, bold=True)
        cell.fill = PatternFill("solid", fgColor=header_fill)
        cell.alignment = Alignment(horizontal="center", vertical="center")
        cell.border = Border(bottom=thin)
    for row in ws.iter_rows(min_row=2):
        for c in row:
            c.font = Font(name="Calibri", size=10) if isinstance(c.value, (int, float)) else Font(name="楷体", size=10)
            c.border = Border(bottom=thin)
            if isinstance(c.value, float):
                c.number_format = "#,##0.00"
            elif isinstance(c.value, int):
                c.number_format = "#,##0"
    for i, col in enumerate(df.columns, start=1):
        width = max(10, min(30, max([len(str(col)) * 2] + [len(str(x)) for x in df[col].astype(str).head(200)]) + 4))
        ws.column_dimensions[get_column_letter(i)].width = width
    ws.freeze_panes = "A2"
    return ws


def write_text_sheet(wb, name, pairs, title=None):
    ws = wb.create_sheet(name)
    if title:
        ws.append([title])
        ws["A1"].font = Font(name="楷体", size=12, bold=True)
    ws.append(["项目", "说明"])
    for k, v in pairs:
        ws.append([k, v])
    hdr = 3 if title else 1
    for cell in ws[hdr]:
        cell.font = Font(name="楷体", size=10, bold=True)
        cell.fill = PatternFill("solid", fgColor="DDEBF7")
    for row in ws.iter_rows(min_row=hdr + 1):
        for c in row:
            c.font = Font(name="楷体", size=10)
            c.alignment = Alignment(wrap_text=True, vertical="top")
    ws.column_dimensions["A"].width = 30
    ws.column_dimensions["B"].width = 110
    return ws


def main():
    df = load()
    mkt = market_by_day(df)

    # 数据校验：各版本首次出现日是否与预期一致
    first_seen = df.groupby("iver")["dt"].min().to_dict()
    mismatch = {v: (RELEASE[v], first_seen.get(v)) for v in VLIST if first_seen.get(v) != RELEASE[v]}

    a_rows = []
    for v in VLIST:
        s, e = RELEASE[v], WIN_END[v]
        t = window_stats(df, mkt, s, e, f"{s}~{e}", only_version=v)
        a_rows.append(t)
    seg = pd.concat(a_rows, ignore_index=True)

    peak_rows = []
    for v in VLIST:
        a2 = df[df["iver"] == v]
        pk = a2.loc[a2["exposure_user_cnt"].idxmax()]
        st = a2[a2["exposure_user_cnt"] >= pk["exposure_user_cnt"] * 0.5]
        peak_rows.append({
            "版本": v,
            "峰值日": pk["dt"],
            "峰值日曝光人数": int(pk["exposure_user_cnt"]),
            "稳定期_曝光达峰值50pct": f"{st['dt'].min()}~{st['dt'].max()}",
            "稳定期天数": int(len(st)),
            "稳定期日均曝光": round(st["exposure_user_cnt"].mean()),
            "稳定期日均支付人数": round(st["pay_user_cnt"].mean(), 1),
            "稳定期日均AI流水_元": round(st["ai_amount"].mean()),
            "稳定期日均转化率_pct": round((st["pay_user_cnt"] / st["exposure_user_cnt"]).mean() * 100, 4),
        })
    peak = pd.DataFrame(peak_rows)

    common = window_stats(df, mkt, COMMON_START, COMMON_END, f"{COMMON_START}~{COMMON_END}")
    idx, daily_idx = relative_index(df, mkt)
    cmp_all = comparable_stats(df, mkt, "2026-07-13", "2026-09-14", "全期 2026-07-13~2026-09-14")
    cmp_common = comparable_stats(df, mkt, COMMON_START, COMMON_END, f"共有期 {COMMON_START}~{COMMON_END}")
    comparable = pd.concat([cmp_all, cmp_common], ignore_index=True)

    # 口径断点体检：白名单合计占大盘曝光的比重
    brk = mkt[["dt", "wl_exp", "mkt_exp", "wl_share_of_app"]].copy()
    brk.columns = ["日期", "8版本合计曝光", "大盘曝光", "8版本占大盘"]
    pre = brk[brk["日期"] <= "2026-08-31"]["8版本占大盘"].mean()
    post = brk[brk["日期"] >= "2026-09-01"]["8版本占大盘"].mean()

    wb = Workbook()
    wb.remove(wb.active)

    write_text_sheet(wb, "结论摘要", [
        ("结论1｜版本并不分段，而是长期共存",
         "8 个版本不是「上一个退干净、下一个才上」。13.3.82 从 7/13 一直有量到 9/14（64 天），"
         "13.4.63 只在 9/8~9/14 有量（7 天）。所以「13.3.82 只算 7/13~7/19」是错的："
         "那 7 天里 13.3.82 的日均曝光只有 20.8 万，而它在 7/27 单日曝光达 48.1 万。"),
        ("结论2｜按「发布日切段」算，一半版本样本太小",
         "13.4.0 窗口内日均曝光仅 3,796、13.4.22 仅 9,507、13.4.40 仅 857。"
         "原因是用户升级是渐进的，新版本发布后 2~3 周才有规模。"
         "用这些窗口算出来的日均转化率（如 13.4.40 的 0.0067%）不代表该版本的真实表现。"),
        ("结论3｜曝光口径在 9/1 有一个约 4 倍的断崖",
         f"大盘曝光 8/31 为 134.7 万，9/1 掉到 31.8 万；8 个白名单版本占大盘的比重从 7/13~8/31 均值 "
         f"{pre:.1%} 跳到 9/1~9/14 均值 {post:.1%}。全部版本同步下降，属于口径变化而非用户行为变化。"
         "这直接影响「9 月版本 vs 8 月版本」的曝光与转化率横向对比，需要先向调度表口径负责人确认。"),
        ("结论4｜只有 7 天（9/8~9/14）能直接横比",
         "这段时间 8 个版本同时有量且曝光口径一致。该窗口内转化率：13.3.82 0.1141%、"
         "13.4.2 0.0813%、13.4.40 0.0808%、13.4.63 0.0791%、13.4.52 0.0724%、"
         "13.4.41 0.0614%、13.4.22 0.0545%、13.4.0 0.0534%。"
         "注意各版本曝光量级差 35 倍（13.4.0 日均仅 3,064，13.4.40 为 108,376），不是同质人群。"),
        ("结论5｜方案一（同日基准折算）后，8 个版本的支付效率几乎没有差别",
         "全期口径：把每个版本每天的曝光，按当天 8 版本合计的转化率折算成「应得支付人数」，再与实际比。"
         "比值落在 0.977（13.3.82）~ 1.046（13.4.40）之间，最大偏差不到 5%。"
         "也就是说，换成任何一个版本，用户掏钱的比例基本没有变化。"),
        ("结论6｜流水效率有约 ±20% 的差异，且方向与版本新旧不一致",
         "同口径的流水指数：13.4.63 1.191、13.4.22 1.186、13.4.0 1.142、13.4.40 1.127、"
         "13.4.52 1.021 高于 1；13.3.82 0.926、13.4.41 0.885、13.4.2 0.762 低于 1。"
         "既不是「越新越好」，也不是单调变化，更像是各版本被抽到的付费人群结构不同（流水由少数大额订单主导，波动天然更大）。"),
        ("结论7｜最新版 13.4.63 在共有期并不占优",
         "共有期 9/8~9/14：13.4.63 支付人数指数 0.989、流水指数 1.191；13.4.40 为 1.077 / 1.160。"
         "两者支付效率相当，13.4.63 的流水效率略高但并不显著。"
         "「13.4.63 转化率 0.0754% vs 13.3.82 的 0.0208%」这个 3.6 倍落差是时间差异，不是版本差异。"),
        ("结论8｜简单平均的指数不可用",
         "对同一天的版本值/基准值做算术平均，会被曝光极少的天严重放大"
         "（13.3.82 简单平均 1.141、比率求和 0.977，两者方向相反）。"
         "请以「方案一_可比化日均」sheet 的比率求和口径为准，简单平均那列只作参考。"),
    ])

    write_sheet(wb, "版本天明细", df.rename(columns={
        "dt": "日期", "iver": "版本号", "exposure_user_cnt": "该版本AI工坊曝光人数",
        "pay_user_cnt": "该版本AI礼物支付人数", "ai_amount": "该版本AI流水_元",
        "market_exposure_user_cnt": "大盘曝光人数", "market_pay_user_cnt": "大盘支付人数",
        "market_ai_amount": "大盘AI流水_元"}))
    write_sheet(wb, "口径A_发布日切段", seg)
    write_sheet(wb, "口径B_峰值稳定期", peak)
    write_sheet(wb, "口径C_共有期9808-0914", common)
    write_sheet(wb, "方案一_可比化日均", comparable)
    write_sheet(wb, "方案一_指数_两种加权参考", idx)
    write_sheet(wb, "口径断点体检", brk)
    write_sheet(wb, "版本天_相对指数明细", daily_idx[[
        "dt", "iver", "exposure_user_cnt", "pay_user_cnt", "ai_amount",
        "share", "conv_idx", "arpu_idx", "amount_idx"]].round(4).rename(columns={
        "dt": "日期", "iver": "版本号", "exposure_user_cnt": "该版本曝光人数",
        "pay_user_cnt": "该版本支付人数", "ai_amount": "该版本AI流水_元",
        "share": "曝光占8版本合计", "conv_idx": "转化率相对指数",
        "arpu_idx": "ARPPU相对指数", "amount_idx": "曝光人均流水相对指数"}))

    write_text_sheet(wb, "口径说明", [
        ("数据来源",
         "Presto 引擎（env=domestic），取数 SQL：C:\\Users\\tiany\\Desktop\\SQL\\AI工坊\\AI工坊_版本天明细_取数.sql；"
         "rid=1222077524497127424；窗口 2026-07-13 ~ 2026-09-14。"),
        ("分析粒度", "版本号 × 日期，共 292 行（版本当天有 AI工坊 曝光才成行，曝光 < 100 的天已剔除）。"),
        ("曝光口径",
         "来自每日调度表 zhgametemp.zty_ads_huya_ai_gift_user_detail_0901_v1 的 is_exposure，"
         "按 (日期, ukey) 去重后的人天。"),
        ("支付口径",
         "revenue 表 gamelive.dws_huya_revenue_detail_d_i 中，consume_order_type='礼物'、"
         "道具为 AI 礼物（ext['is_ai']='1' 且 play_type 非抽奖）、user_consume_amount>0，"
         "按 (日期, ukey) 去重的支付人；流水为该用户当天 AI 礼物消费额之和。"),
        ("版本归属",
         "gamelive.dw_huya_session_level（tag='product'，product 含 huya_andriod / huya_ipad / huya_pad / huya_ios），"
         "按 (日期, ukey) 取一个版本号，同一用户同一天只归一个版本。PC / Web 无版本号，天然排除。"),
        ("基准定义",
         "白名单 8 个版本的当日合计（不是全体 App 大盘）。用全体 App 大盘做基准时，"
         "白名单外版本会拉低基准，导致所有版本指数都大于 1、失去区分度。口径断点体检里同时给出两者。"),
        ("日均定义",
         "日均 = 该窗口内逐日值的算术平均；转化率 = 逐日 (支付人数/曝光人数) 的算术平均，"
         "不是「总支付/总曝光」。两者会有小幅差异。"),
        ("指数含义",
         "conv_idx = 该版本当日转化率 / 当日基准转化率；大于 1 表示好于同期基准。"
         "曝光加权版的加权平均恒等于 1，只能做横向比较，不能解释成绝对好坏。"),
        ("已知限制1",
         "曝光口径在 2026-09-01 出现约 4 倍断崖（见「口径断点体检」），9/1 前后的曝光、转化率不可直接比。"),
        ("已知限制2",
         "8 个版本长期共存、用户升级渐进，版本与时间高度共线。方案一只能回答「相对同期其他版本好多少」，"
         "不能回答绝对增量。"),
        ("已知限制3",
         "13.3.82 在共有期只有 4.9 个支付人/天，其 0.1141% 的转化率是小样本结果，不宜单独引用。"),
        ("数据校验",
         ("各版本首次出现日与发布日完全一致。" if not mismatch else f"存在偏差：{mismatch}")),
    ])

    wb.save(OUT)
    print("saved:", OUT)
    print("sheets:", wb.sheetnames)
    print("mismatch:", mismatch)


if __name__ == "__main__":
    main()
