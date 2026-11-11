class_name GameState
extends RefCounted
## 纯逻辑层：不依赖场景树，可在 --headless 下直接实例化做测试。
## 状态机：ACTION → GROUP_SELECT → EVENT（A→D，期间可进 BATTLE / RECRUIT）→ 下一回合。

signal changed

enum Phase { ACTION, GROUP_SELECT, EVENT, DEPLOY, BATTLE, RECRUIT, GAME_OVER, WON }

const EventPoolScript := preload("res://scripts/core/event_pool.gd")
const HexGridScript := preload("res://scripts/core/hex_grid.gd")
const DataStoreScript := preload("res://scripts/core/data_store.gd")

const TOTAL_TURNS := 6
const TURNS_PER_SEASON := 6
const GROUP_SIZE := 4
const SEASONS := ["春", "夏", "秋", "冬"]
const EVENT_LETTERS := ["A", "B", "C", "D"]

var balance: Dictionary = {}
var event_data: Dictionary = {}
var event_templates_data: Dictionary = {}
var units_data: Dictionary = {}
var enemies_data: Dictionary = {}
var seeds_data: Dictionary = {}
var rng := RandomNumberGenerator.new()
var seed_value := 0

var season := 0
var turn := 1
var weather := "clear"
var season_weathers: Array[String] = []
var weather_index := 0
var event_index := 0
var phase: int = Phase.ACTION
var health := 100.0
var resources := {"food": 0}
var exp_points := 0
var seeds: Array[String] = []
var planted: Array = []
var warfruits := {}
var army: Array = []
var nest_level := 1
var location := "river"
var blocked_dirs: Array = []
var cells: Array = []
var groups: Array = []
var active_group: Dictionary = {}
var battle := {}
var deploy_units: Array = []
var pending_event: Dictionary = {}
var recruit_candidates: Array[String] = []
var recruit_context := "turn"
var free_refreshes := 0
var food_spent_total := 0
var food_spent_milestone := 0
var selected_uid := -1
var next_unit_uid := 1
var free_recruits_left := 0
var tier_pity := 0
var amber := 0
var run_start_food := 0
var run_start_health := 100.0
var battle_count := 0
var win_count := 0
var lose_count := 0
var observed_forecast := false
var data_version := 0
var logs: Array[String] = []


func _init(p_seed: int = 0) -> void:
	_apply_store(DataStoreScript.instance())
	start_new_game(p_seed)


## 热更：从唯一数据入口重新取数；战斗中不改场上单位（保持开战快照）。
func reload_data() -> void:
	var store = DataStoreScript.instance()
	if store.version == data_version:
		return
	_apply_store(store)
	_add_log("数据已热更（v%d）；战斗数值从下一场生效。" % data_version)
	changed.emit()


func _apply_store(store) -> void:
	data_version = store.version
	balance = store.get_data("balance")
	event_data = store.get_data("events")
	event_templates_data = store.get_data("event_templates")
	units_data = store.get_data("units")
	enemies_data = store.get_data("enemies")
	seeds_data = store.get_data("seeds")


func start_new_game(p_seed: int = 0) -> void:
	seed_value = p_seed if p_seed != 0 else int(Time.get_unix_time_from_system())
	rng.seed = seed_value

	season = 0
	turn = 1
	event_index = 0
	season_weathers = []
	weather_index = 0
	nest_level = int(balance["start"].get("nest_level", 1))
	health = float(balance["start"]["health"])
	resources = {"food": int(balance["start"]["food"])}
	exp_points = 0
	seeds = []
	planted = []
	warfruits = {}
	army = []
	groups = []
	active_group = {}
	battle = {}
	deploy_units = []
	recruit_candidates = []
	recruit_context = "turn"
	free_refreshes = 0
	food_spent_total = 0
	food_spent_milestone = 0
	selected_uid = -1
	next_unit_uid = 1
	free_recruits_left = int(balance["start"].get("free_recruits", 2)) if int(balance["start"].get("free_recruits", 2)) > 0 else 0
	tier_pity = 0
	amber = 0
	battle_count = 0
	win_count = 0
	lose_count = 0
	observed_forecast = false
	logs = []

	location = str(balance.get("location", "river"))
	blocked_dirs = []
	for dir in balance["locations"][location].get("blocked_dirs", []):
		blocked_dirs.append(int(dir))

	_rebuild_cells()
	var start_seed := str(balance["start"].get("seed", ""))
	if start_seed != "":
		_plant(start_seed)
	run_start_food = int(resources["food"])
	run_start_health = health
	_add_log("新的一局：%s，巢穴 Lv.%d（%d 格，%d 个肥沃格），食物 %d，完整度 %d。" % [
		str(balance["locations"][location].get("name", location)), nest_level,
		cells.size(), _usable_fertile_count(), int(resources["food"]), int(health)
	])
	_begin_turn()


func _begin_turn() -> void:
	# 文档 Q-090：季初一次性生成 6 个天气，按季节权重抽取；预报窗口 Q-091 未定。
	if season_weathers.is_empty() or weather_index >= TURNS_PER_SEASON:
		_generate_season_weathers()
	weather = season_weathers[weather_index]
	weather_index += 1

	groups = EventPoolScript.build_groups(
		rng, event_data, event_templates_data, int(balance["event_groups_per_turn"]), season
	)
	event_index = 0
	active_group = {}
	battle = {}
	deploy_units = []
	pending_event = {}
	recruit_candidates = []
	if turn > 1:
		free_recruits_left = 0
	# 2026-11-09：工蚁 / 维持 / 被动恢复已删除，回合开始只做收入汇报（Q-035）。
	_add_log("第 %d 回合（%s 第 %d/%d 回合，总 %d/%d）· 天气 %s：食物 %d，已播种 %d 块，事件内预计食物 +%d。" % [
		turn, season_name(), turn_in_season(), TURNS_PER_SEASON, turn, TOTAL_TURNS,
		weather_name(), int(resources["food"]), planted.size(), _forecast_food_per_turn()
	])
	_open_recruit_window("turn")
	changed.emit()


func _open_recruit_window(context: String) -> void:
	recruit_context = context
	recruit_candidates = _roll_recruits()
	phase = Phase.RECRUIT
	if context == "event":
		_add_log("招募事件：3 选 1，可反复招募；点「结束招募」继续事件。")
	else:
		_add_log("招募窗口：3 选 1，可一直招募到点「结束招募」；免费剩余 %d 次。" % free_recruits_left)
	changed.emit()


func end_recruit() -> bool:
	if phase != Phase.RECRUIT:
		return false
	recruit_candidates = []
	var context := recruit_context
	recruit_context = "turn"
	if context == "event":
		_advance_event()
	else:
		phase = Phase.GROUP_SELECT
	_add_log("结束招募。" if context == "event" else "结束招募，进入事件组选择。")
	changed.emit()
	return true


func choose_action(action_id: String) -> bool:
	if phase != Phase.ACTION:
		return false
	var ok := false
	match action_id:
		"adventure":
			ok = _do_adventure()
		"heal":
			ok = _do_heal()
		"expand":
			ok = _do_expand()
		_:
			return false

	if ok:
		if health <= 0.0:
			phase = Phase.GAME_OVER
			_add_log("巢穴完整度归零，本局结束。")
		else:
			_end_turn()
	changed.emit()
	return ok


func can_train_cangcao(uid: int) -> bool:
	if phase != Phase.ACTION:
		return false
	var entry := _army_entry(uid)
	if entry.is_empty():
		return false
	var data := unit_info(str(entry.get("unit_id", "")))
	if str(data.get("signature", {}).get("id", "")) != "jiliang":
		return false
	if int(entry.get("trained_turn", -1)) == turn:
		return false
	return int(resources["food"]) >= int(data.get("signature", {}).get("params", {}).get("food_cost", 2))


func train_cangcao(uid: int, stat: String) -> bool:
	if not can_train_cangcao(uid):
		return false
	var entry := _army_entry(uid)
	var data := unit_info(str(entry.get("unit_id", "")))
	var params: Dictionary = data.get("signature", {}).get("params", {})
	var cost := int(params.get("food_cost", 2))
	_spend_food(cost)
	entry["trained_turn"] = turn
	if stat == "hp":
		entry["max_hp"] = float(entry.get("max_hp", 7.0)) + float(params.get("hp_gain", 3.0))
		_add_log("积粮：%s 最大生命 +%.1f【永久】（当前 %.1f），食物 -%d。" % [
			str(data.get("name", "仓曹蚁")), float(params.get("hp_gain", 3.0)),
			float(entry["max_hp"]), cost
		])
	else:
		entry["attack"] = float(entry.get("attack", 2.0)) + float(params.get("attack_gain", 2.0))
		_add_log("积粮：%s 攻击 +%.1f【永久】（当前 %.1f），食物 -%d。" % [
			str(data.get("name", "仓曹蚁")), float(params.get("attack_gain", 2.0)),
			float(entry["attack"]), cost
		])
	changed.emit()
	return true


func choose_group(index: int) -> bool:
	if phase != Phase.GROUP_SELECT:
		return false
	if index < 0 or index >= groups.size():
		return false
	active_group = groups[index]
	event_index = 0
	phase = Phase.EVENT
	_add_log("选定事件组：%s（%s）。" % [
		EventPoolScript.group_title(index), EventPoolScript.describe(active_group)
	])
	changed.emit()
	return true


