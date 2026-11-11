extends Control
## 主界面：程序化构建 UI，把 GameState 的状态画出来。
## M0 范围：巢穴视图 + HUD + 三选一 + 事件组选择 + 事件结算 + 日志。

const GameStateScript := preload("res://scripts/core/game_state.gd")
const DataStoreScript := preload("res://scripts/core/data_store.gd")
const EventPoolScript := preload("res://scripts/core/event_pool.gd")
const NestViewScript := preload("res://scripts/ui/nest_view.gd")

const INK := Color("201d18")
const MUTED := Color("6f6a60")
const PAPER := Color("f1ebdf")
const CARD_BG := Color(1, 1, 1, 0.72)
const CARD_LINE := Color(0.16, 0.14, 0.11, 0.16)
const ACCENT := Color("3d5a3a")        # 深苔绿：标题 / 高亮 / 主要按钮
const ACCENT_SOFT := Color("e2e8da")
const GOLD := Color("93641f")          # 食物 / 奖励
const DANGER := Color("a33a2a")        # 敌方 / 危险
const DANGER_SOFT := Color("f1ded8")

var game = null
var nest_view = null
var side_box: VBoxContainer
var footer_box: VBoxContainer
var log_label: RichTextLabel
var season_label: Label
var progress_label: Label
var weather_label: Label
var resources_label: Label
var seed_label: Label
var army_label: Label
var health_label: Label
var health_bar: ProgressBar
var data_warning: Label


func _ready() -> void:
	_build_theme()
	_build_ui()
	_start_game(0)
	var store = DataStoreScript.instance()
	store.data_reloaded.connect(_on_data_reloaded)
	_update_data_warning()
	_maybe_demo()
	_maybe_capture()


func _process(delta: float) -> void:
	DataStoreScript.instance().poll(delta)
	_update_data_warning()


func _on_data_reloaded(_version: int) -> void:
	if game != null:
		game.reload_data()
	_update_data_warning()


func _update_data_warning() -> void:
	if data_warning == null:
		return
	var store = DataStoreScript.instance()
	if store.last_error.is_empty():
		data_warning.visible = false
		data_warning.text = ""
		return
	data_warning.visible = true
	data_warning.text = "⚠ 数据未生效（保留旧版本）：%s" % store.last_error


## 开发用：-- --demo-event / --demo-deploy / --demo-battle / --demo-recruit 直达对应界面。
func _maybe_demo() -> void:
	var args := OS.get_cmdline_user_args()
	if "--demo-actions" in args:
		game.phase = GameStateScript.Phase.ACTION
		game.changed.emit()
		return
	if "--demo-end" in args:
		game.health = 0
		game.phase = GameStateScript.Phase.GAME_OVER
		game.changed.emit()
		return
	if not (
		"--demo-deploy" in args
		or "--demo-battle" in args
		or "--demo-recruit" in args
		or "--demo-event" in args
	):
		return
	var is_recruit := "--demo-recruit" in args
	var show_event := "--demo-event" in args
	var demo_event := {
		"id": "demo_battle" if not is_recruit else "demo_recruit",
		"category": "self" if is_recruit else "enemy_strong",
		"pressure": not is_recruit,
		"title": "育婴室" if is_recruit else "演示战",
		"text": "开发用演示。",
		"effects": {} if is_recruit else {},
	}
	if is_recruit:
		demo_event["recruit"] = true
	else:
		demo_event["battle"] = "bird"
	if not is_recruit and game.army.is_empty():
		for unit_id in ["houwang", "hushi", "kuiliang"]:
			game.army.append(game._new_army_unit(unit_id))
	game.active_group = {
		"events": [demo_event],
		"categories": ["self" if is_recruit else "enemy_strong"],
		"pressure": 0 if is_recruit else 1,
	}
	game.event_index = 0
	game.phase = GameStateScript.Phase.EVENT
	if is_recruit:
		game.ready_up()
	elif not show_event:
		game.choose_encounter("fight")
	if "--demo-battle" in args:
		game.start_battle()
		if "--demo-select" in args:
			var picked := false
			for row in ["front", "back"]:
				if picked:
					break
				for unit in game.battle.get("player", {}).get(row, []):
					if bool(unit["alive"]) and float(unit["atk"]) > 0.0:
						game.select_player(int(unit["uid"]))
						picked = true
						break
	else:
		game.changed.emit()


## 开发用：带着 -- --shot=<绝对路径> 启动时，渲染两帧后截图并退出。
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


func _build_theme() -> void:
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "SimHei",
		"Noto Sans CJK SC", "Arial Unicode MS",
	])
	font.allow_system_fallback = true
	theme.default_font = font
	theme.default_font_size = 18

	theme.set_color("font_color", "Label", INK)
	theme.set_stylebox("normal", "Button", _button_style(Color(1, 1, 1, 0.92), CARD_LINE))
	theme.set_stylebox("hover", "Button", _button_style(ACCENT_SOFT, ACCENT))
	theme.set_stylebox("pressed", "Button", _button_style(Color("d3ddc7"), ACCENT))
	theme.set_stylebox("disabled", "Button", _button_style(Color(1, 1, 1, 0.38), Color(0, 0, 0, 0.10)))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", ACCENT)
	theme.set_color("font_pressed_color", "Button", ACCENT)
	theme.set_color("font_disabled_color", "Button", Color("a39d92"))
	theme.set_color("font_hover_color", "Label", INK)
	self.theme = theme


