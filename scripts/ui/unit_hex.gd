class_name UnitHex
extends Control
## 兵种六边形棋子：底色按阶级 / 阵营，中央是名字前两字，底边是生命条。
## 图形母题取自 doc/reference/gi-wrapping-star.png（四角星），作为极淡的水印。
## 纯显示 + 点击信号，不修改游戏状态。

signal hex_pressed(hex: Control)

const INK := Color("201d18")
const MUTED := Color("6f6a60")
const ACCENT := Color("3d5a3a")
const ACCENT_SOFT := Color("e2e8da")
const GOLD := Color("93641f")
const GOLD_SOFT := Color("f2e6cc")
const DANGER := Color("a33a2a")
const DANGER_SOFT := Color("f1ded8")
const PAPER := Color("fffdf7")
const SHIELD := Color("3f6f8a")
const DEAD := Color("b9b3a8")

var unit: Dictionary = {}
var uid := 0
var tier := 1
var hostile := false
var selected := false
var dimmed := false
var blocked := false
var empty := false
var glyph := ""
var hp := 0.0
var max_hp := 0.0
var atk := 0.0
var ap := 0
var max_ap := 0
var shield := 0.0
var weaken := 0
var alive := true

var _hover := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(90, 96)
	resized.connect(queue_redraw)
	mouse_entered.connect(_on_hover_changed.bind(true))
	mouse_exited.connect(_on_hover_changed.bind(false))


func setup(p_unit: Dictionary) -> void:
	unit = p_unit
	uid = int(p_unit.get("uid", 0))
	tier = int(p_unit.get("tier", 1))
	hostile = bool(p_unit.get("hostile", false))
	selected = bool(p_unit.get("selected", false))
	dimmed = bool(p_unit.get("dimmed", false))
	blocked = bool(p_unit.get("blocked", false))
	alive = bool(p_unit.get("alive", true))
	glyph = str(p_unit.get("glyph", ""))
	hp = float(p_unit.get("hp", 0.0))
	max_hp = float(p_unit.get("max_hp", 0.0))
	atk = float(p_unit.get("atk", 0.0))
	ap = int(p_unit.get("ap", 0))
	max_ap = int(p_unit.get("max_ap", 0))
	shield = float(p_unit.get("shield", 0.0))
	weaken = int(p_unit.get("weaken", 0))
	empty = false
	tooltip_text = str(p_unit.get("tooltip", ""))
	queue_redraw()


func set_empty(hint := "") -> void:
	empty = true
	dimmed = true
	alive = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_text = hint
	queue_redraw()


func _on_hover_changed(inside: bool) -> void:
	_hover = inside
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if empty or dimmed or not alive:
		return
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		hex_pressed.emit(self)


func _draw() -> void:
	var font := get_theme_default_font()
	var r := _radius()
	var center := Vector2(size.x * 0.5, size.y * 0.5)
	var outline := _closed(_hex(center, r))

	# 落地阴影
	if not empty:
		draw_colored_polygon(_hex(center + Vector2(0, 3), r), Color(0, 0, 0, 0.08))

	var fill := _fill_color()
	if empty:
		fill.a = 0.16
	draw_colored_polygon(_hex(center, r), fill)

	var line := _line_color()
	if empty:
		line.a = 0.22
	elif dimmed:
		line.a = 0.45

	if not empty:
		# 四角星水印（参考图标）
		draw_colored_polygon(_star(center, r * 0.66, 0.30), _with_alpha(line, 0.10))
		# 名字字标
		if font != null and glyph != "":
			var font_size := int(r * 0.68)
			var glyph_color := line.darkened(0.18)
			if not alive:
				glyph_color = DEAD
			elif dimmed:
				glyph_color = glyph_color.lerp(DEAD, 0.45)
			draw_string(
				font, Vector2(0, center.y + font_size * 0.36), glyph,
				HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, glyph_color
			)
		_draw_hp_bar(center, r)
		_draw_ap(center, r)
		_draw_badges(center, r, font)

	# 边框：选中 / 悬停 / 阻挡
	var width := 2.0
	var border := line
	if blocked and not empty:
		border = MUTED
	if selected:
		border = ACCENT
		width = 3.5
		draw_colored_polygon(_hex(center, r + 5.0), _with_alpha(GOLD, 0.14))
		draw_polyline(_closed(_hex(center, r + 4.0)), _with_alpha(GOLD, 0.85), 2.5, true)
	elif _hover and not dimmed and not empty:
		width = 3.0
	draw_polyline(outline, border, width, true)

	if not alive and not empty:
		# 退场：斜杠
		draw_line(
			center + Vector2(-r * 0.55, -r * 0.55),
			center + Vector2(r * 0.55, r * 0.55),
			_with_alpha(INK, 0.35), 2.0, true
		)


