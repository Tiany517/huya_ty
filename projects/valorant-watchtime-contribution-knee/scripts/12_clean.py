# -*- coding: utf-8 -*-
"""清洗 CSV：修复落单引号导致的字段错位，输出副本，不覆盖原始文件

已知问题：3 行形如  ...,huya,"Style丶James-90327,1628046910,...
          r_owner 前面有一个「落单引号」（引号数为奇数），导致该行被拆成 21 段
处理：引号数为奇数的行 -> 去掉该行所有引号；偶数引号（合法带逗号昵称）保持原样
"""
import csv
import io
import os

SRC = r"C:\Users\tiany\Downloads\无畏契约行业ACU份额_全网主播价值预测口径_1至9月份.csv"
DST_DIR = r"C:\Users\tiany\Desktop\无畏契约观时贡献率拐点_20261015\data"
DST = os.path.join(DST_DIR, "无畏契约观时贡献率_1至9月_清洗版.csv")
NCOL = 19


def main():
    os.makedirs(DST_DIR, exist_ok=True)
    raw = io.open(SRC, encoding="utf-8-sig", newline="").read().split("\n")
    print("原始行数(含表头):", len(raw))

    fixed_lines, fixed_rows, bad_rows = [], 0, []
    for i, line in enumerate(raw):
        if not line.strip():
            continue
        nq = line.count('"')
        if nq % 2 == 1:
            fixed_lines.append(line.replace('"', ""))
            fixed_rows += 1
            bad_rows.append(i + 1)
        else:
            fixed_lines.append(line)

    print("修复行数:", fixed_rows, "| 行号:", bad_rows)

    header, body = fixed_lines[0], fixed_lines[1:]
    print("表头字段数:", len(next(csv.reader([header]))))
    bad = [(i + 2, len(next(csv.reader([l])))) for i, l in enumerate(body)
           if len(next(csv.reader([l]))) != NCOL]
    print("修复后字段数 != 19 的行:", len(bad), bad[:5])

    with io.open(DST, "w", encoding="utf-8-sig", newline="") as f:
        f.write("\n".join(fixed_lines) + "\n")
    print("已输出:", DST, "| 行数:", len(body))


if __name__ == "__main__":
    main()