func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_BG
	style.border_color = CARD_LINE
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 14
	return style


func _card_style(bg: Color = Color(1, 1, 1, 0.55), border: Color = CARD_LINE) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	return panel


func _chip(text: String, bg: Color = Color(1, 1, 1, 0.82), fg: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", fg)
	label.add_theme_font_size_override("font_size", 15)
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = CARD_LINE
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	label.add_theme_stylebox_override("normal", style)
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
		margin.add_theme_constant_override("margin_" + side, 18)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	column.add_child(_build_hud())

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 800
	column.add_child(split)
	split.add_child(_build_nest_panel())
	split.add_child(_build_side_panel())

	column.add_child(_build_log_panel())


func _build_hud() -> Control:
	var panel := _panel()
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 0)
	box.add_child(left)

	season_label = Label.new()
	season_label.add_theme_font_size_override("font_size", 23)
	season_label.add_theme_color_override("font_color", ACCENT)
	left.add_child(season_label)

	progress_label = Label.new()
	progress_label.add_theme_color_override("font_color", MUTED)
	progress_label.add_theme_font_size_override("font_size", 14)
	left.add_child(progress_label)

	weather_label = Label.new()
	weather_label.add_theme_color_override("font_color", MUTED)
	weather_label.add_theme_font_size_override("font_size", 14)
	weather_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(weather_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	resources_label = _chip("食物 0", Color("f7efd9"), GOLD)
	box.add_child(resources_label)

	seed_label = _chip("种子 0")
	box.add_child(seed_label)

	army_label = _chip("军队 0/7")
	box.add_child(army_label)

	health_label = _chip("完整度 100/100")
	box.add_child(health_label)

	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(170, 16)
	health_bar.show_percentage = false
	health_bar.max_value = 100
	health_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_health_bar(health_bar)
	box.add_child(health_bar)

	return panel


func _style_health_bar(bar: ProgressBar) -> void:
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.7)
	back.border_color = CARD_LINE
	back.set_border_width_all(1)
	back.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", back)
	_tint_health_bar(bar)


func _tint_health_bar(bar: ProgressBar) -> void:
	if bar == null:
		return
	var ratio := 0.0 if bar.max_value <= 0.0 else bar.value / bar.max_value
	var fill := StyleBoxFlat.new()
	fill.bg_color = DANGER if ratio < 0.3 else (GOLD if ratio < 0.6 else ACCENT)
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)


