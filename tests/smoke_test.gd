extends SceneTree
## 冒烟测试：春季 6 回合主循环、可反复招募、手动点选战斗、关键词钩子。
## 用法：godot --headless --path <project> --script res://tests/smoke_test.gd

const GameStateScript := preload("res://scripts/core/game_state.gd")
const HexGridScript := preload("res://scripts/core/hex_grid.gd")
const DataStoreScript := preload("res://scripts/core/data_store.gd")

var failures := 0


func _initialize() -> void:
	_test_hex_grid()
	_test_new_game()
	_test_opening_recruit()
	_test_repeat_recruit()
	_test_recruit_cost_and_refresh()
	_test_army_cap()
	_test_event_options()
	_test_nest_expansion()
	_test_seed_planting()
	_test_seed_harvest()
	_test_turn_flow()
	_test_group_rules()
	_test_determinism()
	_test_weather()
	_test_battle()
	_test_enemy_formation()
	_test_target_rules()
	_test_final_ruling()
	_test_battle_defeat()
	_test_encounter_options()
	_test_keyword_hooks()
	_test_sell()
	_test_unit_pool()
	_test_tier_units()
	_test_data_store()
	_test_full_run()

	if failures == 0:
		print("SMOKE OK")
		quit(0)
	else:
		printerr("SMOKE FAILED: %d" % failures)
		quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)


func _boot(seed: int):
	var game = GameStateScript.new(seed)
	while game.phase == GameStateScript.Phase.RECRUIT:
		game.skip_recruit()
	game.army.clear()
	for unit_id in ["houwang", "hushi", "cangcao"]:
		_add_unit(game, unit_id)
	game.phase = GameStateScript.Phase.ACTION
	return game


func _add_unit(game, unit_id: String) -> Dictionary:
	var entry: Dictionary = game._new_army_unit(unit_id)
	game.army.append(entry)
	return entry


func _deploy_uid(game, unit_id: String) -> int:
	for entry in game.deploy_units:
		if str(entry["unit_id"]) == unit_id:
			return int(entry["uid"])
	return -1


func _first_ready_player(game) -> Dictionary:
	for row in ["front", "back"]:
		for unit in game.battle["player"][row]:
			# 0 攻击单位（驿传蚁）有行动点也不能普攻，自动战斗跳过它。
			if bool(unit["alive"]) and int(unit["ap"]) > 0 and float(unit["atk"]) > 0.0:
				return unit
	return {}


func _first_alive_enemy(game) -> Array:
	var row := "front" if game.enemies_front_alive() else "back"
	var list: Array = game.battle["enemies"][row]
	for index in list.size():
		if bool(list[index]["alive"]):
			return [row, index]
	return []


func _test_hex_grid() -> void:
	check(HexGridScript.ring_cells(0).size() == 1, "ring 0 = 1 cell")
	check(HexGridScript.ring_cells(1).size() == 6, "ring 1 = 6 cells")
	check(HexGridScript.ring_cells(2).size() == 12, "ring 2 = 12 cells")
	check(HexGridScript.ring_cells(3).size() == 18, "ring 3 = 18 cells")

	var axial := Vector2i(2, -1)
	var round_trip := HexGridScript.pixel_to_axial(HexGridScript.axial_to_pixel(2, -1, 40.0), 40.0)
	check(round_trip == axial, "pixel <-> axial round trip")
	check(HexGridScript.direction_of(-1, 0) == 3, "river side direction = 3")


func _test_new_game() -> void:
	var game = GameStateScript.new(1234)
	check(game.turn == 1, "turn starts at 1")
	check(game.phase == GameStateScript.Phase.RECRUIT, "turn 1 opens with a recruit window")
	check(game.free_recruits_left == 2, "2 free recruits in the opening window")
	check(game.recruit_candidates.size() == 3, "opening offers 3 candidates")
	check(game.season_name() == "春", "starts in spring")
	check(int(game.resources["food"]) == 15, "starts with 15 food")
	check(game.resources.keys() == ["food"], "food is the only resource")
	check(is_equal_approx(game.health, 100.0), "start health 100")
	check(game.groups.size() == 3, "3 event groups generated")
	check(game.cells.size() == 7, "L1 start = 7 cells")
	check(game.nest_blocked_cells() == 1, "river blocks 1 cell at L1")
	check(game.nest_level == 1, "starts at nest level 1")
	check(game.seeds.is_empty(), "no seeds in inventory at start")
	check(game.planted.size() == 1, "starting seed is already planted")
	check(game.army.is_empty(), "no fixed starting army")
	check(game.season_weathers.size() == 6, "season weather generated up front")
	check(game.weather == game.season_weathers[0], "turn 1 uses first season weather")
	check(game.logs.size() > 0, "log has entries")


func _test_opening_recruit() -> void:
	var game = GameStateScript.new(124)
	check(game.free_recruits_left == 2, "opening has 2 free recruits")
	var first: String = game.recruit_candidates[0]
	game.resources["food"] = 0
	check(game.recruit(first), "free recruit ignores cost")
	check(int(game.resources["food"]) == 0, "free recruit costs nothing")
	check(game.free_recruits_left == 1, "one free recruit left")
	check(game.phase == GameStateScript.Phase.RECRUIT, "recruit window stays open")

	var second: String = game.recruit_candidates[0]
	check(game.recruit(second), "second free recruit works")
	check(game.army.size() == 2, "opening produces 2 units")
	check(game.free_recruits_left == 0, "free recruits spent")
	check(game.recruit_candidates.is_empty(), "no affordable candidates with 0 food")

	check(game.end_recruit(), "ending the window advances the turn")
	check(game.phase == GameStateScript.Phase.GROUP_SELECT, "recruit window -> event group select")

	var skipped = GameStateScript.new(125)
	skipped.skip_recruit()
	check(skipped.army.is_empty(), "opening can be skipped")
	check(skipped.phase == GameStateScript.Phase.GROUP_SELECT, "skip goes to GROUP_SELECT")


