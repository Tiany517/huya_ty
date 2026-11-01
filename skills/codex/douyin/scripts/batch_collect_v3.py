"""启动 DouK-Downloader API 服务并批量采集博主数据

策略：
1. 用 Python subprocess 启动 API 服务（通过 stdin 输入菜单选项）
2. 等待服务启动完成
3. 用 httpx 调用 API 接口批量采集数据
4. 关闭服务
"""

import json
import os
import subprocess
import sys
import time
import traceback

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

API_BASE = "http://127.0.0.1:5555"
PROJECT_ROOT = os.path.join(os.path.expanduser("~"), "TikTokDownloader")
SETTINGS_PATH = os.path.join(PROJECT_ROOT, "Volume", "settings.json")


def load_cookie():
    """从 settings.json 加载 Cookie"""
    try:
        with open(SETTINGS_PATH, "r", encoding="utf-8") as f:
            settings = json.load(f)
        return settings.get("cookie", "")
    except Exception:
        return ""


def start_api_server():
    """启动 DouK-Downloader API 服务

    通过 stdin 自动选择菜单选项：
    1 -> 中文
    8 -> Web API 模式
    """
    print("正在启动 DouK-Downloader API 服务...")

    # 自动输入菜单选项：选择中文(1)，然后选择 Web API 模式(8)
    proc = subprocess.Popen(
        [sys.executable, "main.py"],
        cwd=PROJECT_ROOT,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        encoding="utf-8",
        bufsize=1,
    )

    # 发送菜单输入
    inputs = "1\n8\n"  # 选择中文 -> 选择 Web API 模式
    proc.stdin.write(inputs)
    proc.stdin.flush()

    # 等待服务启动
    print("等待服务启动...")
    max_wait = 30
    for i in range(max_wait):
        time.sleep(1)
        try:
            resp = httpx.get(f"{API_BASE}/", timeout=3, follow_redirects=False)
            if resp.status_code in (200, 307):
                print("服务已启动！")
                return proc
        except Exception:
            pass
        if i % 5 == 0:
            print(f"  等待中... ({i}/{max_wait}s)")

    print("服务启动超时")
    proc.kill()
    return None


def search_user(client: httpx.Client, keyword: str, cookie: str) -> list:
    """通过 API 搜索抖音用户"""
    try:
        resp = client.post(
            f"{API_BASE}/douyin/search/user",
            json={
                "keyword": keyword,
                "pages": 1,
                "cookie": cookie,
                "source": True,  # 返回原始数据
            },
            timeout=30,
        )
        data = resp.json()
        if data.get("message") and "成功" in data.get("message", ""):
            return data.get("data", [])
        else:
            print(f"  搜索API返回: {data.get('message', '未知错误')}")
            return []
    except Exception as e:
        print(f"  搜索请求失败: {e}")
        return []


def get_user_detail(client: httpx.Client, sec_user_id: str, cookie: str) -> dict:
    """通过 API 获取用户详情"""
    try:
        resp = client.post(
            f"{API_BASE}/douyin/account",
            json={
                "sec_user_id": sec_user_id,
                "tab": "post",
                "pages": 1,
                "cookie": cookie,
                "source": True,
            },
            timeout=30,
        )
        data = resp.json()
        if data.get("message") and "成功" in data.get("message", ""):
            return data.get("data", {})
        return {}
    except Exception as e:
        print(f"  获取详情失败: {e}")
        return {}


def save_to_excel(results: list, output_path: str):
    """保存结果到 Excel"""
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "抖音博主数据"

    headers = [
        "搜索名称", "抖音昵称", "MCN机构", "粉丝数",
        "发布视频数", "最高点赞量", "最高播放量", "抖音主页链接",
    ]
    ws.append(headers)

    from openpyxl.styles import Font, Alignment, PatternFill
    header_font = Font(bold=True, size=12, color="FFFFFF")
    header_fill = PatternFill(start_color="4472C4", end_color="4472C4", fill_type="solid")
    for col in range(1, len(headers) + 1):
        cell = ws.cell(row=1, column=col)
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = Alignment(horizontal="center", vertical="center")

    for r in results:
        ws.append([
            r.get("search_name", ""),
            r.get("nickname", ""),
            r.get("mcn", ""),
            r.get("followers", ""),
            r.get("video_count", ""),
            r.get("max_likes", ""),
            r.get("max_plays", ""),
            r.get("profile_url", ""),
        ])

    col_widths = [12, 15, 20, 15, 12, 15, 15, 45]
    for i, w in enumerate(col_widths, 1):
        ws.column_dimensions[openpyxl.utils.get_column_letter(i)].width = w

    wb.save(output_path)
    print(f"\nExcel 已保存到: {output_path}")


