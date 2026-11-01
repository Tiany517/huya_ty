# -*- coding: utf-8 -*-
"""
AI 礼物类目补标引擎 v3（按 2026-09-20 与用户确认的新定义）

新定义要点：
  1) 一级 主播IP 的二级只剩四支：主播肖像 / 主播热梗 / 网友热梗 / 公会肖像（「热梗」并入「主播热梗」）
  2) 提示词优先级高于礼物名称
  3) 提示词里对主播/公会/粉丝团只有模糊迹象的，退回通用题材，不强行判 主播IP
  4) 神豪梗（陌白、时倾等单月打赏十万级以上的大哥）归 网友热梗

修正后人工标签基线（GOLD_FIX）来自用户逐条确认：
  - 聋瞎 / 懒聋瞎：原标 女性角色/可爱 -> 主播IP/网友热梗（跨主播的圈层梗）
  - 初皇 / 别皇：原标 女性角色·男性角色/国风 -> 主播IP/主播肖像（超皇身份定制）
  - 只手遮天：原标 场景与氛围/发财 -> 主播IP/网友热梗（提示词为"发财哥降临…直播间"）
  - 粉锤之恋：原标 主播IP/公会肖像 -> 主播IP/主播热梗（提示词"把爱留在798飘屏"）
  - 锦程壮歌：原标 主播IP/主播IP -> 主播IP/主播肖像
  - 萌白熊：原标 主播IP/动物 -> 主播IP/主播热梗
  - 二级「热梗」全部并入「主播热梗」

输出：AI工坊被送出的礼物明细_打标后.csv / .xlsx（覆盖上一版同名输出，原文件不动）
"""
import csv
import io
import re
import sys
from collections import Counter, OrderedDict

sys.path.insert(0, r"C:/Users/tiany/Desktop/AI工坊专题/scripts")
sys.stdout.reconfigure(encoding="utf-8")

import tag_ai_gift_categories_v2 as base

SRC = r"C:/Users/tiany/Desktop/AI工坊专题/AI工坊被送出的礼物明细.csv"
OUT_CSV = r"C:/Users/tiany/Desktop/AI工坊专题/AI工坊被送出的礼物明细_打标后.csv"
OUT_XLSX = r"C:/Users/tiany/Desktop/AI工坊专题/AI工坊被送出的礼物明细_打标后.xlsx"

norm = base.norm
squeeze = base.squeeze
to_num = base.to_num
strip_template = base.strip_template
row_tokens = base.row_tokens
global_tokens = base.global_tokens
THEME_RULES = base.THEME_RULES
STYLE_RULES = base.STYLE_RULES
ANIMAL_STRONG = base.ANIMAL_STRONG
ANIMAL_WEAK = base.ANIMAL_WEAK
STRONG_PREFIX = base.STRONG_PREFIX

# 全站圈层梗词：出现在任意主播昵称括号里的词（去通用词），跨主播使用时按网友热梗处理
def build_meme_tokens(rows):
    """全站圈层梗词：昵称括号里的词，剔通用词，并过滤在礼物名里高频出现的通用词（如 花海/天天开心）。"""
    toks = set()
    for r in rows:
        for col in ("主主播昵称", "第二主播昵称", "第三主播昵称"):
            nick = norm(r.get(col))
            if not nick or nick.lower() == "null":
                continue
            for m in re.findall(r"[【\[（(]([^】\]）)]+)[】\]）)]", nick):
                for part in re.split(r"[,，、\s]", m):
                    part = part.strip()
                    if len(part) >= 2 and part not in base.STOP_TOKENS and not re.fullmatch(r"[0-9]+", part):
                        toks.add(part)
    # 频次过滤：在礼物名里出现超过 10 次的词，视为通用词，不作为圈层梗
    names = [squeeze(r.get("礼物名称")) for r in rows]
    keep = set()
    for t in toks:
        freq = sum(1 for n in names if t in n)
        if freq <= 10:
            keep.add(t)
    return keep


