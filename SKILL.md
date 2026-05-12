---
name: workbuddy-pet-factory
description: WorkBuddy 桌宠工厂 —— 给一张角色图、一个 codex.pet 链接、一条 codex-pets.net 下载 URL、或一份现成的精灵表，就能自动创建一只可联动 WorkBuddy 状态的桌面宠物。当用户说"创建桌宠"、"做一只桌宠"、"用这张图做桌宠"、"从 codex.pet 安装桌宠"、"导入 codex 桌宠 XX"、"装一下 codex-pets.net 上的 XX"、"召唤新桌宠"、"启动 XX 桌宠"、"停止 XX 桌宠"、"切换到 XX 桌宠"、"换成 XX"、"列出所有桌宠"、"桌宠体检/排查"等，或者用户**直接粘贴一条 `curl ... codex-pets.net/api/pets/<id>/download...` 命令**时，使用此 skill 自动完成下载/解压/安装/启动一条龙。从图片生成 sprite 时强制走 hatch-pet 工作流并自动校验，**不接受**本地代码画图作为替代。桌面强制单例，同一时刻只保留一只在跑，start/switch 会自动停掉其它。安装后桌宠会读取 ~/.workbuddy/workbuddy.db 的会话与自动化状态，自动切换挥手/思考/等待/庆祝/沮丧动画，且不抢键盘焦点、切 app 不消失（macOS）。
agent_created: true
version: 0.7.0
---

# WorkBuddy Pet Factory · 桌宠工厂

只要给我一张角色图、一个 codex.pet 链接或一份精灵表，就能产出一只联动 WorkBuddy 的桌宠。

> ⚠️ **当前仅支持 macOS**（依赖 PySide6 + pyobjc 做透明无焦点窗口）。Linux/Windows 暂未适配。

## 触发短语

- 创建桌宠 / 做一只桌宠 / 安装桌宠
- 用这张图做桌宠 / 用 XXX 做桌宠
- 从 codex.pet 安装 / 导入 codex 桌宠 XX / 装一下 codex-pets.net 上的 XX
- 用户直接粘贴 `curl ... codex-pets.net/api/pets/<id>/download...`（**自动触发 import_codex.sh**）
- 启动 XX 桌宠 / 召唤 XX / 让 XX 上班
- 停止 XX 桌宠 / 让 XX 休息 / 收起 XX
- 切换到 XX / 换成 XX / 把桌宠换成 XX / 现在让 XX 出来
- 关掉所有桌宠 / 全部退场
- 列出所有桌宠 / 桌宠列表 / 我有几只桌宠 / 当前是哪只
- 桌宠体检 / 桌宠排查 / 校验桌宠 / 桌宠状态不对
- 删除桌宠 / 卸载桌宠 / 不要 XX 了

## 文件结构

```
~/.workbuddy/skills/workbuddy-pet-factory/
├── SKILL.md
├── scripts/
│   ├── install_pet.py      # 安装/创建（4 种来源 + --auto-hatch / --validate）
│   ├── import_codex.sh     # 一键 codex-pets.net 导入：下载→解压→安装→启动
│   ├── hatch_bridge.sh     # 接 hatch-pet：从参考图 → run dir → 校验 → 搬运 → 启动
│   ├── validate_pet.py     # 校验 sprite（复用 hatch-pet/validate_atlas）
│   ├── wb_pet_runtime.py   # 通用桌宠引擎
│   └── pet_ctl.sh          # 启停/状态/列表/doctor/remove
└── references/
    ├── wb-status-mapping.md   # WorkBuddy DB → 动画映射（权威）
    └── spritesheet-spec.md    # 精灵表硬规格（与 hatch-pet 一致）

桌宠数据放在：
~/.workbuddy/pets/<pet_id>/
├── pet.json                # id / displayName / spritesheetPath / 可选 layout
├── spritesheet.webp        # 9 行 × 8 列，每帧 192×208
├── reference.png?          # --from-image 时落盘的参考图（可选）
└── .runtime/
    ├── pet.pid
    └── pet.log
```

## 安装来源（4 种 + 一键 codex-pets.net）

### ⚡️ 一键导入 codex-pets.net（推荐）

只要用户给了一个 codex-pets.net 上的桌宠 id（或直接粘 curl），就用这个：

