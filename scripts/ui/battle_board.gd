extends Control
## 六边形战场板：布阵预览 / 战斗。放在左侧大面板，隐藏巢穴视图。
## 敌方在上、我方在下，前 4 后 3；底部是未上场棋子与战果手牌。
## 战斗中的点击走 GameState.select_player / player_attack，不复制规则。

const UnitHexScript := preload("res://scripts/ui/unit_hex.gd")
const WarHandScript := preload("res://scripts/ui/war_hand.gd")
const GameStateScript := preload("res://scripts/core/game_state.gd")

const INK := Color("201d18")
const MUTED := Color("6f6a60")
const ACCENT := Color("3d5a3a")
const GOLD := Color("93641f")
const DANGER := Color("a33a2a")
const LINE := Color(0.16, 0.14, 0.11, 0.16)

var game = null

var _r := 40.0
var _hex_w := 74.0
var _hex_h := 82.0
var _divider_y := 210.0
var _bench_y := 500.0
var _hand_top := 450.0
var _hand_x := 272.0
var _hand_w := 480.0
var _hint := ""
var _last_phase := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	resized.connect(_on_resized)


func bind(g) -> void:
	game = g


func refresh() -> void:
	if not is_inside_tree() or game == null:
		return
	if int(game.phase) != _last_phase:
		_last_phase = int(game.phase)
		_hint = ""
	_rebuild()


func _on_resized() -> void:
	if is_inside_tree():
		_rebuild()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if game == null:
		return
	var w := size.x
	var h := size.y
	if w < 140.0 or h < 140.0:
		return

	_r = clampf(minf(w / 12.0, (h - 180.0) / 9.5), 20.0, 42.0)
	_hex_w = _r * 1.84
	_hex_h = _r * 2.04
	var step := _r * 2.02
	var enemy_back_y := 22.0 + _r
	var enemy_front_y := enemy_back_y + _r * 2.18
	_divider_y = enemy_front_y + _r * 1.95
	var player_front_y := _divider_y + _r * 1.15
	var player_back_y := player_front_y + _r * 2.18
	_bench_y = h - 40.0
	_hand_top = h - 140.0
	_hand_x = minf(276.0, w * 0.36)
	_hand_w = maxf(160.0, w - _hand_x - 16.0)

	var battle_mode: bool = game.phase == GameStateScript.Phase.BATTLE

	if battle_mode:
		var battle: Dictionary = game.battle
		var enemies: Dictionary = battle.get("enemies", {})
		var players: Dictionary = battle.get("player", {})
		var attacker: Dictionary = game.selected_player()
		var can_attack: bool = not attacker.is_empty() and float(attacker.get("atk", 0.0)) > 0.0
		_place_enemy_row(enemies.get("back", []), 3, "back", enemy_back_y, can_attack, step)
		_place_enemy_row(enemies.get("front", []), 4, "front", enemy_front_y, can_attack, step)
		_place_player_row(players.get("front", []), 4, "front", player_front_y, step)
		_place_player_row(players.get("back", []), 3, "back", player_back_y, step)
	else:
		# 布阵预览：敌方留空，开战后才出现。
		_place_empty_row(3, enemy_back_y, step, "开战后显示敌方")
		_place_empty_row(4, enemy_front_y, step, "开战后显示敌方")
		_place_deploy_row(_deploy_row("front"), 4, player_front_y, step)
		_place_deploy_row(_deploy_row("back"), 3, player_back_y, step)

	_place_bench()
	_place_hand()
	queue_redraw()


func _place_enemy_row(units: Array, slots: int, row: String, y: float, can_attack: bool, step: float) -> void:
	var blocked: bool = row == "back" and game.enemies_front_alive()
	for i in slots:
		var x := _slot_x(i, slots, step)
		if i >= units.size():
			_new_empty(x, y, "空位")
			continue
		var unit: Dictionary = units[i]
		var alive := bool(unit.get("alive", true))
		var data := {
			"uid": 0,
			"tier": 1,
			"hostile": true,
			"selected": false,
			"dimmed": (not alive) or blocked or (not can_attack),
			"blocked": blocked,
			"alive": alive,
			"glyph": _glyph(str(unit.get("name", ""))),
			"hp": float(unit.get("hp", 0.0)),
			"max_hp": float(unit.get("max_hp", 0.0)),
			"atk": float(unit.get("atk", 0.0)),
			"ap": int(unit.get("ap", 0)),
			"max_ap": int(unit.get("max_ap", 0)),
			"shield": float(unit.get("shield", 0.0)),
			"weaken": int(unit.get("weaken", 0)),
			"tooltip": _unit_tooltip(unit, blocked),
		}
		var hex = _new_hex(data, x, y)
		hex.set_meta("kind", "enemy")
		hex.set_meta("row", row)
		hex.set_meta("index", i)


