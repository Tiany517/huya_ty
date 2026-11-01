#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
huya_zhubo_monitor — Excel 追踪表格更新脚本
==============================================
创建或更新主播专属的监控 Excel 文件。
每个主播一个独立文件，同主播多次监控追加行。

用法:
  python update_excel.py \
    --streamer "Letme严君泽" \
    --room-id "660137" \
    --category "英雄联盟" \
    --summary "report-summary.txt" \
    --screenshot "path/to/keyframe.jpg" \
    --live-date "2026-05-29" \
    --excel-dir "C:\\Users\\tiany\\Desktop"
"""

import argparse
import os
import sys
import json
from datetime import datetime
from pathlib import Path

try:
    from openpyxl import Workbook, load_workbook
    from openpyxl.styles import Font, Alignment, Border, Side, PatternFill
    from openpyxl.utils import get_column_letter
    from openpyxl.drawing.image import Image as XLImage
except ImportError:
    print("错误: 需要 openpyxl 库，请运行: pip install openpyxl")
    sys.exit(1)

try:
    from PIL import Image as PILImage
except ImportError:
    print("错误: 需要 Pillow 库，请运行: pip install Pillow")
    sys.exit(1)

# ── 配置 ──────────────────────────────────────────────
COLUMN_WIDTHS = {
    "A": 20,   # 检测时间
    "B": 16,   # 主播昵称
    "C": 16,   # 房间号
    "D": 18,   # 归属游戏
    "E": 65,   # 回放内容（宽列容纳多行文本）
    "F": 28,   # 截图
    "G": 16,   # 直播日期
}

HEADERS = [
    "检测时间",
    "主播昵称",
    "主播房间号",
    "主播归属游戏",
    "直播回放的内容",
    "直播间的截图",
    "直播间的日期",
]

HEADER_FILL = PatternFill(start_color="1F4E79", end_color="1F4E79", fill_type="solid")
HEADER_FONT = Font(name="微软雅黑", size=11, bold=True, color="FFFFFF")
DATA_FONT = Font(name="微软雅黑", size=10)
WRAP_ALIGNMENT = Alignment(wrap_text=True, vertical="top", horizontal="left")
CENTER_ALIGNMENT = Alignment(wrap_text=True, vertical="center", horizontal="center")
THIN_BORDER = Border(
    left=Side(style="thin", color="B0B0B0"),
    right=Side(style="thin", color="B0B0B0"),
    top=Side(style="thin", color="B0B0B0"),
    bottom=Side(style="thin", color="B0B0B0"),
)

SCREENSHOT_MAX_WIDTH = 260   # px，Excel 中图片最大宽度
SCREENSHOT_MAX_HEIGHT = 160  # px，Excel 中图片最大高度
DEFAULT_ROW_HEIGHT = 140     # 默认数据行高度


def sanitize_filename(name: str) -> str:
    """清理文件名中的非法字符"""
    illegal = r'[\\/:*?"<>|]'
    cleaned = name
    for ch in illegal:
        cleaned = cleaned.replace(ch, "_")
    return cleaned.strip()


def get_excel_path(excel_dir: str, streamer: str) -> str:
    """获取主播对应的 Excel 文件路径"""
    safe_name = sanitize_filename(streamer)
    return os.path.join(excel_dir, f"{safe_name}_监控.xlsx")


def find_existing_row(ws, live_date: str) -> int:
    """
    检查是否已存在相同日期的记录。
    返回行号（1-based），不存在返回 -1。
    G列是"直播间的日期"。
    """
    for row_idx in range(2, ws.max_row + 1):
        cell_val = ws.cell(row=row_idx, column=7).value
        if cell_val and str(cell_val).strip() == live_date.strip():
            return row_idx
    return -1


def create_workbook_with_headers(excel_path: str) -> Workbook:
    """创建新 Workbook 并写入表头"""
    wb = Workbook()
    ws = wb.active
    ws.title = "主播监控记录"

    # 写表头
    for col_idx, header in enumerate(HEADERS, 1):
        cell = ws.cell(row=1, column=col_idx, value=header)
        cell.font = HEADER_FONT
        cell.fill = HEADER_FILL
        cell.alignment = CENTER_ALIGNMENT
        cell.border = THIN_BORDER

    # 设置列宽
    for col_letter, width in COLUMN_WIDTHS.items():
        ws.column_dimensions[col_letter].width = width

    # 冻结表头
    ws.freeze_panes = "A2"

    # 设置自动筛选
    ws.auto_filter.ref = f"A1:G1"

    wb.save(excel_path)
    return wb


def resize_screenshot(image_path: str) -> str:
    """
    将截图缩放到适合 Excel 单元格的大小。
    返回缩放后的临时文件路径（或原图如果不需要缩放）。
    """
    img = PILImage.open(image_path)
    w, h = img.size

    # 计算缩放比例
    ratio = min(SCREENSHOT_MAX_WIDTH / w, SCREENSHOT_MAX_HEIGHT / h, 1.0)

    if ratio >= 1.0:
        return image_path  # 不需要缩放

    new_w = int(w * ratio)
    new_h = int(h * ratio)
    resized = img.resize((new_w, new_h), PILImage.LANCZOS)

    # 保存到临时文件
    tmp_dir = os.path.join(os.environ.get("TEMP", os.path.dirname(image_path)), "huya_excel_tmp")
    os.makedirs(tmp_dir, exist_ok=True)
    tmp_path = os.path.join(tmp_dir, os.path.basename(image_path))
    resized.save(tmp_path, "JPEG", quality=85)
    return tmp_path


def add_data_row(ws, row_idx: int, data: dict, screenshot_path: str = None):
    """
    在指定行写入数据。

    data 应包含:
      - detect_time: str      # YYYY/MM/DD HH:MM
      - streamer: str         # 主播昵称
      - room_id: str          # 房间号
      - category: str         # 归属游戏
      - summary: str          # 回放内容（分点）
      - live_date: str        # 直播日期 YYYY-MM-DD
    """
    values = [
        data.get("detect_time", datetime.now().strftime("%Y/%m/%d %H:%M")),
        data.get("streamer", ""),
        data.get("room_id", ""),
        data.get("category", ""),
        data.get("summary", ""),
        "",  # F列是图片，文字留空
        data.get("live_date", ""),
    ]

    for col_idx, val in enumerate(values, 1):
        cell = ws.cell(row=row_idx, column=col_idx, value=val)
        cell.font = DATA_FONT
        cell.border = THIN_BORDER
        if col_idx == 5:  # E列：内容列
            cell.alignment = WRAP_ALIGNMENT
        elif col_idx == 6:  # F列：截图列（居中对齐）
            cell.alignment = CENTER_ALIGNMENT
        else:
            cell.alignment = Alignment(vertical="top", horizontal="left")

    # 设置行高
    ws.row_dimensions[row_idx].height = DEFAULT_ROW_HEIGHT

    # 嵌入截图到 F 列
    if screenshot_path and os.path.exists(screenshot_path):
        try:
            resized_path = resize_screenshot(screenshot_path)
            img = XLImage(resized_path)

            # 锚定到 F{row_idx} 单元格
            cell_ref = f"F{row_idx}"
            img.anchor = cell_ref

            # 微调图片位置使其居中
            ws.add_image(img)

            # 根据图片实际高度调整行高
            pil_img = PILImage.open(resized_path)
            img_h_px = pil_img.height
            # Excel 行高单位是磅，1磅 ≈ 1.33像素
            row_height_pts = max(DEFAULT_ROW_HEIGHT, img_h_px * 0.75 + 10)
            ws.row_dimensions[row_idx].height = row_height_pts

        except Exception as e:
            print(f"  [警告] 嵌入截图失败: {e}")
            ws.cell(row=row_idx, column=6).value = f"[截图: {os.path.basename(screenshot_path)}]"


def load_summary_text(summary_source: str) -> str:
    """从文件或直接字符串加载摘要内容"""
    if os.path.exists(summary_source):
        with open(summary_source, "r", encoding="utf-8") as f:
            return f.read().strip()
    return summary_source


def main():
    parser = argparse.ArgumentParser(description="更新主播监控 Excel 追踪表格")
    parser.add_argument("--streamer", required=True, help="主播昵称")
    parser.add_argument("--room-id", default="", help="主播房间号")
    parser.add_argument("--category", default="", help="主播归属游戏")
    parser.add_argument("--summary", default="", help="直播回放内容摘要（文本或文件路径）")
    parser.add_argument("--screenshot", default="", help="代表性截图路径")
    parser.add_argument("--live-date", default="", help="直播回放日期 YYYY-MM-DD")
    parser.add_argument("--detect-time", default="", help="检测时间 YYYY/MM/DD HH:MM（默认当前时间）")
    parser.add_argument("--excel-dir", default=None, help="Excel文件存放目录（默认桌面）")
    parser.add_argument("--json-input", default="", help="从JSON文件读取所有参数（从AI分析结果的结构化摘要）")

    args = parser.parse_args()

    # ── 解析参数 ──────────────────────────────────────
    if args.json_input and os.path.exists(args.json_input):
        with open(args.json_input, "r", encoding="utf-8") as f:
            jdata = json.load(f)
        streamer = jdata.get("streamer", args.streamer)
        room_id = jdata.get("roomId", args.room_id)
        category = jdata.get("category", args.category)
        summary = jdata.get("coreSummary", args.summary)
        live_date = jdata.get("liveDate", args.live_date)
        # keyScreenshots 提取
        screenshots = jdata.get("keyScreenshots", [])
        screenshot_path = args.screenshot
        if screenshots and not screenshot_path:
            # 从 raw-data.json 中找到对应帧的路径
            pass  # 由调用方传入 --screenshot
    else:
        streamer = args.streamer
        room_id = args.room_id
        category = args.category
        summary = load_summary_text(args.summary) if args.summary else ""
        live_date = args.live_date
        screenshot_path = args.screenshot

    detect_time = args.detect_time or datetime.now().strftime("%Y/%m/%d %H:%M")

    # ── 确定 Excel 目录 ──────────────────────────────
    if args.excel_dir:
        excel_dir = args.excel_dir
    else:
        # 默认输出到 Desktop/主机监/excel/
        monitor_root = os.path.join(os.environ.get("USERPROFILE", ""), "Desktop", "主机监")
        excel_dir = os.path.join(monitor_root, "excel")

    os.makedirs(excel_dir, exist_ok=True)

    # ── 验证必要参数 ──────────────────────────────────
    if not streamer:
        print("错误: 必须提供主播昵称 (--streamer)")
        sys.exit(1)

    excel_path = get_excel_path(excel_dir, streamer)

    print(f"主播: {streamer}")
    print(f"Excel: {excel_path}")
    print(f"日期: {live_date or '(未指定)'}")
    print(f"分类: {category or '(未指定)'}")
    print()

    # ── 打开或创建 Excel ──────────────────────────────
    if os.path.exists(excel_path):
        print("📂 找到已有监控文件，正在更新...")
        wb = load_workbook(excel_path)
        ws = wb.active
    else:
        print("📂 创建新的监控文件...")
        wb = create_workbook_with_headers(excel_path)
        ws = wb.active

    # ── 检查重复 ──────────────────────────────────────
    existing_row = -1
    if live_date:
        existing_row = find_existing_row(ws, live_date)

    # ── 组装数据 ──────────────────────────────────────
    row_data = {
        "detect_time": detect_time,
        "streamer": streamer,
        "room_id": str(room_id) if room_id else "",
        "category": category,
        "summary": summary,
        "live_date": live_date,
    }

    if existing_row > 0:
        print(f"⚠️ 已存在日期 {live_date} 的记录（第{existing_row}行），将覆盖更新。")
        row_idx = existing_row
    else:
        row_idx = ws.max_row + 1

    # ── 写入数据 ──────────────────────────────────────
    add_data_row(ws, row_idx, row_data, screenshot_path)

    # ── 保存 ──────────────────────────────────────────
    wb.save(excel_path)
    print(f"✅ 已{'更新' if existing_row > 0 else '新增'}第{row_idx}行记录")
    print(f"   文件: {excel_path}")
    print(f"   检测时间: {detect_time}")
    print(f"   主播: {streamer}")
    print(f"   房间号: {room_id or '(空)'}")
    print(f"   游戏: {category or '(空)'}")
    print(f"   直播日期: {live_date or '(空)'}")
    print(f"   截图: {screenshot_path or '(无)'}")

    # 输出 JSON 格式结果，方便脚本解析
    result = {
        "excel_path": excel_path,
        "row": row_idx,
        "streamer": streamer,
        "action": "updated" if existing_row > 0 else "created",
    }
    print(f"\nRESULT: {json.dumps(result, ensure_ascii=False)}")


if __name__ == "__main__":
    main()