func ready_up() -> bool:
	if phase != Phase.EVENT:
		return false
	var event := current_event()
	if event.is_empty():
		return false

	if event.has("battle"):
		_add_log("敌对遭遇：选择「迎战」「谈判」或「回避」。")
		changed.emit()
		return false

	_resolve_event(event)
	changed.emit()
	return true


func choose_encounter(option: String) -> bool:
	if phase != Phase.EVENT:
		return false
	var event := current_event()
	if event.is_empty() or not event.has("battle"):
		return false
	match option:
		"fight":
			_open_deploy(event)
			changed.emit()
			return true
		"talk":
			# 谈判代价为占位：Q-084 未定具体食物数。
			var cost := 2
			if int(resources["food"]) < cost:
				_add_log("食物不足 %d，无法谈判。" % cost)
				changed.emit()
				return false
			_spend_food(cost)
			_add_log("谈判：支付 %d 食物，避开战斗（代价为占位，Q-084）。" % cost)
			_tick_planted()
			_advance_event()
			changed.emit()
			return true
		"avoid":
			_add_log("回避：绕开这场战斗，放弃战利品。")
			_tick_planted()
			_advance_event()
			changed.emit()
			return true
	return false


func choose_event_option(index: int) -> bool:
	if phase != Phase.EVENT:
		return false
	var event := current_event()
	var options: Array = event.get("options", [])
	if index < 0 or index >= options.size():
		return false
	var option: Dictionary = options[index]
	var label := str(option.get("label", "选项"))
	var cost := int(option.get("food_cost", 0))
	if int(resources["food"]) < cost:
		_add_log("食物不足 %d，无法选择「%s」。" % [cost, label])
		changed.emit()
		return false
	if cost > 0:
		_spend_food(cost)

	var effects: Dictionary = option.get("effects", {}).duplicate(true)
	if option.has("rain_food") and weather == "rain":
		effects["food"] = int(option["rain_food"])
	_apply_effects(effects)
	var roll: Dictionary = option.get("roll", {})
	if not roll.is_empty():
		if rng.randf() < float(roll.get("chance", 0.0)):
			_apply_effects(roll.get("effects", {}))
		elif rng.randf() < float(roll.get("fail_chance", 0.0)):
			_apply_effects(roll.get("fail_effects", {}))
	if bool(option.get("observe", false)):
		observed_forecast = true
		_add_log("观察天气：下回合预计「%s」。" % forecast_weather(1))

	if health <= 0.0:
		_fail_game()
		changed.emit()
		return true

	var letter: String = EVENT_LETTERS[event_index] if event_index < EVENT_LETTERS.size() else "?"
	_add_log("事件 %s：%s → %s。" % [letter, str(event.get("title", "")), label])

	if option.has("battle"):
		var battle_event := event.duplicate(true)
		battle_event["battle"] = str(option["battle"])
		_open_deploy(battle_event)
		changed.emit()
		return true

	_tick_planted()
	if bool(option.get("recruit", false)):
		_open_recruit()
		changed.emit()
		return true

	_advance_event()
	changed.emit()
	return true


# ---------------------------------------------------------------------------
# 布阵（开战前）
# ---------------------------------------------------------------------------

func _open_deploy(event: Dictionary) -> void:
	pending_event = event
	deploy_units = []
	var front_used := 0
	var back_used := 0
	for entry in army:
		var data := unit_info(str(entry["unit_id"]))
		if data.is_empty():
			continue
		var row := str(data.get("row", "front"))
		if row == "either":
			row = "front" if front_used < _row_cap("front") else "back"
		var deployed := true
		if row == "front":
			if front_used >= _row_cap("front"):
				deployed = false
			else:
				front_used += 1
		else:
			if back_used >= _row_cap("back"):
				deployed = false
			else:
				back_used += 1
		deploy_units.append({
			"uid": int(entry["uid"]),
			"unit_id": str(entry["unit_id"]),
			"name": str(data.get("name", entry["unit_id"])),
			"row": row,
			"deployed": deployed,
		})
	battle = {}
	phase = Phase.DEPLOY
	var spec := _encounter_spec()
	_add_log("布阵：%s 来袭，选择出战单位（前 %d / 后 %d）。" % [
		_encounter_name(spec), _row_cap("front"), _row_cap("back")
	])


func _row_cap(row: String) -> int:
	return int(balance["army"].get(row, 4))


func _deploy_entry(uid: int) -> Dictionary:
	for entry in deploy_units:
		if int(entry["uid"]) == uid:
			return entry
	return {}


func deploy_set(uid: int, row: String) -> bool:
	if phase != Phase.DEPLOY:
		return false
	var entry := _deploy_entry(uid)
	if entry.is_empty():
		return false
	if row == "":
		entry["deployed"] = false
		changed.emit()
		return true
	if row != "front" and row != "back":
		return false
	var data := unit_info(str(entry["unit_id"]))
	var fixed_row := str(data.get("row", "either"))
	if fixed_row != "either" and fixed_row != row:
		_add_log("%s 只能站%s。" % [str(entry["name"]), "前排" if fixed_row == "front" else "后排"])
		changed.emit()
		return false
	var used := 0
	for other in deploy_units:
		if other == entry:
			continue
		if bool(other["deployed"]) and str(other["row"]) == row:
			used += 1
	if used >= _row_cap(row):
		_add_log("该排已满（%d 个）。" % _row_cap(row))
		changed.emit()
		return false
	entry["row"] = row
	entry["deployed"] = true
	changed.emit()
	return true


func deployed_count() -> int:
	var count := 0
	for entry in deploy_units:
		if bool(entry["deployed"]):
			count += 1
	return count


func deploy_supply() -> int:
	# 2026-11-09 Q-052：战斗补给已取消，保留方法给 UI 兼容。
	return 0


func can_start_battle() -> bool:
	return phase == Phase.DEPLOY and deployed_count() > 0


func start_battle() -> bool:
	if phase != Phase.DEPLOY:
		return false
	if deployed_count() <= 0:
		_add_log("没有出战单位，无法迎战。")
		changed.emit()
		return false

	var players_front: Array = []
	var players_back: Array = []
	for entry in deploy_units:
		if not bool(entry["deployed"]):
			continue
		var data := unit_info(str(entry["unit_id"]))
		var persistent := _army_entry(int(entry["uid"]))
		var unit := _make_unit(
			str(data.get("name", entry["unit_id"])),
			float(persistent.get("max_hp", data.get("hp", 8.0))),
			float(persistent.get("attack", data.get("attack", 2.0))),
			int(data.get("ap", 1)),
			str(entry["row"]),
			int(entry["uid"]),
			str(entry["unit_id"]),
			data.get("keywords", []),
			data.get("signature", {}),
			int(persistent.get("star", 1))
		)
		unit["base_max_hp"] = float(unit["max_hp"])
		if str(entry["row"]) == "front":
			players_front.append(unit)
		else:
			players_back.append(unit)

	var spec := _encounter_spec()
	var enemies_front: Array = []
	var enemies_back: Array = []
	var enemy_skipped := 0
	var enemy_mult := float(balance.get("spring", {}).get("enemy_scale", 1.0))
	for template in _encounter_units(spec):
		var enemy_data := _enemy_info(str(template.get("enemy_id", "")))
		if enemy_data.is_empty():
			continue
		for i in int(template.get("count", 1)):
			var row := str(enemy_data.get("row", "front"))
			var signature: Dictionary = enemy_data.get("signature", {})
			var params: Dictionary = signature.get("params", {})
			var unit := _make_unit(
				str(enemy_data.get("name", "敌人")),
				snappedf(float(enemy_data.get("hp", 8.0)) * enemy_mult, 0.1),
				snappedf(float(enemy_data.get("attack", 2.0)) * enemy_mult, 0.1),
				int(enemy_data.get("ap", 1)),
				row,
				0,
				str(enemy_data.get("id", "")),
				enemy_data.get("keywords", []),
				signature
			)
			# 敌我阵列一致：前排 4 / 后排 3；放不下就跳过（不串排）。
			if row == "front" and enemies_front.size() < _row_cap("front"):
				enemies_front.append(unit)
			elif row == "back" and enemies_back.size() < _row_cap("back"):
				enemies_back.append(unit)
			else:
				enemy_skipped += 1
				continue
			for key in ["shield_per_round", "weaken_chance", "weaken_per_round", "bypass_first"]:
				if params.has(key):
					unit[key] = params[key]
			unit["first_attack_used"] = false
	if enemy_skipped > 0:
		_add_log("敌方阵列已满（前 %d / 后 %d），跳过 %d 个敌人。" % [
			_row_cap("front"), _row_cap("back"), enemy_skipped
		])

	battle = {
		"player": {"front": players_front, "back": players_back},
		"enemies": {"front": enemies_front, "back": enemies_back},
		"round": 1,
		"event": pending_event,
		"encounter": spec,
		"encounter_name": _encounter_name(spec),
		"rewards": balance.get("combat", {}).get("rewards", {}).duplicate(true),
		"result": "",
	}
	selected_uid = -1
	battle_count += 1
	phase = Phase.BATTLE
	_add_log("战斗开始：%s · 我方 %d 只，敌方 %d 只。" % [
		_encounter_name(spec),
		players_front.size() + players_back.size(),
		enemies_front.size() + enemies_back.size()
	])
	_battle_start_effects()
	_start_round_effects()
	changed.emit()
	return true


