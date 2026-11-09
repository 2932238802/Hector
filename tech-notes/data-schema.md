---
status: draft
owner: tech
last-review: 2026-11-09
---

# 数据 Schema（M2）

> 所有数值都是**原型占位**，不做平衡承诺。JSON 放在 `data/`，游戏只读不写。
> 文档 `doc/02-systems/economy.md` / `time-and-seasons.md` 是规则的唯一来源。

## 1. `data/balance.json`

| 键 | 类型 | 含义 |
|---|---|---|
| `max_health` | int | 巢穴完整度上限 |
| `start.health` | int | 开局完整度 |
| `start.food` | int | 开局食物（唯一资源） |
| `start.workers` | int | 开局工蚁数 |
| `start.nest_level` | int | 开局巢穴等级（当前 2） |
| `start.seed` | string | 开局已种下的种子 id（`seeds.json`） |
| `start.army` | string[] | 开局军队（`units.json` 的 id） |
| `queen.workers_per_turn` | int | 蚁后每回合产工蚁 |
| `heal.per_worker` | float | 每只工蚁每回合的被动恢复量 |
| `heal.cap` | float | 每回合被动恢复上限 |
| `actions.adventure.food_min` / `food_max` | int | 冒险食物收益区间 |
| `actions.adventure.workers_min` / `workers_max` | int | 冒险工蚁消耗区间 |
| `actions.adventure.seed_chance` | float 0–1 | 冒险带回种子的概率 |
| `actions.adventure.seed_pool` | string[] | 冒险可能带回的种子 id |
| `actions.adventure.health` | int | 冒险对完整度的影响（负值） |
| `actions.heal.food_cost` | int | 主动修复的食物消耗 |
| `actions.heal.health` | int | 主动修复量 |
| `actions.expand.exp_threshold` | int[] | 按当前等级索引的经验阈值：`[_, _, L2→L3, L3→L4]` |
| `nest.max_level` | int | 最高等级（当前 4） |
| `nest.fertile_per_ring` | int | 每圈肥沃格数量（当前 3） |
| `army.max_size` | int | 军队上限（当前 7） |
| `army.front` / `army.back` | int | 前 / 后排格数（4 / 3，战斗 v2 用） |
| `recruit.refresh_cost` | int | 刷新一次招募候选的食物成本 |
| `combat.defeat_health` | int | 战斗失败扣的巢穴完整度 |
| `weather.names` | object | 天气 id → 显示名（`clear` 晴 / `rain` 雨 / `cloudy` 多云） |
| `weather.weights` | object[] | 按季节索引的天气权重（4 项，对应春 / 夏 / 秋 / 冬） |
| `weather.effects.<id>.*` | object | 天气效果：`adventure_food` / `adventure_workers` / `adventure_health` / `supply_mult` |
| `season_modifier` | object[] | 按季节索引的修正：`adventure_food` |
| `event_groups_per_turn` | int | 每回合生成几组（3~5） |
| `location` | string | 当前巢穴位置（`locations` 的键） |
| `locations.<id>.name` | string | 位置显示名 |
| `locations.<id>.blocked_dirs` | int[] | 被阻断的方向扇区（0–5），命中则整边缺格 |

> 已删除：`income.*`、`start.stone` / `start.fiber`、`actions.upgrade.*`。

## 2. `data/seeds.json`

