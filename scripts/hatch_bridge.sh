#!/usr/bin/env bash
# WorkBuddy Pet Factory · Hatch Bridge
#
# 把一张参考图通过 hatch-pet skill 生成规范精灵表，校验，搬到 pet 目录，并启动桌宠。
#
# 用法：
#     bash hatch_bridge.sh <pet_id> [reference_image_path] [--name <DisplayName>] [--no-start]
#
# 流程：
#   1) 准备：~/.workbuddy/pets/<pet_id>/ 必须已存在（由 install_pet.py --from-image 创建）
#   2) 调用 hatch-pet 的 prepare_pet_run.py 创建 run dir
#   3) 把 run dir 路径打印出来，提示 agent 调 $imagegen 生成 base + 9 row strips
#   4) 等 hatch-pet finalize 完成（产物在 ~/.codex/pets/<pet_id>/spritesheet.webp）
#   5) validate_pet.py 校验，校验通过才搬到 ~/.workbuddy/pets/<pet_id>/
#   6) 自动启动桌宠（除非 --no-start）
#
# 关键点：本脚本不直接生成图，只做"准备 + 校验 + 搬运"。视觉生成必须由 agent
# 走 hatch-pet skill 的 imagegen 流程，避免本地脚本造图。

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "用法: $0 <pet_id> [reference_image] [--name <DisplayName>] [--no-start]" >&2
  exit 2
fi

PET_ID="$1"; shift || true
REF_IMG=""
DISPLAY_NAME=""
NO_START=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) DISPLAY_NAME="$2"; shift 2 ;;
    --no-start) NO_START=1; shift ;;
    --) shift; break ;;
    -*) echo "未知参数: $1" >&2; exit 2 ;;
    *) REF_IMG="$1"; shift ;;
  esac
done

PY="$(command -v python3 || echo /opt/miniconda3/bin/python3)"
SK_DIR="$HOME/.workbuddy/skills/workbuddy-pet-factory/scripts"
HATCH_DIR="$HOME/.workbuddy/skills/hatch-pet"
PETS_ROOT="$HOME/.workbuddy/pets"
CODEX_PETS="$HOME/.codex/pets"
PET_DIR="$PETS_ROOT/$PET_ID"

if [[ ! -d "$HATCH_DIR" ]]; then
  cat >&2 <<EOF
[bridge] hatch-pet skill 不存在：$HATCH_DIR
[bridge] 请先安装 hatch-pet skill 再用本桥接。
[bridge] 或者：自行准备 1536x1872 精灵表，用：
[bridge]     install_pet.py --from-sheet <sheet.png> --pet-id $PET_ID
EOF
  exit 1
fi

mkdir -p "$PET_DIR"

# 拷贝参考图到 pet 目录（如果给了）
if [[ -n "$REF_IMG" ]]; then
  if [[ ! -f "$REF_IMG" ]]; then
    echo "[bridge] 参考图不存在: $REF_IMG" >&2
    exit 1
  fi
  ext="${REF_IMG##*.}"
  cp "$REF_IMG" "$PET_DIR/reference.${ext,,}"
  echo "[bridge] 参考图已落盘: $PET_DIR/reference.${ext,,}"
fi

REF_PATH="$(ls "$PET_DIR"/reference.* 2>/dev/null | head -1 || true)"

if [[ -z "$REF_PATH" ]]; then
  echo "[bridge] ⚠️  pet 目录无 reference 图，hatch-pet 会走纯文本生成（也可以）。"
fi

RUN_DIR="$HOME/.workbuddy/pets/$PET_ID/.hatch_run"
mkdir -p "$RUN_DIR"

# ---- 第 1 步：准备 hatch-pet run ----
echo
echo "[bridge] 步骤 1/4：准备 hatch-pet run dir..."
PREPARE="$HATCH_DIR/scripts/prepare_pet_run.py"
if [[ ! -f "$PREPARE" ]]; then
  echo "[bridge] 找不到 $PREPARE" >&2
  exit 1
fi

