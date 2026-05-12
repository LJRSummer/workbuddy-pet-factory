#!/usr/bin/env python3
"""
WorkBuddy Pet Runtime · 通用桌宠引擎
====================================
从 ~/.workbuddy/pets/<pet_id>/ 加载 pet.json + sprite，启动一只联动 WorkBuddy 的桌宠。

用法：
    python3 wb_pet_runtime.py <pet_id>

pet.json 必填字段：
    id, displayName, spritesheetPath
可选字段（带默认值）：
    frameWidth=192, frameHeight=208, sheetCols=8,
    displayScale=0.85, animFps=8, pollIntervalMs=2000,
    layout={state:[row,count,mode]} 覆盖默认状态布局
"""
from __future__ import annotations

import json
import os
import subprocess
import sqlite3
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from PySide6.QtCore import Qt, QTimer, QPoint, QRect, Signal, QObject
from PySide6.QtGui import (
    QAction,
    QGuiApplication,
    QImage,
    QPainter,
    QPixmap,
)
from PySide6.QtWidgets import QApplication, QMenu, QWidget

HOME = Path.home()
DB_PATH = HOME / ".workbuddy" / "workbuddy.db"
PETS_ROOT = HOME / ".workbuddy" / "pets"

DEFAULT_LAYOUT = {
    "idle":          (0, 6, "loop"),
    "running-right": (1, 8, "loop"),
    "running-left":  (2, 8, "loop"),
    "waving":        (3, 4, "once"),
    "jumping":       (4, 5, "once"),
    "failed":        (5, 8, "loop"),
    "waiting":       (6, 6, "loop"),
    "running":       (7, 6, "loop"),
    "review":        (8, 6, "loop"),
}

WB_STATUS_TO_ANIM = {
    "working":   "running",
    "Pending":   "waiting",
    "Completed": "jumping",
    "completed": "jumping",
    "Failed":    "review",
}


@dataclass
class PetConfig:
    pet_id: str
    display_name: str
    pet_dir: Path
    sprite_path: Path
    frame_w: int
    frame_h: int
    sheet_cols: int
    display_scale: float
    anim_fps: int
    poll_interval_ms: int
    layout: dict

    @classmethod
    def load(cls, pet_id: str) -> "PetConfig":
        pet_dir = PETS_ROOT / pet_id
        cfg_path = pet_dir / "pet.json"
        if not cfg_path.exists():
            raise FileNotFoundError(f"pet.json not found: {cfg_path}")
        cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
        sprite_rel = cfg.get("spritesheetPath", "spritesheet.webp")
        sprite = pet_dir / sprite_rel
        if not sprite.exists():
            raise FileNotFoundError(f"sprite not found: {sprite}")
        layout = {**DEFAULT_LAYOUT}
        for k, v in (cfg.get("layout") or {}).items():
            if isinstance(v, (list, tuple)) and len(v) == 3:
                layout[k] = (int(v[0]), int(v[1]), str(v[2]))
        return cls(
            pet_id=pet_id,
            display_name=cfg.get("displayName") or pet_id,
            pet_dir=pet_dir,
            sprite_path=sprite,
            frame_w=int(cfg.get("frameWidth", 192)),
            frame_h=int(cfg.get("frameHeight", 208)),
            sheet_cols=int(cfg.get("sheetCols", 8)),
            display_scale=float(cfg.get("displayScale", 0.85)),
            anim_fps=int(cfg.get("animFps", 8)),
            poll_interval_ms=int(cfg.get("pollIntervalMs", 2000)),
            layout=layout,
        )


@dataclass
class WBSnapshot:
    active_status: Optional[str]
    active_session_title: Optional[str]
    has_running_automation: bool
    timestamp: float


class WorkBuddyWatcher(QObject):
    snapshot_changed = Signal(object)

    def __init__(self):
        super().__init__()
        self._last_status: Optional[str] = None
        self._last_auto: bool = False

    def poll(self) -> Optional[WBSnapshot]:
        if not DB_PATH.exists():
            return None
        try:
            conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True, timeout=1.0)
            cur = conn.cursor()
            cutoff = int((time.time() - 60) * 1000)
            cur.execute(
                """
                SELECT id, title, status, updated_at FROM sessions
                WHERE deleted_at IS NULL AND updated_at >= ?
                ORDER BY updated_at DESC LIMIT 1
                """,
                (cutoff,),
            )
            row = cur.fetchone()
            session_id, title, status, _ = row if row else (None, None, None, None)
            cur.execute("SELECT COUNT(*) FROM automation_runtime_state WHERE running=1")
            running_auto = cur.fetchone()[0] > 0
            conn.close()
            return WBSnapshot(status, title, running_auto, time.time())
        except Exception as e:
            print(f"[wb-pet] poll failed: {e}", file=sys.stderr)
            return None

    def tick(self):
        snap = self.poll()
        if snap is None:
            return
        key = (snap.active_status, snap.has_running_automation)
        last_key = (self._last_status, self._last_auto)
        if key != last_key:
            self._last_status = snap.active_status
            self._last_auto = snap.has_running_automation
            self.snapshot_changed.emit(snap)


