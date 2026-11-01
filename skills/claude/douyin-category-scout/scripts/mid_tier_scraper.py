# -*- coding: utf-8 -*-
"""多关键词搜索电商腰部主播: 粉丝 10万-300万"""
import requests, json, time, os, sys
from urllib.parse import quote

CDP = "http://localhost:3456"
KEYWORDS = [
    "带货", "好物推荐", "种草", "测评", "穿搭",
    "美妆", "零食", "家居好物", "服装", "直播带货",
]

MIN_FANS = 100000
MAX_FANS = 3000000

def fmt(n):
    if n >= 100000000: return f"{n/100000000:.1f}亿"
    if n >= 10000: return f"{n/10000:.1f}万"
    return str(n)

print("=== 电商腰部主播搜索 ===")
print(f"粉丝范围: {MIN_FANS//10000}万 - {MAX_FANS//10000}万")
print(f"关键词: {KEYWORDS}\n")

# Open one tab for all searches (reuse cookie context)
first = quote(KEYWORDS[0])
r = requests.get(f"{CDP}/new?url=https://www.douyin.com/search/{first}?type=user", timeout=30)
tid = r.json().get("targetId", "")
print(f"Tab: {tid}")
time.sleep(5)

all_items = []
seen = set()

for kw in KEYWORDS:
    encoded = quote(kw)
    # Switch to this search
    nav_js = f"window.location.href = 'https://www.douyin.com/search/{encoded}?type=user'; return 'ok';"
    r2 = requests.post(f"{CDP}/eval?target={tid}", data=nav_js, timeout=15)
    time.sleep(4)

    kw_items = []
    cursor = 0
    for page in range(1, 12):  # ~180 results per keyword
        api = (
            "https://www.douyin.com/aweme/v1/web/discover/search/"
            "?device_platform=webapp&aid=6383&channel=channel_pc_web"
            "&search_channel=aweme_user_web"
            f"&keyword={encoded}"
            "&search_source=normal_search&query_correct_type=1&is_filter_search=0"
            "&count=15&pc_client_type=1&version_code=170400&version_name=17.4.0"
            "&cookie_enabled=true&screen_width=1920&screen_height=1080"
            f"&offset={cursor}"
        )

        js = (
            '(async function(){'
            '  try {'
            f'    var r = await fetch("{api}", {{credentials:"include",signal:AbortSignal.timeout(15000)}});'
            '    var d = await r.json();'
            '    var list = (d.user_list||[]).map(function(u){'
            '      var i = u.user_info||{};'
            '      return {n:i.nickname||"",f:i.follower_count||0,l:i.total_favorited||0,u:i.sec_uid||""};'
            '    });'
            '    return JSON.stringify({ok:true,users:list,cursor:d.cursor,has_more:d.has_more});'
            '  } catch(e) { return JSON.stringify({ok:false,err:e.message}); }'
            '})()'
        )

        data = requests.post(f"{CDP}/eval?target={tid}", data=js, timeout=45)
        val = data.json().get("value", "")
        try: resp = json.loads(val) if val else {}
        except: break

        if not resp.get("ok"):
            break

        users = resp.get("users", [])
        if not users:
            break

        # Check if we're below threshold zone
        min_f = min(u.get("f", 0) for u in users)
        max_f = max(u.get("f", 0) for u in users)

        new_local = 0
        for u in users:
            uid = u.get("u", "")
            fans = u.get("f", 0)
            if uid and uid not in seen:
                seen.add(uid)
                item = {"name": u.get("n", ""), "fans": fans,
                        "likes": u.get("l", 0), "uid": uid, "kw": kw}
                all_items.append(item)
                kw_items.append(item)
                new_local += 1

        cursor = resp.get("cursor", 0)
        has_more = resp.get("has_more", False)

        if max_f < MIN_FANS:
            break  # all below threshold
        if not has_more:
            break

        time.sleep(1.5)

    in_range_kw = [x for x in kw_items if MIN_FANS <= x["fans"] <= MAX_FANS]
    print(f"  [{kw}] found {len(kw_items)} new, {len(in_range_kw)} in range (total all: {len(all_items)})")

r2 = requests.get(f"{CDP}/close?target={tid}", timeout=10)

# Filter + dedup
mid_tier = []
seen_out = set()
for b in all_items:
    uid = b["uid"]
    if uid in seen_out:
        continue
    if MIN_FANS <= b["fans"] <= MAX_FANS:
        seen_out.add(uid)
        mid_tier.append(b)

mid_tier.sort(key=lambda x: x["fans"], reverse=True)

print(f"\n=== 结果: {len(mid_tier)} 位腰部主播 ({MIN_FANS//10000}万-{MAX_FANS//10000}万) ===\n")
for i, b in enumerate(mid_tier[:60], 1):
    url = f"https://www.douyin.com/user/{b['uid']}"
    print(f"{i:2d}. {b['name']:24s}  粉丝:{fmt(b['fans']):>8s}  获赞:{fmt(b['likes']):>8s}  来源:{b['kw']}")

# Save Excel
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill, Border, Side
from datetime import date

wb = Workbook()
ws = wb.active
ws.title = "电商腰部主播10w-300w"

hf = PatternFill(start_color="4472C4", end_color="4472C4", fill_type="solid")
hfont = Font(name="微软雅黑", bold=True, color="FFFFFF", size=11)
tb = Border(left=Side(style="thin"), right=Side(style="thin"),
            top=Side(style="thin"), bottom=Side(style="thin"))
df = Font(name="微软雅黑", size=10)

headers = ["序号", "博主名称", "粉丝数", "获赞数", "搜索来源", "博主主页链接"]
widths = [6, 24, 14, 14, 12, 52]
for i, (h, w) in enumerate(zip(headers, widths), 1):
    c = ws.cell(row=1, column=i, value=h)
    c.font = hfont; c.fill = hf; c.border = tb
    c.alignment = Alignment(horizontal="center", vertical="center")
    ws.column_dimensions[c.column_letter].width = w
ws.row_dimensions[1].height = 26

for i, b in enumerate(mid_tier, 1):
    vals = [i, b["name"], fmt(b["fans"]), fmt(b["likes"]), b["kw"],
            f"https://www.douyin.com/user/{b['uid']}"]
    for col, val in enumerate(vals, 1):
        c = ws.cell(row=i+1, column=col, value=val)
        c.font = df; c.border = tb
        c.alignment = Alignment(horizontal="center" if col != 2 else "left", vertical="center")
    ws.row_dimensions[i+1].height = 22

ws.freeze_panes = "A2"

out_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "output")
os.makedirs(out_dir, exist_ok=True)
out = os.path.join(out_dir, f"{date.today()}_电商腰部主播_10w-300w.xlsx")
wb.save(out)
print(f"\nSaved: {out} ({len(mid_tier)} bloggers)")
