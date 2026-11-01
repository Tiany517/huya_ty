# -*- coding: utf-8 -*-
"""
AI 礼物类目补标引擎（v2）
在 v1 基础上按"回测误判"做的修正：
  1) 圈层匹配改为"同一行主播昵称 token 命中"优先，全局库只保留高区分度 token（团号/英文代号/强前缀）
  2) 国风/水墨风格优先压过动物、神话，落到 场景与氛围/国风（复现打标人的兜底习惯）
  3) 场景与氛围 无具体主题时，国风风格 -> 国风，否则 -> 其他
  4) 新增"纯文字口号"识别 -> 文字互动
  5) 题材二级不再被风格词覆盖

输入：C:/Users/tiany/Desktop/AI工坊专题/AI工坊被送出的礼物明细.csv（只读）
输出：同目录 AI工坊被送出的礼物明细_打标后.csv / .xlsx
"""
import csv
import io
import re
import sys
from collections import Counter, OrderedDict

sys.stdout.reconfigure(encoding="utf-8")

SRC = r"C:/Users/tiany/Desktop/AI工坊专题/AI工坊被送出的礼物明细.csv"
OUT_CSV = r"C:/Users/tiany/Desktop/AI工坊专题/AI工坊被送出的礼物明细_打标后.csv"
OUT_XLSX = r"C:/Users/tiany/Desktop/AI工坊专题/AI工坊被送出的礼物明细_打标后.xlsx"

# 通用词黑名单：出现在主播昵称里但不足以判定为圈层标记
STOP_TOKENS = {
    "公主", "仙女", "可爱", "女王", "女神", "温暖", "阳光", "发财", "好运", "幸运",
    "甜心", "宝贝", "小可爱", "大王", "宝宝", "哥哥", "弟弟", "妹妹", "姐姐",
    "快乐", "开心", "幸福", "加油", "美好", "小白", "白白", "小小白", "小仙女",
    "颜值", "才艺", "唱歌", "跳舞", "主播", "公會", "公会", "家族", "传媒",
}

# 强前缀：区分度高，命中即为圈层
STRONG_PREFIX = [
    "集梦", "集美", "狂鸟", "正恒", "大锤酱", "童锦程", "小小小酷哥", "书香", "乐听",
    "乐佰", "盛世", "映画", "满创", "龙城", "金水", "魔创", "蔚璃", "奇领", "朝朝",
    "壮壮", "子圣", "师兄", "图一", "桃桃", "雯雯", "月玥", "小奶狗", "懒懒大王",
    "不命苦的白熊", "神枪小子", "老实人sask", "DANK1NG", "kRYST4L", "Letme严君泽",
    "QY", "TG", "HR", "AH", "MY", "XG", "JS", "LK", "DK", "CX", "CUTE", "ZKL",
]

# 弱前缀：可能是圈层也可能是通用词
WEAK_PREFIX = ["仙女", "组织", "小白", "白熊"]

# 已核实的梗 / 身份词
VERIFIED_MEME = {
    "陌白": ("主播IP", "网友热梗", "陌白-798圈层大哥身份梗（百度检索：子圣-798直播间 恭喜陌白哥荣升超神帝皇）"),
    "陌什么白": ("主播IP", "网友热梗", "陌白圈层大哥身份梗（同上）"),
    "陌上白": ("主播IP", "网友热梗", "陌白衍生写法（同上）"),
    "帝临": ("主播IP", "网友热梗", "帝临-与陌白同源的圈层身份梗（百度检索命中）"),
    "时倾": ("主播IP", "网友热梗", "时倾-跨多个直播间的公共梗（百度检索：虎牙时倾相关）"),
    "别皇": ("主播IP", "主播肖像", "虎牙超皇身份定制（提示词自述）"),
    "初皇": ("主播IP", "主播肖像", "虎牙超皇阿初身份定制（提示词自述）"),
    "聋瞎": ("主播IP", "主播热梗", "懒懒大王直播间圈层梗"),
    "懒懒大王": ("主播IP", "主播热梗", "主播昵称本身即梗"),
    "八门": ("主播IP", "公会肖像", "大锤酱798圈层组织称号"),
    "黄门": ("主播IP", "热梗", "直播间圈层组织称号"),
    "虎粮": ("场景与氛围", "猫粮", "平台常驻礼物虎粮一号的AI化（百度检索：虎牙一号=1000元）"),
    "虎牙一号": ("场景与氛围", "虎牙一号", "平台常驻礼物（百度检索：虎牙一号=1000虎牙币=1000元）"),
}

