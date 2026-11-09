// 设计手册数据 —— 与 doc/ 下的设计文档同步维护
// 修改设计后，同步更新本文件；刷新页面即可看到。
window.HANDBOOK = {
  meta: {
    title: "Hector 设计手册",
    subtitle: "工作名，正式名待定（Q-019）· 当前阶段：春季切片 · 一阶",
    updated: "2026-11-09",
    legend: [
      { label: "已定", cls: "ok", note: "已经你确认的规则" },
      { label: "提案", cls: "wip", note: "我提出、还没确认" },
      { label: "待定", cls: "todo", note: "明确还没设计" }
    ]
  },

  // ── 兵种（一阶 12 个）──────────────────────────────
  units: [
    // 共享 · 一阶（已定稿）
    { name: "锐士", tier: 1, kind: "shared", source: "共享", cost: 8, supply: 1, hp: 10.0, atk: 3.0, row: "前排",
      sig: "成长", text: "每次攻击后永久 +0.2 攻击", status: "已定",
      note: "起步偏慢，靠攻击次数滚雪球；不增加生命。" },
    { name: "斥候", tier: 1, kind: "shared", source: "共享", cost: 5, supply: 1, hp: 7.0, atk: 2.0, row: "前排（推荐）",
      sig: "迅捷 / 不甘", text: "开局得【迅捷】、阵亡得【不甘】两个战果", status: "已定",
      note: "低血低攻，推荐放前排主动卖死触发不甘。" },
    { name: "采薇", tier: 1, kind: "shared", source: "共享", cost: 6, supply: 1, hp: 6.0, atk: 1.5, row: "后排（推定）",
      sig: "采撷", text: "胜利或存活，额外 +1–3 食物", status: "已定",
      note: "站位文档未明确写过，本页按后排推定，待确认。" },
    { name: "干城", tier: 1, kind: "shared", source: "共享", cost: 9, supply: 2, hp: 16.0, atk: 1.0, row: "前排",
      sig: "扼守 + 格挡 + 受伤成长", text: "每轮 3.0 护盾；每次实际掉血永久 +1 最大生命", status: "已定",
      note: "嘲讽位，把单体攻击吸到自己身上；攻击 1.0，纯耐久。" },
    { name: "焚卒", tier: 1, kind: "shared", source: "共享", cost: 6, supply: 1, hp: 8.0, atk: 2.0, row: "前排",
      sig: "自爆 / 不甘", text: "1 行动点阵亡；对敌方前排每单位造成攻击力 ×50%，全灭后继续打后排", status: "已定",
      note: "一次性，爆炸每目标 1.0；战后返场并回满 HP。" },
    { name: "弩手", tier: 1, kind: "shared", source: "共享", cost: 7, supply: 1, hp: 6.0, atk: 3.0, row: "后排",
      sig: "连射", text: "每次攻击 30% 获得 +1 行动点，可连锁", status: "已定",
      note: "期望 1.43 次攻击/轮；额外行动点只给自己。" },
    { name: "辅兵", tier: 1, kind: "shared", source: "共享", cost: 7, supply: 1, hp: 7.0, atk: 2.0, row: "后排",
      sig: "庇护", text: "每轮玩家阶段开始，随机 1 名友军获得 1 层护盾（5 点）", status: "已定",
      note: "随机不可控；层数是否叠加、是否每轮清零、是否含自己仍待定。" },
    { name: "缚者", tier: 1, kind: "shared", source: "共享", cost: 8, supply: 1, hp: 6.0, atk: 1.5, row: "后排",
      sig: "缠缚", text: "每轮开始选 1 个敌人施加【削弱】（本轮攻击 ×50%）；可叠层，每轮 −1 层", status: "已定",
      note: "输出极低，只能控 1 人；对不攻击的单位无效。" },

    // 共享 · 二阶 / 三阶（提案）
    { name: "传令", tier: 2, kind: "shared", source: "共享", cost: 10, supply: 2, hp: 11.0, atk: 2.0, row: "后排",
      sig: "传令", text: "每场 1 次，令 1 名友军本轮 +1 行动点", status: "提案",
      note: "一场一次；给不到多段输出单位就浪费。" },
    { name: "悍卒", tier: 2, kind: "shared", source: "共享", cost: 10, supply: 2, hp: 15.0, atk: 2.5, row: "前排",
      sig: "悍勇", text: "每轮首次实际掉血后，本场攻击永久 +1.0", status: "提案",
      note: "不能和干城同排：扼守会把攻击吸走。" },
    { name: "队正", tier: 2, kind: "shared", source: "共享", cost: 11, supply: 2, hp: 13.0, atk: 2.0, row: "后排",
      sig: "整阵", text: "存活时，同排友军每轮玩家阶段开始获得 1.0 护盾", status: "提案",
      note: "只护同排；站前排又挤。" },
    { name: "司天", tier: 3, kind: "shared", source: "共享", cost: 14, supply: 3, hp: 12.0, atk: 3.0, row: "后排",
      sig: "观天", text: "布阵阶段把本场天气改为晴 / 多云 / 雨任一，每场 1 次", status: "提案",
      note: "天气双方共享；天气本来就合适时等于白板。" },

    // 廪实专属 · 一阶（提案）
    { name: "囤卒", tier: 1, kind: "species", source: "廪实专属", cost: 9, supply: 2, hp: 10.0, atk: 2.5, row: "前排",
      sig: "积粮", text: "战斗开始时，可交 2 食物，本场攻击 +1.5", status: "提案",
      note: "粮紧时等于白板；与实卒的囤粮方向相反。" },
    { name: "拾卒", tier: 1, kind: "species", source: "廪实专属", cost: 8, supply: 2, hp: 9.0, atk: 2.0, row: "前排",
      sig: "拾遗", text: "本场每退场 1 个敌人，结算 +1 食物（上限 +4）", status: "提案",
      note: "不要求自己击杀；速推收益低。" },
    { name: "拒卒", tier: 1, kind: "species", source: "廪实专属", cost: 8, supply: 2, hp: 11.0, atk: 2.0, row: "前排",
      sig: "立壁", text: "战斗开始时获得 3.0 护盾，一次性、不刷新", status: "提案",
      note: "第二轮起是白板，与干城功能有交集。" },
    { name: "禾卒", tier: 1, kind: "species", source: "廪实专属", cost: 7, supply: 2, hp: 7.0, atk: 1.5, row: "后排",
      sig: "护苗", text: "每株存活的己方战斗植物，全体友军 +0.5 攻击（上限 +2.0）", status: "提案",
      note: "不带植物就是 1.5 攻击的白板。" },

    // 廪实专属 · 二阶 / 三阶（提案）
    { name: "廪尉", tier: 2, kind: "species", source: "廪实专属", cost: 13, supply: 2, hp: 12.0, atk: 2.0, row: "后排",
      sig: "发廪", text: "每场 1 次，交 3 食物，全队本场 +1.0 攻击", status: "提案",
      note: "一次性；粮不足不能用。" },
    { name: "障卒", tier: 2, kind: "species", source: "廪实专属", cost: 13, supply: 2, hp: 17.0, atk: 2.0, row: "前排",
      sig: "屏障", text: "每轮指定 1 名后排友军，替其承受下一次单体攻击（不能替 AOE）", status: "提案",
      note: "每轮只有 1 次；自己会被打穿。" },
    { name: "田正", tier: 2, kind: "species", source: "廪实专属", cost: 12, supply: 2, hp: 11.0, atk: 1.5, row: "后排",
      sig: "督耕", text: "每轮玩家阶段开始，己方全部战斗植物获得 1.0 护盾", status: "提案",
      note: "无植物白板；1.0 只挡零头。" },
    { name: "釜卒", tier: 2, kind: "species", source: "廪实专属", cost: 12, supply: 2, hp: 14.0, atk: 2.5, row: "前排",
      sig: "灶火", text: "每轮可交 1 食物，随机 1 名友军本场 +1.0 攻击（可叠加）", status: "提案",
      note: "每轮烧粮；随机不可控。" },
    { name: "殉卒", tier: 2, kind: "species", source: "廪实专属", cost: 14, supply: 3, hp: 13.0, atk: 3.0, row: "前排",
      sig: "不甘", text: "阵亡时全队本场 +1.0 攻击（每场 1 次）", status: "提案",
      note: "要主动送死；与采薇的存活条件相反。" },
    { name: "太仓", tier: 3, kind: "species", source: "廪实专属", cost: 18, supply: 3, hp: 18.0, atk: 3.0, row: "后排",
      sig: "开廪", text: "每场 1 次，交 5 食物，全队 +2.0 攻击与 2.0 护盾", status: "提案",
      note: "5 食物门槛高；一场一次。" },
    { name: "镇廪", tier: 3, kind: "species", source: "廪实专属", cost: 18, supply: 3, hp: 22.0, atk: 2.5, row: "前排",
      sig: "镇仓", text: "存活时，每轮玩家阶段开始全队获得 2.0 护盾", status: "提案",
      note: "高血嘲讽位；死了断供。" },
    { name: "实卒", tier: 3, kind: "species", source: "廪实专属", cost: 17, supply: 3, hp: 19.0, atk: 3.0, row: "前排",
      sig: "实仓", text: "攻击额外 +（当前食物 ÷ 8，向下取整，最高 +3.0）", status: "提案",
      note: "吃库存；与烧粮体系方向相反。" }
  ],

  // ── 敌人（春季）──────────────────────────────────
  enemies: [
    { name: "盾甲", family: "甲虫", hp: 8.0, atk: 1.5, row: "前排", elite: false,
      sig: "厚甲", text: "每轮玩家阶段开始获得 2.0 护盾，不叠加", status: "提案",
      note: "肉盾，拖轮数；没有嘲讽。" },
    { name: "锹甲", family: "甲虫", hp: 6.0, atk: 2.5, row: "前排", elite: false,
      sig: "挑击", text: "攻击命中后 30% 使目标获得【削弱】", status: "提案",
      note: "前排压力位，直接压低玩家输出。" },
    { name: "结网蛛", family: "蜘蛛", hp: 4.0, atk: 2.0, row: "后排", elite: false,
      sig: "吐丝", text: "每轮玩家阶段开始，对随机 1 名玩家单位施加【削弱】", status: "提案",
      note: "血薄但躲在前排后面；两只同场时有削弱叠加风险。" },
    { name: "掠食雀", family: "鸟", hp: 9.0, atk: 3.0, row: "后排", elite: true,
      sig: "俯冲", text: "每轮首次攻击无视前排，直接攻击玩家后排 1 名单位", status: "提案",
      note: "强敌；越排攻击是全局唯一例外。" }
  ],

  // ── 虫种 ─────────────────────────────────────────
  species: [
    { name: "廪实", theme: "仓廪充实、以粮为纲的收获之族", status: "已定（技能）/ 提案（专属兵）",
      passive: "劝农：开局 + 夏 / 秋 / 冬开始，共 4 次种子三选一；免费、不占行动、可跳过",
      actives: [
        { name: "开仓", cd: 6, text: "催熟所有收获型种子，立即产出一次，计数器归零" },
        { name: "守廪", cd: 6, text: "立即恢复最大巢穴完整度的 25%" }
      ],
      builds: ["积廪：存粮 / 开仓，节奏型爆发", "劝农：扩田 / 加种子 / 缩周期", "守廪：修巢 / 防守植物 / 工蚁，消耗战"],
      extra: "开局默认 L2 / 3 肥沃格 / 1 基础食物种子 / 15 食物；共享池权重均衡；上手难度中等。" }
  ],

  // ── 虫珀 ─────────────────────────────────────────
  relics: {
    status: "仅有规则，具体条目未设计",
    entries: [],
    types: [
      { name: "经济", eg: "每回合 +1 食物；收获型种子产量 +1" },
      { name: "战斗", eg: "锐士攻击 +1；焚卒爆炸伤害 +1" },
      { name: "巢穴", eg: "完整度上限 +10；修复更便宜" },
      { name: "规则", eg: "事件组多 1 个选项；三选一可多选；招募可刷新" },
      { name: "招募", eg: "解锁一个稀有兵种候选" }
    ],
    rarities: ["普通", "稀有", "传说（暂定）", "诅咒（独立于稀有度，按负面强度分级）"],
    note: "遗迹基础奖励 1 个普通虫珀；另有概率直接获得诅咒虫珀，不可拒绝。"
  },

  // ── 势力 ─────────────────────────────────────────
  factions: [
    { name: "中立生物", attitude: "可交友 / 可击败", risk: "低–中", reward: "商人 / 战友 / buff / 虫珀", status: "已定" },
    { name: "弱小敌对势力", attitude: "敌对", risk: "低", reward: "基础资源、虫珀、战果", status: "已定" },
    { name: "强大敌对势力", attitude: "敌对", risk: "高", reward: "稀有虫珀、稀有种子、战果", status: "已定" }
  ],

  // ── 事件（春季 13 个）────────────────────────────
  events: [
    { name: "沙路截击", cat: "普通敌对", opts: "迎战 / 谈判（−2 食物）/ 回避（−5 完整度）", status: "提案" },
    { name: "树脂争夺", cat: "普通敌对", opts: "迎战 / 谈判（−3 食物，得 1 种子）/ 回避", status: "提案" },
    { name: "巢口巡游", cat: "普通敌对", opts: "迎战 / 驱赶（−1 完整度）/ 无视", status: "提案" },
    { name: "雀袭", cat: "强大敌对", opts: "迎战 / 献食（−5 食物）/ 绕行（−1 回合）", status: "提案" },
    { name: "腐木探路", cat: "探索", opts: "深入（工蚁 −2，得 1 食物种子）/ 浅探（工蚁 −1，+2 食物）/ 放弃", status: "提案" },
    { name: "露水洼", cat: "探索", opts: "取水（+3 食物，雨天 +6）/ 观察（看下回合天气）/ 离开", status: "提案" },
    { name: "旧巢残骸", cat: "探索", opts: "挖掘（50% 得 1 战果）/ 拆解（+2 食物）/ 离开", status: "提案" },
    { name: "春雨", cat: "意外随机", opts: "蓄水（+2 食物）/ 加固巢口（完整度 +5）", status: "提案" },
    { name: "掠食鸟影", cat: "意外随机", opts: "隐蔽（−1 工蚁）/ 转移（−1 食物）", status: "提案" },
    { name: "迷路工蚁", cat: "意外随机", opts: "带回（+1 工蚁）/ 放弃", status: "提案" },
    { name: "树脂滴落", cat: "意外随机", opts: "收集（得 1 工具种子）/ 避开", status: "提案" },
    { name: "流浪蚁群", cat: "招募", opts: "招募（3 选 1 一阶，付费）/ 刷新（−2 食物）/ 放弃", status: "提案" },
    { name: "琥珀碎片", cat: "神秘遗迹", opts: "研究（得 1 虫珀）/ 进入（50% 虫珀，30% −5 完整度）/ 离开", status: "提案" }
  ],

  // ── 枚举值 ───────────────────────────────────────
  enums: [
    { group: "阶级", items: [
      { key: "一阶", value: "巢穴 L2", status: "已定" },
      { key: "二阶", value: "巢穴 L3", status: "已定" },
      { key: "三阶", value: "巢穴 L4", status: "已定" }
    ]},
    { group: "站位", items: [
      { key: "前排", value: "最多 4 格，前排全灭前后排不可被攻击", status: "已定" },
      { key: "后排", value: "最多 3 格，受前排保护", status: "已定" }
    ]},
    { group: "通用关键词", items: [
      { key: "扼守", value: "前排存活时，敌方单体攻击必须选它", status: "已定" },
      { key: "迅捷", value: "战斗开始时触发一次绑定效果", status: "已定" },
      { key: "不甘", value: "阵亡时触发一次绑定效果", status: "已定" },
      { key: "负伤", value: "每轮首次受伤后触发", status: "已定" },
      { key: "战蜕", value: "本场首次击杀后成长", status: "已定" }
    ]},
    { group: "状态", items: [
      { key: "削弱", value: "攻击 ×50%，效果不随层数变化；每次施加 +1 层，每轮结束 −1 层，层数只决定持续时间", status: "已定" }
    ]},
    { group: "天气", items: [
      { key: "晴", value: "正向修正（生产 +1，提案）", status: "已定" },
      { key: "多云", value: "无额外修正", status: "已定" },
      { key: "雨", value: "战斗补给 ×1.5、探索工蚁损失 +1", status: "已定" }
    ]},
    { group: "季节", items: [
      { key: "春", value: "探索风险↑、敌对更强、生产加速", status: "已定" },
      { key: "夏", value: "探索回报↑、敌对概率↓、损失↑、生产↓、伤害↑", status: "已定" },
      { key: "秋", value: "生产加速、击败敌对可能额外掉落", status: "已定" },
      { key: "冬", value: "食物消耗↓、伤害↓、巢穴更易受伤", status: "已定" }
    ]},
    { group: "事件类别", items: [
      { key: "普通敌对势力", value: "迎战 / 谈判 / 回避", status: "已定" },
      { key: "强大敌对势力", value: "迎战 / 献食 / 绕行", status: "已定" },
      { key: "探索", value: "深入 / 带回 / 放弃", status: "已定" },
      { key: "意外随机事件", value: "生物 / 天气 / 灾害 / 机遇", status: "已定" },
      { key: "招募事件", value: "3 选 1 / 刷新 / 放弃", status: "已定" },
      { key: "神秘遗迹", value: "进入 / 研究 / 离开", status: "已定" }
    ]},
    { group: "兵种来源", items: [
      { key: "共享", value: "全局共用池 12 个", status: "已定" },
      { key: "专属", value: "每个虫种各 12 个，只在该虫种局出现", status: "已定" }
    ]},
    { group: "种子产出", items: [
      { key: "食物型", value: "周期产出食物", status: "已定" },
      { key: "战果型", value: "周期产出战果", status: "已定" },
      { key: "工具型", value: "恢复 / 增益 / 羁绊 / 战斗植物", status: "已定" }
    ]},
    { group: "战果时效", items: [
      { key: "本场", value: "只在本场战斗有效", status: "已定" },
      { key: "本局", value: "本局永久，重开重置", status: "已定" }
    ]}
  ],

  // ── 核心数值 ─────────────────────────────────────
  formulas: [
    { name: "攻击值", formula: "基础攻击 × 状态修正（如削弱 ×0.5）", status: "已定" },
    { name: "伤害", formula: "攻击值 × 技能倍率 × 浮动(0.90–1.10)", status: "已定" },
    { name: "最低伤害", formula: "0.1", status: "已定" },
    { name: "每回合食物消耗", formula: "1 + ceil(人口 / 5)", status: "已定" },
    { name: "雨天补给", formula: "总补给 × 1.5，向上取整", status: "已定" },
    { name: "目标轮数", formula: "3–4 轮", status: "提案" },
    { name: "最终裁决", formula: "第 6 轮结束仍未分胜负", status: "提案" },
    { name: "一阶敌人分档", formula: "HP 4.0–8.0 / 攻击 1.5–2.5；强敌 +20%–40%", status: "提案" }
  ]
};
