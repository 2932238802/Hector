---
status: living
owner: design
last-review: 2026-11-11
---

# 数据契约 v1（`data/*.json`）

> **谁创建**：实现层（开发 Agent）。设计层只定义字段与语义，不写文件、不写解析代码。
> **唯一事实来源**：进入实现后，**JSON 是运行期事实来源**；`doc/` 里的表格是设计说明，两者冲突时以本文档 + 设计文档的语义为准，并登记 `OPEN-QUESTIONS` 仲裁。
> 本期（春季切片）只需要下表的字段，**多一个字段都属于未定义行为**。

## 0. 通用约定

- 编码 UTF-8，无 BOM；缩进 2 空格。
- 每个文件顶层必须含 `"schema_version": 1`。
- `id`：小写 ASCII + 下划线，稳定不变；**改中文名不改 id**。
- 数值：HP / 攻击最多 1 位小数；成本 / 概率按字段说明。
- 枚举值必须使用下表中文原值，大小写与空格都不得变。
- 所有字段**必填**，除非标注「可空」。

## 1. 文件划分

| 文件 | 内容 | 本期规模 |
|---|---|---|
| `data/units.json` | 兵种 | 31 个（一阶 14 / 二阶 11 / 三阶 6） |
| `data/enemies.json` | 敌人 | 4 个（盾甲 / 锹甲 / 结网蛛 / 掠食雀） |
| `data/events.json` | 事件池 + 事件组模板 + 季节权重 | 13 个事件 / 6 模板 |
| `data/balance.json` | 全局常数 | 见 §5 |
| `data/species.json` | 虫种 | 廪实 1 个 |
| `data/relics.json` | 虫珀 | 2 个示例 |

> **禁止合并**：兵种 / 敌人 / 事件 / 虫珀 / 虫种各自独立文件，不得塞进同一个"大 JSON"。

## 2. `units.json`

```json
{
  "schema_version": 1,
  "units": [ { ... } ]
}
```

| 字段 | 类型 | 取值 / 说明 |
|---|---|---|
| `id` | string | 唯一，如 `ruishi` |
| `name` | string | 显示名，如 `弧矢蚁` |
| `name_alt` | string | 备选名，仅留档，不显示 |
| `tier` | int | `1` / `2` / `3`（对应巢穴 L1 / L2 / L3） |
| `source` | enum | `shared` / `species` |
| `species_id` | string \| null | `source=species` 时必填，如 `linshi` |
| `role` | string | 自由文本，如 `前排主力` |
| `cost_food` | number | ≥ 0 |
| `hp` | number | > 0，1 位小数 |
| `attack` | number | ≥ 0，1 位小数 |
| `ap` | int | ≥ 1，默认 1 |
| `row` | enum | `front` / `back` / `either` |
| `signature` | object | `{id, name, text, params}`；`params` 放可调数值 |
| `keywords` | string[] | 只能取 `迅捷` / `角质化` / `点卯` / `营巢` / `不甘` / `号令` / `余勇` / `猎杀` / `反噬` / `狂热` / `引导` / `扼守` |
| `weakness` | string | 主要缺点，一句话 |
| `status` | enum | `final` / `proposal`（数据侧标记，UI 可显示） |

**`signature.params` 约定**：签名里所有会调的数值都放这里，**不得写死在 `text` 里**。例：

```json
"signature": {
  "id": "lian_she",
  "name": "连射",
  "text": "每次攻击有概率获得 1 行动点，可连锁",
  "params": { "proc_chance": 0.30 }
}
```

## 3. `enemies.json`

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | string | 唯一 |
| `name` | string | 显示名 |
| `family` | enum | `beetle` / `spider` / `bird`（甲虫 / 蜘蛛 / 鸟） |
| `tier` | int | 本期 1 |
| `hp` / `attack` | number | 1 位小数 |
| `ap` | int | ≥ 1，默认 1 |
| `row` | enum | `front` / `back` |
| `signature` | object | `{id, name, text, params}`，与 `units.json` 同结构 |
| `keywords` | string[] | 同 `units.json` 枚举；本期敌人可为空 |
| `count_min` / `count_max` | int | 该敌人一次出现的数量区间 |
| `is_elite` | bool | 强敌标记 |
| `tags` | string[] | 自由标签（如 `甲虫` / `越排`） |

**顶层结构**（2026-11-11 与代码对齐）：

```json
{
  "schema_version": 1,
  "enemies": [ { "id": "dunjia", "...": "..." } ],
  "encounters": {
    "sand": {
      "name": "沙路截击",
      "units": [ { "enemy_id": "dunjia", "count": 2 } ]
    }
  }
}
```

| 遭遇字段 | 说明 |
|---|---|
| `encounters.<id>.name` | 战斗显示名 |
| `encounters.<id>.units` | `[{enemy_id, count}]`；按站位放入前 4 / 后 3，放不下则跳过并记日志 |

## 4. `events.json`

