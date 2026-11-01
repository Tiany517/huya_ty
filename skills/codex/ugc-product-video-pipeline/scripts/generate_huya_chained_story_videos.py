import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List

from generate_huya_story_media import (
    build_video_parameters,
    download_file,
    extract_media_urls,
    json_headers,
    parse_json_response,
    read_json,
    submit_generation,
    upload_file,
    write_json,
)


API_BASE = "https://art.huya.info/openapi/v1"


def require_api_key() -> str:
    api_key = os.getenv("HUYA_ART_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("缺少 HUYA_ART_API_KEY 环境变量。")
    return api_key


def append_jsonl(path: Path, row: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")


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


def upload_image_rel(api_key: str, base_dir: Path, rel_path: str, cache_path: Path) -> str:
    cache = read_json(cache_path) if cache_path.exists() else {}
    rel_key = rel_path.replace("\\", "/")
    if rel_key in cache:
        return cache[rel_key]
    path = base_dir / rel_key
    if not path.exists():
        raise FileNotFoundError(f"缺少首尾帧图片: {path}")
    cache[rel_key] = upload_file(api_key, path)
    write_json(cache_path, cache)
    return cache[rel_key]


def extract_last_frame(video_path: Path, output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
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
    ]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def build_chain_prompt(segment: Dict[str, Any], index: int, total: int) -> str:
    opener = "第一段从给定起始分镜自然开始。" if index == 1 else "本段第一帧来自上一段视频的真实末帧，必须像同一镜头继续拍摄，不要重新开场。"
    closer = "最后0.5秒保持人物和镜头稳定，给下一段继续衔接。" if index < total else "结尾收束稳定，不要黑场，不要淡出。"
    return (
        "制作一段中国历史人物口播短视频，竖屏9:16，真实电影纪录片质感。"
        f"{opener}"
        "使用首尾帧模式，但不要做闪白、黑场、跳切、转场特效、淡入淡出。"
        "镜头运动要慢，优先使用轻微推近、横移、人物自然转身或环境运动来连接首尾帧。"
        "人物身份保持为同一个曹操，脸型、服饰质感、时代背景、色调连续。"
        f"本段视觉目标：{segment['visual_goal']}"
        "必须生成清晰自然的中文成年男声口播，并让人物口型和口播同步。"
        f"完整覆盖这段文案：{segment['voiceover_cn']}"
        "口播语速偏慢，句间有停顿，不要抢话，不要在结尾截断。"
        "不要生成背景音乐，不要配乐，不要鼓点，不要歌声，只保留轻微环境声和清晰人声。"
        "不要字幕，不要标题，不要水印。"
        f"{closer}"
    )


def task_status(payload: Dict[str, Any]) -> str:
    return (payload.get("status") or payload.get("data", {}).get("status") or "").lower()


def wait_download_one(
    api_key: str,
    task_id: Any,
    output_path: Path,
    log_path: Path,
    max_wait_seconds: int,
) -> Dict[str, Any]:
    started_at = time.time()
    while time.time() - started_at < max_wait_seconds:
        payload = poll_once(api_key, task_id)
        append_jsonl(log_path, {"event": "poll", "task_id": task_id, "payload": payload, "ts": int(time.time())})
        status = task_status(payload)
        if status in {"success", "completed", "succeeded"}:
            urls = extract_media_urls(payload)
            if not urls:
                raise RuntimeError(f"视频任务完成但未返回 URL: {payload}")
            download_file(urls[0], output_path)
            return {"payload": payload, "urls": urls}
        if status in {"fail", "failed", "error"}:
            raise RuntimeError(f"视频任务失败: {payload}")
        print(f"[poll] task={task_id} status={status or 'unknown'}")
        time.sleep(10)
    raise TimeoutError(f"视频任务超时: {task_id}")


def submit_with_fallback(
    api_key: str,
    task: Dict[str, Any],
    platform: Dict[str, Any],
    upload_urls: Dict[str, str],
    log_path: Path,
    output_path: Path,
    max_wait_seconds: int,
) -> Dict[str, Any]:
    errors: List[str] = []
    for model_index, model_spec in enumerate(platform["video_model_priority"]):
        params = build_video_parameters(task, platform["default_parameters"], model_spec, upload_urls)
        result = submit_generation(api_key, model_spec, params)
        task_id = result.get("task_id") or result.get("data", {}).get("task_id")
        if not task_id:
            raise RuntimeError(f"创建视频任务失败，缺少 task_id: {result}")
        append_jsonl(
            log_path,
            {
                "event": "submitted",
                "business_id": task["client_business_id"],
                "task_id": task_id,
                "model": model_spec,
                "parameters": params,
                "ts": int(time.time()),
            },
        )
        try:
            done = wait_download_one(api_key, task_id, output_path, log_path, max_wait_seconds)
            return {
                "status": "success",
                "task_id": task_id,
                "model_index": model_index,
                "model": model_spec,
                "parameters": params,
                "result_urls": done["urls"],
                "downloaded_to": str(output_path),
            }
        except RuntimeError as exc:
            errors.append(str(exc))
            append_jsonl(
                log_path,
                {
                    "event": "model_failed",
                    "business_id": task["client_business_id"],
                    "task_id": task_id,
                    "model": model_spec,
                    "error": str(exc),
                    "ts": int(time.time()),
                },
            )
            continue
    raise RuntimeError(f"所有视频模型均失败: {errors}")


def generate_chain(plan_path: Path, max_wait_seconds: int) -> None:
    api_key = require_api_key()
    base_dir = plan_path.parent
    plan = read_json(plan_path)
    platform = {
        "video_model_priority": [
            {"provider": "volcengine", "model": "seedance-2.0-fast-cn", "type": "image2video"},
            {"provider": "volcengine", "model": "seedance-2.0-cn", "type": "image2video"},
            {"provider": "aliyun", "model": "happyhorse-1.0", "type": "image2video"},
        ],
        "default_parameters": {
            "aspectRatio": "9:16",
            "resolution": "480p_to_720p",
            "generateAudio": True,
            "roleMode": "frame",
            "nsfw": False,
            "isUploadAsset": True,
        },
    }
    output_dir = base_dir / "videos_chain_v2_huya"
    frame_dir = base_dir / "chain_v2_frames"
    state_path = base_dir / "huya_chained_video_tasks_state.json"
    log_path = base_dir / "huya_chained_video_generation_log.jsonl"
    upload_cache_path = base_dir / "huya_upload_cache_chain_v2.json"
    output_dir.mkdir(parents=True, exist_ok=True)
    frame_dir.mkdir(parents=True, exist_ok=True)
    state = read_json(state_path) if state_path.exists() else {"task_name": "曹操_实际末帧链式生成_v2", "tasks": {}}

    segments = plan["segments"]
    previous_last_frame_rel = ""
    for index, segment in enumerate(segments, start=1):
        business_id = f"caocao-chain-v2-seg-{index:02d}"
        output_file = f"曹操_视频_{index:02d}_chain_v2.mp4"
        output_path = output_dir / output_file
        last_frame_rel = f"chain_v2_frames/曹操_实际末帧_{index:02d}.png"
        last_frame_path = base_dir / last_frame_rel

        if index == 1:
            first_frame_rel = segment["first_frame_file"]
        else:
            first_frame_rel = previous_last_frame_rel

        task = {
            "client_business_id": business_id,
            "first_frame_file": first_frame_rel,
            "last_frame_file": segment["last_frame_file"],
            "output_file": output_file,
            "duration": int(segment["duration"]) + 2,
            "prompt": build_chain_prompt(segment, index, len(segments)),
        }

        task_state = state["tasks"].get(business_id, {})
        if output_path.exists() and last_frame_path.exists() and task_state.get("status") == "success":
            print(f"[skip] {business_id} already generated")
            previous_last_frame_rel = last_frame_rel
            continue

        start_url = upload_image_rel(api_key, base_dir, first_frame_rel, upload_cache_path)
        end_url = upload_image_rel(api_key, base_dir, segment["last_frame_file"], upload_cache_path)
        upload_urls = {first_frame_rel: start_url, segment["last_frame_file"]: end_url}

        print(f"[submit] {business_id}: {first_frame_rel} -> {segment['last_frame_file']} duration={task['duration']}")
        result_state = submit_with_fallback(
            api_key=api_key,
            task=task,
            platform=platform,
            upload_urls=upload_urls,
            log_path=log_path,
            output_path=output_path,
            max_wait_seconds=max_wait_seconds,
        )
        extract_last_frame(output_path, last_frame_path)
        result_state["actual_last_frame_file"] = last_frame_rel
        result_state["source_first_frame_file"] = first_frame_rel
        result_state["target_last_frame_file"] = segment["last_frame_file"]
        result_state["duration"] = task["duration"]
        result_state["prompt"] = task["prompt"]
        state["tasks"][business_id] = result_state
        write_json(state_path, state)
        print(f"[video] {business_id} -> {output_path}")
        print(f"[frame] {business_id} -> {last_frame_path}")
        previous_last_frame_rel = last_frame_rel


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate story videos with actual-last-frame chaining.")
    parser.add_argument("--plan", required=True)
    parser.add_argument("--max-wait-seconds", type=int, default=2400)
    args = parser.parse_args()
    generate_chain(Path(args.plan).resolve(), args.max_wait_seconds)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