func _test_repeat_recruit() -> void:
	var game = GameStateScript.new(126)
	game.resources["food"] = 8
	game.free_recruits_left = 0
	game._open_recruit_window("turn")
	var count := 0
	while game.recruit_candidates.size() > 0 and int(game.resources["food"]) >= 4:
		var before: int = game.army.size()
		check(game.recruit(game.recruit_candidates[0]), "paid recruit #%d succeeds" % (count + 1))
		check(game.army.size() == before + 1, "army grows in the same window")
		check(game.phase == GameStateScript.Phase.RECRUIT, "window remains open after recruiting")
		count += 1
		if count > 10:
			break
	check(count == 2, "8 food buys 2 units at 4 food each")
	check(int(game.resources["food"]) == 0, "food is spent per recruit")
	check(game.recruit_candidates.is_empty(), "candidates re-roll to affordable options")
	game.end_recruit()
	check(game.phase == GameStateScript.Phase.GROUP_SELECT, "ending repeat recruit advances")


func _test_recruit_cost_and_refresh() -> void:
	var game = GameStateScript.new(127)
	game.free_recruits_left = 0
	game.resources["food"] = 10
	check(game.refresh_recruit(), "refresh works")
	check(int(game.resources["food"]) == 9, "refresh costs 1 food")
	check(game.refresh_recruit(), "refresh is repeatable in the same window")
	check(int(game.resources["food"]) == 8, "second refresh also costs 1 food")

	var duzhi_game = GameStateScript.new(128)
	_add_unit(duzhi_game, "duzhi")
	duzhi_game.resources["food"] = 20
	duzhi_game._spend_food(6)
	check(duzhi_game.free_refreshes == 1, "度支蚁 grants 1 free refresh per 6 food spent")
	duzhi_game.free_recruits_left = 0
	var food_before := int(duzhi_game.resources["food"])
	check(duzhi_game.refresh_recruit(), "free refresh works")
	check(duzhi_game.free_refreshes == 0, "free refresh is consumed")
	check(int(duzhi_game.resources["food"]) == food_before, "free refresh costs no food")


func _test_army_cap() -> void:
	var game = GameStateScript.new(129)
	while game.army.size() < int(game.balance["army"]["max_size"]):
		_add_unit(game, "houwang")
	var candidate: String = game.recruit_candidates[0]
	check(not game.can_recruit(candidate), "cannot recruit at max army size")
	check(not game.recruit(candidate), "recruit rejected at max army size")
	check(game.phase == GameStateScript.Phase.RECRUIT, "still can end the window")
	game.end_recruit()
	check(game.phase == GameStateScript.Phase.GROUP_SELECT, "full army still advances")


func _test_event_options() -> void:
	var game = _boot(130)
	_force_single_event(game, {
		"id": "test_option", "category": "random", "pressure": false,
		"title": "选项测试", "text": "",
		"options": [
			{"label": "+2 食物", "effects": {"food": 2}},
			{"label": "战斗", "battle": "sand"},
			{"label": "进入招募", "recruit": true},
		],
	})
	var food_before := int(game.resources["food"])
	check(game.choose_event_option(0), "event option resolves")
	check(int(game.resources["food"]) == food_before + 2, "option applies effects")
	check(game.event_index == 1, "option advances the event")

	_force_single_event(game, {
		"id": "test_option_battle", "category": "enemy_weak", "pressure": true,
		"title": "选项战斗", "text": "",
		"options": [{"label": "迎战", "battle": "sand"}],
	})
	check(game.choose_event_option(0), "battle option opens deployment")
	check(game.phase == GameStateScript.Phase.DEPLOY, "battle option enters DEPLOY")
	check(str(game.pending_event.get("battle", "")) == "sand", "battle option carries encounter id")

	var lethal = _boot(131)
	lethal.health = 3.0
	_force_single_event(lethal, {
		"id": "test_lethal", "category": "random", "pressure": false,
		"title": "致命选项", "text": "",
		"options": [{"label": "硬闯", "effects": {"health": -5}}],
	})
	check(lethal.choose_event_option(0), "lethal option resolves")
	check(lethal.phase == GameStateScript.Phase.GAME_OVER, "health 0 during an option ends the run")


func _test_nest_expansion() -> void:
	var poor = _boot(7)
	poor.resources["food"] = 5
	check(not poor.choose_action("expand"), "expansion rejected with 5 food (needs 12)")
	check(poor.phase == GameStateScript.Phase.ACTION, "failed expansion stays in ACTION")

	var game = _boot(7)
	game.resources["food"] = 30
	check(game.choose_action("expand"), "expansion succeeds with 30 food")
	check(game.nest_level == 2, "nest reaches level 2")
	check(game.cells.size() == 19, "L2 = 1 + 6 + 12 cells")
	check(game.nest_blocked_cells() == 2, "river blocks 2 cells at L2")
	check(int(game.resources["food"]) == 18, "L1 -> L2 costs 12 food")
	check(game.phase == GameStateScript.Phase.RECRUIT, "action ends the turn into next recruit window")
	check(game.fertile_count() == 6, "L2 has 6 fertile cells")


func _test_seed_planting() -> void:
	var game = _boot(8)
	check(game.free_fertile_cells().size() == 2, "2 free fertile cells after starting seed")
	game.seeds.append("grain_basic")
	check(game.plant_seed("grain_basic"), "planting a seed succeeds")
	check(game.planted.size() == 2, "planted seeds = 2")
	check(game.seeds.is_empty(), "seed removed from inventory")
	check(game.free_fertile_cells().size() == 1, "1 free fertile cell left")

	game.seeds.append("grain_rich")
	check(game.plant_seed("grain_rich"), "second planting succeeds")
	game.seeds.append("resin")
	check(not game.plant_seed("resin"), "no free fertile cell rejects planting")
	check(game.seeds.has("resin"), "rejected seed stays in inventory")


