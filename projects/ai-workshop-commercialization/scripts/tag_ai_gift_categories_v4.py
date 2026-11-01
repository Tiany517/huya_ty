# -*- coding: utf-8 -*-
"""AI 礼物类目补标引擎 v4（按 2026-09-20 用户在选择题里的选择收敛）

用户选择：
  Q1-C  单字匹配只保留「命中主主播」的行
  Q2    只要不是本行主主播的 IP，一律剔除（第二/第三主播命中同样剔除）
  Q3-B  圈层梗词里命中通用词的行全部剔除
  Q5-A  二级类目与一级同名保持原样
  Q6-A  命名统一：一级「男性人物」->「男性角色」；二级「庆生」->「庆生与祝福」

实现要点：
  1) 圈层标记 / 团号代号 / 强前缀 / 昵称片段 / 单字 这些「昵称类」规则，全部只用主主播昵称
  2) 新增「主主播口径」列，标明该行是否因非主主播命中而被剔除（可 filter、可复盘）
  3) 神豪/身份梗（陌白、时倾等平台级）不受 Q2 影响，仍按用户已确认的网友热梗处理

输出（不覆盖 v3 产物，也不动原文件）：
  AI工坊被送出的礼物明细_打标后_v4.csv
  AI工坊被送出的礼物明细_打标后_v4.xlsx
"""
import csv
import io
import re
import sys
from collections import Counter, OrderedDict

sys.path.insert(0, r"C:/Users/tiany/Desktop/AI工坊专题/scripts")
sys.stdout.reconfigure(encoding="utf-8")

import tag_ai_gift_categories_v2 as base
import tag_ai_gift_categories_v3 as v3

SRC = r"C:/Users/tiany/Desktop/AI工坊专题/AI工坊被送出的礼物明细.csv"
OUT_CSV = r"C:/Users/tiany/Desktop/AI工坊专题/AI工坊被送出的礼物明细_打标后_v4.csv"
OUT_XLSX = r"C:/Users/tiany/Desktop/AI工坊专题/AI工坊被送出的礼物明细_打标后_v4.xlsx"

norm = base.norm
squeeze = base.squeeze
to_num = base.to_num
row_tokens = base.row_tokens

# Q3-B：圈层梗词里被判定为通用词的黑名单（出现频次低所以没被频次过滤挡掉）
GENERIC_MEME_BLOCK = {
    "天天开心", "憨憨", "锦鲤", "福星", "节奏", "风景", "摩羯座", "好棒",
    "幸运星", "爆爆爆", "无忧无虑", "旺旺旺", "喜乐", "努力鸭", "巅峰第一",
    "暴富", "超甜", "黑马",
}

# Q6-A：命名统一
CAT1_FIX = {"男性人物": "男性角色"}
CAT2_FIX = {"庆生": "庆生与祝福", "男性人物": "男性角色"}

# 主播IP 的二级只能是这四支（用户 2026-09-20 前的确认口径）
IP_BRANCHES = {"主播肖像", "主播热梗", "网友热梗", "公会肖像"}

GTOK_ALL = set()


def build_room_exclusive(rows, max_rows=10, min_rows=2):
    """单房间专属词：某个 2-4 字词在 min_rows~max_rows 个礼物里重复出现，且全部集中在同一个主播房间。

    用途：识别「房间梗」。要求重复出现是为了区别于一次性随口起名（一次性无法被数据复现）。
    返回 (gram_rows, gram_anchor)，供 is_room_exclusive 判断。
    """
    from collections import Counter as _C
    from collections import defaultdict as _D
    gram = _D(_C)
    nrows = _C()
    for r in rows:
        names = re.sub(r"[^\u4e00-\u9fa5]", "", str(r.get("礼物名称") or ""))
        anchor = norm(r.get("主主播昵称"))
        if not names or not anchor:
            continue
        seen = set()
        for L in (2, 3, 4):
            for i in range(len(names) - L + 1):
                seen.add(names[i:i + L])
        for t in seen:
            gram[t][anchor] += 1
            nrows[t] += 1
    keep = {}
    for t, c in gram.items():
        if min_rows <= nrows[t] <= max_rows and len(c) == 1:
            keep[t] = list(c)[0]
    return keep, nrows


