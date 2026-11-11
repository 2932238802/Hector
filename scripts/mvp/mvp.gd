extends Control
## 最小可玩回合（MVP）——独立于 M0 原型，用当前文档的一阶兵做 3 回合体验。
##
## 一回合 = 招募（3 选 1）→ 经营（1 个行动）→ 自动战斗 → 结算。
## 目的：先感受「粮 → 兵 → 战斗 → 再投资」的节奏，再决定下一步扩什么。
## 本文件刻意把签名压成最小实现；数值与文案以 doc/03-content/units.md 为准。

enum Phase { RECRUIT, ACTION, BATTLE, RESULT, WON, LOST }

const MAX_TURN := 3
const MAX_PLANTS := 3
const NEST_MAX := 20.0
const START_FOOD := 15
const RECRUIT_COST := 4
const REFRESH_COST := 1
const SEED_COST := 3
const REPAIR_COST := 4
const REPAIR_AMOUNT := 6.0
const TRAIN_COST := 2
const PLANT_FOOD := 2

const INK := Color("1a1a1a")
const MUTED := Color("6f6a60")
const PAPER := Color("f4f1ea")
const ACCENT := Color("8a4b2a")

# 一阶 MVP 池：只取签名最容易在最小版本里跑通的 6 个。
const UNIT_DEFS := {
	"houwang": {
		"name": "候望蚁", "row": "前排", "hp": 5.5, "atk": 2.0, "sig": "迅捷",
		"desc": "战斗开始：自身 +1.0 攻击【战时】（MVP 简化）"
	},
	"suihuo": {
		"name": "燧火蚁", "row": "前排", "hp": 6.5, "atk": 2.0, "sig": "不甘",
		"desc": "阵亡时：敌方前排每单位受到 1.0 伤害"
	},
	"hushi": {
		"name": "弧矢蚁", "row": "后排", "hp": 5.0, "atk": 3.0, "sig": "角质化",
		"desc": "每次攻击 30% 追加一次攻击"
	},
	"yunnou": {
		"name": "耘耨蚁", "row": "后排", "hp": 5.5, "atk": 2.0, "sig": "点卯",
		"desc": "每轮：攻击最低的友军 +1.0 攻击【战时】"
	},
	"fengsui": {
		"name": "烽燧蚁", "row": "前排", "hp": 7.0, "atk": 1.5, "sig": "余勇",
		"desc": "每次实际掉血：+0.5 最大生命【永久】"
	},
	"cangcao": {
		"name": "仓曹蚁", "row": "前排", "hp": 7.0, "atk": 2.0, "sig": "营巢",
		"desc": "战斗外：交 2 食物，+3.0 生命或 +2.0 攻击【永久】"
	},
}

const POOL := ["houwang", "suihuo", "hushi", "yunnou", "fengsui", "cangcao"]

var phase: int = Phase.RECRUIT
var turn := 1
var food := START_FOOD
var nest := NEST_MAX
var plants := 1
var army: Array[Dictionary] = []
var candidates: Array[String] = []
var enemies: Array[Dictionary] = []
var battle_round := 0
var log_lines: Array[String] = []
var busy := false
var action_used := false
var rng := RandomNumberGenerator.new()

var hud_food: Label
var hud_nest: Label
var hud_turn: Label
var hud_plants: Label
var army_box: VBoxContainer
var enemy_title: Label
var enemy_box: VBoxContainer
var nest_box: VBoxContainer
var side_title: Label
var side_body: Label
var side_actions: VBoxContainer
var log_label: RichTextLabel


func _ready() -> void:
	rng.randomize()
	_build_theme()
	_build_ui()
	_new_game()
	_maybe_capture()
	_maybe_autoplay()


func _new_game() -> void:
	phase = Phase.RECRUIT
	turn = 1
	food = START_FOOD
	nest = NEST_MAX
	plants = 1
	army = []
	enemies = []
	battle_round = 0
	log_lines = []
	action_used = false
	busy = false
	_add_unit("houwang")
	_add_unit("hushi")
	candidates = _roll_candidates()
	_log("新的一局：食物 %d，巢穴完整度 %d，%d 块田，队伍 %d 人。" % [food, int(nest), plants, army.size()])
	_log("第 1 回合 · 招募事件：3 选 1，花费 %d 食物；也可以跳过。" % RECRUIT_COST)
	_refresh()


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

