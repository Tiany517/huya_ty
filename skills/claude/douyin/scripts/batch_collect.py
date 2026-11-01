"""批量采集抖音博主信息并导出 Excel

功能：搜索指定博主名称，获取 MCN机构、粉丝数、发布视频数等信息
输出：Excel 文件保存到桌面

注意：需要抖音 Cookie 才能正常搜索
"""

import asyncio
import json
import os
import sys
import time

import httpx
import openpyxl

# 博主名称列表（去重）
BLOGGER_NAMES = [
    "姜十七", "莫邪", "田小野", "多余和毛毛姐", "名侦探小宇",
    "邵雨轩", "拜托啦学妹", "papi酱",
    "白小白", "王靖雯不胖", "阿悠悠", "隔壁老樊",
    "麻辣德子", "腊月小九", "野食小哥",
    "祝晓晗", "刀小刀sama", "大掌柜夫妇",
    "芒果妈妈", "娱乐全明星", "毒舌电影",
    "楚淇", "蔡萝莉", "彭十六elf",
    "代古拉k", "张欣尧",
    "金毛路虎一家人", "尿尿是只猫", "会说话的刘二豆", "刘金毛蛋黄二豆",
    "一禅小和尚", "柠檬心理", "涂磊",
    "高雨田大魔王", "欧文浩", "黑脸V",
    "戴建业老师", "看鉴", "意公子",
    "房琪kiki", "冒险雷探长", "凯诺梦露夫妇",
    "刘畊宏", "周六野Zoey",
    "手工耿", "培学长手工",
]

# 读取 settings.json 获取 Cookie
SETTINGS_PATH = os.path.join(os.path.expanduser("~"), "TikTokDownloader", "Volume", "settings.json")


def load_cookie():
    """从 settings.json 加载 Cookie"""
    try:
        with open(SETTINGS_PATH, "r", encoding="utf-8") as f:
            settings = json.load(f)
        return settings.get("cookie", "")
    except Exception:
        return ""


def search_user_sync(client: httpx.Client, keyword: str, cookie: str) -> list:
    """同步搜索抖音用户"""
    api_url = "https://www.douyin.com/aweme/v1/web/discover/search/"
    params = {
        "search_channel": "aweme_user_web",
        "keyword": keyword,
        "search_source": "switch_tab",
        "query_correct_type": "1",
        "is_filter_search": "0",
        "offset": "0",
        "count": "10",
        "version_code": "170400",
        "version_name": "17.4.0",
        "device_platform": "webapp",
    }
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36",
        "Referer": f"https://www.douyin.com/root/search/{keyword}?type=user",
        "Cookie": cookie,
    }

    try:
        resp = client.get(api_url, params=params, headers=headers, timeout=15)
        data = resp.json()
        user_list = data.get("data", {}).get("user_list", [])
        return user_list
    except Exception as e:
        print(f"  搜索 '{keyword}' 失败: {e}")
        return []


def get_user_detail_sync(client: httpx.Client, sec_user_id: str, cookie: str) -> dict:
    """获取用户详细资料"""
    api_url = "https://www.douyin.com/aweme/v1/web/user/profile/other/"
    params = {
        "sec_user_id": sec_user_id,
        "publish_video_strategy_type": "2",
        "personal_center_strategy": "1",
        "version_code": "170400",
        "version_name": "17.4.0",
        "device_platform": "webapp",
    }
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36",
        "Referer": "https://www.douyin.com/",
        "Cookie": cookie,
    }

    try:
        resp = client.get(api_url, params=params, headers=headers, timeout=15)
        data = resp.json()
        user = data.get("user", {})
        return user
    except Exception as e:
        print(f"  获取用户详情失败: {e}")
        return {}


def get_account_videos_sync(client: httpx.Client, sec_user_id: str, cookie: str, max_pages: int = 3) -> dict:
    """获取账号作品列表，找出最高点赞和播放量"""
    api_url = "https://www.douyin.com/aweme/v1/web/aweme/post/"
    max_likes = 0
    max_plays = 0
    max_likes_desc = ""
    max_plays_desc = ""
    video_count = 0

    for page in range(max_pages):
        cursor = page * 20
        params = {
            "sec_user_id": sec_user_id,
            "count": "20",
            "max_cursor": str(cursor),
            "version_code": "170400",
            "version_name": "17.4.0",
            "device_platform": "webapp",
        }
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36",
            "Referer": "https://www.douyin.com/",
            "Cookie": cookie,
        }

        try:
            resp = client.get(api_url, params=params, headers=headers, timeout=15)
            data = resp.json()
            aweme_list = data.get("aweme_list", [])
            if not aweme_list:
                break

            video_count += len(aweme_list)

            for video in aweme_list:
                stats = video.get("statistics", {})
                likes = stats.get("digg_count", 0)
                plays = stats.get("play_count", 0)
                desc = video.get("desc", "")[:30]

                if likes > max_likes:
                    max_likes = likes
                    max_likes_desc = desc
                if plays > max_plays:
                    max_plays = plays
                    max_plays_desc = desc

            if not data.get("has_more", False):
                break

            time.sleep(0.5)  # 避免请求过快
        except Exception as e:
            print(f"  获取视频列表第{page+1}页失败: {e}")
            break

    return {
        "video_count": video_count,
        "max_likes": max_likes,
        "max_likes_desc": max_likes_desc,
        "max_plays": max_plays,
        "max_plays_desc": max_plays_desc,
    }


