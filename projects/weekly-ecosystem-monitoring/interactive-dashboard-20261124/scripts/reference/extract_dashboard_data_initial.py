from __future__ import annotations

import argparse
import json
import math
import posixpath
import re
import zipfile
from collections import defaultdict
from datetime import date, datetime, timedelta
from pathlib import Path
from xml.etree import ElementTree as ET


NS_MAIN = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
NS_REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
Q = lambda tag: f"{{{NS_MAIN}}}{tag}"
CELL_RE = re.compile(r"([A-Z]+)(\d+)")

TARGET_CATEGORIES = {"英雄联盟", "王者荣耀", "CS2", "体育", "户外", "无畏契约"}
START_DATE = date(2026, 8, 31)
END_DATE = date(2026, 10, 11)
WEEK_LABELS = [f"2026W{i}" for i in range(36, 42)]
WEEK_INDEX = {label: i for i, label in enumerate(WEEK_LABELS)}


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def read_shared_strings(zf: zipfile.ZipFile) -> list[str]:
    if "xl/sharedStrings.xml" not in zf.namelist():
        return []
    values: list[str] = []
    with zf.open("xl/sharedStrings.xml") as fh:
        for _, elem in ET.iterparse(fh, events=("end",)):
            if local_name(elem.tag) == "si":
                values.append("".join(node.text or "" for node in elem.iter() if local_name(node.tag) == "t"))
                elem.clear()
    return values


def workbook_sheets(zf: zipfile.ZipFile) -> dict[str, str]:
    wb = ET.fromstring(zf.read("xl/workbook.xml"))
    rels = ET.fromstring(zf.read("xl/_rels/workbook.xml.rels"))
    targets = {node.attrib["Id"]: node.attrib["Target"] for node in rels}
    out = {}
    for sheet in wb.find(Q("sheets")):
        rid = sheet.attrib.get(f"{{{NS_REL}}}id")
        out[sheet.attrib["name"]] = posixpath.normpath(posixpath.join("xl", targets[rid]))
    return out


def scalar(value):
    if value is None or value == "":
        return None
    if isinstance(value, (int, float)):
        return value
    text = str(value).strip()
    if text.lower() in {"", "null", "none", "nan"}:
        return None
    try:
        number = float(text.replace(",", ""))
        return int(number) if number.is_integer() else number
    except ValueError:
        return text


def cell_value(cell: ET.Element, shared: list[str]):
    typ = cell.attrib.get("t")
    if typ == "inlineStr":
        return scalar("".join(node.text or "" for node in cell.iter() if local_name(node.tag) == "t"))
    v = cell.find(Q("v"))
    if v is None or v.text is None:
        return None
    if typ == "s":
        try:
            return scalar(shared[int(v.text)])
        except (ValueError, IndexError):
            return None
    return scalar(v.text)


def parse_row(elem: ET.Element, shared: list[str]) -> tuple[int, dict[str, object]]:
    row_number = int(elem.attrib.get("r", "0"))
    values = {}
    for cell in elem.findall(Q("c")):
        ref = cell.attrib.get("r", "")
        match = CELL_RE.match(ref)
        if match:
            values[match.group(1)] = cell_value(cell, shared)
    return row_number, values


def parse_date(value) -> date | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        # Excel serial date. Values in this workbook are stored without time.
        return (datetime(1899, 12, 30) + timedelta(days=float(value))).date()
    text = str(value).strip()
    for fmt in ("%Y-%m-%d", "%Y/%m/%d", "%Y%m%d"):
        try:
            return datetime.strptime(text, fmt).date()
        except ValueError:
            pass
    return None


def number(value, default=0.0) -> float:
    value = scalar(value)
    if isinstance(value, (int, float)) and math.isfinite(float(value)):
        return float(value)
    return default


def week_label(day: date) -> str:
    iso = day.isocalendar()
    return f"{iso.year}W{iso.week:02d}"


def compact_number(value: float, digits: int = 2):
    rounded = round(float(value), digits)
    if abs(rounded - round(rounded)) < 1e-9:
        return int(round(rounded))
    return rounded


def extract_aggregate(zf: zipfile.ZipFile, target: str, shared: list[str]) -> list[dict]:
    records = []
    seen = set()
    duplicates = 0
    with zf.open(target) as fh:
        for _, elem in ET.iterparse(fh, events=("end",)):
            if local_name(elem.tag) != "row":
                continue
            row_num, c = parse_row(elem, shared)
            elem.clear()
            if row_num == 1:
                continue
            day = parse_date(c.get("A"))
            category = str(c.get("B") or "").strip()
            if day is None or category not in TARGET_CATEGORIES | {"大盘", "品类整体"}:
                continue
            if day < START_DATE or day > END_DATE:
                continue
            key = (day.isoformat(), category)
            if key in seen:
                duplicates += 1
                continue
            seen.add(key)
            records.append({
                "d": day.isoformat(),
                "c": category,
                "dau": compact_number(number(c.get("C"))),
                "rev": compact_number(number(c.get("D"))),
                "pay": compact_number(number(c.get("E"))),
                "arppu": compact_number(number(c.get("F"))),
                "view": compact_number(number(c.get("G"))),
                "attr": compact_number(number(c.get("H"))),
            })
    records.sort(key=lambda x: (x["d"], x["c"]))
    return records, duplicates