func _build_theme() -> void:
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "SimHei",
		"Noto Sans CJK SC", "Arial Unicode MS",
	])
	font.allow_system_fallback = true
	theme.default_font = font
	theme.default_font_size = 17
	theme.set_color("font_color", "Label", INK)
	theme.set_stylebox("normal", "Button", _button_style(Color(1, 1, 1, 0.94), Color(0, 0, 0, 0.5)))
	theme.set_stylebox("hover", "Button", _button_style(Color("e9e3d5"), INK))
	theme.set_stylebox("pressed", "Button", _button_style(Color("ddd5c3"), INK))
	theme.set_stylebox("disabled", "Button", _button_style(Color(1, 1, 1, 0.4), Color(0, 0, 0, 0.15)))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", INK)
	theme.set_color("font_pressed_color", "Button", INK)
	theme.set_color("font_disabled_color", "Button", MUTED)
	self.theme = theme


func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.66)
	style.border_color = Color(0, 0, 0, 0.18)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	return panel


func _label(text: String, size := 17, color := INK, wrap := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	return label


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = PAPER
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	column.add_child(_build_hud())

	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 10)
	column.add_child(split)
	split.add_child(_build_nest_panel())
	split.add_child(_build_center_panel())
	split.add_child(_build_side_panel())

	column.add_child(_build_log_panel())


func _build_hud() -> Control:
	var panel := _panel()
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 26)
	panel.add_child(box)

	hud_turn = _label("", 22)
	box.add_child(hud_turn)
	hud_food = _label("")
	box.add_child(hud_food)
	hud_plants = _label("")
	box.add_child(hud_plants)
	hud_nest = _label("")
	box.add_child(hud_nest)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	box.add_child(_label("Hector · 最小回合 MVP", 14, MUTED))
	return panel


