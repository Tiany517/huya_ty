"""批量采集抖音博主信息 - 使用 DouK-Downloader 的 Params 类

Params 是项目的独立测试/签名类，不需要复杂的 Parameter/Settings 初始化。
直接用它生成 XBogus/aBogus 签名参数，然后通过 httpx 调用抖音 API。
"""

import asyncio
import json
import os
import sys
import time

# 添加项目路径
PROJECT_ROOT = os.path.join(os.path.expanduser("~"), "TikTokDownloader")
sys.path.insert(0, PROJECT_ROOT)

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


async def collect_blogger_data():
    """使用 Params 类和项目内部 Search 接口采集数据"""
    from src.testers import Params
    from src.interface import Search, User
    from src.interface.account import Account

    # 初始化 Params（独立的，不需要完整项目初始化）
    params = Params()

    # 从 settings.json 读取 Cookie 并更新
    settings_path = os.path.join(PROJECT_ROOT, "Volume", "settings.json")
    try:
        with open(settings_path, "r", encoding="utf-8") as f:
            settings = json.load(f)
        cookie = settings.get("cookie", "")
        if cookie:
            # 更新 Params 的 Cookie
            params.cookie_str = cookie
            params.headers["Cookie"] = cookie
            print(f"Cookie 已加载 ({len(cookie)} 字符)")
        else:
            print("警告: Cookie 未配置！")
    except Exception as e:
        print(f"读取 Cookie 失败: {e}")

    results = []

    for name in BLOGGER_NAMES:
        print(f"\n正在搜索: {name}")

        try:
            # 1. 搜索用户
            search_obj = Search(
                params,
                cookie=cookie,
                keyword=name,
                channel=2,  # 用户搜索
                pages=1,
            )
            search_data = await search_obj.run()

            if not search_data or not any(search_data):
                print(f"  -> 搜索 '{name}' 无结果")
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
                await asyncio.sleep(2)
                continue

            # 2. 找到最匹配的用户
            user_list = search_data[0] if isinstance(search_data, list) and len(search_data) > 0 else []
            matched = None

            for item in user_list:
                if isinstance(item, dict):
                    user_info = item.get("user_info", {})
                    nickname = user_info.get("nickname", "")
                    # 模糊匹配
                    if nickname == name or \
                       nickname.replace(" ", "").replace("​", "") == name.replace(" ", "").replace("​", "") or \
                       name in nickname or nickname in name:
                        matched = user_info
                        break

            if not matched and user_list:
                matched = user_list[0].get("user_info", {})

            if not matched:
                print(f"  -> '{name}' 未找到匹配用户")
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
                await asyncio.sleep(2)
                continue

            sec_uid = matched.get("sec_uid", "")
            nickname = matched.get("nickname", name)
            followers = matched.get("follower_count", 0)
            mcn = matched.get("mcn_name", "")
            aweme_count = matched.get("aweme_count", 0)

            # 3. 获取用户详情（补充 MCN 等信息）
            try:
                user_obj = User(
                    params,
                    cookie=cookie,
                    sec_user_id=sec_uid,
                )
                user_data = await user_obj.run()
                if user_data and isinstance(user_data, dict):
                    mcn_name = user_data.get("mcn_name", "")
                    if mcn_name:
                        mcn = mcn_name
                    follower_count = user_data.get("follower_count", 0)
                    if follower_count:
                        followers = follower_count
                    aweme_count_detail = user_data.get("aweme_count", 0)
                    if aweme_count_detail:
                        aweme_count = aweme_count_detail
            except Exception as e:
                print(f"  用户详情获取异常: {e}")

            # 4. 获取视频数据找最高点赞/播放
            max_likes = 0
            max_plays = 0

            try:
                account_obj = Account(
                    params,
                    cookie=cookie,
                    sec_user_id=sec_uid,
                    tab="post",
                    pages=5,
                )
                video_data = await account_obj.run()

                if video_data:
                    # video_data 是列表，遍历所有视频
                    videos = video_data if isinstance(video_data, list) else []
                    for v_page in videos:
                        page_items = v_page if isinstance(v_page, list) else [v_page] if v_page else []
                        for v in page_items:
                            if isinstance(v, dict):
                                stats = v.get("statistics", {})
                                likes = stats.get("digg_count", 0) or 0
                                plays = stats.get("play_count", 0) or 0
                                if likes > max_likes:
                                    max_likes = likes
                                if plays > max_plays:
                                    max_plays = plays
            except Exception as e:
                print(f"  视频数据获取异常: {e}")

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

        except Exception as e:
            print(f"  -> '{name}' 处理异常: {e}")
            results.append({
                "search_name": name,
                "nickname": "",
                "mcn": f"错误",
                "followers": "",
                "video_count": "",
                "max_likes": "",
                "max_plays": "",
                "profile_url": "",
            })

        await asyncio.sleep(3)

    # 清理
    await params.client.aclose()
    return results


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


async def main():
    print("=" * 50)
    print("抖音博主数据批量采集工具")
    print("=" * 50)

    results = await collect_blogger_data()

    desktop = os.path.join(os.path.expanduser("~"), "Desktop")
    output_path = os.path.join(desktop, "抖音博主数据.xlsx")
    save_to_excel(results, output_path)

    success_count = sum(1 for r in results if r.get("followers") and str(r.get("followers")) not in ("", "搜索无结果", "未找到"))
    print(f"\n采集完成！共处理 {len(results)} 位博主")
    print(f"成功: {success_count} 位")
    print(f"失败: {len(results) - success_count} 位")


if __name__ == "__main__":
    asyncio.run(main())
