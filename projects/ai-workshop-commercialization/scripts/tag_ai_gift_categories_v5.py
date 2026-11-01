# -*- coding: utf-8 -*-
"""AI 礼物类目补标引擎 v5

相对 v4 的变化（按 2026-09-20 用户最新要求）：
  1) 撤销 Q2 的「非主主播命中一律剔除」：命中第二/第三主播的礼物仍然保留为 主播IP
  2) 对这类行做「归属置换」：把礼物真正指向的那位主播置换到 主主播 列，原主主播退到被置换的那一列
     - 例：玥光魅影 原主=Dk-妙妙 第二=蔓玥玥，提示词「蔓玥玥穿着黑丝」-> 置换后 主=蔓玥玥 第二=Dk-妙妙
  3) 原值全部保留在 原主主播昵称 / 原第二主播昵称 / 原第三主播昵称，可随时还原
  4) 纳入用户在 100 行抽样文件里的人工标注（人工_一级类目 非空即以人工为准）

注意（必须在汇报里说明）：原表只有 主主播ID 一个 ID 列，没有第二/第三主播 ID。
置换只置换昵称，主主播ID 与 主主播金额集中度_pct 仍是原来那位（金额最高的主播）的口径。
"""
import csv
import io
import re
import sys
from collections import Counter, OrderedDict

sys.path.insert(0, r"C:/Users/tiany/Desktop/AI工坊专题/scripts")
sys.stdout.reconfigure(encoding="utf-8")

import pandas as pd

import tag_ai_gift_categories_v2 as base
import tag_ai_gift_categories_v3 as v3
import tag_ai_gift_categories_v4 as v4

SRC = r"C:/Users/tiany/Desktop/AI工坊专题/AI工坊被送出的礼物明细.csv"
MANUAL = r"C:/Users/tiany/Desktop/AI工坊专题/AI工坊兜底待复核_随机抽样100行_20260920.xlsx"
OUT_CSV = r"C:/Users/tiany/Desktop/AI工坊专题/AI工坊被送出的礼物明细_打标后_v5.csv"
OUT_XLSX = r"C:/Users/tiany/Desktop/AI工坊专题/AI工坊被送出的礼物明细_打标后_v5.xlsx"

norm = base.norm
squeeze = base.squeeze
to_num = base.to_num
SPLIT = r"[-_丶·|【\[\]（）()\s,/]"

GTOK_ALL = set()


def nick_terms(nick):
    """主播昵称里可用于匹配的词片段"""
    out = []
    n = norm(nick)
    if not n or n.lower() == "null":
        return out
    for part in re.split(SPLIT, n):
        part = re.sub(r"[A-Za-z0-9]+", "", part)
        if len(part) < 2 or part in base.STOP_TOKENS:
            continue
        out.append(part)
    return out


def pos_hits(nick, text, gtext):
    """返回 (是否有片段命中, 是否有单字命中, 命中词)  —— 片段用 提示词+礼物名，单字只看礼物名"""
    frag = None
    char = None
    for part in nick_terms(nick):
        subs = {part[i:i + 2] for i in range(len(part) - 1)}
        h = next((s for s in sorted(subs, key=len, reverse=True) if s in text), None)
        if h and not frag:
            frag = h
        if not char:
            c = next((ch for ch in part if ch not in v3.COMMON_CHARS and ch in gtext), None)
            if c:
                char = c
    return frag, char


def classify_one(gift, prompt, nick, gtok_all):
    """以指定主播为「本行主播」跑一遍分类"""
    n = norm(nick)
    gtok_row = {t for t in gtok_all if t and t.lower() in n.lower()}
    old = v3.STRONG_PREFIX
    v3.STRONG_PREFIX = [p for p in old if p.lower() in n.lower()]
    try:
        return v3.classify_v3(gift, prompt, [nick], gtok_row)
    finally:
        v3.STRONG_PREFIX = old


