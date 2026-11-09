---
status: draft
owner: tech
last-review: 2026-11-09
---

# 数据 Schema（M7 无工蚁 / L1 对齐）

> 所有数值都是**原型占位**，不做平衡承诺。JSON 放在 `data/`，游戏只读不写。
> 文档 `doc/02-systems/economy.md` / `time-and-seasons.md` 是规则的唯一来源。

## 1. `data/balance.json`

| 键 | 类型 | 含义 |
|---|---|---|
| `max_health` | int | 巢穴完整度上限 |
| `start.health` | int | 开局完整度（切片 100） |
| `start.food` | int | 开局食物（唯一资源） |
| `start.nest_level` | int | 开局巢穴等级（当前 1） |
| `start.seed` | string | 开局已种下的种子 id（`seeds.json`） |
| `start.free_recruits` | int | 开局免费招募次数（当前 2，3 选 1） |
| `spring.production_bonus` | int | 春季食物型种子每次额外产出 |
| `spring.enemy_scale` | float | 春季敌人 HP / 攻击倍率 |
| `spring.explore_food_loss` | int | 春季探索食物额外损失 |
| `actions.adventure.food_cost_min` / `food_cost_max` | int | 冒险食物代价区间 |
| `actions.adventure.food_min` / `food_max` | int | 冒险食物收益区间 |
| `actions.adventure.seed_chance` | float 0–1 | 冒险带回种子的概率 |
| `actions.adventure.seed_pool` | string[] | 冒险可能带回的种子 id |
| `actions.adventure.health` | int | 冒险对完整度的影响（负值） |
| `actions.heal.food_cost` | int | 主动修复的食物消耗 |
| `actions.heal.health` | int | 主动修复量 |
| `actions.expand.exp_threshold` | int[] | 按当前等级索引的经验阈值：`[_, L1→L2, L2→L3]`（20 / 30） |
| `nest.max_level` | int | 最高等级（当前 3） |
| `nest.fertile_per_ring` | int | 每圈肥沃格数量（当前 3） |
| `army.max_size` | int | 军队上限（当前 7） |
| `army.front` / `army.back` | int | 前 / 后排格数（4 / 3，战斗 v2 用） |
| `recruit.refresh_cost` | int | 刷新一次招募候选的食物成本 |
| `recruit.candidates` | int | 每次招募生成几个候选（当前 3） |
| `recruit.tier_rates` | object | 按巢穴等级（`"1"` / `"2"` / `"3"`）的各阶权重，如 `[[1,60],[2,40]]` |
| `combat.defeat_health` | int | 战斗失败扣的巢穴完整度 |
| `combat.verdict_round` | int | 第几轮结束触发最终裁决（6） |
| `combat.rewards.<tier>` | object | 战斗胜利奖励：`food` 区间 / `warfruits` 概率 / `amber` 概率；tier 为 `sand` / `resin` / `nest` / `bird` |
| `weather.names` | object | 天气 id → 显示名（`clear` 晴 / `rain` 雨 / `cloudy` 多云） |
| `weather.weights` | object[] | 按季节索引的天气权重（4 项，对应春 / 夏 / 秋 / 冬） |
| `weather.effects.<id>.*` | object | 天气效果：`adventure_food` / `explore_food_loss` / `adventure_health` / `production_bonus` |
| `season_modifier` | object[] | 按季节索引的修正：`adventure_food` |
| `event_groups_per_turn` | int | 每回合生成几组（3~5） |
| `location` | string | 当前巢穴位置（`locations` 的键） |
| `locations.<id>.name` | string | 位置显示名 |
| `locations.<id>.blocked_dirs` | int[] | 被阻断的方向扇区（0–5），命中则整边缺格 |

> 已删除：`income.*`、`start.stone` / `start.fiber`、`actions.upgrade.*`；
> 2026-11-09 又删除 `start.workers` / `start.army` / `queen.*` / `upkeep.*` / `heal.*`。
> 所有 `data/*.json` 顶层必须有 `"schema_version": 1`，缺失或非法时加载报错。

## 2. `data/seeds.json`

