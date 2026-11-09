extends SceneTree
## M2 冒烟测试：24 回合 / 食物单资源 / L2 开局 / 种子生产。
## 用法：godot --headless --path <project> --script res://tests/smoke_test.gd

const GameStateScript := preload("res://scripts/core/game_state.gd")
const HexGridScript := preload("res://scripts/core/hex_grid.gd")
const DataStoreScript := preload("res://scripts/core/data_store.gd")

var failures := 0


func _initialize() -> void:
	_test_hex_grid()
	_test_new_game()
	_test_opening_recruit()
	_test_event_options()
	_test_nest_expansion()
	_test_seed_planting()
	_test_seed_harvest()
	_test_turn_flow()
	_test_group_rules()
	_test_determinism()
	_test_weather()
	_test_battle()
	_test_target_rules()
	_test_final_ruling()
	_test_battle_defeat()
	_test_encounter_options()
	_test_recruit()
	_test_recruit_tiers()
	_test_unit_pool()
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
	game.army.assign(["ruishi", "chihou", "caiwei"])
	return game


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
	check(game.phase == GameStateScript.Phase.RECRUIT, "starts with 2 free recruits")
	check(game.free_recruits_left == 2, "2 free recruits queued")
	check(game.recruit_candidates.size() == 3, "opening offers 3 candidates")
	check(game.season_name() == "春", "starts in spring")
	check(int(game.resources["food"]) == 15, "starts with 15 food (no upkeep)")
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
	check(game.phase == GameStateScript.Phase.RECRUIT, "still in opening recruit")
	game.resources["food"] = 13
	game._open_free_recruit()
	check(game.recruit(game.recruit_candidates[0]), "second free recruit works")
	check(game.army.size() == 2, "opening produces 2 units")
	check(game.phase == GameStateScript.Phase.ACTION, "opening ends in ACTION")

	var skipped = GameStateScript.new(125)
	skipped.skip_recruit()
	skipped.skip_recruit()
	check(skipped.army.is_empty(), "both free recruits can be skipped")
	check(skipped.phase == GameStateScript.Phase.ACTION, "skipping both starts the turn")


func _test_event_options() -> void:
	var game = _boot(126)
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
	check(str(game.pending_event.get("battle", "")) == "sand", "battle option carries tier")

	var lethal = _boot(127)
	lethal.health = 3.0
	_force_single_event(lethal, {
		"id": "test_lethal", "category": "random", "pressure": false,
		"title": "致命选项", "text": "",
		"options": [{"label": "硬闯", "effects": {"health": -5}}],
	})
	check(lethal.choose_event_option(0), "lethal option resolves")
	check(lethal.phase == GameStateScript.Phase.GAME_OVER, "health 0 during an option ends the run")


