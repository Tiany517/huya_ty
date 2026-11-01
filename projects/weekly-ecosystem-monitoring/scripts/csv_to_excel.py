import csv
import os
import re
import sys
from pathlib import Path

import pandas as pd

# ===================== 【配置区】请修改这里的文件路径 =====================
# 你的CSV文件路径（用r开头，避免路径转义报错）
csv_file_path = os.environ.get(
    "CSV_FILE_PATH",
    r"C:\Users\tiany\Downloads\execId-5092fbef-d192-4d88-85f7-837f0fd02ce8.csv"
)
# 你要生成的Excel文件路径
excel_file_path = os.environ.get(
    "EXCEL_FILE_PATH",
    r"C:\Users\tiany\Downloads\站内ACU份额_数字化_v2.xlsx"
)
output_path = Path(excel_file_path)
# CSV文件编码（中文乱码就改成 "gbk"，Windows导出的CSV大多用gbk）
csv_encoding = "utf-8-sig"
# 分隔符（你的文件是逗号就不用改，是中文逗号就改成 "，"）
csv_sep = ","
# ==========================================================================

# ---------------------- 【核心清洗函数】解决所有报错 ----------------------
def clean_excel_cell(text):
    """
    1. 清除Excel不允许的非法控制字符（解决IllegalCharacterError报错）
    2. 截断超长文本到Excel单元格上限32767字符（解决截断警告）
    3. 空字符串和 \\N 转成字面量 null
    """
    if text is None or pd.isna(text):
        return "null"
    if not isinstance(text, str):
        return text
    text_str = str(text)
    if text_str == "" or text_str == r"\N":
        return "null"
    # 清除所有Excel非法的不可见控制字符
    illegal_chars = re.compile(r'[\x00-\x08\x0B\x0C\x0E-\x1F]')
    cleaned_text = illegal_chars.sub('', text_str)
    # 截断到Excel单元格最大字符限制32767
    return cleaned_text[:32767]


def parse_csv_line(line):
    """解析被拆出的单行，保留 CSV 引号规则。"""
    return next(csv.reader([line], delimiter=csv_sep))


def repair_row(row):
    """修复主播昵称字段中被错误拼接的多条记录。"""
    if len(row) != 16 or "\n" not in row[4]:
        return [row]

    parts = row[4].splitlines()
    repaired_rows = []

    # 第一条记录的前 4 列仍在原 row 中，后 12 列在异常字段的第一行。
    first = row[:4] + parse_csv_line(parts[0])
    if len(first) == 16:
        repaired_rows.append(first)

    # 中间部分通常是完整的 16 列记录。
    for line in parts[1:-1]:
        values = parse_csv_line(line)
        if len(values) == 16:
            repaired_rows.append(values)

    # 最后一条记录的前 5 列在异常字段最后一行，后 11 列仍在原 row[5:] 中。
    last = parse_csv_line(parts[-1]) + row[5:]
    if len(last) == 16:
        repaired_rows.append(last)

    return repaired_rows or [row]


def convert_column_types(dataframe):
    """将英文表头对应的列转成数值；缺失值保留为 Excel 中的字面量 null。"""
    numeric_columns = [
        "gameid", "luid", "is_live", "live_mins", "avg_acu", "dau",
        "daily_revenue", "daily_pay_user_cnt", "arppu", "avg_view_mins",
        "attribution_user_cnt", "interest_user_cnt",
        "non_category_interest_user_cnt"
    ]
    for column in numeric_columns:
        if column not in dataframe.columns:
            continue
        values = pd.to_numeric(
            dataframe[column].replace({"": pd.NA, r"\N": pd.NA, "null": pd.NA}),
            errors="coerce"
        )
        dataframe[column] = values.astype(object).where(values.notna(), "null")
    return dataframe


# Python 的 csv 解析器默认限制单个字段不超过 131072 个字符。
# 这里提高上限，之后仍会按 Excel 单元格的 32767 字符限制截断。
csv_field_limit = sys.maxsize
while True:
    try:
        csv.field_size_limit(csv_field_limit)
        break
    except OverflowError:
        csv_field_limit //= 10

try:
    with open(csv_file_path, "r", encoding=csv_encoding, newline="") as csv_file:
        reader = csv.reader(csv_file, delimiter=csv_sep)
        header = next(reader)
        rows = []
        repaired_count = 0
        for row in reader:
            repaired_rows = repair_row(row)
            if len(repaired_rows) > 1:
                repaired_count += 1
            rows.extend(repaired_rows)

    df = pd.DataFrame(rows, columns=header)
    df = convert_column_types(df)
    print(f"[OK] 成功读取CSV，共 {len(df)} 行 x {len(df.columns)} 列")
    if repaired_count:
        print(f"[OK] 已修复 {repaired_count} 个被拼接的异常记录块")
except FileNotFoundError:
    print(f"[ERROR] 找不到CSV文件，请检查路径：{csv_file_path}")
    exit()
except Exception as e:
    print(f"[ERROR] 读取CSV失败：{str(e)}")
    exit()

# ---------------------- 【2. 全表清洗+导出Excel】 ----------------------
# 对所有单元格执行清洗，解决报错问题
df_cleaned = df.apply(lambda column: column.map(clean_excel_cell))

# 直接导出无美化的Excel文件
try:
    if output_path.exists() and os.environ.get("CSV_TO_EXCEL_OVERWRITE") != "1":
        raise RuntimeError(
            "Output workbook already exists. Set CSV_TO_EXCEL_OVERWRITE=1 "
            "only after confirming the destination and a backup."
        )
    df_cleaned.to_excel(
        output_path,
        index=False,  # 不导出Python的索引列
        engine="openpyxl"
    )
    print(f"[OK] 转换完成！文件已保存至：{excel_file_path}")
except Exception as e:
    print(f"[ERROR] 导出Excel失败：{str(e)}")
    exit()
