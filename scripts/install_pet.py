#!/usr/bin/env python3
"""
WorkBuddy Pet Factory · 安装/创建桌宠

支持三种来源：
1. --from-codex <pet_id>     从 ~/.codex/pets/<pet_id>/ 复制（已通过 hatch-pet 等生成的）
2. --from-codex-url <url>    从 codex.pet 站点直链下载 spritesheet + pet.json
3. --from-sheet <path>       用户已有的标准精灵表（9行×8列，每帧默认 192×208）
4. --from-image <path>       一张角色立绘 → 提示用户用 hatch-pet 工作流生成 9 状态精灵表

成功后产出：
    ~/.workbuddy/pets/<pet_id>/
        pet.json
        spritesheet.webp
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
import urllib.request
from pathlib import Path

HOME = Path.home()
PETS_ROOT = HOME / ".workbuddy" / "pets"
CODEX_PETS = HOME / ".codex" / "pets"


def slugify(name: str) -> str:
    s = re.sub(r"[^a-zA-Z0-9\-]+", "-", name.strip().lower()).strip("-")
    return s or "pet"


def write_pet_json(target_dir: Path, pet_id: str, display_name: str, sprite_name: str,
                    description: str = "", extra: dict | None = None):
    cfg = {
        "id": pet_id,
        "displayName": display_name,
        "description": description,
        "spritesheetPath": sprite_name,
    }
    if extra:
        cfg.update(extra)
    (target_dir / "pet.json").write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8")


def install_from_codex(pet_id: str, display_name: str | None) -> Path:
    src = CODEX_PETS / pet_id
    if not src.exists():
        raise FileNotFoundError(f"~/.codex/pets/{pet_id} 不存在")
    sprite_src = None
    for cand in ("spritesheet.webp", "spritesheet.png"):
        if (src / cand).exists():
            sprite_src = src / cand
            break
    if sprite_src is None:
        raise FileNotFoundError(f"找不到 spritesheet：{src}")
    src_cfg = {}
    if (src / "pet.json").exists():
        try:
            src_cfg = json.loads((src / "pet.json").read_text(encoding="utf-8"))
        except Exception:
            src_cfg = {}
    target = PETS_ROOT / pet_id
    target.mkdir(parents=True, exist_ok=True)
    dst_sprite = target / sprite_src.name
    shutil.copy2(sprite_src, dst_sprite)
    write_pet_json(
        target, pet_id,
        display_name or src_cfg.get("displayName") or pet_id,
        dst_sprite.name,
        src_cfg.get("description", ""),
    )
    return target


def install_from_url(url: str, pet_id: str | None, display_name: str | None) -> Path:
    """url 可以是 spritesheet 直链，或 codex.pet 的某种 pet 资源地址。"""
    pid = pet_id or slugify(url.rsplit("/", 1)[-1].rsplit(".", 1)[0] or "pet")
    target = PETS_ROOT / pid
    target.mkdir(parents=True, exist_ok=True)
    # 简单处理：把 url 当 sprite 直链
    ext = "webp" if url.lower().endswith(".webp") else ("png" if url.lower().endswith(".png") else "webp")
    sprite_path = target / f"spritesheet.{ext}"
    print(f"[factory] downloading {url} -> {sprite_path}")
    with urllib.request.urlopen(url, timeout=30) as resp:
        sprite_path.write_bytes(resp.read())
    write_pet_json(target, pid, display_name or pid, sprite_path.name,
                   description=f"Imported from {url}")
    return target


def install_from_sheet(sheet_path: Path, pet_id: str | None, display_name: str | None,
                        frame_w: int, frame_h: int, sheet_cols: int) -> Path:
    if not sheet_path.exists():
        raise FileNotFoundError(sheet_path)
    pid = pet_id or slugify(sheet_path.stem)
    target = PETS_ROOT / pid
    target.mkdir(parents=True, exist_ok=True)
    dst = target / f"spritesheet{sheet_path.suffix.lower()}"
    shutil.copy2(sheet_path, dst)
    extra = {"frameWidth": frame_w, "frameHeight": frame_h, "sheetCols": sheet_cols}
    write_pet_json(target, pid, display_name or pid, dst.name,
                   description=f"From sheet {sheet_path.name}", extra=extra)
    return target


def install_from_image(image_path: Path, pet_id: str | None, display_name: str | None) -> Path:
    """图片来源：仅落盘资料，提示调用方用 hatch-pet 工作流生成 spritesheet。"""
    if not image_path.exists():
        raise FileNotFoundError(image_path)
    pid = pet_id or slugify(image_path.stem)
    target = PETS_ROOT / pid
    target.mkdir(parents=True, exist_ok=True)
    ref = target / f"reference{image_path.suffix.lower()}"
    shutil.copy2(image_path, ref)
    # 写一个待生成 sprite 的 pet.json 占位
    write_pet_json(target, pid, display_name or pid, "spritesheet.webp",
                   description=f"Pending sprite generation from {ref.name}",
                   extra={"_needs_sprite": True})
    print("\n[factory] 已保存参考图：", ref)
    print("[factory] 接下来需要由 agent 调用 hatch-pet skill 生成 9 状态精灵表：")
    print(f"           输出路径必须为：{target / 'spritesheet.webp'}")
    print("           规格：9 行 × 8 列，每帧 192×208，总尺寸 1536×1872")
    print("           状态顺序：idle / run-R / run-L / wave / jump / fail / wait / run / review")
    return target


def main():
    ap = argparse.ArgumentParser(description="安装 WorkBuddy 桌宠")
    ap.add_argument("--pet-id", help="桌宠 ID（slug，缺省由源推断）")
    ap.add_argument("--name", help="显示名（缺省同 pet-id）")
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--from-codex", help="从 ~/.codex/pets/<id>/ 复制")
    src.add_argument("--from-url", help="从 codex.pet 或任意直链下载 spritesheet")
    src.add_argument("--from-sheet", help="已有精灵表文件路径")
    src.add_argument("--from-image", help="一张角色立绘（需配合 hatch-pet 后续生成 sprite）")
    ap.add_argument("--frame-w", type=int, default=192)
    ap.add_argument("--frame-h", type=int, default=208)
    ap.add_argument("--cols", type=int, default=8)
    args = ap.parse_args()

    if args.from_codex:
        target = install_from_codex(args.from_codex, args.name)
    elif args.from_url:
        target = install_from_url(args.from_url, args.pet_id, args.name)
    elif args.from_sheet:
        target = install_from_sheet(Path(args.from_sheet).expanduser(),
                                     args.pet_id, args.name,
                                     args.frame_w, args.frame_h, args.cols)
    elif args.from_image:
        target = install_from_image(Path(args.from_image).expanduser(),
                                     args.pet_id, args.name)
    else:
        ap.error("must specify a source")
        return 2

    print(f"\n[factory] ✅ 桌宠已安装到 {target}")
    print(f"[factory] 启动：bash {Path(__file__).parent / 'pet_ctl.sh'} start {target.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
