from __future__ import annotations

import csv
import json
import re
from collections import Counter
from pathlib import Path


INPUT_PATH = Path(r"C:\Users\tiany\Downloads\FPS类主播的年日均开播时长.csv")


EVENT_TERMS = [
    "夏季赛",
    "赛事",
    "联赛",
    "总决赛",
    "回顾",
    "轮播",
    "邀请赛",
    "职业赛",
    "职业联赛",
    "公开赛",
    "锦标赛",
    "先锋赛",
    "冠军赛",
    "挑战赛",
    "资格赛",
    "淘汰赛",
    "小组赛",
    "半决赛",
    "季后赛",
    "常规赛",
    "揭幕战",
    "决赛",
    "杯赛",
    "大奖赛",
    "表演赛",
    "解说",
    "二路",
    "回放",
    "集锦",
    "官方赛事",
    "赛事官方",
    "官方直播",
    "精彩集锦",
    "比赛回放",
    "赛事回顾",
    "赛事轮播",
    "电竞",
    "官方",
    "比赛",
    "对战",
    "活动",
]

# 高置信俱乐部别名。短代码在匹配时要求独立大写词，避免普通昵称误伤。
CLUB_ALIASES = {
    "EDward Gaming": ["EDward Gaming", "EDG"],
    "Bilibili Gaming": ["Bilibili Gaming", "BLG", "哔哩哔哩"],
    "JD Gaming": ["JD Gaming", "JDG", "京东"],
    "Weibo Gaming": ["Weibo Gaming", "WBG", "微博"],
    "Royal Never Give Up": ["Royal Never Give Up", "RNG", "皇族"],
    "Oh My God": ["Oh My God", "OMG"],
    "LGD Gaming": ["LGD Gaming", "LGD"],
    "LNG Esports": ["LNG Esports", "LNG", "李宁"],
    "Top Esports": ["Top Esports", "TES", "滔搏"],
    "Invictus Gaming": ["Invictus Gaming", "IG"],
    "Team WE": ["Team WE", "WE"],
    "Rare Atom": ["Rare Atom", "RA"],
    "FunPlus Phoenix": ["FunPlus Phoenix", "FPX"],
    "Nova Esports": ["Nova Esports", "NOVA", "NV"],
    "TYLOO": ["TYLOO"],
    "Titan Esports Club": ["Titan Esports Club", "TEC", "泰坦"],
    "Xi Lai Gaming": ["Xi Lai Gaming", "XLG"],
    "Dragon Ranger Gaming": ["Dragon Ranger Gaming", "DRG"],
    "Trace Esports": ["Trace Esports", "TE"],
    "Wolves Esports": ["Wolves Esports", "WOL", "狼队"],
    "All Gamers": ["All Gamers", "AG", "超玩会"],
    "Four Angry Men": ["Four Angry Men", "4AM"],
    "17 Gaming": ["17 Gaming", "17"],
    "Petrichor Road": ["Petrichor Road", "PeRo", "PERO"],
    "KeepBest Gaming": ["KeepBest Gaming", "KBG"],
    "Any Questions Gaming": ["Any Questions Gaming", "AQ"],
    "AT（VCT CN 战队代码）": ["AT"],
    "Octagonal Disposition Gaming": ["Octagonal Disposition Gaming", "ODG"],
    "Unsettled Resentment": ["Unsettled Resentment", "UR"],
    "VLG（VCT CN 战队代码）": ["VLG"],
    "WSIG（VCT CN 战队代码）": ["WSIG"],
    "NIP Group": ["NIP Group", "NIP"],
    "FaZe Clan": ["FaZe Clan", "FAZE"],
    "Astralis": ["Astralis", "AST"],
    "Heroic": ["Heroic", "HEROIC"],
    "MOUZ": ["MOUZ"],
    "Team Vitality": ["Team Vitality", "VITALITY"],
    "Natus Vincere": ["Natus Vincere", "NAVI"],
    "Paper Rex": ["Paper Rex", "PRX"],
    "DRX": ["DRX"],
    "DetonatioN FocusMe": ["DetonatioN FocusMe", "DFM"],
    "Rex Regum Qeon": ["Rex Regum Qeon", "RRQ"],
    "ZETA DIVISION": ["ZETA DIVISION", "ZETA"],
    "MIBR": ["MIBR"],
    "LOUD": ["LOUD"],
    "Sentinels": ["Sentinels", "SEN"],
    "NRG": ["NRG"],
    "FURIA": ["FURIA", "FUR"],
    "KRÜ Esports": ["KRÜ Esports", "KRU"],
    "Tianba": ["Tianba", "天霸"],
    "J Team": ["J Team", "JT"],
    "Q9/情久": ["Q9", "情久"],
    "Tongfu": ["Tongfu", "同福"],
    "Tt Esports": ["Tt Esports", "TT"],
    "NewHappy": ["NewHappy", "NH"],
}


