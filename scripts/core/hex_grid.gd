class_name HexGrid
extends RefCounted
## 尖顶六边形（pointy-top）轴向坐标工具。
## 坐标为轴向 (q, r)，屏幕坐标系 y 向下。

const SQRT3 := 1.7320508075688772


static func axial_to_pixel(q: int, r: int, hex_size: float) -> Vector2:
	return Vector2(
		SQRT3 * hex_size * (float(q) + float(r) * 0.5),
		1.5 * hex_size * float(r)
	)


static func pixel_to_axial(pos: Vector2, hex_size: float) -> Vector2i:
	var qf := (SQRT3 / 3.0 * pos.x - pos.y / 3.0) / hex_size
	var rf := (2.0 / 3.0 * pos.y) / hex_size
	var sf := -qf - rf
	var q := roundi(qf)
	var r := roundi(rf)
	var s := roundi(sf)
	var dq := absf(float(q) - qf)
	var dr := absf(float(r) - rf)
	var ds := absf(float(s) - sf)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	return Vector2i(q, r)


## 返回半径 radius 的一整圈格子（radius = 0 时返回中心格）。
static func ring_cells(radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if radius <= 0:
		out.append(Vector2i.ZERO)
		return out
	for q in range(-radius, radius + 1):
		for r in range(-radius, radius + 1):
			var s := -q - r
			var dist := maxi(maxi(absi(q), absi(r)), absi(s))
			if dist == radius:
				out.append(Vector2i(q, r))
	return out


## 把格子归到 6 个方向扇区之一（0..5），用于「被河岸阻断一整边」。
static func direction_of(q: int, r: int) -> int:
	var p := axial_to_pixel(q, r, 1.0)
	var deg := rad_to_deg(atan2(p.y, p.x))
	return int(floor(fposmod(deg + 30.0, 360.0) / 60.0)) % 6


static func corners(center: Vector2, hex_size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * float(i) - 90.0)
		pts.append(center + Vector2(cos(a), sin(a)) * hex_size)
	return pts


static func closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := points.duplicate()
	if not out.is_empty():
		out.append(out[0])
	return out
