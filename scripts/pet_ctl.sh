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

cmd_remove() {
  local id="$1"
  [ -n "$id" ] || { echo "需要 pet_id"; exit 2; }
  local d; d=$(pet_dir "$id")
  [ -d "$d" ] || { echo "[$id] 不存在"; exit 3; }
  # 先停掉
  if pid=$(is_running "$(pid_file "$id")"); then
    cmd_stop "$id"
  fi
  rm -rf "$d"
  if [ -f "$ACTIVE_FILE" ] && [ "$(cat "$ACTIVE_FILE" 2>/dev/null)" = "$id" ]; then
    rm -f "$ACTIVE_FILE"
  fi
  echo "[$id] 已删除"
}

cmd_doctor() {
  # 体检：依赖 / 数据库 / 桌宠目录 / sprite / 进程 / 日志
  local id="${1:-}"
  echo "===== WorkBuddy Pet Factory · Doctor ====="
  echo
  echo "[1/5] 运行环境"
  echo "  Python: $PYTHON_BIN"
  if "$PYTHON_BIN" -c "import PySide6, sys; print('   PySide6:', PySide6.__version__)" 2>/dev/null; then :; else
    echo "  ⚠️  PySide6 未安装"
  fi
  if [ "$(uname -s)" = "Darwin" ]; then
    if "$PYTHON_BIN" -c "import objc, AppKit" 2>/dev/null; then
      echo "   pyobjc:  ok"
    else
      echo "  ⚠️  pyobjc 未安装（macOS 焦点策略需要）"
    fi
  fi
  if "$PYTHON_BIN" -c "from PIL import Image" 2>/dev/null; then
    echo "   Pillow:  ok"
  else
    echo "  ⚠️  Pillow 未安装（校验需要）"
  fi

  echo
  echo "[2/5] WorkBuddy 数据库"
  local db="$HOME/.workbuddy/workbuddy.db"
  if [ -f "$db" ]; then
    echo "  $db ($(stat -f%z "$db" 2>/dev/null || stat -c%s "$db") bytes)"
    if command -v sqlite3 >/dev/null; then
      sqlite3 "$db" "SELECT '   最新 session: ' || COALESCE(status,'?') || '  id=' || COALESCE(id,'?') FROM sessions WHERE deleted_at IS NULL ORDER BY updated_at DESC LIMIT 1;" 2>/dev/null
      sqlite3 "$db" "SELECT '   自动化在跑: ' || COALESCE(SUM(running),0) FROM automation_runtime_state;" 2>/dev/null
    fi
  else
    echo "  ⚠️  数据库不存在，桌宠状态联动会失效"
  fi

  echo
  echo "[3/5] 已安装桌宠"
  if [ -d "$PETS_ROOT" ]; then
    cmd_list | sed 's/^/  /'
  else
    echo "  (无)"
  fi

  echo
  echo "[4/5] 校验"
  if [ -n "$id" ]; then
    "$PYTHON_BIN" "$SCRIPT_DIR/validate_pet.py" "$id" 2>&1 | sed 's/^/  /' || true
  else
    if [ -d "$PETS_ROOT" ]; then
      for d in "$PETS_ROOT"/*/; do
        [ -d "$d" ] || continue
        local pid; pid=$(basename "$d")
        echo "  --- $pid ---"
        "$PYTHON_BIN" "$SCRIPT_DIR/validate_pet.py" "$pid" 2>&1 | grep -E '"ok"|"errors"|"warnings"' | sed 's/^/    /' || true
      done
    fi
  fi

  echo
  echo "[5/5] 最近日志"
  if [ -n "$id" ]; then
    local lf; lf=$(log_file "$id")
    if [ -f "$lf" ]; then
      tail -n 10 "$lf" | sed 's/^/  /'
    else
      echo "  (无 $id 日志)"
    fi
  else
    echo "  指定 pet_id 才显示日志：bash $0 doctor <pet_id>"
  fi
  echo
  echo "===== 完成 ====="
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
  remove|rm|uninstall) cmd_remove "$2" ;;
  doctor|check) cmd_doctor "$2" ;;
  *)        echo "用法: $0 start|stop|switch|restart|status|list|active|stop-all|remove|doctor [pet_id]"; exit 2 ;;
esac

