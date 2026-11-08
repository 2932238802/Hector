---
status: living
owner: qa
last-review: 2026-11-08
---

# COVERAGE —— 文档完备性覆盖清单

> 验证方式：**只做覆盖清单**。
> 目标：每个系统、每条数值、每类资产都能在文档里找到出处；开发 Agent 读完不需要假设。
> 用法：新建/修改文档后更新此表；`approved` 才能打勾。

## 状态图例

- `—` 未开始
- `draft` 有草稿
- `deferred` 已明确暂缓
- `approved` 可据此实现
- `n/a` 本期不做

---

## A. 概念与范围

| 项 | 文档 | 状态 | 备注 |
|---|---|---|---|
| 玩家画像 / 核心快感 | `00-vision/player-persona.md` | review | 已有；待升级 approved |
| 设计现状总览 | `00-vision/design-summary-2026-11-08.md` | draft | 一页汇总；随讨论更新 |
| 一句话概念 / 类型 / 目标玩家 | `00-vision/game-concept.md` | — | 未建 |
| 设计支柱（不可妥协原则） | `00-vision/design-pillars.md` | — | 未建 |
| v1.0 范围与非目标 | `00-vision/scope-v1.md` | — | 未建 |
| 参考作品与差异化 | `00-vision/references.md` | — | 未建 |

## B. 循环与成长

| 项 | 文档 | 状态 | 备注 |
|---|---|---|---|
| 核心循环（局内 / 局外） | `01-loop/core-loop.md` | — | 未建 |
| 回合流程（收入 / 三选一 / 事件组） | `01-loop/turn-flow.md` | draft | 收入 / 生产周期 / 三选一 / 事件组 / 工蚁恢复巢穴健康 |
| 一局的结构与时长 | `02-systems/time-and-seasons.md` | draft | 四季连玩、40 决策、季节特性、默认天气 |
| 局内成长曲线 | `01-loop/in-run-progression.md` | — | 未建（天赋/兵种散落各文档） |
| 局外解锁与难度阶梯 | `01-loop/meta-progression.md` | — | 未建 |

## C. 系统

| 项 | 文档 | 状态 | 备注 |
|---|---|---|---|
| 战斗规则 | `02-systems/combat.md` | draft | 前5后4 + 手动 AP + 蚁穴外战斗 + 准备就绪；士兵失败返场；战斗损耗食物；战粮；季节/天气修正 |
| 兵种与部署 | `03-content/units.md` | draft | 食物为主招募（事件触发）；士兵持久且不饿死；工蚁不能出战；战粮 |
| 巢穴 / 空间 | `02-systems/nest-honeycomb.md` | draft | 中心 + 外圈；位置可阻断扩展；种子播种（替代地势） |
| 经济与资源 | `02-systems/economy.md` | draft | 食物 / 石头 / 纤维；生产周期以事件计；战斗损耗食物；季节修正；种子产出；战粮 |
| 随机事件 | `02-systems/events.md` | draft | N 选 1；组内 A→D 四事件；季节特性；种子探索；招募事件 |
| 时间与季节 | `02-systems/time-and-seasons.md` | draft | 四季连玩；季节特性；默认天气 |
| 难度与 Boss | `02-systems/difficulty-boss.md` | — | 未建 |

## D. 内容

| 项 | 文档 | 状态 | 备注 |
|---|---|---|---|
| 内容总量与清单 | `03-content/content-matrix.md` | — | 未建 |
| 蚁种 | `03-content/species.md` | draft | 5 个候选 |
| 兵种数值表 | `03-content/units.md` | draft | 共享 6 + 专属 |
| 天赋树 | `03-content/talent-trees.md` | draft | 结构未定；点数已定 |
| 势力 / 中立生物 | `03-content/factions.md` | draft | 中立 / 弱 / 强；敌对基本不可避免 |
| 虫珀 | `03-content/relics.md` | draft | 遗物类物品 |
| 敌人与 Boss 数值表 | `03-content/enemies.md` | — | 未建 |
| 建筑 / 设施 / 道具 | `03-content/structures-items.md` | — | 未建 |
| 事件文本 | `03-content/events-text.md` | — | 未建 |

## E. 叙事

| 项 | 文档 | 状态 | 备注 |
|---|---|---|---|
| 世界观 | `04-narrative/world.md` | — | 未建 |
| 角色设定 | `04-narrative/characters.md` | — | 未建 |
| 文案语气与命名规范 | `04-narrative/tone-style.md` | — | 未建 |

## F. 美术

| 项 | 文档 | 状态 | 备注 |
|---|---|---|---|
| 美术方向与参考 | `05-art/art-direction.md` | — | 未建；初步倾向黑白极简 |
| 色板与字体 | `05-art/palette-typography.md` | — | 未建 |
| UI 布局与交互规格 | `05-art/ui-spec.md` | — | 未建 |
| 资产清单（尺寸/命名/导出） | `05-art/asset-list.md` | — | 未建 |
| 动画与特效规格 | `05-art/animation-vfx.md` | — | 未建 |

## G. 音频

| 项 | 文档 | 状态 | 备注 |
|---|---|---|---|
| 音乐方向与参考 | `06-audio/music-direction.md` | — | 未建 |
| 曲目清单 | `06-audio/music-list.md` | — | 未建 |
| 音效清单 | `06-audio/sfx-list.md` | — | 未建 |

## H. 技术

| 项 | 文档 | 状态 | 备注 |
|---|---|---|---|
| 代码架构与分层 | `07-tech/architecture.md` | — | 未建 |
| 数据 schema（单位/敌人/事件等） | `07-tech/data-schema.md` | — | 未建 |
| Godot 目录与命名约定 | `07-tech/godot-conventions.md` | — | 未建 |
| 随机与可复现 | `07-tech/rng.md` | — | 未建 |
| 存档格式与迁移 | `07-tech/save-format.md` | — | 未建 |
| 本地化 | `07-tech/localization.md` | — | 未建 |
| 测试策略 | `07-tech/testing.md` | — | 未建 |
| 构建与导出 | `07-tech/build-release.md` | — | 未建 |

## I. 合规

| 项 | 文档 | 状态 | 备注 |
|---|---|---|---|
| 版权自查 | `09-legal/ip-clearance.md` | — | 未建 |
| 资产来源登记 | `09-legal/asset-register.md` | — | 未建 |
| 设计决策记录（ADR） | `09-legal/decision-log.md` | — | 未建 |

---

## 完备性判定

一份文档算 `approved`，必须同时满足：

1. 规则完整：能回答"是什么、怎么算、边界情况"。
2. 数值有出处：所有数字在文档或 `data/` 里，不依赖实现者猜测。
3. 依赖明确：引用了哪些其他文档/数据。
4. 验收标准：能写出对应测试或检查项。
