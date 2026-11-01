# -*- coding: utf-8 -*-
"""
极简4列 Excel 生成器 — douyin-category-scout 专用

列: 博主名称 | 粉丝数 | 获赞数 | 博主主页链接
"""
import os
import re
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill, Border, Side


def generate_category_excel(result: dict, output_dir: str) -> str:
    """Generate a 4-column Excel file from category scout results.

    Args:
        result: CategoryScoutResult.model_dump() dict with keys:
            keyword, total_found, scrape_time, top_100.
        output_dir: Directory to write the .xlsx file into.

    Returns:
        Absolute path to the generated .xlsx file.
    """
    os.makedirs(output_dir, exist_ok=True)

    wb = Workbook()
    ws = wb.active
    ws.title = "抖音博主Top100"

    keyword = result.get("keyword", "未知搜索")
    top_100 = result.get("top_100", [])
    scrape_time = result.get("scrape_time", "")
    scrape_date = scrape_time[:10] if scrape_time else "unknown"

    # Styles
    header_fill = PatternFill(start_color="4472C4", end_color="4472C4", fill_type="solid")
    header_font = Font(name="微软雅黑", bold=True, color="FFFFFF", size=11)
    header_alignment = Alignment(horizontal="center", vertical="center")

    thin_border = Border(
        left=Side(style="thin"),
        right=Side(style="thin"),
        top=Side(style="thin"),
        bottom=Side(style="thin"),
    )
    center_align = Alignment(horizontal="center", vertical="center")
    left_align = Alignment(horizontal="left", vertical="top", wrap_text=True)
    link_font = Font(name="微软雅黑", color="0000FF", underline="single")
    data_font = Font(name="微软雅黑", size=10)

    # Headers: 4 columns
    headers = ["博主名称", "粉丝数", "获赞数", "博主主页链接"]
    column_widths = {"A": 16, "B": 14, "C": 14, "D": 50}

    for col_idx, header_text in enumerate(headers, start=1):
        cell = ws.cell(row=1, column=col_idx, value=header_text)
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = header_alignment
        cell.border = thin_border

    for col_letter, width in column_widths.items():
        ws.column_dimensions[col_letter].width = width

    ws.row_dimensions[1].height = 28

    # Data rows
    for row_idx, blogger in enumerate(top_100, start=2):
        # Column A: blogger name
        name = blogger.get("blogger_name", "") or "—"
        cell_a = ws.cell(row=row_idx, column=1, value=name)
        cell_a.font = data_font
        cell_a.alignment = left_align
        cell_a.border = thin_border

        # Column B: fans count (display original text, or parsed count as fallback)
        fans = blogger.get("fans_count", "") or "—"
        cell_b = ws.cell(row=row_idx, column=2, value=fans)
        cell_b.font = data_font
        cell_b.alignment = center_align
        cell_b.border = thin_border

        # Column C: total likes
        likes = blogger.get("total_likes", "") or "—"
        cell_c = ws.cell(row=row_idx, column=3, value=likes)
        cell_c.font = data_font
        cell_c.alignment = center_align
        cell_c.border = thin_border

        # Column D: profile link (blue underlined)
        url = blogger.get("profile_url", "") or "—"
        cell_d = ws.cell(row=row_idx, column=4, value=url)
        cell_d.font = link_font
        cell_d.alignment = center_align
        cell_d.border = thin_border

        ws.row_dimensions[row_idx].height = 24

    # Freeze header
    ws.freeze_panes = "A2"

    # Filename: YYYY-MM-DD_关键词_抖音博主Top100.xlsx
    safe_keyword = re.sub(r'[<>:"/\\|?*]', '_', keyword)
    filename = f"{scrape_date}_{safe_keyword}_抖音博主Top100.xlsx"
    filepath = os.path.abspath(os.path.join(output_dir, filename))

    wb.save(filepath)
    return filepath
