class_name NestView
extends Control
## 巢穴六边形视图：中心格 + 逐圈外扩，被位置阻断的格子画成灰格。
## 纯视觉层，不修改游戏状态。

const HexGridScript := preload("res://scripts/core/hex_grid.gd")

const INK := Color("1a1a1a")
const MUTED := Color("6f6a60")
const PAPER_CELL := Color(1, 1, 1, 0.88)
const FERTILE_FILL := Color(0.87, 0.84, 0.74, 0.95)
const BLOCKED_FILL := Color(0.1, 0.1, 0.1, 0.07)
const BLOCKED_LINE := Color(0.45, 0.42, 0.37)

var _cells: Array = []
var _level := 1
var _hover := Vector2i(999, 999)
var _hover_blocked := false
var _hover_fertile := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
	mouse_exited.connect(_on_mouse_exited)


func set_data(cells: Array, level: int) -> void:
	_cells = cells
	_level = level
	_hover = Vector2i(999, 999)
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	if font == null:
		return

	draw_string(
		font, Vector2(6, 22), "巢穴 Lv.%d" % _level,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK
	)
	draw_string(
		font, Vector2(6, 42), "六边形外圈 = 可扩展位；小圆点 = 肥沃格（可播种）",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MUTED
	)

	var hex := _hex_size()
	var center := Vector2(size.x * 0.5, size.y * 0.5 + 12.0)

	for cell in _cells:
		var q := int(cell["q"])
		var r := int(cell["r"])
		var blocked := bool(cell["blocked"])
		var cell_center := center + HexGridScript.axial_to_pixel(q, r, hex)
		var points := HexGridScript.corners(cell_center, hex * 0.93)
		var outline := HexGridScript.closed(points)

		if blocked:
			draw_colored_polygon(points, BLOCKED_FILL)
			draw_polyline(outline, BLOCKED_LINE, 1.0, true)
			var a := cell_center + Vector2(-hex * 0.45, -hex * 0.45)
			var b := cell_center + Vector2(hex * 0.45, hex * 0.45)
			draw_line(a, b, BLOCKED_LINE, 1.0, true)
		else:
			var fertile := bool(cell.get("fertile", false))
			draw_colored_polygon(points, FERTILE_FILL if fertile else PAPER_CELL)
			draw_polyline(outline, INK, 1.3, true)
			if fertile:
				draw_circle(cell_center, hex * 0.16, INK)

		if Vector2i(q, r) == _hover:
			draw_polyline(outline, INK, 3.0, true)

	if _hover.x != 999:
		var status := "被阻断" if _hover_blocked else _hover_status()
		draw_string(
			font, Vector2(6, size.y - 8), "格 (%d, %d) · %s" % [_hover.x, _hover.y, status],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MUTED
		)
	else:
		draw_string(
			font, Vector2(6, size.y - 8), "灰格 + 斜线 = 被位置阻断，不可用",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MUTED
		)


func _hover_status() -> String:
	return "肥沃格（可播种）" if _hover_fertile else "可用"


func _hex_size() -> float:
	var max_ring := maxi(_level - 1, 0)
	var width_units := HexGridScript.SQRT3 * (2.0 * max_ring + 1.0)
	var height_units := 3.0 * max_ring + 2.0
	var available := Vector2(size.x - 16.0, size.y - 60.0)
	if available.x <= 0.0 or available.y <= 0.0:
		return 12.0
	return maxf(12.0, minf(available.x / width_units, available.y / height_units) * 0.98)


func _cell_at(pos: Vector2):
	var hex := _hex_size()
	var center := Vector2(size.x * 0.5, size.y * 0.5 + 12.0)
	var best = null
	var best_distance := hex * 0.95
	for cell in _cells:
		var cell_center := center + HexGridScript.axial_to_pixel(int(cell["q"]), int(cell["r"]), hex)
		var distance := cell_center.distance_to(pos)
		if distance < best_distance:
			best_distance = distance
			best = cell
	return best


func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		var cell = _cell_at(motion.position)
		var next := Vector2i(999, 999)
		var blocked := false
		var fertile := false
		if cell != null:
			next = Vector2i(int(cell["q"]), int(cell["r"]))
			blocked = bool(cell["blocked"])
			fertile = bool(cell.get("fertile", false))
		if next != _hover or blocked != _hover_blocked or fertile != _hover_fertile:
			_hover = next
			_hover_blocked = blocked
			_hover_fertile = fertile
			queue_redraw()


func _on_mouse_exited() -> void:
	if _hover.x != 999:
		_hover = Vector2i(999, 999)
		_hover_blocked = false
		_hover_fertile = false
		queue_redraw()
