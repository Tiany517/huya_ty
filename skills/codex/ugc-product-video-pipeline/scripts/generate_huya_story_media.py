import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

import requests


API_BASE = "https://art.huya.info/openapi/v1"


def require_api_key() -> str:
    api_key = os.getenv("HUYA_ART_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("缺少 HUYA_ART_API_KEY 环境变量。")
    return api_key


def auth_headers(api_key: str) -> Dict[str, str]:
    return {"Authorization": f"Bearer {api_key}"}


def json_headers(api_key: str) -> Dict[str, str]:
    return {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json; charset=utf-8",
    }


def read_json(path: Path) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path: Path, data: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def append_jsonl(path: Path, row: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")


def parse_json_response(response: requests.Response) -> Any:
    try:
        return response.json()
    except requests.exceptions.JSONDecodeError:
        raise RuntimeError(f"接口返回非 JSON，HTTP {response.status_code}: {response.text[:500]}")


def ensure_ok(response: requests.Response, payload: Any) -> None:
    if response.ok:
        return
    raise RuntimeError(f"HTTP {response.status_code}: {payload}")


def upload_file(api_key: str, path: Path) -> str:
    with path.open("rb") as f:
        response = requests.post(
            f"{API_BASE}/file/upload",
            headers=auth_headers(api_key),
            files={"file": (path.name, f)},
            timeout=300,
        )
    payload = parse_json_response(response)
    ensure_ok(response, payload)
    if not payload.get("success"):
        raise RuntimeError(f"上传失败: {payload}")
    return payload["url"]


def wait_for_task(api_key: str, task_id: Any, log_path: Path, max_wait_seconds: int = 1800) -> Dict[str, Any]:
    start = time.time()
    while time.time() - start < max_wait_seconds:
        response = requests.get(
            f"{API_BASE}/generate/result/{task_id}",
            headers=json_headers(api_key),
            timeout=120,
        )
        payload = parse_json_response(response)
        ensure_ok(response, payload)
        append_jsonl(
            log_path,
            {"event": "poll", "task_id": task_id, "payload": payload, "ts": int(time.time())},
        )
        status = (payload.get("status") or payload.get("data", {}).get("status") or "").lower()
        if status in {"success", "completed", "succeeded"}:
            return payload
        if status in {"fail", "failed", "error"}:
            raise RuntimeError(f"任务失败: {payload}")
        time.sleep(8)
    raise TimeoutError(f"任务超时: {task_id}")


def poll_task_once(api_key: str, task_id: Any, log_path: Path) -> Dict[str, Any]:
    response = requests.get(
        f"{API_BASE}/generate/result/{task_id}",
        headers=json_headers(api_key),
        timeout=120,
    )
    payload = parse_json_response(response)
    ensure_ok(response, payload)
    append_jsonl(
        log_path,
        {"event": "poll", "task_id": task_id, "payload": payload, "ts": int(time.time())},
    )
    return payload


def extract_media_urls(payload: Dict[str, Any]) -> List[str]:
    urls: List[str] = []
    if isinstance(payload.get("results"), list):
        for item in payload["results"]:
            if isinstance(item, dict):
                for key in ("url", "url_cdn", "image_url", "video_url", "output"):
                    if isinstance(item.get(key), str):
                        urls.append(item[key])
    if isinstance(payload.get("images"), list):
        urls.extend([u for u in payload["images"] if isinstance(u, str)])
    if isinstance(payload.get("videos"), list):
        urls.extend([u for u in payload["videos"] if isinstance(u, str)])
    data = payload.get("data")
    if isinstance(data, dict):
        for key in ("images", "videos", "result", "outputs"):
            value = data.get(key)
            if isinstance(value, list):
                for item in value:
                    if isinstance(item, str):
                        urls.append(item)
                    elif isinstance(item, dict):
                        for k in ("url", "output", "image_url", "video_url"):
                            if isinstance(item.get(k), str):
                                urls.append(item[k])
            elif isinstance(value, str):
                urls.append(value)
        for key in ("url", "image_url", "video_url"):
            if isinstance(data.get(key), str):
                urls.append(data[key])
    for key in ("url", "image_url", "video_url", "output"):
        if isinstance(payload.get(key), str):
            urls.append(payload[key])
    deduped = []
    for url in urls:
        if url not in deduped:
            deduped.append(url)
    return deduped


def download_file(url: str, output_path: Path) -> None:
    response = requests.get(url, stream=True, timeout=600)
    response.raise_for_status()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("wb") as f:
        for chunk in response.iter_content(1024 * 1024):
            if chunk:
                f.write(chunk)


def submit_generation(api_key: str, model_spec: Dict[str, str], parameters: Dict[str, Any]) -> Dict[str, Any]:
    payload = {"model": model_spec, "parameters": parameters}
    response = requests.post(
        f"{API_BASE}/generate/image",
        headers=json_headers(api_key),
        json=payload,
        timeout=300,
    )
    result = parse_json_response(response)
    ensure_ok(response, result)
    return result


def build_video_parameters(
    task: Dict[str, Any],
    default_params: Dict[str, Any],
    model_spec: Dict[str, str],
    upload_urls: Dict[str, str],
) -> Dict[str, Any]:
    first_image = upload_urls[task["first_frame_file"]]
    last_image = upload_urls[task["last_frame_file"]]
    duration = int(task["duration"])

    if model_spec["provider"] == "aliyun" and model_spec["model"] == "happyhorse-1.0":
        return {
            "prompt": task["prompt"],
            "image_list": [first_image, last_image],
            "mode": "reference",
            "duration": duration,
            "resolution": "720P",
            "ratio": "9:16",
        }

    params = {
        **default_params,
        "prompt": task["prompt"],
        "images": [first_image, last_image],
        "duration": duration,
    }
    if model_spec["provider"] == "volcengine" and model_spec["model"].startswith("seedance-"):
        params["isUploadAsset"] = True
    return params


def generate_images(config_path: Path, api_key: str, max_wait_seconds: int) -> None:
    config = read_json(config_path)
    base_dir = config_path.parent
    log_path = base_dir / "huya_image_generation_log.jsonl"
    state_path = base_dir / "huya_image_tasks_state.json"
    state = read_json(state_path) if state_path.exists() else {"task_name": config["task_name"], "shots": {}}

    model_spec = config["platform"]["image_model_priority"][0]
    default_params = config["platform"]["default_parameters"]

    pending: List[Dict[str, Any]] = []
    for shot in config["shots"]:
        image_file = shot["image_file"]
        shot_id = shot["shot_id"]
        output_path = base_dir / image_file
        shot_state = state["shots"].get(shot_id, {})
        if output_path.exists() and shot_state.get("status") == "success":
            continue

        if not shot_state.get("task_id"):
            result = submit_generation(
                api_key,
                model_spec,
                {**default_params, "prompt": shot["prompt"]},
            )
            task_id = result.get("task_id") or result.get("data", {}).get("task_id")
            if not task_id:
                raise RuntimeError(f"创建图片任务失败，缺少 task_id: {result}")
            shot_state = {
                "task_id": task_id,
                "status": result.get("status", "submitted"),
                "model": model_spec,
                "image_file": image_file,
            }
            state["shots"][shot_id] = shot_state
            write_json(state_path, state)
            append_jsonl(log_path, {"event": "submitted", "shot_id": shot_id, "task_id": task_id, "ts": int(time.time())})
        pending.append(
            {
                "shot_id": shot_id,
                "image_file": image_file,
                "output_path": output_path,
                "task_id": shot_state["task_id"],
                "submitted_at": time.time(),
            }
        )

    while pending:
        next_pending: List[Dict[str, Any]] = []
        for item in pending:
            final_payload = poll_task_once(api_key, item["task_id"], log_path)
            status = (final_payload.get("status") or final_payload.get("data", {}).get("status") or "").lower()
            if status in {"success", "completed", "succeeded"}:
                urls = extract_media_urls(final_payload)
                if not urls:
                    raise RuntimeError(f"图片任务完成但未返回 URL: {final_payload}")
                download_file(urls[0], item["output_path"])
                shot_state = state["shots"][item["shot_id"]]
                shot_state["status"] = "success"
                shot_state["result_urls"] = urls
                shot_state["downloaded_to"] = str(item["output_path"])
                state["shots"][item["shot_id"]] = shot_state
                write_json(state_path, state)
                print(f"[image] {item['shot_id']} -> {item['output_path']}")
                continue
            if status in {"fail", "failed", "error"}:
                raise RuntimeError(f"图片任务失败: {final_payload}")
            if time.time() - item["submitted_at"] >= max_wait_seconds:
                raise TimeoutError(f"图片任务超时: {item['task_id']}")
            next_pending.append(item)
        pending = next_pending
        if pending:
            time.sleep(8)


def ensure_uploaded_image_urls(api_key: str, base_dir: Path, video_tasks: List[Dict[str, Any]], upload_cache_path: Path) -> Dict[str, str]:
    cache = read_json(upload_cache_path) if upload_cache_path.exists() else {}
    needed = sorted({t["first_frame_file"] for t in video_tasks} | {t["last_frame_file"] for t in video_tasks})
    for name in needed:
        if name in cache:
            continue
        path = base_dir / name
        if not path.exists():
            raise FileNotFoundError(f"缺少图片: {path}")
        cache[name] = upload_file(api_key, path)
        write_json(upload_cache_path, cache)
    return cache


def generate_videos(config_path: Path, api_key: str, max_wait_seconds: int) -> None:
    config = read_json(config_path)
    base_dir = config_path.parent
    log_path = base_dir / "huya_video_generation_log.jsonl"
    state_path = base_dir / "huya_video_tasks_state.json"
    upload_cache_path = base_dir / "huya_upload_cache.json"
    output_dir = base_dir / "videos_v2_huya"
    state = read_json(state_path) if state_path.exists() else {"task_name": config["task_name"], "tasks": {}}

    model_priority = config["platform"]["video_model_priority"]
    default_params = config["platform"]["default_parameters"]
    upload_urls = ensure_uploaded_image_urls(api_key, base_dir, config["video_tasks"], upload_cache_path)

    pending: List[Dict[str, Any]] = []
    for task in config["video_tasks"]:
        business_id = task["client_business_id"]
        output_path = output_dir / task["output_file"]
        task_state = state["tasks"].get(business_id, {})
        if output_path.exists() and task_state.get("status") == "success":
            continue

        model_index = int(task_state.get("model_index", 0))
        model_spec = model_priority[model_index]
        params = build_video_parameters(task, default_params, model_spec, upload_urls)

        if not task_state.get("task_id"):
            result = submit_generation(api_key, model_spec, params)
            task_id = result.get("task_id") or result.get("data", {}).get("task_id")
            if not task_id:
                raise RuntimeError(f"创建视频任务失败，缺少 task_id: {result}")
            task_state = {
                "task_id": task_id,
                "status": result.get("status", "submitted"),
                "model": model_spec,
                "model_index": model_index,
                "output_file": task["output_file"],
                "parameters": params,
            }
            state["tasks"][business_id] = task_state
            write_json(state_path, state)
            append_jsonl(log_path, {"event": "submitted", "business_id": business_id, "task_id": task_id, "ts": int(time.time())})
        pending.append(
            {
                "task": task,
                "business_id": business_id,
                "output_path": output_path,
                "task_id": task_state["task_id"],
                "submitted_at": time.time(),
            }
        )

    while pending:
        next_pending: List[Dict[str, Any]] = []
        for item in pending:
            final_payload = poll_task_once(api_key, item["task_id"], log_path)
            status = (final_payload.get("status") or final_payload.get("data", {}).get("status") or "").lower()
            if status in {"success", "completed", "succeeded"}:
                urls = extract_media_urls(final_payload)
                if not urls:
                    raise RuntimeError(f"视频任务完成但未返回 URL: {final_payload}")
                download_file(urls[0], item["output_path"])
                task_state = state["tasks"][item["business_id"]]
                task_state["status"] = "success"
                task_state["result_urls"] = urls
                task_state["downloaded_to"] = str(item["output_path"])
                state["tasks"][item["business_id"]] = task_state
                write_json(state_path, state)
                print(f"[video] {item['business_id']} -> {item['output_path']}")
                continue
            if status in {"fail", "failed", "error"}:
                task_state = state["tasks"][item["business_id"]]
                current_index = int(task_state.get("model_index", 0))
                if current_index + 1 < len(model_priority):
                    next_index = current_index + 1
                    next_model = model_priority[next_index]
                    next_params = build_video_parameters(item["task"], default_params, next_model, upload_urls)
                    result = submit_generation(api_key, next_model, next_params)
                    task_id = result.get("task_id") or result.get("data", {}).get("task_id")
                    if not task_id:
                        raise RuntimeError(f"视频任务降级重试失败，缺少 task_id: {result}")
                    task_state["task_id"] = task_id
                    task_state["status"] = result.get("status", "submitted")
                    task_state["model"] = next_model
                    task_state["model_index"] = next_index
                    task_state["parameters"] = next_params
                    task_state["retry_from_task_id"] = item["task_id"]
                    task_state["last_error"] = final_payload.get("error")
                    state["tasks"][item["business_id"]] = task_state
                    write_json(state_path, state)
                    append_jsonl(
                        log_path,
                        {
                            "event": "fallback_submitted",
                            "business_id": item["business_id"],
                            "previous_task_id": item["task_id"],
                            "task_id": task_id,
                            "model": next_model,
                            "ts": int(time.time()),
                        },
                    )
                    item["task_id"] = task_id
                    item["submitted_at"] = time.time()
                    next_pending.append(item)
                    continue
                raise RuntimeError(f"视频任务失败: {final_payload}")
            if time.time() - item["submitted_at"] >= max_wait_seconds:
                raise TimeoutError(f"视频任务超时: {item['task_id']}")
            next_pending.append(item)
        pending = next_pending
        if pending:
            time.sleep(8)


def main() -> int:
    parser = argparse.ArgumentParser(description="Huya art platform story media generator.")
    parser.add_argument("--mode", choices=["images", "videos"], required=True)
    parser.add_argument("--config", required=True)
    parser.add_argument("--max-wait-seconds", type=int, default=1800)
    args = parser.parse_args()

    api_key = require_api_key()
    config_path = Path(args.config).resolve()
    if args.mode == "images":
        generate_images(config_path, api_key, args.max_wait_seconds)
    else:
        generate_videos(config_path, api_key, args.max_wait_seconds)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
