# -*- coding: utf-8 -*-
"""合并所有品类 Excel 到一份文件"""
import os, glob
from openpyxl import Workbook, load_workbook
from openpyxl.styles import Font, Alignment, PatternFill, Border, Side

output_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "output")
files = sorted(glob.glob(os.path.join(output_dir, "2026-06-26_*_抖音博主Top100.xlsx")))
# 排除临时文件
files = [f for f in files if not os.path.basename(f).startswith("~$")]
print(f"Found {len(files)} files")

wb_out = Workbook()
ws = wb_out.active
ws.title = "全品类Top300汇总"

# Styles
header_fill = PatternFill(start_color="4472C4", end_color="4472C4", fill_type="solid")
header_font = Font(name="微软雅黑", bold=True, color="FFFFFF", size=11)
header_align = Alignment(horizontal="center", vertical="center")
thin_border = Border(
    left=Side(style="thin"), right=Side(style="thin"),
    top=Side(style="thin"), bottom=Side(style="thin"),
)
center_align = Alignment(horizontal="center", vertical="center")
left_align = Alignment(horizontal="left", vertical="top")
data_font = Font(name="微软雅黑", size=10)
cat_font = Font(name="微软雅黑", size=10, bold=True)

# Headers
headers = ["品类", "博主名称", "粉丝数", "获赞数", "博主主页链接", "排名"]
widths = [12, 20, 16, 18, 52, 6]
for col_idx, (h, w) in enumerate(zip(headers, widths), 1):
    cell = ws.cell(row=1, column=col_idx, value=h)
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = header_align
    cell.border = thin_border
    ws.column_dimensions[cell.column_letter].width = w
ws.row_dimensions[1].height = 28

row = 2
total_bloggers = 0

for fpath in files:
    fname = os.path.basename(fpath)
    # Extract category from filename: YYYY-MM-DD_品类_抖音博主Top100.xlsx
    parts = fname.replace(".xlsx", "").split("_")
    category = parts[1] if len(parts) >= 2 else "未知"

    wb_src = load_workbook(fpath, read_only=True)
    ws_src = wb_src.active

    # Read all data rows (skip header row 1)
    data_rows = list(ws_src.iter_rows(min_row=2, values_only=True))
    wb_src.close()

    for rank, data in enumerate(data_rows, 1):
        # data: (博主名称, 粉丝数, 获赞数, 主页链接)
        name = data[0] if len(data) > 0 and data[0] else "—"
        fans = data[1] if len(data) > 1 and data[1] else "—"
        likes = data[2] if len(data) > 2 and data[2] else "—"
        url = data[3] if len(data) > 3 and data[3] else "—"

        values = [category, name, fans, likes, url, rank]
        for col_idx, val in enumerate(values, 1):
            cell = ws.cell(row=row, column=col_idx, value=val)
            cell.font = data_font
            cell.border = thin_border
            if col_idx == 1:
                cell.font = cat_font
                cell.alignment = center_align
            elif col_idx == 6:
                cell.alignment = center_align
            elif col_idx == 4:
                cell.alignment = center_align
            elif col_idx == 2:
                cell.alignment = left_align
            else:
                cell.alignment = center_align
        row += 1
        total_bloggers += 1

    print(f"  {category}: {len(data_rows)} rows")

ws.freeze_panes = "A2"

# Auto-filter
ws.auto_filter.ref = f"A1:F{row-1}"

# Summary sheet
ws_sum = wb_out.create_sheet("汇总统计")
ws_sum.append(["品类", "博主数"])
ws_sum["A1"].font = Font(name="微软雅黑", bold=True)
ws_sum["B1"].font = Font(name="微软雅黑", bold=True)
ws_sum.column_dimensions["A"].width = 14
ws_sum.column_dimensions["B"].width = 10

for fpath in files:
    fname = os.path.basename(fpath)
    parts = fname.replace(".xlsx", "").split("_")
    category = parts[1] if len(parts) >= 2 else "未知"
    wb_src = load_workbook(fpath, read_only=True)
    count = wb_src.active.max_row - 1  # minus header
    wb_src.close()
    ws_sum.append([category, count])

out_path = os.path.join(output_dir, "2026-06-26_全品类汇总_抖音博主Top300.xlsx")
wb_out.save(out_path)
print(f"\nSaved: {out_path}")
print(f"Total: {total_bloggers} bloggers across {len(files)} categories")
