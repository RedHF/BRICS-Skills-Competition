extends RefCounted

# A code-native ink silhouette; no external artwork or sampled animation.
static func paint(canvas: CanvasItem, point: Vector2, scale: float, time: float) -> void:
	var sway := sin(time * 3) * 2
	var coat := Color("#719a90")
	var robe := PackedVector2Array([Vector2(-8,-5),Vector2(8,-5),Vector2(18+sway,27),Vector2(-18+sway,27)])
	for i in range(robe.size()): robe[i] = point + robe[i] * scale
	canvas.draw_colored_polygon(robe,coat)
	canvas.draw_polyline(robe,Color("#d8c291"),1.5,true)
	canvas.draw_circle(point+Vector2(0,-14)*scale,8*scale,Color("#d7c5a0"))
	canvas.draw_line(point+Vector2(-12,-21)*scale,point+Vector2(12,-21)*scale,Color("#172e30"),5*scale,true)
	canvas.draw_line(point+Vector2(-5,0)*scale,point+Vector2(8,18)*scale,Color("#234843"),3*scale,true)
	canvas.draw_line(point+Vector2(6,5)*scale,point+Vector2(23,-8)*scale,Color("#c8ac77"),3*scale,true)
	canvas.draw_line(point+Vector2(23,-8)*scale,point+Vector2(28,-16)*scale,Color("#101f24"),4*scale,true)