```bash
SK=~/.workbuddy/skills/workbuddy-pet-factory/scripts
bash $SK/import_codex.sh <pet_id> [<download_url>] [--name <DisplayName>] [--no-start]

# 示例
bash $SK/import_codex.sh xiaoba                                              # 用默认 URL
bash $SK/import_codex.sh xiaoba "https://codex-pets.net/api/pets/xiaoba/download?v=1778..."
bash $SK/import_codex.sh xiaoba --name "小八"
```

它一键完成：下载 zip → 解压到 `~/.codex/pets/<id>` → `install_pet.py --from-codex` → `pet_ctl.sh start`（同时自动停掉当前其它桌宠）。

> **触发规则**：用户**粘贴 `curl ... codex-pets.net/api/pets/<id>/download...` 命令**或说"装一下 codex-pets.net 上的 XX / 导入 codex 桌宠 XX"时，**直接调 `import_codex.sh <id> <URL>`**，不要分步执行 curl + install。

### 4 种通用来源

```bash
PY=/opt/miniconda3/bin/python3
SK=~/.workbuddy/skills/workbuddy-pet-factory/scripts

# 1) 从 ~/.codex/pets/<id>/ 复制（用户已用 hatch-pet 等做好的）
$PY $SK/install_pet.py --from-codex xiao-zuo --name "小做" --validate

# 2) codex.pet 网站 / 任意 spritesheet 直链
$PY $SK/install_pet.py --from-url https://codex.pet/.../spritesheet.webp \
    --pet-id sunny --name "Sunny" --validate

# 3) 用户已有标准精灵表
$PY $SK/install_pet.py --from-sheet ~/Downloads/my_sheet.png \
    --pet-id mochi --name "Mochi" --frame-w 192 --frame-h 208 --cols 8 --validate

# 4) 一张角色立绘 → 走 hatch-pet 桥接（详见下一节）
$PY $SK/install_pet.py --from-image ~/Pictures/cat.png --pet-id orange --name "橘子"
```

`--validate` 是建议默认开启的开关，会立刻跑 `validate_pet.py` 检查尺寸、透明、cell 占用。

## 从图生 sprite · hatch-pet 桥接（重要）

**硬规则**：从参考图生成 sprite **必须**走 hatch-pet skill 的 `$imagegen` 流程。**禁止**用 Pillow / SVG / canvas / HTML 等本地脚本造像素或拼接 sprite，那样产出的图无法满足 9 行 × 8 列 × 192×208 + 透明 cell 的硬约束，并且会破坏角色一致性。

### 推荐流程

```bash
SK=~/.workbuddy/skills/workbuddy-pet-factory/scripts

# 第一步：落盘参考图，准备 hatch-pet run
bash $SK/hatch_bridge.sh <pet_id> /path/to/reference.png --name "<DisplayName>"
```

`hatch_bridge.sh` 会：
1. 把参考图复制到 `~/.workbuddy/pets/<pet_id>/reference.png`
2. 调 `hatch-pet/scripts/prepare_pet_run.py` 创建 `~/.workbuddy/pets/<pet_id>/.hatch_run/`
3. 打印 `imagegen-jobs.json` 路径并退出，**等待 agent 按 hatch-pet SKILL.md 跑完整工作流**：
   - 用 `$imagegen` 生成 base
   - `record_imagegen_result.py` 入库
   - 9 个行 strip 通过 subagent 生成（**默认必须用 subagent**）
   - `record_imagegen_result.py` 逐个入库
   - `running-left` 视情况镜像 `running-right`
   - `finalize_pet_run.py` 出图

完成后再次运行：

```bash
bash $SK/hatch_bridge.sh <pet_id> --finalize-only
```

桥接会自动：
4. 从 `~/.workbuddy/pets/<pet_id>/.hatch_run/final/` 或 `~/.codex/pets/<pet_id>/` 找产物
5. 调 `validate_pet.py` 校验：**校验失败就停**（不会启动桌宠）
6. 把 sprite 搬到 `~/.workbuddy/pets/<pet_id>/spritesheet.webp` 并清掉 `_needs_sprite`
7. `pet_ctl.sh start <pet_id>`

### 为什么不能本地造图