func _build_nest_panel() -> Control:
	var panel := _panel()
	panel.custom_minimum_size = Vector2(540, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nest_view = NestViewScript.new()
	nest_view.clip_contents = true
	nest_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nest_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(nest_view)
	return panel


func _build_side_panel() -> Control:
	var panel := _panel()
	panel.custom_minimum_size = Vector2(440, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	side_box = VBoxContainer.new()
	side_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_box.add_theme_constant_override("separation", 8)
	scroll.add_child(side_box)

	# 阶段主按钮固定在这里，内容再长也不必滚到底才能继续。
	footer_box = VBoxContainer.new()
	footer_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_box.add_theme_constant_override("separation", 6)
	column.add_child(footer_box)
	return panel


func _build_log_panel() -> Control:
	var panel := _panel()
	panel.custom_minimum_size = Vector2(0, 138)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	var title := _section("日志")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var log_hint := _hint("最近 8 条记录")
	log_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	log_hint.size_flags_horizontal = Control.SIZE_SHRINK_END
	header.add_child(log_hint)

	data_warning = Label.new()
	data_warning.visible = false
	data_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	data_warning.add_theme_color_override("font_color", DANGER)
	data_warning.add_theme_font_size_override("font_size", 13)
	box.add_child(data_warning)

	log_label = RichTextLabel.new()
	log_label.fit_content = false
	log_label.scroll_following = true
	log_label.custom_minimum_size = Vector2(0, 92)
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.add_theme_color_override("default_color", INK)
	log_label.add_theme_font_size_override("normal_font_size", 14)
	log_label.add_theme_constant_override("line_separation", 3)
	box.add_child(log_label)
	return panel


func _start_game(p_seed: int) -> void:
	if game != null and game.changed.is_connected(_refresh):
		game.changed.disconnect(_refresh)
	game = GameStateScript.new(p_seed)
	game.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if game == null or nest_view == null:
		return

	season_label.text = "%s %d/%d 回合 · 总 %d/%d" % [
		game.season_name(), game.turn_in_season(), GameStateScript.TURNS_PER_SEASON,
		game.turn, GameStateScript.TOTAL_TURNS
	]
	progress_label.text = _phase_text()
	weather_label.text = game.weather_forecast_text()
	resources_label.text = "食物 %d" % int(game.resources["food"])
	seed_label.text = "种子 %d · 已种 %d" % [game.seeds.size(), game.planted.size()]
	army_label.text = "军队 %d/%d" % [game.army.size(), int(game.balance["army"]["max_size"])]
	health_label.text = "完整度 %d/%d" % [int(game.health), int(game.max_health())]
	health_bar.max_value = game.max_health()
	health_bar.value = game.health
	_tint_health_bar(health_bar)

	_build_side()
	nest_view.set_data(game.cells, game.nest_level)

	log_label.bbcode_enabled = true
	var recent: Array = game.logs.slice(maxi(0, game.logs.size() - 8))
	var lines := PackedStringArray()
	for line in recent:
		lines.append(_log_line(str(line)))
	log_label.text = "\n".join(lines)


## 日志着色：危险红、收益金、回合 / 战斗标题绿。bbcode 里的 "[" 需要转义。
func _log_line(line: String) -> String:
	var text := line.replace("[", "[lb]")
	if "失去" in line or "失败" in line or "失守" in line or "退场" in line or "归零" in line:
		return "[color=#a33a2a]%s[/color]" % text
	if "获得" in line or "拾遗" in line or "奖励" in line or "战利品" in line:
		return "[color=#93641f]%s[/color]" % text
	if "战斗开始" in line or "开局" in line:
		return "[color=#3d5a3a]%s[/color]" % text
	return text


func _phase_text() -> String:
	match game.phase:
		GameStateScript.Phase.ACTION:
			return "选择主观行动"
		GameStateScript.Phase.GROUP_SELECT:
			return "选择事件组"
		GameStateScript.Phase.EVENT:
			return "事件 %s · %d/%d" % [
				GameStateScript.EVENT_LETTERS[game.event_index],
				game.event_index + 1, GameStateScript.GROUP_SIZE
			]
		GameStateScript.Phase.BATTLE:
			return "战斗 · 第 %d 轮" % int(game.battle.get("round", 1))
		GameStateScript.Phase.DEPLOY:
			return "布阵 · 出战 %d" % game.deployed_count()
		GameStateScript.Phase.RECRUIT:
			return "%s招募 · 免费 %d 次 · 可反复招募" % [
				"事件" if game.recruit_context == "event" else "", game.free_recruits_left
			]
		GameStateScript.Phase.GAME_OVER:
			return "本局失败"
		GameStateScript.Phase.WON:
			return "春季结束"
	return ""


func _build_side() -> void:
	for child in side_box.get_children():
		side_box.remove_child(child)
		child.queue_free()
	for child in footer_box.get_children():
		footer_box.remove_child(child)
		child.queue_free()

	match game.phase:
		GameStateScript.Phase.ACTION:
			_build_actions()
		GameStateScript.Phase.GROUP_SELECT:
			_build_groups()
		GameStateScript.Phase.EVENT:
			_build_event()
		GameStateScript.Phase.DEPLOY:
			_build_deploy()
		GameStateScript.Phase.BATTLE:
			_build_battle()
		GameStateScript.Phase.RECRUIT:
			_build_recruit()
		GameStateScript.Phase.GAME_OVER, GameStateScript.Phase.WON:
			_build_end()


func _build_actions() -> void:
	side_box.add_child(_title("主观行动（三选一）"))
	side_box.add_child(_hint("拿着本回合的产出，只能做一件事；播种不占行动。"))
	side_box.add_child(_hint("巢穴 Lv.%d · 肥沃格 %d（空 %d）· 经验 %d" % [
		game.nest_level, game.fertile_count(), game.free_fertile_cells().size(), game.exp_points
	]))
	side_box.add_child(_divider())

	var heal_cost := int(game.balance["actions"]["heal"]["food_cost"])
	var heal_gain := int(game.balance["actions"]["heal"]["health"])
	var health_full: bool = game.health >= game.max_health()
	_add_action_button(
		"冒险", "外出探索：食物 -1~2（雨天 / 春季 +1），回来 +2~4，可能带回种子；巢穴 -2", "adventure"
	)
	_add_action_button(
		"巢穴恢复",
		"消耗 %d 食物，巢穴完整度 +%d（唯一的恢复手段）%s" % [
			heal_cost, heal_gain, " · 完整度已满" if health_full else ""
		],
		"heal",
		health_full or int(game.resources["food"]) < heal_cost
	)
	var expand_cost := 0
	var at_max_level: bool = game.nest_level >= int(game.balance["nest"]["max_level"])
	var thresholds: Array = game.balance["actions"]["expand"].get("exp_threshold", [0, 20, 30])
	if not at_max_level:
		expand_cost = maxi(0, int(thresholds[game.nest_level]) - game.exp_points)
	if at_max_level:
		_add_action_button(
			"巢穴扩建", "巢穴已达最高等级 Lv.%d，肥沃格全部开放。" % game.nest_level, "expand", true
		)
	else:
		_add_action_button(
			"巢穴扩建", "走巢穴经验线：1 食物 = 1 经验，本次需 %d 食物（Lv.%d → Lv.%d，+3 肥沃格）%s" % [
				expand_cost, game.nest_level, mini(game.nest_level + 1, 3),
				" · 食物不足" if int(game.resources["food"]) < expand_cost else ""
			],
			"expand",
			int(game.resources["food"]) < expand_cost
		)

	_build_training()

	if not game.seeds.is_empty():
		side_box.add_child(_section("种子袋（播种不占行动）"))
		for seed_id in game.seeds:
			var info: Dictionary = game.seed_info(seed_id)
			var button := Button.new()
			button.text = "播种【%s】— 每 %d 事件产出 %d %s" % [
				str(info.get("name", seed_id)), int(info.get("period", 3)),
				int(info.get("yield", 1)), _seed_yield_name(str(info.get("kind", "food")))
			]
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.custom_minimum_size = Vector2(0, 40)
			button.disabled = game.free_fertile_cells().is_empty()
			button.pressed.connect(_on_plant.bind(seed_id))
			side_box.add_child(button)

	if not game.planted.is_empty():
		side_box.add_child(_section("已播种"))
		for entry in game.planted:
			var info: Dictionary = game.seed_info(str(entry["seed_id"]))
			var period := maxi(1, int(info.get("period", 3)))
			side_box.add_child(_hint("【%s】%d/%d 事件 → %d %s" % [
				str(info.get("name", "")), int(entry["counter"]), period,
				int(info.get("yield", 1)), _seed_yield_name(str(info.get("kind", "food")))
			]))


func _seed_yield_name(kind: String) -> String:
	match kind:
		"food":
			return "食物"
		"warspoil":
			return "战果"
		"tool_heal":
			return "巢穴恢复"
	return "产出"


func _build_training() -> void:
	var trainers: Array = []
	for entry in game.army:
		var data: Dictionary = game.unit_info(str(entry.get("unit_id", "")))
		if str(data.get("signature", {}).get("id", "")) == "jiliang":
			trainers.append(entry)
	if trainers.is_empty():
		return
	side_box.add_child(_section("积粮（仓曹蚁，每只每回合 1 次，2 食物）"))
	for entry in trainers:
		var uid := int(entry["uid"])
		var data: Dictionary = game.unit_info(str(entry["unit_id"]))
		var box := HBoxContainer.new()
		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_font_size_override("font_size", 14)
		info.text = "%s  生命 %.1f · 攻击 %.1f" % [
			str(data.get("name", "仓曹蚁")), float(entry.get("max_hp", 0.0)), float(entry.get("attack", 0.0))
		]
		box.add_child(info)
		var can_train: bool = game.can_train_cangcao(uid)
		for stat in ["hp", "attack"]:
			var button := Button.new()
			button.text = "生命 +3" if stat == "hp" else "攻击 +2"
			button.custom_minimum_size = Vector2(78, 34)
			button.disabled = not can_train
			button.pressed.connect(_on_train.bind(uid, stat))
			box.add_child(button)
		side_box.add_child(box)


func _build_groups() -> void:
	side_box.add_child(_title("选择事件组（%d 选 1）" % game.groups.size()))
	side_box.add_child(_hint("每组 4 个事件，按 A→B→C→D 结算；敌对压力基本不可避免。"))
	side_box.add_child(_divider())

	for index in game.groups.size():
		var group: Dictionary = game.groups[index]
		var pressure := int(group.get("pressure", 0))
		var card := _card()
		var layout := VBoxContainer.new()
		layout.add_theme_constant_override("separation", 4)
		card.add_child(layout)

		var button := Button.new()
		button.text = "%s ｜ %s" % [
			EventPoolScript.group_title(index), EventPoolScript.describe(group)
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size = Vector2(0, 56)
		button.pressed.connect(_on_group.bind(index))
		layout.add_child(button)

		var chip_row := HBoxContainer.new()
		chip_row.add_theme_constant_override("separation", 8)
		chip_row.add_child(_chip("4 个事件"))
		chip_row.add_child(_chip(
			"%d 个压力事件" % pressure,
			DANGER_SOFT if pressure > 0 else Color(1, 1, 1, 0.82),
			DANGER if pressure > 0 else MUTED
		))
		layout.add_child(chip_row)
		side_box.add_child(card)


func _build_event() -> void:
	var event: Dictionary = game.current_event()
	var letter: String = GameStateScript.EVENT_LETTERS[game.event_index]

	side_box.add_child(_title("事件 %s：%s" % [letter, str(event.get("title", ""))]))
	side_box.add_child(_hint(str(EventPoolScript.CATEGORY_NAMES.get(
		str(event.get("category", "")), "未知类别"
	))))

	var body := Label.new()
	body.text = str(event.get("text", ""))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(0, 72)
	side_box.add_child(body)

	var options: Array = event.get("options", [])
	if not options.is_empty():
		side_box.add_child(_hint("进度 %d/4 · 选择一个结果（选项代价为春季切片值）" % (game.event_index + 1)))
		for i in options.size():
			var opt: Dictionary = options[i]
			var opt_button := Button.new()
			opt_button.text = str(opt.get("label", "选项"))
			opt_button.custom_minimum_size = Vector2(0, 46)
			opt_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if opt.has("food_cost"):
				opt_button.disabled = int(game.resources["food"]) < int(opt["food_cost"])
			opt_button.pressed.connect(_on_event_option.bind(i))
			side_box.add_child(opt_button)
		return

	var is_battle: bool = event.has("battle")
	side_box.add_child(_hint(("战利品：" if is_battle else "影响：") + _effects_text(event.get("effects", {}))))
	if is_battle:
		side_box.add_child(_hint("敌方：%s · 出战不扣食物" % game.battle_tier_name(event["battle"])))
		side_box.add_child(_hint("谈判 / 回避的代价见事件选项；旧式事件仍用 2 食物占位（Q-084）。"))
		var fight_button := Button.new()
		fight_button.text = "迎战（进入布阵）"
		fight_button.custom_minimum_size = Vector2(0, 48)
		_primary_style(fight_button)
		fight_button.pressed.connect(_on_encounter.bind("fight"))
		side_box.add_child(fight_button)

		var talk_button := Button.new()
		talk_button.text = "谈判（-2 食物，不战斗）"
		talk_button.custom_minimum_size = Vector2(0, 44)
		talk_button.disabled = int(game.resources["food"]) < 2
		talk_button.pressed.connect(_on_encounter.bind("talk"))
		side_box.add_child(talk_button)

		var avoid_button := Button.new()
		avoid_button.text = "回避（放弃战利品）"
		avoid_button.custom_minimum_size = Vector2(0, 44)
		avoid_button.pressed.connect(_on_encounter.bind("avoid"))
		side_box.add_child(avoid_button)
	else:
		side_box.add_child(_hint("进度 %d/4" % (game.event_index + 1)))
		var button := Button.new()
		button.text = "准备就绪"
		button.custom_minimum_size = Vector2(0, 52)
		_primary_style(button)
		button.pressed.connect(_on_ready_up)
		side_box.add_child(button)


func _army_by_uid(uid: int) -> Dictionary:
	for entry in game.army:
		if int(entry.get("uid", 0)) == uid:
			return entry
	return {}


func _build_deploy() -> void:
	var front_cap := int(game.balance["army"]["front"])
	var back_cap := int(game.balance["army"]["back"])
	var front_used := 0
	var back_used := 0
	for entry in game.deploy_units:
		if not bool(entry.get("deployed", false)):
			continue
		if str(entry.get("row", "")) == "front":
			front_used += 1
		else:
			back_used += 1

	side_box.add_child(_title("布阵"))
	side_box.add_child(_hint("前排 %d/%d · 后排 %d/%d · 出战 %d 个" % [
		front_used, front_cap, back_used, back_cap, game.deployed_count()
	]))
	side_box.add_child(_hint("布阵确认后直接开战，出战不扣食物（Q-052）。空位允许。"))
	side_box.add_child(_divider())

	var front_full: bool = front_used >= front_cap
	var back_full: bool = back_used >= back_cap
	for entry in game.deploy_units:
		var uid := int(entry["uid"])
		var data: Dictionary = game.unit_info(str(entry["unit_id"]))
		var army_entry := _army_by_uid(uid)
		var hp := float(army_entry.get("max_hp", data.get("hp", 0.0)))
		var atk := float(army_entry.get("attack", data.get("attack", 0.0)))
		var fixed_row := str(data.get("row", "either"))
		var deployed := bool(entry["deployed"])
		var current_row := str(entry.get("row", ""))

		var card := _card()
		var layout := VBoxContainer.new()
		layout.add_theme_constant_override("separation", 4)
		card.add_child(layout)

		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "%s · 生命 %.1f / 攻击 %.1f · %s%s" % [
			str(entry["name"]), hp, atk,
			"前排" if current_row == "front" else ("后排" if current_row == "back" else "未上场"),
			"" if deployed else "（后备）"
		]
		label.add_theme_font_size_override("font_size", 15)
		layout.add_child(label)

		var buttons := HBoxContainer.new()
		buttons.add_theme_constant_override("separation", 6)
		for row in ["front", "back"]:
			var cap_full: bool = front_full if row == "front" else back_full
			var already_there: bool = deployed and current_row == row
			var wrong_row: bool = fixed_row != "either" and fixed_row != row
			var row_button := Button.new()
			row_button.text = "前" if row == "front" else "后"
			row_button.custom_minimum_size = Vector2(52, 34)
			row_button.disabled = already_there or wrong_row or (cap_full and not already_there)
			if wrong_row:
				row_button.tooltip_text = "该单位只能站%s" % ("前排" if fixed_row == "front" else "后排")
			elif cap_full and not already_there:
				row_button.tooltip_text = "%s已满" % ("前排" if row == "front" else "后排")
			row_button.pressed.connect(_on_deploy.bind(uid, row))
			buttons.add_child(row_button)
		var out_button := Button.new()
		out_button.text = "撤下"
		out_button.custom_minimum_size = Vector2(64, 34)
		out_button.disabled = not deployed
		out_button.pressed.connect(_on_deploy.bind(uid, ""))
		buttons.add_child(out_button)
		layout.add_child(buttons)
		side_box.add_child(card)

	var start_button := Button.new()
	start_button.text = "开战"
	start_button.custom_minimum_size = Vector2(0, 50)
	start_button.disabled = not game.can_start_battle()
	_primary_style(start_button)
	start_button.pressed.connect(_on_start_battle)
	footer_box.add_child(start_button)
	if not game.can_start_battle():
		footer_box.add_child(_hint("至少派 1 个单位上场才能开战。"))

	var avoid_button := Button.new()
	avoid_button.text = "避战（不结算；谈判 / 回避规则待定）"
	avoid_button.custom_minimum_size = Vector2(0, 40)
	avoid_button.pressed.connect(_on_avoid)
	footer_box.add_child(avoid_button)


func _build_end() -> void:
	var won: bool = game.phase == GameStateScript.Phase.WON
	side_box.add_child(_title("春季结束" if won else "巢穴失守"))
	side_box.add_child(_hint(
		game.season_summary() if won else "第 %d 回合，巢穴完整度归零。" % game.turn
	))
	side_box.add_child(_divider())

	side_box.add_child(_section("本局统计"))
	side_box.add_child(_hint("回合 %d · 巢穴 Lv.%d" % [game.turn, game.nest_level]))
	side_box.add_child(_hint("完整度 %d/%d · 食物 %d" % [
		int(game.health), int(game.max_health()), int(game.resources["food"])
	]))
	side_box.add_child(_hint("军队 %d 只 · 种子 %d 粒（已种 %d）" % [
		game.army.size(), game.seeds.size(), game.planted.size()
	]))

	var button := Button.new()
	button.text = "重开一局"
	button.custom_minimum_size = Vector2(0, 52)
	_primary_style(button)
	button.pressed.connect(_on_restart)
	footer_box.add_child(button)


func _build_battle() -> void:
	var battle: Dictionary = game.battle
	side_box.add_child(_title("战斗 · 第 %d 轮" % int(battle.get("round", 1))))
	side_box.add_child(_hint("遭遇：%s" % str(battle.get("encounter_name", "遭遇"))))
	var attacker: Dictionary = game.selected_player()
	if attacker.is_empty():
		side_box.add_child(_hint("① 先点选我方单位 → ② 再点敌方目标。每个单位每轮 1 AP，顺序自由。"))
	elif float(attacker.get("atk", 0.0)) <= 0.0:
		side_box.add_child(_hint("已选【%s】：该单位没有攻击力，不能普攻，请另选一只。" % str(attacker["name"])))
	else:
		side_box.add_child(_hint("已选【%s】：攻击 %.1f · 剩余 AP %d → 点敌方目标。" % [
			str(attacker["name"]), float(attacker["atk"]), int(attacker["ap"])
		]))
	side_box.add_child(_divider())

	var players: Dictionary = battle.get("player", {})
	side_box.add_child(_section("我方（点选行动单位）"))
	for row in ["front", "back"]:
		var list: Array = players.get(row, [])
		if list.is_empty():
			side_box.add_child(_hint("  （空）"))
		for unit in list:
			var button := Button.new()
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.custom_minimum_size = Vector2(0, 38)
			if not bool(unit["alive"]):
				button.text = "  %s（已退场）" % str(unit["name"])
				button.disabled = true
				side_box.add_child(button)
				continue
			var selected: bool = int(unit["uid"]) == game.selected_uid
			var note := ""
			if int(unit.get("weaken", 0)) > 0:
				note += "  削弱×%d" % int(unit["weaken"])
			if float(unit.get("shield", 0.0)) > 0.0:
				note += "  护盾 %.1f" % float(unit["shield"])
			if float(unit.get("atk", 0.0)) <= 0.0:
				note += "  无攻击"
			button.text = "%s%s %s  %.1f/%.1f  AP %d/%d%s" % [
				"★ " if selected else "  ",
				"前" if row == "front" else "后", str(unit["name"]),
				float(unit["hp"]), float(unit["max_hp"]),
				int(unit["ap"]), int(unit["max_ap"]), note
			]
			button.disabled = int(unit["ap"]) <= 0
			if button.disabled:
				button.tooltip_text = "本回合已行动"
			elif float(unit.get("atk", 0.0)) <= 0.0:
				button.tooltip_text = "无攻击力，不能普攻"
			if selected:
				_select_style(button)
			button.pressed.connect(_on_select.bind(int(unit["uid"])))
			side_box.add_child(_unit_card(button, float(unit["hp"]), float(unit["max_hp"]), false))

	var enemies: Dictionary = battle.get("enemies", {})
	side_box.add_child(_section("敌方（点选目标）"))
	var can_attack: bool = not attacker.is_empty() and float(attacker.get("atk", 0.0)) > 0.0
	for row in ["front", "back"]:
		var list: Array = enemies.get(row, [])
		if list.is_empty():
			side_box.add_child(_hint("  （空）"))
		for index in list.size():
			var enemy: Dictionary = list[index]
			var button := Button.new()
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.custom_minimum_size = Vector2(0, 38)
			if not bool(enemy["alive"]):
				button.text = "  %s（已退场）" % str(enemy["name"])
				button.disabled = true
				side_box.add_child(button)
				continue
			var signature: Dictionary = enemy.get("signature", {})
			var note := ""
			if float(enemy.get("shield", 0.0)) > 0.0:
				note += "  护盾 %.1f" % float(enemy["shield"])
			if int(enemy.get("weaken", 0)) > 0:
				note += "  削弱×%d" % int(enemy["weaken"])
			var row_blocked: bool = row == "back" and game.enemies_front_alive()
			if row_blocked:
				note += "  前排未破"
			button.text = "  %s %s【%s】  %.1f/%.1f%s" % [
				"前" if row == "front" else "后", str(enemy["name"]),
				str(signature.get("name", "")), float(enemy["hp"]), float(enemy["max_hp"]), note
			]
			button.disabled = not can_attack or row_blocked
			if attacker.is_empty():
				button.tooltip_text = "先选一只我方单位"
			elif not can_attack:
				button.tooltip_text = "所选单位没有攻击力"
			elif row_blocked:
				button.tooltip_text = "敌方前排还活着"
			_danger_style(button)
			button.pressed.connect(_on_attack.bind(row, index))
			side_box.add_child(_unit_card(button, float(enemy["hp"]), float(enemy["max_hp"]), true))

	var end_button := Button.new()
	end_button.text = "结束玩家阶段 → 敌方行动"
	end_button.custom_minimum_size = Vector2(0, 46)
	_primary_style(end_button)
	end_button.pressed.connect(_on_end_phase)
	footer_box.add_child(end_button)
	if game.player_has_ap():
		footer_box.add_child(_hint("还有单位可以行动；也可以直接结束本方阶段。"))
	else:
		footer_box.add_child(_hint("我方单位都已行动，可以结束阶段。"))


func _build_recruit() -> void:
	var is_event: bool = game.recruit_context == "event"
	side_box.add_child(_title(("事件招募" if is_event else "招募窗口") + " · 可反复招募"))
	var free_left: int = game.free_recruits_left
	var free_text := "免费招募剩余 %d 次。" % free_left if free_left > 0 else "招募按单位标价扣食物。"
	side_box.add_child(_hint("食物 %d · 军队 %d/%d" % [
		int(game.resources["food"]), game.army.size(), int(game.balance["army"]["max_size"])
	]))
	side_box.add_child(_hint("%s可以一直招募，直到点「结束招募」。" % free_text))
	side_box.add_child(_divider())

	side_box.add_child(_section("候选单位"))
	if game.recruit_candidates.is_empty():
		side_box.add_child(_hint("没有可招募的候选（食物不足或军队已满）。"))
	for unit_id in game.recruit_candidates:
		var data: Dictionary = game.unit_info(unit_id)
		var free: bool = free_left > 0
		var card := _card()
		var layout := VBoxContainer.new()
		layout.add_theme_constant_override("separation", 4)
		card.add_child(layout)

		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 44)
		button.text = "%s · %s — %s" % [
			game.tier_name(int(data.get("tier", 1))), str(data.get("name", unit_id)),
			("免费" if free else "%d 食物" % int(data.get("cost_food", 4)))
		]
		button.disabled = not game.can_recruit(unit_id)
		if button.disabled:
			button.tooltip_text = "军队已满或食物不足"
		button.pressed.connect(_on_recruit.bind(unit_id))
		layout.add_child(button)

		var signature: Dictionary = data.get("signature", {})
		var stats := Label.new()
		stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stats.add_theme_font_size_override("font_size", 13)
		stats.add_theme_color_override("font_color", MUTED)
		stats.text = "%s · 生命 %.1f / 攻击 %.1f · 【%s】%s" % [
			str(data.get("role", "")),
			float(data.get("hp", 0.0)), float(data.get("attack", 0.0)),
			str(signature.get("name", "")), str(signature.get("text", ""))
		]
		layout.add_child(stats)
		side_box.add_child(card)

	var refresh_cost := int(game.balance["recruit"]["refresh_cost"])
	var refresh_button := Button.new()
	if game.free_refreshes > 0:
		refresh_button.text = "刷新候选（免费，剩 %d 次）" % game.free_refreshes
	else:
		refresh_button.text = "刷新候选（%d 食物）" % refresh_cost
	refresh_button.custom_minimum_size = Vector2(0, 42)
	refresh_button.disabled = game.free_refreshes <= 0 and int(game.resources["food"]) < refresh_cost
	refresh_button.pressed.connect(_on_refresh)
	side_box.add_child(refresh_button)

	if not game.army.is_empty():
		side_box.add_child(_section("当前军队（可卖出）"))
		for entry in game.army:
			var data: Dictionary = game.unit_info(str(entry.get("unit_id", "")))
			var uid := int(entry["uid"])
			var card := _card()
			var layout := VBoxContainer.new()
			layout.add_theme_constant_override("separation", 4)
			card.add_child(layout)

			var info := Label.new()
			info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info.add_theme_font_size_override("font_size", 14)
			info.text = "%s · 生命 %.1f · 攻击 %.1f · %s%s" % [
				str(data.get("name", entry.get("unit_id", ""))),
				float(entry.get("max_hp", 0.0)), float(entry.get("attack", 0.0)),
				_row_name(str(data.get("row", "either"))),
				" · 出战 %d 场" % int(entry.get("battles", 0)) if int(entry.get("battles", 0)) > 0 else ""
			]
			layout.add_child(info)

			var sell_button := Button.new()
			sell_button.text = "卖出 +%d 食物" % game.sell_price(uid)
			sell_button.custom_minimum_size = Vector2(0, 34)
			sell_button.disabled = not game.can_sell(uid)
			if sell_button.disabled:
				sell_button.tooltip_text = "已在阵中或本回合已招募"
			sell_button.pressed.connect(_on_sell.bind(uid))
			layout.add_child(sell_button)
			side_box.add_child(card)

	var end_button := Button.new()
	end_button.text = "结束招募，下一步 →"
	end_button.custom_minimum_size = Vector2(0, 48)
	_primary_style(end_button)
	end_button.pressed.connect(_on_skip)
	footer_box.add_child(end_button)


func _row_name(row: String) -> String:
	match row:
		"front":
			return "前排"
		"back":
			return "后排"
	return "前后皆可"


func _section(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", ACCENT)
	return label


func _add_action_button(title: String, description: String, action_id: String, disabled := false) -> void:
	var button := Button.new()
	button.text = title
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 46)
	button.disabled = disabled
	button.pressed.connect(_on_action.bind(action_id))
	side_box.add_child(button)

	var label := Label.new()
	label.text = description
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", MUTED)
	label.add_theme_font_size_override("font_size", 13)
	side_box.add_child(label)


func _title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", INK)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", MUTED)
	label.add_theme_font_size_override("font_size", 14)
	return label


func _divider() -> Control:
	var line := ColorRect.new()
	line.color = CARD_LINE
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _hp_bar(value: float, max_value: float, fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 6)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.max_value = maxf(max_value, 0.001)
	bar.value = clampf(value, 0.0, bar.max_value)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.08)
	back.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


