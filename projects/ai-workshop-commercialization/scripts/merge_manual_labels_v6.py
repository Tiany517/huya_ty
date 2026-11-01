# -*- coding: utf-8 -*-
"""把全量人工打标结果合并回 5,592 行 AI 礼物明细，输出 v6 交付物。

输入：
- AI工坊被送出的礼物明细_打标后_v5.csv（5,592 行，31 列）
- 人工打标\人工标注_{兜底,单字,圈层,词表}_batch*.tsv（人工重标 5,135 行）
- 人工打标\原表沿用_人工审核后_339行.xlsx（原表 339 行复核结果，含主播置换）

输出：
- AI工坊被送出的礼物明细_打标后_v6.xlsx（7 个 sheet）
- AI工坊被送出的礼物明细_打标后_v6.csv（UTF-8 BOM）
"""
import glob
import os

import numpy as np
import pandas as pd
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

ROOT = "C:/Users/tiany/Desktop/AI工坊专题"
BASE = os.path.join(ROOT, "人工打标")
V5 = os.path.join(ROOT, "AI工坊被送出的礼物明细_打标后_v5.csv")
ORIG = os.path.join(BASE, "原表沿用_人工审核后_339行.xlsx")

QUEUE_ORDER = [
    ("兜底", "人工标注_兜底_"),
    ("单字匹配", "人工标注_单字_"),
    ("圈层规则", "人工标注_圈层_"),
    ("词表规则", "人工标注_词表_"),
]

CN_FONT = "楷体"
EN_FONT = "Calibri"


def load_human_labels():
    rows = []
    for qname, prefix in QUEUE_ORDER:
        for f in sorted(glob.glob(os.path.join(BASE, prefix + "batch*.tsv"))):
            d = pd.read_csv(f, sep="\t", encoding="utf-8-sig", dtype=str)
            d = d.iloc[:, [0, 1, 2, 3, 4, 5]]
            d.columns = ["礼物ID", "礼物名称_重标", "一级类目_人工", "二级类目_人工", "归属位次_人工", "打标依据_人工"]
            d["来源筐"] = qname
            d["来源批次文件"] = os.path.basename(f)
            rows.append(d)
    h = pd.concat(rows, ignore_index=True)
    h["礼物ID"] = h["礼物ID"].astype(str).str.strip()
    return h


def load_orig_review():
    d = pd.read_excel(ORIG, dtype=str)
    return pd.DataFrame({
        "礼物ID": d["礼物ID"].astype(str).str.strip(),
        "一级类目_人工": d["一级类目"],
        "二级类目_人工": d["二级类目"],
        "归属位次_人工": d["IP归属位次"].fillna("-"),
        "打标依据_人工": d["审核依据"],
        "是否存疑_原表": d["是否存疑"],
        "来源筐": "原表复核",
        "来源批次文件": "原表沿用_人工审核后_339行.xlsx",
        "是否置换主播": d["是否置换主播"],
        "置换后主主播": d["主主播"],
        "置换后第二主播": d["第二主播"],
        "置换后第三主播": d["第三主播"],
    })


# 原表复核 339 行里，96 行「主播IP」被标为「未改动」，但没有填 IP归属位次。
# 归属位次不允许留空，这里做一次可复盘的机械补位，并写进判断依据（不覆盖原有审核依据）。
ORIG_FILL_POS = {"主播肖像": "主主播", "主播热梗": "主主播", "公会肖像": "主主播", "网友热梗": "待定"}


def fill_orig_missing_pos(d):
    ip = d["一级类目_人工"].astype(str).str.strip() == "主播IP"
    missing = d["归属位次_人工"].isna() | (d["归属位次_人工"].astype(str).str.strip().isin(["", "-", "nan"]))
    hit = d[ip & missing].copy()
    filled = 0
    for i in hit.index:
        sub = str(d.at[i, "二级类目_人工"]).strip()
        pos = ORIG_FILL_POS.get(sub)
        if not pos:
            continue
        d.at[i, "归属位次_人工"] = pos
        old = str(d.at[i, "打标依据_人工"] or "").strip()
        d.at[i, "打标依据_人工"] = (
            old + "｜【root补充】原表复核此行标为未改动、未填归属位次，"
                  "按冻结口径「主播IP行归属位次不得为空」补位为" + pos
                  + ("（网友热梗为平台神壕/网络梗，不归属本行主播，故记待定）" if sub == "网友热梗" else "")
        )
        filled += 1
    return d, filled


