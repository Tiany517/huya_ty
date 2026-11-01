# -*- coding: utf-8 -*-
"""
赛后7日 ACU 保持率（按单个赛事、按时间顺序）

算法：
    对每个赛事 e：
        D0 = 该赛事最后一次出现的开播日（赛事结束日）
        分子 = Mean(valid_acu | dt ∈ (D0, D0+7]，且当日有开播记录，且该日不直播任何赛事)
        分母A = Mean(valid_acu | 该赛事最后 7 个开播日)      # 主口径，贴近「结束后回落」
        分母B = Mean(valid_acu | 该赛事全部开播日)          # 附口径
        赛后7日ACU保持率 = 分子 / 分母

    时长校正版：把 valid_acu 换成「等效平均在线 = view_mins / live_mins」再算一遍。

    可比性判定：赛后7日内若混入其他赛事日（is_big_match=1），则该赛事的「赛后保持率」
    不具解释力，标注为「赛事重叠，不可比」。

依赖：与 analyze_yuezi_acu.py 相同的原始文件与去重规则。
"""

import os
import numpy as np
import pandas as pd
from openpyxl import load_workbook
from openpyxl.styles import Font, Alignment, PatternFill, Border, Side

RAW = r"C:\Users\tiany\Downloads\虎视月子（无畏契约）观时数据_V2.csv"
OUTDIR = r"C:\Users\tiany\Desktop\无畏契约主播潜力分析\月子二路节目化效果_20261016"
XLSX = os.path.join(OUTDIR, "月子_赛后7日ACU保持率_20261016.xlsx")
N_POST = 7


def load():
    raw = pd.read_csv(RAW, encoding="utf-8-sig", dtype={"match_name": "object"})
    raw["dt"] = pd.to_datetime(raw["dt"], format="%Y/%m/%d")
    daily = raw.groupby("dt", as_index=False).agg(
        is_big_match=("is_big_match", "max"),
        total_dau=("total_dau", "first"), valid_dau=("valid_dau", "first"),
        valid_acu=("valid_acu", "first"), view_mins=("view_mins", "first"),
        avg_view_mins=("avg_view_mins", "first"), live_mins=("live_mins", "first"))
    daily["等效平均在线"] = daily["view_mins"] / daily["live_mins"]

    # 日 × 赛事 长表（同日多场赛事会展开成多行，指标相同）
    m = raw[["dt", "match_name", "is_big_match"]].copy()
    m = m[m["match_name"].notna()].drop_duplicates()
    m = m.merge(daily, on="dt", how="left", suffixes=("", "_d"))
    return raw, daily, m