func _place_player_row(units: Array, slots: int, _row: String, y: float, step: float) -> void:
	for i in slots:
		var x := _slot_x(i, slots, step)
		if i >= units.size():
			_new_empty(x, y, "空位")
			continue
		var unit: Dictionary = units[i]
		var alive := bool(unit.get("alive", true))
		var data := {
			"uid": int(unit.get("uid", 0)),
			"tier": int(unit.get("tier", 1)),
			"hostile": false,
			"selected": int(unit.get("uid", 0)) == game.selected_uid,
			"dimmed": (not alive) or int(unit.get("ap", 0)) <= 0,
			"blocked": false,
			"alive": alive,
			"glyph": _glyph(str(unit.get("name", ""))),
			"hp": float(unit.get("hp", 0.0)),
			"max_hp": float(unit.get("max_hp", 0.0)),
			"atk": float(unit.get("atk", 0.0)),
			"ap": int(unit.get("ap", 0)),
			"max_ap": int(unit.get("max_ap", 0)),
			"shield": float(unit.get("shield", 0.0)),
			"weaken": int(unit.get("weaken", 0)),
			"tooltip": _unit_tooltip(unit, false),
		}
		var hex = _new_hex(data, x, y)
		hex.set_meta("kind", "player")


func _place_deploy_row(entries: Array, slots: int, y: float, step: float) -> void:
	for i in slots:
		var x := _slot_x(i, slots, step)
		if i >= entries.size():
			_new_empty(x, y, "空位")
			continue
		var data: Dictionary = entries[i]
		var hex = _new_hex(data, x, y)
		hex.set_meta("kind", "deploy")


func _place_empty_row(slots: int, y: float, step: float, hint: String) -> void:
	for i in slots:
		_new_empty(_slot_x(i, slots, step), y, hint)


func _place_bench() -> void:
	var bench := _bench_entries()
	var count := 0
	for entry in bench:
		if count >= 7:
			break
		var uid := int(entry.get("uid", 0))
		var stats := _army_stats(uid)
		var data_info: Dictionary = game.unit_info(str(entry.get("unit_id", "")))
		var hp := float(stats.get("max_hp", data_info.get("hp", 0.0)))
		var atk := float(stats.get("attack", data_info.get("attack", 0.0)))
		var data := {
			"uid": uid,
			"tier": int(data_info.get("tier", 1)),
			"hostile": false,
			"selected": false,
			"dimmed": true,
			"blocked": false,
			"alive": true,
			"glyph": _glyph(str(entry.get("name", data_info.get("name", "")))),
			"hp": hp,
			"max_hp": hp,
			"atk": atk,
			"ap": 0,
			"max_ap": 0,
			"shield": 0.0,
			"weaken": 0,
			"tooltip": "%s（未上场）\n生命 %.1f · 攻击 %.1f" % [
				str(entry.get("name", data_info.get("name", ""))), hp, atk
			],
		}
		var hex = UnitHexScript.new()
		hex.position = Vector2(12.0 + count * 39.0, _bench_y - 19.5)
		hex.setup(data)
		hex.set_meta("kind", "bench")
		add_child(hex)
		hex.custom_minimum_size = Vector2(36.0, 39.0)
		hex.size = Vector2(36.0, 39.0)
		count += 1


func _place_hand() -> void:
	var hand = WarHandScript.new()
	hand.position = Vector2(_hand_x, _hand_top)
	hand.size = Vector2(_hand_w, 136.0)
	add_child(hand)
	hand.bind(game)
	hand.card_selected.connect(_on_card_selected)
	hand.refresh()


func _on_card_selected(_spoil_id: String, description: String) -> void:
	_hint = description
	queue_redraw()


func _on_hex_pressed(hex: Control) -> void:
	if game == null or game.phase != GameStateScript.Phase.BATTLE:
		return
	_hint = ""
	match str(hex.get_meta("kind", "")):
		"player":
			game.select_player(int(hex.get_meta("uid", 0)))
		"enemy":
			if game.selected_uid > 0:
				game.player_attack(
					str(hex.get_meta("row", "front")),
					int(hex.get_meta("index", 0))
				)


func _slot_x(index: int, slots: int, step: float) -> float:
	return size.x * 0.5 + (float(index) - float(slots - 1) * 0.5) * step


