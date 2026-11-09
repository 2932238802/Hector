class_name GameState
extends RefCounted
## 纯逻辑层：不依赖场景树，可在 --headless 下直接实例化做测试。
## 状态机：ACTION → GROUP_SELECT → EVENT（A→D，期间可进 BATTLE / RECRUIT）→ 下一回合。

signal changed

enum Phase { ACTION, GROUP_SELECT, EVENT, DEPLOY, BATTLE, RECRUIT, GAME_OVER, WON }

const EventPoolScript := preload("res://scripts/core/event_pool.gd")
const HexGridScript := preload("res://scripts/core/hex_grid.gd")

const TOTAL_TURNS := 24
const TURNS_PER_SEASON := 6
const GROUP_SIZE := 4
const SEASONS := ["春", "夏", "秋", "冬"]
const EVENT_LETTERS := ["A", "B", "C", "D"]

var balance: Dictionary = {}
var event_data: Dictionary = {}
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
var health := 60.0
var resources := {"food": 0}
var workers := 0
var exp_points := 0
var seeds: Array[String] = []
var planted: Array = []
var warfruits := {}
var army: Array[String] = []
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
var recruit_refreshed := false
var logs: Array[String] = []


func _init(p_seed: int = 0) -> void:
	balance = _load_json("res://data/balance.json")
	event_data = _load_json("res://data/events.json")
	units_data = _load_json("res://data/units.json")
	enemies_data = _load_json("res://data/enemies.json")
	seeds_data = _load_json("res://data/seeds.json")
	start_new_game(p_seed)


func start_new_game(p_seed: int = 0) -> void:
	seed_value = p_seed if p_seed != 0 else int(Time.get_unix_time_from_system())
	rng.seed = seed_value

	season = 0
	turn = 1
	event_index = 0
	season_weathers = []
	weather_index = 0
	nest_level = int(balance["start"].get("nest_level", 2))
	workers = int(balance["start"]["workers"])
	health = float(balance["start"]["health"])
	resources = {"food": int(balance["start"]["food"])}
	exp_points = 0
	seeds = []
	planted = []
	warfruits = {}
	army = []
	for unit_id in balance["start"].get("army", []):
		army.append(str(unit_id))
	groups = []
	active_group = {}
	battle = {}
	recruit_candidates = []
	recruit_refreshed = false
	logs = []

	location = str(balance.get("location", "river"))
	blocked_dirs = []
	for dir in balance["locations"][location].get("blocked_dirs", []):
		blocked_dirs.append(int(dir))

	_rebuild_cells()
	var start_seed := str(balance["start"].get("seed", ""))
	if start_seed != "":
		_plant(start_seed)
	_add_log("新的一局：%s，巢穴 Lv.%d（%d 格，%d 个肥沃格），食物 %d，军队 %d 只。" % [
		str(balance["locations"][location].get("name", location)), nest_level,
		cells.size(), _usable_fertile_count(), int(resources["food"]), army.size()
	])
	_begin_turn()


func _begin_turn() -> void:
	# 文档 Q-090：季初一次性生成 6 个天气，按季节权重抽取；预报窗口 Q-091 未定。
	if season_weathers.is_empty() or weather_index >= TURNS_PER_SEASON:
		_generate_season_weathers()
	weather = season_weathers[weather_index]
	weather_index += 1
	workers += int(balance["queen"]["workers_per_turn"])

	var heal_amount := minf(
		float(workers) * float(balance["heal"]["per_worker"]),
		float(balance["heal"]["cap"])
	)
	health = minf(max_health(), health + heal_amount)

	groups = EventPoolScript.build_groups(
		rng, event_data, int(balance["event_groups_per_turn"]), season
	)
	event_index = 0
	active_group = {}
	battle = {}
	deploy_units = []
	pending_event = {}
	recruit_candidates = []
	phase = Phase.ACTION
	_add_log("第 %d 回合（%s 第 %d/%d 回合，总 %d/%d）· 天气 %s：本回合预计产出 %d 食物，工蚁 +%d，巢穴恢复 +%d。" % [
		turn, season_name(), turn_in_season(), TURNS_PER_SEASON, turn, TOTAL_TURNS,
		weather_name(), _forecast_food_per_turn(),
		int(balance["queen"]["workers_per_turn"]), int(heal_amount)
	])
	changed.emit()


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
			phase = Phase.GROUP_SELECT
	changed.emit()
	return ok


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
		_open_deploy(event)
		changed.emit()
		return true

	_resolve_event(event)
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
	for unit_id in army:
		var data := unit_info(unit_id)
		if data.is_empty() or not bool(data.get("combat", false)):
			continue
		var row := str(data.get("row", "front"))
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
			"unit_id": unit_id,
			"name": str(data.get("name", unit_id)),
			"row": row,
			"supply": int(data.get("supply", 1)),
			"deployed": deployed,
		})
	battle = {}
	phase = Phase.DEPLOY
	_add_log("布阵：%s 来袭，选择出战单位（前 %d / 后 %d）。" % [
		battle_tier_name(str(event.get("battle", "weak"))), _row_cap("front"), _row_cap("back")
	])


