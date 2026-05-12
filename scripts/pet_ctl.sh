#!/usr/bin/env bash
# WorkBuddy 桌宠通用启停脚本（强制单例：桌面同一时刻只有一只）
# 用法： pet_ctl.sh start|stop|status|restart|list|switch|active|stop-all [pet_id]
set -e

PYTHON_BIN="${XIAOZUO_PYTHON:-/opt/miniconda3/bin/python3}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIME="$SCRIPT_DIR/wb_pet_runtime.py"
PETS_ROOT="$HOME/.workbuddy/pets"
ACTIVE_FILE="$PETS_ROOT/.active"

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

stop_all_running() {
  # 把当前所有在跑的桌宠都停掉（保证单例）
  [ -d "$PETS_ROOT" ] || return 0
  for d in "$PETS_ROOT"/*/; do
    [ -d "$d" ] || continue
    local oid; oid=$(basename "$d")
    local opf; opf=$(pid_file "$oid")
    if pid=$(is_running "$opf"); then
      kill "$pid" 2>/dev/null || true
      sleep 0.2
      kill -9 "$pid" 2>/dev/null || true
      rm -f "$opf"
      echo "[$oid] 已停止 (pid=$pid)"
    fi
  done
}

cmd_start() {
  local id="$1"
  [ -n "$id" ] || { echo "需要 pet_id"; exit 2; }
  [ -d "$(pet_dir "$id")" ] || { echo "桌宠不存在: $id（请先 install_pet.py）"; exit 3; }
  ensure_pyside
  local pf; pf=$(pid_file "$id")
  local lf; lf=$(log_file "$id")
  mkdir -p "$(dirname "$pf")" "$PETS_ROOT"

  # 单例：先把其它正在跑的桌宠停掉
  if pid=$(is_running "$pf"); then
    echo "[$id] 已在运行 pid=$pid"
    echo "$id" > "$ACTIVE_FILE"
    return 0
  fi
  stop_all_running

  rm -f "$pf"
  nohup "$PYTHON_BIN" "$RUNTIME" "$id" >"$lf" 2>&1 &
  local newpid=$!
  echo "$newpid" > "$pf"
  echo "$id" > "$ACTIVE_FILE"
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
  # 清理 active 指针
  if [ -f "$ACTIVE_FILE" ] && [ "$(cat "$ACTIVE_FILE" 2>/dev/null)" = "$id" ]; then
    rm -f "$ACTIVE_FILE"
  fi
}

cmd_switch() {
  local id="$1"
  [ -n "$id" ] || { echo "需要 pet_id"; exit 2; }
  [ -d "$(pet_dir "$id")" ] || { echo "桌宠不存在: $id（请先 install_pet.py）"; exit 3; }
  echo "[factory] 切换到 $id ..."
  stop_all_running
  sleep 0.3
  cmd_start "$id"
}

cmd_stop_all() {
  stop_all_running
  rm -f "$ACTIVE_FILE"
  echo "[factory] 所有桌宠已停止"
}

cmd_active() {
  if [ -f "$ACTIVE_FILE" ]; then
    local id; id=$(cat "$ACTIVE_FILE" 2>/dev/null)
    if [ -n "$id" ] && pid=$(is_running "$(pid_file "$id")"); then
      echo "● $id  (pid=$pid)"
    else
      echo "(无活跃桌宠；上次记录: ${id:-空})"
    fi
  else
    echo "(无活跃桌宠)"
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
  local active=""
  [ -f "$ACTIVE_FILE" ] && active=$(cat "$ACTIVE_FILE" 2>/dev/null)
  for d in "$PETS_ROOT"/*/; do
    [ -d "$d" ] || continue
    id=$(basename "$d")
    pf=$(pid_file "$id")
    marker=""
    [ "$id" = "$active" ] && marker=" ★"
    if pid=$(is_running "$pf"); then
      echo "● $id  (pid=$pid)$marker"
    else
      echo "○ $id$marker"
    fi
  done
}

case "${1:-}" in
  start)    cmd_start "$2" ;;
  stop)     cmd_stop "$2" ;;
  status)   cmd_status "$2" ;;
  restart)  cmd_restart "$2" ;;
  list)     cmd_list ;;
  switch|use) cmd_switch "$2" ;;
  active)   cmd_active ;;
  stop-all) cmd_stop_all ;;
  *)        echo "用法: $0 start|stop|switch|restart|status|list|active|stop-all [pet_id]"; exit 2 ;;
esac