## 战斗单位卡：按钮 + 细血条（点击区域仍是按钮）。
func _unit_card(button: Button, hp: float, max_hp: float, hostile: bool) -> Control:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 2)
	card.add_child(button)
	if max_hp > 0.0:
		card.add_child(_hp_bar(hp, max_hp, DANGER if hostile else ACCENT))
	return card


## 候选 / 军队条目的浅色卡片容器。
func _card() -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return card


func _select_style(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _button_style(ACCENT_SOFT, ACCENT))
	button.add_theme_color_override("font_color", ACCENT)


func _primary_style(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _button_style(ACCENT, ACCENT))
	button.add_theme_stylebox_override("hover", _button_style(ACCENT.lightened(0.10), ACCENT))
	button.add_theme_stylebox_override("pressed", _button_style(ACCENT.darkened(0.12), ACCENT))
	button.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1, 0.96))
	button.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.96))


func _danger_style(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _button_style(Color(1, 1, 1, 0.85), DANGER))
	button.add_theme_color_override("font_color", DANGER)


func _effects_text(effects: Dictionary) -> String:
	var names := {
		"health": "巢穴", "food": "食物", "integrity_delta": "巢穴", "food_delta": "食物",
	}
	var parts: Array[String] = []
	for key in names.keys():
		if effects.has(key):
			var value := int(effects[key])
			if value != 0:
				parts.append("%s %s%d" % [names[key], "+" if value > 0 else "", value])
	if effects.has("seed") or effects.has("gain_seed"):
		var value = effects.get("seed", effects.get("gain_seed"))
		if value is String and str(value) != "":
			parts.append("种子 " + str(value))
		elif bool(value):
			parts.append("种子 +1")
	if parts.is_empty():
		return "无"
	return "，".join(parts)


