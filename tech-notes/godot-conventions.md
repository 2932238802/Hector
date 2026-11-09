---
status: draft
owner: tech
last-review: 2026-11-09
---

# Godot 约定

## 1. 版本与语言

- **Godot 4.7.2 stable（标准版）**，只写 **GDScript**。
- 本机没有 .NET SDK，**不使用 C#**；`.gitignore` 里的 Mono 段是模板遗留，可忽略。
- 渲染后端：`gl_compatibility`（兼容性优先，不绑定 Vulkan）。
- 窗口：1600×900，`stretch/mode=canvas_items`、`aspect=expand`。

## 2. 目录职责

| 目录 | 放什么 | 不放什么 |
|---|---|---|
| `scenes/` | 可运行场景（当前只有 `main.tscn`） | 临时测试场景 |
| `scripts/core/` | 纯逻辑、RefCounted、可无头实例化 | `Node`、`Control`、`await get_tree()` |
| `scripts/ui/` | Control 节点、绘制、输入 | 数值与规则 |
| `data/` | 只读 JSON 配置（数值、事件文本） | 运行时状态 |
| `tests/` | 无头测试脚本 | 会被游戏加载的资源 |
| `tools/` | 本机开发脚本（PowerShell） | 游戏资源 |
| `doc/` | 设计与技术文档 | 可执行代码 |

## 3. 命名

- 文件与变量：`snake_case`；类：`PascalCase`（`class_name GameState`）。
- 信号：过去式 / 名词短语（`changed`）；方法：动词（`choose_action`、`ready_up`）。
- JSON 键：`snake_case`；事件 id：`<category>_<name>`（如 `enemy_raid`）。
- 中文注释可以，但**标识符一律英文**。

## 4. 场景与 UI

- M0 的 UI 在 `main.gd` 里用代码搭（Theme、Panel、Button、`_draw`）。
- 只有在界面结构**稳定**后才拆 `.tscn`；拆的时候一个界面一个场景，脚本挂根节点。
- 所有文字走 `SystemFont`（Microsoft YaHei 等）以保证中文；不提交字体文件。
- 视觉：纸白底 + 墨黑线，禁止引入彩色贴图（对应 `05-art` 的黑白极简方向）。

## 5. 数据与随机

- 数值只写 `data/*.json`，代码里不出现魔法数字（`GameState` 只读不写回文件）。
- 随机统一用 `GameState.rng`（`RandomNumberGenerator`，显式设置 `seed`）。
- 不要用全局 `randi()` / `randf()`；不要用 `Array.shuffle()`（它走全局 RNG）。
- 任何影响结算的随机都必须在同种子下可复现（冒烟测试会检查事件组）。

## 6. 版本管理

- 不提交 `.godot/`、`*.import`、`build/`、导出产物。
- 提交信息用 `[feat]` / `[fix]` / `[doc]` + 一句话；小步提交。
- 改数值也要走提交，方便回滚与对比。

## 7. 本地入口

```powershell
.\tools\run.ps1              # 启动
.\tools\run.ps1 -Mode test   # 无头测试
```

Godot 不在 PATH 时，设 `$env:GODOT_BIN` 指向 `Godot_v*_console.exe`；
`-Mode test` 必须用 **console 版**，否则拿不到 stdout。