ROOM_EXCL = {}
ROOM_EXCL_NROWS = {}


def room_exclusive_tokens(gift, anchor):
    names = re.sub(r"[^\u4e00-\u9fa5]", "", str(gift or ""))
    hits = []
    cand = set()
    for L in (2, 3, 4):
        for i in range(len(names) - L + 1):
            cand.add(names[i:i + L])
    for t in sorted(cand, key=len, reverse=True):
        if ROOM_EXCL.get(t) == norm(anchor):
            hits.append(t)
    return hits


def nick_hits(nick, gtext):
    """复刻「昵称片段 + 单字」两段逻辑，仅用于给非主主播命中留痕。"""
    hits = []
    n = norm(nick)
    if not n or n.lower() == "null":
        return hits
    for part in re.split(r"[-_丶·|【\[\]（）()\s,/]", n):
        part = re.sub(r"[A-Za-z0-9]+", "", part)
        if len(part) < 2 or part in base.STOP_TOKENS:
            continue
        subs = {part[i:i + 2] for i in range(len(part) - 1)}
        h = next((s for s in sorted(subs, key=len, reverse=True) if s in gtext), None)
        if h:
            hits.append(h)
            continue
        ch = next((c for c in part if c not in v3.COMMON_CHARS and c in gtext), None)
        if ch:
            hits.append(ch)
    return hits


def classify_v4(gift, prompt, main_nick, other_nicks, gtok_all):
    """Q1-C + Q2：昵称类规则一律只认主主播。"""
    mainn = norm(main_nick)
    gtok_row = {t for t in gtok_all if t and t.lower() in mainn.lower()}
    old_prefix = v3.STRONG_PREFIX
    v3.STRONG_PREFIX = [p for p in old_prefix if p.lower() in mainn.lower()]
    try:
        out = v3.classify_v3(gift, prompt, [main_nick], gtok_row)
    finally:
        v3.STRONG_PREFIX = old_prefix
    c1, c2, why, method, level, review, rw, style = out
    gtext = squeeze(norm(gift))
    other_hit = []
    for nk in other_nicks:
        other_hit.extend(nick_hits(nk, gtext))
    if c1 == "主播IP":
        scope = "主主播命中+另有非主主播命中" if other_hit else "主主播命中"
    else:
        scope = "剔除非主主播命中" if other_hit else "不涉及"
    if other_hit:
        why = "%s｜非主主播命中[%s]" % (why, "/".join(sorted(set(other_hit))[:3]))
    return CAT1_FIX.get(c1, c1), CAT2_FIX.get(c2, c2), why, method, level, review, rw, style, scope