func _test_seed_harvest() -> void:
	var game = _boot(9)
	game.weather = "cloudy"
	var food_before := int(game.resources["food"])
	game._tick_planted()
	game._tick_planted()
	check(int(game.resources["food"]) == food_before, "no harvest before period 3")
	game._tick_planted()
	check(int(game.resources["food"]) == food_before + 3, "basic seed harvests 3 food at event 3 (spring +1)")
	check(int(game.planted[0]["counter"]) == 0, "counter resets after harvest")

	game._tick_planted()
	game._tick_planted()
	game._tick_planted()
	check(int(game.resources["food"]) == food_before + 6, "second harvest at event 6")

	game.weather = "clear"
	game._tick_planted()
	game._tick_planted()
	game._tick_planted()
	check(int(game.resources["food"]) == food_before + 10, "clear weather adds +1 production")


func _test_turn_flow() -> void:
	var game = _boot(99)
	game.health = 50.0
	check(game.choose_action("heal"), "heal succeeds (food 15 >= 4)")
	check(int(game.resources["food"]) == 11, "heal costs 4 food")
	check(game.health > 50.0, "heal raises health")
	check(game.phase == GameStateScript.Phase.RECRUIT, "action -> next turn recruit window")
	check(game.turn == 2, "turn advances after the action")

	game.end_recruit()
	check(game.phase == GameStateScript.Phase.GROUP_SELECT, "ending recruit -> group select")
	check(game.choose_group(0), "group 0 selectable")
	check(game.phase == GameStateScript.Phase.EVENT, "enters EVENT phase")
	check(game.event_index == 0, "event index starts at 0")

	_play_until_turn_end(game)

	check(game.phase == GameStateScript.Phase.ACTION, "4 events end in ACTION")
	check(game.turn == 2, "still the same turn until an action is chosen")
	check(int(game.resources["food"]) >= 0, "resources never negative")
	check(game.health > 0.0, "nest still alive")


func _test_group_rules() -> void:
	for game_index in 20:
		var game = _boot(2000 + game_index)
		var templates := {}
		var crisis := 0
		var relic := 0
		for group in game.groups:
			var events: Array = group["events"]
			check(events.size() == 4, "group has 4 events")
			var category_counts := {}
			var enemy_count := 0
			var pressure := 0
			for event in events:
				var category := str(event["category"])
				category_counts[category] = int(category_counts.get(category, 0)) + 1
				if category in ["enemy_weak", "enemy_strong"]:
					enemy_count += 1
				if bool(event["pressure"]):
					pressure += 1
			check(enemy_count >= 1, "group has at least 1 enemy event")
			check(pressure >= 1, "group has at least 1 pressure event")
			for category in category_counts.keys():
				check(int(category_counts[category]) <= 2, "no category appears 3 times")
			templates[str(group.get("template", ""))] = true
			if str(group.get("template", "")) == "crisis":
				crisis += 1
			if bool(group.get("slots", []).has("relic")):
				relic += 1
		check(game.groups.size() == 3, "3 groups per turn")
		check(templates.size() == game.groups.size(), "templates are distinct within a turn")
		check(crisis <= 1, "at most 1 crisis group per turn")
		check(relic <= 1, "at most 1 relic group per turn")


func _test_determinism() -> void:
	var a = _boot(4242)
	var b = _boot(4242)
	check(a.weather == b.weather, "same seed produces the same weather")
	check(a.season_weathers == b.season_weathers, "same seed produces the same season weather")
	var same := true
	for group_index in a.groups.size():
		for event_index in a.groups[group_index]["events"].size():
			if a.groups[group_index]["events"][event_index]["id"] != b.groups[group_index]["events"][event_index]["id"]:
				same = false
	check(same, "same seed produces the same event groups")


func _test_weather() -> void:
	var game = _boot(2026)
	check(game.weather in ["clear", "rain", "cloudy"], "weather is one of the 3 types")
	check(game.weather_name() in ["晴", "雨", "多云"], "weather has a display name")
	check("天气" in "\n".join(game.logs), "turn log mentions the weather")
	check(game.season_weathers.size() == 6, "6 weather states per season")
	check(game.forecast_weather(0) == game.weather, "forecast offset 0 = current weather")
	check(game.forecast_weather(1) != "", "forecast shows next turn")
	check("天气 " in game.weather_forecast_text(), "forecast text is built")

	var battle_game = _boot(2026)
	battle_game.weather = "rain"
	_force_single_event(battle_game, {
		"id": "weather_battle", "category": "enemy_weak", "pressure": true,
		"title": "雨天敌袭", "text": "", "battle": "sand", "effects": {},
	})
	battle_game.choose_encounter("fight")
	check(battle_game.phase == GameStateScript.Phase.DEPLOY, "rain battle enters DEPLOY")
	var food_before := int(battle_game.resources["food"])
	check(battle_game.start_battle(), "rain battle starts")
	check(int(battle_game.resources["food"]) == food_before, "starting a battle costs no food")

	var adventure_game = _boot(11)
	adventure_game.season = 1
	adventure_game.weather = "rain"
	adventure_game.resources["food"] = 50
	var health_before: float = adventure_game.health
	check(adventure_game.choose_action("adventure"), "adventure works in rain")
	check(
		int(adventure_game.resources["food"]) >= 49 and int(adventure_game.resources["food"]) <= 52,
		"rain adds 1 food cost to adventure"
	)
	check(is_equal_approx(health_before - adventure_game.health, 3.0), "rain adds 1 health loss to adventure")

	var sunny_game = _boot(12)
	sunny_game.season = 1
	sunny_game.weather = "clear"
	sunny_game.resources["food"] = 50
	sunny_game.choose_action("adventure")
	check(
		int(sunny_game.resources["food"]) >= 50 and int(sunny_game.resources["food"]) <= 54,
		"clear weather adventure stays in the base range"
	)