func avoid_battle() -> void:
	if phase != Phase.DEPLOY:
		return
	_add_log("避战：谈判 / 回避规则未定（Q-084），原型按不结算处理。")
	deploy_units = []
	pending_event = {}
	_advance_event()
	changed.emit()


func _make_unit(
	name: String,
	hp: float,
	atk: float,
	ap: int,
	row: String,
	uid: int = 0,
	unit_id: String = "",
	keywords: Array = [],
	signature: Dictionary = {},
	star: int = 1
) -> Dictionary:
	return {
		"name": name,
		"unit_id": unit_id,
		"uid": uid,
		"hp": hp,
		"max_hp": hp,
		"atk": atk,
		"ap": ap,
		"max_ap": ap,
		"shield": 0.0,
		"weaken": 0,
		"row": row,
		"alive": true,
		"keywords": keywords,
		"signature": signature,
		"star": star,
	}


func _encounter_spec() -> Dictionary:
	var raw = pending_event.get("battle", {})
	if raw is String:
		var encounter: Dictionary = enemies_data.get("encounters", {}).get(str(raw), {}).duplicate(true)
		encounter["id"] = str(raw)
		return encounter
	if raw is Dictionary:
		if raw.has("units"):
			return raw
		if raw.has("enemy_id"):
			var enemy := _enemy_info(str(raw["enemy_id"]))
			return {
				"name": str(enemy.get("name", "遭遇")),
				"units": [raw],
			}
	return {}


func _encounter_units(spec: Dictionary) -> Array:
	return spec.get("units", [])


func _encounter_name(spec: Dictionary) -> String:
	if spec.has("name"):
		return str(spec["name"])
	var units: Array = spec.get("units", [])
	if not units.is_empty():
		var enemy := _enemy_info(str(units[0].get("enemy_id", "")))
		return str(enemy.get("name", "遭遇"))
	return "遭遇"


func _enemy_info(enemy_id: String) -> Dictionary:
	for enemy in enemies_data.get("enemies", []):
		if str(enemy.get("id", "")) == enemy_id:
			return enemy
	return {}


# ---------------------------------------------------------------------------
# 战斗
# ---------------------------------------------------------------------------

func select_player(uid: int) -> bool:
	if phase != Phase.BATTLE:
		return false
	var unit := _player_by_uid(uid)
	if unit.is_empty() or not bool(unit["alive"]):
		return false
	if int(unit["ap"]) <= 0:
		_add_log("%s 本回合没有行动点。" % str(unit["name"]))
		changed.emit()
		return false
	selected_uid = uid
	changed.emit()
	return true


func selected_player() -> Dictionary:
	if selected_uid <= 0:
		return {}
	return _player_by_uid(selected_uid)


func _player_by_uid(uid: int) -> Dictionary:
	var players: Dictionary = battle.get("player", {})
	for row in ["front", "back"]:
		for unit in players.get(row, []):
			if int(unit.get("uid", 0)) == uid:
				return unit
	return {}


func player_attack(row: String, index: int) -> bool:
	if phase != Phase.BATTLE:
		return false
	if row != "front" and row != "back":
		return false
	var attacker := selected_player()
	if attacker.is_empty():
		_add_log("先点选我方单位，再点敌方目标。")
		changed.emit()
		return false
	if not bool(attacker["alive"]) or int(attacker["ap"]) <= 0:
		selected_uid = -1
		_add_log("%s 本回合没有行动点。" % str(attacker["name"]))
		changed.emit()
		return false
	# 驿传蚁等 0 攻击单位：即使面板被加成也不普攻（文档 4.9）。
	if float(attacker["atk"]) <= 0.0:
		_add_log("%s 没有攻击力，无法攻击。" % str(attacker["name"]))
		changed.emit()
		return false
	var enemies: Dictionary = battle["enemies"]
	var targets: Array = enemies[row]
	if index < 0 or index >= targets.size():
		return false
	var target: Dictionary = targets[index]
	if not bool(target["alive"]):
		return false
	if row == "back" and _side_alive(enemies["front"]):
		_add_log("敌方前排还在，打不到后排。")
		changed.emit()
		return false

	_attack(attacker, target)
	attacker["ap"] = int(attacker["ap"]) - 1
	_after_player_attack(attacker, target)
	if int(attacker["ap"]) <= 0:
		selected_uid = -1
	_check_battle_end()
	changed.emit()
	return true


func _after_player_attack(attacker: Dictionary, _target: Dictionary) -> void:
	# 角质化：弧矢蚁「连射」——每次攻击后 30% 获得 +1 行动点，可连锁。
	var signature: Dictionary = attacker.get("signature", {})
	if str(signature.get("id", "")) != "lianshe":
		return
	var params: Dictionary = signature.get("params", {})
	if rng.randf() < float(params.get("proc_chance", 0.30)):
		attacker["ap"] = int(attacker["ap"]) + 1
		_add_log("连射：%s 获得 1 行动点。" % str(attacker["name"]))


func end_player_phase() -> void:
	if phase != Phase.BATTLE:
		return
	selected_uid = -1
	for row in ["front", "back"]:
		for enemy in battle["enemies"][row]:
			while bool(enemy["alive"]) and int(enemy["ap"]) > 0:
				var target := {}
				if bool(enemy.get("bypass_first", false)) and not bool(enemy.get("first_attack_used", false)):
					target = _pick_back_player()
					if not target.is_empty():
						enemy["first_attack_used"] = true
				if target.is_empty():
					target = _pick_player_target()
				if target.is_empty():
					break
				_attack(enemy, target)
				enemy["ap"] = int(enemy["ap"]) - 1
				if _check_battle_end():
					changed.emit()
					return
	_add_log("敌方阶段结束。")

	battle["round"] = int(battle["round"]) + 1
	if int(battle["round"]) > 6:
		_add_log("第 6 轮结束仍未分胜负，触发最终裁决（防守方胜，掉落减少）。")
		_finish_battle(true, true)
		changed.emit()
		return

	_refill_ap()
	_start_round_effects()
	changed.emit()


func _start_round_effects() -> void:
	# 削弱每轮结束 -1 层；盾甲补盾；结网蛛吐丝；掠食雀重置越排攻击；耘耨蚁点卯。
	for row in ["front", "back"]:
		for unit in battle["player"][row]:
			unit["weaken"] = maxi(0, int(unit.get("weaken", 0)) - 1)
		for enemy in battle["enemies"][row]:
			enemy["weaken"] = maxi(0, int(enemy.get("weaken", 0)) - 1)
			enemy["first_attack_used"] = false
			if enemy.has("shield_per_round") and bool(enemy["alive"]):
				enemy["shield"] = maxf(float(enemy.get("shield", 0.0)), float(enemy["shield_per_round"]))
			if int(enemy.get("weaken_per_round", 0)) > 0 and bool(enemy["alive"]):
				var target := _pick_player_target()
				if not target.is_empty():
					target["weaken"] = int(target.get("weaken", 0)) + int(enemy["weaken_per_round"])
					_add_log("%s 吐丝，%s 被削弱（%d 层）。" % [
						str(enemy["name"]), str(target["name"]), int(target["weaken"])
					])

	# 点卯：耘耨蚁每轮给攻击最低的友军 +1.0 攻击【战时】。
	for unit in _all_players():
		if not bool(unit["alive"]):
			continue
		var signature: Dictionary = unit.get("signature", {})
		if str(signature.get("id", "")) != "dianmao":
			continue
		var target := _lowest_attack_ally(unit)
		if target.is_empty():
			continue
		var gain := float(signature.get("params", {}).get("attack_gain", 1.0))
		target["atk"] = float(target["atk"]) + gain
		_add_log("点卯：%s 给 %s +%.1f 攻击【战时】。" % [
			str(unit["name"]), str(target["name"]), gain
		])

	# 点卯 / 每轮：催阵调度行动点、镇廪给全队护盾、障塞重新指定替伤对象。
	for unit in _all_players():
		if not bool(unit["alive"]):
			continue
		var signature: Dictionary = unit.get("signature", {})
		var params: Dictionary = signature.get("params", {})
		match str(signature.get("id", "")):
			"cuizhen":
				var target := _highest_attack_ally(unit)
				if not target.is_empty():
					target["ap"] = int(target["ap"]) + int(params.get("ap_gain", 1))
					_add_log("催阵：%s 令 %s 本轮 +%d 行动点。" % [
						str(unit["name"]), str(target["name"]), int(params.get("ap_gain", 1))
					])
			"dianmao_zhenlin":
				var shield := float(params.get("shield", 1.5))
				for ally in _all_players():
					if bool(ally["alive"]):
						ally["shield"] = maxf(float(ally.get("shield", 0.0)), shield)
				_add_log("镇廪：%s 存活，全队获得 %.1f 护盾。" % [str(unit["name"]), shield])
			"zhangsai":
				var ward := _lowest_hp_back_ally(unit)
				if not ward.is_empty():
					unit["guard_uid"] = int(ward["uid"])
					_add_log("障塞：%s 本轮替 %s 承受下一次单体攻击。" % [
						str(unit["name"]), str(ward["name"])
					])
			"dugeng":
				if not bool(unit.get("dugeng_logged", false)):
					unit["dugeng_logged"] = true
					_add_log("督耕：%s 的护田效果需要植物（当前未带植物）。" % str(unit["name"]))