def read_rows(path: Path) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.reader(handle)
        header = next(reader)
        for source_line, values in enumerate(reader, start=2):
            values = (values + [""] * 12)[:12]
            rows.append(
                {
                    "luid": values[0],
                    "snick": values[1],
                    "main_game_id": values[2],
                    "main_game_name": values[3],
                    "avg_daily_live_minutes": values[4],
                    "source_line": source_line,
                }
            )
    return rows


def club_match(name: str, club_name: str, alias: str) -> re.Match[str] | None:
    """按全名、长代码和短代码分别匹配，降低普通昵称误伤。"""
    del club_name
    if re.fullmatch(r"[A-Za-z0-9]{3,}", alias):
        return re.search(
            rf"(?<![A-Za-z0-9]){re.escape(alias)}(?![A-Za-z0-9])", name
        )
    if re.fullmatch(r"[A-Z0-9]{1,2}", alias):
        if alias == "AG":
            return re.search(r"^AG", name)
        if alias in {"WE", "IG", "TE", "AQ", "AT"}:
            return re.search(
                rf"^{re.escape(alias)}(?:$|[\u4e00-\u9fff]|[\s\-_.·・|丨/\\、，,])",
                name,
            )
        return re.search(
            rf"^{re.escape(alias)}(?:$|[\s\-_.·・|丨/\\、，,])", name
        )
    return re.search(re.escape(alias), name, flags=re.IGNORECASE)


def main() -> None:
    rows = read_rows(INPUT_PATH)
    event_hits = Counter()
    club_hits = Counter()
    event_rows = 0
    club_rows = 0

    for row in rows:
        name = str(row["snick"]).strip()
        hits = [term for term in EVENT_TERMS if term.casefold() in name.casefold()]
        if hits:
            event_rows += 1
            event_hits.update(hits)

        club_found = []
        for club_name, aliases in CLUB_ALIASES.items():
            for alias in aliases:
                matched = club_match(name, club_name, alias)
                if matched:
                    club_found.append((club_name, alias))
        if club_found:
            club_rows += 1
            club_hits.update(f"{club_name}|{alias}" for club_name, alias in club_found)

    durations = []
    low = 0
    for row in rows:
        name = str(row["snick"]).strip()
        event = any(term.casefold() in name.casefold() for term in EVENT_TERMS)
        club = any(
            club_match(name, "", alias)
            for aliases in CLUB_ALIASES.values()
            for alias in aliases
        )
        try:
            duration = float(str(row["avg_daily_live_minutes"]).strip())
        except ValueError:
            continue
        if duration < 30:
            low += 1
        if not event and not club and duration >= 30:
            durations.append(duration)

    durations.sort()

    def quantile(values: list[float], p: float) -> float:
        pos = (len(values) - 1) * p
        lo = int(pos)
        hi = min(lo + 1, len(values) - 1)
        frac = pos - lo
        return values[lo] * (1 - frac) + values[hi] * frac

    q1 = quantile(durations, 0.25)
    q3 = quantile(durations, 0.75)
    iqr = q3 - q1
    threshold = q3 + 3 * iqr

    print(json.dumps({
        "rows": len(rows),
        "event_rows": event_rows,
        "event_hits": event_hits.most_common(),
        "club_rows": club_rows,
        "club_hits": club_hits.most_common(),
        "low_activity_all_rows": low,
        "iqr_base_rows": len(durations),
        "q1": q1,
        "q3": q3,
        "iqr": iqr,
        "high_threshold_minutes": threshold,
        "high_threshold_hours": threshold / 60,
        "high_rows": sum(value > threshold for value in durations),
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