func _new_hex(data: Dictionary, x: float, y: float) -> Control:
	var hex = UnitHexScript.new()
	hex.size = Vector2(_hex_w, _hex_h)
	hex.position = Vector2(x - _hex_w * 0.5, y - _hex_h * 0.5)
	hex.setup(data)
	hex.hex_pressed.connect(_on_hex_pressed)
	add_child(hex)
	return hex


func _new_empty(x: float, y: float, hint: String) -> void:
	var hex = UnitHexScript.new()
	var w := _hex_w * 0.9
	var h := _hex_h * 0.9
	hex.size = Vector2(w, h)
	hex.position = Vector2(x - w * 0.5, y - h * 0.5)
	hex.set_empty(hint)
	add_child(hex)


func _deploy_row(row: String) -> Array:
	var out: Array = []
	for entry in game.deploy_units:
		if not bool(entry.get("deployed", false)) or str(entry.get("row", "")) != row:
			continue
		var uid := int(entry.get("uid", 0))
		var stats := _army_stats(uid)
		var info: Dictionary = game.unit_info(str(entry.get("unit_id", "")))
		var hp := float(stats.get("max_hp", info.get("hp", 0.0)))
		var atk := float(stats.get("attack", info.get("attack", 0.0)))
		out.append({
			"uid": uid,
			"tier": int(info.get("tier", 1)),
			"hostile": false,
			"selected": false,
			"dimmed": false,
			"blocked": false,
			"alive": true,
			"glyph": _glyph(str(entry.get("name", info.get("name", "")))),
			"hp": hp,
			"max_hp": hp,
			"atk": atk,
			"ap": 0,
			"max_ap": 0,
			"shield": 0.0,
			"weaken": 0,
			"tooltip": "%s\n生命 %.1f · 攻击 %.1f · %s" % [
				str(entry.get("name", info.get("name", ""))), hp, atk,
				"前排" if row == "front" else "后排"
			],
		})
	return out


func _bench_entries() -> Array:
	var out: Array = []
	for entry in game.deploy_units:
		if not bool(entry.get("deployed", false)):
			out.append(entry)
	return out


func _army_stats(uid: int) -> Dictionary:
	for entry in game.army:
		if int(entry.get("uid", 0)) == uid:
			return entry
	return {}


func _unit_tooltip(unit: Dictionary, blocked: bool) -> String:
	var text := "%s\n生命 %.1f/%.1f · 攻击 %.1f" % [
		str(unit.get("name", "")),
		float(unit.get("hp", 0.0)), float(unit.get("max_hp", 0.0)),
		float(unit.get("atk", 0.0)),
	]
	if int(unit.get("max_ap", 0)) > 0:
		text += " · AP %d/%d" % [int(unit.get("ap", 0)), int(unit.get("max_ap", 0))]
	if blocked:
		text += "\n敌方前排未破，打不到后排"
	return text


func _glyph(name: String) -> String:
	if name.length() <= 2:
		return name
	return name.substr(0, 2)


func _draw() -> void:
	var font := get_theme_default_font()
	if font == null or game == null or size.x < 140.0:
		return
	draw_dashed_line(Vector2(22, _divider_y), Vector2(size.x - 22, _divider_y), LINE, 1.0)
	draw_string(font, Vector2(14, 24), "敌方", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, DANGER)
	draw_string(font, Vector2(14, _divider_y + 26), "我方", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ACCENT)

	var bench := _bench_entries()
	draw_string(
		font, Vector2(12, _bench_y - 28), "未上场 %d" % bench.size(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED
	)
	if bench.is_empty():
		draw_string(
			font, Vector2(12, _bench_y + 18), "（全部上场）",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, MUTED
		)

	var hint := _current_hint()
	if hint != "":
		draw_string(
			font, Vector2(_hand_x, _hand_top - 8), hint.substr(0, 52),
			HORIZONTAL_ALIGNMENT_LEFT, _hand_w, 12, MUTED
		)


func _current_hint() -> String:
	if _hint != "":
		return _hint
	if game.phase == GameStateScript.Phase.BATTLE:
		var attacker: Dictionary = game.selected_player()
		if attacker.is_empty():
			return "点选我方单位，再点敌方目标"
		if float(attacker.get("atk", 0.0)) <= 0.0:
			return "所选单位没有攻击力，请另选一只"
		return "已选【%s】→ 点敌方目标" % str(attacker.get("name", ""))
	return "布阵预览 · 用右侧按钮调整前 / 后排"