- 精灵表硬规格在 `references/spritesheet-spec.md`，**任何不达标的 sprite 都会被 `validate_pet.py` 拒绝**
- 9 个状态有不同语义（详见 `references/spritesheet-spec.md`），LLM 不该现场推理动画分镜
- 行/列大小、透明度、cell 完整性、角色一致性这四件事必须由 hatch-pet 的 deterministic + QA 流程保证

### 校验是硬门槛

任何来源的 sprite 在启动前**都应该过校验**：

```bash
$PY $SK/validate_pet.py <pet_id>           # 检查整个 pet 目录
$PY $SK/validate_pet.py --sheet <path>     # 单独校验一张 sprite
$PY $SK/validate_pet.py <pet_id> --strict  # warning 也按错处理
```

输出示例：
```json
{ "ok": true, "format": "WEBP", "width": 1536, "height": 1872, "errors": [], "warnings": [] }
```

**`ok: false` → 不要启动桌宠**，必须重做 sprite 或回退到现成的 codex pet。

## 启停管理

> **单例原则**：桌面同一时刻只保留一只桌宠在跑。`start` / `switch` 会自动把其它的停掉。当前活跃桌宠记录在 `~/.workbuddy/pets/.active`。

```bash
SK=~/.workbuddy/skills/workbuddy-pet-factory/scripts
bash $SK/pet_ctl.sh start    <pet_id>   # 召唤（会先停掉其它）
bash $SK/pet_ctl.sh switch   <pet_id>   # 切换：停当前，起目标（= use）
bash $SK/pet_ctl.sh stop     <pet_id>   # 退场
bash $SK/pet_ctl.sh stop-all            # 所有桌宠全部退场
bash $SK/pet_ctl.sh status   <pet_id>   # 状态
bash $SK/pet_ctl.sh restart  <pet_id>   # 重启
bash $SK/pet_ctl.sh active              # 当前活跃桌宠
bash $SK/pet_ctl.sh list                # 列出所有桌宠（★ = 活跃）
bash $SK/pet_ctl.sh remove   <pet_id>   # 卸载（先 stop 再删目录）
bash $SK/pet_ctl.sh doctor   [pet_id]   # 体检：依赖/db/sprite/进程/日志
```

### 体检（doctor）

排查桌宠不工作时第一时间运行：

```bash
bash $SK/pet_ctl.sh doctor jiyi
```

会依次检查：
1. **运行环境**：Python / PySide6 / pyobjc / Pillow 是否齐
2. **WorkBuddy 数据库**：`~/.workbuddy/workbuddy.db` 是否存在 + 当前 session.status + 自动化运行状态
3. **已安装桌宠**：列表 + 哪只在跑 + 哪只 ★ 活跃
4. **sprite 校验**：跑一遍 `validate_pet.py`，输出 errors/warnings
5. **最近日志**：tail 该桌宠的 `pet.log` 末 10 行

## 精灵表规格（重要）

详见 [`references/spritesheet-spec.md`](references/spritesheet-spec.md)。要点：

- 总尺寸 `1536 × 1872`（8 列 × 9 行，cell `192 × 208`）
- PNG / WebP，**必须含 alpha**
- 行顺序：idle / run-R / run-L / wave / jump / fail / wait / run / review
- unused cell 必须完全透明
- 不同行数/帧数可在 `pet.json.layout` 覆盖

## 联动行为（默认 idle 静止 + 事件驱动）

DB → 动画映射详见 [`references/wb-status-mapping.md`](references/wb-status-mapping.md)。要点：

- `sessions.status='working'` → `running` (loop)
- `sessions.status='Pending'` → `waiting` (loop)
- `sessions.status IN ('Completed','completed')` → `jumping` (once)
- `sessions.status='Failed'` → `review` (loop)
- `automation_runtime_state.running=1` → `running` (loop, 弱信号)
- 其它 → `idle` 静止
- 触发键：`(session_id, status, has_running_automation)`，任一变化才 emit
- **不**用 `updated_at` 做活跃过滤（长 working 会被误过滤）

## macOS 焦点策略（已内置）

- `Frameless | StaysOnTop | WindowDoesNotAcceptFocus` + `WA_ShowWithoutActivating`
- pyobjc 在 NSWindow 上：`setHidesOnDeactivate_(False)` / `setCanHide_(False)` / `setCollectionBehavior_(CanJoinAllSpaces|Stationary|IgnoresCycle|FullScreenAuxiliary)` / `setLevel_(NSStatusWindowLevel)`
- 周期置顶用 `orderFrontRegardless()`（不 activate / 不抢 key）
- `NSApplicationActivationPolicyAccessory` 让进程不进 Dock