class SpriteSheet:
    def __init__(self, path: Path, frame_w: int, frame_h: int):
        img = QImage(str(path))
        if img.isNull():
            raise RuntimeError(f"Failed to load spritesheet: {path}")
        self.img = img.convertToFormat(QImage.Format_ARGB32)
        self.fw = frame_w
        self.fh = frame_h
        self._cache: dict[tuple[int, int], QPixmap] = {}

    def frame(self, row: int, col: int) -> QPixmap:
        key = (row, col)
        if key not in self._cache:
            rect = QRect(col * self.fw, row * self.fh, self.fw, self.fh)
            sub = self.img.copy(rect)
            self._cache[key] = QPixmap.fromImage(sub)
        return self._cache[key]


class PetWidget(QWidget):
    def __init__(self, cfg: PetConfig, sheet: SpriteSheet):
        super().__init__()
        self.cfg = cfg
        self.sheet = sheet

        flags = (
            Qt.FramelessWindowHint
            | Qt.WindowStaysOnTopHint
            | Qt.WindowDoesNotAcceptFocus
        )
        self.setWindowFlags(flags)
        self.setAttribute(Qt.WA_TranslucentBackground)
        self.setAttribute(Qt.WA_NoSystemBackground)
        self.setAttribute(Qt.WA_ShowWithoutActivating)
        self.setAttribute(Qt.WA_OpaquePaintEvent, False)
        self.setAttribute(Qt.WA_InputMethodEnabled, False)
        self.setFocusPolicy(Qt.NoFocus)
        self.setAutoFillBackground(False)

        w = int(cfg.frame_w * cfg.display_scale)
        h = int(cfg.frame_h * cfg.display_scale)
        self.resize(w, h)
        # 多桌宠错位摆放：用 pet_id 哈希散到右侧不同高度
        screen = QGuiApplication.primaryScreen().availableGeometry()
        offset = (abs(hash(cfg.pet_id)) % 5) * 60
        x = screen.x() + int(screen.width() * 0.65)
        y = screen.y() + int(screen.height() * 0.45) - offset
        self.move(x, y)
        print(
            f"[wb-pet:{cfg.pet_id}] window {w}x{h} at ({x},{y}) | screen avail="
            f"{screen.x()},{screen.y()} {screen.width()}x{screen.height()}",
            flush=True,
        )

        self.current_state = "waving"
        self._fallback_state = "idle"
        self.frame_idx = 0
        self.last_wb_snapshot: Optional[WBSnapshot] = None
        self._animating = True

        self.anim_timer = QTimer(self)
        self.anim_timer.timeout.connect(self._next_frame)
        self.anim_timer.start(int(1000 / cfg.anim_fps))

        self._drag_origin: Optional[QPoint] = None

        self.watcher = WorkBuddyWatcher()
        self.watcher.snapshot_changed.connect(self._on_wb_changed)
        self.poll_timer = QTimer(self)
        self.poll_timer.timeout.connect(self.watcher.tick)
        self.poll_timer.start(cfg.poll_interval_ms)
        QTimer.singleShot(2500, lambda: self.set_state("idle"))

    def set_state(self, state: str, fallback: str = "idle"):
        if state not in self.cfg.layout:
            return
        if state == self.current_state:
            return
        self.current_state = state
        self._fallback_state = fallback
        self.frame_idx = 0
        self._animating = (state != "idle")
        self.update()

    def _next_frame(self):
        if not self._animating:
            return
        row, count, mode = self.cfg.layout[self.current_state]
        self.frame_idx += 1
        if self.frame_idx >= count:
            if mode == "once":
                self.frame_idx = 0
                self.set_state(self._fallback_state)
                return
            self.frame_idx = 0
        self._maybe_walk_step()
        self.update()

    def _maybe_walk_step(self):
        if self.current_state == "running-right":
            self.move(self.x() + 4, self.y())
        elif self.current_state == "running-left":
            self.move(self.x() - 4, self.y())
        screen = QGuiApplication.primaryScreen().availableGeometry()
        if self.x() + self.width() > screen.right():
            self.set_state("running-left", fallback=self._fallback_state)
        elif self.x() < screen.left():
            self.set_state("running-right", fallback=self._fallback_state)

    def _on_wb_changed(self, snap: WBSnapshot):
        self.last_wb_snapshot = snap
        anim = WB_STATUS_TO_ANIM.get(snap.active_status or "")
        if snap.has_running_automation and not anim:
            anim = "running"
        if anim is None:
            anim = "idle"
        # loop 状态（running/waiting/review/idle）持续展示，直到 WorkBuddy 状态变化；
        # once 状态（jumping/waving）由 _next_frame 播完后自动 fallback。
        # 因此这里直接 set_state 即可，不再加 1.2s 强制切回 idle 的定时器。
        self.set_state(anim, fallback="idle")

    def paintEvent(self, event):
        row, count, _ = self.cfg.layout[self.current_state]
        col = min(self.frame_idx, count - 1)
        pix = self.sheet.frame(row, col)
        painter = QPainter(self)
        painter.setRenderHint(QPainter.SmoothPixmapTransform, True)
        painter.drawPixmap(self.rect(), pix)

    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton:
            self._drag_origin = event.globalPosition().toPoint() - self.frameGeometry().topLeft()
            event.accept()
        elif event.button() == Qt.RightButton:
            self._show_menu(event.globalPosition().toPoint())
            event.accept()

    def mouseMoveEvent(self, event):
        if self._drag_origin is not None and event.buttons() & Qt.LeftButton:
            self.move(event.globalPosition().toPoint() - self._drag_origin)

    def mouseReleaseEvent(self, event):
        self._drag_origin = None

    def mouseDoubleClickEvent(self, event):
        self.set_state("waving", fallback="idle")

    def _list_installed_pets(self) -> list[tuple[str, str]]:
        """返回 [(pet_id, display_name), ...]，按 id 排序。"""
        out = []
        if not PETS_ROOT.exists():
            return out
        for sub in sorted(PETS_ROOT.iterdir()):
            if not sub.is_dir() or sub.name.startswith("."):
                continue
            pid = sub.name
            name = pid
            cfg = sub / "pet.json"
            if cfg.exists():
                try:
                    name = json.loads(cfg.read_text(encoding="utf-8")).get("displayName", pid)
                except Exception:
                    pass
            out.append((pid, name))
        return out

    def _switch_to(self, pet_id: str):
        """调 pet_ctl.sh switch <id>；脚本会停掉当前进程再起目标。"""
        if pet_id == self.cfg.pet_id:
            return
        ctl = Path(__file__).resolve().parent / "pet_ctl.sh"
        try:
            subprocess.Popen(
                ["bash", str(ctl), "switch", pet_id],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except Exception as e:
            print(f"[wb-pet:{self.cfg.pet_id}] switch failed: {e}", flush=True)

    def _show_menu(self, pos):
        menu = QMenu(self)
        menu.addAction(f"🐾 {self.cfg.display_name} ({self.cfg.pet_id})").setEnabled(False)
        title = self.last_wb_snapshot.active_session_title if self.last_wb_snapshot else None
        if title:
            menu.addAction(f"📌 当前会话: {title[:24]}").setEnabled(False)
        status = self.last_wb_snapshot.active_status if self.last_wb_snapshot else "—"
        menu.addAction(f"状态: {status}  →  {self.current_state}").setEnabled(False)
        menu.addSeparator()

        # 切换宠物子菜单
        installed = self._list_installed_pets()
        switch_menu = menu.addMenu("🔄 切换宠物")
        if len(installed) <= 1:
            empty = QAction("（没有其它桌宠，先用 install_pet.py 安装）", self)
            empty.setEnabled(False)
            switch_menu.addAction(empty)
        else:
            for pid, name in installed:
                if pid == self.cfg.pet_id:
                    cur = QAction(f"★ {name}（当前）", self)
                    cur.setEnabled(False)
                    switch_menu.addAction(cur)
                else:
                    act = QAction(f"切到 {name}", self)
                    act.triggered.connect(lambda _=False, p=pid: self._switch_to(p))
                    switch_menu.addAction(act)

        # 手动切动作子菜单
        action_menu = menu.addMenu("🎬 切换动作")
        for state in ["idle", "waving", "jumping", "running", "waiting", "review", "running-right", "running-left", "failed"]:
            act = QAction(state, self)
            act.triggered.connect(lambda _=False, s=state: self.set_state(s, fallback="idle"))
            action_menu.addAction(act)

        menu.addSeparator()
        hide_act = QAction("隐藏 30 秒", self)
        hide_act.triggered.connect(self._hide_temp)
        menu.addAction(hide_act)
        quit_act = QAction("退出", self)
        quit_act.triggered.connect(QApplication.instance().quit)
        menu.addAction(quit_act)
        menu.exec(pos)

    def _hide_temp(self):
        self.hide()
        QTimer.singleShot(30000, self.show)


def runtime_dir(pet_id: str) -> Path:
    d = HOME / ".workbuddy" / "pets" / pet_id / ".runtime"
    d.mkdir(parents=True, exist_ok=True)
    return d


def main():
    if len(sys.argv) < 2:
        print("Usage: wb_pet_runtime.py <pet_id>", file=sys.stderr)
        return 2
    pet_id = sys.argv[1]
    try:
        cfg = PetConfig.load(pet_id)
    except FileNotFoundError as e:
        print(f"[wb-pet] {e}", file=sys.stderr)
        return 3

    rt = runtime_dir(pet_id)
    pid_file = rt / "pet.pid"
    self_pid = os.getpid()
    if pid_file.exists():
        try:
            old_pid = int(pid_file.read_text().strip())
            if old_pid != self_pid:
                os.kill(old_pid, 0)
                print(f"{cfg.display_name} 已在运行 (pid={old_pid})", file=sys.stderr)
                return 0
        except (OSError, ValueError):
            pass
    pid_file.write_text(str(self_pid))

    try:
        app = QApplication(sys.argv)
        app.setQuitOnLastWindowClosed(True)
        if sys.platform == "darwin":
            try:
                from AppKit import NSApp, NSApplicationActivationPolicyAccessory  # type: ignore
                NSApp.setActivationPolicy_(NSApplicationActivationPolicyAccessory)
            except Exception:
                pass

        sheet = SpriteSheet(cfg.sprite_path, cfg.frame_w, cfg.frame_h)
        pet = PetWidget(cfg, sheet)
        pet.show()
        pet.raise_()

        # macOS：NSWindow 配置（不抢焦点 + 切 app 不隐藏 + 关阴影）
        ns_window_ref = None
        if sys.platform == "darwin":
            try:
                from AppKit import (  # type: ignore
                    NSColor,
                    NSWindowCollectionBehaviorCanJoinAllSpaces,
                    NSWindowCollectionBehaviorStationary,
                    NSWindowCollectionBehaviorIgnoresCycle,
                    NSWindowCollectionBehaviorFullScreenAuxiliary,
                    NSStatusWindowLevel,
                )
                import ctypes
                import objc  # type: ignore
                ns_view = objc.objc_object(c_void_p=ctypes.c_void_p(int(pet.winId())))
                ns_window = ns_view.window()
                if ns_window is not None:
                    ns_window.setHasShadow_(False)
                    ns_window.setOpaque_(False)
                    ns_window.setBackgroundColor_(NSColor.clearColor())
                    ns_window.setLevel_(NSStatusWindowLevel)
                    behavior = (
                        NSWindowCollectionBehaviorCanJoinAllSpaces
                        | NSWindowCollectionBehaviorStationary
                        | NSWindowCollectionBehaviorIgnoresCycle
                        | NSWindowCollectionBehaviorFullScreenAuxiliary
                    )
                    ns_window.setCollectionBehavior_(behavior)
                    ns_window.setHidesOnDeactivate_(False)
                    ns_window.setCanHide_(False)
                    ns_window.invalidateShadow()
                    ns_window_ref = ns_window
            except Exception as e:
                print(f"[wb-pet:{pet_id}] NSWindow setup failed: {e}", flush=True)

        def _keep_front():
            if ns_window_ref is not None:
                try:
                    ns_window_ref.orderFrontRegardless()
                    return
                except Exception:
                    pass
            pet.raise_()

        keep_top = QTimer()
        keep_top.timeout.connect(_keep_front)
        keep_top.start(3000)
        print(f"[wb-pet:{pet_id}] visible={pet.isVisible()} geom={pet.geometry()}", flush=True)
        return app.exec()
    finally:
        try:
            pid_file.unlink()
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    sys.exit(main())