# 明确动物主体
ANIMAL_STRONG = ["猫", "狗", "熊", "兔", "猪", "鸭", "鹅", "鹦鹉", "鲲", "鹏", "鼠",
                 "狐狸", "猩猩", "乌龟", "法斗", "二哈", "狸猫", "哈士奇", "青蛙",
                 "鸽子", "螃蟹", "鹿", "老虎", "狮子", "大象", "猴子", "孔雀", "金鱼"]
ANIMAL_WEAK = ["龙", "虎", "马", "牛", "羊", "鱼", "鸟", "蛇", "鳄"]

STYLE_RULES = [
    ("国风", ["国风", "古风", "水墨", "汉服", "仙侠", "东方", "古装", "国漫", "中式", "新中式", "盛唐", "汉风", "墨色", "仙殿", "天阙", "仙气", "灵气"]),
    ("可爱", ["可爱", "萌", "甜心", "Q版", "卡哇伊", "软萌", "乖乖", "奶萌", "小可爱"]),
    ("酷炫", ["酷炫", "赛博", "暗黑", "机甲", "科幻", "霓虹", "金属", "重工", "黑色系"]),
]

THEME_RULES = [
    ("庆生与祝福", "庆生与祝福", ["生日快乐", "生日", "庆生", "周年庆", "蛋糕", "寿星"], "strong"),
    ("诙谐低俗", "诙谐低俗", ["象拔蚌", "粑粑", "屎", "勾八", "放屁", "臭鸡蛋", "蛆", "垃圾桶", "厕所", "马桶", "蟑螂", "丑八怪", "变态辣"], "strong"),
    ("惊悚", "惊悚", ["恐怖", "鬼", "骷髅", "万圣", "幽灵", "丧尸", "棺材"], "strong"),
    ("豪车载具", "豪车载具", ["法拉利", "兰博基尼", "玛莎拉蒂", "保时捷", "劳斯莱斯", "布加迪", "跑车", "敞篷", "机车", "摩托", "豪车", "游艇", "敞篷车"], "strong"),
    ("美食饮品", "食品/饮品", ["香蕉", "板栗", "可乐", "奶茶", "咖啡", "火锅", "烧烤", "自助餐", "薯条", "冰淇淋", "馒头", "炒饭", "饺子", "汉堡", "蓝莓", "西瓜", "葡萄", "椰子", "面包", "田螺"], "strong"),
    ("生活用品", "生活用品", ["纸尿裤", "戒指", "卡片", "砖", "牙刷", "纸巾", "鞋子", "包包", "手电筒", "沙包", "信封"], "strong"),
    ("游戏/动漫角色", "游戏/动漫角色", ["王者荣耀", "火影", "龙珠", "比克", "佩恩", "蜡笔小新", "寒冰射手", "英雄联盟", "原神", "狄仁杰", "齐天大圣", "斗战胜佛", "蒙恬", "锦衣卫", "库洛米", "皮卡丘"], "strong"),
    ("神话角色", "神话角色", ["牛魔王", "二郎神", "哪吒", "财神", "魔尊", "天帝", "古神", "神尊", "上古神", "龙王", "佛祖", "菩萨", "盘古", "女娲"], "strong"),
    ("CP", "CP", ["情侣", "拥抱", "牵手", "亲吻", "求婚", "相拥", "结婚", "恋人", "单膝跪", "恋爱"], "strong"),
    ("女性角色", "可爱", ["女孩", "少女", "公主", "仙女", "女神", "美女", "小姐姐", "女主播", "女明星", "萌妹", "姑娘", "歌姬", "舞姬", "女王", "仙子", "天使", "富婆", "女武神", "女帝"], "strong"),
    ("男性角色", "男性角色", ["男生", "男孩", "少年", "帅哥", "男神", "王子", "总裁", "剑仙", "剑客", "将军", "少爷", "男士"], "strong"),
    ("场景与氛围", "城堡", ["城堡", "古堡", "宫殿", "殿堂"], "strong"),
    ("场景与氛围", "嘉年华", ["嘉年华", "游乐园", "摩天轮", "旋转木马", "过山车"], "strong"),
    ("场景与氛围", "玫瑰", ["玫瑰", "花海", "花束"], "strong"),
    ("场景与氛围", "流星雨", ["流星雨", "流星", "星空", "银河", "星云", "繁星", "星光"], "strong"),
    ("场景与氛围", "烟花", ["烟花", "焰火", "礼花"], "strong"),
    ("场景与氛围", "金钱雨", ["金钱雨", "钱从天", "钞票", "金币雨", "金砖"], "strong"),
    ("场景与氛围", "阳光", ["阳光", "向阳", "暖阳"], "strong"),
    ("场景与氛围", "夕阳", ["夕阳", "落日", "黄昏"], "strong"),
    ("场景与氛围", "太阳", ["太阳", "烈日"], "strong"),
    ("场景与氛围", "植被", ["梧桐", "盆栽", "森林", "桃花树", "樱花树", "花海"], "strong"),
    ("场景与氛围", "抽奖池", ["奖池", "抽奖"], "strong"),
    ("场景与氛围", "发财", ["发财", "富贵", "暴富"], "strong"),
    ("场景与氛围", "国风", ["国风", "古风", "水墨", "汉服", "仙侠", "古装", "国漫", "中式", "仙殿", "天阙", "仙境", "仙气", "灵气", "龙啸", "凤舞", "神龙", "金龙", "古神"], "strong"),
    ("场景与氛围", "其他", ["月亮", "弯月", "夜色", "夜晚", "沙滩", "雪花", "钟楼", "王座", "旗帜", "舞台", "红毯", "云海", "祥云", "彩虹", "光环", "水晶", "特效"], "weak"),
]