## 执行流程（agent 决策树）

收到用户请求时：

1. **安装类**：判断来源
   - 用户给「图片附件 / 本地图片路径」→ **强制走 `hatch_bridge.sh`**：
     - 第一步 `hatch_bridge.sh <pid> <ref>` 准备 run dir
     - 第二步：agent **必须**按 hatch-pet SKILL.md 跑完 imagegen 流程（subagent 生成行 strip → record → finalize）
     - 第三步 `hatch_bridge.sh <pid> --finalize-only` 自动校验+搬运+启动
     - **任何"我用 Pillow / svg / 文本拼一个" 都是违规**
   - 用户给「codex.pet URL / 直链」→ `install_pet.py --from-url ... --validate`
   - 用户给「`~/.codex/pets/<id>` 已存在的 id」→ `install_pet.py --from-codex ... --validate`
   - 用户给「现成精灵表文件」→ `install_pet.py --from-sheet ... --validate`
   - 缺 pet-id 或 name 时基于源文件名/URL 推断，必要时向用户简短确认
   - 安装+校验通过后 `pet_ctl.sh start <pet_id>`

2. **启停/切换类**：
   - "启动/召唤 XX" → `pet_ctl.sh start <id>`（会自动停其它）
   - "切换到 XX / 换成 XX" → `pet_ctl.sh switch <id>`
   - "停止/休息 XX" → `pet_ctl.sh stop <id>`
   - "全部关掉 / 都退下" → `pet_ctl.sh stop-all`
   - "现在是哪只" → `pet_ctl.sh active`
   - "列出所有" → `pet_ctl.sh list`
   - "删除/卸载 XX" → `pet_ctl.sh remove <id>`

3. **故障排查**：
   - 第一时间 `pet_ctl.sh doctor [<id>]`，根据输出对症下药
   - sprite 校验失败 → 检查源文件，必要时重做（图片来源走 hatch_bridge 重生）
   - 状态不联动 → 看 doctor 第 2 步的 db 状态是否符合预期，再看第 5 步日志

## 右键菜单（运行中桌宠）

在任何运行中的桌宠身上点右键，可以：

- **🔄 切换宠物**：自动列出 `~/.workbuddy/pets/` 下所有已安装桌宠
  - ★ 标当前那只（灰掉不可点）
  - 点其它任一项 → 调 `pet_ctl.sh switch <id>` → 当前退场，目标登场
- **🎬 切换动作**：手动测试各种状态动画（idle/waving/jumping/...）
- **隐藏 30 秒** / **退出**

切换宠物**不用打命令**，纯右键就能完成。

## 与既有 hatch-pet / xiaozuo-pet skill 的关系

- **hatch-pet** 负责"从概念/参考图造合规精灵表"（`$imagegen` + 9 行 strip + QA）。pet-factory 通过 `hatch_bridge.sh` 复用它，**不重复造轮子**。
- 旧版 `xiaozuo-pet` 是单只桌宠的硬编码版本，仍可用，但不建议再扩展。
- 新桌宠**一律**通过 `workbuddy-pet-factory` 安装与运行（`pet_ctl.sh start <id>`），数据放 `~/.workbuddy/pets/<id>/`。
- 想把"小做"迁过来：`install_pet.py --from-codex xiao-zuo --name 小做 --validate` 即可。

# WorkBuddy Pet Factory · 桌宠工厂

只要给我一张角色图、一个 codex.pet 链接或一份精灵表，就能产出一只联动 WorkBuddy 的桌宠。

## 触发短语

- 创建桌宠 / 做一只桌宠 / 安装桌宠
- 用这张图做桌宠 / 用 XXX 做桌宠
- 从 codex.pet 安装 / 导入 codex 桌宠 XX / 装一下 codex-pets.net 上的 XX
- 用户直接粘贴 `curl ... codex-pets.net/api/pets/<id>/download...`（**自动触发 import_codex.sh**）
- 启动 XX 桌宠 / 召唤 XX / 让 XX 上班
- 停止 XX 桌宠 / 让 XX 休息 / 收起 XX
- 切换到 XX / 换成 XX / 把桌宠换成 XX / 现在让 XX 出来
- 关掉所有桌宠 / 全部退场
- 列出所有桌宠 / 桌宠列表 / 我有几只桌宠 / 当前是哪只

