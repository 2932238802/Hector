---
status: living
owner: design
last-review: 2026-11-09
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
| `data/units.json` | 兵种 | 12 个一阶 |
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
| `name` | string | 显示名，如 `锐士` |
| `name_alt` | string | 备选名，仅留档，不显示 |
| `tier` | int | `1` / `2` / `3`（本期只有 1） |
| `source` | enum | `shared` / `species` |
| `species_id` | string \| null | `source=species` 时必填，如 `linshi` |
| `role` | string | 自由文本，如 `前排主力` |
| `cost_food` | number | ≥ 0 |
| `hp` | number | > 0，1 位小数 |
| `attack` | number | ≥ 0，1 位小数 |
| `ap` | int | ≥ 1，默认 1 |
| `row` | enum | `front` / `back` / `either` |
| `signature` | object | `{id, name, text, params}`；`params` 放可调数值 |
| `keywords` | string[] | 只能取 `扼守` / `迅捷` / `不甘` / `负伤` / `战蜕` |
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
| `upkeep` | `base` / `pop_divisor` | `1` / `5` |
| `harvest.food` | `period_events` / `amount` | `3` / `2` |
| `harvest.bountiful` | `period_events` / `amount` | `5` / `4` |
| `spring` | `production_bonus` / `enemy_scale` / `explore_worker_loss` | `1` / `1.1` / `1` |
| `weather.clear` | `production_bonus` | `1` |
| `weather.cloudy` | — | 无修正 |
| `weather.rain` | `explore_worker_loss` | `1` |
| `combat` | `target_rounds` / `verdict_round` | `[3,4]` / `6` |
| `rewards.normal` | `food_min` / `food_max` / `result_chance` | `2` / `4` / `0.5` |
| `rewards.elite` | `food_min` / `food_max` / `relic_chance` | `4` / `6` / `0.5` |
| `start` | `nest_level` / `food` / `plots` / `free_recruits` | `2` / `15` / `3` / `2` |

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
2. `tier` 只能是 1–3；本期数据只允许 1。
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
