---
name: workbuddy-pet-factory
description: WorkBuddy 桌宠工厂 —— 给一张角色图、一个 codex.pet 链接、或一份现成的精灵表，就能自动创建一只可联动 WorkBuddy 状态的桌面宠物。当用户说"创建桌宠"、"做一只桌宠"、"用这张图做桌宠"、"从 codex.pet 安装桌宠"、"召唤新桌宠"、"启动 XX 桌宠"、"停止 XX 桌宠"、"列出所有桌宠"等，使用此 skill 安装/启停/管理桌宠。安装后桌宠会读取 ~/.workbuddy/workbuddy.db 的会话与自动化状态，自动切换挥手/思考/等待/庆祝/沮丧动画，且不抢键盘焦点、切 app 不消失（macOS）。
agent_created: true
---

# WorkBuddy Pet Factory · 桌宠工厂

只要给我一张角色图、一个 codex.pet 链接或一份精灵表，就能产出一只联动 WorkBuddy 的桌宠。

## 触发短语

- 创建桌宠 / 做一只桌宠 / 安装桌宠
- 用这张图做桌宠 / 用 XXX 做桌宠
- 从 codex.pet 安装 / 导入 codex 桌宠 XX
- 启动 XX 桌宠 / 召唤 XX / 让 XX 上班
- 停止 XX 桌宠 / 让 XX 休息 / 收起 XX
- 列出所有桌宠 / 桌宠列表 / 我有几只桌宠

## 文件结构

```
~/.workbuddy/skills/workbuddy-pet-factory/
├── SKILL.md
├── scripts/
│   ├── install_pet.py      # 安装/创建（4 种来源）
│   ├── wb_pet_runtime.py   # 通用桌宠引擎
│   └── pet_ctl.sh          # 启停/状态/列表
└── references/             # 设计参考

桌宠数据放在：
~/.workbuddy/pets/<pet_id>/
├── pet.json                # id / displayName / spritesheetPath / 可选 layout
├── spritesheet.webp        # 9 行 × 8 列，每帧 192×208
└── .runtime/
    ├── pet.pid
    └── pet.log
```

## 安装来源（4 种）

```bash
PY=/opt/miniconda3/bin/python3
SK=~/.workbuddy/skills/workbuddy-pet-factory/scripts

# 1) 从 ~/.codex/pets/<id>/ 复制（用户已用 hatch-pet 等做好的）
$PY $SK/install_pet.py --from-codex xiao-zuo --name "小做"

# 2) codex.pet 网站 / 任意 spritesheet 直链
$PY $SK/install_pet.py --from-url https://codex.pet/.../spritesheet.webp \
    --pet-id sunny --name "Sunny"

# 3) 用户已有标准精灵表
$PY $SK/install_pet.py --from-sheet ~/Downloads/my_sheet.png \
    --pet-id mochi --name "Mochi" --frame-w 192 --frame-h 208 --cols 8

# 4) 一张角色立绘（需后续用 hatch-pet 工作流生成 sprite）
$PY $SK/install_pet.py --from-image ~/Pictures/cat.png --pet-id orange --name "橘子"
# install_pet.py 会把图片放进 ~/.workbuddy/pets/<id>/reference.png
# 然后 agent 必须调用 hatch-pet skill，按规格生成 spritesheet.webp 写到 pet 目录
```

## 启停管理

```bash
SK=~/.workbuddy/skills/workbuddy-pet-factory/scripts
bash $SK/pet_ctl.sh start   <pet_id>   # 召唤
bash $SK/pet_ctl.sh stop    <pet_id>   # 退场
bash $SK/pet_ctl.sh status  <pet_id>   # 状态
bash $SK/pet_ctl.sh restart <pet_id>   # 重启
bash $SK/pet_ctl.sh list               # 列出所有桌宠及运行状态
```

## 精灵表规格（重要）

- 总尺寸：1536×1872（9 行 × 8 列，每帧 192×208）
- 行顺序（默认布局）：
  | 行 | 状态 | 帧数 | 模式 |
  |---|---|---|---|
  | 0 | idle | 6 | loop（默认静止只画第 1 帧） |
  | 1 | running-right | 8 | loop |
  | 2 | running-left | 8 | loop |
  | 3 | waving | 4 | once |
  | 4 | jumping | 5 | once |
  | 5 | failed | 8 | loop |
  | 6 | waiting | 6 | loop |
  | 7 | running | 6 | loop |
  | 8 | review | 6 | loop |

- 不同行数/帧数的精灵表可在 `pet.json` 的 `layout` 字段覆盖：
  ```json
  {
    "layout": {
      "idle": [0, 4, "loop"],
      "waving": [1, 6, "once"]
    }
  }
  ```

## 联动行为（默认 idle 静止 + 事件驱动）

- 每 `pollIntervalMs`（默认 2000ms）读 `~/.workbuddy/workbuddy.db`：
  - `sessions.status='working'` → 短暂 `running` 后回 idle
  - `sessions.status='Pending'` → 短暂 `waiting` 后回 idle
  - `sessions.status IN ('Completed','completed')` → 一次 `jumping` 庆祝
  - `sessions.status='Failed'` → 短暂 `review` 后回 idle
  - `automation_runtime_state.running=1` → 短暂 `running` 后回 idle
- 闲置时**整体静止**，不抢键盘、不打断输入

## macOS 焦点策略（已内置）

- `Frameless | StaysOnTop | WindowDoesNotAcceptFocus` + `WA_ShowWithoutActivating`
- 启动后通过 pyobjc 在 NSWindow 上：`setHidesOnDeactivate_(False)` / `setCanHide_(False)` / `setCollectionBehavior_(CanJoinAllSpaces|Stationary|IgnoresCycle|FullScreenAuxiliary)` / `setLevel_(NSStatusWindowLevel)`
- 周期置顶用 `orderFrontRegardless()`（不 activate / 不抢 key）
- `NSApplicationActivationPolicyAccessory` 让进程不进 Dock

## 执行流程（agent 决策树）

收到用户请求时：

1. **安装类**：判断来源
   - 用户给了「图片附件 / 本地图片路径」→ 走 `--from-image`，**之后 agent 必须**调用 `hatch-pet` skill 把规格化精灵表写入 `~/.workbuddy/pets/<id>/spritesheet.webp`，然后从 `pet.json` 删掉 `_needs_sprite` 字段。
   - 用户给了「codex.pet URL / 直链」→ 走 `--from-url`
   - 用户给了「`~/.codex/pets/<id>` 已存在的 id」→ 走 `--from-codex`
   - 用户给了「现成精灵表文件」→ 走 `--from-sheet`
   - 缺 pet-id 或 name 时基于源文件名/URL 推断，必要时向用户简短确认
   - 安装成功后**直接** `pet_ctl.sh start <pet_id>`，告知用户位置和启停命令

2. **启停类**：
   - "启动/召唤 XX" → `pet_ctl.sh start <id>`
   - "停止/休息 XX" → `pet_ctl.sh stop <id>`
   - "列出所有" → `pet_ctl.sh list`

3. **故障排查**：读 `~/.workbuddy/pets/<id>/.runtime/pet.log` 末尾 30 行

## 与既有 xiaozuo-pet skill 的关系

- 旧版 `xiaozuo-pet` 是单只桌宠的硬编码版本，仍可用。
- 新桌宠**一律**通过 `workbuddy-pet-factory` 安装与运行（`pet_ctl.sh start <id>`），数据放 `~/.workbuddy/pets/<id>/`。
- 想把"小做"迁过来：`install_pet.py --from-codex xiao-zuo --name 小做` 即可。