## 文件结构

```
~/.workbuddy/skills/workbuddy-pet-factory/
├── SKILL.md
├── scripts/
│   ├── install_pet.py      # 安装/创建（4 种来源）
│   ├── import_codex.sh     # 一键 codex-pets.net 导入：下载→解压→安装→启动
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

## 安装来源（4 种 + 一键 codex-pets.net）

### ⚡️ 一键导入 codex-pets.net（推荐）

只要用户给了一个 codex-pets.net 上的桌宠 id（或直接粘 curl），就用这个：

```bash
SK=~/.workbuddy/skills/workbuddy-pet-factory/scripts
bash $SK/import_codex.sh <pet_id> [<download_url>] [--name <DisplayName>] [--no-start]

# 示例
bash $SK/import_codex.sh xiaoba                                              # 用默认 URL
bash $SK/import_codex.sh xiaoba "https://codex-pets.net/api/pets/xiaoba/download?v=1778..."
bash $SK/import_codex.sh xiaoba --name "小八"
```

它一键完成：下载 zip → 解压到 `~/.codex/pets/<id>` → `install_pet.py --from-codex` → `pet_ctl.sh start`（同时自动停掉当前其它桌宠）。

> **触发规则**：用户**粘贴 `curl ... codex-pets.net/api/pets/<id>/download...` 命令**或说"装一下 codex-pets.net 上的 XX / 导入 codex 桌宠 XX"时，**直接调 `import_codex.sh <id> <URL>`**，不要分步执行 curl + install。

### 4 种通用来源

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

> **单例原则**：桌面同一时刻只保留一只桌宠在跑。`start` / `switch` 会自动把其它的停掉。当前活跃桌宠记录在 `~/.workbuddy/pets/.active`。

```bash
SK=~/.workbuddy/skills/workbuddy-pet-factory/scripts
bash $SK/pet_ctl.sh start    <pet_id>   # 召唤（会先停掉其它）
bash $SK/pet_ctl.sh switch   <pet_id>   # 切换：停当前，起目标（= use）
bash $SK/pet_ctl.sh stop     <pet_id>   # 退场
bash $SK/pet_ctl.sh stop-all            # 所有桌宠全部退场
bash $SK/pet_ctl.sh status   <pet_id>   # 状态
bash $SK/pet_ctl.sh restart  <pet_id>   # 重启
bash $SK/pet_ctl.sh active              # 当前活跃桌宠
bash $SK/pet_ctl.sh list                # 列出所有桌宠（★ = 活跃）
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

2. **启停/切换类**：
   - "启动/召唤 XX" → `pet_ctl.sh start <id>`（会自动停其它）
   - "切换到 XX / 换成 XX" → `pet_ctl.sh switch <id>`
   - "停止/休息 XX" → `pet_ctl.sh stop <id>`
   - "全部关掉 / 都退下" → `pet_ctl.sh stop-all`
   - "现在是哪只" → `pet_ctl.sh active`
   - "列出所有" → `pet_ctl.sh list`

3. **故障排查**：读 `~/.workbuddy/pets/<id>/.runtime/pet.log` 末尾 30 行

## 右键菜单（运行中桌宠）

在任何运行中的桌宠身上点右键，可以：

- **🔄 切换宠物**：自动列出 `~/.workbuddy/pets/` 下所有已安装桌宠
  - ★ 标当前那只（灰掉不可点）
  - 点其它任一项 → 调 `pet_ctl.sh switch <id>` → 当前退场，目标登场
- **🎬 切换动作**：手动测试各种状态动画（idle/waving/jumping/...）
- **隐藏 30 秒** / **退出**

切换宠物**不用打命令**，纯右键就能完成。

## 与既有 xiaozuo-pet skill 的关系

- 旧版 `xiaozuo-pet` 是单只桌宠的硬编码版本，仍可用。
- 新桌宠**一律**通过 `workbuddy-pet-factory` 安装与运行（`pet_ctl.sh start <id>`），数据放 `~/.workbuddy/pets/<id>/`。
- 想把"小做"迁过来：`install_pet.py --from-codex xiao-zuo --name 小做` 即可。