```json
{
  "seeds": [
    { "id": "grain_basic", "name": "基础谷种", "kind": "food",
      "period": 3, "yield": 2, "source": "开局", "desc": "…" }
  ]
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | string | 唯一 id |
| `name` | string | 显示名 |
| `kind` | string | `food` / `warspoil`（战果）/ `tool_heal`（恢复完整度） |
| `period` | int | 每多少个**事件**收获一次 |
| `yield` | int | 每次收获的数量 |
| `source` | string | 获取来源（展示用） |
| `desc` | string | 一句话说明 |

- 已种下的种子存 `planted: [{seed_id, q, r, counter}]`；`counter` 每个事件 +1，
  到 `period` 收获并归零。
- 移除 / 替换 / 播种消耗仍 open（Q-065）；原型不消耗食物。

## 3. `data/events.json`

```json
{
  "categories": ["enemy", "self", "creature", "explore", "weather"],
  "events": [
    {
      "id": "enemy_raid",
      "category": "enemy",
      "pressure": true,
      "title": "宿敌来袭",
      "text": "……",
      "battle": "weak",
      "effects": { "food": 3 }
    }
  ]
}
```

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `id` | string | 是 | 唯一，`<category>_<name>` |
| `category` | string | 是 | 必须是 `categories` 里的值 |
| `pressure` | bool | 是 | 是否压力事件（每组至少 1 个） |
| `season` | int | 否 | 0–3 限定季节；缺省 = 全季可用 |
| `title` | string | 是 | 事件名 |
| `text` | string | 是 | 事件描述，一句话 |
| `battle` | string | 否 | 指定 `enemies.json` 的 tier；有该字段则先进战斗 |
| `recruit` | bool | 否 | `true` 时结算后进入招募面板 |
| `effects` | object | 是 | 结算效果，见下 |

`effects` 可用键（都可省略）：

| 键 | 类型 | 说明 |
|---|---|---|
| `health` | int | 巢穴完整度增减，结算后夹在 `[0, max_health]` |
| `food` | int | 食物增减，结算后不低于 0 |
| `workers` | int | 工蚁增减，结算后不低于 0 |
| `seed` | bool / string | `true` 从冒险池随机 1 颗；字符串按 id 给种子 |

> 带 `battle` 的事件，`effects` 只在**战斗胜利**时结算，视为战利品；
> 失败时改为扣 `combat.defeat_health`。

## 4. `data/units.json`

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | string | 兵种 id（当前 8 个一阶共享兵） |
| `name` | string | 显示名（两字） |
| `combat` | bool | 是否能出战 |
| `tag` | string | 定位标签 |
| `tier` | int | 阶级（1 = L2 池；2 = L3；3 = L4） |
| `supply` | int | 每场战斗消耗的食物 |
| `hp` / `atk` | float | 战斗属性，允许 1 位小数；**无防御 / 速度** |
| `ap` | int | 每轮行动点（基础 1） |
| `row` | string | `front` / `back` |
| `cost` | object | 招募成本，键只有 `food` |
| `signature` | string | 签名特性（占位文本，未实现效果） |

## 5. `data/enemies.json`

```json
{
  "tiers": {
    "weak": {
      "name": "弱小敌对势力",
      "units": [
        { "name": "敌兵蚁", "hp": 10, "atk": 2, "ap": 2, "row": "front", "count": 2 }
      ]
    }
  }
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `tiers.<tier>.name` | string | 势力显示名 |
| `tiers.<tier>.units[]` | array | 敌军模板列表 |
| `units[].name` | string | 敌军单位名 |
| `units[].hp` / `atk` / `ap` | number | 属性；防御已删除 |
| `units[].row` | string | `front` / `back`；双方前 4 后 3，超出容量的模板忽略 |
| `units[].count` | int | 该模板生成几个 |

战斗状态（`GameState.battle`，运行时结构，不落盘）：

```text
{
  "player":  { "front": [unit...4], "back": [unit...3] },
  "enemies": { "front": [unit...4], "back": [unit...3] },
  "round": 1,
  "supply": 3,          # 本场实际支付的食物
  "event": {...},       # 战斗胜利后结算 effects
  "result": "win" | "lose" | "ruling"
}
unit = { "name", "hp", "max_hp", "atk", "ap", "max_ap", "shield", "row", "alive" }
```

布阵阶段另有 `deploy_units`：`[{ "unit_id", "name", "row", "supply", "deployed" }]`；
`deploy_supply()` 只累计 `deployed=true` 的单位，再乘天气补给倍率。

## 6. 代码保证的不变量

事件组生成（`EventPool`）：

1. 每组 4 个事件（`GROUP_SIZE`）。
2. 4 个事件类别互不相同。
3. 至少 1 个 `pressure=true`；不足时用同类别压力事件替换。
4. 季节过滤：`season == -1` 或等于当前季节。

时间 / 经济（`GameState`）：

5. 一局 24 回合；`turn_in_season()` 在 1–6 之间；第 24 回合结束 → `WON`。
6. 资源只有 `food`；任何扣减不低于 0。
7. 巢穴完整度夹在 `[0, max_health]`；归零 → `GAME_OVER`。
8. 肥沃格每圈 3 个；`blocked` 格不可播种。
9. 一颗种子只能种在「肥沃 + 未阻断 + 未占用」的格子；种子袋数量与已种数量之和守恒。
10. 种子计数只在事件结算后推进一次（含战斗事件，战后结算一次）。

战斗 / 招募：

11. 军队数量 ≤ `army.max_size`；招募不会超上限。
12. 每场战斗只扣一次补给，且只按 `deployed=true` 的单位累计；战斗结束后军队数量不变（士兵返场）。
13. 战斗失败只扣一次 `defeat_health`，不会把完整度扣成负数。
14. 招募刷新每轮最多一次。
15. 目标合法性：某排有存活单位时，另一排不可被选为目标（双方通用）。
16. 第 6 轮敌方阶段结束仍未分胜负 → `result = "ruling"`，按防守方胜结算且掉落减半。
17. 单位 HP 不跨场：每场从 `units.json` / `enemies.json` 重建，满血开场。

## 7. 校验与演进

- 当前**没有**外部 schema 校验器；字段缺失靠 `Dictionary.get()` 默认值兜底。
- 加字段时：先改本文件 → 再改 `data/*.json` → 最后改 `GameState`。
- 后续新增（系统拍板后再建表）：`relics.json`（虫珀）、`talents.json`（天赋）、
  `recruit_tiers.json`（阶级概率）、`plants.json`（战斗植物）。