def norm(s):
    return (s or "").strip()


def squeeze(s):
    return re.sub(r"\s+", "", norm(s))


def strip_template(s):
    s = squeeze(s)
    for w in ("礼物名称：", "礼物名称:", "礼物名称为", "礼物名字：", "礼物名字:", "礼物名叫", "礼物名字", "礼物名为", "礼物名：", "礼物名:", "礼物名", "名字叫", "命名为", "名字是", "名字："):
        s = s.replace(w, "")
    return s


def to_num(s):
    try:
        return float(norm(s).replace(",", ""))
    except Exception:
        return 0.0


def row_tokens(nicks):
    """从同一行的主播昵称抽 token（高精度：只取括号内容、团号、强前缀）。"""
    toks = set()
    for nick in nicks:
        nick = norm(nick)
        if not nick or nick.lower() == "null":
            continue
        for m in re.findall(r"[【\[（(]([^】\]）)]+)[】\]）)]", nick):
            for part in re.split(r"[,，、\s]", m):
                part = part.strip()
                if len(part) >= 2 and part not in STOP_TOKENS:
                    toks.add(part)
        for m in re.findall(r"(?<![0-9])([0-9]{3,5})(?![0-9])", nick):
            toks.add(m)
        for p in STRONG_PREFIX:
            if p in nick:
                toks.add(p)
    return toks


def global_tokens(rows):
    """全局高区分度 token：只保留团号与英文代号。"""
    toks = set()
    for r in rows:
        for col in ("主主播昵称", "第二主播昵称", "第三主播昵称"):
            nick = norm(r.get(col))
            if not nick or nick.lower() == "null":
                continue
            for m in re.findall(r"(?<![0-9A-Za-z])([0-9]{3,5})(?![0-9])", nick):
                toks.add(m)
            for m in re.findall(r"(?<![A-Za-z])([A-Z]{2,6})(?![A-Za-z])", nick):
                toks.add(m)
    return toks