def main():
    os.makedirs(OUTDIR, exist_ok=True)
    raw, daily, m = load()
    data_end = daily["dt"].max()
    event_days = set(daily.loc[daily["is_big_match"] == 1, "dt"])

    rows, evid = [], []
    orders = m.groupby("match_name")["dt"].agg(["min", "max"]).sort_values(["min", "max"])
    for i, (name, r) in enumerate(orders.iterrows(), start=1):
        d0 = r["max"]
        ev = m[m["match_name"] == name].sort_values("dt")
        win = daily[(daily["dt"] > d0) & (daily["dt"] <= d0 + pd.Timedelta(days=N_POST))]
        post_event_days = [d for d in win["dt"] if d in event_days]
        win_clean = win[~win["dt"].isin(post_event_days)]
        last7 = ev.sort_values("dt").tail(7)
        last7_acu = last7["valid_acu"].mean()
        whole_acu = ev["valid_acu"].mean()
        post_acu = win_clean["valid_acu"].mean() if len(win_clean) else np.nan

        # 时长校正版
        post_eff = win_clean["view_mins"].sum() / win_clean["live_mins"].sum() if len(win_clean) else np.nan
        eff_last7 = last7["view_mins"].sum() / last7["live_mins"].sum()

        truncated = (d0 + pd.Timedelta(days=N_POST)) > data_end
        notes = []
        if post_event_days:
            notes.append(f"赛事重叠：赛后7日内有{len(post_event_days)}天仍在其他赛事期({post_event_days[0]:%m-%d}~{post_event_days[-1]:%m-%d})")
        if truncated:
            notes.append(f"数据截断：赛后7日窗口至{d0 + pd.Timedelta(days=N_POST):%Y-%m-%d}，但数据只到{data_end:%Y-%m-%d}")
        if len(win_clean) == 0:
            notes.append("赛后7日内无开播记录")
        elif len(win_clean) < 3:
            notes.append(f"赛后7日内仅{len(win_clean)}天开播，样本很薄")
        if not notes:
            notes.append("赛后7日为纯非赛事期，可比")

        span = (d0 - r["min"]).days + 1
        no_live = span - len(ev)
        if no_live > 0:
            notes.append(
                f"口径提示：该赛事标签跨度{span}个自然日，其中{no_live}天文件内无开播记录（不排除赛程更长）")

        comparable = (not post_event_days) and len(win_clean) > 0
        rows.append({
            "序号": i, "赛事名称": name,
            "赛事首次开播": f"{r['min']:%Y-%m-%d}", "赛事最后开播D0": f"{d0:%Y-%m-%d}",
            "赛事标签开播天数(主播口径)": len(ev),
            "赛事标签自然日跨度_天": span,
            "跨度内无开播记录日数": no_live,
            "分母_赛事期ACU均值": round(whole_acu, 1),
            "赛后7日窗口": f"{d0 + pd.Timedelta(days=1):%Y-%m-%d} ~ {d0 + pd.Timedelta(days=N_POST):%Y-%m-%d}",
            "分子_赛后7日非赛事开播天数": len(win_clean),
            "分子_赛后7日ACU均值": round(post_acu, 1) if len(win_clean) else "无数据",
            "赛后7日ACU保持率(主口径=分子/赛事期ACU)": f"{post_acu / whole_acu:.1%}" if len(win_clean) else "不可计算",
            "参考_分母改用末7开播日的保持率": f"{post_acu / last7_acu:.1%}" if len(win_clean) else "不可计算",
            "赛事末段ACU均值_末7开播日": round(last7_acu, 1),
            "参考_赛事末段等效在线": round(eff_last7, 1),
            "时长校正_赛后7日等效在线": round(post_eff, 1) if len(win_clean) else "无数据",
            "时长校正_保持率(分母用赛事期等效在线)": f"{post_eff / (ev['view_mins'].sum() / ev['live_mins'].sum()):.1%}" if len(win_clean) else "不可计算",
            "赛事期日均直播_分钟": round(ev["live_mins"].mean(), 1),
            "赛后7日日均直播_分钟": round(win_clean["live_mins"].mean(), 1) if len(win_clean) else "无数据",
            "是否可比": "可比" if comparable else "不可比（赛事重叠或无数据）",
            "备注": "；".join(notes),
        })
        for _, x in last7.iterrows():
            evid.append({"赛事名称": name, "用途": "分母A_赛事末段", "日期": f"{x['dt']:%Y-%m-%d}",
                         "有效ACU": round(x["valid_acu"], 1), "直播时长_分钟": int(x["live_mins"])})
        for _, x in win_clean.iterrows():
            evid.append({"赛事名称": name, "用途": "分子_赛后7日", "日期": f"{x['dt']:%Y-%m-%d}",
                         "有效ACU": round(x["valid_acu"], 1), "直播时长_分钟": int(x["live_mins"])})

    out = pd.DataFrame(rows)
    evid_df = pd.DataFrame(evid)

    algo = pd.DataFrame([
        ("指标定义（主口径，已按业务方确认）", "赛后N日ACU保持率 = 赛事结束日后N日内的非赛事开播日有效ACU均值 ÷ 赛事期有效ACU均值"),
        ("N", f"{N_POST}（自然日，含 D0+1 ~ D0+{N_POST}）"),
        ("事件结束日D0", "该赛事 match_name 最后一次出现的开播日"),
        ("分子", "dt ∈ (D0, D0+7] 且当日有开播记录、且当日 is_big_match=0 的 valid_acu 算术均值"),
        ("分母（主口径）", "该赛事全部开播日的 valid_acu 算术均值，即「赛事的ACU均值」"),
        ("分母A（参考口径，非主口径）", "该赛事最后 7 个开播日的 valid_acu 算术均值（按开播日滚动，跳过断播日），仅作敏感性参考"),
        ("「开播日」定义", "文件中存在该主播当日记录的自然日；断播日文件内没有行、没有 ACU 值，无法参与均值，因此分母A要向前滚动取满7个开播日"),
        ("分母A会退化的情况", "当该赛事开播天数 < 7 时，分母A 等于该赛事全部开播日的均值（与分母B相同），此时该赛事的保持率不具统计意义，需结合天数读"),
        ("分母B（附口径）", "该赛事全部开播日的 valid_acu 算术均值"),
        ("为何要A分母", "赛事>7天时，用整体均值做分母会把赛事前期低水位也算进去，掩盖结束前的真实水位"),
        ("断播日处理", "无开播记录的日期不参与均值计算，但计入7日窗口的天数；同时报告窗口内实际开播天数"),
        ("赛事重叠处理", "若赛后7日内仍有 is_big_match=1 的日子，该窗口不是「赛后非赛事期」，保持率标注为不可比，不参与横向比较"),
        ("数据截断处理", "若 D0+7 超过数据最后一天(2026-10-11)，标注截断，保持率仅代表已覆盖天数"),
        ("直播时长校正", "把 valid_acu 换成「等效平均在线 = Σview_mins / Σlive_mins」，分子分母同样起止，再算一次保持率"),
        ("数据来源", RAW),
        ("去重规则", "同一 dt 多行(同日多场赛事)指标一致，按 dt 保留1行；赛事归属按 match_name 展开"),
    ], columns=["条目", "说明"])

    with pd.ExcelWriter(XLSX, engine="openpyxl") as w:
        out.to_excel(w, sheet_name="01_赛后7日ACU保持率", index=False)
        algo.to_excel(w, sheet_name="02_算法与口径", index=False)
        evid_df.to_excel(w, sheet_name="03_分子分母明细依据", index=False)
    wb = load_workbook(XLSX)
    fill = PatternFill("solid", fgColor="DCE6F1")
    thin = Side(style="thin", color="BFBFBF")
    bd = Border(left=thin, right=thin, top=thin, bottom=thin)
    for ws in wb.worksheets:
        for c in ws[1]:
            c.font = Font(name="楷体", size=11, bold=True); c.fill = fill
            c.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True); c.border = bd
        for row in ws.iter_rows(min_row=2):
            for c in row:
                num = isinstance(c.value, (int, float)) and not isinstance(c.value, bool)
                c.font = Font(name="Calibri" if num else "楷体", size=10); c.border = bd
                if num:
                    c.number_format = "#,##0.0" if isinstance(c.value, float) else "#,##0"
                else:
                    c.alignment = Alignment(vertical="center", wrap_text=True)
        for i, col in enumerate(ws.iter_cols(min_row=1, max_row=1), start=1):
            vals = [len(str(ws.cell(row=r, column=i).value or "")) for r in range(1, min(ws.max_row, 80) + 1)]
            ws.column_dimensions[col[0].column_letter].width = min(max(max(vals) * 1.3 + 4, 10), 46)
        ws.freeze_panes = "A2"
    wb.save(XLSX)

    pd.set_option("display.width", 260); pd.set_option("display.max_columns", 40)
    print(out.drop(columns=["备注"]).to_string(index=False))
    print("\n【备注】")
    for _, x in out.iterrows():
        print(f"  {x['序号']}. {x['赛事名称']}：{x['备注']}")
    print(f"\n输出：{XLSX}")


if __name__ == "__main__":
    main()