PREPARE_ARGS=(
  --pet-name "${DISPLAY_NAME:-$PET_ID}"
  --output-dir "$RUN_DIR"
  --force
)
if [[ -n "$REF_PATH" ]]; then
  PREPARE_ARGS+=(--reference "$REF_PATH")
fi

"$PY" "$PREPARE" "${PREPARE_ARGS[@]}" || {
  echo "[bridge] hatch-pet prepare_pet_run.py 失败" >&2
  exit 1
}

# ---- 第 2 步：把状态信息打印给 agent ----
cat <<EOF

[bridge] 步骤 2/4：交给 agent 用 hatch-pet skill 生成图。
[bridge] 现在 agent 必须按 hatch-pet 的 SKILL.md 流程：
[bridge]   1. 读 $RUN_DIR/imagegen-jobs.json 看待生成的 job
[bridge]   2. 用 \$imagegen 依次生成 base 和 9 个行 strip
[bridge]   3. 用 record_imagegen_result.py 入库
[bridge]   4. 最后调 finalize_pet_run.py 输出 spritesheet
[bridge]
[bridge] 完成后 spritesheet 会落到：
[bridge]   $CODEX_PETS/${DISPLAY_NAME:-$PET_ID}/spritesheet.webp
[bridge]   或 $RUN_DIR/final/spritesheet.webp
[bridge]
[bridge] 然后再次运行：
[bridge]   bash $0 $PET_ID --finalize-only ${NO_START:+--no-start}
[bridge] 即可校验并搬到 pet 目录。

EOF

if [[ "${1:-}" == "--finalize-only" ]] || [[ -f "$RUN_DIR/final/spritesheet.webp" ]] || [[ -f "$CODEX_PETS/$PET_ID/spritesheet.webp" ]]; then
  : # 进入下一步
else
  echo "[bridge] 当前还没有生成完的精灵表，到这里先停。"
  exit 0
fi

# ---- 第 3 步：找产物 ----
echo "[bridge] 步骤 3/4：定位 hatch-pet 产物..."
SHEET=""
for cand in "$RUN_DIR/final/spritesheet.webp" \
            "$RUN_DIR/final/spritesheet.png" \
            "$CODEX_PETS/$PET_ID/spritesheet.webp" \
            "$CODEX_PETS/$PET_ID/spritesheet.png"; do
  if [[ -f "$cand" ]]; then SHEET="$cand"; break; fi
done

if [[ -z "$SHEET" ]]; then
  echo "[bridge] 找不到 hatch-pet 产物（spritesheet.webp/png）" >&2
  exit 1
fi
echo "[bridge] 找到产物: $SHEET"

# ---- 第 4 步：校验 ----
echo "[bridge] 步骤 4/4：校验 + 搬到 pet 目录..."
if ! "$PY" "$SK_DIR/validate_pet.py" --sheet "$SHEET"; then
  echo "[bridge] ❌ 校验失败！必须重做行/cell。不会启动桌宠。" >&2
  exit 1
fi

cp "$SHEET" "$PET_DIR/spritesheet${SHEET##*.}" 2>/dev/null || \
cp "$SHEET" "$PET_DIR/spritesheet.${SHEET##*.}"
DST_SHEET="$PET_DIR/spritesheet.${SHEET##*.}"

# 写/更新 pet.json
"$PY" - <<PY
import json, pathlib
p = pathlib.Path("$PET_DIR/pet.json")
cfg = {}
if p.exists():
    try: cfg = json.loads(p.read_text(encoding="utf-8"))
    except: cfg = {}
cfg.update({
    "id": "$PET_ID",
    "displayName": "${DISPLAY_NAME:-$PET_ID}",
    "spritesheetPath": pathlib.Path("$DST_SHEET").name,
})
cfg.pop("_needs_sprite", None)
p.write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"[bridge] pet.json 已更新: {p}")
PY

echo "[bridge] ✅ 桌宠 $PET_ID 安装完成: $PET_DIR"

# ---- 第 5 步：启动 ----
if [[ "$NO_START" -eq 0 ]]; then
  echo "[bridge] 启动桌宠..."
  bash "$SK_DIR/pet_ctl.sh" start "$PET_ID"
else
  echo "[bridge] --no-start 已指定，未启动。"
fi