func _all_players() -> Array:
	var result: Array = []
	var players: Dictionary = battle.get("player", {})
	for row in ["front", "back"]:
		result.append_array(players.get(row, []))
	return result


func _has_any_signature(signature_id: String) -> bool:
	for unit in _all_players():
		if bool(unit["alive"]) and str(unit.get("signature", {}).get("id", "")) == signature_id:
			return true
	return false


func _is_player_unit(unit: Dictionary) -> bool:
	# 我方单位由队伍 uid（≥1）标识；敌方单位创建时 uid 固定为 0。
	return int(unit.get("uid", 0)) > 0


func _lowest_attack_ally(exclude: Dictionary) -> Dictionary:
	var best := {}
	for unit in _all_players():
		if unit == exclude or not bool(unit["alive"]):
			continue
		if best.is_empty() or float(unit["atk"]) < float(best["atk"]):
			best = unit
	return best


func _highest_attack_ally(exclude: Dictionary) -> Dictionary:
	var best := {}
	for unit in _all_players():
		if unit == exclude or not bool(unit["alive"]):
			continue
		if best.is_empty() or float(unit["atk"]) > float(best["atk"]):
			best = unit
	return best


func _lowest_hp_back_ally(exclude: Dictionary) -> Dictionary:
	var best := {}
	for unit in battle.get("player", {}).get("back", []):
		if unit == exclude or not bool(unit["alive"]):
			continue
		if best.is_empty() or float(unit["hp"]) < float(best["hp"]):
			best = unit
	return best


func _zhangsai_guard_for(target: Dictionary) -> Dictionary:
	for unit in _all_players():
		if not bool(unit["alive"]):
			continue
		if str(unit.get("signature", {}).get("id", "")) != "zhangsai":
			continue
		if int(unit.get("guard_uid", 0)) != int(target.get("uid", -1)):
			continue
		if int(unit.get("uid", 0)) == int(target.get("uid", -1)):
			continue
		unit["guard_uid"] = 0
		return unit
	return {}


func _battle_start_effects() -> void:
	# 迅捷：战斗开始时触发一次绑定效果。
	# 旌旗蚁「号令」绑定【迅捷】：友方迅捷额外结算 1 次（多只不叠加）。
	var swift_times := 2 if _has_any_signature("haoling_jingqi") else 1
	for unit in _all_players():
		if not bool(unit["alive"]):
			continue
		var signature: Dictionary = unit.get("signature", {})
		var params: Dictionary = signature.get("params", {})
		for _i in swift_times:
			match str(signature.get("id", "")):
				"xunjie_bugan":
					warfruits["xunjie"] = int(warfruits.get("xunjie", 0)) + 1
					_add_log("迅捷：%s 获得战果【迅捷】。" % str(unit["name"]))
				"shiyi":
					_battle_start_shiyi(unit, params)
				"xunjie_dilei":
					var heal := float(params.get("integrity", 2.0))
					var before := health
					health = minf(max_health(), health + heal)
					_add_log("迅捷：%s 恢复巢穴完整度 %.0f（%d → %d）。" % [
						str(unit["name"]), heal, int(before), int(health)
					])
				"xunjie_kenong":
					_add_log("迅捷：课农蚁生效，本场己方植物攻击返粮（当前未带植物）。")
				"xunjie_gouxu":
					var shield := float(params.get("shield", 2.0))
					for ally in _all_players():
						if bool(ally["alive"]):
							ally["shield"] = maxf(float(ally.get("shield", 0.0)), shield)
					_add_log("迅捷：%s 令全队获得 %.1f 护盾。" % [str(unit["name"]), shield])
				"xunjie_taicang":
					_battle_start_taicang(unit, params)


func _battle_start_taicang(unit: Dictionary, params: Dictionary) -> void:
	var cost := int(params.get("food_cost", 5))
	if int(resources["food"]) < cost:
		_add_log("太仓：%s 食物不足 %d，不交粮。" % [str(unit["name"]), cost])
		return
	_spend_food(cost)
	var atk_gain := float(params.get("attack_gain", 2.0))
	var shield := float(params.get("shield", 2.0))
	for ally in _all_players():
		if not bool(ally["alive"]):
			continue
		ally["atk"] = float(ally["atk"]) + atk_gain
		ally["shield"] = maxf(float(ally.get("shield", 0.0)), shield)
	_add_log("太仓：%s 交 %d 食物，全队 +%.1f 攻击【战时】与 %.1f 护盾。" % [
		str(unit["name"]), cost, atk_gain, shield
	])


func _battle_start_shiyi(unit: Dictionary, params: Dictionary) -> void:
	var loss := float(params.get("self_hp_loss", 2.0))
	if float(unit["max_hp"]) < loss:
		return
	unit["max_hp"] = float(unit["max_hp"]) - loss
	unit["hp"] = float(unit["max_hp"])
	var ally := _random_other_player(unit)
	if not ally.is_empty():
		ally["max_hp"] = float(ally["max_hp"]) + float(params.get("ally_hp_gain", 1.0))
		ally["hp"] = float(ally["hp"]) + float(params.get("ally_hp_gain", 1.0))
		_add_log("拾遗：%s 自损 %.1f 最大生命，%s +1.0 最大生命【永久】。" % [
			str(unit["name"]), loss, str(ally["name"])
		])
	else:
		_add_log("拾遗：%s 自损 %.1f 最大生命（没有其它友军）。" % [str(unit["name"]), loss])
	var food := rng.randi_range(int(params.get("food_min", 1)), int(params.get("food_max", 2)))
	_gain_food(food)
	_add_log("拾遗：获得 %d 食物。" % food)


func _random_other_player(exclude: Dictionary) -> Dictionary:
	var pool: Array = []
	for unit in _all_players():
		if unit != exclude and bool(unit["alive"]):
			pool.append(unit)
	if pool.is_empty():
		return {}
	return pool[rng.randi_range(0, pool.size() - 1)]


func _attack(attacker: Dictionary, target: Dictionary) -> float:
	# 障塞蚁：替指定后排友军承受下一次单体攻击（仅敌方攻击我方时）。
	if _is_player_unit(target):
		var guard := _zhangsai_guard_for(target)
		if not guard.is_empty():
			_add_log("障塞：%s 替 %s 挡下攻击。" % [str(guard["name"]), str(target["name"])])
			target = guard
			# 障塞自身被攻击时，若它同时是挡刀者，仍按挡刀后的目标结算。
	var variance := rng.randf_range(0.90, 1.10)
	var atk := float(attacker["atk"])
	if int(attacker.get("weaken", 0)) > 0:
		atk *= 0.5
	# 实仓蚁：攻击额外 +食物÷8（上限 +3.0）。
	if str(attacker.get("signature", {}).get("id", "")) == "eshou_shicang":
		var cang_params: Dictionary = attacker["signature"].get("params", {})
		var divisor := maxi(1, int(cang_params.get("food_divisor", 8)))
		var bonus := minf(float(cang_params.get("bonus_cap", 3.0)), floor(float(int(resources["food"])) / float(divisor)))
		atk += bonus
	var damage := maxf(0.1, snappedf(atk * variance, 0.1))
	var shield := float(target.get("shield", 0.0))
	if shield > 0.0:
		var absorbed := minf(shield, damage)
		target["shield"] = shield - absorbed
		damage -= absorbed
		if absorbed > 0.0:
			_add_log("%s 的护盾吸收 %.1f。" % [str(target["name"]), absorbed])
	if damage <= 0.0:
		_add_log("%s 攻击 %s，被护盾完全挡下。" % [str(attacker["name"]), str(target["name"])])
		return 0.0

	var lost := minf(float(target["hp"]), damage)
	target["hp"] = float(target["hp"]) - damage
	_add_log("%s 攻击 %s，造成 %.1f 伤害（%s 剩余 %.1f）。" % [
		str(attacker["name"]), str(target["name"]), damage,
		str(target["name"]), maxf(0.0, float(target["hp"]))
	])
	_after_take_damage(target, lost)

	# 因粮蚁：每次攻击命中获得 1 食物，无上限。
	if damage > 0.0 and str(attacker.get("signature", {}).get("id", "")) == "yinliang":
		var food := int(attacker["signature"].get("params", {}).get("food_per_hit", 1))
		_gain_food(food)
		_add_log("因粮：%s 命中，食物 +%d。" % [str(attacker["name"]), food])

	if attacker.has("weaken_chance") and rng.randf() < float(attacker["weaken_chance"]):
		target["weaken"] = int(target.get("weaken", 0)) + 1
		_add_log("%s 的挑击使 %s 被削弱（%d 层）。" % [
			str(attacker["name"]), str(target["name"]), int(target["weaken"])
		])
	if float(target["hp"]) <= 0.0 and bool(target["alive"]):
		_on_death(target, attacker)
	return damage