func _build_nest_panel() -> Control:
	var panel := _panel()
	panel.custom_minimum_size = Vector2(330, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 2.0
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(_label("巢穴", 21))
	box.add_child(_label("完整度归零即失败。修复 %d 食物 → +%d。" % [REPAIR_COST, int(REPAIR_AMOUNT)], 14, MUTED))
	nest_box = VBoxContainer.new()
	nest_box.add_theme_constant_override("separation", 8)
	box.add_child(nest_box)
	return panel


func _build_center_panel() -> Control:
	var panel := _panel()
	panel.custom_minimum_size = Vector2(400, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 3.0
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(_label("队伍", 21))
	army_box = VBoxContainer.new()
	army_box.add_theme_constant_override("separation", 6)
	box.add_child(army_box)
	enemy_title = _label("敌方", 21, ACCENT)
	enemy_title.visible = false
	box.add_child(enemy_title)
	enemy_box = VBoxContainer.new()
	enemy_box.add_theme_constant_override("separation", 6)
	box.add_child(enemy_box)
	return panel


func _build_side_panel() -> Control:
	var panel := _panel()
	panel.custom_minimum_size = Vector2(430, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 3.0
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	side_title = _label("", 21)
	box.add_child(side_title)
	side_body = _label("", 15, MUTED, true)
	box.add_child(side_body)
	side_actions = VBoxContainer.new()
	side_actions.add_theme_constant_override("separation", 8)
	box.add_child(side_actions)
	return panel


func _build_log_panel() -> Control:
	var panel := _panel()
	panel.custom_minimum_size = Vector2(0, 150)
	var box := VBoxContainer.new()
	panel.add_child(box)
	log_label = RichTextLabel.new()
	log_label.fit_content = false
	log_label.scroll_following = true
	log_label.custom_minimum_size = Vector2(0, 120)
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.add_theme_color_override("default_color", INK)
	log_label.add_theme_font_size_override("normal_font_size", 14)
	box.add_child(log_label)
	return panel


# ---------------------------------------------------------------------------
# 刷新
# ---------------------------------------------------------------------------

func _refresh() -> void:
	hud_turn.text = "第 %d / %d 回合" % [turn, MAX_TURN]
	hud_food.text = "食物 %d" % food
	hud_plants.text = "田 %d / %d" % [plants, MAX_PLANTS]
	hud_nest.text = "巢穴 %d / %d" % [int(nest), int(NEST_MAX)]

	_rebuild_nest()
	_rebuild_army()
	_rebuild_side()
	log_label.text = "\n".join(log_lines.slice(maxi(0, log_lines.size() - 14)))


func _rebuild_nest() -> void:
	_clear(nest_box)
	var bar := ProgressBar.new()
	bar.max_value = NEST_MAX
	bar.value = nest
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 18)
	_style_bar(bar, Color("7a5c3e"))
	nest_box.add_child(bar)
	for i in range(MAX_PLANTS):
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		if i < plants:
			line.add_child(_label("田 %d" % (i + 1), 16))
			line.add_child(_label("食物种子 · 每回合 +%d 食物" % PLANT_FOOD, 14, MUTED))
		else:
			line.add_child(_label("田 %d" % (i + 1), 16, MUTED))
			line.add_child(_label("空地（播种 %d 食物）" % SEED_COST, 14, MUTED))
		nest_box.add_child(line)


func _rebuild_army() -> void:
	_clear(army_box)
	if army.is_empty():
		army_box.add_child(_label("队伍为空。", 15, MUTED))
	for unit in army:
		army_box.add_child(_unit_card(unit, false))

	if phase == Phase.BATTLE and not enemies.is_empty():
		enemy_title.visible = true
		_clear(enemy_box)
		for enemy in enemies:
			enemy_box.add_child(_unit_card(enemy, true))
	else:
		enemy_title.visible = false
		_clear(enemy_box)


func _unit_card(unit: Dictionary, is_enemy: bool) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.55) if not is_enemy else Color("f6e7e2")
	style.border_color = Color(0, 0, 0, 0.14)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var name_label := _label(str(unit["name"]), 17)
	head.add_child(name_label)
	head.add_child(_label(str(unit["row"]), 13, MUTED))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(_label("生命 %.1f / %.1f   攻击 %.1f" % [
		maxf(0.0, float(unit["hp"])), float(unit["max_hp"]),
		float(unit["atk"]) + float(unit.get("battle_atk", 0.0))
	], 14, MUTED))
	box.add_child(head)

	var bar := ProgressBar.new()
	bar.max_value = maxf(0.1, float(unit["max_hp"]))
	bar.value = maxf(0.0, float(unit["hp"]))
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	_style_bar(bar, Color("3b3b3b") if not is_enemy else ACCENT)
	box.add_child(bar)

	if not is_enemy:
		box.add_child(_label("%s · %s" % [str(unit["sig"]), str(unit["desc"])], 13, MUTED, true))
	return panel


func _style_bar(bar: ProgressBar, fill_color: Color) -> void:
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.7)
	back.border_color = Color(0, 0, 0, 0.3)
	back.set_border_width_all(1)
	back.set_corner_radius_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", fill)


