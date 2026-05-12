# WorkBuddy DB → 桌宠动画映射

> 这是 `wb_pet_runtime.py` 的**唯一权威来源**。任何对状态判定/映射的改动必须先改这里。

## 数据库

`~/.workbuddy/workbuddy.db`（SQLite，wb_pet_runtime 用 `uri=True&mode=ro` 只读连接）

## 表与字段

### `sessions`

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | TEXT | 会话 id（唯一）。**桌宠用它判定"是否同一场对话"，不同 id 即使 status 相同也会触发动画** |
| `title` | TEXT | 会话标题 |
| `status` | TEXT | **核心字段**。值见下表 |
| `updated_at` | INT | 最后交互时间戳。**注意：用户停止操作但 agent 还在 working 时，updated_at 不会刷新**。**不要用它做活跃窗口过滤** |
| `deleted_at` | INT? | 非 NULL = 已删除会话，必须排除 |

最新一条 = `WHERE deleted_at IS NULL ORDER BY updated_at DESC LIMIT 1`。

### `sessions.status` 全枚举

| 值 | 含义 | 桌宠映射 | 动画类型 |
|---|---|---|---|
| `Pending` | 等待用户输入 | `waiting` | loop（持续） |
| `working` | Agent 正在执行 | `running` | loop（持续） |
| `Completed` | 任务成功完成 | `jumping` | once（一次性庆祝） |
| `completed` | 同上（小写） | `jumping` | once |
| `Failed` | 任务失败 | `review` | loop（持续） |

**坑点**：大小写混用（`Completed` vs `completed`）是历史遗留，必须两个都识别。

### `automation_runtime_state`

| 字段 | 说明 |
|---|---|
| `automation_id` | 自动化任务 id |
| `running` | 1 = 当前正在跑，0 = 空闲 |

桌宠判定：`SELECT 1 FROM automation_runtime_state WHERE running=1 LIMIT 1` → 只要有一个在跑，就给个短暂 `running` 提示。

## 状态优先级

同时命中时按 sessions.status 优先，automation 次之：

```
Completed/completed → jumping (once)
Failed              → review  (loop)
working             → running (loop)
Pending             → waiting (loop)
automation.running  → running (loop, 弱信号)
其它/无数据         → idle
```

## 触发规则（已写进 wb_pet_runtime.py）

`WorkBuddyWatcher.tick()` 用 `(session_id, status, has_running_automation)` 作为对比键：
- 键变化 → emit 一次新 snap → `_on_wb_changed` 调 `set_state(animation, fallback="idle")`
- `set_state` 对 loop 状态会一直循环播放，直到 DB 的状态键再次改变；对 once 状态播一次自动回 idle

## 历史 bug 教训

1. **不要用 `updated_at > now-60s` 做活跃过滤**：长 working 会被过滤掉 → status=None → 桌宠回 idle
2. **不要在 `_on_wb_changed` 里加 `QTimer.singleShot(1200, → idle)`**：会让 working 桌宠 1.2 秒就闪回 idle
3. **必须把 session_id 算进对比键**：否则切到同状态的不同会话不会触发动画

## SQL 速查

```sql
-- 当前最新会话
SELECT id, title, status, updated_at FROM sessions
WHERE deleted_at IS NULL ORDER BY updated_at DESC LIMIT 1;

-- 是否有自动化在跑
SELECT EXISTS(SELECT 1 FROM automation_runtime_state WHERE running=1);

-- 看 status 枚举值
SELECT DISTINCT status FROM sessions;
```
