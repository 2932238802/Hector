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
var recruit_pity_tier := 0
var free_recruits_left := 0
var recruit_free := false
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
	recruit_candidates = []
	recruit_refreshed = false
	recruit_pity_tier = 0
	free_recruits_left = 0
	recruit_free = false
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
	_begin_opening()


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
	phase = Phase.ACTION
	# 2026-11-09：工蚁 / 维持 / 被动恢复已删除，回合开始只做收入汇报（Q-035）。
	_add_log("第 %d 回合（%s 第 %d/%d 回合，总 %d/%d）· 天气 %s：食物 %d，已播种 %d 块，事件内预计食物 +%d。" % [
		turn, season_name(), turn_in_season(), TURNS_PER_SEASON, turn, TOTAL_TURNS,
		weather_name(), int(resources["food"]), planted.size(), _forecast_food_per_turn()
	])
	changed.emit()


func _begin_opening() -> void:
	free_recruits_left = int(balance["start"].get("free_recruits", 2))
	if free_recruits_left <= 0:
		phase = Phase.ACTION
		return
	_add_log("开局：免费招募 %d 次（3 选 1，不占行动）。" % free_recruits_left)
	_open_free_recruit()


func _open_free_recruit() -> void:
	recruit_free = true
	recruit_refreshed = true
	recruit_candidates = _roll_recruits()
	phase = Phase.RECRUIT
	var done := int(balance["start"].get("free_recruits", 2)) - free_recruits_left
	_add_log("免费招募 %d/%d：从一阶池 3 选 1，可跳过。" % [done + 1, int(balance["start"].get("free_recruits", 2))])
	changed.emit()