def main():
    with io.open(SRC, "r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        fieldnames = list(reader.fieldnames)
        rows = [r for r in reader]

    global GTOK_ALL
    GTOK_ALL = base.global_tokens(rows)
    v3.MEME_TOKENS = v3.build_meme_tokens(rows) - v4.GENERIC_MEME_BLOCK
    v3.COMMON_CHARS = v3.build_common_chars(rows)

    # 人工标注（100 行抽样）优先
    man = {}
    try:
        m = pd.read_excel(MANUAL, sheet_name="待标注100行").fillna("")
        for _, r in m.iterrows():
            if str(r["人工_一级类目"]).strip():
                man[str(r["礼物ID"]).strip()] = (
                    str(r["人工_一级类目"]).strip(), str(r["人工_二级类目"]).strip(),
                    str(r["备注"]).strip(),
                    str(r["主主播昵称"]).strip(), str(r["第二主播昵称"]).strip(),
                    str(r["第三主播昵称"]).strip())
        print("人工标注行数:", len(man))
    except Exception as e:
        print("人工标注读取失败（跳过）:", e)

    new_cols = ["一级类目_补标", "二级类目_补标", "风格标签", "打标方式", "打标依据",
                "打标置信度", "是否需复核", "复核原因", "人工标签修正", "主主播口径",
                "IP归属位次", "IP归属主播昵称", "原主主播昵称", "原第二主播昵称",
                "原第三主播昵称", "单房间专属词"]
    swap_cnt = 0
    restored = 0

    for r in rows:
        gift = norm(r.get("礼物名称"))
        prompt = norm(r.get("用户提示词"))
        main_nick = norm(r.get("主主播昵称"))
        nicks = [norm(r.get("主主播昵称")), norm(r.get("第二主播昵称")), norm(r.get("第三主播昵称"))]
        text = squeeze(gift + " " + prompt)
        gtext = squeeze(gift)

        r["原主主播昵称"] = nicks[0]
        r["原第二主播昵称"] = nicks[1]
        r["原第三主播昵称"] = nicks[2]
        r["单房间专属词"] = ""

        # 1) 人工标注优先
        gid = str(r.get("礼物ID")).strip()
        if gid in man:
            c1, c2, note, m_main, m_sec, m_third = man[gid]
            # 人工在抽样文件里改过主播昵称的（= 人工置换），以此为准
            manual_pos = 0
            if m_main and m_main != nicks[0]:
                if m_main == nicks[1]:
                    manual_pos = 1
                elif m_main == nicks[2]:
                    manual_pos = 2
            if manual_pos:
                cols = ["主主播昵称", "第二主播昵称", "第三主播昵称"]
                r[cols[0]], r[cols[manual_pos]] = nicks[manual_pos], nicks[0]
                swap_cnt += 1
            r["一级类目_补标"] = v4.CAT1_FIX.get(c1, c1)
            r["二级类目_补标"] = v4.CAT2_FIX.get(c2, c2)
            r["风格标签"] = next((s for s, kws in base.STYLE_RULES if any(k in text for k in kws)), "其他")
            r["打标方式"] = "人工标注（100行抽样）"
            r["打标依据"] = "人工标注" + ("｜" + note if note else "")
            r["打标置信度"] = "高"
            r["是否需复核"] = "否"
            r["复核原因"] = ""
            r["人工标签修正"] = ""
            if manual_pos:
                r["主主播口径"] = "人工置换（归属=%s）" % ["", "第二主播", "第三主播"][manual_pos]
                r["IP归属位次"] = ["", "第二主播", "第三主播"][manual_pos]
                r["IP归属主播昵称"] = nicks[manual_pos]
            else:
                r["主主播口径"] = "人工标注"
                r["IP归属位次"] = "人工标注" if r["一级类目_补标"] == "主播IP" else "不适用"
                r["IP归属主播昵称"] = nicks[0] if r["一级类目_补标"] == "主播IP" else ""
            continue

        # 2) 原表已有人工标签
        old1 = norm(r.get("一级类目"))
        if old1:
            fixrow = v3.GOLD_FIX.get(gift)
            c1 = old1
            c2 = v3.CAT2_NORMALIZE.get(norm(r.get("二级类目")), norm(r.get("二级类目")))
            fix_note = ""
            if fixrow:
                c1, c2 = fixrow
                fix_note = "用户确认修正：%s/%s -> %s/%s" % (old1, norm(r.get("二级类目")), c1, c2)
            r["一级类目_补标"] = v4.CAT1_FIX.get(c1, c1)
            r["二级类目_补标"] = v4.CAT2_FIX.get(c2, c2)
            r["风格标签"] = next((s for s, kws in base.STYLE_RULES if any(k in text for k in kws)), "其他")
            r["打标方式"] = "原表沿用（含用户修正）" if fixrow else "原表沿用"
            r["打标依据"] = fix_note or "原文件已有类目（二级「热梗」已并入「主播热梗」）"
            r["打标置信度"] = "高"
            r["是否需复核"] = "否"
            r["复核原因"] = ""
            if r["一级类目_补标"] == "主播IP" and r["二级类目_补标"] not in v4.IP_BRANCHES:
                r["复核原因"] = "原人工二级「%s」不属于主播IP四支，暂按主播肖像" % r["二级类目_补标"]
                r["二级类目_补标"] = "主播肖像"
                r["是否需复核"] = "是"
            r["人工标签修正"] = fix_note
            r["主主播口径"] = "原表人工标签"
            r["IP归属位次"] = "按主主播" if r["一级类目_补标"] == "主播IP" else "不适用"
            r["IP归属主播昵称"] = nicks[0] if r["一级类目_补标"] == "主播IP" else ""
            continue

        # 3) 规则打标：先按主主播判，判不出来再按第二/第三主播判（命中即保留为主播IP并置换）
        c1, c2, why, method, level, review, rw, style = classify_one(gift, prompt, nicks[0], GTOK_ALL)
        pos = 0
        if c1 != "主播IP":
            for i in (1, 2):
                if not nicks[i] or nicks[i].lower() == "null":
                    continue
                frag, char = pos_hits(nicks[i], text, gtext)
                if not frag and not char:
                    continue
                c1b, c2b, whyb, methodb, levelb, reviewb, rwb, styleb = classify_one(
                    gift, prompt, nicks[i], GTOK_ALL)
                if c1b == "主播IP":
                    c1, c2, why, method, level, review, rw, style = c1b, c2b, whyb, methodb, levelb, reviewb, rwb, styleb
                    pos = i
                    break
            if pos:
                restored += 1
                hit_word = "+".join(x for x in pos_hits(nicks[pos], text, gtext) if x)
                why = "礼物实际指向【%s】(%s)｜%s｜按用户要求保留为主播IP并置换主主播列" % (
                    nicks[pos], hit_word, why)
                method = method or "圈层规则"
        r["一级类目_补标"] = c1
        r["二级类目_补标"] = c2
        r["风格标签"] = style
        r["打标方式"] = method
        r["打标依据"] = why
        r["打标置信度"] = level
        r["是否需复核"] = review
        r["复核原因"] = rw
        r["人工标签修正"] = ""

        if c1 == "主播IP":
            owner = nicks[pos] if pos else nicks[0]
            r["IP归属位次"] = ["主主播", "第二主播", "第三主播"][pos]
            r["IP归属主播昵称"] = owner
            other_hit = pos_hits(nicks[0], text, gtext) if pos else (None, None)
            if pos:
                # 置换：归属主播移到主主播列，原主主播退到被置换的那一列
                cols = ["主主播昵称", "第二主播昵称", "第三主播昵称"]
                r[cols[0]], r[cols[pos]] = nicks[pos], nicks[0]
                swap_cnt += 1
                r["主主播口径"] = "已置换（归属=第%s主播）" % ("二" if pos == 1 else "三")
            elif other_hit[0] or other_hit[1]:
                r["主主播口径"] = "主主播命中+另有非主主播命中"
            else:
                r["主主播口径"] = "主主播命中"
        else:
            if any(pos_hits(nicks[i], text, gtext)[0] or pos_hits(nicks[i], text, gtext)[1] for i in (1, 2)
                   if nicks[i] and nicks[i].lower() != "null"):
                r["主主播口径"] = "剔除非主主播命中"
            else:
                r["主主播口径"] = "不涉及"
            r["IP归属位次"] = "不适用"
            r["IP归属主播昵称"] = ""

    out_cols = fieldnames + new_cols
    with io.open(OUT_CSV, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=out_cols, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow(r)
    print("已写 CSV:", OUT_CSV)

    tot_amt = sum(to_num(r.get(" 打赏金额 ")) for r in rows)
    ip = [r for r in rows if r["一级类目_补标"] == "主播IP"]
    ip_amt = sum(to_num(r.get(" 打赏金额 ")) for r in ip)
    print("")
    print("=== v5 打标结果（总 %d 行）===" % len(rows))
    print("打标方式:", dict(Counter(r["打标方式"] for r in rows)))
    print("主主播口径:", dict(Counter(r["主主播口径"] for r in rows)))
    print("IP归属位次:", dict(Counter(r["IP归属位次"] for r in ip)))
    print("置换行数 %d；由第二/第三主播收回为主播IP 的行数 %d" % (swap_cnt, restored))
    print("主播IP：供给 %d/%d = %.2f%%；金额 %.0f/%.0f = %.2f%%；倍数 %.2f" % (
        len(ip), len(rows), 100.0 * len(ip) / len(rows), ip_amt, tot_amt,
        100.0 * ip_amt / tot_amt, (ip_amt / tot_amt) / (len(ip) / len(rows))))
    print("主播IP 二级分布:", dict(Counter(r["二级类目_补标"] for r in ip)))
    print("一级类目分布:", dict(Counter(r["一级类目_补标"] for r in rows).most_common()))

    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Font

    wb = Workbook()
    ws = wb.active
    ws.title = "打标后明细"
    ws.append(out_cols)
    for r in rows:
        ws.append([r.get(c, "") for c in out_cols])
    for cell in ws[1]:
        cell.font = Font(name="Calibri", bold=True)
    ws.freeze_panes = "A2"

    ws2 = wb.create_sheet("类目分布统计")
    ws2.append(["一级类目_补标", "行数", "打赏订单数", "打赏金额", "金额占比"])
    agg = OrderedDict()
    for r in rows:
        k = r["一级类目_补标"]
        a = agg.setdefault(k, [0, 0.0, 0.0])
        a[0] += 1
        a[1] += to_num(r.get("打赏订单数"))
        a[2] += to_num(r.get(" 打赏金额 "))
    for k, a in sorted(agg.items(), key=lambda x: -x[1][2]):
        ws2.append([k, int(a[0]), int(a[1]), round(a[2], 2), "%.2f%%" % (100.0 * a[2] / tot_amt)])

    ws3 = wb.create_sheet("归属置换清单")
    ws3.append(["礼物名称", "标准价值", " 打赏金额 ", "原主主播昵称", "原第二主播昵称",
                "原第三主播昵称", "IP归属位次", "IP归属主播昵称", "置换后主主播",
                "一级类目", "二级类目", "用户提示词", "打标依据"])
    swaps = [r for r in rows if r["主主播口径"].startswith("已置换")]
    for r in sorted(swaps, key=lambda x: -to_num(x.get(" 打赏金额 "))):
        ws3.append([r.get("礼物名称"), r.get("标准价值"), r.get(" 打赏金额 "),
                    r["原主主播昵称"], r["原第二主播昵称"], r["原第三主播昵称"],
                    r["IP归属位次"], r["IP归属主播昵称"], r.get("主主播昵称"),
                    r["一级类目_补标"], r["二级类目_补标"], r.get("用户提示词"), r["打标依据"]])
    for cell in ws3[1]:
        cell.font = Font(name="Calibri", bold=True)
    ws3.freeze_panes = "A2"

    ws4 = wb.create_sheet("口径与规则")
    ws4.append(["项目", "内容"])
    for k, val in [
        ("版本", "v5（2026-09-20 按用户最新要求撤销 Q2 剔除、改为归属置换）"),
        ("输入", SRC),
        ("变化1", "命中第二/第三主播的礼物不再剔除，仍判 主播IP"),
        ("变化2", "这类行把真正指向的主播置换到 主主播 列，原主主播退到被置换的那一列；原值保留在 原主主播昵称/原第二主播昵称/原第三主播昵称"),
        ("变化3", "纳入用户在 100 行抽样文件里的人工标注（人工_一级类目 非空即以人工为准）"),
        ("重要限制", "原表只有 主主播ID 一个 ID 列。置换只置换昵称，主主播ID 与 主主播金额集中度_pct 仍是原来那位（金额最高的主播）的口径，做金额归属时要注意"),
        ("保留的口径", "Q1-C 单字只认主主播；Q3-B 圈层梗词剔除通用词；Q5-A 二级与一级同名保持；Q6-A 命名统一"),
    ]:
        ws4.append([k, val])
    ws4.column_dimensions["B"].width = 110
    for row in ws4.iter_rows():
        for c in row:
            c.alignment = Alignment(wrap_text=True, vertical="top")

    wb.save(OUT_XLSX)
    print("已写 XLSX:", OUT_XLSX)


if __name__ == "__main__":
    main()