```json
{
  "schema_version": 1,
  "templates": [ { "id": "...", "name": "...", "slots": ["hostile", "explore", "random", "random"], "weights": { "spring": 35 } } ],
  "events": [ { "id": "...", "name": "...", "category": "hostile", "options": [ ... ] } ]
}
```

**类别枚举**：`hostile` / `elite_hostile` / `explore` / `random` / `recruit` / `ruin`。

| 模板字段 | 说明 |
|---|---|
| `slots` | 固定 4 项，按 A→B→C→D 顺序；**至少 1 项是 `hostile` 或 `elite_hostile`** |
| `weights` | 按季节给权重（本期只需 `spring`），0–100 |

| 事件字段 | 说明 |
|---|---|
| `category` | 上述枚举 |
| `options` | 2–3 个选项，每个含 `id` / `label` / `effects` |

**选项效果用声明式字段，不写脚本**：

| 效果字段 | 类型 | 说明 |
|---|---|---|
| `food_delta` | number | 正负均可 |
| `integrity_delta` | number | 巢穴完整度 |
| `gain_seed` | string \| null | 种子 id |
| `gain_result` | string \| null | 战果 id |
| `gain_relic` | string \| null | 虫珀 id |
| `battle` | object \| null | `{ "enemy_id": "...", "count": 3 }` |
| `chance` | number | 0–1，可空；有值时按概率抽结果 |

## 5. `balance.json`

| 键 | 字段 | 本期值 |
|---|---|---|
| `max_health` | — | `100` |
| `start` | `health` / `food` / `nest_level` / `seed` / `free_recruits` | `100` / `15` / `1` / `grain_basic` / `2` |
| `actions.adventure` | `food_cost_min` / `food_cost_max` / `food_min` / `food_max` / `seed_chance` / `health` / `seed_pool` | `1` / `2` / `2` / `4` / `0.35` / `-2` / 4 个种子 id |
| `actions.heal` | `food_cost` / `health` | `4` / `18` |
| `actions.expand` | `exp_threshold` | `[0, 12, 18]` |
| `nest` | `max_level` / `fertile_per_ring` | `3` / `3` |
| `army` | `max_size` / `front` / `back` | `7` / `4` / `3` |
| `recruit` | `refresh_cost` / `candidates` / `tier_rates` | `1` / `3` / 见下 |
| `combat` | `defeat_health` / `verdict_round` / `rewards` | `5` / `6` / 按遭遇 id 分档 |
| `spring` | `production_bonus` / `enemy_scale` / `explore_food_loss` | `1` / `1.1` / `1` |
| `weather` | `names` / `weights` / `effects` | 晴 / 雨 / 多云；季内 4 段权重；晴产出 +1、雨探索损失 +1 且冒险生命 −1 |
| `season_modifier` | 4 项 `adventure_food` | 春夏秋冬冒险食物修正 |
| `event_groups_per_turn` | — | `3`（每回合可选事件组数） |
| `location` / `locations` | `name` / `blocked_dirs` | `river`；河边 / 人类房屋边 / 沙漠 |

**`recruit.tier_rates`**：按巢穴等级给出各阶级出现率，形如 `"2": [[1,60],[2,40]]`，权重合计 100。
**`combat.rewards`**：按遭遇 id 给 `{food:[min,max], warfruits:概率, amber:概率}`；目前 `bird` 为强敌档。

## 6. `species.json`

| 字段 | 说明 |
|---|---|
| `id` / `name` | `linshi` / `廪实` |
| `passive` | `{id, name, text, params}` |
| `actives` | 2 项，各含 `{id, name, text, cooldown, params}` |
| `default` | bool，是否默认开局虫种 |

## 7. `relics.json`

| 字段 | 说明 |
|---|---|
| `id` / `name` | 唯一 |
| `rarity` | `common` / `rare` / `cursed` |
| `text` | 效果描述 |
| `params` | 可调数值 |
| `is_cursed` | bool |

## 8. 校验规则（工具与运行时共用）

1. 所有 `id` 在文件内唯一；跨文件引用必须存在（事件的 `battle.enemy_id`、`gain_relic` 等）。
2. `tier` 只能是 1–3。
3. `hp > 0`、`attack ≥ 0`、`cost_food ≥ 0`、`ap ≥ 1`。
4. `row` / `keywords` / `category` / `status` 只能取枚举值。
5. 模板 `slots` 必须 4 项，且至少 1 项敌对。
6. 权重 0–100；同一模板四季权重不必合计 100。
7. 数值小数位：`hp` / `attack` 最多 1 位；写更多位视为校验失败。

## 9. 文档 → 字段映射

| 设计文档 | JSON |
|---|---|
| `03-content/units.md` 4.1–4.12、5.1–5.4 | `units.json` |
| `03-content/units.md` 5.5 一阶总表 | `units.json` 的汇总视图（不单独存） |
| `04-slice/spring-v0.md` §6 | `enemies.json` |
| `04-slice/spring-v0.md` §7 | `events.json` |
| `04-slice/spring-v0.md` §4 / §5 / §2 | `balance.json` |
| `03-content/species.md` 3.0 | `species.json` |
| `03-content/relics.md` | `relics.json` |