func _test_battle() -> void:
	var game = _boot(555)
	_force_single_event(game, {
		"id": "test_battle", "category": "enemy", "pressure": true,
		"title": "测试战斗", "text": "", "battle": "sand", "effects": {"food": 3},
	})
	var food_before := int(game.resources["food"])
	game.weather = "clear"
	check(game.choose_encounter("fight"), "encounter fight opens deployment")
	check(game.phase == GameStateScript.Phase.DEPLOY, "enters DEPLOY phase")
	check(game.deploy_units.size() == 3, "all 3 units listed for deployment")
	check(game.deployed_count() == 3, "all units deployed by default")
	check(game.can_start_battle(), "can start with any food")

	var hushi_uid := _deploy_uid(game, "hushi")
	check(game.deploy_set(hushi_uid, ""), "can bench a unit")
	check(game.deployed_count() == 2, "benching removes one unit")
	check(game.deploy_set(hushi_uid, "back"), "can redeploy the unit")
	check(game.deployed_count() == 3, "redeploy restores 3")

	check(game.start_battle(), "battle starts")
	check(game.phase == GameStateScript.Phase.BATTLE, "enters BATTLE phase")
	check(int(game.resources["food"]) == food_before, "starting a battle costs no food")
	check(game.battle["enemies"]["front"].size() == 2, "sand encounter front = 2")
	check(game.battle["enemies"]["back"].size() == 0, "sand encounter back = 0")

	check(not game.player_attack("front", 0), "attack needs a selected unit")
	check(game.selected_player().is_empty(), "nothing selected before clicking own unit")

	for row in ["front", "back"]:
		for enemy in game.battle["enemies"][row]:
			enemy["hp"] = 0.5
			enemy["shield"] = 0.0

	var front_uid := int(game.battle["player"]["front"][0]["uid"])
	check(game.select_player(front_uid), "selecting own unit works")
	check(game.selected_player()["uid"] == front_uid, "selected unit is tracked")
	check(game.player_attack("front", 0), "selected unit attacks chosen target")
	check(int(game.battle["player"]["front"][0]["ap"]) == 0, "attack consumes the unit's 1 AP")
	check(game.selected_player().is_empty(), "selection clears at 0 AP")

	var second_uid := int(game.battle["player"]["front"][1]["uid"])
	check(game.select_player(second_uid), "second front unit selectable")
	check(game.player_attack("front", 1), "second attack resolves")

	check(game.phase != GameStateScript.Phase.BATTLE, "battle ends after all enemies die")
	check(game.battle.is_empty(), "battle state cleared")
	check(game.army.size() == 3, "units return after battle (army unchanged)")
	var loot := int(game.resources["food"]) - food_before
	check(loot >= 2 and loot <= 4, "victory gives 2-4 food loot (got %d)" % loot)
	check(game.health > 0.0, "victory does not damage the nest")


func _test_enemy_formation() -> void:
	var game = _boot(4242)
	game.enemies_data = {
		"enemies": [
			{"id": "tf", "name": "前", "hp": 5.0, "attack": 1.0, "ap": 1, "row": "front"},
			{"id": "tb", "name": "后", "hp": 5.0, "attack": 1.0, "ap": 1, "row": "back"},
		],
		"encounters": {"test": {"name": "阵列测试", "units": [
			{"enemy_id": "tf", "count": 6},
			{"enemy_id": "tb", "count": 4},
		]}},
	}
	_force_single_event(game, {
		"id": "test_formation", "category": "enemy_weak", "pressure": true,
		"title": "阵列测试", "text": "", "battle": "test", "effects": {},
	})
	check(game.choose_encounter("fight"), "formation encounter enters deploy")
	check(game.start_battle(), "formation battle starts")
	check(game.battle["enemies"]["front"].size() == 4, "enemy front row caps at 4")
	check(game.battle["enemies"]["back"].size() == 3, "enemy back row caps at 3")
	check(str(game.battle["enemies"]["front"][0]["row"]) == "front", "front enemies stay front")
	check(str(game.battle["enemies"]["back"][0]["row"]) == "back", "back enemies stay back")


func _test_target_rules() -> void:
	var game = _boot(557)
	_force_single_event(game, {
		"id": "test_targets", "category": "enemy", "pressure": true,
		"title": "前后排测试", "text": "", "battle": "bird", "effects": {"food": 5},
	})
	game.choose_encounter("fight")
	game.start_battle()
	check(game.phase == GameStateScript.Phase.BATTLE, "bird battle starts")
	check(game.battle["enemies"]["front"].size() == 1, "bird encounter front = 1 (盾甲)")
	check(game.battle["enemies"]["back"].size() == 1, "bird encounter back = 1 (掠食雀)")
	check(game.enemies_front_alive(), "enemy front is alive")

	var uid := int(game.battle["player"]["front"][0]["uid"])
	check(game.select_player(uid), "select a front unit")
	var ap_before := int(game.selected_player()["ap"])
	check(not game.player_attack("back", 0), "cannot attack back row while front alive")
	check(int(game.selected_player()["ap"]) == ap_before, "rejected attack does not consume AP")
	check(game.player_attack("front", 0), "can attack front row")
	check(int(game.battle["player"]["front"][0]["ap"]) == 0, "attack consumes 1 AP")


