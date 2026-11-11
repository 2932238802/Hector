extends Control
## 战果手牌：把 warfruits 画成炉石 / 月圆之夜式的手牌。
## 当前只做展示与选中说明——战果效果数值仍待 Q-074，接效果时在这里加使用入口。

signal card_selected(spoil_id: String, description: String)

const INK := Color("201d18")
const MUTED := Color("6f6a60")
const GOLD := Color("93641f")
const PAPER := Color("fffdf7")
const CARD_W := 94.0
const CARD_H := 128.0

const SPOILS := {
	"xunjie": {"name": "迅捷", "art": "迅", "desc": "战斗开始时获得的战果。效果与数值待定（Q-074）。"},
	"bugan": {"name": "不甘", "art": "不", "desc": "阵亡时获得的战果。效果与数值待定（Q-074）。"},
	"warspoil": {"name": "战果", "art": "战", "desc": "通用战果，可直接加属性或挂 buff；数值待定（Q-074）。"},
	"resin": {"name": "树脂", "art": "树", "desc": "树脂种产出的战果占位，效果待定（Q-074）。"},
	"venom": {"name": "毒液", "art": "毒", "desc": "毒液种产出的战果占位，效果待定（Q-074）。"},
}

var game = null
var _selected_id := ""


class CardArt extends Control:
	var ink := Color("3d5a3a")
	var glyph := "战"

	func _draw() -> void:
		var r := maxf(4.0, minf(size.x, size.y) * 0.44)
		var center := size * 0.5
		draw_colored_polygon(_star(center, r), Color(ink.r, ink.g, ink.b, 0.16))
		var font := get_theme_default_font()
		if font != null and glyph != "":
			var font_size := int(maxf(12.0, r * 1.02))
			draw_string(
				font, Vector2(0, center.y + font_size * 0.36), glyph,
				HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, ink
			)

	func _star(center: Vector2, r: float) -> PackedVector2Array:
		var points := PackedVector2Array()
		for i in 8:
			var angle := -PI * 0.5 + i * PI * 0.25
			var length := r if i % 2 == 0 else r * 0.30
			points.append(center + Vector2(cos(angle), sin(angle)) * length)
		return points


func bind(g) -> void:
	game = g


func refresh() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if game == null:
		return

	var ids: Array = []
	for known in SPOILS:
		if int(game.warfruits.get(known, 0)) > 0:
			ids.append(str(known))
	for raw in game.warfruits:
		var key := str(raw)
		if not ids.has(key) and int(game.warfruits[raw]) > 0:
			ids.append(key)

	if ids.is_empty():
		var empty := Label.new()
		empty.text = "手中暂无战果 · 战果型种子与兵种关键词会在这里生成手牌"
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", MUTED)
		empty.size = size
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(empty)
		return

	var spacing := CARD_W + 10.0
	if ids.size() > 1 and spacing * float(ids.size() - 1) + CARD_W > size.x:
		spacing = maxf(CARD_W * 0.62, (size.x - CARD_W) / float(ids.size() - 1))
	var total := CARD_W + spacing * float(ids.size() - 1)
	var start := (size.x - total) * 0.5
	for i in ids.size():
		var card := _build_card(ids[i])
		card.position = Vector2(start + spacing * float(i), 2)
		add_child(card)


func _build_card(spoil_id: String) -> PanelContainer:
	var info: Dictionary = SPOILS.get(spoil_id, {})
	var name := str(info.get("name", spoil_id))
	var art := str(info.get("art", name.substr(0, 1)))
	var desc := str(info.get("desc", "战果效果待定（Q-074）。"))
	var count := int(game.warfruits.get(spoil_id, 0))

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_W, CARD_H)
	card.size = Vector2(CARD_W, CARD_H)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = "%s ×%d\n%s" % [name, count, desc]

	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.border_color = GOLD if _selected_id == spoil_id else Color(0.16, 0.14, 0.11, 0.22)
	style.set_border_width_all(2 if _selected_id == spoil_id else 1)
	style.set_corner_radius_all(9)
	style.shadow_color = Color(0, 0, 0, 0.16)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 2)
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(header)
	var title := Label.new()
	title.text = name
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", GOLD)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(title)
	var badge := Label.new()
	badge.text = "×%d" % count
	badge.add_theme_font_size_override("font_size", 13)
	badge.add_theme_color_override("font_color", MUTED)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(badge)

	var art_view := CardArt.new()
	art_view.custom_minimum_size = Vector2(0, 56)
	art_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art_view.ink = GOLD
	art_view.glyph = art
	art_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(art_view)

	var footer := Label.new()
	footer.text = "战果 · 待实装"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 10)
	footer.add_theme_color_override("font_color", MUTED)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(footer)

	card.gui_input.connect(_on_card_input.bind(spoil_id, desc))
	card.mouse_entered.connect(_lift.bind(card, true))
	card.mouse_exited.connect(_lift.bind(card, false))
	return card


func _on_card_input(event: InputEvent, spoil_id: String, desc: String) -> void:
	var mouse := event as InputEventMouseButton
	if mouse == null or not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	_selected_id = "" if _selected_id == spoil_id else spoil_id
	card_selected.emit(spoil_id, desc)
	refresh()


func _lift(card: PanelContainer, up: bool) -> void:
	card.pivot_offset = card.size * 0.5
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(card, "scale", Vector2(1.05, 1.05) if up else Vector2.ONE, 0.12)
	if up:
		card.z_index = 5
	else:
		card.z_index = 0