func _test_nest_expansion() -> void:
	var game = _boot(7)
	check(not game.choose_action("expand"), "expansion rejected with 15 food (needs 20)")
	check(game.phase == GameStateScript.Phase.ACTION, "failed expansion stays in ACTION")

	game.resources["food"] = 40
	check(game.choose_action("expand"), "expansion succeeds with 40 food")
	check(game.nest_level == 2, "nest reaches level 2")
	check(game.cells.size() == 19, "L2 = 1 + 6 + 12 cells (blocked cells included)")
	check(game.nest_blocked_cells() == 2, "river blocks 2 cells at L2")
	check(int(game.resources["food"]) == 20, "expansion costs 20 food (L1 -> L2)")
	check(game.phase == GameStateScript.Phase.GROUP_SELECT, "expansion advances to GROUP_SELECT")
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
	check(int(game.resources["food"]) == 11, "heal costs 4 food (15 - 4)")
	check(game.health > 50.0, "heal raises health")
	check(game.phase == GameStateScript.Phase.GROUP_SELECT, "action advances to GROUP_SELECT")

	check(game.choose_group(0), "group 0 selectable")
	check(game.phase == GameStateScript.Phase.EVENT, "enters EVENT phase")
	check(game.event_index == 0, "event index starts at 0")

	_play_until_turn_end(game)

	check(game.turn == 2, "turn advances after 4 events")
	check(game.phase == GameStateScript.Phase.ACTION, "new turn starts in ACTION")
	check(game.event_index == 0, "event index reset")
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

	# 雨天：出战不扣食物（Q-052 补给已取消）
	var battle_game = _boot(2026)
	battle_game.weather = "rain"
	_force_single_event(battle_game, {
		"id": "weather_battle", "category": "enemy_weak", "pressure": true,
		"title": "雨天敌袭", "text": "", "battle": "sand", "effects": {},
	})
	battle_game.choose_encounter("fight")
	check(battle_game.phase == GameStateScript.Phase.DEPLOY, "rain battle enters DEPLOY")
	check(battle_game.deploy_supply() == 0, "battle supply removed")
	var food_before := int(battle_game.resources["food"])
	check(battle_game.start_battle(), "rain battle starts")
	check(int(battle_game.resources["food"]) == food_before, "starting a battle costs no food")

	# 雨天：探索食物损失 +1，完整度 -3（基础 -2 + 雨天 -1）
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

	# 晴天：冒险食物 +1（基础 2–4 -> 3–5）
	var sunny_game = _boot(12)
	sunny_game.season = 1
	sunny_game.weather = "clear"
	sunny_game.resources["food"] = 50
	sunny_game.choose_action("adventure")
	check(
		int(sunny_game.resources["food"]) >= 51 and int(sunny_game.resources["food"]) <= 54,
		"clear weather adds 1 adventure food"
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
	check(game.deploy_supply() == 0, "no battle supply")
	check(game.can_start_battle(), "can start with any food")

	check(game.deploy_set("caiwei", ""), "can bench a unit")
	check(game.deployed_count() == 2, "benching removes one unit")
	check(game.deploy_set("caiwei", "back"), "can redeploy the unit")
	check(game.deployed_count() == 3, "redeploy restores 3")
	check(game.start_battle(), "battle starts")
	check(game.phase == GameStateScript.Phase.BATTLE, "enters BATTLE phase")
	check(int(game.resources["food"]) == food_before, "starting a battle costs no food")
	check(game.battle["enemies"]["front"].size() == 2, "weak tier front = 2")
	check(game.battle["enemies"]["back"].size() == 0, "weak tier back = 0")

	_auto_battle(game)

	check(game.phase != GameStateScript.Phase.BATTLE, "battle ends")
	check(game.battle.is_empty(), "battle state cleared")
	check(game.army.size() == 3, "units return after battle (army unchanged)")
	var loot := int(game.resources["food"]) - food_before
	check(loot >= 2 and loot <= 4, "victory gives 2-4 food loot (got %d)" % loot)
	check(game.health > 0.0, "victory does not damage the nest")


func _test_target_rules() -> void:
	var game = _boot(557)
	_force_single_event(game, {
		"id": "test_targets", "category": "enemy", "pressure": true,
		"title": "前后排测试", "text": "", "battle": "bird", "effects": {"food": 5},
	})
	game.choose_encounter("fight")
	game.start_battle()
	check(game.phase == GameStateScript.Phase.BATTLE, "bird battle starts")
	check(game.battle["enemies"]["front"].size() == 1, "bird tier front = 1 (盾甲)")
	check(game.battle["enemies"]["back"].size() == 1, "bird tier back = 1 (掠食雀)")
	check(game.enemies_front_alive(), "enemy front is alive")
	check(not game.player_attack("back", 0), "cannot attack back row while front alive")
	check(game.player_has_ap(), "rejected attack does not consume AP")
	check(game.player_attack("front", 0), "can attack front row")
	check(int(game.battle["player"]["front"][0]["ap"]) == 0, "attack consumes the unit's 1 AP")


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
	game.army.append("caiwei")
	_force_single_event(game, {
		"id": "test_defeat", "category": "enemy", "pressure": true,
		"title": "必败战斗", "text": "", "battle": "bird", "effects": {"food": 5},
	})
	var health_before: float = game.health
	game.choose_encounter("fight")
	game.start_battle()
	_auto_battle(game)

	check(game.phase != GameStateScript.Phase.BATTLE, "defeat ends the battle")
	check(is_equal_approx(game.health, maxf(0.0, health_before - 10.0)), "defeat costs 10 nest health")
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


func _test_recruit() -> void:
	var game = _boot(777)
	_force_single_event(game, {
		"id": "test_recruit", "category": "self", "pressure": false,
		"title": "育婴室", "text": "", "recruit": true, "effects": {},
	})
	game.ready_up()
	check(game.phase == GameStateScript.Phase.RECRUIT, "recruit event enters RECRUIT phase")
	check(game.recruit_candidates.size() == 3, "3 recruit candidates")
	for unit_id in game.recruit_candidates:
		var data: Dictionary = game.unit_info(unit_id)
		check(int(data.get("tier", 1)) == 1, "L1 recruits are tier 1: " + unit_id)
		check(int(data.get("cost", {}).get("food", 99)) <= 15, "candidates are affordable: " + unit_id)

	var food_before := int(game.resources["food"])
	check(game.refresh_recruit(), "first refresh works")
	check(int(game.resources["food"]) == food_before - 3, "refresh costs 3 food")
	check(not game.refresh_recruit(), "second refresh rejected")
	check(game.recruit_candidates.size() == 3, "refresh keeps 3 candidates")

	var picked := ""
	for unit_id in game.recruit_candidates:
		if game.can_recruit(unit_id):
			picked = unit_id
			break
	if picked == "":
		game.skip_recruit()
		check(game.phase == GameStateScript.Phase.EVENT, "skip returns to EVENT")
		check(game.event_index == 1, "skip advances the event")
	else:
		var army_before: int = game.army.size()
		check(game.recruit(picked), "recruit succeeds: " + picked)
		check(game.army.size() == army_before + 1, "army grows by 1")
		check(game.phase == GameStateScript.Phase.EVENT, "recruit returns to EVENT")
		check(game.event_index == 1, "recruit advances the event")


func _test_recruit_tiers() -> void:
	# 升 L2 后的第一次招募必出二阶；升 L3 后必出三阶。
	var game = _boot(778)
	game.resources["food"] = 90
	game.phase = GameStateScript.Phase.ACTION
	check(game.choose_action("expand"), "expand to L2")
	check(game.nest_level == 2, "nest is L2")
	check(game.recruit_pity_tier == 2, "upgrade to L2 sets pity tier 2")
	_force_single_event(game, {
		"id": "test_recruit_l2", "category": "self", "pressure": false,
		"title": "育婴室", "text": "", "recruit": true, "effects": {},
	})
	game.ready_up()
	var has_tier2 := false
	for unit_id in game.recruit_candidates:
		if int(game.unit_info(unit_id).get("tier", 1)) == 2:
			has_tier2 = true
	check(has_tier2, "L2 pity guarantees a tier-2 candidate")
	check(game.recruit_pity_tier == 0, "pity is consumed after the roll")

	game.skip_recruit()
	game.phase = GameStateScript.Phase.ACTION
	check(game.choose_action("expand"), "expand to L3")
	check(game.nest_level == 3, "nest is L3")
	check(game.recruit_pity_tier == 3, "upgrade to L3 sets pity tier 3")
	_force_single_event(game, {
		"id": "test_recruit_l3", "category": "self", "pressure": false,
		"title": "育婴室", "text": "", "recruit": true, "effects": {},
	})
	game.ready_up()
	var has_tier3 := false
	for unit_id in game.recruit_candidates:
		if int(game.unit_info(unit_id).get("tier", 1)) == 3:
			has_tier3 = true
	check(has_tier3, "L3 pity guarantees a tier-3 candidate")

	# 食物不足时，只出付得起的候选。
	var poor = _boot(780)
	poor.resources["food"] = 5
	_force_single_event(poor, {
		"id": "test_recruit_poor", "category": "self", "pressure": false,
		"title": "育婴室", "text": "", "recruit": true, "effects": {},
	})
	poor.ready_up()
	for unit_id in poor.recruit_candidates:
		check(int(poor.unit_info(unit_id).get("cost", {}).get("food", 99)) <= 5,
			"only affordable candidates when food is low: " + unit_id)


func _test_unit_pool() -> void:
	var game = _boot(781)
	var counts := {1: 0, 2: 0, 3: 0}
	for unit in game.units_data.get("units", []):
		if not bool(unit.get("combat", false)):
			continue
		var tier := int(unit.get("tier", 1))
		counts[tier] += 1
		check(int(unit.get("ap", 0)) == 1, "base AP is 1: " + str(unit["id"]))
		check(not unit.has("def"), "no defense stat: " + str(unit["id"]))
	check(counts[1] == 12, "tier 1 has 12 units (8 shared + 4 exclusive)")
	check(counts[2] == 8, "tier 2 has 8 units (3 shared + 5 exclusive)")
	check(counts[3] == 4, "tier 3 has 4 units (1 shared + 3 exclusive)")
	check(game.unit_info("tunzu").get("name", "") == "囤卒", "exclusive unit is present")


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
	while steps < 4000:
		steps += 1
		match game.phase:
			GameStateScript.Phase.ACTION:
				if int(game.resources["food"]) >= 4 and game.health < 50.0:
					game.choose_action("heal")
				elif game.nest_level < 3 and int(game.resources["food"]) >= (20 if game.nest_level == 1 else 30):
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
				game.skip_recruit()
			_:
				break

	check(steps < 4000, "full run terminates (no infinite loop)")
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
			game.skip_recruit()
		else:
			break


func _auto_battle(game) -> void:
	var guard := 0
	while game.phase == GameStateScript.Phase.BATTLE and guard < 300:
		guard += 1
		if game.player_has_ap():
			var row := "front" if game.enemies_front_alive() else "back"
			var list: Array = game.battle["enemies"][row]
			var target := -1
			for index in list.size():
				if bool(list[index]["alive"]):
					target = index
					break
			if target >= 0:
				game.player_attack(row, target)
			else:
				break
		else:
			game.end_player_phase()