func _test_final_ruling() -> void:
	var game = _boot(558)
	_force_single_event(game, {
		"id": "test_ruling", "category": "enemy", "pressure": true,
		"title": "僵局", "text": "", "battle": "bird", "effects": {"food": 5},
	})
	game.choose_encounter("fight")
	game.start_battle()
	var food_after_supply := int(game.resources["food"])
	for row in ["front", "back"]:
		for unit in game.battle["player"][row]:
			unit["atk"] = 0.0
			unit["hp"] = 999.0
			unit["max_hp"] = 999.0
		for enemy in game.battle["enemies"][row]:
			enemy["atk"] = 0.0
			enemy["hp"] = 999.0
			enemy["max_hp"] = 999.0

	for i in 6:
		game.end_player_phase()

	check(game.phase != GameStateScript.Phase.BATTLE, "6-round stalemate triggers final ruling")
	check(game.phase == GameStateScript.Phase.EVENT, "ruling advances the event")
	var ruling_loot := int(game.resources["food"]) - food_after_supply
	check(ruling_loot >= 2 and ruling_loot <= 3, "ruling gives halved loot (got %d)" % ruling_loot)


func _test_battle_defeat() -> void:
	var game = _boot(556)
	game.army.clear()
	_add_unit(game, "houwang")
	_force_single_event(game, {
		"id": "test_defeat", "category": "enemy", "pressure": true,
		"title": "必败战斗", "text": "", "battle": "bird", "effects": {"food": 5},
	})
	var health_before: float = game.health
	game.choose_encounter("fight")
	game.start_battle()
	_auto_battle(game)

	check(game.phase != GameStateScript.Phase.BATTLE, "defeat ends the battle")
	check(is_equal_approx(game.health, maxf(0.0, health_before - 5.0)), "defeat costs 5 nest health")
	check(game.army.size() == 1, "soldier returns after defeat")


func _test_encounter_options() -> void:
	var game = _boot(560)
	_force_single_event(game, {
		"id": "test_talk", "category": "enemy_weak", "pressure": true,
		"title": "谈判测试", "text": "", "battle": "sand", "effects": {"food": 3},
	})
	check(not game.ready_up(), "battle event requires an encounter choice")
	var food_before := int(game.resources["food"])
	check(game.choose_encounter("talk"), "talk resolves the encounter")
	check(int(game.resources["food"]) == food_before - 2, "talk costs 2 food (placeholder)")
	check(game.event_index == 1, "talk advances the event")
	check(game.battle.is_empty(), "talk never starts a battle")

	var avoid_game = _boot(561)
	_force_single_event(avoid_game, {
		"id": "test_avoid", "category": "enemy_weak", "pressure": true,
		"title": "回避测试", "text": "", "battle": "sand", "effects": {"food": 3},
	})
	var food_avoid := int(avoid_game.resources["food"])
	check(avoid_game.choose_encounter("avoid"), "avoid resolves the encounter")
	check(int(avoid_game.resources["food"]) == food_avoid, "avoid is free")
	check(avoid_game.event_index == 1, "avoid advances the event")


func _test_keyword_hooks() -> void:
	var game = _boot(900)
	game.army.clear()
	var cangcao := _add_unit(game, "cangcao")
	var uid := int(cangcao["uid"])
	game.resources["food"] = 10
	check(game.can_train_cangcao(uid), "仓曹蚁 can train outside battle")
	check(game.train_cangcao(uid, "hp"), "积粮 HP training succeeds")
	check(is_equal_approx(float(cangcao["max_hp"]), 10.0), "积粮 grants +3 max HP permanently")
	check(int(game.resources["food"]) == 8, "积粮 costs 2 food")
	check(not game.can_train_cangcao(uid), "积粮 is once per turn per unit")
	check(not game.train_cangcao(uid, "attack"), "second training in a turn is rejected")

	var duzhi = _boot(901)
	duzhi.army.clear()
	_add_unit(duzhi, "duzhi")
	duzhi.resources["food"] = 20
	duzhi._spend_food(6)
	duzhi._spend_food(6)
	check(duzhi.free_refreshes == 2, "度支蚁 accumulates free refreshes every 6 food")

	var unit := {
		"name": "烽燧蚁", "hp": 7.0, "max_hp": 7.0, "atk": 1.5,
		"signature": {"id": "yuyong", "params": {"max_hp_gain": 0.5}},
	}
	game._after_take_damage(unit, 1.0)
	check(is_equal_approx(float(unit["max_hp"]), 7.5), "余勇 grants +0.5 max HP after taking damage")
	check(is_equal_approx(float(unit["hp"]), 7.5), "余勇 immediately heals the new max HP")


func _test_sell() -> void:
	var game = _boot(902)
	var uid := int(game.army[0]["uid"])
	var food_before := int(game.resources["food"])
	check(game.sell_price(uid) == 2, "basic unit sells for 2 food")
	check(game.sell_unit(uid), "selling a unit succeeds outside battle")
	check(int(game.resources["food"]) == food_before + 2, "selling adds food")
	check(game.army.size() == 2, "sold unit leaves the army")
	check(not game.sell_unit(uid), "selling an unknown uid is rejected")

	var zhiku := _add_unit(game, "zhiku")
	zhiku["battles"] = 3
	check(game.sell_price(int(zhiku["uid"])) == 5, "质库蚁 sells for 2 + 1 per battle")
	check(game.sell_unit(int(zhiku["uid"])), "质库蚁 can be sold")

	var battle_game = _boot(903)
	_force_single_event(battle_game, {
		"id": "sell_battle", "category": "enemy", "pressure": true,
		"title": "卖出限制", "text": "", "battle": "sand", "effects": {},
	})
	battle_game.choose_encounter("fight")
	battle_game.start_battle()
	check(not battle_game.can_sell(int(battle_game.battle["player"]["front"][0]["uid"])),
		"cannot sell during battle")


