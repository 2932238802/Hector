extends Control
## 主界面：程序化构建 UI，把 GameState 的状态画出来。
## M0 范围：巢穴视图 + HUD + 三选一 + 事件组选择 + 事件结算 + 日志。

const GameStateScript := preload("res://scripts/core/game_state.gd")
const DataStoreScript := preload("res://scripts/core/data_store.gd")
const EventPoolScript := preload("res://scripts/core/event_pool.gd")
const NestViewScript := preload("res://scripts/ui/nest_view.gd")

const INK := Color("1a1a1a")
const MUTED := Color("6f6a60")
const PAPER := Color("f4f1ea")

var game = null
var nest_view = null
var side_box: VBoxContainer
var log_label: RichTextLabel
var season_label: Label
var progress_label: Label
var weather_label: Label
var resources_label: Label
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
		game.army.assign(["ruishi", "chihou", "caiwei"])
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
	theme.set_stylebox("normal", "Button", _button_style(Color(1, 1, 1, 0.92), Color(0, 0, 0, 0.55)))
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
	style.content_margin_top = 10
	style.content_margin_bottom = 10
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
	box.add_theme_constant_override("separation", 22)
	panel.add_child(box)

	season_label = Label.new()
	season_label.add_theme_font_size_override("font_size", 22)
	box.add_child(season_label)

	progress_label = Label.new()
	progress_label.add_theme_color_override("font_color", MUTED)
	box.add_child(progress_label)

	weather_label = Label.new()
	weather_label.add_theme_color_override("font_color", MUTED)
	weather_label.add_theme_font_size_override("font_size", 14)
	box.add_child(weather_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	resources_label = Label.new()
	box.add_child(resources_label)

	army_label = Label.new()
	box.add_child(army_label)

	health_label = Label.new()
	box.add_child(health_label)

	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(190, 18)
	health_bar.show_percentage = false
	health_bar.max_value = 100
	health_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_health_bar(health_bar)
	box.add_child(health_bar)

	return panel


func _style_health_bar(bar: ProgressBar) -> void:
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.7)
	back.border_color = Color(0, 0, 0, 0.35)
	back.set_border_width_all(1)
	back.set_corner_radius_all(2)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("3b3b3b")
	fill.set_corner_radius_all(2)

	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", fill)


