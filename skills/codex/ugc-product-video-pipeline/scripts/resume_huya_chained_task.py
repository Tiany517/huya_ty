import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List

from generate_huya_story_media import download_file, extract_media_urls, json_headers, parse_json_response, read_json, write_json


API_BASE = "https://art.huya.info/openapi/v1"


def require_api_key() -> str:
    api_key = os.getenv("HUYA_ART_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("缺少 HUYA_ART_API_KEY 环境变量。")
    return api_key


def append_jsonl(path: Path, row: Dict[str, Any]) -> None:
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")


def load_submitted_event(log_path: Path, business_id: str) -> Dict[str, Any]:
    matched: Dict[str, Any] = {}
    with log_path.open("r", encoding="utf-8") as f:
        for line in f:
            row = json.loads(line)
            if row.get("event") == "submitted" and row.get("business_id") == business_id:
                matched = row
    if not matched:
        raise RuntimeError(f"未找到 submitted 事件: {business_id}")
    return matched


def poll_once(api_key: str, task_id: Any) -> Dict[str, Any]:
    import requests

    response = requests.get(
        f"{API_BASE}/generate/result/{task_id}",
        headers=json_headers(api_key),
        timeout=120,
    )
    payload = parse_json_response(response)
    if not response.ok:
        raise RuntimeError(f"HTTP {response.status_code}: {payload}")
    return payload


def status_of(payload: Dict[str, Any]) -> str:
    return (payload.get("status") or payload.get("data", {}).get("status") or "").lower()


def extract_last_frame(video_path: Path, output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-sseof",
            "-0.12",
            "-i",
            str(video_path),
            "-vf",
            "scale=720:1280:force_original_aspect_ratio=increase,crop=720:1280,setsar=1",
            "-frames:v",
            "1",
            str(output_path),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def segment_index_from_business_id(business_id: str) -> int:
    return int(business_id.rsplit("-", 1)[-1])


def main() -> int:
    parser = argparse.ArgumentParser(description="Resume one submitted Huya chained video task.")
    parser.add_argument("--base-dir", required=True)
    parser.add_argument("--business-id", required=True)
    parser.add_argument("--max-wait-seconds", type=int, default=3600)
    args = parser.parse_args()

    api_key = require_api_key()
    base_dir = Path(args.base_dir).resolve()
    log_path = base_dir / "huya_chained_video_generation_log.jsonl"
    state_path = base_dir / "huya_chained_video_tasks_state.json"
    video_dir = base_dir / "videos_chain_v2_huya"
    frame_dir = base_dir / "chain_v2_frames"
    event = load_submitted_event(log_path, args.business_id)
    task_id = event["task_id"]
    index = segment_index_from_business_id(args.business_id)
    output_path = video_dir / f"曹操_视频_{index:02d}_chain_v2.mp4"
    last_frame_rel = f"chain_v2_frames/曹操_实际末帧_{index:02d}.png"
    last_frame_path = base_dir / last_frame_rel

    started_at = time.time()
    while time.time() - started_at < args.max_wait_seconds:
        payload = poll_once(api_key, task_id)
        append_jsonl(log_path, {"event": "resume_poll", "task_id": task_id, "payload": payload, "ts": int(time.time())})
        status = status_of(payload)
        print(f"[resume_poll] {args.business_id} task={task_id} status={status or 'unknown'}")
        if status in {"success", "completed", "succeeded"}:
            urls = extract_media_urls(payload)
            if not urls:
                raise RuntimeError(f"视频任务完成但未返回 URL: {payload}")
            download_file(urls[0], output_path)
            extract_last_frame(output_path, last_frame_path)
            state = read_json(state_path) if state_path.exists() else {"task_name": "曹操_实际末帧链式生成_v2", "tasks": {}}
            state["tasks"][args.business_id] = {
                "status": "success",
                "task_id": task_id,
                "model_index": 0,
                "model": event["model"],
                "parameters": event["parameters"],
                "result_urls": urls,
                "downloaded_to": str(output_path),
                "actual_last_frame_file": last_frame_rel,
                "duration": event["parameters"].get("duration"),
                "prompt": event["parameters"].get("prompt"),
                "resumed_from_log": True,
            }
            write_json(state_path, state)
            print(f"[video] {args.business_id} -> {output_path}")
            print(f"[frame] {args.business_id} -> {last_frame_path}")
            return 0
        if status in {"fail", "failed", "error"}:
            raise RuntimeError(f"任务失败: {payload}")
        time.sleep(10)
    raise TimeoutError(f"任务超时: {task_id}")


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