```json
{
  "schema_version": 1,
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
  "categories": ["enemy_weak", "enemy_strong", "explore", "random", "recruit", "relic"],
  "events": [
    {
      "id": "enemy_raid",
      "category": "enemy_weak",
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
| `category` | string | 是 | 6 类之一：`enemy_weak` / `enemy_strong` / `explore` / `random` / `recruit` / `relic` |
| `pressure` | bool | 是 | 是否压力事件（每组至少 1 个） |
| `season` | int | 否 | 0–3 限定季节；缺省 = 全季可用 |
| `title` | string | 是 | 事件名 |
| `text` | string | 是 | 事件描述，一句话 |
| `battle` | string | 否 | 指定 `enemies.json` 的 tier；有该字段则先让玩家选迎战 / 谈判 / 回避 |
| `recruit` | bool | 否 | `true` 时结算后进入招募面板 |
| `effects` | object | 是 | 结算效果，见下 |

> 敌对事件不再自动开战：`ready_up()` 只提示选择，必须调用
> `choose_encounter("fight" / "talk" / "avoid")`。谈判扣 2 食物、回避免费，均为占位（Q-084）。

## 3.5 `data/event_templates.json`

```json
{
  "templates": [
    { "id": "patrol", "name": "巡逻组", "slots": ["enemy_weak", "explore", "random", "random"], "crisis": false, "relic": false }
  ],
  "season_weights": {
    "0": { "patrol": 35, "expedition": 20, "elite": 15, "crisis": 10, "relic": 10, "recruit": 10 }
  }
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `templates[].id` / `name` | string | 模板 id / 显示名（巡逻组等 6 种） |
| `templates[].slots` | string[] | 4 个类别槽位，顺序即组内事件顺序 |
| `templates[].crisis` | bool | 是否危机组（本轮最多 1 个） |
| `templates[].relic` | bool | 是否含遗迹（本轮最多 1 个） |
| `season_weights.<0-3>.<id>` | int | 按季节的模板权重 |

`effects` 可用键（都可省略）：

| 键 | 类型 | 说明 |
|---|---|---|
| `health` | int | 巢穴完整度增减，结算后夹在 `[0, max_health]` |
| `food` | int | 食物增减，结算后不低于 0 |
| `seed` | bool / string | `true` 从冒险池随机 1 颗；字符串按 id 给种子 |
| `warspoil` | int | 战果 +N（通用 `warspoil` 计数） |
| `amber` | int | 虫珀 +N |
| `integrity_delta` / `food_delta` / `gain_seed` / `gain_result` / `gain_relic` | — | data-contract v1 别名，兼容读取 |

`options[]`（春季事件用；存在时玩家必须选一个）：

| 键 | 类型 | 说明 |
|---|---|---|
| `label` | string | 按钮文字 |
| `food_cost` | int | 选择前扣食物，不足则不可选 |
| `effects` | object | 同上的结算键 |
| `roll` | object | `chance` / `effects` / `fail_chance` / `fail_effects` 概率分支 |
| `battle` | string | 选择后进入布阵，值为 `enemies.json` 的 tier |
| `recruit` | bool | 结算后进入招募 |
| `observe` | bool | 记录预报提示 |
| `rain_food` | int | 雨天时用该值替换 `effects.food`（露水洼 +6） |

> 有 `options` 的事件用 `choose_event_option(index)`；没有 `options` 的旧式事件仍走
> `ready_up()` 或 `choose_encounter(...)`。

## 4. `data/units.json`

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | string | 兵种 id（当前 24 个：共享 12 + 廪实专属 12） |
| `name` | string | 显示名（两字） |
| `combat` | bool | 是否能出战 |
| `tag` | string | 定位标签 |
| `tier` | int | 阶级（1 = L1 池；2 = L2；3 = L3），总和 12 / 8 / 4 |
| `pool` | string | `shared` / `linshi`（专属虫种） |
| `hp` / `atk` | float | 战斗属性，允许 1 位小数；**无防御 / 速度 / 补给** |
| `ap` | int | 每轮行动点（基础 1） |
| `row` | string | `front` / `back` |
| `cost` | object | 招募成本，键只有 `food` |
| `signature` | string | 签名特性（显示文本，效果未实现） |

## 5. `data/enemies.json`

```json
{
  "tiers": {
    "sand": {
      "name": "沙路截击",
      "units": [
        { "name": "盾甲", "hp": 8.0, "atk": 1.5, "ap": 1, "row": "front", "count": 2, "shield_per_round": 2.0 }
      ]
    }
  }
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `tiers.<tier>.name` | string | 势力显示名（`sand` / `resin` / `nest` / `bird`） |
| `tiers.<tier>.units[]` | array | 敌军模板列表 |
| `count` | int | 该模板生成几个 |
| `shield_per_round` | float | 每轮开始护盾补到该值（盾甲） |
| `weaken_chance` | float | 命中后施加 1 层削弱的概率（锹甲） |
| `weaken_per_round` | int | 每轮开始对随机玩家单位施加削弱层数（结网蛛） |
| `bypass_first` | bool | 每轮首次攻击无视前排（掠食雀） |
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
  "event": {...},       # 战斗胜利后按 rewards 结算
  "result": "win" | "lose" | "ruling"
}
unit = { "name", "hp", "max_hp", "atk", "ap", "max_ap", "shield", "weaken", "row", "alive" }
```

布阵阶段另有 `deploy_units`：`[{ "unit_id", "name", "row", "deployed" }]`；
出战不扣食物（Q-052），`deploy_supply()` 恒为 0。

## 6. 代码保证的不变量

事件组生成（`EventPool`）：

1. 每组 4 个事件（`GROUP_SIZE`），类别由模板 `slots` 决定，同类最多 2 个。
2. 每组至少 1 个敌对势力（`enemy_weak` / `enemy_strong`）。
3. 每轮 3 组，模板互不重复；最多 1 个危机组、1 个含遗迹模板。
4. 季节过滤：`season == -1` 或等于当前季节；同一轮内尽量不重复事件 id。
5. 有 `options` 的事件必须经 `choose_event_option`；旧式敌对事件经 `choose_encounter`。

时间 / 经济（`GameState`）：

6. 一局 6 回合（春季切片）；第 6 回合结束 → `WON`，并输出本季统计。
7. 开局先免费招募 2 次（3 选 1、免费、不占行动），完成后才进入 ACTION。
8. 没有工蚁 / 人口 / 维持费；回合开始只做收入汇报。
9. 资源只有 `food`；任何扣减不低于 0。
10. 巢穴完整度夹在 `[0, max_health]`；归零 → `GAME_OVER`。
11. 巢穴 L1 起步，最多扩建 2 次到 L3；肥沃格 3 → 6 → 9。
12. 一颗种子只能种在「肥沃 + 未阻断 + 未占用」的格子；种子袋数量与已种数量之和守恒。
13. 种子计数只在事件结算后推进一次（含战斗事件，战后结算一次）。

战斗 / 招募：

14. 军队数量 ≤ `army.max_size`；招募不会超上限。
15. 候选阶级 ≤ 当前巢穴阶级（L1 = 1、L2 ≤ 2、L3 ≤ 3），成本 ≤ 当前食物；不满足的单位不进池。
16. 升阶后第一次招募至少 1 个新阶级（且付得起）；保底在该次生成后清 0，刷新不重复触发。
17. 开战不扣食物；战斗结束后军队数量不变（士兵返场）。
18. 战斗失败只扣一次 `defeat_health`，不会把完整度扣成负数。
19. 招募刷新每轮最多一次。
20. 目标合法性：某排有存活单位时，另一排不可被选为目标（双方通用）。
21. 第 6 轮敌方阶段结束仍未分胜负 → `result = "ruling"`，按防守方胜结算且食物奖励减半。
22. 单位 HP 不跨场：每场从 `units.json` / `enemies.json` 重建，满血开场。

## 7. 校验与演进

- 运行期**唯一读盘入口**是 `scripts/core/data_store.gd`（`DataStore`）：加载、`schema_version` 校验、
  版本号、`data_reloaded`、错误保留都在这里；新系统不得自己读 `data/`。
- 当前**没有**外部 schema 校验器；字段缺失靠 `Dictionary.get()` 默认值兜底。
- 加字段时：先改本文件 → 再改 `data/*.json` → 最后改 `GameState`。
- 后续新增（系统拍板后再建表）：`relics.json`（虫珀）、`talents.json`（天赋）、
  `recruit_tiers.json`（阶级概率）、`plants.json`（战斗植物）。
