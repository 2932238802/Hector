class_name EventPool
extends RefCounted
## 事件组生成 v2：6 套模板、每组 4 个事件、至少 1 个敌对势力、本轮模板不重复。
## 规则来源：doc/02-systems/events.md 第 4–5 节（Q-082 / Q-056）。

const GROUP_SIZE := 4

const CATEGORY_NAMES := {
	"enemy_weak": "普敌",
	"enemy_strong": "强敌",
	"explore": "探索",
	"random": "随机",
	"recruit": "招募",
	"relic": "遗迹",
}

const ENEMY_CATEGORIES := ["enemy_weak", "enemy_strong"]


static func build_groups(
	rng: RandomNumberGenerator,
	data: Dictionary,
	templates_data: Dictionary,
	count: int,
	season: int
) -> Array:
	var by_category := _bucket_events(data)
	var templates := _pick_templates(rng, templates_data, count, season)
	var groups: Array = []
	var used_event_ids := {}
	for template in templates:
		groups.append(_build_group(rng, template, by_category, season, used_event_ids))
	return groups


static func group_title(index: int) -> String:
	return "第 %s 组" % char(65 + index)


static func describe(group: Dictionary) -> String:
	var names: Array[String] = []
	for category in group.get("categories", []):
		names.append(str(CATEGORY_NAMES.get(category, category)))
	var template := str(group.get("name", "事件组"))
	return "%s：%s" % [template, " · ".join(names)]


static func shuffle(rng: RandomNumberGenerator, items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp


static func _bucket_events(data: Dictionary) -> Dictionary:
	var by_category := {}
	for event in data.get("events", []):
		var category := str(event.get("category", ""))
		if not by_category.has(category):
			by_category[category] = []
		by_category[category].append(event)
	return by_category


static func _pick_templates(
	rng: RandomNumberGenerator,
	templates_data: Dictionary,
	count: int,
	season: int
) -> Array:
	var templates: Array = templates_data.get("templates", [])
	var weights: Dictionary = templates_data.get("season_weights", {}).get(str(season), {})
	var picked: Array = []
	var used := {}
	var crisis_count := 0
	var relic_count := 0
	var guard := 0

	while picked.size() < count and guard < 200:
		guard += 1
		var pool: Array = []
		for template in templates:
			var id := str(template.get("id", ""))
			if used.has(id):
				continue
			if bool(template.get("crisis", false)) and crisis_count >= 1:
				continue
			if bool(template.get("relic", false)) and relic_count >= 1:
				continue
			pool.append(template)
		# 退化：先放宽遗迹上限，再放宽危机上限。
		if pool.is_empty():
			for template in templates:
				if used.has(str(template.get("id", ""))):
					continue
				if bool(template.get("crisis", false)) and crisis_count >= 2:
					continue
				pool.append(template)
		if pool.is_empty():
			break
		var template := _weighted_pick(rng, pool, weights)
		var tid := str(template.get("id", ""))
		used[tid] = true
		if bool(template.get("crisis", false)):
			crisis_count += 1
		if bool(template.get("relic", false)):
			relic_count += 1
		picked.append(template)
	return picked


static func _weighted_pick(rng: RandomNumberGenerator, pool: Array, weights: Dictionary) -> Dictionary:
	var total := 0
	for template in pool:
		total += int(weights.get(str(template.get("id", "")), 1))
	if total <= 0:
		return pool[rng.randi_range(0, pool.size() - 1)]
	var roll := rng.randi_range(1, total)
	var acc := 0
	for template in pool:
		acc += int(weights.get(str(template.get("id", "")), 1))
		if roll <= acc:
			return template
	return pool[pool.size() - 1]


static func _build_group(
	rng: RandomNumberGenerator,
	template: Dictionary,
	by_category: Dictionary,
	season: int,
	used_event_ids: Dictionary
) -> Dictionary:
	var categories: Array = []
	var events: Array = []
	for category in template.get("slots", []):
		var cid := str(category)
		categories.append(cid)
		var event := _pick_event(rng, by_category.get(cid, []), season, used_event_ids)
		if event.is_empty():
			event = _pick_event(rng, by_category.get("random", []), season, used_event_ids)
		events.append(event)

	# 硬规则：每组至少 1 个敌对势力。模板本身已保证，这里做兜底。
	if not _has_enemy(events):
		var fallback := _pick_event(rng, by_category.get("enemy_weak", []), season, used_event_ids)
		if not fallback.is_empty():
			events[0] = fallback
			categories[0] = "enemy_weak"

	var pressure := 0
	for event in events:
		if bool(event.get("pressure", false)):
			pressure += 1

	return {
		"template": str(template.get("id", "")),
		"name": str(template.get("name", "事件组")),
		"slots": template.get("slots", []),
		"categories": categories,
		"events": events,
		"pressure": pressure,
	}


static func _pick_event(
	rng: RandomNumberGenerator,
	pool: Array,
	season: int,
	used_event_ids: Dictionary
) -> Dictionary:
	var fresh: Array = []
	var seasonal: Array = []
	for event in pool:
		var event_season := int(event.get("season", -1))
		if event_season != -1 and event_season != season:
			continue
		seasonal.append(event)
		if not used_event_ids.has(str(event.get("id", ""))):
			fresh.append(event)
	var candidates: Array = fresh if not fresh.is_empty() else seasonal
	if candidates.is_empty():
		candidates = pool
	if candidates.is_empty():
		return {}
	var picked: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
	used_event_ids[str(picked.get("id", ""))] = true
	return picked


static func _has_enemy(events: Array) -> bool:
	for event in events:
		if ENEMY_CATEGORIES.has(str(event.get("category", ""))):
			return true
	return false
