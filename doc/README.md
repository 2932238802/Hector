# 文档中心（项目代号 Hector；正式名待定，见 Q-019）

> 本目录是《Hector》的**唯一事实来源**。设计、数值、接口、美术、音频都以这里为准。
> 讨论中形成的结论要**实时落盘**；本文件本身也是 living 文档，结构变化时同步更新。

---

## 1. 基本规则

- **文档优先**：文档与实现冲突时，以文档为准；要改设计，先改文档。
- **禁止假设**：文档没写清楚的，登记到 `OPEN-QUESTIONS.md`，不要自行补全。
- **状态标记**：每篇文档头部写 frontmatter：

```yaml
---
status: draft | review | approved | deprecated | living
owner: design | tech | art | audio | narrative | qa
last-review: YYYY-MM-DD
---
```

- `living` 仅用于索引、问题清单、覆盖清单这类持续维护的文件。
- **只按 approved 实现**：draft 只能做原型验证，不作为验收依据。
- **实时更新**：每轮讨论的结论直接写进对应文件；没有对应文件就新建。

---

## 2. `reference/` —— 参考资料区

`doc/reference/` 专门存放**参考资料**，不是游戏成品资产。四类内容：

| 类型 | 建议位置 | 说明 |
|---|---|---|
| 参考图案 | `reference/images/` | 构图、配色、UI、角色、场景、图标、动画节奏等视觉参考 |
| 参考设计思路 | `reference/notes/` | 其他游戏的机制拆解、流程分析、设计笔记 |
| 参考链接 | `reference/links.md` | Steam 页面、文章、视频、论坛帖、设计博客 |
| 第三方文件 | `reference/third-party/` | 第三方素材、字体、音频样本、工具文件 |

### 使用规则

1. **只作参考，不直接进游戏。** 第三方文件默认不可复用；确需使用，必须确认许可证允许商用，并登记到 `09-legal/asset-register.md`。
2. **必须记录出处。** 图片记录来源 URL / 作者 / 用途；链接统一写进 `reference/links.md`；文字笔记放 `reference/notes/`。
3. **命名规范**：`<来源或作者>_<用途>_<序号>.<ext>`，例如 `sts_map_layout_01.png`。
4. **版权敏感内容显式标注**：在文件名或笔记里写「仅参考，不可复用」。
5. **禁止放入**：解包资源、盗版素材、无来源文件。

> 当前 `reference/gi-wrapping-star.png` 直接放在根目录，未按 `reference/images/` 归类；
> 暂不移动（`nest-honeycomb.md` 已引用该路径），后续整理时统一处理。

---

## 3. 文档地图（随讨论增减）

```
doc/
├── README.md              # 本文件：索引 + 规则
├── OPEN-QUESTIONS.md      # 未决问题（唯一登记处）
├── COVERAGE.md            # 完备性覆盖清单
├── reference/             # 参考资料区
├── 00-vision/
│   ├── player-persona.md          # 玩家画像（review）
│   ├── design-summary-2026-11-08.md  # 设计现状总览（draft）
│   ├── concept-ant-colony.md      # 早期概念（deprecated）
│   ├── game-concept-explainer.md  # 已否决方向（deprecated）
│   └── brainstorm-2026-11-08.md   # 头脑风暴存档（deprecated）
├── 01-loop/
│   └── turn-flow.md               # 回合流程（draft）
├── 02-systems/
│   ├── time-and-seasons.md        # 时间与季节
│   ├── economy.md                 # 经济与资源
│   ├── events.md                  # 事件组
│   ├── nest-honeycomb.md          # 巢穴蜂巢
│   └── combat.md                  # 战斗（deferred）
├── 03-content/
│   ├── ant-types.md               # 蚁种/兵种总览（living）
│   ├── species.md                 # 蚁种（英雄层）
│   ├── units.md                   # 兵种（收集层）
│   ├── talent-trees.md            # 天赋树
│   ├── factions.md                # 势力与中立生物
│   └── relics.md                  # 虫珀
└── （待建）
    ├── 04-narrative/              # 世界观、角色、文案
    ├── 05-art/                    # 美术方向、色板、UI
    ├── 06-audio/                  # 音乐、音效
    ├── 07-tech/                   # 架构、schema、Godot 约定
    ├── 08-pipeline/               # 资产管线、本地化、构建
    └── 09-legal/                  # 版权、资产登记、ADR
```

---

## 4. 索引

| 文档 | 状态 | 说明 |
|---|---|---|
| `README.md` | living | 本文件 |
| `OPEN-QUESTIONS.md` | living | 未决问题 |
| `COVERAGE.md` | living | 完备性覆盖清单 |
| `reference/` | living | 参考资料 |
| `00-vision/player-persona.md` | review | 玩家画像与设计含义 |
| `00-vision/design-summary-2026-11-08.md` | draft | 设计现状总览：已定 / 待定 / 下一步 |
| `00-vision/concept-ant-colony.md` | deprecated | 早期概念草案 |
| `00-vision/game-concept-explainer.md` | deprecated | 阵线 / 织命（否决） |
| `00-vision/brainstorm-2026-11-08.md` | deprecated | 六方向头脑风暴存档 |
| `01-loop/turn-flow.md` | draft | 收入 + 蚁后产工蚁 + 工蚁恢复巢穴健康 + 三选一 + 事件组 |
| `02-systems/time-and-seasons.md` | draft | 四季连玩、40 决策、季节特性、默认天气 |
| `02-systems/economy.md` | draft | 食物 / 石头 / 纤维；生产单位；战斗损耗食物；季节修正；种子产出；战粮 |
| `02-systems/events.md` | draft | 事件组 N 选 1；组内 A→D 四事件；季节特性；种子探索；招募事件 |
| `02-systems/nest-honeycomb.md` | draft | 中心六边形 + 外圈；位置可阻断扩展；种子播种 |
| `02-systems/combat.md` | draft | 前5后4 + 手动 AP + 蚁穴外战斗 + 准备就绪；战粮；季节/天气修正 |
| `03-content/ant-types.md` | living | 蚁种/兵种总览 |
| `03-content/species.md` | draft | 5 个蚁种候选 |
| `03-content/units.md` | draft | 兵种 + 食物为主招募（事件触发）+ 战粮 |
| `03-content/talent-trees.md` | draft | 天赋树（结构未定） |
| `03-content/factions.md` | draft | 中立 / 弱小 / 强大 |
| `03-content/relics.md` | draft | 虫珀 |

> 新文档建立后，必须在这里补一行。

---

## 5. 当前进度

- [x] 仓库恢复到 WSL2
- [x] 文档区入口与 `reference/` 规范
- [x] 未决问题 / 覆盖清单骨架
- [x] 核心概念：蚁群战争
- [x] 时间结构：四季连玩（4 大回合 × 10 决策）
- [x] 回合流程（初稿：收入 / 三选一 / 事件组）
- [x] 经济、事件、巢穴、蚁种、兵种、天赋、势力、虫珀 初稿
- [x] 战斗（初稿）
- [x] 经济闭环：战斗损耗食物 + 工蚁恢复巢穴健康
- [x] 季节特性与默认天气
- [x] 种子系统（替代地势探索）；招募改为事件触发
- [x] 战斗保持手动 AP；战粮（强化食物）
- [ ] 人口 / 卵 / 幼虫成长
- [ ] 巢穴外圈格子内容
- [ ] 胜负条件与局外成长
- [ ] 技术架构与数据 schema
- [ ] 美术 / 音频
- [ ] 合规与资产登记
