# Spritesheet Spec · 精灵表硬规格

> 这是 pet-factory 引擎能识别的**唯一格式**。和 hatch-pet 完全兼容（hatch-pet 的产物可以直接用）。

## 总体

| 项 | 值 |
|---|---|
| 格式 | **PNG** 或 **WebP**（必须含 alpha 通道） |
| 总尺寸 | **1536 × 1872** 像素 |
| 网格 | **8 列 × 9 行** |
| 每帧 | **192 × 208** 像素 |
| 背景 | **完全透明**（unused cell 必须 alpha=0） |

**禁止**：标签、网格线、装订边、cell 外阴影、额外帧、白底、checkerboard 透明指示。

## 行布局（默认）

| 行 | 状态 | 已用列 | 模式 | 帧节奏（ms） |
|---|---|---|---|---|
| 0 | `idle` | 0–5（6 帧） | loop | 280 / 110 / 110 / 140 / 140 / 320 |
| 1 | `running-right` | 0–7（8 帧） | loop | 120 × 7 + 220 |
| 2 | `running-left` | 0–7（8 帧） | loop | 120 × 7 + 220 |
| 3 | `waving` | 0–3（4 帧） | once | 140 × 3 + 280 |
| 4 | `jumping` | 0–4（5 帧） | once | 140 × 4 + 280 |
| 5 | `failed` | 0–7（8 帧） | loop | 140 × 7 + 240 |
| 6 | `waiting` | 0–5（6 帧） | loop | 150 × 5 + 260 |
| 7 | `running` | 0–5（6 帧） | loop | 120 × 5 + 220 |
| 8 | `review` | 0–5（6 帧） | loop | 150 × 5 + 280 |

每行"已用列"之外的 cell 必须 alpha=0。

## 状态语义（生成 sprite 时务必区分）

- `idle` —— 安静的呼吸/眨眼，**不要走、不要挥手、不要表情大幅变化**
- `running-right` / `running-left` —— **真实奔跑**，方向性步态
- `running` —— **抽象"忙碌中"**，不是真奔跑（不要抬腿、不要前进、不要长步伐）
- `waving` —— 仅靠手/爪 pose，不要画动作线
- `jumping` —— 起跳→空中→落下，**不画落地阴影/灰尘/冲击波**
- `failed` —— 沮丧/沉默，眼泪/小烟雾可贴在身上但不能飘出
- `waiting` —— 比 idle 多一点等待感（看表/小晃动/道具摆动）
- `review` —— 思考/检查，**不加放大镜/纸张/UI 等额外道具**（除非基础形象本身就有）

## pet.json 完整字段

```jsonc
{
  "id": "xiao-zuo",                  // slug，必填，等于目录名
  "displayName": "小做",             // 必填
  "description": "...",              // 选填
  "spritesheetPath": "spritesheet.webp",  // 必填，相对 pet 目录
  "frameWidth": 192,                 // 选填，默认 192
  "frameHeight": 208,                // 选填，默认 208
  "sheetCols": 8,                    // 选填，默认 8
  "pollIntervalMs": 2000,            // 选填，默认 2000
  "layout": {                        // 选填：覆盖默认行布局
    "<state>": [<row>, <frameCount>, "loop"|"once"]
  }
}
```

非默认行数/帧数时，用 `layout` 覆盖，例如：

```jsonc
{
  "layout": {
    "idle":    [0, 4, "loop"],
    "waving":  [1, 6, "once"],
    "running": [2, 8, "loop"]
  }
}
```

## 校验

任何新装的 sprite，**必须** `validate_pet.py <pet_id>` 通过：

- 尺寸 = 1536×1872
- 含 alpha 通道
- 每个 used cell 至少 50 个非透明像素
- 每个 unused cell 必须完全透明
- 不全部不透明（否则就是没扣掉背景）

校验失败 → **不要启动**，必须重做或报错给用户。