def main():
    with io.open(SRC, "r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        fieldnames = list(reader.fieldnames)
        rows = [r for r in reader]

    global GTOK_ALL
    GTOK_ALL = base.global_tokens(rows)
    global ROOM_EXCL, ROOM_EXCL_NROWS
    ROOM_EXCL, ROOM_EXCL_NROWS = build_room_exclusive(rows)
    v3.MEME_TOKENS = v3.build_meme_tokens(rows) - GENERIC_MEME_BLOCK
    v3.COMMON_CHARS = v3.build_common_chars(rows)
    print("单房间专属词（>=2 个礼物重复出现且只在一个直播间）: %d 个" % len(ROOM_EXCL))
    print("全站圈层梗词数（已剔除通用词 %d 个）: %d" % (len(GENERIC_MEME_BLOCK), len(v3.MEME_TOKENS)))
    print("全局团号池: %d；全局高频字过滤: %d" % (len(GTOK_ALL), len(v3.COMMON_CHARS)))

    new_cols = ["一级类目_补标", "二级类目_补标", "风格标签", "打标方式", "打标依据",
                "打标置信度", "是否需复核", "复核原因", "人工标签修正", "主主播口径",
                "单房间专属词"]

    for r in rows:
        gift = norm(r.get("礼物名称"))
        prompt = norm(r.get("用户提示词"))
        main_nick = r.get("主主播昵称")
        other_nicks = [r.get("第二主播昵称"), r.get("第三主播昵称")]
        old1 = norm(r.get("一级类目"))
        if old1:
            name = gift
            fix = v3.GOLD_FIX.get(name)
            c1 = old1
            c2 = v3.CAT2_NORMALIZE.get(norm(r.get("二级类目")), norm(r.get("二级类目")))
            fix_note = ""
            if fix:
                c1, c2 = fix
                fix_note = "用户确认修正：%s/%s -> %s/%s" % (
                    old1, norm(r.get("二级类目")), c1, c2)
            r["一级类目_补标"] = CAT1_FIX.get(c1, c1)
            r["二级类目_补标"] = CAT2_FIX.get(c2, c2)
            text = squeeze(gift + " " + prompt)
            r["风格标签"] = next((s for s, kws in base.STYLE_RULES if any(k in text for k in kws)), "其他")
            r["打标方式"] = "原表沿用（含用户修正）" if fix else "原表沿用"
            r["打标依据"] = fix_note or "原文件已有类目（二级「热梗」已并入「主播热梗」）"
            r["打标置信度"] = "高"
            r["是否需复核"] = "否"
            r["复核原因"] = ""
            # 原人工标签里 主播IP 却用了非四支的二级（如「庆生」），暂按主播肖像并标记复核
            if r["一级类目_补标"] == "主播IP" and r["二级类目_补标"] not in IP_BRANCHES:
                r["复核原因"] = "原人工二级「%s」不属于主播IP四支，暂按主播肖像" % r["二级类目_补标"]
                r["二级类目_补标"] = "主播肖像"
                r["是否需复核"] = "是"
            r["人工标签修正"] = fix_note
            r["主主播口径"] = "原表人工标签"
            r["单房间专属词"] = "/".join(room_exclusive_tokens(gift, main_nick)[:2])
            continue
        c1, c2, why, method, level, review, rw, style, scope = classify_v4(
            gift, prompt, main_nick, other_nicks, GTOK_ALL)
        r["一级类目_补标"] = c1
        r["二级类目_补标"] = c2
        r["风格标签"] = style
        r["打标方式"] = method
        r["打标依据"] = why
        r["打标置信度"] = level
        r["是否需复核"] = review
        r["复核原因"] = rw
        r["人工标签修正"] = ""
        r["主主播口径"] = scope
        r["单房间专属词"] = "/".join(room_exclusive_tokens(gift, main_nick)[:2])

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
    print("=== v4 打标结果（总 %d 行）===" % len(rows))
    print("打标方式:", dict(Counter(r["打标方式"] for r in rows)))
    print("主主播口径:", dict(Counter(r["主主播口径"] for r in rows)))
    print("主播IP：供给 %d/%d = %.2f%%；金额 %.0f/%.0f = %.2f%%；倍数 %.2f" % (
        len(ip), len(rows), 100.0 * len(ip) / len(rows), ip_amt, tot_amt,
        100.0 * ip_amt / tot_amt, (ip_amt / tot_amt) / (len(ip) / len(rows))))
    print("主播IP 二级分布:", dict(Counter(r["二级类目_补标"] for r in ip)))
    print("一级类目分布:", dict(Counter(r["一级类目_补标"] for r in rows).most_common()))

    need_review = [r for r in rows if r["是否需复核"] == "是"]
    room_cand = [r for r in rows if r["单房间专属词"] and r["一级类目_补标"] != "主播IP"]
    print("需复核: %d" % len(need_review))
    for k, v in Counter(r["复核原因"] for r in need_review).most_common():
        print("   %s: %d" % (k, v))
    print("单房间专属词候选（当前不在主播IP）: %d 行，金额 %.0f" % (
        len(room_cand), sum(to_num(r.get(" 打赏金额 ")) for r in room_cand)))

    from openpyxl import Workbook
    from openpyxl.styles import Font, Alignment

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

    ws3 = wb.create_sheet("需复核清单")
    ws3.append(["礼物名称", "标准价值", "打赏订单数", " 打赏金额 ", "主主播昵称", "用户提示词",
                "一级类目_补标", "二级类目_补标", "打标依据", "复核原因", "主主播口径"])
    for r in sorted(need_review, key=lambda x: -to_num(x.get(" 打赏金额 "))):
        ws3.append([r.get("礼物名称"), r.get("标准价值"), r.get("打赏订单数"), r.get(" 打赏金额 "),
                    r.get("主主播昵称"), r.get("用户提示词"), r["一级类目_补标"], r["二级类目_补标"],
                    r["打标依据"], r["复核原因"], r["主主播口径"]])

    ws5 = wb.create_sheet("房间梗候选")
    ws5.append(["礼物名称", "标准价值", " 打赏金额 ", "主主播昵称", "单房间专属词",
                "用户提示词", "当前_一级类目", "当前_二级类目", "打标方式", "打标依据"])
    for r in sorted(room_cand, key=lambda x: -to_num(x.get(" 打赏金额 "))):
        ws5.append([r.get("礼物名称"), r.get("标准价值"), r.get(" 打赏金额 "), r.get("主主播昵称"),
                    r["单房间专属词"], r.get("用户提示词"), r["一级类目_补标"], r["二级类目_补标"],
                    r["打标方式"], r["打标依据"]])
    for cell in ws5[1]:
        cell.font = Font(name="Calibri", bold=True)
    ws5.freeze_panes = "A2"

    ws4 = wb.create_sheet("口径与规则")
    ws4.append(["项目", "内容"])
    notes = [
        ("版本", "v4（2026-09-20 按用户在选择题里的选择收敛）"),
        ("输入", SRC),
        ("Q1-C", "单字匹配只保留「命中主主播」的行；命中第二/第三主播的单字一律剔除"),
        ("Q2", "只要不是本行主主播的 IP，一律剔除（圈层标记/团号/强前缀/昵称片段/单字全部只认主主播）"),
        ("Q3-B", "圈层梗词剔除通用词命中，黑名单：天天开心/憨憨/锦鲤/福星/节奏/风景/摩羯座/好棒/幸运星/爆爆爆/无忧无虑/旺旺旺/喜乐/努力鸭/巅峰第一/暴富/超甜/黑马"),
        ("Q5-A", "二级类目与一级同名保持原样（不细分、不置空）"),
        ("Q6-A", "命名统一：一级「男性人物」->「男性角色」；二级「庆生」->「庆生与祝福」"),
        ("不受 Q2 影响", "神豪/身份梗（陌白、时倾、帝临等平台级大哥身份）按用户已确认口径仍归 主播IP/网友热梗"),
        ("新增列", "主主播口径：主主播命中 / 主主播命中+另有非主主播命中 / 剔除非主主播命中 / 不涉及 / 原表人工标签"),
        ("新增列", "单房间专属词：某 2-4 字词在 2~10 个礼物里重复出现、且全部集中在同一个主播房间 => 房间梗候选；空=无"),
        ("主播IP 定义", "礼物能追溯到某个具体主播、其圈层（粉丝团/公会）、或其圈层的核心人物（超皇/神豪/榜一大哥）"),
        ("提示词优先", "提示词命中圈层标记 -> 主播热梗；仅礼物名命中 -> 主播肖像"),
    ]
    for k, v in notes:
        ws4.append([k, v])
    ws4.column_dimensions["B"].width = 110
    for row in ws4.iter_rows():
        for c in row:
            c.alignment = Alignment(wrap_text=True, vertical="top")

    wb.save(OUT_XLSX)
    print("已写 XLSX:", OUT_XLSX)


if __name__ == "__main__":
    main()