func _rebuild_side() -> void:
	_clear(side_actions)
	match phase:
		Phase.RECRUIT:
			side_title.text = "招募事件"
			side_body.text = "从 3 名候选中招募 1 名（%d 食物），或跳过进入经营。刷新 1 次 %d 食物。" % [RECRUIT_COST, REFRESH_COST]
			for id in candidates:
				var def: Dictionary = UNIT_DEFS[id]
				var btn := Button.new()
				btn.text = "招募 %s（%d 食物）\n%s · %s" % [def["name"], RECRUIT_COST, def["sig"], def["desc"]]
				btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				btn.disabled = food < RECRUIT_COST
				btn.pressed.connect(_recruit.bind(id))
				side_actions.add_child(btn)
			var refresh := Button.new()
			refresh.text = "刷新候选（%d 食物）" % REFRESH_COST
			refresh.disabled = food < REFRESH_COST
			refresh.pressed.connect(_refresh_candidates)
			side_actions.add_child(refresh)
			side_actions.add_child(_action_button("跳过招募 → 经营", _skip_recruit))
		Phase.ACTION:
			side_title.text = "第 %d 回合 · 经营" % turn
			side_body.text = "选择 1 个行动，然后迎战。植物会在战斗结算后产出食物。"
			var seed_btn := _action_button("播种（%d 食物，+1 块田）" % SEED_COST, _do_seed)
			seed_btn.disabled = food < SEED_COST or plants >= MAX_PLANTS
			side_actions.add_child(seed_btn)
			var repair := _action_button("修复巢穴（%d 食物，+%d）" % [REPAIR_COST, int(REPAIR_AMOUNT)], _do_repair)
			repair.disabled = food < REPAIR_COST or nest >= NEST_MAX
			side_actions.add_child(repair)
			if _has_unit("cangcao"):
				var hp_train := _action_button("仓曹训练：+3.0 生命（%d 食物）" % TRAIN_COST, _train_hp)
				hp_train.disabled = food < TRAIN_COST or action_used
				side_actions.add_child(hp_train)
				var atk_train := _action_button("仓曹训练：+2.0 攻击（%d 食物）" % TRAIN_COST, _train_atk)
				atk_train.disabled = food < TRAIN_COST or action_used
				side_actions.add_child(atk_train)
			side_actions.add_child(_action_button("跳过行动 → 迎战", _skip_action))
		Phase.BATTLE:
			side_title.text = "战斗 · 第 %d 轮" % battle_round
			side_body.text = "自动结算中……前排全灭后才会打到后排。"
		Phase.RESULT:
			side_title.text = "第 %d 回合结算" % turn
			side_body.text = str(side_body.get_meta("result", "")) if side_body.has_meta("result") else ""
			if turn >= MAX_TURN:
				side_actions.add_child(_action_button("结束这一局", _finish_run))
			else:
				side_actions.add_child(_action_button("进入第 %d 回合" % (turn + 1), _next_turn))
		Phase.WON:
			side_title.text = "撑过 %d 回合 · 胜利" % MAX_TURN
			side_body.text = "你守住了巢穴。最小循环跑通了：招募 → 经营 → 战斗 → 再投资。"
			side_actions.add_child(_action_button("再来一局", _new_game))
		Phase.LOST:
			side_title.text = "巢穴完整度归零 · 失败"
			side_body.text = "食物与队伍都还在，但巢穴没撑住。"
			side_actions.add_child(_action_button("再来一局", _new_game))


func _action_button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.disabled = busy
	btn.pressed.connect(callback)
	return btn


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


# ---------------------------------------------------------------------------
# 招募 / 经营
# ---------------------------------------------------------------------------

func _roll_candidates() -> Array[String]:
	var pool := POOL.duplicate()
	pool.shuffle()
	var out: Array[String] = []
	for i in range(mini(3, pool.size())):
		out.append(str(pool[i]))
	return out


func _refresh_candidates() -> void:
	if phase != Phase.RECRUIT or food < REFRESH_COST:
		return
	food -= REFRESH_COST
	candidates = _roll_candidates()
	_log("刷新招募候选（-%d 食物）。" % REFRESH_COST)
	_refresh()


func _recruit(id: String) -> void:
	if phase != Phase.RECRUIT or food < RECRUIT_COST:
		return
	food -= RECRUIT_COST
	_add_unit(id)
	_log("招募 %s（-%d 食物）。" % [str(UNIT_DEFS[id]["name"]), RECRUIT_COST])
	phase = Phase.ACTION
	_refresh()


func _skip_recruit() -> void:
	if phase != Phase.RECRUIT:
		return
	_log("跳过招募。")
	phase = Phase.ACTION
	_refresh()


func _do_seed() -> void:
	if phase != Phase.ACTION or food < SEED_COST or plants >= MAX_PLANTS:
		return
	food -= SEED_COST
	plants += 1
	action_used = true
	_log("播种（-%d 食物）：田增至 %d 块，每回合 +%d 食物。" % [SEED_COST, plants, plants * PLANT_FOOD])
	_start_battle()