# 全局高频字（在礼物名里出现超过 40 次），用于过滤单字匹配的噪声
COMMON_CHARS = set()


def build_common_chars(rows, threshold=80):
    from collections import Counter as _C
    c = _C()
    for r in rows:
        for ch in squeeze(r.get("礼物名称")):
            c[ch] += 1
    return {ch for ch, n in c.items() if n > threshold}

# 二级归一：热梗 -> 主播热梗
CAT2_NORMALIZE = {"热梗": "主播热梗"}

# 专家确认的神豪名（单月打赏十万级以上，属虎牙平台级身份梗）
SHENHAO_NAMES = ["陌白", "陌什么白", "陌上白", "时倾", "帝临", "发财哥", "别皇", "初皇"]
# 超皇身份定制（用户确认归 主播肖像）
CHAOHUANG_NAMES = ["阿初"]
# 明确指向具体主播/公会的身份词
IDENT_ANCHOR = ["虎牙主播", "女主播", "女主持", "超皇", "榜一大哥", "祖师爷"]
IDENT_GUILD = ["公会", "传媒", "粉丝团", "家族"]
# 神豪/大哥类身份词（归网友热梗）
IDENT_SHENHAO = ["神豪", "榜一", "大哥", "老板", "大佬", "土豪", "金主"]

# 用户逐条确认的修正后人工标签
GOLD_FIX = {
    "聋瞎": ("主播IP", "网友热梗"),
    "懒聋瞎": ("主播IP", "网友热梗"),
    "初皇": ("主播IP", "主播肖像"),
    "别皇": ("主播IP", "主播肖像"),
    "只手遮天": ("主播IP", "网友热梗"),
    "粉锤之恋": ("主播IP", "主播热梗"),
    "锦程壮歌": ("主播IP", "主播肖像"),
    "萌白熊": ("主播IP", "主播热梗"),
}