func _row_cap(row: String) -> int:
	return int(balance["army"].get(row, 4))


func _deploy_entry(unit_id: String) -> Dictionary:
	for entry in deploy_units:
		if str(entry["unit_id"]) == unit_id:
			return entry
	return {}


func deploy_set(unit_id: String, row: String) -> bool:
	if phase != Phase.DEPLOY:
		return false
	var entry := _deploy_entry(unit_id)
	if entry.is_empty():
		return false
	if row == "":
		entry["deployed"] = false
		changed.emit()
		return true
	if row != "front" and row != "back":
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
	var base := 0
	for entry in deploy_units:
		if bool(entry["deployed"]):
			base += int(entry["supply"])
	var mult := _weather_effect("supply_mult", 1.0)
	return int(ceil(float(base) * mult))


func can_start_battle() -> bool:
	return (
		phase == Phase.DEPLOY
		and deployed_count() > 0
		and int(resources["food"]) >= deploy_supply()
	)


func start_battle() -> bool:
	if phase != Phase.DEPLOY:
		return false
	var supply := deploy_supply()
	if deployed_count() <= 0:
		_add_log("没有出战单位，无法迎战。")
		changed.emit()
		return false
	if int(resources["food"]) < supply:
		_add_log("食物不足（补给需要 %d），先撤下单位。" % supply)
		changed.emit()
		return false

	resources["food"] = int(resources["food"]) - supply
	var players_front: Array = []
	var players_back: Array = []
	for entry in deploy_units:
		if not bool(entry["deployed"]):
			continue
		var data := unit_info(str(entry["unit_id"]))
		var unit := _make_unit(
			str(data.get("name", entry["unit_id"])),
			float(data.get("hp", 8)),
			float(data.get("atk", 2)),
			int(data.get("ap", 1)),
			str(entry["row"])
		)
		unit["unit_id"] = str(entry["unit_id"])
		if str(entry["row"]) == "front":
			players_front.append(unit)
		else:
			players_back.append(unit)

	var enemies_front: Array = []
	var enemies_back: Array = []
	for template in _tier_units(str(pending_event.get("battle", "weak"))):
		for i in int(template.get("count", 1)):
			var unit := _make_unit(
				str(template.get("name", "敌人")),
				float(template.get("hp", 8)),
				float(template.get("atk", 2)),
				int(template.get("ap", 1)),
				str(template.get("row", "front"))
			)
			if str(unit["row"]) == "front" and enemies_front.size() < _row_cap("front"):
				enemies_front.append(unit)
			elif enemies_back.size() < _row_cap("back"):
				unit["row"] = "back"
				enemies_back.append(unit)

	battle = {
		"player": {"front": players_front, "back": players_back},
		"enemies": {"front": enemies_front, "back": enemies_back},
		"round": 1,
		"supply": supply,
		"event": pending_event,
		"result": "",
	}
	phase = Phase.BATTLE
	_add_log("战斗开始：我方 %d 只，敌方 %d 只，补给 -%d 食物。" % [
		players_front.size() + players_back.size(),
		enemies_front.size() + enemies_back.size(), supply
	])
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


func _make_unit(name: String, hp: float, atk: float, ap: int, row: String) -> Dictionary:
	return {
		"name": name,
		"hp": hp,
		"max_hp": hp,
		"atk": atk,
		"ap": ap,
		"max_ap": ap,
		"shield": 0.0,
		"row": row,
		"alive": true,
	}


func _tier_units(tier: String) -> Array:
	var tiers: Dictionary = enemies_data.get("tiers", {})
	var tier_data: Dictionary = tiers.get(tier, tiers.get("weak", {}))
	return tier_data.get("units", [])


# ---------------------------------------------------------------------------
# 战斗
# ---------------------------------------------------------------------------

func player_attack(row: String, index: int) -> bool:
	if phase != Phase.BATTLE:
		return false
	if row != "front" and row != "back":
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

	var attacker := _next_ready_player()
	if attacker.is_empty():
		_add_log("我方没有剩余行动点，点「结束玩家阶段」。")
		changed.emit()
		return false

	_attack(attacker, target)
	attacker["ap"] = int(attacker["ap"]) - 1
	_check_battle_end()
	changed.emit()
	return true