def to_amount(s):
    return pd.to_numeric(s.astype(str).str.replace(",", "").str.strip(), errors="coerce").fillna(0.0)


def main():
    v5 = pd.read_csv(V5, encoding="utf-8-sig", dtype=str)
    v5["礼物ID"] = v5["礼物ID"].astype(str).str.strip()
    dup = int(v5["礼物ID"].duplicated().sum())
    v5 = v5.drop_duplicates("礼物ID", keep="first").reset_index(drop=True)
    v5["金额_num"] = to_amount(v5[" 打赏金额 "])
    v5["标准价值_num"] = to_amount(v5["标准价值"])

    human = pd.concat([load_human_labels(), load_orig_review()], ignore_index=True)

    # 只对「原表复核」筐做缺失位次机械补位，人工重标筐已在批次文件里补齐
    orig_mask = human["来源筐"] == "原表复核"
    fixed_orig = human[orig_mask].copy()
    fixed_orig, n_pos_filled = fill_orig_missing_pos(fixed_orig)
    human = pd.concat([human[~orig_mask], fixed_orig], ignore_index=True)

    dup_h = int(human["礼物ID"].duplicated().sum())
    human = human.drop_duplicates("礼物ID", keep="last").reset_index(drop=True)

    m = v5.merge(human, on="礼物ID", how="left")
    m["是否重标"] = np.where(m["一级类目_人工"].notna(), "是", "否")
    m["最终一级类目"] = m["一级类目_人工"].fillna(m["一级类目_补标"])
    m["最终二级类目"] = m["二级类目_人工"].fillna(m["二级类目_补标"])
    m["最终归属位次"] = np.where(m["是否重标"] == "是", m["归属位次_人工"], m["IP归属位次"])
    m["最终归属位次"] = m["最终归属位次"].replace({"不适用": "-"}).fillna("-")

    # 归属位次合法性收敛：非主播IP 一律 `-`；主播IP 只允许冻结取值，越界值（多为 v5 脏值）落 `待定`
    LEGAL_POS = {"主主播", "第二主播", "第三主播", "非本行主播", "圈层", "待定", "-"}
    is_ip = m["最终一级类目"].astype(str).str.strip() == "主播IP"
    pos_now = m["最终归属位次"].astype(str).str.strip()
    m["最终归属位次"] = np.where(
        ~is_ip, "-",
        np.where(pos_now.isin(LEGAL_POS - {"-"}), pos_now, "待定"))
    m["最终是否存疑"] = np.where(
        m["打标依据_人工"].astype(str).str.contains("存疑", na=False), "是",
        np.where(m["是否存疑_原表"].astype(str).str.strip() == "是", "是", "否"))
    m["来源筐"] = m["来源筐"].fillna("未重标（沿用v5）")

    swap = m["是否置换主播"].astype(str).str.strip() == "是"
    for src_col, dst_col in (("置换后主主播", "主主播昵称"), ("置换后第二主播", "第二主播昵称"), ("置换后第三主播", "第三主播昵称")):
        m.loc[swap, dst_col] = m.loc[swap, src_col].fillna(m.loc[swap, dst_col])

    m["IP二分"] = np.where(m["最终一级类目"].astype(str).str.strip() == "主播IP", "主播IP", "非主播IP")

    full = m[m["是否重标"] == "是"].copy()
    total_rows = len(full)
    total_amt = float(full["金额_num"].sum())
    ip_rows = int((full["IP二分"] == "主播IP").sum())
    ip_amt = float(full.loc[full["IP二分"] == "主播IP", "金额_num"].sum())
    non_rows = total_rows - ip_rows
    non_amt = total_amt - ip_amt

    head = pd.DataFrame([
        {"指标": "纳入统计行数", "数值": total_rows, "说明": "已人工重标且可归属的行（不含未重标/空名脏数据行）"},
        {"指标": "重标行合计金额（元）", "数值": round(total_amt, 2), "说明": "v5 打赏金额列求和，时间窗 2026-07-13~2026-09-14"},
        {"指标": "主播IP 供给行数", "数值": ip_rows, "说明": "一级类目 = 主播IP"},
        {"指标": "主播IP 供给占比", "数值": round(ip_rows / total_rows, 4), "说明": "主播IP行数 / 重标行数"},
        {"指标": "主播IP 金额（元）", "数值": round(ip_amt, 2), "说明": "一级类目 = 主播IP 的金额合计"},
        {"指标": "主播IP 金额占比", "数值": round(ip_amt / total_amt, 4), "说明": "主播IP金额 / 重标金额合计"},
        {"指标": "非主播IP 供给行数", "数值": non_rows, "说明": "一级类目 ≠ 主播IP"},
        {"指标": "非主播IP 金额（元）", "数值": round(non_amt, 2), "说明": "非主播IP金额合计"},
        {"指标": "存疑行数", "数值": 0, "说明": "见「存疑清单」sheet，存疑行未硬判成主播IP"},
        {"指标": "变更行数", "数值": 0, "说明": "v5自动判定被人工改类的行，见「变更明细」sheet"},
    ])

    dist = (full.groupby("最终一级类目")
            .agg(供给行数=("礼物ID", "size"), 金额=("金额_num", "sum"))
            .reset_index().sort_values("金额", ascending=False))
    dist["供给占比"] = (dist["供给行数"] / total_rows).round(4)
    dist["金额占比"] = (dist["金额"] / total_amt).round(4)
    dist["件均金额"] = (dist["金额"] / dist["供给行数"]).round(2)

    ip_sub = (full[full["IP二分"] == "主播IP"].groupby("最终二级类目")
              .agg(供给行数=("礼物ID", "size"), 金额=("金额_num", "sum"))
              .reset_index().sort_values("金额", ascending=False))
    pos = (full[full["IP二分"] == "主播IP"].groupby("最终归属位次")
           .agg(供给行数=("礼物ID", "size"), 金额=("金额_num", "sum"))
           .reset_index().sort_values("金额", ascending=False))

    doubt = m[m["最终是否存疑"] == "是"][["礼物ID", "礼物名称", "主主播昵称", "来源筐",
                                          "最终一级类目", "最终二级类目", "最终归属位次",
                                          "打标依据_人工", "金额_num", "标准价值_num"]]
    doubt = doubt.rename(columns={"金额_num": "打赏金额", "标准价值_num": "标准价值"})

    changed = m[(m["是否重标"] == "是") & ((m["一级类目_人工"] != m["一级类目_补标"]) | (m["二级类目_人工"] != m["二级类目_补标"]))][
        ["礼物ID", "礼物名称", "来源筐", "一级类目_补标", "一级类目_人工", "二级类目_补标", "二级类目_人工",
         "IP归属位次", "归属位次_人工", "打标依据_人工", "金额_num"]]
    changed = changed.rename(columns={"一级类目_补标": "v5一级类目", "一级类目_人工": "v6人工一级类目",
                                      "二级类目_补标": "v5二级类目", "二级类目_人工": "v6人工二级类目",
                                      "IP归属位次": "v5归属位次", "归属位次_人工": "v6归属位次", "金额_num": "打赏金额"})

    unlabeled = m[m["是否重标"] == "否"][["礼物ID", "礼物名称", "主主播昵称", "打标方式", "一级类目_补标", "二级类目_补标", "金额_num"]]
    unlabeled = unlabeled.rename(columns={"一级类目_补标": "v5一级类目", "二级类目_补标": "v5二级类目", "金额_num": "打赏金额"})

    head.loc[head["指标"] == "存疑行数", "数值"] = len(doubt)
    head.loc[head["指标"] == "变更行数", "数值"] = len(changed)

    note = pd.DataFrame([
        {"项": "时间窗", "说明": "2026-07-13 ~ 2026-09-14"},
        {"项": "样本", "说明": "v5 明细 5,592 行（去重后 %d 个礼物ID，v5 存在 %d 个重复ID，本次保留首行）" % (len(v5), dup)},
        {"项": "人工重标覆盖", "说明": "5,474 行（兜底979 + 单字匹配411 + 圈层规则943 + 词表规则2802 + 原表复核339）"},
        {"项": "未重标行", "说明": "118 行（含 42 行礼物名称为空、实为提示词残行的脏数据），保留 v5 判定，见「未重标行」sheet"},
        {"项": "统计口径", "说明": "供给占比/金额占比只在「已重标行」上计算，避免脏数据干扰"},
        {"项": "金额口径", "说明": "v5「打赏金额」列（该礼物在时间窗内打赏金额，单位元），求和不去重"},
        {"项": "供给口径", "说明": "一行 = 一个被送出的 AI 礼物道具（礼物ID 粒度）"},
        {"项": "一级/二级词表", "说明": "见 人工打标/打标口径_v6_冻结版.md 第二节；归属位次只取 主主播/第二主播/第三主播/非本行主播/圈层/待定/-"},
        {"项": "主播IP 四类", "说明": "主播肖像=主播本人形象或署名；主播热梗=房间自造说法/口头禅/房间号；公会肖像=公会或圈层门派标识；网友热梗=跨房间平台梗与神壕名"},
        {"项": "两条硬约束", "说明": "①发光「八」字不算主播IP ②门派标识（八门/黄门）写圈层，只有门派首领本人或署名才写主主播"},
        {"项": "庆生优先", "说明": "画面主题为生日/庆生/寿星/周年祝福时，即使使用房间专属形象也按 庆生与祝福 归类"},
        {"项": "房间母题", "说明": "房间专属动物/人名形象（大橘八爷、红鼠、小白熊、小毛驴、大猩猩、猩猩公主、来福/金柱/康康、蛋肯、八洋宝贝、梅花鹿/折耳根/扫雪、李逵、茶冻）统一判 主播IP"},
        {"项": "存疑处理", "说明": "拿不准的行在判断依据里写明存疑点，未硬判成主播IP；全部存疑行见「存疑清单」sheet"},
        {"项": "主播置换", "说明": "原表复核中「是否置换主播=是」的行，主/第二/第三主播昵称已按复核结果置换，原昵称仍保留在原*昵称列"},
        {"项": "归属位次补位", "说明": "原表复核 339 行中有 %d 行标为「未改动」但未填归属位次，按冻结口径「主播IP行归属位次不得为空」机械补位：主播肖像/主播热梗/公会肖像→主主播，网友热梗→待定；补位说明已写入判断依据" % n_pos_filled},
        {"项": "打标方式", "说明": "本次全部为人工逐行打标（禁止关键词规则自动判定），批次文件保留在 人工打标/ 目录"},
    ])

    detail_cols = [c for c in m.columns if c not in ("金额_num", "标准价值_num", "礼物名称_重标")]
    detail = m[detail_cols + ["金额_num", "标准价值_num"]].rename(
        columns={"金额_num": "打赏金额_num", "标准价值_num": "标准价值_num"})

    out_xlsx = os.path.join(ROOT, "AI工坊被送出的礼物明细_打标后_v6.xlsx")
    out_csv = os.path.join(ROOT, "AI工坊被送出的礼物明细_打标后_v6.csv")

    with pd.ExcelWriter(out_xlsx, engine="openpyxl") as xw:
        start = 0
        head.to_excel(xw, sheet_name="结论_供给与金额", index=False, startrow=start)
        start += len(head) + 2
        dist.to_excel(xw, sheet_name="结论_供给与金额", index=False, startrow=start)
        start += len(dist) + 2
        ip_sub.to_excel(xw, sheet_name="结论_供给与金额", index=False, startrow=start)
        start += len(ip_sub) + 2
        pos.to_excel(xw, sheet_name="结论_供给与金额", index=False, startrow=start)
        detail.to_excel(xw, sheet_name="明细", index=False)
        note.to_excel(xw, sheet_name="口径说明", index=False)
        doubt.to_excel(xw, sheet_name="存疑清单", index=False)
        changed.to_excel(xw, sheet_name="变更明细", index=False)
        unlabeled.to_excel(xw, sheet_name="未重标行", index=False)

        wb = xw.book
        for ws in wb.worksheets:
            n_cols = ws.max_column
            for c in range(1, n_cols + 1):
                ws.column_dimensions[get_column_letter(c)].width = 18
            for row in ws.iter_rows(min_row=1, max_row=min(ws.max_row, 6000)):
                for cell in row:
                    cell.font = Font(name=CN_FONT, size=10)
                    cell.alignment = Alignment(vertical="center", wrap_text=False)
            for c in range(1, n_cols + 1):
                ws.cell(row=1, column=c).font = Font(name=CN_FONT, size=10, bold=True)
                ws.cell(row=1, column=c).fill = PatternFill("solid", fgColor="DDEBF7")

    detail.to_csv(out_csv, index=False, encoding="utf-8-sig")

    print("v5 行数", len(v5), "| v5 重复ID", dup)
    print("人工标签行数", len(human), "| 标签内部重复ID", dup_h)
    print("重标行", int((m["是否重标"] == "是").sum()), "| 未重标行", int((m["是否重标"] == "否").sum()))
    print("原表复核归属位次补位行数", n_pos_filled)
    print("主播IP 供给占比 %.2f%% | 金额占比 %.2f%%" % (ip_rows / total_rows * 100, ip_amt / total_amt * 100))
    print("存疑行", len(doubt), "| 变更行", len(changed))
    print("输出:", out_xlsx)
    print("输出:", out_csv)


if __name__ == "__main__":
    main()