func _after_take_damage(target: Dictionary, lost: float) -> void:
	if lost <= 0.0:
		return
	var signature: Dictionary = target.get("signature", {})
	var params: Dictionary = signature.get("params", {})
	match str(signature.get("id", "")):
		"yuyong":
			var gain := float(params.get("max_hp_gain", 0.5))
			target["max_hp"] = float(target["max_hp"]) + gain
			target["hp"] = float(target["hp"]) + gain
			_add_log("余勇：%s +%.1f 最大生命【永久】（当前 %.1f）。" % [
				str(target["name"]), gain, float(target["max_hp"])
			])
		"hanyong":
			var atk_gain := float(params.get("attack_gain", 3.0))
			target["atk"] = float(target["atk"]) + atk_gain
			_add_log("悍勇：%s 实际掉血，攻击 +%.1f【战时】（当前 %.1f）。" % [
				str(target["name"]), atk_gain, float(target["atk"])
			])
		"eshou_baowu":
			if int(target.get("baowu_round", 0)) == int(battle.get("round", 1)):
				return
			target["baowu_round"] = int(battle.get("round", 1))
			var shield := float(params.get("shield", 1.0))
			target["shield"] = float(target.get("shield", 0.0)) + shield
			_add_log("堡坞：%s 受击后获得 %.1f 护盾（每轮 1 次）。" % [str(target["name"]), shield])


func _on_death(target: Dictionary, killer: Dictionary) -> void:
	target["alive"] = false
	_add_log("%s 退场。" % str(target["name"]))
	var signature: Dictionary = target.get("signature", {})
	var params: Dictionary = signature.get("params", {})
	# 钦天蚁「号令」绑定【不甘】：友方不甘额外结算 1 次（多只不叠加）。
	var bugan_times := 2 if _has_any_signature("haoling_qintian") else 1
	match str(signature.get("id", "")):
		"xunjie_bugan":
			warfruits["bugan"] = int(warfruits.get("bugan", 0)) + bugan_times
			_add_log("不甘：%s 获得 %d 个战果【不甘】。" % [str(target["name"]), bugan_times])
		"bugan_baozha":
			for _i in bugan_times:
				_suihuo_explosion(target, signature)
		"bugan_sishi":
			var gain := float(params.get("attack_gain", 1.0)) * float(bugan_times)
			for ally in _all_players():
				if bool(ally["alive"]):
					ally["atk"] = float(ally["atk"]) + gain
			_add_log("不甘：%s 阵亡，全队 +%.1f 攻击【战时】。" % [str(target["name"]), gain])
		"dilei":
			pass

	# 丰稔蚁「猎杀」：击杀者永久 +0.5 攻击；每场首杀额外 +1.0【战时】。
	if not killer.is_empty():
		var killer_signature: Dictionary = killer.get("signature", {})
		if str(killer_signature.get("id", "")) == "liesha_fengren":
			_fengren_kill(killer, killer_signature)


func _fengren_kill(killer: Dictionary, signature: Dictionary) -> void:
	var params: Dictionary = signature.get("params", {})
	var gain := float(params.get("kill_gain", 0.5))
	killer["atk"] = float(killer["atk"]) + gain
	var entry := _army_entry(int(killer.get("uid", 0)))
	if not entry.is_empty():
		entry["attack"] = float(entry.get("attack", 0.0)) + gain
	_add_log("丰稔：%s 击杀，攻击 +%.1f【永久】。" % [str(killer["name"]), gain])
	if bool(killer.get("fengren_first_kill", false)):
		return
	killer["fengren_first_kill"] = true
	var first_gain := float(params.get("first_kill_gain", 1.0))
	killer["atk"] = float(killer["atk"]) + first_gain
	_add_log("丰稔：%s 本场首杀，额外 +%.1f 攻击【战时】。" % [str(killer["name"]), first_gain])


func _suihuo_explosion(source: Dictionary, signature: Dictionary) -> void:
	var ratio := float(signature.get("params", {}).get("damage_ratio", 0.5))
	var base := float(source["atk"]) * ratio
	_add_log("不甘：%s 爆炸，对敌方前排每单位造成 %.1f 基础伤害。" % [str(source["name"]), base])
	var front: Array = battle["enemies"]["front"]
	var back: Array = battle["enemies"]["back"]
	for target in front:
		if bool(target["alive"]):
			_flat_damage(target, base, str(source["name"]))
	if not _side_alive(front):
		for target in back:
			if bool(target["alive"]):
				_flat_damage(target, base, str(source["name"]))


func _flat_damage(target: Dictionary, base: float, source_name: String) -> void:
	var damage := maxf(0.1, snappedf(base * rng.randf_range(0.90, 1.10), 0.1))
	var shield := float(target.get("shield", 0.0))
	if shield > 0.0:
		var absorbed := minf(shield, damage)
		target["shield"] = shield - absorbed
		damage -= absorbed
	if damage <= 0.0:
		_add_log("%s 的爆炸被 %s 的护盾挡下。" % [source_name, str(target["name"])])
		return
	var lost := minf(float(target["hp"]), damage)
	target["hp"] = float(target["hp"]) - damage
	_add_log("%s 的爆炸对 %s 造成 %.1f 伤害（剩余 %.1f）。" % [
		source_name, str(target["name"]), damage, maxf(0.0, float(target["hp"]))
	])
	_after_take_damage(target, lost)
	if float(target["hp"]) <= 0.0 and bool(target["alive"]):
		_on_death(target, {})


func _check_battle_end() -> bool:
	if not _side_alive(battle["enemies"]["front"]) and not _side_alive(battle["enemies"]["back"]):
		_finish_battle(true)
		return true
	if not _side_alive(battle["player"]["front"]) and not _side_alive(battle["player"]["back"]):
		_finish_battle(false)
		return true
	return false


func _side_alive(units: Array) -> bool:
	for unit in units:
		if bool(unit["alive"]):
			return true
	return false


func _pick_back_player() -> Dictionary:
	var back: Array = battle["player"]["back"]
	for unit in back:
		if bool(unit["alive"]):
			return unit
	return {}


func enemies_front_alive() -> bool:
	return _side_alive(battle.get("enemies", {}).get("front", []))


func _pick_player_target() -> Dictionary:
	var front: Array = battle["player"]["front"]
	var back: Array = battle["player"]["back"]
	# 堡坞蚁「扼守」：常驻嘲讽，优先成为敌方单体攻击对象。
	for unit in front:
		if bool(unit["alive"]) and str(unit.get("signature", {}).get("id", "")) == "eshou_baowu":
			return unit
	var pool: Array = front if _side_alive(front) else back
	var best := {}
	for unit in pool:
		if not bool(unit["alive"]):
			continue
		if best.is_empty() or float(unit["hp"]) < float(best["hp"]):
			best = unit
	return best


func _refill_ap() -> void:
	for row in ["front", "back"]:
		for unit in battle["player"][row]:
			if bool(unit["alive"]):
				unit["ap"] = int(unit["max_ap"])
		for enemy in battle["enemies"][row]:
			if bool(enemy["alive"]):
				enemy["ap"] = int(enemy["max_ap"])


func player_has_ap() -> bool:
	if phase != Phase.BATTLE:
		return false
	for unit in _all_players():
		if bool(unit["alive"]) and int(unit["ap"]) > 0:
			return true
	return false


func army_base_supply() -> int:
	return 0


func army_supply() -> int:
	return 0



func _finish_battle(victory: bool, ruling: bool = false) -> void:
	var spec: Dictionary = battle.get("encounter", {})
	var encounter_key := str(spec.get("id", "sand"))
	battle["result"] = "ruling" if ruling else ("win" if victory else "lose")

	# 永久成长写回队伍（HP 上限）；攻击的【战时】加成不保留。
	# 用「上场快照 + 永久增量」写回，避免战斗内计相成长（花食物 +3 HP）被旧快照覆盖。
	for row in ["front", "back"]:
		for unit in battle["player"][row]:
			var entry := _army_entry(int(unit.get("uid", 0)))
			if not entry.is_empty():
				var base := float(unit.get("base_max_hp", float(unit["max_hp"])))
				var delta := float(unit["max_hp"]) - base
				entry["max_hp"] = float(entry.get("max_hp", base)) + delta
			var signature: Dictionary = unit.get("signature", {})
			if str(signature.get("id", "")) == "yingchao_zhiku" and not entry.is_empty():
				entry["battles"] = int(entry.get("battles", 0)) + 1
				_add_log("质库蚁：%s 累计第 %d 场，卖出时额外 +%d 食物。" % [
					str(unit["name"]), int(entry["battles"]), int(entry["battles"])
				])

	# 司农蚁「采撷」：每只参与战斗的司农蚁，若胜利或存活，额外 1–3 食物。
	for unit in _all_players():
		var signature: Dictionary = unit.get("signature", {})
		if str(signature.get("id", "")) != "caixie":
			continue
		if not (victory or bool(unit["alive"])):
			continue
		var params: Dictionary = signature.get("params", {})
		var food := rng.randi_range(int(params.get("food_min", 1)), int(params.get("food_max", 3)))
		_gain_food(food)
		_add_log("采撷：%s 额外带回 %d 食物。" % [str(unit["name"]), food])

	if victory:
		win_count += 1
		if ruling:
			_add_log("最终裁决：按未击杀结算，战利品减半。")
		_grant_battle_rewards(encounter_key, ruling)
		_add_log("战斗胜利。")
	else:
		lose_count += 1
		var penalty := int(balance.get("combat", {}).get("defeat_health", 5))
		health = maxf(0.0, health - penalty)
		_add_log("战斗失败：巢穴 -%d，士兵返场（HP 下场回满）。" % penalty)

	_tick_planted()
	battle = {}
	deploy_units = []
	pending_event = {}
	selected_uid = -1
	if health <= 0.0:
		_fail_game()
		return
	_advance_event()


