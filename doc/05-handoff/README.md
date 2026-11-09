---
status: living
owner: design
last-review: 2026-11-09
---

# 交接层（设计 → 开发）

> 本目录**不是设计内容**，是给开发 Agent / 开发者的**实现需求与边界说明**。
> 设计内容仍然只写在 `00-vision` / `01-loop` / `02-systems` / `03-content` / `04-slice` 里。

## 文档清单

| 文件 | 作用 | 谁执行 |
|---|---|---|
| `boundary.md` | 设计层与实现层的职责边界、禁止事项、变更流程 | 双方遵守 |
| `data-contract.md` | `data/*.json` 的文件划分、字段、枚举、校验规则 | 开发实现，设计定义 |
| `tuning-tool.md` | 网页调参工具的功能需求、接口、验收标准 | 开发实现 |
| `hot-reload.md` | Godot 热更的触发方式、生效时机、信号契约 | 开发实现 |

## 阅读顺序（给开发 Agent）

1. 先读 `boundary.md`，确认哪些能做、哪些不能做。
2. 再读 `data-contract.md`，这是设计层唯一认可的数据格式。
3. 实现工具与热更时对照 `tuning-tool.md` / `hot-reload.md` 的验收标准。
4. 设计内容按需查：`04-slice/spring-v0.md`（本期做什么）、`03-content/*`（内容条目）、`02-systems/*`（规则）。

> **歧义处理**：文档没写清楚的地方，**不要自行假设**，登记到 `doc/OPEN-QUESTIONS.md`，由设计层回答后再实现。

## 本期（春季切片）的交付顺序

1. 数据文件落地（按 `data-contract.md`）。
2. 网页调参工具（按 `tuning-tool.md`）。
3. Godot 数据总线与热更（按 `hot-reload.md`）。
4. 春季切片可玩流程（按 `04-slice/spring-v0.md`）。
