"""
抖音 CLI — 合并 v1 + v2

命令：
  auth          扫码登录并保存 Cookie
  check-auth    验证 Cookie 是否有效
  blogger       抓取博主主页 Top N 高赞视频
  video         抓取单个视频
  comments      深度抓取评论区

文件位置: cli/main.py
"""

import argparse
import asyncio
import json
import sys
from pathlib import Path

# 添加项目根目录到路径
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))

from cli.cookie_manager import CookieManager
from cli.auth import AuthManager
from cli.scraper import DouyinScraper


def print_json(data: dict) -> None:
    """输出 JSON 到 stdout"""
    print(json.dumps(data, ensure_ascii=False, indent=2))


async def handle_auth(args):
    """处理登录命令"""
    cookie_manager = CookieManager()
    auth = AuthManager(cookie_manager)
    result = await auth.login()
    print_json(result)


async def handle_check_auth(args):
    """处理验证 Cookie 命令"""
    cookie_manager = CookieManager()

    if not cookie_manager.has_cookie():
        print_json({"error": "COOKIE_NOT_FOUND", "message": "Cookie 不存在，请先运行 auth 登录"})
        return

    from playwright.async_api import async_playwright
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        cookie = cookie_manager.load_cookie()
        context = await browser.new_context(storage_state=cookie)
        result = await cookie_manager.validate_cookie(context)
        await context.close()
        await browser.close()

    print_json(result)


async def handle_blogger(args):
    """处理博主抓取命令"""
    cookie_manager = CookieManager()
    scraper = DouyinScraper(cookie_manager)
    result = await scraper.scrape_blogger(args.url, top_n=args.top)
    print_json(result)


async def handle_video(args):
    """处理视频抓取命令"""
    cookie_manager = CookieManager()
    scraper = DouyinScraper(cookie_manager)
    result = await scraper.scrape_video(args.url)
    print_json(result)


async def handle_comments(args):
    """
    处理评论区深度抓取命令

    用法:
      python cli/main.py comments --url https://www.douyin.com/video/xxx
      python cli/main.py comments --urls https://... https://... --max 20 --scrolls 3
    """
    cookie_manager = CookieManager()
    scraper = DouyinScraper(cookie_manager)

    if args.url:
        # 单个视频
        result = await scraper.scrape_video_comments(
            video_url=args.url,
            max_comments=args.max,
            scroll_count=args.scrolls,
        )
        print_json(result)
    elif args.urls:
        # 批量视频
        results = await scraper.scrape_blogger_comments_batch(
            video_urls=args.urls,
            max_comments_per_video=args.max,
            scroll_count=args.scrolls,
        )
        print_json({"videos": results, "total": len(results)})
    else:
        print("错误: 请提供 --url 或 --urls 参数", file=sys.stderr)
        sys.exit(1)


async def main():
    parser = argparse.ArgumentParser(description="抖音 Playwright 数据采集工具（含评论区深度抓取）")
    subparsers = parser.add_subparsers(dest="command", help="可用命令")

    # auth 命令
    subparsers.add_parser("auth", help="扫码登录并保存 Cookie")

    # check-auth 命令
    subparsers.add_parser("check-auth", help="验证 Cookie 是否有效")

    # blogger 命令
    blogger_parser = subparsers.add_parser("blogger", help="抓取博主主页 Top N 高赞视频")
    blogger_parser.add_argument("url", help="博主主页 URL")
    blogger_parser.add_argument("--top", type=int, default=10, help="取前 N 个高赞视频 (默认: 10)")

    # video 命令
    video_parser = subparsers.add_parser("video", help="抓取单个视频")
    video_parser.add_argument("url", help="视频 URL")

    # comments 命令
    comments_parser = subparsers.add_parser("comments", help="深度抓取评论区")
    comments_group = comments_parser.add_mutually_exclusive_group(required=True)
    comments_group.add_argument("--url", help="单个视频 URL")
    comments_group.add_argument("--urls", nargs="+", help="多个视频 URL（批量）")
    comments_parser.add_argument("--max", type=int, default=20, help="每个视频最多抓取评论数 (默认: 20)")
    comments_parser.add_argument("--scrolls", type=int, default=3, help="评论区滚动次数 (默认: 3)")

    args = parser.parse_args()

    if args.command == "auth":
        await handle_auth(args)
    elif args.command == "check-auth":
        await handle_check_auth(args)
    elif args.command == "blogger":
        await handle_blogger(args)
    elif args.command == "video":
        await handle_video(args)
    elif args.command == "comments":
        await handle_comments(args)
    else:
        parser.print_help()


if __name__ == "__main__":
    asyncio.run(main())