def extract_anchor_sheet(
    zf: zipfile.ZipFile,
    target: str,
    shared: list[str],
    weekly: dict,
    diagnostics: dict,
) -> None:
    seen_daily = set()
    duplicates = 0
    filtered_rows = 0
    with zf.open(target) as fh:
        for _, elem in ET.iterparse(fh, events=("end",)):
            if local_name(elem.tag) != "row":
                continue
            row_num, c = parse_row(elem, shared)
            elem.clear()
            if row_num == 1:
                continue
            day = parse_date(c.get("A"))
            if day is None or day < START_DATE or day > END_DATE:
                continue
            category = str(c.get("C") or "").strip()
            if category not in TARGET_CATEGORIES:
                continue
            uid_raw = scalar(c.get("D"))
            if uid_raw is None:
                continue
            uid = str(uid_raw)
            nickname = str(c.get("E") or "未知主播").strip()
            if nickname in {"品类整体", "品类大盘", "大盘"}:
                continue
            # 源文件里部分 UID 被压缩为同一数值，结合昵称可避免误合并不同主播。
            daily_key = (day.isoformat(), category, uid, nickname)
            if daily_key in seen_daily:
                duplicates += 1
                continue
            seen_daily.add(daily_key)
            dau = number(c.get("I"))
            rev = number(c.get("J"))
            pay = number(c.get("K"))
            live = number(c.get("G"))
            acu = number(c.get("H"))
            view = number(c.get("M"))
            attr = number(c.get("N"))
            if max(abs(dau), abs(rev), abs(pay), abs(live), abs(acu), abs(view), abs(attr)) == 0:
                continue
            label = week_label(day)
            if label not in WEEK_INDEX:
                continue
            filtered_rows += 1
            key = (category, label, uid, nickname)
            agg = weekly.setdefault(key, {
                "nick": nickname,
                "dau": 0.0,
                "rev": 0.0,
                "pay": 0.0,
                "live": 0.0,
                "acu_sum": 0.0,
                "acu_days": 0,
                "view_sum": 0.0,
                "view_days": 0,
                "attr": 0.0,
            })
            # 同 UID 的多个源昵称在这个模板中代表不同主播，因此展示与归因键均保留昵称。
            agg["nick"] = nickname
            agg["dau"] += dau
            agg["rev"] += rev
            agg["pay"] += pay
            agg["live"] += live
            agg["attr"] += attr
            if acu > 0:
                agg["acu_sum"] += acu
                agg["acu_days"] += 1
            if view > 0:
                agg["view_sum"] += view
                agg["view_days"] += 1
    diagnostics["duplicate_daily_keys"] += duplicates
    diagnostics["anchor_rows_in_window"] += filtered_rows


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("workbook", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    weekly: dict[tuple[str, str, str], dict] = {}
    diagnostics = {"duplicate_daily_keys": 0, "anchor_rows_in_window": 0, "aggregate_duplicates": 0}

    with zipfile.ZipFile(args.workbook) as zf:
        shared = read_shared_strings(zf)
        sheets = workbook_sheets(zf)
        aggregate, agg_duplicates = extract_aggregate(zf, sheets["各品类的DAU和打赏情况"], shared)
        diagnostics["aggregate_duplicates"] = agg_duplicates
        anchor_sheets = [
            "英雄数据源", "王者数据源", "CS2数据源", "体育数据源", "户外数据源", "无畏数据源",
        ]
        for sheet_name in anchor_sheets:
            print(f"reading {sheet_name}...", flush=True)
            extract_anchor_sheet(zf, sheets[sheet_name], shared, weekly, diagnostics)

    anchors = []
    for (category, label, uid, _nickname), agg in weekly.items():
        anchors.append([
            category,
            WEEK_INDEX[label],
            uid,
            agg["nick"],
            compact_number(agg["dau"]),
            compact_number(agg["rev"]),
            compact_number(agg["pay"]),
            compact_number(agg["live"]),
            compact_number(agg["acu_sum"]),
            agg["acu_days"],
            compact_number(agg["view_sum"]),
            agg["view_days"],
            compact_number(agg["attr"]),
        ])
    anchors.sort(key=lambda x: (x[1], x[0], -float(x[5]), -float(x[4]), x[2]))

    categories = ["大盘", *sorted(TARGET_CATEGORIES)]
    payload = {
        "meta": {
            "source": str(args.workbook),
            "startDate": START_DATE.isoformat(),
            "endDate": END_DATE.isoformat(),
            "weeks": WEEK_LABELS,
            "categories": categories,
            "categoryColumns": ["d", "c", "dau", "rev", "pay", "arppu", "view", "attr"],
            "anchorColumns": ["category", "weekIndex", "uid", "nickname", "dauSum", "revenueSum", "payUsersSum", "liveHoursSum", "acuSum", "acuDays", "viewMinsSum", "viewDays", "attributionSum"],
            "diagnostics": diagnostics,
        },
        "aggregate": aggregate,
        "anchors": anchors,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(json.dumps({
        "output": str(args.output),
        "bytes": args.output.stat().st_size,
        "aggregateRows": len(aggregate),
        "anchorWeeklyRows": len(anchors),
        **diagnostics,
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