def classify(gift, prompt, nicks, gtok):
    text = squeeze(gift + " " + prompt)
    pbody = strip_template(prompt)
    style = next((s for s, kws in STYLE_RULES if any(k in text for k in kws)), "其他")

    cat1 = cat2 = why = ""
    method = ""
    level = ""
    review = "否"
    review_why = ""

    # 2) 同一行圈层 token
    own = [t for t in row_tokens(nicks) if t in text]
    if own:
        cat1, cat2 = "主播IP", "主播肖像"
        why = "礼物名/提示词命中本行主播圈层标记[%s]" % "/".join(own[:3])
        method = "圈层规则"
        level = "高"
        if any(k in text for k in ("公会", "传媒", "家族")):
            cat2 = "公会肖像"

    # 3) 全局团号/英文代号
    if not cat1:
        g = [t for t in gtok if t in text]
        if g:
            cat1, cat2 = "主播IP", "主播肖像"
            why = "命中平台主播团号/代号[%s]" % "/".join(sorted(g)[:3])
            method = "圈层规则"
            level = "高"

    # 4) 已核实梗
    if not cat1:
        for kw, (c1, c2, src) in VERIFIED_MEME.items():
            if kw in text:
                cat1, cat2, why = c1, c2, "命中已核实梗[%s]：%s" % (kw, src)
                method = "联网核实"
                level = "高"
                break

    # 5) 主播昵称"主名"片段（去掉圈层前缀后的中文名，如 正恒-桃老师Tyii -> 桃老师）
    if not cat1:
        for nick in nicks:
            nick = norm(nick)
            if not nick or nick.lower() == "null":
                continue
            for part in re.split(r"[-_丶·|【\[\]（）()\s,/]", nick):
                part = re.sub(r"[A-Za-z0-9]+", "", part)
                if len(part) < 2 or part in STOP_TOKENS:
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

    # 6) 强前缀
    if not cat1:
        for p in STRONG_PREFIX:
            if p.lower() in text.lower():
                cat1, cat2 = "主播IP", "主播肖像"
                why = "命中主播圈层前缀[%s]" % p
                method = "圈层规则"
                level = "中"
                break

    # 6) 弱前缀 / 公会词
    if not cat1:
        for p in WEAK_PREFIX:
            if p in text:
                cat1, cat2 = "主播IP", "主播肖像"
                why = "命中弱圈层词[%s]（可能为主播所属公会/圈层）" % p
                method = "圈层规则"
                level = "中"
                review = "是"
                review_why = "弱圈层词，需确认是否为主播IP"
                break
    if not cat1 and any(k in text for k in ("公会", "传媒", "家族", "粉丝团")):
        cat1, cat2 = "主播IP", "公会肖像"
        why = "命中公会/传媒/家族字样"
        method = "词表规则"
        level = "中"

    # 7) 平台身份词（超皇/榜一/虎牙主播/女主持）
    if not cat1 and any(k in text for k in ("虎牙主播", "女主持", "超皇", "榜一", "榜一大哥", "大哥")):
        cat1, cat2 = "主播IP", "主播肖像"
        why = "提示词出现平台身份词（虎牙主播/超皇/榜一/女主持）"
        method = "词表规则"
        level = "高"

    # 8) 题材规则（含动物强弱区分与国风优先）
    if not cat1:
        for c1, c2, kws, strength in THEME_RULES:
            hit = next((k for k in kws if k in text), None)
            if hit:
                cat1, cat2 = c1, c2
                why = "命中题材关键词[%s]" % hit
                method = "词表规则"
                level = "高" if strength == "strong" else "中"
                break
        # 动物：强词优先，弱词只在礼物名里出现才算
        if not cat1:
            hit = next((k for k in ANIMAL_STRONG if k in text), None)
            if not hit:
                hit = next((k for k in ANIMAL_WEAK if k in squeeze(gift)), None)
            if hit:
                cat1, cat2 = "动物", "动物"
                why = "命中动物关键词[%s]" % hit
                method = "词表规则"
                level = "高" if hit in ANIMAL_STRONG else "中"

    # 9) 纯文字口号（放在题材之后，避免把有明确题材的礼物误判成文字）
    if not cat1:
        gm = squeeze(gift)
        if gm and (pbody == gm or (len(pbody) <= 14 and gm in pbody)):
            cat1, cat2 = "文字互动", "文字互动"
            why = "礼物名与提示词同为纯文字口号[%s]" % gm
            method = "词表规则"
            level = "中"

    # 10) 国风优先压过动物/神话（复现打标人兜底习惯）
    if cat1 in ("动物", "神话角色") and style == "国风":
        native = re.search(r"(一只|一条|一群|一只可爱|可爱的|喵|汪汪)", text) is not None
        if not native:
            why = "%s，但整体为国风/水墨意境，按打标人习惯归入 场景与氛围/国风（原判定=%s，依据=%s）" % (why, cat1, cat2 or cat1)
            cat1, cat2 = "场景与氛围", "国风"
            method = "词表规则"
            level = "中"

    # 10) 兜底
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
    return cat1, cat2, why, method, level, review, review_why, style