def classify_v3(gift, prompt, nicks, gtok):
    gift = norm(gift)
    prompt = norm(prompt)
    ptext = squeeze(prompt)      # 提示词（优先）
    gtext = squeeze(gift)
    text = ptext + gtext
    style = next((s for s, kws in STYLE_RULES if any(k in text for k in kws)), "其他")

    cat1 = cat2 = why = ""
    method = ""
    level = ""
    review = "否"
    review_why = ""
    vague = False

    # A. 神豪梗（平台级身份梗，归网友热梗）
    if not cat1:
        hit = next((k for k in SHENHAO_NAMES if k in text), None)
        if hit:
            cat1, cat2 = "主播IP", "网友热梗"
            why = "命中神豪/身份梗[%s]（用户确认：单月打赏十万级以上大哥）" % hit
            method = "联网核实"
            level = "高"
        else:
            hit = next((k for k in IDENT_SHENHAO if k in ptext), None)
            if hit:
                cat1, cat2 = "主播IP", "网友热梗"
                why = "提示词出现神豪/大哥身份词[%s]" % hit
                method = "词表规则"
                level = "中"
                review = "是"
                review_why = "仅命中宽泛身份词，需确认指向的具体人物"

    # B. 明确指向主播本人 / 公会
    if not cat1:
        hit = next((k for k in CHAOHUANG_NAMES if k in text), None)
        if hit:
            cat1, cat2 = "主播IP", "主播肖像"
            why = "命中超皇身份名[%s]（用户确认归主播肖像）" % hit
            method = "联网核实"
            level = "高"
    if not cat1:
        hit = next((k for k in IDENT_ANCHOR if k in ptext), None)
        if hit:
            cat1, cat2 = "主播IP", "主播肖像"
            why = "提示词出现明确主播身份词[%s]" % hit
            method = "词表规则"
            level = "高"
    if not cat1:
        hit = next((k for k in IDENT_GUILD if k in ptext), None)
        if hit:
            cat1, cat2 = "主播IP", "公会肖像"
            why = "提示词出现公会/传媒/粉丝团字样[%s]" % hit
            method = "词表规则"
            level = "中"

    # C. 本行主播圈层标记：提示词命中 -> 主播热梗；仅礼物名命中 -> 主播肖像
    if not cat1:
        toks = row_tokens(nicks)
        in_p = [t for t in toks if t in ptext]
        in_g = [t for t in toks if t in gtext]
        if in_p:
            cat1, cat2 = "主播IP", "主播热梗"
            why = "提示词命中本行主播圈层标记[%s]（提示词优先）" % "/".join(in_p[:3])
            method = "圈层规则"
            level = "高"
        elif in_g:
            cat1, cat2 = "主播IP", "主播肖像"
            why = "礼物名命中本行主播圈层标记[%s]" % "/".join(in_g[:3])
            method = "圈层规则"
            level = "中"

    # D. 全局团号/英文代号
    if not cat1:
        g = [t for t in gtok if t in text]
        if g:
            cat1, cat2 = "主播IP", "主播热梗"
            why = "命中平台主播团号/代号[%s]（提示词优先，按圈层梗处理）" % "/".join(sorted(g)[:3])
            method = "圈层规则"
            level = "中"

    # D2. 强圈层前缀（集梦/仙女/大锤酱/童锦程等），命中即为主播IP
    if not cat1:
        for p in STRONG_PREFIX:
            if p.lower() in text.lower():
                cat1, cat2 = "主播IP", "主播热梗"
                why = "命中主播圈层强前缀[%s]" % p
                method = "圈层规则"
                level = "中"
                break

    # D3. 全站圈层梗词（其他主播昵称括号里的圈层词，如 聋瞎）
    if not cat1:
        hits = [t for t in MEME_TOKENS if t in text]
        if hits:
            cat1, cat2 = "主播IP", "网友热梗"
            why = "命中全站圈层梗词[%s]（跨主播使用，按网友热梗处理）" % "/".join(hits[:3])
            method = "圈层规则"
            level = "中"

    # E. 主播昵称主名片段
    if not cat1:
        for nick in nicks:
            nick = norm(nick)
            if not nick or nick.lower() == "null":
                continue
            for part in re.split(r"[-_丶·|【\[\]（）()\s,/]", nick):
                part = re.sub(r"[A-Za-z0-9]+", "", part)
                if len(part) < 2 or part in base.STOP_TOKENS:
                    continue
                subs = {part[i:i + 2] for i in range(len(part) - 1)}
                hit = next((s for s in sorted(subs, key=len, reverse=True) if s in text), None)
                if hit:
                    cat1, cat2 = "主播IP", "主播肖像"
                    why = "礼物名/提示词命中主播主名片段[%s]（主播=%s）" % (hit, nick)
                    method = "圈层规则"
                    level = "中"
                    break
            if cat1:
                break

    # F. 主题材规则（含国风优先/纯文字/兜底）
    # E2. 主播主名单字匹配（只匹配低频字，且只在礼物名里找，避免提示词噪声）
    if not cat1:
        for nick in nicks:
            nick = norm(nick)
            if not nick or nick.lower() == "null":
                continue
            for part in re.split(r"[-_丶·|【\[\]（）()\s,/]", nick):
                part = re.sub(r"[A-Za-z0-9]+", "", part)
                if len(part) < 2 or part in base.STOP_TOKENS:
                    continue
                hit = next((ch for ch in part if ch not in COMMON_CHARS and ch in gtext), None)
                if hit:
                    cat1, cat2 = "主播IP", "主播肖像"
                    why = "礼物名命中主播主名低频字[%s]（主播=%s）" % (hit, nick)
                    method = "圈层规则"
                    level = "中"
                    review = "是"
                    review_why = "仅单字匹配，需人工确认是否为主播相关"
                    break
            if cat1:
                break

    if not cat1:
        for c1, c2, kws, strength in THEME_RULES:
            hit = next((k for k in kws if k in text), None)
            if hit:
                cat1, cat2 = c1, c2
                why = "命中题材关键词[%s]" % hit
                method = "词表规则"
                level = "高" if strength == "strong" else "中"
                break
        if not cat1:
            hit = next((k for k in ANIMAL_STRONG if k in text), None)
            if not hit:
                hit = next((k for k in ANIMAL_WEAK if k in gtext), None)
            if hit:
                cat1, cat2 = "动物", "动物"
                why = "命中动物关键词[%s]" % hit
                method = "词表规则"
                level = "高" if hit in ANIMAL_STRONG else "中"
        if not cat1:
            gm = gtext
            pbody = strip_template(prompt)
            if gm and (pbody == gm or (len(pbody) <= 14 and gm in pbody)):
                cat1, cat2 = "文字互动", "文字互动"
                why = "礼物名与提示词同为纯文字口号[%s]" % gm
                method = "词表规则"
                level = "中"
        if cat1 in ("动物", "神话角色") and style == "国风":
            if not re.search(r"(一只|一条|一群|可爱的|喵|汪汪)", text):
                why = "%s；整体为国风/水墨意境，按打标习惯归入 场景与氛围/国风" % why
                cat1, cat2 = "场景与氛围", "国风"
                level = "中"
        if not cat1:
            if not prompt:
                cat1, cat2 = "其他", "其他"
                why = "无提示词，无法判定题材"
                method = "兜底"
                level = "低"
                review = "是"
                review_why = "无提示词"
            else:
                cat1 = "场景与氛围"
                cat2 = "国风" if style == "国风" else "其他"
                why = "未命中明确题材关键词，按氛围类兜底（风格=%s）" % style
                method = "兜底"
                level = "低"
                review = "是"
                review_why = "未命中题材词，需人工确认题材"

    if not cat2:
        cat2 = cat1
    cat2 = CAT2_NORMALIZE.get(cat2, cat2)
    return cat1, cat2, why, method, level, review, review_why, style


