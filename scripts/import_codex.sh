#!/usr/bin/env bash
# import_codex.sh —— 一键把 codex-pets.net 的桌宠导入到 WorkBuddy 工厂
# 用法：
#   bash import_codex.sh <pet_id> [<download_url>] [--name <DisplayName>] [--no-start]
#   bash import_codex.sh xiaoba "https://codex-pets.net/api/pets/xiaoba/download?v=1778..."
#   bash import_codex.sh xiaoba                                # 用默认 URL（无版本戳）
#
# 流程：下载 zip → 解压到 ~/.codex/pets/<id> → 工厂 install_pet.py --from-codex → pet_ctl.sh start
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "用法: import_codex.sh <pet_id> [<download_url>] [--name <DisplayName>] [--no-start]" >&2
  exit 2
fi

PET_ID="$1"; shift
URL=""
NAME=""
START=1

# 第一个剩余位置参数若不是 --，视为 URL
if [[ $# -gt 0 && "$1" != --* ]]; then
  URL="$1"; shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --no-start) START=0; shift ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$URL" ]]; then
  URL="https://codex-pets.net/api/pets/${PET_ID}/download"
fi

CODEX_DIR="$HOME/.codex/pets/$PET_ID"
ZIP_PATH="/tmp/${PET_ID}.codex-pet.zip"
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PY=$(command -v python3 || echo /opt/miniconda3/bin/python3)

echo "[import-codex] ↓ 下载 $URL"
curl -fsSL "$URL" -o "$ZIP_PATH"

echo "[import-codex] 📦 解压到 $CODEX_DIR"
mkdir -p "$CODEX_DIR"
unzip -oq "$ZIP_PATH" -d "$CODEX_DIR"

echo "[import-codex] 🏭 工厂安装"
INSTALL_ARGS=( --from-codex "$PET_ID" )
[[ -n "$NAME" ]] && INSTALL_ARGS+=( --name "$NAME" )
"$PY" "$SCRIPTS_DIR/install_pet.py" "${INSTALL_ARGS[@]}"

if [[ "$START" == "1" ]]; then
  echo "[import-codex] 🚀 启动 $PET_ID（会停掉当前其它桌宠）"
  bash "$SCRIPTS_DIR/pet_ctl.sh" start "$PET_ID"
else
  echo "[import-codex] ✅ 已安装。手动启动：bash $SCRIPTS_DIR/pet_ctl.sh start $PET_ID"
fi