func end_player_phase() -> void:
	if phase != Phase.BATTLE:
		return
	for row in ["front", "back"]:
		for enemy in battle["enemies"][row]:
			while bool(enemy["alive"]) and int(enemy["ap"]) > 0:
				var target := _pick_player_target()
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
	changed.emit()


func _attack(attacker: Dictionary, target: Dictionary) -> float:
	var variance := rng.randf_range(0.90, 1.10)
	var damage := maxf(0.1, snappedf(float(attacker["atk"]) * variance, 0.1))
	var shield := float(target.get("shield", 0.0))
	if shield > 0.0:
		var absorbed := minf(shield, damage)
		target["shield"] = shield - absorbed
		damage -= absorbed
		if absorbed > 0.0:
			_add_log("%s 的护盾吸收 %.1f。" % [str(target["name"]), absorbed])
	if damage > 0.0:
		target["hp"] = float(target["hp"]) - damage
		_add_log("%s 攻击 %s，造成 %.1f 伤害（%s 剩余 %.1f）。" % [
			str(attacker["name"]), str(target["name"]), damage,
			str(target["name"]), maxf(0.0, float(target["hp"]))
		])
		if float(target["hp"]) <= 0.0 and bool(target["alive"]):
			target["alive"] = false
			_add_log("%s 退场。" % str(target["name"]))
	else:
		_add_log("%s 攻击 %s，被护盾完全挡下。" % [str(attacker["name"]), str(target["name"])])
	return damage


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


func enemies_front_alive() -> bool:
	return _side_alive(battle.get("enemies", {}).get("front", []))


func _pick_player_target() -> Dictionary:
	var front: Array = battle["player"]["front"]
	var back: Array = battle["player"]["back"]
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
	return not _next_ready_player().is_empty()


func army_base_supply() -> int:
	var supply := 0
	for unit_id in army:
		supply += int(unit_info(unit_id).get("supply", 0))
	return supply


func army_supply() -> int:
	var base := army_base_supply()
	var mult := _weather_effect("supply_mult", 1.0)
	return int(ceil(float(base) * mult))



func _finish_battle(victory: bool, ruling: bool = false) -> void:
	var event: Dictionary = battle.get("event", {})
	battle["result"] = "ruling" if ruling else ("win" if victory else "lose")

	if victory:
		var effects: Dictionary = event.get("effects", {})
		if ruling:
			var reduced := {}
			for key in effects.keys():
				if str(key) == "food":
					reduced[key] = int(floor(float(int(effects[key])) / 2.0))
			effects = reduced
			_add_log("最终裁决：按未击杀结算，只给减少后的防守奖励。")
		_apply_effects(effects)
		_add_log("战斗胜利，战利品已结算。")
	else:
		var penalty := int(balance.get("combat", {}).get("defeat_health", 10))
		health = maxf(0.0, health - penalty)
		_add_log("战斗失败：巢穴 -%d，士兵返场（HP 下场回满）。" % penalty)

	_tick_planted()
	battle = {}
	deploy_units = []
	pending_event = {}
	if health <= 0.0:
		_fail_game()
		return
	_advance_event()


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
		_add_log("军队已满（%d/%d）。" % [army.size(), int(balance["army"]["max_size"])])
		changed.emit()
		return false
	if not _can_pay(data.get("cost", {})):
		_add_log("资源不足，无法招募 %s。" % str(data.get("name", unit_id)))
		changed.emit()
		return false

	_pay(data.get("cost", {}))
	army.append(unit_id)
	_add_log("招募 %s，军队 %d/%d。" % [
		str(data.get("name", unit_id)), army.size(), int(balance["army"]["max_size"])
	])
	recruit_candidates = []
	_advance_event()
	changed.emit()
	return true


func refresh_recruit() -> bool:
	if phase != Phase.RECRUIT or recruit_refreshed:
		return false
	var cost := int(balance["recruit"]["refresh_cost"])
	if int(resources["food"]) < cost:
		_add_log("食物不足，无法刷新招募。")
		changed.emit()
		return false
	resources["food"] = int(resources["food"]) - cost
	recruit_refreshed = true
	recruit_candidates = _roll_recruits()
	_add_log("刷新招募候选，食物 -%d。" % cost)
	changed.emit()
	return true


func skip_recruit() -> void:
	if phase != Phase.RECRUIT:
		return
	_add_log("跳过招募。")
	recruit_candidates = []
	_advance_event()
	changed.emit()


func can_recruit(unit_id: String) -> bool:
	if phase != Phase.RECRUIT or not recruit_candidates.has(unit_id):
		return false
	if army.size() >= int(balance["army"]["max_size"]):
		return false
	return _can_pay(unit_info(unit_id).get("cost", {}))