func _grant_battle_rewards(encounter_key: String, ruling: bool) -> void:
	# 用开战快照里的奖励表，战斗中途热更不影响本场结算。
	var rewards: Dictionary = battle.get("rewards", {})
	var cfg: Dictionary = rewards.get(encounter_key, rewards.get("sand", {}))
	if cfg.is_empty():
		return
	var food_range: Array = cfg.get("food", [0, 0])
	var food := rng.randi_range(int(food_range[0]), int(food_range[1]))
	if ruling:
		food = int(floor(float(food) / 2.0))
	_gain_food(food)
	var text := "战利品：食物 +%d" % food
	if rng.randf() < float(cfg.get("warfruits", 0.0)):
		warfruits["warspoil"] = int(warfruits.get("warspoil", 0)) + 1
		text += "、战果 +1"
	if rng.randf() < float(cfg.get("amber", 0.0)):
		amber += 1
		text += "、虫珀 +1"
	_add_log(text + "。")


func _army_entry(uid: int) -> Dictionary:
	for entry in army:
		if int(entry.get("uid", 0)) == uid:
			return entry
	return {}


func _new_army_unit(unit_id: String) -> Dictionary:
	var data := unit_info(unit_id)
	var entry := {
		"uid": next_unit_uid,
		"unit_id": unit_id,
		"max_hp": float(data.get("hp", 5.0)),
		"attack": float(data.get("attack", 1.0)),
		"star": 1,
		"battles": 0,
	}
	next_unit_uid += 1
	return entry


func _next_ready_player() -> Dictionary:
	var players: Dictionary = battle.get("player", {})
	for row in ["front", "back"]:
		for unit in players.get(row, []):
			if bool(unit["alive"]) and int(unit["ap"]) > 0:
				return unit
	return {}


# ---------------------------------------------------------------------------
# 招募
# ---------------------------------------------------------------------------

func recruit(unit_id: String) -> bool:
	if phase != Phase.RECRUIT or not recruit_candidates.has(unit_id):
		return false
	var data := unit_info(unit_id)
	if data.is_empty():
		return false
	if army.size() >= int(balance["army"]["max_size"]):
		_add_log("军队已满（%d/%d），先结束招募。" % [army.size(), int(balance["army"]["max_size"])])
		changed.emit()
		return false
	var free := free_recruits_left > 0
	if free:
		free_recruits_left -= 1
	else:
		var cost := int(data.get("cost_food", 4))
		if int(resources["food"]) < cost:
			_add_log("食物不足，无法招募 %s（需要 %d）。" % [str(data.get("name", unit_id)), cost])
			changed.emit()
			return false
		_spend_food(cost)

	army.append(_new_army_unit(unit_id))
	_add_log("%s招募 %s，军队 %d/%d。" % [
		"免费" if free else "花费 %d 食物，" % int(data.get("cost_food", 4)),
		str(data.get("name", unit_id)), army.size(), int(balance["army"]["max_size"])
	])
	recruit_candidates = _roll_recruits()
	changed.emit()
	return true


func refresh_recruit() -> bool:
	if phase != Phase.RECRUIT:
		return false
	if free_refreshes > 0:
		free_refreshes -= 1
		recruit_candidates = _roll_recruits()
		_add_log("使用免费刷新（剩余 %d 次）。" % free_refreshes)
		changed.emit()
		return true
	var cost := int(balance["recruit"]["refresh_cost"])
	if int(resources["food"]) < cost:
		_add_log("食物不足，无法刷新招募。")
		changed.emit()
		return false
	_spend_food(cost)
	recruit_candidates = _roll_recruits()
	_add_log("刷新招募候选，食物 -%d。" % cost)
	changed.emit()
	return true


func skip_recruit() -> void:
	end_recruit()


func can_recruit(unit_id: String) -> bool:
	if phase != Phase.RECRUIT or not recruit_candidates.has(unit_id):
		return false
	if army.size() >= int(balance["army"]["max_size"]):
		return false
	var data := unit_info(unit_id)
	if free_recruits_left > 0:
		return true
	return int(resources["food"]) >= int(data.get("cost_food", 4))


func unit_info(unit_id: String) -> Dictionary:
	for unit in units_data.get("units", []):
		if str(unit.get("id", "")) == unit_id:
			return unit
	return {}


func can_sell(uid: int) -> bool:
	if phase != Phase.RECRUIT and phase != Phase.ACTION:
		return false
	return not _army_entry(uid).is_empty()


func sell_price(uid: int) -> int:
	var entry := _army_entry(uid)
	if entry.is_empty():
		return 0
	var data := unit_info(str(entry.get("unit_id", "")))
	var signature: Dictionary = data.get("signature", {})
	var params: Dictionary = signature.get("params", {})
	var price := int(params.get("sell_base", 2))
	if str(signature.get("id", "")) == "yingchao_zhiku":
		price += int(entry.get("battles", 0)) * int(params.get("bonus_per_battle", 1))
	return price


func sell_unit(uid: int) -> bool:
	if not can_sell(uid):
		return false
	var entry := _army_entry(uid)
	var data := unit_info(str(entry.get("unit_id", "")))
	var price := sell_price(uid)
	var name := str(data.get("name", entry.get("unit_id", "")))
	army.erase(entry)
	_gain_food(price)
	_add_log("卖出 %s，食物 +%d（军队 %d/%d）。" % [
		name, price, army.size(), int(balance["army"]["max_size"])
	])
	changed.emit()
	return true


func battle_tier_name(raw) -> String:
	if raw is String:
		var encounter: Dictionary = enemies_data.get("encounters", {}).get(str(raw), {})
		return str(encounter.get("name", raw))
	if raw is Dictionary:
		return _encounter_name(raw)
	return str(raw)


# ---------------------------------------------------------------------------
# 事件结算
# ---------------------------------------------------------------------------

func _resolve_event(event: Dictionary) -> void:
	var title := str(event.get("title", "未知事件"))
	var letter: String = EVENT_LETTERS[event_index] if event_index < EVENT_LETTERS.size() else "?"
	_apply_effects(event.get("effects", {}))
	_add_log("事件 %s：%s 结算。" % [letter, title])
	_tick_planted()

	if health <= 0.0:
		_fail_game()
		return
	if bool(event.get("recruit", false)):
		_open_recruit()
		return
	_advance_event()


func _advance_event() -> void:
	event_index += 1
	if event_index >= GROUP_SIZE:
		# 春季切片：事件组 → 三选一（主观行动）→ 回合结束。
		phase = Phase.ACTION
		_add_log("事件组结束：选择本回合的主观行动（冒险 / 巢穴恢复 / 巢穴扩建）。")
	else:
		phase = Phase.EVENT


func _open_recruit() -> void:
	_open_recruit_window("event")


func _roll_recruits() -> Array[String]:
	var rates := _tier_rates()
	var pool_by_tier := {}
	for unit in units_data.get("units", []):
		var tier := int(unit.get("tier", 1))
		if tier > nest_level:
			continue
		var cost := int(unit.get("cost_food", 4))
		# 免费招募不看食物；付费招募只列付得起的。
		if free_recruits_left <= 0 and cost > int(resources["food"]):
			continue
		if not pool_by_tier.has(tier):
			pool_by_tier[tier] = []
		pool_by_tier[tier].append(str(unit["id"]))

	var picked: Array[String] = []
	var all_affordable: Array[String] = []
	for tier in pool_by_tier.keys():
		for unit_id in pool_by_tier[tier]:
			all_affordable.append(str(unit_id))
	if all_affordable.is_empty():
		return picked

	var want := int(balance["recruit"].get("candidates", 3))
	while picked.size() < want:
		var tier := _roll_tier(rates)
		var pool: Array = pool_by_tier.get(tier, [])
		if pool.is_empty():
			pool = all_affordable
		picked.append(str(pool[rng.randi_range(0, pool.size() - 1)]))

	# 升阶保底：新阶级第一次招募至少 1 个该阶级单位（付得起的才保底）。
	if tier_pity > 0:
		var pity_pool: Array = pool_by_tier.get(tier_pity, [])
		if not pity_pool.is_empty():
			var already := false
			for unit_id in picked:
				if pity_pool.has(unit_id):
					already = true
					break
			if not already and not picked.is_empty():
				picked[0] = str(pity_pool[rng.randi_range(0, pity_pool.size() - 1)])
			tier_pity = 0
	return picked


func _tier_rates() -> Array:
	var table: Dictionary = balance["recruit"].get("tier_rates", {})
	var key := str(nest_level)
	if table.has(key):
		return table[key]
	return table.get("3", [])


func _roll_tier(rates: Array) -> int:
	if rates.is_empty():
		return 1
	var roll := rng.randf() * 100.0
	var acc := 0.0
	for entry in rates:
		acc += float(entry[1])
		if roll < acc:
			return int(entry[0])
	return int(rates[rates.size() - 1][0])


