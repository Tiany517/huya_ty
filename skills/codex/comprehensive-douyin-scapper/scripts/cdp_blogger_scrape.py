# -*- coding: utf-8 -*-
"""CDP 抓取单个博主全部视频点赞排名"""
import requests, json, time, sys, os, re
from urllib.parse import quote

CDP = "http://localhost:3456"

def _open(url, timeout=30):
    r = requests.get(f"{CDP}/new?url={url}", timeout=timeout)
    return r.json().get("targetId", "")

def _eval(tid, js, timeout=45):
    r = requests.post(f"{CDP}/eval?target={tid}", data=js, timeout=timeout)
    return r.json().get("value", "")

def _close(tid):
    try: requests.get(f"{CDP}/close?target={tid}", timeout=10)
    except: pass

# Step 1: search for blogger
keyword = "三只羊网络"
print(f"Searching: {keyword}")
tid = _open(f"https://www.douyin.com/search/{quote(keyword)}?type=user")
time.sleep(5)

api = "https://www.douyin.com/aweme/v1/web/discover/search/?device_platform=webapp&aid=6383&channel=channel_pc_web&search_channel=aweme_user_web&keyword=%E4%B8%89%E5%8F%AA%E7%BE%8A%E7%BD%91%E7%BB%9C&search_source=normal_search&query_correct_type=1&is_filter_search=0&offset=0&count=15&pc_client_type=1&version_code=170400&version_name=17.4.0&cookie_enabled=true&screen_width=1920&screen_height=1080"

js = '(async function(){try{var r=await fetch("' + api + '",{credentials:"include",signal:AbortSignal.timeout(15000)});var d=await r.json();var list=(d.user_list||[]).map(function(u){var i=u.user_info||{};return{name:i.nickname||"",fans:i.follower_count||0,uid:i.sec_uid||""};});return JSON.stringify({list:list});}catch(e){return JSON.stringify({err:e.message});}})()'

val = _eval(tid, js, timeout=120)
data = json.loads(val) if val else {}
users = data.get("list", [])
if not users:
    print("No search results found")
    _close(tid)
    sys.exit(1)

# Find best match
best = None
for u in users:
    if keyword in u.get("name", "") or u.get("name", "") == keyword:
        best = u
        break
if not best:
    best = users[0]  # fallback to first

name = best["name"]
uid = best["uid"]
fans = best["fans"]
profile_url = f"https://www.douyin.com/user/{uid}"
print(f"Found: {name} ({fans} fans)")
print(f"URL: {profile_url}")
_close(tid)

# Step 2: scroll blogger profile to extract all videos
print("\nOpening profile page...")
tid2 = _open(profile_url)
time.sleep(5)

# Scroll to load all videos
prev_sh = 0
stale = 0
rounds = 0
while rounds < 100:
    rounds += 1
    scroll_js = """
(function(){
  var rc = document.querySelector('.route-scroll-container');
  if (!rc) return JSON.stringify({sh:0});
  rc.scrollTop = rc.scrollHeight;
  rc.dispatchEvent(new WheelEvent('wheel', {deltaY: 800, deltaMode: 0, bubbles: true, cancelable: true}));
  rc.dispatchEvent(new Event('scroll', {bubbles: true}));
  return JSON.stringify({sh: rc.scrollHeight});
})()
"""
    val = _eval(tid2, scroll_js, timeout=30)
    try:
        info = json.loads(val) if val else {"sh": 0}
        sh = info.get("sh", 0)
    except:
        sh = 0

    print(f"  scroll round {rounds}: scrollHeight={sh}")

    if sh == prev_sh:
        stale += 1
        if stale >= 8:
            print("  No more content, stopping scroll")
            break
    else:
        stale = 0
        prev_sh = sh

    time.sleep(3)

