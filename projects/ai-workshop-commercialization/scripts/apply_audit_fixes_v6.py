# -*- coding: utf-8 -*-
"""按 audit_v6 报告的 P0/P1/P2 清单，对人工打标批次文件做机械修订。

只改这 5 类，且每类都有明确口径依据；不含任何关键词自动判定。
1) P0 二级类目越界（男性角色/男性角色、动物/国风）
2) P0 归属位次非法值「其他主播」→「非本行主播」
3) P0 「柒宝生日快乐」庆生优先 vs 主播肖像冲突 → 从后口径（第九节第3条）
4) P1 主播IP 行归属位次为 `-` → `待定`
5) P2 房间母题未按第九节第4条判主播IP（10 行）

输出：原地重写命中的 batch*.tsv，并打印变更明细到 stdout；
     同时写出一份 `母题与格式修订明细_20260921.tsv` 供复盘。
"""
import glob
import os

import pandas as pd

BASE = "C:/Users/tiany/Desktop/AI工坊专题/人工打标"

# ---------------- 1) 二级类目越界 ----------------
SUBCAT_FIX = {
    "30025037": ("男性角色", "炫酷", "六翼骑士持权杖，西式炫酷造型"),
    "30022075": ("男性角色", "其他", "青年男子捧豆芽，无可爱/炫酷/国风/明星特征"),
    "30024339": ("男性角色", "其他", "康巴汉子形象，非明星非国风"),
    "30014111": ("男性角色", "炫酷", "圣光守护骑士，炫酷造型"),
    "30010879": ("男性角色", "明星", "库里（篮球运动员）真人形象"),
    "30025877": ("动物", "动物", "水墨青龙白虎，主体为动物"),
    "30000969": ("动物", "动物", "人形老虎，主体为动物"),
    "30008787": ("动物", "动物", "水墨青龙白虎，主体为动物"),
}

# ---------------- 2) 归属位次非法值 ----------------
POS_VALUE_FIX = {"其他主播": "非本行主播"}

# ---------------- 3) 柒宝生日快乐 ----------------
BIRTHDAY_CONFLICT = {
    "30018013": (
        "庆生与祝福",
        "庆生与祝福",
        "-",
        "画面主题为主播TG-喵柒生日庆生，按冻结口径第九节第3条庆生题材优先，"
        "归庆生与祝福；原第九节第3条与第三节主播肖像已验证例冲突，以从后口径为准",
    )
}

# ---------------- 5) 房间母题（第九节第4条） ----------------
MOTIF_TO_IP = {
    "30026807": ("主播肖像", "猫儿2斯诺克房间专属大橘猫形象（持台球杆骑驴）"),
    "30021167": ("主播肖像", "猫儿2斯诺克房间专属大橘猫形象（猫八戒造型）"),
    "30012145": ("主播肖像", "盛世-伯千房间专属红鼠形象"),
    "30015571": ("主播肖像", "盛世-伯千房间专属红鼠形象"),
    "30020711": ("主播肖像", "盛世-伯千房间专属红鼠形象"),
    "30007489": ("主播肖像", "盛世-伯千房间专属红鼠形象"),
    "30018669": ("主播肖像", "盛世-伯千房间专属红鼠形象"),
    "30023693": ("主播肖像", "不命苦的白熊房间专属小熊形象"),
    "30026261": ("主播肖像", "驴鸽LvGe房间专属小毛驴形象"),
    "30026313": ("主播肖像", "公主HAP房间专属猩猩公主形象"),
}


def main():
    files = [f for f in sorted(glob.glob(os.path.join(BASE, "人工标注_*.tsv"))) if "复核版" not in f]
    changes = []
    for f in files:
        d = pd.read_csv(f, sep="\t", encoding="utf-8-sig", dtype=str)
        if len(d.columns) != 6:
            continue
        d.columns = ["礼物ID", "礼物名称", "一级类目", "二级类目", "归属位次", "判断依据"]
        for i, row in d.iterrows():
            gid = str(row["礼物ID"]).strip()
            new1, new2, newpos, why = None, None, None, None
            if gid in SUBCAT_FIX:
                new1, new2, why = SUBCAT_FIX[gid]
            if gid in BIRTHDAY_CONFLICT:
                new1, new2, newpos, why = BIRTHDAY_CONFLICT[gid]
            if gid in MOTIF_TO_IP:
                new1, new2 = "主播IP", MOTIF_TO_IP[gid][0]
                newpos = "主主播"
                why = MOTIF_TO_IP[gid][1] + "；按冻结口径第九节第4条判主播IP"
            if str(row["归属位次"]).strip() in POS_VALUE_FIX:
                newpos = POS_VALUE_FIX[str(row["归属位次"]).strip()]
                why = "归属位次取值须落在冻结取值集合内，统一写『非本行主播』"
            if str(row["一级类目"]).strip() == "主播IP" and str(row["归属位次"]).strip() == "-":
                newpos = "待定"
                why = (str(row["判断依据"]) + "；主播IP行归属位次不得为空，按存疑统一写『待定』")

            if new1 is None and new2 is None and newpos is None:
                continue
            old = (row["一级类目"], row["二级类目"], row["归属位次"])
            if new1:
                d.at[i, "一级类目"] = new1
            if new2:
                d.at[i, "二级类目"] = new2
            if newpos:
                d.at[i, "归属位次"] = newpos
            if why:
                d.at[i, "判断依据"] = why
            changes.append({
                "来源文件": os.path.basename(f),
                "礼物ID": gid,
                "礼物名称": row["礼物名称"],
                "原一级": old[0], "原二级": old[1], "原归属位次": old[2],
                "新一级": d.at[i, "一级类目"], "新二级": d.at[i, "二级类目"],
                "新归属位次": d.at[i, "归属位次"],
                "修订说明": why,
            })
        d.to_csv(f, sep="\t", index=False, encoding="utf-8")

    c = pd.DataFrame(changes)
    out = os.path.join(BASE, "母题与格式修订明细_20260921.tsv")
    c.to_csv(out, sep="\t", index=False, encoding="utf-8-sig")
    print("修订行数:", len(c))
    print(c.to_string())
    print("明细已写出:", out)


if __name__ == "__main__":
    main()
