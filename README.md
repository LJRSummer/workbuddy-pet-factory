# workbuddy-pet-factory

WorkBuddy 桌宠工厂 —— 给一张角色图、一个 [codex.pet](https://codex.pet) 链接、或一份现成的精灵表，就能自动创建一只可联动 WorkBuddy 状态的桌面宠物（macOS）。

## 特性

- 4 种安装来源：`--from-codex` / `--from-url` / `--from-sheet` / `--from-image`
- 通用引擎 `wb_pet_runtime.py`，按 `pet.json` 读规格（frame size / cols / fps / layout / scale）
- 多只桌宠按 `pet_id` 隔离 pid / log（`~/.workbuddy/pets/<id>/.runtime/`）
- macOS 焦点策略修复：
  - 不抢键盘 IME（不会打断输入法）
  - 切 app / 点击桌面不消失（NSStatusWindowLevel + setHidesOnDeactivate_(False)）
  - 无白底框（关 NSWindow shadow + 透明 background）
  - 进程不进 Dock（NSApplicationActivationPolicyAccessory）
- 自动安装 PySide6 / pyobjc 依赖

## 安装到 WorkBuddy

```bash
unzip workbuddy-pet-factory.zip -d ~/.workbuddy/skills/
```

然后在 WorkBuddy 里说：

> 用 codex.pet 上的 xiao-zuo 做一只桌宠

或：

> 启动小做桌宠 / 停止小做桌宠 / 列出所有桌宠

## 命令行直接用

```bash
# 从 codex.pet 安装
python3 scripts/install_pet.py --from-codex xiao-zuo --name 小做

# 从精灵表安装
python3 scripts/install_pet.py --from-sheet ./my-sheet.webp --pet-id mycat --name 喵酱

# 从单张图（落占位 + 参考图，需后续用 hatch-pet 生成精灵表）
python3 scripts/install_pet.py --from-image ./avatar.png --pet-id newpet --name 新宠

# 启停
./scripts/pet_ctl.sh start xiao-zuo
./scripts/pet_ctl.sh stop xiao-zuo
./scripts/pet_ctl.sh list
```

## 精灵表规范

- 总尺寸建议 1536×1872
- 布局 9 行 × 8 列，每帧 192×208
- 行顺序：idle / blink / running-right / running-left / waiting / thinking / celebrate / sad / wave
- 可在 `pet.json` 的 `layout` 字段里覆盖默认行映射

## 许可证

MIT
