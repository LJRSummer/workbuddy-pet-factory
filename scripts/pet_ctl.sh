#!/usr/bin/env bash
# WorkBuddy 桌宠通用启停脚本
# 用法： pet_ctl.sh start|stop|status|restart|list <pet_id>
set -e

PYTHON_BIN="${XIAOZUO_PYTHON:-/opt/miniconda3/bin/python3}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIME="$SCRIPT_DIR/wb_pet_runtime.py"
PETS_ROOT="$HOME/.workbuddy/pets"

pet_dir() { echo "$PETS_ROOT/$1"; }
pid_file() { echo "$(pet_dir "$1")/.runtime/pet.pid"; }
log_file() { echo "$(pet_dir "$1")/.runtime/pet.log"; }

ensure_pyside() {
  "$PYTHON_BIN" -c "import PySide6" 2>/dev/null || {
    echo "[factory] 安装 PySide6 ..."
    "$PYTHON_BIN" -m pip install --quiet PySide6 pyobjc-core pyobjc-framework-Cocoa
  }
}

is_running() {
  local pid_path="$1"
  [ -f "$pid_path" ] || return 1
  local pid; pid=$(cat "$pid_path" 2>/dev/null) || return 1
  [ -n "$pid" ] || return 1
  if ps -p "$pid" -o command= 2>/dev/null | grep -q wb_pet_runtime.py; then
    echo "$pid"; return 0
  fi
  return 1
}

cmd_start() {
  local id="$1"
  [ -n "$id" ] || { echo "需要 pet_id"; exit 2; }
  [ -d "$(pet_dir "$id")" ] || { echo "桌宠不存在: $id（请先 install_pet.py）"; exit 3; }
  ensure_pyside
  local pf; pf=$(pid_file "$id")
  local lf; lf=$(log_file "$id")
  mkdir -p "$(dirname "$pf")"
  if pid=$(is_running "$pf"); then
    echo "[$id] 已在运行 pid=$pid"; return 0
  fi
  rm -f "$pf"
  nohup "$PYTHON_BIN" "$RUNTIME" "$id" >"$lf" 2>&1 &
  local newpid=$!
  echo "$newpid" > "$pf"
  echo "[$id] 已启动 pid=$newpid 日志: $lf"
}

cmd_stop() {
  local id="$1"
  [ -n "$id" ] || { echo "需要 pet_id"; exit 2; }
  local pf; pf=$(pid_file "$id")
  if pid=$(is_running "$pf"); then
    kill "$pid" 2>/dev/null || true
    sleep 0.5
    kill -9 "$pid" 2>/dev/null || true
    rm -f "$pf"
    echo "[$id] 已停止"
  else
    echo "[$id] 未在运行"
    rm -f "$pf"
  fi
}

cmd_status() {
  local id="$1"
  if [ -z "$id" ]; then cmd_list; return; fi
  local pf; pf=$(pid_file "$id")
  if pid=$(is_running "$pf"); then
    echo "[$id] 运行中 pid=$pid"
  else
    echo "[$id] 未运行"
  fi
}

cmd_restart() {
  cmd_stop "$1"; sleep 0.5; cmd_start "$1"
}

cmd_list() {
  [ -d "$PETS_ROOT" ] || { echo "(尚未安装任何桌宠)"; return; }
  for d in "$PETS_ROOT"/*/; do
    [ -d "$d" ] || continue
    id=$(basename "$d")
    pf=$(pid_file "$id")
    if pid=$(is_running "$pf"); then
      echo "● $id  (pid=$pid)"
    else
      echo "○ $id"
    fi
  done
}

case "${1:-}" in
  start)   cmd_start "$2" ;;
  stop)    cmd_stop "$2" ;;
  status)  cmd_status "$2" ;;
  restart) cmd_restart "$2" ;;
  list)    cmd_list ;;
  *)       echo "用法: $0 start|stop|status|restart|list <pet_id>"; exit 2 ;;
esac
