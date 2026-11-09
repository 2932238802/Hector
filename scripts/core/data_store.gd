class_name DataStore
extends RefCounted
## 唯一的数据入口：加载 data/*.json、校验 schema_version、发现文件变化后热更。
## - 运行期只从这里取数据，其他系统不得各自读文件。
## - 检测按文件内容比较（不是大小 / mtime），1 秒内可发现保存。
## - 非法 JSON：保留上一份有效数据，记录 last_error，不崩溃。

signal data_reloaded(version: int)

const FILES := {
	"balance": "res://data/balance.json",
	"events": "res://data/events.json",
	"event_templates": "res://data/event_templates.json",
	"units": "res://data/units.json",
	"enemies": "res://data/enemies.json",
	"seeds": "res://data/seeds.json",
}

const POLL_INTERVAL := 0.25
const REQUIRED_SCHEMA := 1
const REQUIRED_KEYS := {
	"balance": ["max_health", "start"],
	"events": ["events"],
	"event_templates": ["templates"],
	"units": ["units"],
	"enemies": ["tiers"],
	"seeds": ["seeds"],
}

static var _instance = null

var data: Dictionary = {}
var version := 0
var last_error := ""
var last_error_file := ""

var _texts: Dictionary = {}
var _timer := 0.0


static func instance():
	if _instance == null:
		_instance = load("res://scripts/core/data_store.gd").new()
	return _instance


func _init() -> void:
	reload_all()


## 查询类接口（供 UI / 测试）。
func get_data(name: String) -> Dictionary:
	return data.get(name, {})


func has_data(name: String) -> bool:
	return not get_data(name).is_empty()


## 读全部文件；返回本次成功更新的文件数。
func reload_all() -> int:
	var changed := 0
	for name in FILES:
		if _reload_file(str(name), str(FILES[name])):
			changed += 1
	if changed > 0:
		data_reloaded.emit(version)
	return changed


## 每帧由 UI 调用；内部按 POLL_INTERVAL 节流。
func poll(delta: float) -> void:
	_timer += delta
	if _timer < POLL_INTERVAL:
		return
	_timer = 0.0
	var changed := 0
	for name in FILES:
		if _reload_file(str(name), str(FILES[name])):
			changed += 1
	if changed > 0:
		if OS.is_debug_build():
			print("DataStore: 热更生效 v%d（%d 个文件）。" % [version, changed])
		data_reloaded.emit(version)


## 供测试 / 工具：直接应用一段文本，走同一套校验与保留逻辑。
func apply_text(name: String, text: String) -> bool:
	return _apply(name, text)


func _reload_file(name: String, path: String) -> bool:
	if not FileAccess.file_exists(path):
		_set_error(name, "文件不存在：%s" % path)
		return false
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		_set_error(name, "读取为空：%s（错误码 %d）" % [path, FileAccess.get_open_error()])
		return false
	return _apply(name, text)


func _apply(name: String, text: String) -> bool:
	if str(_texts.get(name, "")) == text:
		return false
	var parsed: Dictionary = _parse(text)
	if parsed.is_empty():
		# 记下坏文本，避免每次轮询重复报错；旧数据保留。
		_texts[name] = text
		return false
	for key in REQUIRED_KEYS.get(name, []):
		if not parsed.has(key):
			_set_error(name, "缺少必填字段「%s」" % key)
			_texts[name] = text
			return false
	data[name] = parsed
	_texts[name] = text
	version += 1
	last_error = ""
	last_error_file = ""
	return true


func _parse(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		_set_error("-", "JSON 解析失败（第 %d 行）：%s" % [json.get_error_line(), json.get_error_message()])
		return {}
	var parsed = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		_set_error("-", "顶层不是 JSON 对象")
		return {}
	if int((parsed as Dictionary).get("schema_version", 0)) != REQUIRED_SCHEMA:
		_set_error("-", "缺少或非法 schema_version（应为 %d）" % REQUIRED_SCHEMA)
		return {}
	return parsed


func _set_error(name: String, message: String) -> void:
	last_error = message
	last_error_file = name
	printerr("数据加载失败 [%s]：%s" % [name, message])
