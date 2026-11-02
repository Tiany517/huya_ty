from __future__ import annotations

import argparse
import csv
import hashlib
import json
import shutil
import sqlite3
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path


def iso_from_ms(value: int | None) -> str | None:
    if value is None:
        return None
    return datetime.fromtimestamp(value / 1000, tz=timezone.utc).isoformat().replace("+00:00", "Z")


def read_titles(path: Path) -> dict[str, str]:
    titles: dict[str, str] = {}
    if not path.is_file():
        return titles
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            if row.get("id"):
                titles[str(row["id"])] = str(row.get("thread_name") or "")
    return titles


def message_text(item_type: str, payload: dict[str, object]) -> str:
    if item_type == "userMessage":
        parts: list[str] = []
        for part in payload.get("content") or []:
            if isinstance(part, dict) and part.get("type") == "text" and part.get("text"):
                parts.append(str(part["text"]))
        return "\n".join(parts).strip()
    if item_type == "agentMessage":
        return str(payload.get("text") or "").strip()
    return ""


def is_internal_observer_message(text: str) -> bool:
    return text.lstrip().startswith("Hello memory agent") or "<observed_from_primary_session>" in text[:500]


def safe_copy_tree(source: Path, destination: Path) -> list[str]:
    copied: list[str] = []
    if not source.exists():
        return copied
    for path in sorted(source.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(source)
        if any(part in {".git", "__pycache__"} for part in relative.parts):
            continue
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        copied.append(relative.as_posix())
    return copied


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", type=Path, required=True)
    parser.add_argument("--session-index", type=Path, required=True)
    parser.add_argument("--memories", type=Path, required=True)
    parser.add_argument("--staging", type=Path, required=True)
    args = parser.parse_args()

    staging = args.staging.resolve()
    if staging.exists() and any(staging.iterdir()):
        raise SystemExit(f"Staging directory must be absent or empty: {staging}")
    staging.mkdir(parents=True, exist_ok=True)

    titles = read_titles(args.session_index)
    database_uri = f"file:{args.db.resolve()}?mode=ro"
    connection = sqlite3.connect(database_uri, uri=True)
    connection.row_factory = sqlite3.Row

    turn_rows = connection.execute(
        "select thread_id, turn_id, status, started_at, completed_at, duration_ms from thread_turns"
    ).fetchall()
    turn_stats: dict[str, Counter[str]] = defaultdict(Counter)
    for row in turn_rows:
        turn_stats[str(row["thread_id"])][str(row["status"] or "unknown")] += 1

    item_rows = connection.execute(
        """
        select thread_id, turn_id, item_id, created_at_ms, item_type, item_json
        from thread_items
        where item_type in ('userMessage', 'agentMessage')
        order by thread_id, created_at_ms, rollout_ordinal, item_id
        """
    ).fetchall()

    threads: dict[str, dict[str, object]] = {}
    selected_counts = Counter()
    excluded_internal = 0
    for row in item_rows:
        item_type = str(row["item_type"])
        try:
            payload = json.loads(row["item_json"])
        except json.JSONDecodeError:
            continue
        phase = payload.get("phase") if item_type == "agentMessage" else None
        if item_type == "agentMessage" and phase == "commentary":
            continue
        text = message_text(item_type, payload)
        if not text:
            continue
        if item_type == "userMessage" and is_internal_observer_message(text):
            excluded_internal += 1
            continue
        thread_id = str(row["thread_id"])
        thread = threads.setdefault(
            thread_id,
            {
                "thread_id": thread_id,
                "title": titles.get(thread_id) or "Untitled thread",
                "messages": [],
            },
        )
        thread["messages"].append(
            {
                "item_id": row["item_id"],
                "turn_id": row["turn_id"],
                "created_at": iso_from_ms(row["created_at_ms"]),
                "role": "user" if item_type == "userMessage" else "assistant",
                "phase": phase,
                "text": text,
            }
        )
        selected_counts[item_type] += 1

    catalog: list[dict[str, object]] = []
    ordered_threads = sorted(
        threads.values(),
        key=lambda thread: (thread["messages"][-1]["created_at"] or "", thread["thread_id"]),
        reverse=True,
    )
    with (staging / "threads.jsonl").open("w", encoding="utf-8", newline="\n") as handle:
        for thread in ordered_threads:
            handle.write(json.dumps(thread, ensure_ascii=False, separators=(",", ":")) + "\n")
            messages = thread["messages"]
            first_at = next((item["created_at"] for item in messages if item["created_at"]), None)
            last_at = next((item["created_at"] for item in reversed(messages) if item["created_at"]), None)
            catalog.append(
                {
                    "thread_id": thread["thread_id"],
                    "title": thread["title"],
                    "first_message_at": first_at,
                    "last_message_at": last_at,
                    "user_messages": sum(item["role"] == "user" for item in messages),
                    "assistant_messages": sum(item["role"] == "assistant" for item in messages),
                    "turns_completed": turn_stats[thread["thread_id"]]["completed"],
                    "turns_interrupted": turn_stats[thread["thread_id"]]["interrupted"],
                    "turns_failed": turn_stats[thread["thread_id"]]["failed"],
                    "turns_in_progress": turn_stats[thread["thread_id"]]["inProgress"],
                }
            )

    with (staging / "thread-catalog.csv").open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(catalog[0]) if catalog else ["thread_id"])
        writer.writeheader()
        writer.writerows(catalog)

    shutil.copy2(args.session_index, staging / "session-index.jsonl")
    memory_files = safe_copy_tree(args.memories, staging / "memory")

    data_files = ["threads.jsonl", "thread-catalog.csv", "session-index.jsonl"] + [f"memory/{name}" for name in memory_files]
    file_hashes = {name: hashlib.sha256((staging / name).read_bytes()).hexdigest() for name in data_files}
    metadata = {
        "format": "codex-work-history-digest-v1",
        "created_at": datetime.now(tz=timezone.utc).isoformat().replace("+00:00", "Z"),
        "source_database": args.db.name,
        "source_database_mtime_utc": datetime.fromtimestamp(args.db.stat().st_mtime, tz=timezone.utc).isoformat().replace("+00:00", "Z"),
        "scope": "User messages plus assistant final and unspecified-phase messages; internal observer prompts, commentary, reasoning, tool calls, command output, images, and file diffs excluded.",
        "threads": len(catalog),
        "source_turns": len(turn_rows),
        "source_message_counts": dict(connection.execute(
            "select item_type, count(*) from thread_items where item_type in ('userMessage','agentMessage') group by item_type"
        ).fetchall()),
        "selected_message_counts": dict(selected_counts),
        "excluded_internal_observer_messages": excluded_internal,
        "memory_files": len(memory_files),
        "file_sha256": file_hashes,
    }
    (staging / "archive-metadata.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(metadata, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