func tier_name(tier: int) -> String:
	match tier:
		2:
			return "二阶"
		3:
			return "三阶"
		_:
			return "一阶"


func current_event() -> Dictionary:
	var events: Array = active_group.get("events", [])
	if event_index < 0 or event_index >= events.size():
		return {}
	return events[event_index]


func current_group() -> Dictionary:
	return active_group


func max_health() -> float:
	return float(balance["max_health"])


func season_name() -> String:
	return SEASONS[clampi(season, 0, SEASONS.size() - 1)]


func weather_name() -> String:
	return weather_display_name(weather)


func weather_display_name(id: String) -> String:
	var names: Dictionary = balance.get("weather", {}).get("names", {})
	return str(names.get(id, id))


## 当前天气 + 未来 2 回合预报（Q-091 默认窗口；越界自动截断）。
func weather_forecast_text() -> String:
	var parts: Array[String] = []
	for offset in 3:
		var id := forecast_weather(offset)
		if id == "":
			break
		parts.append(("【%s】" % weather_display_name(id)) if offset == 0 else weather_display_name(id))
	return "天气 " + " → ".join(parts)


func _weather_effect(key: String, default_value: float) -> float:
	var effects: Dictionary = balance.get("weather", {}).get("effects", {})
	var entry: Dictionary = effects.get(weather, {})
	return float(entry.get(key, default_value))


func _season_modifier(key: String) -> int:
	var modifiers: Array = balance.get("season_modifier", [])
	if season >= 0 and season < modifiers.size():
		return int(modifiers[season].get(key, 0))
	return 0


func _roll_weather() -> String:
	var weights: Array = balance.get("weather", {}).get("weights", [])
	if weights.is_empty():
		return "clear"
	var table: Dictionary = weights[clampi(season, 0, weights.size() - 1)]
	var total := 0
	for key in table.keys():
		total += int(table[key])
	if total <= 0:
		return "clear"
	var roll := rng.randi_range(1, total)
	var accumulated := 0
	for key in table.keys():
		accumulated += int(table[key])
		if roll <= accumulated:
			return str(key)
	return "clear"


func _generate_season_weathers() -> void:
	season_weathers = []
	weather_index = 0
	for i in TURNS_PER_SEASON:
		season_weathers.append(_roll_weather())


func forecast_weather(offset: int) -> String:
	var index := weather_index - 1 + offset
	if index < 0 or index >= season_weathers.size():
		return ""
	return season_weathers[index]


func turn_in_season() -> int:
	return (turn - 1) % TURNS_PER_SEASON + 1


func nest_total_cells() -> int:
	return cells.size()


func nest_blocked_cells() -> int:
	var count := 0
	for cell in cells:
		if bool(cell["blocked"]):
			count += 1
	return count


func _end_turn() -> void:
	turn += 1
	if turn > TOTAL_TURNS:
		phase = Phase.WON
		_add_log("春季结束（6/6）。%s" % season_summary())
		changed.emit()
		return
	season = int(floor(float(turn - 1) / float(TURNS_PER_SEASON)))
	_begin_turn()


func season_summary() -> String:
	return "本季统计：食物 %+d（%d → %d），完整度 %+d（%d → %d），战斗 %d 场（胜 %d / 负 %d），虫珀 %d。" % [
		int(resources["food"]) - run_start_food, run_start_food, int(resources["food"]),
		int(health) - int(run_start_health), int(run_start_health), int(health),
		battle_count, win_count, lose_count, amber
	]


func _fail_game() -> void:
	phase = Phase.GAME_OVER
	_add_log("巢穴完整度归零，本局结束。")


func _do_adventure() -> bool:
	var cfg: Dictionary = balance["actions"]["adventure"]
	# 2026-11-09：探索代价由工蚁改为食物（Q-039 / Q-053）。
	var cost := rng.randi_range(int(cfg.get("food_cost_min", 1)), int(cfg.get("food_cost_max", 2)))
	cost += int(_weather_effect("explore_food_loss", 0.0))
	cost += int(balance.get("spring", {}).get("explore_food_loss", 0)) if season == 0 else 0
	if int(resources["food"]) < cost:
		_add_log("食物不足（探索需要 %d），冒险无法进行。" % cost)
		return false

	_spend_food(cost)
	var gain := rng.randi_range(int(cfg["food_min"]), int(cfg["food_max"]))
	gain += int(_weather_effect("adventure_food", 0.0)) + _season_modifier("adventure_food")
	gain = maxi(0, gain)
	_gain_food(gain)

	var health_delta := float(cfg.get("health", 0.0)) + _weather_effect("adventure_health", 0.0)
	health = clampf(health + health_delta, 0.0, max_health())

	var found_seed := rng.randf() < float(cfg.get("seed_chance", 0.0))
	var note := ""
	if found_seed:
		var pool: Array = cfg.get("seed_pool", [])
		if not pool.is_empty():
			var seed_id := str(pool[rng.randi_range(0, pool.size() - 1)])
			seeds.append(seed_id)
			note = "，带回种子【%s】" % _seed_name(seed_id)
	_add_log("冒险（%s）：食物 -%d / +%d（净 %+d）%s，巢穴 %s%d。" % [
		weather_name(), cost, gain, gain - cost, note, "+" if health_delta >= 0.0 else "", int(health_delta)
	])
	return true


func _do_heal() -> bool:
	var cfg: Dictionary = balance["actions"]["heal"]
	var cost := int(cfg["food_cost"])
	if int(resources["food"]) < cost:
		_add_log("食物不足（需要 %d），无法主动修复。" % cost)
		return false

	_spend_food(cost)
	var before := health
	health = minf(max_health(), health + float(cfg["health"]))
	_add_log("巢穴恢复：食物 -%d，巢穴完整度 %d → %d。" % [cost, int(before), int(health)])
	return true


func _do_expand() -> bool:
	var cfg: Dictionary = balance["actions"]["expand"]
	var max_level := int(balance["nest"]["max_level"])
	if nest_level >= max_level:
		_add_log("巢穴已是最高等级 Lv.%d。" % max_level)
		return false

	# 文档：扩建走巢穴经验线，食物可兑换经验（兑换率/阈值 Q-098 / Q-100 未定）。
	# 原型：经验 = 已投入食物，阈值按档位，补齐差额即可升级。
	var thresholds: Array = cfg.get("exp_threshold", [0, 20, 30])
	var need := int(thresholds[clampi(nest_level, 0, thresholds.size() - 1)])
	var remaining := maxi(0, need - exp_points)
	if int(resources["food"]) < remaining:
		_add_log("扩建需要经验 %d（还差 %d，可 1 食物换 1 经验），当前食物不足。" % [
			need, remaining
		])
		return false

	_spend_food(remaining)
	exp_points = need

	nest_level += 1
	exp_points = 0
	# 升阶保底：新阶级的第一次招募至少出现 1 个该阶级单位（Q-106）。
	tier_pity = nest_level
	var before_count := cells.size()
	_rebuild_cells()
	_add_log("巢穴扩建：Lv.%d，消耗 %d 食物，新增 %d 格（肥沃格累计 %d，其中可用 %d）。" % [
		nest_level, remaining, cells.size() - before_count, _fertile_count(), _usable_fertile_count()
	])
	return true


func _apply_effects(effects: Dictionary) -> void:
	# 兼容两套字段：旧 effects（health/food/seed/warspoil/amber）与 data-contract v1。
	var health_delta := float(effects.get("health", effects.get("integrity_delta", 0.0)))
	if health_delta != 0.0:
		health = clampf(health + health_delta, 0.0, max_health())
	var food_delta := int(effects.get("food", effects.get("food_delta", 0)))
	if food_delta > 0:
		_gain_food(food_delta)
	elif food_delta < 0:
		resources["food"] = maxi(0, int(resources["food"]) + food_delta)
	if effects.has("seed") or effects.has("gain_seed"):
		var value = effects.get("seed", effects.get("gain_seed"))
		if value is String and str(value) != "":
			seeds.append(str(value))
		elif bool(value):
			var pool: Array = balance["actions"]["adventure"].get("seed_pool", [])
			if not pool.is_empty():
				seeds.append(str(pool[rng.randi_range(0, pool.size() - 1)]))
	if effects.has("warspoil"):
		warfruits["warspoil"] = int(warfruits.get("warspoil", 0)) + int(effects["warspoil"])
	if effects.has("gain_result") and str(effects["gain_result"]) != "":
		var rid := str(effects["gain_result"])
		warfruits[rid] = int(warfruits.get(rid, 0)) + 1
	if effects.has("amber"):
		amber += int(effects["amber"])
	if effects.has("gain_relic") and str(effects["gain_relic"]) != "":
		amber += 1


# ---------------------------------------------------------------------------
# 种子（收获型生产单位）
# ---------------------------------------------------------------------------

func seed_info(seed_id: String) -> Dictionary:
	for seed in seeds_data.get("seeds", []):
		if str(seed.get("id", "")) == seed_id:
			return seed
	return {}


func _seed_name(seed_id: String) -> String:
	return str(seed_info(seed_id).get("name", seed_id))


func _fertile_count() -> int:
	var count := 0
	for cell in cells:
		if bool(cell["fertile"]):
			count += 1
	return count