func _on_action(action_id: String) -> void:
	game.choose_action(action_id)


func _on_deploy(uid: int, row: String) -> void:
	game.deploy_set(uid, row)


func _on_train(uid: int, stat: String) -> void:
	game.train_cangcao(uid, stat)


func _on_select(uid: int) -> void:
	game.select_player(uid)


func _on_sell(uid: int) -> void:
	game.sell_unit(uid)


func _on_start_battle() -> void:
	game.start_battle()


func _on_avoid() -> void:
	game.avoid_battle()


func _on_encounter(option: String) -> void:
	game.choose_encounter(option)


func _on_event_option(index: int) -> void:
	game.choose_event_option(index)


func _on_plant(seed_id: String) -> void:
	game.plant_seed(seed_id)


func _on_group(index: int) -> void:
	game.choose_group(index)


func _on_ready_up() -> void:
	game.ready_up()


func _on_attack(row: String, index: int) -> void:
	game.player_attack(row, index)


func _on_end_phase() -> void:
	game.end_player_phase()


func _on_recruit(unit_id: String) -> void:
	game.recruit(unit_id)


func _on_refresh() -> void:
	game.refresh_recruit()


func _on_skip() -> void:
	game.skip_recruit()


func _on_restart() -> void:
	_start_game(0)