def main():
    cookie = load_cookie()
    print(f"Cookie 长度: {len(cookie)} 字符")

    # 启动 API 服务
    proc = start_api_server()
    if not proc:
        print("无法启动 API 服务，退出")
        return

    try:
        client = httpx.Client(timeout=30)
        results = []

        for name in BLOGGER_NAMES:
            print(f"\n正在搜索: {name}")

            # 1. 搜索用户
            search_data = search_user(client, name, cookie)
            if not search_data:
                results.append({
                    "search_name": name,
                    "nickname": "",
                    "mcn": "搜索无结果",
                    "followers": "",
                    "video_count": "",
                    "max_likes": "",
                    "max_plays": "",
                    "profile_url": "",
                })
                time.sleep(2)
                continue

            # 2. 找到最匹配的用户
            matched = None
            for item in search_data:
                user_info = item.get("user_info", {})
                nickname = user_info.get("nickname", "")
                if nickname == name or nickname.replace(" ", "").lower() == name.replace(" ", "").lower():
                    matched = user_info
                    break

            if not matched and search_data:
                matched = search_data[0].get("user_info", {})

            if not matched:
                results.append({
                    "search_name": name,
                    "nickname": "",
                    "mcn": "未找到",
                    "followers": "",
                    "video_count": "",
                    "max_likes": "",
                    "max_plays": "",
                    "profile_url": "",
                })
                time.sleep(2)
                continue

            sec_uid = matched.get("sec_uid", "")
            nickname = matched.get("nickname", name)
            followers = matched.get("follower_count", 0)
            mcn = matched.get("mcn_name", "")
            aweme_count = matched.get("aweme_count", 0)

            # 3. 获取视频统计（前5页）
            max_likes = 0
            max_plays = 0

            detail = get_user_detail(client, sec_uid, cookie)
            if detail:
                # 从视频列表中找最高点赞/播放
                if isinstance(detail, list):
                    for v in detail:
                        stats = v.get("statistics", {})
                        likes = stats.get("digg_count", 0) or 0
                        plays = stats.get("play_count", 0) or 0
                        if likes > max_likes:
                            max_likes = likes
                        if plays > max_plays:
                            max_plays = plays
                elif isinstance(detail, dict):
                    stats = detail.get("statistics", {})
                    likes = stats.get("digg_count", 0) or 0
                    plays = stats.get("play_count", 0) or 0
                    max_likes = likes
                    max_plays = plays

            profile_url = f"https://www.douyin.com/user/{sec_uid}" if sec_uid else ""

            results.append({
                "search_name": name,
                "nickname": nickname,
                "mcn": mcn or "未知",
                "followers": followers,
                "video_count": aweme_count,
                "max_likes": max_likes,
                "max_plays": max_plays,
                "profile_url": profile_url,
            })

            print(f"  -> {nickname} | 粉丝: {followers} | MCN: {mcn or '未知'} | 视频: {aweme_count}")

            time.sleep(3)

        client.close()

        # 保存 Excel
        desktop = os.path.join(os.path.expanduser("~"), "Desktop")
        output_path = os.path.join(desktop, "抖音博主数据.xlsx")
        save_to_excel(results, output_path)

        success_count = sum(1 for r in results if r.get("followers") not in ("", "搜索无结果", "未找到"))
        print(f"\n采集完成！共处理 {len(results)} 位博主")
        print(f"成功: {success_count} 位")
        print(f"失败: {len(results) - success_count} 位")

    finally:
        # 关闭服务
        print("\n正在关闭 API 服务...")
        proc.kill()
        proc.wait()
        print("服务已关闭")


if __name__ == "__main__":
    main()