# Step 3: extract video data
print("\nExtracting videos...")
extract_js = """
(function(){
  var videos = [];
  var links = document.querySelectorAll('a[href*="/video/"]');
  links.forEach(function(a){
    var href = a.getAttribute('href') || '';
    var text = a.innerText || '';
    var match = href.match(/\/video\/(\d+)/);
    var vid = match ? match[1] : '';
    if (!vid) return;
    // Check if already added
    if (videos.some(function(v){return v.vid===vid})) return;
    videos.push({vid: vid, text: text, href: href});
  });
  // Also get follower count
  var fansEl = document.querySelector('[data-e2e="followers-count"]');
  var fansText = fansEl ? fansEl.innerText : '';
  return JSON.stringify({videos: videos, fansText: fansText, total: videos.length});
})()
"""
val = _eval(tid2, extract_js, timeout=30)
data = json.loads(val) if val else {}
videos_raw = data.get("videos", [])
fans_text = data.get("fansText", str(fans) + " fans")

print(f"Found {len(videos_raw)} video cards")
if not videos_raw:
    _close(tid2)
    print("No videos found - may need login or page didn't load properly")
    sys.exit(1)

# Parse videos: split text into likes + title
parsed = []
for v in videos_raw:
    lines = v["text"].strip().split("\n")
    like_str = ""
    title_parts = []
    found_like = False
    for line in lines:
        line = line.strip()
        if not line:
            continue
        if not found_like and re.match(r'^[\d.]+[万亿w]?$', line):
            like_str = line
            found_like = True
            continue
        if found_like:
            title_parts.append(line)
    title = " ".join(title_parts) if title_parts else v["text"][:50]
    parsed.append({
        "title": title,
        "likes": like_str,
        "url": "https://www.douyin.com" + v["href"],
    })

# Sort by likes (parse numeric)
def parse_likes(s):
    if not s: return 0
    s = s.strip()
    try:
        if "亿" in s: return int(float(s.replace("亿","").replace("w","")) * 100000000)
        if "万" in s or "w" in s: return int(float(s.replace("万","").replace("w","")) * 10000)
        return int(float(s))
    except:
        return 0

parsed.sort(key=lambda x: parse_likes(x["likes"]), reverse=True)

# Step 4: save as Excel
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill, Border, Side
from datetime import date

wb = Workbook()
ws = wb.active
ws.title = "视频点赞排名"

header_fill = PatternFill(start_color="4472C4", end_color="4472C4", fill_type="solid")
header_font = Font(name="微软雅黑", bold=True, color="FFFFFF", size=11)
thin_border = Border(left=Side(style="thin"), right=Side(style="thin"),
                      top=Side(style="thin"), bottom=Side(style="thin"))
data_font = Font(name="微软雅黑", size=10)

headers = ["博主名称", "博主粉丝数", "视频排名", "视频标题", "点赞数", "视频链接"]
widths = [18, 14, 8, 45, 12, 52]
for i,(h,w) in enumerate(zip(headers,widths),1):
    c = ws.cell(row=1, column=i, value=h)
    c.font = header_font; c.fill = header_fill
    c.alignment = Alignment(horizontal="center", vertical="center")
    c.border = thin_border
    ws.column_dimensions[c.column_letter].width = w
ws.row_dimensions[1].height = 28

for rank, v in enumerate(parsed, 1):
    vals = [name, fans_text, rank, v["title"], v["likes"] or "—", v["url"]]
    for col, val in enumerate(vals, 1):
        c = ws.cell(row=rank+1, column=col, value=val)
        c.font = data_font; c.border = thin_border
        c.alignment = Alignment(horizontal="center" if col != 4 else "left", vertical="center")
    ws.row_dimensions[rank+1].height = 22

ws.freeze_panes = "A2"

out_dir = r"C:\Users\tiany\.claude\skills\comprehensive-douyin-scapper\data\output"
os.makedirs(out_dir, exist_ok=True)
safe_name = re.sub(r'[<>:"/\\|?*]', '_', name)
out_path = os.path.join(out_dir, f"{date.today()}_{safe_name}_全量视频点赞排名.xlsx")
wb.save(out_path)
print(f"\nDone! {len(parsed)} videos -> {out_path}")

_close(tid2)