func unit_info(unit_id: String) -> Dictionary:
	for unit in units_data.get("units", []):
		if str(unit.get("id", "")) == unit_id:
			return unit
	return {}


func battle_tier_name(tier: String) -> String:
	var tiers: Dictionary = enemies_data.get("tiers", {})
	return str(tiers.get(tier, {}).get("name", tier))


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
		_end_turn()
	else:
		phase = Phase.EVENT


func _open_recruit() -> void:
	recruit_candidates = _roll_recruits()
	recruit_refreshed = false
	phase = Phase.RECRUIT
	_add_log("招募事件：3 个候选，选 1；可花 %d 食物刷新一次。" % int(balance["recruit"]["refresh_cost"]))


func _roll_recruits() -> Array[String]:
	var pool: Array[String] = []
	for unit in units_data.get("units", []):
		if bool(unit.get("combat", false)):
			pool.append(str(unit["id"]))

	var picked: Array[String] = []
	var candidates := pool.duplicate()
	EventPoolScript.shuffle(rng, candidates)
	for unit_id in candidates:
		if picked.size() >= 3:
			break
		picked.append(str(unit_id))
	return picked


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
	var names: Dictionary = balance.get("weather", {}).get("names", {})
	return str(names.get(weather, weather))


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
		_add_log("撑过四季，进入终局。")
		changed.emit()
		return
	season = int(floor(float(turn - 1) / float(TURNS_PER_SEASON)))
	_begin_turn()


func _fail_game() -> void:
	phase = Phase.GAME_OVER
	_add_log("巢穴完整度归零，本局结束。")


func _do_adventure() -> bool:
	var cfg: Dictionary = balance["actions"]["adventure"]
	var cost := rng.randi_range(int(cfg["workers_min"]), int(cfg["workers_max"]))
	cost += int(_weather_effect("adventure_workers", 0.0))
	cost = mini(cost, workers)
	if cost <= 0:
		_add_log("没有可派出的工蚁，冒险无法进行。")
		return false

	workers -= cost
	var gain := rng.randi_range(int(cfg["food_min"]), int(cfg["food_max"]))
	gain += int(_weather_effect("adventure_food", 0.0)) + _season_modifier("adventure_food")
	gain = maxi(0, gain)
	resources["food"] = int(resources["food"]) + gain

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
	_add_log("冒险（%s）：派出 %d 只工蚁，食物 +%d%s，巢穴 %s%d。" % [
		weather_name(), cost, gain, note, "+" if health_delta >= 0.0 else "", int(health_delta)
	])
	return true


func _do_heal() -> bool:
	var cfg: Dictionary = balance["actions"]["heal"]
	var cost := int(cfg["food_cost"])
	if int(resources["food"]) < cost:
		_add_log("食物不足（需要 %d），无法主动修复。" % cost)
		return false

	resources["food"] = int(resources["food"]) - cost
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

	resources["food"] = int(resources["food"]) - remaining
	exp_points = need

	nest_level += 1
	exp_points = 0
	var before_count := cells.size()
	_rebuild_cells()
	_add_log("巢穴扩建：Lv.%d，消耗 %d 食物，新增 %d 格（肥沃格累计 %d，其中可用 %d）。" % [
		nest_level, remaining, cells.size() - before_count, _fertile_count(), _usable_fertile_count()
	])
	return true


func _apply_effects(effects: Dictionary) -> void:
	if effects.has("health"):
		health = clampf(health + float(effects["health"]), 0.0, max_health())
	if effects.has("food"):
		resources["food"] = maxi(0, int(resources["food"]) + int(effects["food"]))
	if effects.has("workers"):
		workers = maxi(0, workers + int(effects["workers"]))
	if effects.has("seed"):
		var value = effects["seed"]
		if value is String and str(value) != "":
			seeds.append(str(value))
		elif bool(value):
			var pool: Array = balance["actions"]["adventure"].get("seed_pool", [])
			if not pool.is_empty():
				seeds.append(str(pool[rng.randi_range(0, pool.size() - 1)]))


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
			resources["food"] = int(resources["food"]) + amount
			_add_log("【%s】收获：食物 +%d。" % [name, amount])
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
		resources[key] = maxi(0, int(resources[key]) - int(cost[key]))


func _rebuild_cells() -> void:
	cells = []
	var blocked: Array = blocked_dirs
	var fertile_per_ring := int(balance["nest"].get("fertile_per_ring", 3))
	for ring in range(0, nest_level):
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
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("无法读取数据文件：%s" % path)
		return {}
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("数据文件不是 JSON 对象：%s" % path)
		return {}
	return parsed

