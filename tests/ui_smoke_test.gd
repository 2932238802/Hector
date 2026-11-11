extends SceneTree
## UI 冒烟测试：真实主场景里的按钮接线。
## 覆盖：可反复招募窗口、结束招募、点选我方单位后再点敌方目标。
## 用法：godot --headless --path <project> --script res://tests/ui_smoke_test.gd

const GameStateScript := preload("res://scripts/core/game_state.gd")

var failures := 0
var scene: Node


func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var game = scene.game
	check(game != null, "main scene exposes GameState")
	check(game.phase == GameStateScript.Phase.RECRUIT, "game starts in the recruit window")

	await _check_repeat_recruit_ui(game)
	await _check_manual_target_ui(game)

	if failures == 0:
		print("UI SMOKE OK")
		quit(0)
	else:
		printerr("UI SMOKE FAILED: %d" % failures)
		quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)


func _find_button(node: Node, needle: String) -> Button:
	if node is Button:
		var button := node as Button
		if needle in button.text:
			return button
	for child in node.get_children():
		var found := _find_button(child, needle)
		if found != null:
			return found
	return null


func _check_repeat_recruit_ui(game) -> void:
	var first := _find_button(scene, "— 免费")
	check(first != null, "recruit candidate button is visible")
	if first == null:
		return
	first.pressed.emit()
	await process_frame
	check(game.army.size() == 1, "clicking a candidate recruits one unit")
	check(game.phase == GameStateScript.Phase.RECRUIT, "recruit window stays open after one recruit")

	var second := _find_button(scene, "— 免费")
	check(second != null, "second free candidate is visible")
	if second != null:
		second.pressed.emit()
		await process_frame
	check(game.army.size() == 2, "recruit window allows repeated recruiting")
	check(game.phase == GameStateScript.Phase.RECRUIT, "still in recruit window after the second recruit")

	var end_button := _find_button(scene, "结束招募")
	check(end_button != null, "end-recruit button is visible")
	if end_button != null:
		end_button.pressed.emit()
		await process_frame
	check(game.phase == GameStateScript.Phase.GROUP_SELECT, "ending recruit opens group select")


func _check_manual_target_ui(game) -> void:
	# 直接注入一场固定战斗，避免依赖随机事件组。
	game.army.clear()
	game.army.append(game._new_army_unit("houwang"))
	game.army.append(game._new_army_unit("hushi"))
	game.active_group = {
		"events": [{
			"id": "ui_battle", "category": "enemy", "pressure": true,
			"title": "UI 战", "text": "", "battle": "sand", "effects": {},
		}],
		"categories": ["enemy"], "pressure": 1,
	}
	game.event_index = 0
	game.phase = GameStateScript.Phase.EVENT
	game.choose_encounter("fight")
	await process_frame

	var start_button := _find_button(scene, "开战")
	check(start_button != null, "deploy panel has a start button")
	if start_button == null:
		return
	start_button.pressed.emit()
	await process_frame
	check(game.phase == GameStateScript.Phase.BATTLE, "start button enters battle")

	var enemy_button := _find_button(scene, "盾甲")
	check(enemy_button != null, "enemy target button is visible")
	check(enemy_button != null and enemy_button.disabled, "enemy target is disabled before selecting a unit")

	var attacker_button := _find_button(scene, "候望蚁")
	check(attacker_button != null, "own unit button is visible")
	if attacker_button == null:
		return
	attacker_button.pressed.emit()
	await process_frame
	check(game.selected_uid > 0, "clicking own unit selects it")

	enemy_button = _find_button(scene, "盾甲")
	check(enemy_button != null and not enemy_button.disabled, "enemy target enables after selection")
	if enemy_button == null or enemy_button.disabled:
		return

	var target: Dictionary = game.battle["enemies"]["front"][0]
	var hp_before := float(target["hp"])
	enemy_button.pressed.emit()
	await process_frame
	check(float(target["hp"]) <= hp_before, "clicking an enemy resolves the attack")
	check(game.selected_uid == -1, "selection clears after spending AP")
	enemy_button = _find_button(scene, "盾甲")
	check(enemy_button != null and enemy_button.disabled, "enemy target disables again with no selection")