def main():
    with io.open(SRC, "r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        fieldnames = list(reader.fieldnames)
        rows = [r for r in reader]

    gtok = global_tokens(rows)
    print("全局高区分度 token 数:", len(gtok))

    new_cols = ["一级类目_补标", "二级类目_补标", "风格标签", "打标方式", "打标依据",
                "打标置信度", "是否需复核", "复核原因"]

    for r in rows:
        old1 = norm(r.get("一级类目"))
        if old1:
            r["一级类目_补标"] = old1
            r["二级类目_补标"] = norm(r.get("二级类目"))
            text = squeeze(norm(r.get("礼物名称")) + " " + norm(r.get("用户提示词")))
            r["风格标签"] = next((s for s, kws in STYLE_RULES if any(k in text for k in kws)), "其他")
            r["打标方式"] = "原表沿用"
            r["打标依据"] = "原文件已有类目"
            r["打标置信度"] = "高"
            r["是否需复核"] = "否"
            r["复核原因"] = ""
            continue
        nicks = [r.get("主主播昵称"), r.get("第二主播昵称"), r.get("第三主播昵称")]
        c1, c2, why, method, level, review, rw, style = classify(
            norm(r.get("礼物名称")), norm(r.get("用户提示词")), nicks, gtok)
        r["一级类目_补标"] = c1
        r["二级类目_补标"] = c2
        r["风格标签"] = style
        r["打标方式"] = method
        r["打标依据"] = why
        r["打标置信度"] = level
        r["是否需复核"] = review
        r["复核原因"] = rw

    out_cols = fieldnames + new_cols
    with io.open(OUT_CSV, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=out_cols, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow(r)
    print("已写 CSV:", OUT_CSV)

    new_tagged = [r for r in rows if r["打标方式"] != "原表沿用"]
    dist1 = Counter(r["一级类目_补标"] for r in rows)
    need_review = [r for r in rows if r["是否需复核"] == "是"]
    print("")
    print("=== 打标结果 ===")
    print("总行数 %d  新增 %d  沿用 %d" % (len(rows), len(new_tagged), len(rows) - len(new_tagged)))
    print("打标方式:", dict(Counter(r["打标方式"] for r in rows)))
    print("新增置信度:", dict(Counter(r["打标置信度"] for r in new_tagged)))
    print("需复核:", len(need_review), dict(Counter(r["复核原因"] for r in need_review)))
    print("")
    for k, v in dist1.most_common():
        print("   %-14s %d" % (k, v))

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
    ws2.append(["一级类目_补标", "行数", "打赏订单数", "打赏金额"])
    agg = OrderedDict()
    for r in rows:
        k = r["一级类目_补标"]
        a = agg.setdefault(k, [0, 0.0, 0.0])
        a[0] += 1
        a[1] += to_num(r.get("打赏订单数"))
        a[2] += to_num(r.get(" 打赏金额 "))
    for k, a in sorted(agg.items(), key=lambda x: -x[1][1]):
        ws2.append([k, int(a[0]), int(a[1]), round(a[2], 2)])

    ws3 = wb.create_sheet("需复核清单")
    ws3.append(["礼物名称", "标准价值", "打赏订单数", " 打赏金额 ", "主主播昵称", "用户提示词",
                "一级类目_补标", "二级类目_补标", "打标依据", "复核原因"])
    for r in sorted(need_review, key=lambda x: -to_num(x.get(" 打赏金额 "))):
        ws3.append([r.get("礼物名称"), r.get("标准价值"), r.get("打赏订单数"), r.get(" 打赏金额 "),
                    r.get("主主播昵称"), r.get("用户提示词"), r["一级类目_补标"], r["二级类目_补标"],
                    r["打标依据"], r["复核原因"]])

    ws4 = wb.create_sheet("打标规则说明")
    ws4.append(["项目", "内容"])
    notes = [
        ("输入文件", SRC),
        ("输出文件", OUT_XLSX),
        ("样本范围", "全表 %d 个 AI 礼物；原文件已打标行沿用不覆盖" % len(rows)),
        ("判定顺序", "原表沿用 > 主播IP(本行圈层token > 全局团号 > 已核实梗 > 强/弱前缀 > 公会词) > 纯文字口号 > 题材规则 > 国风优先 > 场景与氛围兜底 > 其他"),
        ("圈层匹配口径", "同一行主/第二/第三主播昵称的括号内容、3-5位团号、强前缀，与礼物名+提示词求交集；全局只保留团号与英文代号"),
        ("联网核实来源", "百度检索：陌白(子圣-798直播间 恭喜陌白哥荣升超神帝皇)；kRYST4L=杨藩(前LOL职业选手)；DANK1NG=吕郑豪(前CSGO职业选手)；虎牙一号=1000虎牙币=1000元"),
        ("回测结果", "以原文件 339 行人工标签为答案，规则一级一致率见 回测结果 页"),
        ("风格标签", "国风/可爱/酷炫单独成列，不与主题维度混层"),
        ("置信度口径", "高=命中本行圈层token/团号/已核实梗/明确题材词；中=弱前缀或弱题材词；低=兜底"),
        ("已知局限", "二级类目在原始人工标签本身就存在同名、跨层、碎片化问题，规则难以完全复现；未核实的圈内梗会落到题材或兜底"),
    ]
    for k, v in notes:
        ws4.append([k, v])
    ws4.column_dimensions["B"].width = 100
    for row in ws4.iter_rows():
        for c in row:
            c.alignment = Alignment(wrap_text=True, vertical="top")

    # 回测页：用 339 行人工标签检验规则一致率
    ws5 = wb.create_sheet("回测结果")
    ws5.append(["指标", "数值"])
    lab = [r for r in rows if norm(r.get("一级类目"))]
    h1 = h2 = 0
    bad = Counter()
    for r in lab:
        nicks = [r.get("主主播昵称"), r.get("第二主播昵称"), r.get("第三主播昵称")]
        p1, p2, _w, _m, _l, _rv, _rw, _s = classify(
            norm(r.get("礼物名称")), norm(r.get("用户提示词")), nicks, gtok)
        t1 = norm(r.get("一级类目"))
        t2 = norm(r.get("二级类目"))
        if p1 == t1:
            h1 += 1
        else:
            bad[(t1, p1)] += 1
        if p1 == t1 and p2 == t2:
            h2 += 1
    nl = len(lab)
    ws5.append(["人工已打标样本数", nl])
    ws5.append(["一级类目一致行数", h1])
    ws5.append(["一级类目一致率", "%.1f%%" % (100.0 * h1 / nl)])
    ws5.append(["二级类目一致行数", h2])
    ws5.append(["二级类目一致率", "%.1f%%" % (100.0 * h2 / nl)])
    ws5.append(["说明", "回测=把规则跑在339行人工标签上，看能否复现。剩余差异主要来自打标人按整体意境判断的部分（同一题材在不同行被归到不同一级），非单一规则可复现"])
    ws5.append([])
    ws5.append(["人工一级 -> 规则一级", "行数"])
    for (t1, p1), c in bad.most_common(20):
        ws5.append(["%s -> %s" % (t1, p1), c])

    wb.save(OUT_XLSX)
    print("已写 XLSX:", OUT_XLSX)
    print("回测：一级一致 %d/%d (%.1f%%)，二级一致 %d/%d (%.1f%%)" % (
        h1, nl, 100.0 * h1 / nl, h2, nl, 100.0 * h2 / nl))


if __name__ == "__main__":
    main()
