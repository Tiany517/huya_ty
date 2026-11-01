import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any, Dict, Iterable


CAMERA_EFFECTS = {
    "推镜头", "缓慢推进", "急速推进", "拉镜头", "逐渐拉远",
    "左摇", "右摇", "横移", "跟随镜头", "跟拍", "环绕镜头",
    "360度旋转", "升镜头", "降镜头", "俯冲", "希区柯克变焦",
    "一镜到底", "手持晃动",
}
CAMERA_CONFLICTS = [
    ({"推镜头", "缓慢推进", "急速推进"}, {"拉镜头", "逐渐拉远"}),
    ({"环绕镜头", "360度旋转"}, {"固定特写"}),
    ({"一镜到底"}, {"跳切", "转场"}),
]


class ValidationError(ValueError):
    pass


def load(path: Path) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValidationError(f"JSON 根对象必须是 object: {path}")
    return value


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationError(message)


def validate_structure(path: Path) -> Dict[str, Any]:
    data = load(path)
    recognition = data.get("recognition", {})
    require(recognition.get("status") == "passed", "产品结构识别未通过")
    require(recognition.get("source_asset_ids"), "结构识别缺少 source_asset_ids")
    require(data.get("components"), "结构识别缺少 components")
    require(data.get("must_keep"), "结构识别缺少 must_keep")
    require(data.get("must_not_change"), "结构识别缺少 must_not_change")
    installation = data.get("installation", {})
    if installation.get("required"):
        require(installation.get("attached_to"), "安装产品缺少 attached_to")
        require(installation.get("orientation"), "安装产品缺少 orientation")
        require(installation.get("water_or_motion_path"), "安装产品缺少 water_or_motion_path")
    return data


def validate_manifest(path: Path, root: Path) -> Dict[str, Dict[str, Any]]:
    data = load(path)
    assets = data.get("assets")
    require(isinstance(assets, list) and assets, "素材清单缺少 assets")
    by_id: Dict[str, Dict[str, Any]] = {}
    for asset in assets:
        require(isinstance(asset, dict), "素材条目必须是 object")
        asset_id = asset.get("asset_id")
        rel_path = asset.get("path")
        require(isinstance(asset_id, str) and asset_id, "素材缺少 asset_id")
        require(asset_id not in by_id, f"重复 asset_id: {asset_id}")
        require(isinstance(rel_path, str) and rel_path, f"素材缺少 path: {asset_id}")
        file_path = root / rel_path
        require(file_path.is_file(), f"素材文件不存在: {file_path}")
        if asset.get("source_of_truth"):
            require(asset.get("kind") == "source", f"source_of_truth 必须是 source 素材: {asset_id}")
        if asset.get("kind") == "actual_last_frame":
            require(not asset.get("source_of_truth"), f"actual_last_frame 不能是 source_of_truth: {asset_id}")
            if asset.get("usable_as_previous_ref"):
                require(asset.get("qa_status") == "passed", f"未通过 QA 的末帧不能进入链路: {asset_id}")
        by_id[asset_id] = asset
    return by_id


def validate_bindings(bindings: Iterable[str], manifest: Dict[str, Dict[str, Any]]) -> None:
    for asset_id in bindings:
        require(asset_id in manifest, f"引用了不存在的 asset_id: {asset_id}")


def validate_camera(camera: Dict[str, Any], item_name: str) -> None:
    if not camera:
        return
    keywords = set(camera.get("camera_keywords", []))
    unknown = keywords - CAMERA_EFFECTS
    require(not unknown, f"未知运镜关键词 {unknown}: {item_name}")
    require(camera.get("camera_effect") in CAMERA_EFFECTS, f"缺少有效 camera_effect: {item_name}")
    require(camera.get("camera_subject"), f"缺少 camera_subject: {item_name}")
    require(camera.get("camera_amplitude"), f"缺少 camera_amplitude: {item_name}")
    require(camera.get("camera_duration"), f"缺少 camera_duration: {item_name}")
    for left, right in CAMERA_CONFLICTS:
        require(not (keywords & left and keywords & right), f"冲突运镜关键词: {item_name}")


def validate_plan(structure_path: Path, manifest_path: Path, plan_path: Path) -> None:
    structure = validate_structure(structure_path)
    manifest = validate_manifest(manifest_path, manifest_path.parent.parent)
    plan = load(plan_path)
    require(structure.get("recognition", {}).get("status") == "passed", "结构识别未通过")
    for item in plan.get("shots", []) + plan.get("video_tasks", []):
        bindings = item.get("reference_bindings", {})
        all_refs = []
        for key in ("canonical_product_refs", "installation_refs", "scene_anchor_refs", "presenter_anchor_refs", "previous_shot_refs", "actual_last_frame_refs"):
            values = bindings.get(key, [])
            all_refs.extend(values if isinstance(values, list) else [values])
        validate_bindings([ref for ref in all_refs if ref], manifest)
        validate_camera(item.get("camera", {}), item.get("shot_id") or item.get("client_business_id") or "unnamed")
        if item.get("inheritance_mode") == "strict":
            require(bindings.get("canonical_product_refs"), f"strict 镜头缺少 canonical refs: {item.get('shot_id') or item.get('client_business_id')}")
    print(json.dumps({"status": "passed", "assets": len(manifest), "plan": str(plan_path)}, ensure_ascii=False))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--structure", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--plan", type=Path)
    args = parser.parse_args()
    try:
        if args.plan:
            validate_plan(args.structure, args.manifest, args.plan)
        else:
            validate_structure(args.structure)
            manifest = validate_manifest(args.manifest, args.manifest.parent.parent)
            print(json.dumps({"status": "passed", "assets": len(manifest)}, ensure_ascii=False))
        return 0
    except (OSError, json.JSONDecodeError, ValidationError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