def save_to_excel(results: list, output_path: str):
    """保存结果到 Excel"""
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "抖音博主数据"

    # 表头
    headers = [
        "博主名称", "抖音昵称", "MCN机构", "粉丝数",
        "发布视频数", "最高点赞量", "最高点赞视频",
        "最高播放量", "最高播放视频", "抖音主页链接",
    ]
    ws.append(headers)

    # 设置表头样式
    from openpyxl.styles import Font, Alignment, PatternFill
    header_font = Font(bold=True, size=12)
    header_fill = PatternFill(start_color="4472C4", end_color="4472C4", fill_type="solid")
    header_font_white = Font(bold=True, size=12, color="FFFFFF")
    for col in range(1, len(headers) + 1):
        cell = ws.cell(row=1, column=col)
        cell.font = header_font_white
        cell.fill = header_fill
        cell.alignment = Alignment(horizontal="center", vertical="center")

    # 数据行
    for r in results:
        ws.append([
            r.get("search_name", ""),
            r.get("nickname", ""),
            r.get("mcn", ""),
            r.get("followers", ""),
            r.get("video_count", ""),
            r.get("max_likes", ""),
            r.get("max_likes_desc", ""),
            r.get("max_plays", ""),
            r.get("max_plays_desc", ""),
            r.get("profile_url", ""),
        ])

    # 设置列宽
    col_widths = [12, 15, 20, 15, 12, 15, 25, 15, 25, 45]
    for i, w in enumerate(col_widths, 1):
        ws.column_dimensions[openpyxl.utils.get_column_letter(i)].width = w

    wb.save(output_path)
    print(f"\nExcel 已保存到: {output_path}")


def main():
    cookie = load_cookie()
    if not cookie:
        print("警告: Cookie 未配置，搜索结果可能不完整！")
        print("请在 settings.json 中配置 cookie 字段")
        print("继续尝试使用无 Cookie 模式...\n")

    desktop = os.path.join(os.path.expanduser("~"), "Desktop")
    output_path = os.path.join(desktop, "抖音博主数据.xlsx")

    results = []
    client = httpx.Client(follow_redirects=True)

    for name in BLOGGER_NAMES:
        print(f"正在搜索: {name}")

        # 1. 搜索用户
        user_list = search_user_sync(client, name, cookie)
        if not user_list:
            results.append({
                "search_name": name,
                "nickname": "",
                "mcn": "",
                "followers": "搜索失败",
                "video_count": "",
                "max_likes": "",
                "max_likes_desc": "",
                "max_plays": "",
                "max_plays_desc": "",
                "profile_url": "",
            })
            time.sleep(1)
            continue

        # 2. 从搜索结果中找到最匹配的用户
        matched_user = None
        for item in user_list:
            user_info = item.get("user_info", {})
            nickname = user_info.get("nickname", "")
            # 精确匹配或最接近匹配
            if nickname == name or nickname.replace(" ", "") == name.replace(" ", ""):
                matched_user = user_info
                break

        if not matched_user and user_list:
            # 取搜索结果第一个
            matched_user = user_list[0].get("user_info", {})

        if not matched_user:
            results.append({
                "search_name": name,
                "nickname": "",
                "mcn": "",
                "followers": "未找到",
                "video_count": "",
                "max_likes": "",
                "max_likes_desc": "",
                "max_plays": "",
                "max_plays_desc": "",
                "profile_url": "",
            })
            time.sleep(1)
            continue

        sec_user_id = matched_user.get("sec_uid", "")
        nickname = matched_user.get("nickname", "")
        followers = matched_user.get("follower_count", "")
        mcn = matched_user.get("mcn_name", "")

        # 构造主页链接
        profile_url = f"https://www.douyin.com/user/{sec_user_id}" if sec_user_id else ""

        # 3. 获取用户详情（补充 MCN 信息）
        detail = get_user_detail_sync(client, sec_user_id, cookie)
        if detail:
            # 优先使用详情中的数据
            if detail.get("mcn_name"):
                mcn = detail["mcn_name"]
            if detail.get("follower_count"):
                followers = detail["follower_count"]
            if detail.get("aweme_count"):
                video_count = detail["aweme_count"]
            else:
                video_count = matched_user.get("aweme_count", "")

        # 4. 获取视频统计（最高点赞/播放）
        video_stats = get_account_videos_sync(client, sec_user_id, cookie, max_pages=5)
        if detail and detail.get("aweme_count"):
            video_count = detail["aweme_count"]
        else:
            video_count = video_stats["video_count"]

        results.append({
            "search_name": name,
            "nickname": nickname,
            "mcn": mcn or "未知",
            "followers": followers,
            "video_count": video_count,
            "max_likes": video_stats["max_likes"],
            "max_likes_desc": video_stats["max_likes_desc"],
            "max_plays": video_stats["max_plays"],
            "max_plays_desc": video_stats["max_plays_desc"],
            "profile_url": profile_url,
        })

        print(f"  -> {nickname} | 粉丝: {followers} | MCN: {mcn or '未知'}")

        time.sleep(2)  # 避免请求过快被封

    client.close()

    # 保存 Excel
    save_to_excel(results, output_path)

    print(f"\n采集完成！共处理 {len(results)} 位博主")
    print(f"成功: {sum(1 for r in results if r.get('followers') not in ('搜索失败', '未找到', ''))} 位")
    print(f"失败: {sum(1 for r in results if r.get('followers') in ('搜索失败', '未找到', ''))} 位")


if __name__ == "__main__":
    main()