func _radius() -> float:
	return maxf(8.0, minf(size.x / 1.78, size.y / 2.02))


func _fill_color() -> Color:
	if empty:
		return Color(1, 1, 1, 0.5)
	if not alive:
		return Color("ece8df")
	if hostile:
		return DANGER_SOFT.lerp(PAPER, 0.35)
	match tier:
		2:
			return GOLD_SOFT
		3:
			return DANGER_SOFT
	return ACCENT_SOFT


func _line_color() -> Color:
	if hostile:
		return DANGER
	match tier:
		2:
			return GOLD
		3:
			return DANGER
	return ACCENT


func _draw_hp_bar(center: Vector2, r: float) -> void:
	if max_hp <= 0.0:
		return
	var width := r * 1.12
	var height := clampf(r * 0.13, 2.0, 5.0)
	var top_left := Vector2(center.x - width * 0.5, center.y + r * 0.56)
	draw_rect(Rect2(top_left, Vector2(width, height)), Color(0, 0, 0, 0.10))
	var ratio := clampf(hp / max_hp, 0.0, 1.0)
	var color := ACCENT if ratio >= 0.6 else (GOLD if ratio >= 0.3 else DANGER)
	draw_rect(Rect2(top_left, Vector2(width * ratio, height)), color)


func _draw_ap(center: Vector2, r: float) -> void:
	if max_ap <= 0:
		return
	var pip := maxf(3.0, r * 0.09)
	var gap := pip * 2.8
	var total := gap * float(max_ap - 1)
	var start := center + Vector2(r * 0.52 - total, -r * 0.52)
	for i in max_ap:
		var p := start + Vector2(gap * i, 0)
		if i < ap:
			draw_circle(p, pip, ACCENT)
		else:
			draw_circle(p, pip, _with_alpha(INK, 0.20))


func _draw_badges(center: Vector2, r: float, font: Font) -> void:
	if font == null:
		return
	var small := int(maxf(9.0, r * 0.24))
	if shield > 0.0:
		var text := "盾%.1f" % shield
		draw_string(
			font, Vector2(0, center.y - r * 0.58), text,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, small, SHIELD
		)
	if weaken > 0:
		draw_string(
			font, Vector2(0, center.y + r * 0.40), "弱×%d" % weaken,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, small, DANGER
		)


func _hex(center: Vector2, r: float) -> PackedVector2Array:
	# 尖顶朝上：上下各一个顶点，左右为竖直边。
	var points := PackedVector2Array()
	for i in 6:
		var angle := deg_to_rad(60.0 * i - 90.0)
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	return points


func _star(center: Vector2, r: float, inner_ratio: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 8:
		var angle := -PI * 0.5 + i * PI * 0.25
		var length := r if i % 2 == 0 else r * inner_ratio
		points.append(center + Vector2(cos(angle), sin(angle)) * length)
	return points


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var closed := points.duplicate()
	if not closed.is_empty():
		closed.append(closed[0])
	return closed


func _with_alpha(color: Color, alpha: float) -> Color:
	var result := color
	result.a = alpha
	return result