func _do_repair() -> void:
	if phase != Phase.ACTION or food < REPAIR_COST or nest >= NEST_MAX:
		return
	food -= REPAIR_COST
	nest = minf(NEST_MAX, nest + REPAIR_AMOUNT)
	action_used = true
	_log("修复巢穴（-%d 食物）：完整度 %d。" % [REPAIR_COST, int(nest)])
	_start_battle()


func _train_hp() -> void:
	_train("hp", 3.0)


func _train_atk() -> void:
	_train("atk", 2.0)


func _train(stat: String, amount: float) -> void:
	if phase != Phase.ACTION or food < TRAIN_COST or action_used:
		return
	var unit := _first_unit("cangcao")
	if unit.is_empty():
		return
	food -= TRAIN_COST
	action_used = true
	if stat == "hp":
		unit["max_hp"] = float(unit["max_hp"]) + amount
		unit["hp"] = float(unit["hp"]) + amount
		_log("仓曹蚁积粮（-%d 食物）：+%.1f 最大生命【永久】。" % [TRAIN_COST, amount])
	else:
		unit["atk"] = float(unit["atk"]) + amount
		_log("仓曹蚁积粮（-%d 食物）：+%.1f 攻击【永久】。" % [TRAIN_COST, amount])
	_start_battle()


func _skip_action() -> void:
	if phase != Phase.ACTION:
		return
	_log("本回合不经营，直接迎战。")
	_start_battle()


# ---------------------------------------------------------------------------
# 战斗
# ---------------------------------------------------------------------------

func _prepare_enemies() -> void:
	enemies = []
	match turn:
		1:
			_add_enemy("工蚁", 9.0, 1.5, "前排")
			_add_enemy("工蚁", 9.0, 1.5, "前排")
		2:
			_add_enemy("兵蚁", 10.0, 2.0, "前排")
			_add_enemy("兵蚁", 10.0, 2.0, "前排")
			_add_enemy("结网蛛", 8.0, 2.0, "后排")
		_:
			_add_enemy("盾甲", 16.0, 1.5, "前排", 2.0)
			_add_enemy("锹甲", 12.0, 2.5, "前排")
			_add_enemy("结网蛛", 9.0, 2.0, "后排")


func _add_enemy(name: String, hp: float, atk: float, row: String, shield := 0.0) -> void:
	enemies.append({
		"name": name, "hp": hp, "max_hp": hp, "atk": atk, "row": row,
		"shield": shield, "battle_atk": 0.0, "death_done": false, "is_enemy": true,
	})


func _start_battle() -> void:
	if phase != Phase.ACTION:
		return
	action_used = false
	_prepare_enemies()
	battle_round = 0
	for unit in army:
		unit["battle_atk"] = 0.0
		unit["shield"] = 0.0
		unit["death_done"] = false
	# 迅捷：候望蚁开战 +1.0 攻击（MVP 简化）。
	for unit in army:
		if str(unit["id"]) == "houwang":
			unit["battle_atk"] = float(unit["battle_atk"]) + 1.0
	_log("战斗开始：敌方 %d 单位。候望蚁迅捷 +1.0 攻击【战时】。" % enemies.size())
	phase = Phase.BATTLE
	busy = true
	_refresh()
	_run_battle()


func _run_battle() -> void:
	while phase == Phase.BATTLE and battle_round < 12:
		battle_round += 1
		_log("—— 第 %d 轮 ——" % battle_round)
		_apply_round_start()
		_player_phase()
		if _alive_enemies().is_empty():
			break
		_enemy_phase()
		_refresh()
		await get_tree().create_timer(0.55).timeout
		if _alive_enemies().is_empty() or _alive_army().is_empty():
			break
	_finish_battle()


func _apply_round_start() -> void:
	# 点卯：攻击最低的友军 +1.0 攻击【战时】。
	for unit in army:
		if str(unit["id"]) == "yunnou" and float(unit["hp"]) > 0.0:
			var lowest := {}
			var lowest_atk := INF
			for other in army:
				if float(other["hp"]) <= 0.0:
					continue
				var value := float(other["atk"]) + float(other["battle_atk"])
				if value < lowest_atk:
					lowest_atk = value
					lowest = other
			if not lowest.is_empty():
				lowest["battle_atk"] = float(lowest["battle_atk"]) + 1.0
				_log("耘耨蚁点卯：%s +1.0 攻击【战时】。" % str(lowest["name"]))