func _build_nest_panel() -> Control:
	var panel := _panel()
	panel.custom_minimum_size = Vector2(540, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nest_view = NestViewScript.new()
	nest_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nest_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(nest_view)
	return panel


func _build_side_panel() -> Control:
	var panel := _panel()
	panel.custom_minimum_size = Vector2(440, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_box = VBoxContainer.new()
	side_box.add_theme_constant_override("separation", 8)
	panel.add_child(side_box)
	return panel


func _build_log_panel() -> Control:
	var panel := _panel()
	panel.custom_minimum_size = Vector2(0, 128)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	data_warning = Label.new()
	data_warning.visible = false
	data_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	data_warning.add_theme_color_override("font_color", Color("a33a2a"))
	data_warning.add_theme_font_size_override("font_size", 13)
	box.add_child(data_warning)
	log_label = RichTextLabel.new()
	log_label.fit_content = false
	log_label.scroll_following = true
	log_label.custom_minimum_size = Vector2(0, 96)
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.add_theme_color_override("default_color", INK)
	log_label.add_theme_font_size_override("normal_font_size", 14)
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
	resources_label.text = "食物 %d   巢穴经验 %d   种子 %d（已种 %d）" % [
		int(game.resources["food"]), game.exp_points, game.seeds.size(), game.planted.size()
	]
	army_label.text = "军队 %d/%d" % [game.army.size(), int(game.balance["army"]["max_size"])]
	health_label.text = "巢穴 %d/%d" % [int(game.health), int(game.max_health())]
	health_bar.max_value = game.max_health()
	health_bar.value = game.health

	_build_side()
	nest_view.set_data(game.cells, game.nest_level)

	var recent: Array = game.logs.slice(maxi(0, game.logs.size() - 8))
	log_label.text = "\n".join(PackedStringArray(recent))


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
			return "招募"
		GameStateScript.Phase.GAME_OVER:
			return "本局失败"
		GameStateScript.Phase.WON:
			return "春季结束"
	return ""


func _build_side() -> void:
	for child in side_box.get_children():
		side_box.remove_child(child)
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

	_add_action_button(
		"冒险", "外出探索：食物 -1~2（雨天 / 春季 +1），回来 +2~4，可能带回种子；巢穴 -2", "adventure"
	)
	_add_action_button(
		"巢穴恢复", "消耗 4 食物，巢穴完整度 +18（唯一的恢复手段）", "heal"
	)
	var expand_cost := 0
	var thresholds: Array = game.balance["actions"]["expand"].get("exp_threshold", [0, 20, 30])
	if game.nest_level < int(game.balance["nest"]["max_level"]):
		expand_cost = maxi(0, int(thresholds[game.nest_level]) - game.exp_points)
	_add_action_button(
		"巢穴扩建", "走巢穴经验线：1 食物 = 1 经验，本次需 %d 食物（Lv.%d → Lv.%d，+3 肥沃格）" % [
			expand_cost, game.nest_level, mini(game.nest_level + 1, 3)
		], "expand"
	)

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


func _build_groups() -> void:
	side_box.add_child(_title("选择事件组（%d 选 1）" % game.groups.size()))
	side_box.add_child(_hint("每组 4 个事件，按 A→B→C→D 结算；敌对压力基本不可避免。"))

	for index in game.groups.size():
		var group: Dictionary = game.groups[index]
		var button := Button.new()
		button.text = "%s ｜ %s" % [
			EventPoolScript.group_title(index), EventPoolScript.describe(group)
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 50)
		button.pressed.connect(_on_group.bind(index))
		side_box.add_child(button)

		var label := Label.new()
		label.text = "4 个事件，其中 %d 个压力事件" % int(group.get("pressure", 0))
		label.add_theme_color_override("font_color", MUTED)
		label.add_theme_font_size_override("font_size", 13)
		side_box.add_child(label)


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
		side_box.add_child(_hint("敌方：%s · 出战不扣食物" % game.battle_tier_name(str(event["battle"]))))
		side_box.add_child(_hint("谈判 / 回避的代价见事件选项；旧式事件仍用 2 食物占位（Q-084）。"))
		var fight_button := Button.new()
		fight_button.text = "迎战（进入布阵）"
		fight_button.custom_minimum_size = Vector2(0, 48)
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
		button.pressed.connect(_on_ready_up)
		side_box.add_child(button)


func _build_deploy() -> void:
	side_box.add_child(_title("布阵（前 %d / 后 %d）" % [
		int(game.balance["army"]["front"]), int(game.balance["army"]["back"])
	]))
	side_box.add_child(_hint("布阵确认后直接开战，出战不扣食物（Q-052）。空位允许。"))

	for entry in game.deploy_units:
		var box := HBoxContainer.new()
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%s · %s%s" % [
			str(entry["name"]), "前排" if str(entry["row"]) == "front" else "后排",
			"" if bool(entry["deployed"]) else "（后备）"
		]
		label.add_theme_font_size_override("font_size", 15)
		box.add_child(label)
		for row in ["front", "back"]:
			var row_button := Button.new()
			row_button.text = "前" if row == "front" else "后"
			row_button.custom_minimum_size = Vector2(44, 34)
			row_button.disabled = bool(entry["deployed"]) and str(entry["row"]) == row
			row_button.pressed.connect(_on_deploy.bind(str(entry["unit_id"]), row))
			box.add_child(row_button)
		var out_button := Button.new()
		out_button.text = "撤"
		out_button.custom_minimum_size = Vector2(44, 34)
		out_button.disabled = not bool(entry["deployed"])
		out_button.pressed.connect(_on_deploy.bind(str(entry["unit_id"]), ""))
		box.add_child(out_button)
		side_box.add_child(box)

	side_box.add_child(_hint("出战 %d 个 · 开战不扣食物" % game.deployed_count()))

	var start_button := Button.new()
	start_button.text = "开战"
	start_button.custom_minimum_size = Vector2(0, 50)
	start_button.disabled = not game.can_start_battle()
	start_button.pressed.connect(_on_start_battle)
	side_box.add_child(start_button)

	var avoid_button := Button.new()
	avoid_button.text = "避战（不结算；谈判 / 回避规则待定）"
	avoid_button.custom_minimum_size = Vector2(0, 40)
	avoid_button.pressed.connect(_on_avoid)
	side_box.add_child(avoid_button)


func _build_end() -> void:
	var won: bool = game.phase == GameStateScript.Phase.WON
	side_box.add_child(_title("春季结束" if won else "巢穴失守"))
	side_box.add_child(_hint(
		game.season_summary() if won else "第 %d 回合，巢穴完整度归零。" % game.turn
	))
	side_box.add_child(_hint("巢穴 Lv.%d · 种子 %d 粒（已种 %d）" % [
		game.nest_level, game.seeds.size(), game.planted.size()
	]))

	var button := Button.new()
	button.text = "重开一局"
	button.custom_minimum_size = Vector2(0, 52)
	button.pressed.connect(_on_restart)
	side_box.add_child(button)


func _build_battle() -> void:
	var battle: Dictionary = game.battle
	side_box.add_child(_title("战斗 · 第 %d 轮" % int(battle.get("round", 1))))
	side_box.add_child(_hint("点敌方单位＝攻击（每单位 1 AP）。前排全灭后才能打后排。"))

	var enemies: Dictionary = battle.get("enemies", {})
	for row in ["front", "back"]:
		var list: Array = enemies.get(row, [])
		side_box.add_child(_section("敌方前排" if row == "front" else "敌方后排"))
		for index in list.size():
			var enemy: Dictionary = list[index]
			var button := Button.new()
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.custom_minimum_size = Vector2(0, 40)
			if bool(enemy["alive"]):
				button.text = "%s  %.1f/%.1f  AP %d" % [
					str(enemy["name"]), float(enemy["hp"]), float(enemy["max_hp"]),
					int(enemy["ap"])
				]
				if row == "back" and game.enemies_front_alive():
					button.disabled = true
				else:
					button.pressed.connect(_on_attack.bind(row, index))
			else:
				button.text = "%s（已退场）" % str(enemy["name"])
				button.disabled = true
			side_box.add_child(button)

	side_box.add_child(_section("我方"))
	var players: Dictionary = battle.get("player", {})
	for row in ["front", "back"]:
		for unit in players.get(row, []):
			var label := Label.new()
			label.add_theme_font_size_override("font_size", 15)
			if bool(unit["alive"]):
				var shield := float(unit.get("shield", 0.0))
				label.text = "%s  %.1f/%.1f  AP %d/%d%s" % [
					str(unit["name"]), float(unit["hp"]), float(unit["max_hp"]),
					int(unit["ap"]), int(unit["max_ap"]),
					"  护盾 %.1f" % shield if shield > 0.0 else ""
				]
			else:
				label.text = "%s（已退场）" % str(unit["name"])
				label.add_theme_color_override("font_color", MUTED)
			side_box.add_child(label)

	var end_button := Button.new()
	end_button.text = "结束玩家阶段（敌方行动）"
	end_button.custom_minimum_size = Vector2(0, 46)
	end_button.pressed.connect(_on_end_phase)
	side_box.add_child(end_button)


func _build_recruit() -> void:
	if game.recruit_free:
		side_box.add_child(_title("开局免费招募（3 选 1）"))
		side_box.add_child(_hint("免费、不占行动；剩余 %d 次。军队 %d/%d。" % [
			game.free_recruits_left, game.army.size(), int(game.balance["army"]["max_size"])
		]))
	else:
		side_box.add_child(_title("招募（3 选 1）"))
		side_box.add_child(_hint("军队 %d/%d · 候选按巢穴阶级抽取；可刷新一次。" % [
			game.army.size(), int(game.balance["army"]["max_size"])
		]))
	if game.recruit_pity_tier > 1:
		side_box.add_child(_hint("升阶保底：本次必出%s单位。" % game.tier_name(game.recruit_pity_tier)))

	for unit_id in game.recruit_candidates:
		var data: Dictionary = game.unit_info(unit_id)
		var button := Button.new()
		button.text = "%s%s — %s" % [
			game.tier_name(int(data.get("tier", 1))), str(data.get("name", unit_id)),
			"免费" if game.recruit_free else _cost_text(data.get("cost", {}))
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 44)
		button.disabled = not game.can_recruit(unit_id)
		button.pressed.connect(_on_recruit.bind(unit_id))
		side_box.add_child(button)
		side_box.add_child(_hint("%s · 生命 %.1f / 攻击 %.1f · %s" % [
			str(data.get("tag", "")), float(data.get("hp", 0.0)), float(data.get("atk", 0.0)),
			str(data.get("signature", ""))
		]))

	if not game.recruit_free:
		var refresh_cost := int(game.balance["recruit"]["refresh_cost"])
		var refresh_button := Button.new()
		refresh_button.text = "刷新候选（%d 食物）" % refresh_cost
		refresh_button.custom_minimum_size = Vector2(0, 42)
		refresh_button.disabled = game.recruit_refreshed or int(game.resources["food"]) < refresh_cost
		refresh_button.pressed.connect(_on_refresh)
		side_box.add_child(refresh_button)

	var skip_button := Button.new()
	skip_button.text = "跳过（不占行动）" if game.recruit_free else "跳过"
	skip_button.custom_minimum_size = Vector2(0, 42)
	skip_button.pressed.connect(_on_skip)
	side_box.add_child(skip_button)


func _cost_text(cost: Dictionary) -> String:
	var names := {"food": "食物"}
	var parts: Array[String] = []
	for key in names.keys():
		if cost.has(key):
			parts.append("%s %d" % [names[key], int(cost[key])])
	if parts.is_empty():
		return "免费"
	return " + ".join(parts)


func _section(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", MUTED)
	return label


func _add_action_button(title: String, description: String, action_id: String) -> void:
	var button := Button.new()
	button.text = title
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 44)
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
	label.add_theme_font_size_override("font_size", 21)
	return label


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", MUTED)
	label.add_theme_font_size_override("font_size", 14)
	return label


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


func _on_deploy(unit_id: String, row: String) -> void:
	game.deploy_set(unit_id, row)


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
