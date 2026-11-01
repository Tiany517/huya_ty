"""批量采集抖音博主信息 - 使用 DouK-Downloader 内部接口

通过直接调用 DouK-Downloader 项目的内部模块进行搜索和数据采集，
解决了 XBogus/aBogus 签名和中文编码问题。
"""

import asyncio
import json
import os
import sys
import time
import traceback

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
    """使用 DouK-Downloader 内部模块批量采集博主数据"""

    from src.custom import PROJECT_ROOT
    from src.application import TikTokDownloader

    # 直接使用项目的初始化逻辑
    app = TikTokDownloader()
    await app.database.__aenter__()
    await app.read_config()

    # 初始化参数
    await app.check_settings(False)

    # 确保接受了免责声明（设置数据库）
    await app.database.update_config_data("Disclaimer", 1)

    # 重新初始化参数
    await app.check_settings(True)

    parameter = app.parameter
    console = app.console

    from src.interface import Search, User
    from src.interface.account import Account

    # 加载 Cookie
    cookie_module = Cookie(settings, console)

    # 初始化数据库
    database = Database()
    await database.__aenter__()

    # 创建 Parameter
    parameter = Parameter(
        settings,
        cookie_module,
        logger=logger,
        console=console,
        **settings.read(),
    )

    results = []

    for name in BLOGGER_NAMES:
        print(f"正在搜索: {name}")

        try:
            # 1. 搜索用户
            search_obj = Search(
                parameter,
                cookie=parameter.cookie,
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
            user_list = search_data[0] if search_data else []
            matched = None

            for item in user_list:
                user_info = item.get("user_info", {})
                nickname = user_info.get("nickname", "")
                if nickname == name or nickname.replace(" ", "") == name.replace(" ", "").lower():
                    matched = user_info
                    break

            if not matched and user_list:
                # 取第一个结果
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

            # 3. 获取详细用户数据
            try:
                user_obj = User(
                    parameter,
                    cookie=parameter.cookie,
                    sec_user_id=sec_uid,
                )
                user_data = await user_obj.run()
                if user_data:
                    if user_data.get("mcn_name"):
                        mcn = user_data["mcn_name"]
                    if user_data.get("follower_count"):
                        followers = user_data["follower_count"]
                    if user_data.get("aweme_count"):
                        aweme_count = user_data["aweme_count"]
            except Exception:
                pass

            # 4. 获取视频数据来找最高点赞/播放
            max_likes = 0
            max_plays = 0

            try:
                account_obj = Account(
                    parameter,
                    cookie=parameter.cookie,
                    sec_user_id=sec_uid,
                    tab="post",
                    pages=5,  # 获取前5页（约100个视频）
                )
                video_data = await account_obj.run()

                if video_data and any(video_data):
                    all_videos = video_data[0] if isinstance(video_data, list) else video_data
                    for v in all_videos if isinstance(all_videos, list) else []:
                        stats = v.get("statistics", {})
                        likes = stats.get("digg_count", 0) or 0
                        plays = stats.get("play_count", 0) or 0
                        if likes > max_likes:
                            max_likes = likes
                        if plays > max_plays:
                            max_plays = plays
            except Exception:
                pass

            # 构造主页链接
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
            traceback.print_exc()
            results.append({
                "search_name": name,
                "nickname": "",
                "mcn": f"错误: {str(e)[:30]}",
                "followers": "",
                "video_count": "",
                "max_likes": "",
                "max_plays": "",
                "profile_url": "",
            })

        await asyncio.sleep(3)  # 避免请求过快

    await database.__aexit__(None, None, None)
    await parameter.close_client()
    # 关闭 app 的周期任务
    app.close()
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
    results = await collect_blogger_data()

    desktop = os.path.join(os.path.expanduser("~"), "Desktop")
    output_path = os.path.join(desktop, "抖音博主数据.xlsx")
    save_to_excel(results, output_path)

    success_count = sum(1 for r in results if r.get("followers") and r.get("followers") != "")
    print(f"\n采集完成！共处理 {len(results)} 位博主")
    print(f"成功: {success_count} 位")


if __name__ == "__main__":
    asyncio.run(main())