func _player_phase() -> void:
	for unit in army:
		if phase != Phase.BATTLE:
			return
		if float(unit["hp"]) <= 0.0:
			continue
		_attack(unit, enemies)
		# 角质化：弧矢蚁 30% 追加一次攻击。
		if str(unit["id"]) == "hushi" and float(unit["hp"]) > 0.0 and rng.randf() < 0.3:
			var target := _pick_target(enemies)
			if not target.is_empty():
				_log("弧矢蚁角质化：追加一次攻击。")
				_attack(unit, enemies, true)
		if _alive_enemies().is_empty():
			return


func _enemy_phase() -> void:
	for enemy in enemies:
		if float(enemy["hp"]) <= 0.0:
			continue
		_attack(enemy, army)
		if _alive_army().is_empty():
			return


func _attack(attacker: Dictionary, targets: Array[Dictionary], extra := false) -> void:
	var target := _pick_target(targets)
	if target.is_empty():
		return
	var atk := float(attacker["atk"]) + float(attacker.get("battle_atk", 0.0))
	var damage := maxf(0.1, atk * rng.randf_range(0.9, 1.1))
	var absorbed := minf(float(target.get("shield", 0.0)), damage)
	if absorbed > 0.0:
		target["shield"] = float(target["shield"]) - absorbed
		damage -= absorbed
	target["hp"] = float(target["hp"]) - damage
	# 余勇：烽燧蚁每次实际掉血 +0.5 最大生命【永久】，并立即回复新增部分。
	if damage > 0.0 and str(target.get("id", "")) == "fengsui":
		target["max_hp"] = float(target["max_hp"]) + 0.5
		target["hp"] = float(target["hp"]) + 0.5
		_log("烽燧蚁余勇：+0.5 最大生命【永久】。")
	var tag := "追加 " if extra else ""
	_log("%s%s → %s：%.1f 伤害（剩余 %.1f）" % [
		tag, str(attacker["name"]), str(target["name"]), damage,
		maxf(0.0, float(target["hp"]))
	])
	if float(target["hp"]) <= 0.0:
		_on_death(target, targets)


func _pick_target(targets: Array[Dictionary]) -> Dictionary:
	var alive: Array[Dictionary] = []
	for target in targets:
		if float(target["hp"]) > 0.0:
			alive.append(target)
	if alive.is_empty():
		return {}
	var front: Array[Dictionary] = []
	for target in alive:
		if str(target["row"]) == "前排":
			front.append(target)
	var pool := front if not front.is_empty() else alive
	return pool[rng.randi_range(0, pool.size() - 1)]


func _on_death(target: Dictionary, _targets: Array[Dictionary]) -> void:
	if bool(target.get("death_done", false)):
		return
	target["death_done"] = true
	_log("%s 阵亡。" % str(target["name"]))
	# 不甘：燧火蚁阵亡时，敌方前排每单位受到 1.0 伤害。
	if str(target.get("id", "")) == "suihuo":
		for enemy in enemies:
			if float(enemy["hp"]) > 0.0 and str(enemy["row"]) == "前排":
				enemy["hp"] = float(enemy["hp"]) - 1.0
				_log("燧火蚁不甘：%s 受到 1.0 伤害（剩余 %.1f）。" % [str(enemy["name"]), maxf(0.0, float(enemy["hp"]))])
	# 余勇（烽燧蚁）在 _attack 里按每次实际掉血结算。