func _test_unit_pool() -> void:
	var game = _boot(781)
	var units: Array = game.units_data.get("units", [])
	check(units.size() == 31, "data has 31 units (14 + 11 + 6)")
	var ids := {}
	var tier_counts := {1: 0, 2: 0, 3: 0}
	for unit in units:
		var id := str(unit.get("id", ""))
		var tier := int(unit.get("tier", 0))
		check(not id.is_empty(), "unit has an id")
		ids[id] = true
		check(tier >= 1 and tier <= 3, "tier is 1-3: " + id)
		tier_counts[tier] = int(tier_counts.get(tier, 0)) + 1
		check(str(unit.get("source", "")) in ["shared", "species"], "unit has a source: " + id)
		check(int(unit.get("ap", 0)) == 1, "base AP is 1: " + id)
		check(float(unit.get("hp", 0.0)) > 0.0, "unit has HP: " + id)
		check(float(unit.get("attack", 0.0)) >= 0.0, "unit has non-negative attack: " + id)
		check(int(unit.get("cost_food", 0)) > 0, "unit has a food cost: " + id)
		check(unit.has("signature"), "unit has a signature: " + id)
		check(not unit.has("def"), "no defense stat: " + id)
	check(int(tier_counts[1]) == 14, "tier 1 = 14 units")
	check(int(tier_counts[2]) == 11, "tier 2 = 11 units")
	check(int(tier_counts[3]) == 6, "tier 3 = 6 units")
	for expected in [
		"houwang", "suihuo", "hushi", "fengsui", "yunnou", "duzhi",
		"cangcao", "kuiliang", "sinong", "zhiku", "leisi", "puqi", "kenong", "dilei",
		"yichuan", "jiuwu", "jiangzuo", "yinliang", "jingqi", "qintian",
		"jixiang", "dugeng", "gouxu", "rangrang", "zhangsai", "sishi", "baowu",
		"taicang", "shicang", "fengren", "zhenlin",
	]:
		check(ids.has(expected), "expected unit present: " + expected)