func _finish_free_recruit() -> void:
	free_recruits_left -= 1
	recruit_candidates = []
	if free_recruits_left > 0:
		_open_free_recruit()
		return
	recruit_free = false
	phase = Phase.ACTION
	_add_log("开局招募完成，第 1 回合开始。")
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
			resources["food"] = int(resources["food"]) - cost
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
		resources["food"] = int(resources["food"]) - cost

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
			var enemy_mult := float(balance.get("spring", {}).get("enemy_scale", 1.0))
			var unit := _make_unit(
				str(template.get("name", "敌人")),
				snappedf(float(template.get("hp", 8)) * enemy_mult, 0.1),
				snappedf(float(template.get("atk", 2)) * enemy_mult, 0.1),
				int(template.get("ap", 1)),
				str(template.get("row", "front"))
			)
			if str(unit["row"]) == "front" and enemies_front.size() < _row_cap("front"):
				enemies_front.append(unit)
			elif enemies_back.size() < _row_cap("back"):
				unit["row"] = "back"
				enemies_back.append(unit)
			for key in ["shield_per_round", "weaken_chance", "weaken_per_round", "bypass_first"]:
				if template.has(key):
					unit[key] = template[key]
			unit["first_attack_used"] = false

	battle = {
		"player": {"front": players_front, "back": players_back},
		"enemies": {"front": enemies_front, "back": enemies_back},
		"round": 1,
		"event": pending_event,
		"rewards": balance.get("combat", {}).get("rewards", {}).duplicate(true),
		"result": "",
	}
	battle_count += 1
	_start_round_effects()
	phase = Phase.BATTLE
	_add_log("战斗开始：我方 %d 只，敌方 %d 只。" % [
		players_front.size() + players_back.size(),
		enemies_front.size() + enemies_back.size()
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
		"weaken": 0,
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
	# 削弱每轮结束 -1 层；盾甲补盾；结网蛛吐丝；掠食雀重置越排攻击。
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


func _attack(attacker: Dictionary, target: Dictionary) -> float:
	var variance := rng.randf_range(0.90, 1.10)
	var atk := float(attacker["atk"])
	if int(attacker.get("weaken", 0)) > 0:
		atk *= 0.5
	var damage := maxf(0.1, snappedf(atk * variance, 0.1))
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
		if attacker.has("weaken_chance") and rng.randf() < float(attacker["weaken_chance"]):
			target["weaken"] = int(target.get("weaken", 0)) + 1
			_add_log("%s 的挑击使 %s 被削弱（%d 层）。" % [
				str(attacker["name"]), str(target["name"]), int(target["weaken"])
			])
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
	return 0


func army_supply() -> int:
	return 0



func _finish_battle(victory: bool, ruling: bool = false) -> void:
	var event: Dictionary = battle.get("event", {})
	battle["result"] = "ruling" if ruling else ("win" if victory else "lose")

	if victory:
		win_count += 1
		if ruling:
			_add_log("最终裁决：按未击杀结算，战利品减半。")
		_grant_battle_rewards(str(event.get("battle", "weak")), ruling)
		_add_log("战斗胜利。")
	else:
		lose_count += 1
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


func _grant_battle_rewards(tier: String, ruling: bool) -> void:
	# 用开战快照里的奖励表，战斗中途热更不影响本场结算。
	var rewards: Dictionary = battle.get("rewards", {})
	var cfg: Dictionary = rewards.get(tier, {})
	if cfg.is_empty():
		return
	var food_range: Array = cfg.get("food", [0, 0])
	var food := rng.randi_range(int(food_range[0]), int(food_range[1]))
	if ruling:
		food = int(floor(float(food) / 2.0))
	resources["food"] = int(resources["food"]) + food
	var text := "战利品：食物 +%d" % food
	if rng.randf() < float(cfg.get("warfruits", 0.0)):
		warfruits["warspoil"] = int(warfruits.get("warspoil", 0)) + 1
		text += "、战果 +1"
	if rng.randf() < float(cfg.get("amber", 0.0)):
		amber += 1
		text += "、虫珀 +1"
	_add_log(text + "。")


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
	if recruit_free:
		army.append(unit_id)
		_add_log("免费招募 %s，军队 %d/%d。" % [
			str(data.get("name", unit_id)), army.size(), int(balance["army"]["max_size"])
		])
		_finish_free_recruit()
		changed.emit()
		return true
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
	if recruit_free:
		_add_log("跳过本次免费招募。")
		_finish_free_recruit()
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
	if recruit_candidates.is_empty():
		_add_log("招募事件：没有付得起的兵种，只能跳过。")
	else:
		_add_log("招募事件：%d 个候选，选 1；可花 %d 食物刷新一次。" % [
			recruit_candidates.size(), int(balance["recruit"]["refresh_cost"])
		])


func _roll_recruits() -> Array[String]:
	var rates := _tier_rates()
	var pool_by_tier := {}
	for unit in units_data.get("units", []):
		if not bool(unit.get("combat", false)):
			continue
		var tier := int(unit.get("tier", 1))
		if tier > nest_level:
			continue
		if int(unit.get("cost", {}).get("food", 0)) > int(resources["food"]):
			continue
		if not pool_by_tier.has(tier):
			pool_by_tier[tier] = []
		pool_by_tier[tier].append(str(unit["id"]))

	var picked: Array[String] = []
	# 升阶保底：扩建后的第一次招募至少 1 个新阶级（Q-103）。
	if recruit_pity_tier > 1:
		var new_tier_pool: Array = pool_by_tier.get(recruit_pity_tier, [])
		if new_tier_pool.is_empty():
			_add_log("升阶保底：没有付得起的%s单位，本次不保底。" % tier_name(recruit_pity_tier))
		else:
			picked.append(str(new_tier_pool[rng.randi_range(0, new_tier_pool.size() - 1)]))
			_add_log("升阶保底：本次招募必出%s。" % tier_name(recruit_pity_tier))
		recruit_pity_tier = 0

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

	resources["food"] = int(resources["food"]) - cost
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
	# 升阶后第一次招募保底：至少 1 个新阶级单位（Q-103）。L2 → 二阶，L3 → 三阶。
	recruit_pity_tier = nest_level
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
	if food_delta != 0:
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
			resources["food"] = int(resources["food"]) + amount + bonus
			_add_log("【%s】收获：食物 +%d。" % [name, amount + bonus])
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