func _finish_battle() -> void:
	busy = false
	var victory := _alive_enemies().is_empty()
	for unit in army:
		unit["hp"] = float(unit["max_hp"])
		unit["battle_atk"] = 0.0
		unit["shield"] = 0.0
		unit["death_done"] = false
	var production := plants * PLANT_FOOD
	food += production
	var text := ""
	if victory:
		food += 3
		text = "战斗胜利：战利品 +3 食物；植物产出 +%d 食物；全队生命回满。" % production
		_log(text)
	else:
		nest = maxf(0.0, nest - 5.0)
		text = "战斗失败：巢穴 −5 完整度；植物产出 +%d 食物；全队生命回满。" % production
		_log(text)
	phase = Phase.RESULT
	side_body.set_meta("result", text)
	if nest <= 0.0:
		phase = Phase.LOST
		_log("巢穴完整度归零，本局结束。")
	elif turn >= MAX_TURN:
		phase = Phase.WON
		_log("撑过 %d 回合，胜利。" % MAX_TURN)
	_refresh()


func _next_turn() -> void:
	if phase != Phase.RESULT or turn >= MAX_TURN:
		return
	turn += 1
	candidates = _roll_candidates()
	action_used = false
	phase = Phase.RECRUIT
	_log("第 %d 回合 · 招募事件：3 选 1（%d 食物）。" % [turn, RECRUIT_COST])
	_refresh()


func _finish_run() -> void:
	phase = Phase.WON
	_refresh()


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _add_unit(id: String) -> void:
	var def: Dictionary = UNIT_DEFS[id]
	army.append({
		"id": id, "name": str(def["name"]), "row": str(def["row"]),
		"hp": float(def["hp"]), "max_hp": float(def["hp"]), "atk": float(def["atk"]),
		"sig": str(def["sig"]), "desc": str(def["desc"]),
		"battle_atk": 0.0, "shield": 0.0, "death_done": false,
	})


func _has_unit(id: String) -> bool:
	for unit in army:
		if str(unit["id"]) == id:
			return true
	return false


func _first_unit(id: String) -> Dictionary:
	for unit in army:
		if str(unit["id"]) == id:
			return unit
	return {}


func _alive_army() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for unit in army:
		if float(unit["hp"]) > 0.0:
			out.append(unit)
	return out


func _alive_enemies() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for enemy in enemies:
		if float(enemy["hp"]) > 0.0:
			out.append(enemy)
	return out


func _log(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 80:
		log_lines = log_lines.slice(log_lines.size() - 80)


func _maybe_capture() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			var path := arg.substr("--shot=".length())
			await get_tree().process_frame
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			var error := image.save_png(path)
			print("screenshot saved: %s (error=%d)" % [path, error])
			get_tree().quit()
			return


## 开发用：-- --autoplay 自动打满 3 回合（招募第一候选 → 跳过经营 → 战斗），用于验证与截图。
func _maybe_autoplay() -> void:
	if not ("--autoplay" in OS.get_cmdline_user_args()):
		return
	print("autoplay: start")
	await get_tree().create_timer(0.3).timeout
	for i in range(MAX_TURN):
		if phase == Phase.RECRUIT:
			var pick := candidates[0] if not candidates.is_empty() else ""
			if "cangcao" in candidates:
				pick = "cangcao"
			if food >= RECRUIT_COST and pick != "":
				_recruit(pick)
			else:
				_skip_recruit()
			print("autoplay: turn %d recruit ok (food=%d army=%d)" % [turn, food, army.size()])
		await get_tree().create_timer(0.15).timeout
		if phase == Phase.ACTION:
			if i == 0 and food >= SEED_COST and plants < MAX_PLANTS:
				_do_seed()
			elif i == 1 and food >= SEED_COST and plants < MAX_PLANTS:
				_do_seed()
			elif i == 2 and _has_unit("cangcao") and food >= TRAIN_COST:
				_train_hp()
			else:
				_skip_action()
			print("autoplay: turn %d action done (food=%d plants=%d)" % [turn, food, plants])
		await get_tree().create_timer(5.0).timeout
		print("autoplay: turn %d resolved phase=%d" % [turn, phase])
		if phase == Phase.RESULT and turn < MAX_TURN:
			_next_turn()
			await get_tree().create_timer(0.2).timeout
	await _save_shot("D:/PROJECT/Hector/.screens/mvp-final.png")
	print("autoplay done: phase=%d turn=%d food=%d nest=%.1f army=%d" % [
		phase, turn, food, nest, army.size()
	])
	get_tree().quit()


func _save_shot(path: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	print("screenshot saved: %s (error=%d)" % [path, error])
