#!/usr/bin/env python3
"""
WorkBuddy Pet Factory · 精灵表校验

针对 ~/.workbuddy/pets/<pet_id>/ 做全面检查：
1. pet.json 字段完整
2. spritesheet 文件存在
3. 复用 hatch-pet 的 validate_atlas（如果可用），否则用本地实现做基本检查
4. 输出结构化 JSON，0 = 通过，1 = 失败

用法：
    python3 validate_pet.py <pet_id> [--strict]
    python3 validate_pet.py --sheet /path/to/sheet.webp [--strict]
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

HOME = Path.home()
PETS_ROOT = HOME / ".workbuddy" / "pets"
HATCH_VALIDATE = HOME / ".workbuddy" / "skills" / "hatch-pet" / "scripts" / "validate_atlas.py"

DEFAULT_LAYOUT = {
    0: ("idle", 6),
    1: ("running-right", 8),
    2: ("running-left", 8),
    3: ("waving", 4),
    4: ("jumping", 5),
    5: ("failed", 8),
    6: ("waiting", 6),
    7: ("running", 6),
    8: ("review", 6),
}
ATLAS_W, ATLAS_H = 1536, 1872
CELL_W, CELL_H = 192, 208
COLS, ROWS = 8, 9


def _validate_with_hatch(sheet: Path) -> dict:
    """优先用 hatch-pet 的官方校验脚本。"""
    try:
        result = subprocess.run(
            [sys.executable, str(HATCH_VALIDATE), str(sheet),
             "--allow-near-opaque-used-cells"],
            capture_output=True, text=True, timeout=30,
        )
        if result.stdout.strip():
            return json.loads(result.stdout)
    except Exception as exc:
        return {"ok": False, "errors": [f"hatch validate failed: {exc}"]}
    return {"ok": False, "errors": ["hatch validate produced no output"]}


def _validate_local(sheet: Path) -> dict:
    """本地实现，hatch-pet 不可用时兜底。"""
    try:
        from PIL import Image
    except ImportError:
        return {"ok": False, "errors": ["Pillow not installed; pip install Pillow"]}

    errors, warnings = [], []
    try:
        with Image.open(sheet) as im:
            fmt = im.format
            mode = im.mode
            img = im.convert("RGBA")
    except Exception as exc:
        return {"ok": False, "errors": [f"open failed: {exc}"]}

    if img.size != (ATLAS_W, ATLAS_H):
        errors.append(f"expected {ATLAS_W}x{ATLAS_H}, got {img.width}x{img.height}")
    if fmt not in {"PNG", "WEBP"}:
        errors.append(f"expected PNG/WEBP, got {fmt}")

    alpha = img.getchannel("A")
    total_alpha = sum(alpha.histogram()[1:])
    if total_alpha == ATLAS_W * ATLAS_H:
        errors.append("atlas is fully opaque (transparent background required)")

    near_opaque = defaultdict(list)
    for r in range(ROWS):
        state, used_cols = DEFAULT_LAYOUT.get(r, (f"row{r}", 0))
        for c in range(COLS):
            box = (c * CELL_W, r * CELL_H, (c + 1) * CELL_W, (r + 1) * CELL_H)
            cell = img.crop(box)
            cnt = sum(cell.getchannel("A").histogram()[1:])
            used = c < used_cols
            if used and cnt < 50:
                errors.append(f"{state} row {r} col {c} too sparse ({cnt} px)")
            if used and cnt > CELL_W * CELL_H * 0.95:
                near_opaque[f"{state} row {r}"].append(c)
            if not used and cnt != 0:
                errors.append(f"{state} row {r} unused col {c} not transparent ({cnt} px)")

    for k, v in near_opaque.items():
        warnings.append(f"{k}: {len(v)} near-opaque cells (may have leftover background)")

    return {
        "ok": not errors,
        "file": str(sheet),
        "format": fmt,
        "mode": mode,
        "width": img.width,
        "height": img.height,
        "errors": errors,
        "warnings": warnings,
    }


def validate_sheet(sheet: Path) -> dict:
    if not sheet.exists():
        return {"ok": False, "errors": [f"sprite file not found: {sheet}"]}
    if HATCH_VALIDATE.exists():
        return _validate_with_hatch(sheet)
    return _validate_local(sheet)


def validate_pet(pet_id: str) -> dict:
    pet_dir = PETS_ROOT / pet_id
    if not pet_dir.exists():
        return {"ok": False, "errors": [f"pet not found: {pet_dir}"]}

    pet_json = pet_dir / "pet.json"
    if not pet_json.exists():
        return {"ok": False, "errors": [f"pet.json missing: {pet_json}"]}

    try:
        cfg = json.loads(pet_json.read_text(encoding="utf-8"))
    except Exception as exc:
        return {"ok": False, "errors": [f"pet.json invalid JSON: {exc}"]}

    errors = []
    for k in ("id", "displayName", "spritesheetPath"):
        if not cfg.get(k):
            errors.append(f"pet.json missing required field: {k}")

    if cfg.get("_needs_sprite"):
        errors.append("pet.json has _needs_sprite=true — sprite hasn't been generated yet")

    sprite_path = pet_dir / cfg.get("spritesheetPath", "")
    if errors:
        return {"ok": False, "errors": errors, "config": cfg}

    sheet_result = validate_sheet(sprite_path)
    sheet_result["pet_id"] = pet_id
    sheet_result["pet_json"] = cfg
    if not sheet_result.get("ok"):
        sheet_result["errors"] = errors + (sheet_result.get("errors") or [])
    return sheet_result


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("pet_id", nargs="?", help="安装好的桌宠 id")
    g.add_argument("--sheet", help="直接校验某个 sprite 文件")
    ap.add_argument("--strict", action="store_true", help="warning 也按 fail 处理")
    args = ap.parse_args()

    if args.sheet:
        result = validate_sheet(Path(args.sheet).expanduser())
    else:
        result = validate_pet(args.pet_id)

    if args.strict and result.get("warnings"):
        result["ok"] = False
        result["errors"] = (result.get("errors") or []) + [
            f"strict mode: {len(result['warnings'])} warnings treated as errors"
        ]

    print(json.dumps(result, ensure_ascii=False, indent=2))
    sys.exit(0 if result.get("ok") else 1)


if __name__ == "__main__":
    main()