def main():
    with io.open(SRC, "r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        fieldnames = list(reader.fieldnames)
        rows = [r for r in reader]

    gtok = global_tokens(rows)
    global MEME_TOKENS
    MEME_TOKENS = build_meme_tokens(rows)
    print("全站圈层梗词数:", len(MEME_TOKENS))
    global COMMON_CHARS
    COMMON_CHARS = build_common_chars(rows)
    print("全局高频字过滤数:", len(COMMON_CHARS))
    new_cols = ["一级类目_补标", "二级类目_补标", "风格标签", "打标方式", "打标依据",
                "打标置信度", "是否需复核", "复核原因", "人工标签修正"]

    for r in rows:
        gift = norm(r.get("礼物名称"))
        prompt = norm(r.get("用户提示词"))
        nicks = [r.get("主主播昵称"), r.get("第二主播昵称"), r.get("第三主播昵称")]
        old1 = norm(r.get("一级类目"))
        if old1:
            name = gift
            fix = GOLD_FIX.get(name)
            c1 = old1
            c2 = CAT2_NORMALIZE.get(norm(r.get("二级类目")), norm(r.get("二级类目")))
            fix_note = ""
            if fix:
                c1, c2 = fix
                fix_note = "用户确认修正：%s/%s -> %s/%s" % (old1, norm(r.get("二级类目")), c1, c2)
            r["一级类目_补标"] = c1
            r["二级类目_补标"] = c2
            text = squeeze(gift + " " + prompt)
            r["风格标签"] = next((s for s, kws in STYLE_RULES if any(k in text for k in kws)), "其他")
            r["打标方式"] = "原表沿用（含用户修正）" if fix else "原表沿用"
            r["打标依据"] = fix_note or "原文件已有类目（二级「热梗」已并入「主播热梗」）"
            r["打标置信度"] = "高"
            r["是否需复核"] = "否"
            r["复核原因"] = ""
            r["人工标签修正"] = fix_note
            continue
        c1, c2, why, method, level, review, rw, style = classify_v3(gift, prompt, nicks, gtok)
        r["一级类目_补标"] = c1
        r["二级类目_补标"] = c2
        r["风格标签"] = style
        r["打标方式"] = method
        r["打标依据"] = why
        r["打标置信度"] = level
        r["是否需复核"] = review
        r["复核原因"] = rw
        r["人工标签修正"] = ""

    out_cols = fieldnames + new_cols
    with io.open(OUT_CSV, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=out_cols, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow(r)
    print("已写 CSV:", OUT_CSV)

    need_review = [r for r in rows if r["是否需复核"] == "是"]
    print("")
    print("=== v3 打标结果（总 %d 行）===" % len(rows))
    print("打标方式:", dict(Counter(r["打标方式"] for r in rows)))
    print("需复核: %d" % len(need_review))
    for k, v in Counter(r["复核原因"] for r in need_review).most_common():
        print("   %s: %d" % (k, v))

    # 主播IP 结构
    tot_amt = sum(to_num(r.get(" 打赏金额 ")) for r in rows)
    ip = [r for r in rows if r["一级类目_补标"] == "主播IP"]
    ip_amt = sum(to_num(r.get(" 打赏金额 ")) for r in ip)
    print("")
    print("主播IP：供给 %d/%d = %.2f%%；金额 %.0f/%.0f = %.2f%%；倍数 %.2f" % (
        len(ip), len(rows), 100.0 * len(ip) / len(rows), ip_amt, tot_amt, 100.0 * ip_amt / tot_amt,
        (ip_amt / tot_amt) / (len(ip) / len(rows))))
    print("主播IP 二级分布:", dict(Counter(r["二级类目_补标"] for r in ip)))

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
                "一级类目_补标", "二级类目_补标", "打标依据", "复核原因"])
    for r in sorted(need_review, key=lambda x: -to_num(x.get(" 打赏金额 "))):
        ws3.append([r.get("礼物名称"), r.get("标准价值"), r.get("打赏订单数"), r.get(" 打赏金额 "),
                    r.get("主主播昵称"), r.get("用户提示词"), r["一级类目_补标"], r["二级类目_补标"],
                    r["打标依据"], r["复核原因"]])

    ws4 = wb.create_sheet("人工修正与规则")
    ws4.append(["项目", "内容"])
    notes = [
        ("版本", "v3（2026-09-20 与用户确认的新定义）"),
        ("输入", SRC),
        ("主播IP 定义", "礼物能追溯到某个具体主播、其圈层（粉丝团/公会）、或其圈层的核心人物（超皇/神豪/榜一大哥）"),
        ("主播IP 二级", "主播肖像 / 主播热梗 / 网友热梗 / 公会肖像（原「热梗」并入「主播热梗」）"),
        ("提示词优先", "提示词命中圈层标记 -> 主播热梗；仅礼物名命中 -> 主播肖像"),
        ("模糊退回", "提示词对主播/公会/粉丝团只有模糊迹象时，退回通用题材，不强行判主播IP"),
        ("神豪梗", "陌白、时倾等单月打赏十万级以上的大哥，归 网友热梗（用户确认时倾单月最高180万）"),
        ("用户逐条修正", "聋瞎、懒聋瞎 -> 网友热梗；初皇、别皇 -> 主播肖像；只手遮天 -> 网友热梗；粉锤之恋 -> 主播热梗；锦程壮歌 -> 主播肖像；萌白熊 -> 主播热梗"),
    ]
    for k, v in notes:
        ws4.append([k, v])
    ws4.column_dimensions["B"].width = 100
    for row in ws4.iter_rows():
        for c in row:
            c.alignment = Alignment(wrap_text=True, vertical="top")

    wb.save(OUT_XLSX)
    print("已写 XLSX:", OUT_XLSX)


if __name__ == "__main__":
    main()
