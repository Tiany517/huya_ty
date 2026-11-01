"""
douyin-category-scout CLI

命令:
  scout   搜索类目关键词 → Top 100 博主 → Excel

文件位置: scripts/main.py
"""
import argparse
import asyncio
import json
import sys
import os
from pathlib import Path

# 添加 scripts 目录到路径（import 同级模块）
_scripts_dir = Path(__file__).parent
sys.path.insert(0, str(_scripts_dir))

from scraper import CategoryScraper
from excel_generator import generate_category_excel


def print_json(data: dict) -> None:
    """输出 JSON 到 stdout"""
    print(json.dumps(data, ensure_ascii=False, indent=2))


async def handle_scout(args):
    """处理 scout 命令：搜索 → 抓取 → 生成 Excel"""
    scraper = CategoryScraper()

    print(f"[scout] 搜索关键词: {args.keyword}", flush=True)

    # Step 1: 抓取搜索结果
    result = await scraper.scrape_category_search(
        keyword=args.keyword,
        max_results=args.max,
    )

    if "error" in result:
        print_json(result)
        return

    total = result.get("total_found", 0)
    top_count = len(result.get("top_100", []))
    print(f"[scout] 共找到 {total} 个博主, 取 Top {top_count}", flush=True)

    # Step 2: 生成 Excel
    output_dir = str(Path(__file__).parent.parent / "output")
    filepath = generate_category_excel(result, output_dir)

    # Step 3: 输出结果
    output = {
        "keyword": result.get("keyword", ""),
        "total_found": total,
        "top_count": top_count,
        "excel_path": filepath,
    }
    print_json(output)
    print(f"[完成] Excel 已生成: {filepath}", flush=True)
    print(f"[完成] 共 {top_count} 个博主", flush=True)


async def main():
    parser = argparse.ArgumentParser(description="抖音类目博主搜索工具")
    subparsers = parser.add_subparsers(dest="command", help="可用命令")

    # scout 命令
    scout_parser = subparsers.add_parser("scout", help="搜索类目关键词 → Top 100 博主 → 生成Excel")
    scout_parser.add_argument("keyword", help="搜索关键词，如\"搞笑幽默\"、\"短剧\"")
    scout_parser.add_argument("--max", type=int, default=100, help="最多获取博主数 (默认: 100)")

    args = parser.parse_args()

    if args.command == "scout":
        await handle_scout(args)
    else:
        parser.print_help()


if __name__ == "__main__":
    asyncio.run(main())
