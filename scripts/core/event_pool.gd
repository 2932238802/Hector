class_name EventPool
extends RefCounted
## 事件组生成：每回合 N 个事件组，每组 4 个事件、类别不重复、至少 1 个压力事件。
## 规则来源：doc/02-systems/events.md 第 4 节。

const GROUP_SIZE := 4

const CATEGORY_NAMES := {
	"enemy": "敌对昆虫",
	"self": "蚁群自我",
	"creature": "随机生物",
	"explore": "冒险探索",
	"weather": "天气",
}


static func build_groups(rng: RandomNumberGenerator, data: Dictionary, count: int, season: int) -> Array:
	var groups: Array = []
	for i in count:
		groups.append(build_one(rng, data, season))
	return groups


static func build_one(rng: RandomNumberGenerator, data: Dictionary, season: int) -> Dictionary:
	var by_category := {}
	for event in data.get("events", []):
		var category: String = str(event.get("category", ""))
		var bucket: Array = by_category.get(category, [])
		bucket.append(event)
		by_category[category] = bucket

	var categories: Array = data.get("categories", []).duplicate()
	shuffle(rng, categories)
	categories = categories.slice(0, mini(GROUP_SIZE, categories.size()))

	var picked: Array = []
	for category in categories:
		picked.append(_pick_for_season(rng, by_category.get(category, []), season))

	if not _has_pressure(picked):
		_force_pressure(rng, picked, by_category)

	var pressure_count := 0
	for event in picked:
		if bool(event.get("pressure", false)):
			pressure_count += 1

	return {
		"categories": categories,
		"events": picked,
		"pressure": pressure_count,
	}


static func group_title(index: int) -> String:
	return "第 %s 组" % char(65 + index)


static func describe(group: Dictionary) -> String:
	var names: Array[String] = []
	for category in group.get("categories", []):
		names.append(str(CATEGORY_NAMES.get(category, category)))
	return " · ".join(names)


static func _pick_for_season(rng: RandomNumberGenerator, pool: Array, season: int) -> Dictionary:
	var candidates: Array = []
	for event in pool:
		var event_season := int(event.get("season", -1))
		if event_season == -1 or event_season == season:
			candidates.append(event)
	if candidates.is_empty():
		candidates = pool
	if candidates.is_empty():
		return {}
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func _has_pressure(picked: Array) -> bool:
	for event in picked:
		if bool(event.get("pressure", false)):
			return true
	return false


static func _force_pressure(rng: RandomNumberGenerator, picked: Array, by_category: Dictionary) -> void:
	for i in picked.size():
		var category: String = str(picked[i].get("category", ""))
		var pool: Array = by_category.get(category, [])
		var options: Array = []
		for event in pool:
			if bool(event.get("pressure", false)):
				options.append(event)
		if not options.is_empty():
			picked[i] = options[rng.randi_range(0, options.size() - 1)]
			return


static func shuffle(rng: RandomNumberGenerator, items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp
