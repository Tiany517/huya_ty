"""
标准化 Excel 生成器 — 接收 JSON 文件，自动生成 3-Sheet Excel

用法:
  python scripts/generate_excel.py <json_file> [--output <output_path>]

输入 JSON 格式：
  {
    "blogger_name": "博主名",
    "blogger_id": "MS4wLjABAAAA...",
    "profile": { ... },          // 博主个人信息
    "total_videos": 156,
    "scrape_time": "2026-06-25T14:30:00",
    "top_videos": [ ... ],       // 视频列表
    "script_analysis": [ ... ]   // AI 脚本分析（可选，没有则只生成 2 个 Sheet）
  }

输出文件路径: data/output/YYYY-MM-DD_博主名_Top10视频分析.xlsx

文件位置: scripts/generate_excel.py
"""

import json
import sys
import os
from datetime import datetime
from pathlib import Path
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill, Border, Side

# 项目根目录
PROJECT_ROOT = Path(__file__).parent.parent
DEFAULT_OUTPUT_DIR = PROJECT_ROOT / "data" / "output"


def create_excel(data: dict, output_path: str = None) -> str:
    """
    从 JSON 数据创建 Excel 文件

    Args:
        data: 抓取结果的 JSON 数据（dict）
        output_path: 输出文件路径，默认为 data/output/YYYY-MM-DD_博主名_Top10视频分析.xlsx

    Returns:
        生成的 Excel 文件路径
    """
    blogger_name = data.get("blogger_name", "未知博主")
    scrape_time = data.get("scrape_time", datetime.now().isoformat())
    profile = data.get("profile", {})
    top_videos = data.get("top_videos", [])
    script_analysis = data.get("script_analysis", [])

    if not output_path:
        date_str = datetime.now().strftime("%Y-%m-%d")
        safe_name = blogger_name.replace("/", "_").replace("\\", "_").replace(":", "_")
        output_path = str(DEFAULT_OUTPUT_DIR / f"{date_str}_{safe_name}_Top10视频分析.xlsx")

    # 确保输出目录存在
    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    wb = Workbook()
    thin_border = Border(
        left=Side(style='thin'), right=Side(style='thin'),
        top=Side(style='thin'), bottom=Side(style='thin')
    )

    # ========== Sheet 1: 博主信息 ==========
    ws1 = wb.active
    ws1.title = "博主信息"

    ws1["A1"] = "抖音博主数据分析报告"
    ws1["A1"].font = Font(size=16, bold=True, color="FFFFFF")
    ws1["A1"].fill = PatternFill(start_color="1E90FF", end_color="1E90FF", fill_type="solid")
    ws1["A1"].alignment = Alignment(horizontal="center", vertical="center")
    ws1.merge_cells("A1:D1")
    ws1.row_dimensions[1].height = 30

    # 从 profile 和 data 中提取博主信息
    info_items = [
        ("博主名称", profile.get("blogger_name", blogger_name)),
        ("抖音号", profile.get("douyin_id", "—")),
        ("粉丝数", profile.get("fans_count", "—")),
        ("获赞数", profile.get("total_likes", "—")),
        ("作品数", profile.get("total_videos", str(data.get("total_videos", "—")))),
        ("认证", profile.get("certification", "—")),
        ("IP属地", profile.get("ip_location", "—")),
        ("简介", profile.get("description", "—")),
        ("主页链接", profile.get("profile_url", f"https://www.douyin.com/user/{data.get('blogger_id', '')}")),
        ("抓取时间", scrape_time[:19] if scrape_time else datetime.now().strftime("%Y-%m-%d %H:%M:%S")),
        ("数据来源", "CDP模式（用户Chrome浏览器）" if data.get("data_source") == "cdp" else "Playwright CLI"),
    ]

    for i, (key, val) in enumerate(info_items):
        row = 3 + i
        ws1[f"A{row}"] = key
        ws1[f"B{row}"] = str(val)
        ws1[f"A{row}"].font = Font(bold=True)
        ws1[f"A{row}"].fill = PatternFill(start_color="F0F0F0", end_color="F0F0F0", fill_type="solid")
        if key == "粉丝数":
            ws1[f"B{row}"].font = Font(bold=True, color="FF0000", size=14)
        if key == "主页链接":
            ws1[f"B{row}"].font = Font(color="0000FF", underline="single")

    ws1.column_dimensions["A"].width = 15
    ws1.column_dimensions["B"].width = 70

    # ========== Sheet 2: Top N 视频数据 + 评论区话题 ==========
    ws2 = wb.create_sheet(title=f"Top {len(top_videos)} 视频数据")

    ws2["A1"] = f"Top {len(top_videos)} 高赞视频数据与评论区话题分析"
    ws2["A1"].font = Font(size=14, bold=True, color="FFFFFF")
    ws2["A1"].fill = PatternFill(start_color="1E90FF", end_color="1E90FF", fill_type="solid")
    ws2["A1"].alignment = Alignment(horizontal="center", vertical="center")
    ws2.merge_cells("A1:K1")
    ws2.row_dimensions[1].height = 25

    headers = ["排名", "视频标题", "点赞数", "评论数", "收藏数", "转发数", "发布日期", "时长", "标签", "评论区话题", "视频链接"]
    for col, h in enumerate(headers, 1):
        cell = ws2.cell(row=3, column=col, value=h)
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = PatternFill(start_color="4472C4", end_color="4472C4", fill_type="solid")
        cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)

    for i, video in enumerate(top_videos):
        row = 4 + i
        ws2.cell(row=row, column=1, value=video.get("rank", i + 1)).alignment = Alignment(horizontal="center")
        ws2.cell(row=row, column=2, value=video.get("title", "")).alignment = Alignment(wrap_text=True, vertical="top")
        ws2.cell(row=row, column=3, value=_fmt_count(video.get("like_count", 0))).alignment = Alignment(horizontal="center")
        ws2.cell(row=row, column=4, value=_fmt_count(video.get("comment_count", 0))).alignment = Alignment(horizontal="center")
        ws2.cell(row=row, column=5, value=_fmt_count(video.get("collect_count", 0))).alignment = Alignment(horizontal="center")
        ws2.cell(row=row, column=6, value=_fmt_count(video.get("share_count", 0))).alignment = Alignment(horizontal="center")
        ws2.cell(row=row, column=7, value=video.get("publish_time", "—")).alignment = Alignment(horizontal="center")
        ws2.cell(row=row, column=8, value=video.get("duration", "—")).alignment = Alignment(horizontal="center")
        ws2.cell(row=row, column=9, value=video.get("tags", "—")).alignment = Alignment(wrap_text=True, vertical="top")

        # 评论区话题
        topic = video.get("comment_topic", "—")
        topic_cell = ws2.cell(row=row, column=10, value=topic)
        topic_cell.alignment = Alignment(wrap_text=True, vertical="top")
        topic_cell.font = Font(size=9)

        # 视频链接
        video_url = video.get("url", "")
        video_id = video.get("video_id", "")
        if not video_url and video_id:
            video_url = f"https://www.douyin.com/video/{video_id}"
        link_cell = ws2.cell(row=row, column=11, value=video_url)
        link_cell.alignment = Alignment(wrap_text=True, vertical="top")
        link_cell.font = Font(color="0000FF", underline="single", size=9)

        for col in range(1, 12):
            ws2.cell(row=row, column=col).border = thin_border

    # 列宽设置
    col_widths = {"A": 6, "B": 30, "C": 10, "D": 10, "E": 10, "F": 10, "G": 12, "H": 10, "I": 25, "J": 45, "K": 40}
    for col_letter, width in col_widths.items():
        ws2.column_dimensions[col_letter].width = width

    for row in range(4, 4 + len(top_videos)):
        ws2.row_dimensions[row].height = 60

    # ========== Sheet 3: AI 脚本制作深度分析（如果有数据） ==========
    if script_analysis:
        ws3 = wb.create_sheet(title="AI 脚本制作深度分析")

        ws3["A1"] = "AI 脚本制作深度分析（Subagent 并行生成）"
        ws3["A1"].font = Font(size=14, bold=True, color="FFFFFF")
        ws3["A1"].fill = PatternFill(start_color="1E90FF", end_color="1E90FF", fill_type="solid")
        ws3["A1"].alignment = Alignment(horizontal="center", vertical="center")
        ws3.merge_cells("A1:J1")
        ws3.row_dimensions[1].height = 25

        analysis_headers = ["排名", "视频标题", "核心主题", "脚本结构分析", "叙事手法", "信息呈现方式", "互动设计", "话题策略", "爆款因素", "数据洞察"]
        for col, h in enumerate(analysis_headers, 1):
            cell = ws3.cell(row=3, column=col, value=h)
            cell.font = Font(bold=True, color="FFFFFF")
            cell.fill = PatternFill(start_color="4472C4", end_color="4472C4", fill_type="solid")
            cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)

        for i, analysis in enumerate(script_analysis):
            row = 4 + i
            video = top_videos[i] if i < len(top_videos) else {}
            ws3.cell(row=row, column=1, value=video.get("rank", i + 1)).alignment = Alignment(horizontal="center", vertical="top")
            ws3.cell(row=row, column=2, value=video.get("title", "")).alignment = Alignment(wrap_text=True, vertical="top")

            for j, key in enumerate(["核心主题", "脚本结构分析", "叙事手法", "信息呈现方式", "互动设计", "话题策略", "爆款因素", "数据洞察"], 3):
                cell = ws3.cell(row=row, column=j, value=analysis.get(key, "—"))
                cell.alignment = Alignment(wrap_text=True, vertical="top")

            for col in range(1, 11):
                ws3.cell(row=row, column=col).border = thin_border

            ws3.row_dimensions[row].height = 100

        ws3_col_widths = {"A": 6, "B": 25, "C": 28, "D": 30, "E": 28, "F": 28, "G": 25, "H": 25, "I": 28, "J": 30}
        for col_letter, width in ws3_col_widths.items():
            ws3.column_dimensions[col_letter].width = width

    # ========== 保存 ==========
    wb.save(output_path)
    return output_path


def _fmt_count(value) -> str:
    """格式化数字：整数原样显示，字符串原样显示，0 显示为 "—" """
    if isinstance(value, str):
        return value if value and value != "0" else "—"
    if isinstance(value, (int, float)):
        if value == 0:
            return "—"
        if value >= 10000:
            return f"{value / 10000:.1f}万"
        return str(int(value))
    return str(value) if value else "—"


def main():
    """命令行入口"""
    if len(sys.argv) < 2:
        print("用法: python scripts/generate_excel.py <json_file> [--output <path>]")
        sys.exit(1)

    json_path = sys.argv[1]
    output_path = None

    if "--output" in sys.argv:
        idx = sys.argv.index("--output")
        if idx + 1 < len(sys.argv):
            output_path = sys.argv[idx + 1]

    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    result_path = create_excel(data, output_path)
    sheet_count = 3 if data.get("script_analysis") else 2
    print(f"Excel saved: {result_path}")
    print(f"{sheet_count} Sheets: 博主信息 | Top N 视频数据" + (" | AI 脚本制作深度分析" if sheet_count == 3 else ""))


if __name__ == "__main__":
    main()