func fertile_count() -> int:
	return _fertile_count()


func _usable_fertile_count() -> int:
	var count := 0
	for cell in cells:
		if bool(cell["fertile"]) and not bool(cell["blocked"]):
			count += 1
	return count


func _is_occupied(q: int, r: int) -> bool:
	for entry in planted:
		if int(entry["q"]) == q and int(entry["r"]) == r:
			return true
	return false


func free_fertile_cells() -> Array:
	var free: Array = []
	for cell in cells:
		if bool(cell["fertile"]) and not bool(cell["blocked"]) and not _is_occupied(int(cell["q"]), int(cell["r"])):
			free.append(cell)
	return free


func plant_seed(seed_id: String) -> bool:
	if phase != Phase.ACTION and phase != Phase.GROUP_SELECT:
		_add_log("事件结算期间不能播种。")
		changed.emit()
		return false
	var index := seeds.find(seed_id)
	if index < 0:
		return false
	if free_fertile_cells().is_empty():
		_add_log("没有空的肥沃格可以播种。")
		changed.emit()
		return false
	seeds.remove_at(index)
	_plant(seed_id)
	_add_log("播种【%s】（周期 %d 事件）。" % [
		_seed_name(seed_id), int(seed_info(seed_id).get("period", 3))
	])
	# 耒耜蚁「营巢」：在场时播种有概率返 1 食物。
	if _has_army_signature("yingchao_leisi") and rng.randf() < 0.35:
		_gain_food(1)
		_add_log("耒耜蚁：播种返 1 食物。")
	changed.emit()
	return true


func _plant(seed_id: String) -> bool:
	var free := free_fertile_cells()
	if free.is_empty():
		seeds.append(seed_id)
		return false
	var cell: Dictionary = free[0]
	planted.append({
		"seed_id": seed_id,
		"q": int(cell["q"]),
		"r": int(cell["r"]),
		"counter": 0,
	})
	return true


func _tick_planted() -> void:
	for entry in planted:
		entry["counter"] = int(entry["counter"]) + 1
		var info := seed_info(str(entry["seed_id"]))
		var period := maxi(1, int(info.get("period", 3)))
		if int(entry["counter"]) < period:
			continue
		entry["counter"] = 0
		_harvest(info)


func _harvest(info: Dictionary) -> void:
	var kind := str(info.get("kind", "food"))
	var amount := int(info.get("yield", 1))
	var name := str(info.get("name", "种子"))
	match kind:
		"food":
			# 春季生产 +1（Q-057 占位）；晴天生产 +1（Q-053 提案）。
			var bonus := 0
			if season == 0:
				bonus += int(balance.get("spring", {}).get("production_bonus", 0))
			bonus += int(_weather_effect("production_bonus", 0.0))
			var total_food := amount + bonus
			_gain_food(total_food)
			_add_log("【%s】收获：食物 +%d。" % [name, total_food])
		"warspoil":
			var id := str(info.get("id", name))
			warfruits[id] = int(warfruits.get(id, 0)) + amount
			_add_log("【%s】收获：战果 +%d。" % [name, amount])
		"tool_heal":
			health = minf(max_health(), health + float(amount))
			_add_log("【%s】收获：巢穴恢复 +%d。" % [name, amount])
		_:
			_add_log("【%s】收获：%d。" % [name, amount])


func _forecast_food_per_turn() -> int:
	var total := 0
	for entry in planted:
		var info := seed_info(str(entry["seed_id"]))
		if str(info.get("kind", "food")) != "food":
			continue
		var period := maxi(1, int(info.get("period", 3)))
		var counter := int(entry["counter"])
		var harvests := int(floor(float(counter + GROUP_SIZE) / float(period))) - int(floor(float(counter) / float(period)))
		total += harvests * int(info.get("yield", 1))
	return total


func warfruit_count(seed_id: String) -> int:
	return int(warfruits.get(seed_id, 0))


func _can_pay(cost: Dictionary) -> bool:
	for key in cost.keys():
		if int(resources.get(key, 0)) < int(cost[key]):
			return false
	return true


func _pay(cost: Dictionary) -> void:
	for key in cost.keys():
		if key == "food":
			_spend_food(int(cost[key]))
		else:
			resources[key] = maxi(0, int(resources[key]) - int(cost[key]))


func _gain_food(amount: int) -> void:
	if amount <= 0:
		return
	resources["food"] = int(resources["food"]) + amount
	# 将作蚁「督造」：每次食物增加时按概率额外 +1 食物（二星 80%）。
	for entry in army:
		var data := unit_info(str(entry.get("unit_id", "")))
		var signature: Dictionary = data.get("signature", {})
		if str(signature.get("id", "")) != "duzao":
			continue
		var params: Dictionary = signature.get("params", {})
		var chance := float(params.get("proc_chance", 0.4))
		if int(entry.get("star", 1)) >= 2:
			chance = minf(1.0, chance * 2.0)
		if rng.randf() >= chance:
			continue
		var bonus := int(params.get("bonus_food", 1))
		resources["food"] = int(resources["food"]) + bonus
		_add_log("督造：食物增加时额外 +%d 食物（当前 %d）。" % [bonus, int(resources["food"])])


func _spend_food(amount: int) -> void:
	if amount <= 0:
		return
	resources["food"] = maxi(0, int(resources["food"]) - amount)
	food_spent_total += amount
	# 度支蚁「营巢」：每累计花费 6 食物，获得 1 次免费招募刷新。
	if _has_army_signature("yingchao_duzhi"):
		var threshold := 6
		var earned := int(floor(float(food_spent_total) / float(threshold)))
		var awarded := int(floor(float(food_spent_milestone) / float(threshold)))
		if earned > awarded:
			free_refreshes += earned - awarded
			food_spent_milestone = earned * threshold
			_add_log("度支蚁：累计花费 %d 食物，获得 %d 次免费刷新（现有 %d 次）。" % [
				food_spent_total, earned - awarded, free_refreshes
			])

	# 计相蚁「营巢」：每累计花费 6 食物，自身 +3.0 生命与攻击【永久】。
	for entry in army:
		var data := unit_info(str(entry.get("unit_id", "")))
		var signature: Dictionary = data.get("signature", {})
		if str(signature.get("id", "")) != "jixiang":
			continue
		var params: Dictionary = signature.get("params", {})
		var threshold := maxi(1, int(params.get("food_threshold", 6)))
		var earned := int(floor(float(food_spent_total) / float(threshold)))
		var awarded := int(entry.get("jixiang_awarded", 0))
		if earned <= awarded:
			continue
		var steps := earned - awarded
		entry["jixiang_awarded"] = earned
		entry["max_hp"] = float(entry.get("max_hp", 8.0)) + float(params.get("hp_gain", 3.0)) * float(steps)
		entry["attack"] = float(entry.get("attack", 1.5)) + float(params.get("attack_gain", 3.0)) * float(steps)
		_add_log("计相：累计花费 %d 食物，%s +%.1f 生命与 +%.1f 攻击【永久】（%d 层）。" % [
			food_spent_total, str(data.get("name", "计相蚁")),
			float(params.get("hp_gain", 3.0)) * float(steps),
			float(params.get("attack_gain", 3.0)) * float(steps), steps
		])


func _has_army_signature(signature_id: String) -> bool:
	for entry in army:
		var data := unit_info(str(entry.get("unit_id", "")))
		if str(data.get("signature", {}).get("id", "")) == signature_id:
			return true
	return false


func _rebuild_cells() -> void:
	cells = []
	var blocked: Array = blocked_dirs
	var fertile_per_ring := int(balance["nest"].get("fertile_per_ring", 3))
	for ring in range(0, nest_level + 1):
		var ring_cells: Array = HexGridScript.ring_cells(ring)
		var fertile_dirs := _fertile_directions(ring, fertile_per_ring, blocked)
		var used_dirs := {}
		for cell in ring_cells:
			var is_blocked := false
			if ring > 0 and blocked.has(HexGridScript.direction_of(cell.x, cell.y)):
				is_blocked = true
			var dir := HexGridScript.direction_of(cell.x, cell.y)
			var is_fertile := (
				ring > 0
				and not is_blocked
				and fertile_dirs.has(dir)
				and not used_dirs.has(dir)
			)
			if is_fertile:
				used_dirs[dir] = true
			cells.append({
				"q": cell.x,
				"r": cell.y,
				"blocked": is_blocked,
				"fertile": is_fertile,
			})


func _fertile_directions(ring: int, count: int, blocked: Array) -> Dictionary:
	# 肥沃格均匀分布在 3 个方向；被位置阻断的方向顺延到下一个可用方向。
	var result := {}
	if ring <= 0:
		return result
	for base in [0, 2, 4]:
		var dir: int = base
		var guard := 0
		while guard < 6 and blocked.has(dir):
			dir = (dir + 1) % 6
			guard += 1
		result[dir] = true
		if result.size() >= count:
			break
	return result


func _add_log(text: String) -> void:
	logs.append(text)
	if logs.size() > 200:
		logs.pop_front()


func _load_json(path: String) -> Dictionary:
	# 保留给旧调用；所有正式读盘走 DataStore。
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("无法读取数据文件：%s" % path)
		return {}
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("数据文件不是 JSON 对象：%s" % path)
		return {}
	return parsed