func _test_tier_units() -> void:
	# 招募池按巢穴等级解锁 + 升阶保底。
	var pool = _boot(910)
	pool.army.clear()
	pool.resources["food"] = 100
	pool.nest_level = 1
	pool.phase = GameStateScript.Phase.RECRUIT
	pool.recruit_candidates = pool._roll_recruits()
	for unit_id in pool.recruit_candidates:
		check(int(pool.unit_info(unit_id).get("tier", 0)) == 1, "L1 only rolls tier 1")
	pool.nest_level = 2
	pool.tier_pity = 2
	pool.recruit_candidates = pool._roll_recruits()
	var has_tier2 := false
	for unit_id in pool.recruit_candidates:
		if int(pool.unit_info(unit_id).get("tier", 0)) == 2:
			has_tier2 = true
	check(has_tier2, "升阶保底 puts a tier-2 unit in the first L2 recruit")
	check(pool.tier_pity == 0, "升阶保底 is consumed")

	# 驿传蚁：0 攻击、不可攻击；催阵每轮给最高攻友军 +1 AP。
	var game = _boot(911)
	game.army.clear()
	var yichuan := _add_unit(game, "yichuan")
	var houwang := _add_unit(game, "houwang")
	_force_single_event(game, {
		"id": "tier_battle", "category": "enemy", "pressure": true,
		"title": "二阶测试", "text": "", "battle": "sand", "effects": {},
	})
	check(game.choose_encounter("fight"), "tier battle enters deploy")
	check(game.start_battle(), "tier battle starts")
	var yichuan_unit: Dictionary = game._player_by_uid(int(yichuan["uid"]))
	var houwang_unit: Dictionary = game._player_by_uid(int(houwang["uid"]))
	check(is_equal_approx(float(yichuan_unit["atk"]), 0.0), "驿传蚁 has 0 attack")
	check(int(houwang_unit["ap"]) == 2, "催阵 grants +1 AP to the highest-attack ally")
	check(game.select_player(int(yichuan["uid"])), "驿传蚁 can still be selected")
	check(not game.player_attack("front", 0), "驿传蚁 cannot attack")

	# 沟洫蚁：战斗开始全队 2.0 护盾。
	var gouxu = _boot(912)
	gouxu.army.clear()
	_add_unit(gouxu, "gouxu")
	_add_unit(gouxu, "houwang")
	_force_single_event(gouxu, {
		"id": "tier_gouxu", "category": "enemy", "pressure": true,
		"title": "沟洫", "text": "", "battle": "sand", "effects": {},
	})
	gouxu.choose_encounter("fight")
	gouxu.start_battle()
	for unit in gouxu._all_players():
		check(float(unit["shield"]) >= 2.0, "沟洫蚁 gives the team 2.0 shield")

	# 计相蚁：每累计 6 食物永久 +3 生命 / +3 攻击。
	var jixiang_game = _boot(913)
	jixiang_game.army.clear()
	var jixiang := _add_unit(jixiang_game, "jixiang")
	jixiang_game.resources["food"] = 30
	jixiang_game._spend_food(6)
	check(is_equal_approx(float(jixiang["max_hp"]), 11.0), "计相蚁 +3 HP per 6 food")
	check(is_equal_approx(float(jixiang["attack"]), 4.5), "计相蚁 +3 attack per 6 food")
	jixiang_game._spend_food(6)
	check(is_equal_approx(float(jixiang["max_hp"]), 14.0), "计相蚁 stacks every 6 food")

	# 因粮蚁：攻击命中 +1 食物。
	var yinliang_game = _boot(914)
	yinliang_game.army.clear()
	var yinliang := _add_unit(yinliang_game, "yinliang")
	_force_single_event(yinliang_game, {
		"id": "tier_yinliang", "category": "enemy", "pressure": true,
		"title": "因粮", "text": "", "battle": "sand", "effects": {},
	})
	yinliang_game.choose_encounter("fight")
	yinliang_game.start_battle()
	for row in ["front", "back"]:
		for enemy in yinliang_game.battle["enemies"][row]:
			enemy["shield"] = 0.0
			enemy["hp"] = 50.0
	var food_before := int(yinliang_game.resources["food"])
	yinliang_game.select_player(int(yinliang["uid"]))
	check(yinliang_game.player_attack("front", 0), "因粮蚁 attacks")
	check(int(yinliang_game.resources["food"]) == food_before + 1, "因粮蚁 gains 1 food per hit")

	# 堡坞蚁：嘲讽；受击后每轮 1 次 +1 护盾。
	var baowu_game = _boot(915)
	baowu_game.army.clear()
	var baowu := _add_unit(baowu_game, "baowu")
	_add_unit(baowu_game, "hushi")
	_force_single_event(baowu_game, {
		"id": "tier_baowu", "category": "enemy", "pressure": true,
		"title": "堡坞", "text": "", "battle": "sand", "effects": {},
	})
	baowu_game.choose_encounter("fight")
	baowu_game.start_battle()
	var baowu_unit: Dictionary = baowu_game._player_by_uid(int(baowu["uid"]))
	check(baowu_game._pick_player_target()["uid"] == int(baowu["uid"]), "堡坞蚁 taunts enemy single-target attacks")
	var shield_before := float(baowu_unit["shield"])
	baowu_game._after_take_damage(baowu_unit, 1.0)
	check(is_equal_approx(float(baowu_unit["shield"]), shield_before + 1.0), "堡坞蚁 gains 1 shield after being hit")
	baowu_game._after_take_damage(baowu_unit, 1.0)
	check(is_equal_approx(float(baowu_unit["shield"]), shield_before + 1.0), "堡坞蚁 shield is once per round")

	# 障塞蚁：替指定后排友军挡下下一次单体攻击。
	var zhangsai_game = _boot(916)
	zhangsai_game.army.clear()
	var zhangsai := _add_unit(zhangsai_game, "zhangsai")
	var hushi := _add_unit(zhangsai_game, "hushi")
	_force_single_event(zhangsai_game, {
		"id": "tier_zhangsai", "category": "enemy", "pressure": true,
		"title": "障塞", "text": "", "battle": "sand", "effects": {},
	})
	zhangsai_game.choose_encounter("fight")
	zhangsai_game.start_battle()
	var zhangsai_unit: Dictionary = zhangsai_game._player_by_uid(int(zhangsai["uid"]))
	var hushi_unit: Dictionary = zhangsai_game._player_by_uid(int(hushi["uid"]))
	check(int(zhangsai_unit.get("guard_uid", 0)) == int(hushi["uid"]), "障塞蚁 guards the back-row ally")
	var hushi_hp := float(hushi_unit["hp"])
	zhangsai_game._attack(zhangsai_game.battle["enemies"]["front"][0], hushi_unit)
	check(is_equal_approx(float(hushi_unit["hp"]), hushi_hp), "障塞蚁 takes the hit instead of the back row")

	# 死士蚁 + 钦天蚁：不甘结算两次（全队 +2.0 攻击）。
	var death_game = _boot(917)
	death_game.army.clear()
	var sishi := _add_unit(death_game, "sishi")
	_add_unit(death_game, "qintian")
	var houwang2 := _add_unit(death_game, "houwang")
	_force_single_event(death_game, {
		"id": "tier_death", "category": "enemy", "pressure": true,
		"title": "不甘", "text": "", "battle": "sand", "effects": {},
	})
	death_game.choose_encounter("fight")
	death_game.start_battle()
	var houwang_unit2: Dictionary = death_game._player_by_uid(int(houwang2["uid"]))
	var atk_before := float(houwang_unit2["atk"])
	death_game._on_death(death_game._player_by_uid(int(sishi["uid"])), {})
	check(is_equal_approx(float(houwang_unit2["atk"]), atk_before + 2.0), "钦天蚁 doubles 不甘: team +2.0 attack")

	# 太仓蚁：交 5 食物，全队 +2 攻击 / 2 护盾。
	var taicang_game = _boot(918)
	taicang_game.army.clear()
	_add_unit(taicang_game, "taicang")
	var houwang3 := _add_unit(taicang_game, "houwang")
	taicang_game.resources["food"] = 20
	_force_single_event(taicang_game, {
		"id": "tier_taicang", "category": "enemy", "pressure": true,
		"title": "太仓", "text": "", "battle": "sand", "effects": {},
	})
	taicang_game.choose_encounter("fight")
	taicang_game.start_battle()
	var hw3: Dictionary = taicang_game._player_by_uid(int(houwang3["uid"]))
	check(int(taicang_game.resources["food"]) == 15, "太仓蚁 pays 5 food at battle start")
	check(is_equal_approx(float(hw3["atk"]), 4.0), "太仓蚁 gives +2.0 attack")
	check(float(hw3["shield"]) >= 2.0, "太仓蚁 gives 2.0 shield")

	# 丰稔蚁：击杀永久 +0.5 攻击；首杀额外 +1.0【战时】。
	var fengren_game = _boot(919)
	fengren_game.army.clear()
	var fengren := _add_unit(fengren_game, "fengren")
	_force_single_event(fengren_game, {
		"id": "tier_fengren", "category": "enemy", "pressure": true,
		"title": "丰稔", "text": "", "battle": "sand", "effects": {},
	})
	fengren_game.choose_encounter("fight")
	fengren_game.start_battle()
	for row in ["front", "back"]:
		for enemy in fengren_game.battle["enemies"][row]:
			enemy["shield"] = 0.0
			enemy["hp"] = 0.1
	fengren_game.select_player(int(fengren["uid"]))
	fengren_game.player_attack("front", 0)
	check(is_equal_approx(float(fengren["attack"]), 3.5), "丰稔蚁 kill grants +0.5 permanent attack")


