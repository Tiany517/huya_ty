# -*- coding: utf-8 -*-
"""v5 回测：以人工标签为基线，测一级/二级一致率与主播IP二分类指标（含第二/第三主播回收）"""
import csv
import io
import sys
from collections import Counter

sys.path.insert(0, r"C:/Users/tiany/Desktop/AI工坊专题/scripts")
sys.stdout.reconfigure(encoding="utf-8")

import tag_ai_gift_categories_v2 as base
import tag_ai_gift_categories_v3 as v3
import tag_ai_gift_categories_v4 as v4
import tag_ai_gift_categories_v5 as v5

norm, to_num = base.norm, base.to_num

with io.open(v5.SRC, "r", encoding="utf-8-sig", newline="") as f:
    rows = [r for r in csv.DictReader(f)]

GTOK = base.global_tokens(rows)
v3.MEME_TOKENS = v3.build_meme_tokens(rows) - v4.GENERIC_MEME_BLOCK
v3.COMMON_CHARS = v3.build_common_chars(rows)
lab = [r for r in rows if norm(r.get("一级类目"))]


def predict(r):
    gift = norm(r.get("礼物名称"))
    prompt = norm(r.get("用户提示词"))
    nicks = [norm(r.get("主主播昵称")), norm(r.get("第二主播昵称")), norm(r.get("第三主播昵称"))]
    text = base.squeeze(gift + " " + prompt)
    gtext = base.squeeze(gift)
    c1, c2 = v5.classify_one(gift, prompt, nicks[0], GTOK)[:2]
    pos = 0
    if c1 != "主播IP":
        for i in (1, 2):
            if not nicks[i] or nicks[i].lower() == "null":
                continue
            if not any(v5.pos_hits(nicks[i], text, gtext)):
                continue
            b1, b2 = v5.classify_one(gift, prompt, nicks[i], GTOK)[:2]
            if b1 == "主播IP":
                c1, c2, pos = b1, b2, i
                break
    return c1, c2, pos


def gold_of(r):
    name = norm(r.get("礼物名称"))
    fx = v3.GOLD_FIX.get(name)
    if fx:
        g1, g2 = fx
    else:
        g1 = norm(r.get("一级类目"))
        g2 = v3.CAT2_NORMALIZE.get(norm(r.get("二级类目")), norm(r.get("二级类目")))
    g1 = v4.CAT1_FIX.get(g1, g1)
    g2 = v4.CAT2_FIX.get(g2, g2)
    if g1 == "主播IP" and g2 not in v4.IP_BRANCHES:
        g2 = "主播肖像"
    return g1, g2


h1 = h2 = 0
TP = FP = FN = TN = 0
bad = Counter()
fn_amt = fp_amt = 0.0
fnl, fpl = [], []
for r in lab:
    g1, g2 = gold_of(r)
    p1, p2, _pos = predict(r)
    if p1 == g1:
        h1 += 1
    else:
        bad[(g1, p1)] += 1
    if p1 == g1 and p2 == g2:
        h2 += 1
    t, p = g1 == "主播IP", p1 == "主播IP"
    amt = to_num(r.get(" 打赏金额 "))
    if t and p:
        TP += 1
    elif p and not t:
        FP += 1
        fp_amt += amt
        if len(fpl) < 12:
            fpl.append((norm(r.get("礼物名称")), g1, p2, norm(r.get("用户提示词"))[:36]))
    elif t and not p:
        FN += 1
        fn_amt += amt
        if len(fnl) < 12:
            fnl.append((norm(r.get("礼物名称")), g2, p1, p2, norm(r.get("用户提示词"))[:36]))
    else:
        TN += 1

n = len(lab)
prec = TP / (TP + FP) if TP + FP else 0
rec = TP / (TP + FN) if TP + FN else 0
f1 = 2 * prec * rec / (prec + rec) if prec + rec else 0
print("基线 %d 行" % n)
print("一级一致 %.1f%%；二级一致 %.1f%%" % (100.0 * h1 / n, 100.0 * h2 / n))
print("主播IP: TP=%d FP=%d FN=%d TN=%d｜精确 %.1f%% 召回 %.1f%% F1 %.1f%%" % (
    TP, FP, FN, TN, 100 * prec, 100 * rec, 100 * f1))
print("漏判金额 %.0f；误判金额 %.0f" % (fn_amt, fp_amt))
print("一级误判 TOP10:")
for (g, p), c in bad.most_common(10):
    print("   %-10s -> %-10s : %d" % (g, p, c))
print("漏判样例:")
for e in fnl[:8]:
    print("   %-12s 人工二级=%-8s 规则=%s/%s | %s" % e)
print("误判样例:")
for e in fpl[:8]:
    print("   %-12s 人工一级=%-8s 规则二级=%-8s | %s" % e)