func _test_data_store() -> void:
	var store = DataStoreScript.instance()
	check(store.version > 0, "DataStore loads initial data")
	for name in ["balance", "events", "event_templates", "units", "enemies", "seeds"]:
		check(not store.get_data(name).is_empty(), "DataStore has " + name)

	var before: int = store.version
	var good := JSON.stringify({"schema_version": 1, "max_health": 101, "start": {"health": 100, "food": 15}})
	check(store.apply_text("balance", good), "valid hot-reload text applies")
	check(int(store.get_data("balance").get("max_health", 0)) == 101, "hot-reload value visible")
	check(store.version == before + 1, "version increments once")

	var applied: int = store.version
	check(not store.apply_text("balance", "{ broken json"), "invalid JSON rejected")
	check(store.version == applied, "version unchanged on invalid data")
	check(int(store.get_data("balance").get("max_health", 0)) == 101, "old data kept on invalid JSON")
	check(not store.last_error.is_empty(), "invalid data records an error")
	check(not store.apply_text("balance", '{"schema_version":1}'), "missing required keys rejected")
	check(store.apply_text("balance", good), "good text re-applies after a bad save")
	check(store.apply_text("balance", good) == false, "same text is not re-applied")

	store.reload_all()
	check(int(store.get_data("balance").get("max_health", 0)) == 100, "real data restored")
	check(store.last_error.is_empty(), "error clears after a good load")

	var live = GameStateScript.new(555)
	var live_good := JSON.stringify({"schema_version": 1, "max_health": 130, "start": {"health": 100, "food": 15}})
	store.apply_text("balance", live_good)
	live.reload_data()
	check(live.max_health() == 130.0, "GameState picks up hot-reloaded balance")
	store.reload_all()
	live.reload_data()
	check(live.max_health() == 100.0, "GameState restores real balance")


func _test_full_run() -> void:
	var game = _boot(31337)
	var steps := 0
	while steps < 6000:
		steps += 1
		match game.phase:
			GameStateScript.Phase.ACTION:
				if int(game.resources["food"]) >= 4 and game.health < 50.0:
					game.choose_action("heal")
				elif game.nest_level < 3 and int(game.resources["food"]) >= (12 if game.nest_level == 1 else 18):
					game.choose_action("expand")
				elif not game.seeds.is_empty() and not game.free_fertile_cells().is_empty():
					game.plant_seed(game.seeds[0])
				else:
					game.choose_action("adventure")
			GameStateScript.Phase.GROUP_SELECT:
				game.choose_group(0)
			GameStateScript.Phase.EVENT:
				_choose_event(game)
			GameStateScript.Phase.DEPLOY:
				if game.can_start_battle():
					game.start_battle()
				else:
					game.avoid_battle()
			GameStateScript.Phase.BATTLE:
				_auto_battle(game)
			GameStateScript.Phase.RECRUIT:
				if game.army.size() < 3 and not game.recruit_candidates.is_empty():
					var picked := ""
					for unit_id in game.recruit_candidates:
						if game.can_recruit(unit_id):
							picked = unit_id
							break
					if picked != "":
						game.recruit(picked)
					else:
						game.end_recruit()
				else:
					game.end_recruit()
			_:
				break

	check(steps < 6000, "full run terminates (no infinite loop)")
	check(
		game.phase == GameStateScript.Phase.WON or game.phase == GameStateScript.Phase.GAME_OVER,
		"full run ends in WON or GAME_OVER"
	)
	check(int(game.resources["food"]) >= 0, "food never negative after full run")
	check(game.health >= 0.0, "health never negative")
	if game.phase == GameStateScript.Phase.WON:
		check(game.turn == GameStateScript.TOTAL_TURNS + 1, "win happens after 6 spring turns")


# ---------------------------------------------------------------------------
# 测试辅助
# ---------------------------------------------------------------------------

func _force_single_event(game, event: Dictionary) -> void:
	game.active_group = {
		"events": [event],
		"categories": [str(event.get("category", "self"))],
		"pressure": 1 if bool(event.get("pressure", false)) else 0,
	}
	game.event_index = 0
	game.phase = GameStateScript.Phase.EVENT


func _choose_event(game) -> void:
	var event: Dictionary = game.current_event()
	var options: Array = event.get("options", [])
	if not options.is_empty():
		var pick := 0
		for i in options.size():
			if options[i].has("battle") and int(game.resources["food"]) >= 3:
				pick = i
				break
		game.choose_event_option(pick)
	elif event.has("battle"):
		game.choose_encounter("fight")
	else:
		game.ready_up()


func _play_until_turn_end(game) -> void:
	var guard := 0
	while guard < 500:
		guard += 1
		if game.phase == GameStateScript.Phase.EVENT:
			_choose_event(game)
		elif game.phase == GameStateScript.Phase.DEPLOY:
			if game.can_start_battle():
				game.start_battle()
			else:
				game.avoid_battle()
		elif game.phase == GameStateScript.Phase.BATTLE:
			_auto_battle(game)
		elif game.phase == GameStateScript.Phase.RECRUIT:
			game.end_recruit()
		else:
			break


func _auto_battle(game) -> void:
	var guard := 0
	while game.phase == GameStateScript.Phase.BATTLE and guard < 300:
		guard += 1
		var attacker := {}
		if game.player_has_ap():
			attacker = _first_ready_player(game)
		if attacker.is_empty():
			# 只剩 0 攻击单位可动时，直接结束玩家阶段，避免空转。
			game.end_player_phase()
			continue
		var target := _first_alive_enemy(game)
		if target.is_empty():
			break
		game.select_player(int(attacker["uid"]))
		if not game.player_attack(str(target[0]), int(target[1])):
			game.end_player_phase()
