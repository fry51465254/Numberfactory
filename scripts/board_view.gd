class_name BoardView
extends Node2D

const TILE = 40.0
const COLORS = {2: Color("16a59a"), 3: Color("e76863"), 5: Color("d5ad35")}
# UV anchors correct generated port offsets without baking game information into the PNG.
const TURN_SOURCE_X = [0.0, 618.0 / 1254.0, 754.0 / 1254.0, 1.0]
const TURN_SOURCE_Y = [0.0, 522.0 / 1254.0, 649.0 / 1254.0, 1.0]
const TURN_DEST = [-0.5, -0.08, 0.08, 0.5]
const TEXTURE_FILES = {"belt_turn": "belt_turn-v2", "splitter": "splitter-fourway"}
var sim: FactorySim
var textures: Dictionary = {}
var turn_mesh: ArrayMesh
var selected = Vector2i(-1000000000, -1000000000)
var hover = Vector2i(-1000000000, -1000000000)
var tool = "select"
var direction = 0
var font: Font
var pulse = 0.0

func _ready():
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	font = load("res://assets/fonts/interface.tres")
	for name in ["floor", "belt", "belt_turn", "source", "multiplier", "splitter", "research", "exploration", "hub"]:
		var path = "res://assets/textures/%s.png" % TEXTURE_FILES.get(name, name)
		if ResourceLoader.exists(path):
			textures[name] = load(path)
	turn_mesh = _make_turn_mesh()

func _make_turn_mesh() -> ArrayMesh:
	var vertices = PackedVector3Array()
	var uvs = PackedVector2Array()
	var indices = PackedInt32Array()
	for y in range(4):
		for x in range(4):
			vertices.append(Vector3(TURN_DEST[x] * TILE, TURN_DEST[y] * TILE, 0))
			uvs.append(Vector2(TURN_SOURCE_X[x], TURN_SOURCE_Y[y]))
	for y in range(3):
		for x in range(3):
			var i = y * 4 + x
			indices.append_array(PackedInt32Array([i, i + 1, i + 4, i + 1, i + 5, i + 4]))
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _process(delta):
	pulse += delta
	queue_redraw()

func _draw():
	if sim == null:
		return
	if sim is WorldSim:
		_draw_world()
		return
	draw_rect(Rect2(0, 0, FactorySim.WIDTH * TILE, FactorySim.HEIGHT * TILE), Color("edf0ef"))
	for y in range(FactorySim.HEIGHT):
		for x in range(FactorySim.WIDTH):
			var r = Rect2(x * TILE, y * TILE, TILE, TILE)
			if textures.has("floor"):
				draw_texture_rect(textures.floor, r, false, Color(1, 1, 1, 0.32))
	for x in range(FactorySim.WIDTH + 1):
		draw_line(Vector2(x * TILE, 0), Vector2(x * TILE, FactorySim.HEIGHT * TILE), Color(0.35, 0.43, 0.42, 0.11), 1, true)
	for y in range(FactorySim.HEIGHT + 1):
		draw_line(Vector2(0, y * TILE), Vector2(FactorySim.WIDTH * TILE, y * TILE), Color(0.35, 0.43, 0.42, 0.11), 1, true)
	for e in sim.entities.values():
		if e.layer == 1: _draw_underground(e)
	for e in sim.entities.values():
		if e.layer == 0: _draw_entity(e)
	for e in sim.entities.values():
		if e.layer == 1: _draw_tunnel_ports(e)
	if not sim.unlocked():
		var region = Rect2(20 * TILE, 0, 12 * TILE, 24 * TILE)
		draw_rect(region, Color(0.16, 0.21, 0.22, 0.87))
		for y in range(0, 24, 2):
			draw_line(Vector2(20 * TILE, y * TILE), Vector2(32 * TILE, (y + 12) * TILE), Color(1, 1, 1, 0.045), 2.0)
		draw_line(Vector2(20 * TILE, 0), Vector2(20 * TILE, 24 * TILE), Color("e76863"), 3)
		_center_text(Vector2(26 * TILE, 11 * TILE), "未探索区域", 24, Color("dce2e0"))
		_center_text(Vector2(26 * TILE, 12 * TILE), "18  ·  %d / 30" % sim.delivered.exploration, 18, Color("e99c94"))
	if selected.x >= 0:
		var e = sim.at(selected)
		if not e.is_empty():
			var size = 2 if e.kind in ["source", "research", "exploration", "hub"] else 1
			draw_rect(Rect2(Vector2(e.pos) * TILE, Vector2.ONE * TILE * size).grow(2), Color("13998e"), false, 2.5)
	if hover.x >= 0 and tool != "select":
		var valid = sim.can_place(hover) if tool != "erase" else not sim.at(hover).is_empty() and sim.at(hover).kind in ["belt", "multiplier", "splitter"]
		if tool == "belt" and sim.accessible(hover) and not sim.at(hover).is_empty():
			valid = sim.at(hover).kind in ["belt", "source", "multiplier", "splitter", "research", "exploration", "hub"]
		var color = Color("1aaf9f") if valid else Color("e76863")
		var r = Rect2(Vector2(hover) * TILE, Vector2.ONE * TILE)
		draw_rect(r, Color(color, 0.16))
		draw_rect(r, color, false, 2)
		if tool != "erase":
			_arrow(r.get_center(), direction, color)

func _draw_world():
	var inverse = get_global_transform_with_canvas().affine_inverse()
	var first = inverse * Vector2.ZERO
	var last = inverse * get_viewport_rect().size
	var area = Rect2i(Vector2i(floori(first.x / TILE) - 2, floori(first.y / TILE) - 2),
		Vector2i(ceili((last.x - first.x) / TILE) + 5, ceili((last.y - first.y) / TILE) + 5))
	var open = sim.world.bounds()
	var visible = area.intersection(open)
	if visible.has_area(): sim.ensure_area(visible)
	draw_rect(Rect2(Vector2(area.position) * TILE, Vector2(area.size) * TILE), Color("d7dfdd"))
	var stride = maxi(1, ceili(float(area.size.x) / 90.0))
	for y in range(visible.position.y, visible.end.y, stride):
		for x in range(visible.position.x, visible.end.x, stride):
			var r = Rect2(Vector2(x, y) * TILE, Vector2.ONE * TILE * stride)
			if textures.has("floor"): draw_texture_rect(textures.floor, r, false, Color(1, 1, 1, 0.32))
	for x in range(area.position.x, area.end.x + 1, stride):
		draw_line(Vector2(x * TILE, area.position.y * TILE), Vector2(x * TILE, area.end.y * TILE), Color(0.35, 0.43, 0.42, 0.14), 1, true)
	for y in range(area.position.y, area.end.y + 1, stride):
		draw_line(Vector2(area.position.x * TILE, y * TILE), Vector2(area.end.x * TILE, y * TILE), Color(0.35, 0.43, 0.42, 0.14), 1, true)
	var next = open.grow(8)
	for y in range(WorldGenerator.chunk_of(area.position).y, WorldGenerator.chunk_of(area.end).y + 1):
		for x in range(WorldGenerator.chunk_of(area.position).x, WorldGenerator.chunk_of(area.end).x + 1):
			for deposit in sim.generator.deposits(Vector2i(x, y)):
				if not open.has_point(deposit.pos) and next.has_point(deposit.pos):
					var center = (Vector2(deposit.pos) + Vector2.ONE) * TILE
					draw_circle(center, 20, Color("edf0ef"))
					_center_text(center, str(deposit.value), 20, Color("84958d"))
	for e in sim.entities.values():
		if area.grow(2).has_point(e.pos) and e.layer == 1: _draw_underground(e)
	for e in sim.entities.values():
		if area.grow(2).has_point(e.pos) and e.layer == 0: _draw_entity(e)
	for e in sim.entities.values():
		if area.grow(2).has_point(e.pos) and e.layer == 1: _draw_tunnel_ports(e)
	draw_rect(Rect2(Vector2(open.position) * TILE, Vector2(open.size) * TILE), Color("159486"), false, 2)
	var e = sim.at(selected)
	if not e.is_empty():
		var size = 2 if e.kind in ["source", "research", "logistics"] else 1
		draw_rect(Rect2(Vector2(e.pos) * TILE, Vector2.ONE * TILE * size).grow(2), Color("13998e"), false, 2.5)
	if area.has_point(hover) and tool != "select":
		var size = 2 if tool == "logistics" else 1
		var valid = sim.can_place_logistics(hover) if tool == "logistics" else sim.can_place(hover)
		if tool == "erase": valid = not sim.at(hover).is_empty() and sim.at(hover).kind in ["belt", "multiplier", "splitter", "logistics"]
		elif tool == "belt": valid = valid or (sim.accessible(hover) and not sim.at(hover).is_empty())
		var color = Color("1aaf9f") if valid else Color("e76863")
		var r = Rect2(Vector2(hover) * TILE, Vector2.ONE * TILE * size)
		draw_rect(r, Color(color, 0.16))
		draw_rect(r, color, false, 2)
		if tool != "erase": _arrow(r.get_center(), direction, color)

func _draw_entity(e: Dictionary):
	var big = e.kind in ["source", "research", "exploration", "hub", "logistics"]
	var size = 2 if big else 1
	var r = Rect2(Vector2(e.pos) * TILE, Vector2.ONE * TILE * size)
	var center = r.get_center()
	var name = "hub" if e.kind == "logistics" else e.kind
	var angle = 0.0 if e.kind == "splitter" else float(e.dir) * PI / 2.0
	if e.kind == "belt" and e.entry >= 0 and e.entry != (e.dir + 2) % 4:
		name = "belt_turn"
		# The elbow texture's default input is north and output east.
		angle = float(e.dir) * PI / 2.0
	if textures.has(name):
		var flip = name == "belt_turn" and e.entry == (e.dir + 1) % 4
		draw_set_transform(center, angle if not big else 0.0, Vector2(1, -1) if flip else Vector2.ONE)
		var tex_rect = Rect2(-r.size / 2, r.size)
		if name == "belt_turn":
			draw_mesh(turn_mesh, textures[name])
		else:
			draw_texture_rect(textures[name], tex_rect, false)
		draw_set_transform(Vector2.ZERO)
	else:
		draw_rect(r.grow(-3), Color("d3dad8") if e.kind == "belt" else Color("f9faf9"))
		draw_rect(r.grow(-3), Color("82938e"), false, 2)
	if e.kind == "source":
		var color = COLORS.get(e.value, Color("d5ad35"))
		draw_circle(center, 19, Color("f5faf8"))
		_center_text(center, str(e.value), 28, color)
		for i in range(sim.source_ports(e)):
			_arrow(Vector2(e.pos + Vector2i(2, i)) * TILE + Vector2(-5, TILE / 2), 0, color)
		if not sim.source_enabled(e):
			draw_rect(r, Color(0.4, 0.45, 0.43, 0.55))
			_center_text(center, "未研究", 14, Color.WHITE)
	elif e.kind == "research" and sim is WorldSim:
		draw_circle(center, 20, Color("f9fbfa"))
		_center_text(center, "研", 24, Color("159486"))
	elif e.kind == "logistics" and sim is WorldSim:
		draw_circle(center, 19, Color("f9fbfa"))
		_center_text(center, "仓", 24, Color("b79725"))
		for port in sim.logistics_ports(e):
			var position = Vector2(port.from) * TILE + Vector2.ONE * TILE / 2 + Vector2(FactorySim.DIRS[port.facing]) * 17
			if port.mode == "none": draw_circle(position, 2, Color("82938e"))
			else: _arrow(position, (port.facing + 2) % 4 if port.mode == "input" else port.facing, Color("159486") if port.mode == "input" else Color("b79725"), 0.65)
	elif e.kind in FactorySim.TARGETS:
		var color = Color("16a59a") if e.kind == "research" else Color("e76863") if e.kind == "exploration" else Color("d5ad35")
		draw_circle(center, 20, Color("f9fbfa"))
		_center_text(center, str(FactorySim.TARGETS[e.kind]), 25, Color("273c38"))
		var progress = minf(1.0, float(sim.delivered[e.kind]) / FactorySim.GOALS[e.kind])
		draw_rect(Rect2(r.position + Vector2(5, 74), Vector2(70, 4)), Color("ccd5d1"))
		draw_rect(Rect2(r.position + Vector2(5, 74), Vector2(70 * progress, 4)), color)
	elif e.kind == "multiplier":
		var rear = center - Vector2(FactorySim.DIRS[e.dir]) * 17
		var left = center + Vector2(FactorySim.DIRS[(e.dir + 3) % 4]) * 17
		draw_circle(rear, 3, Color("16a59a"))
		draw_circle(left, 3, Color("e76863"))
		_arrow(center + Vector2(FactorySim.DIRS[e.dir]) * 15, e.dir, Color("253b36"), 0.55)
		if e.output == 0:
			draw_circle(center, 9, Color("f5faf8"))
			var overflow = e.inputs[0] * e.inputs[1] > FactorySim.MAX_VALUE
			_center_text(center, "!" if overflow else "×", 16, Color("e76863") if overflow else Color("157d73"))
		if e.progress > 0:
			draw_arc(center, 14, -PI / 2, -PI / 2 + TAU * e.progress, 24, Color("16a59a"), 2, true)
		for port in range(2):
			if e.inputs[port] != 0:
				draw_circle(rear if port == 0 else left, 4, Color("e2b13a"))
	elif e.kind == "splitter":
		var ports = sim.splitter_ports(e)
		for facing in range(4):
			var pos = center + Vector2(FactorySim.DIRS[facing]) * 16
			if facing in ports.inputs:
				_arrow(pos, (facing + 2) % 4, Color("157d73"), 0.6)
			elif facing in ports.outputs:
				_arrow(pos, facing, Color("b4534e"), 0.6)
			else:
				draw_circle(pos, 2, Color("82938e"))
	else:
		_arrow(center, e.dir, Color(0.14, 0.24, 0.21, 0.6), 0.7)
	var value = e.output if e.kind == "multiplier" else e.item
	if value != 0:
		var token = token_layout(value)
		var pos = center
		# Animate within the source cell only, leaving the next cell's occupancy authoritative.
		if e.kind == "belt":
			pos += token_offset(token.size, e.entry if e.entry >= 0 else (e.dir + 2) % 4, e.age)
		var box = Rect2(pos - token.size / 2, token.size)
		draw_style_box(_token_style(value), box)
		_center_text(pos, token.label, token.font_size, Color("20352f"))

func token_layout(value: int) -> Dictionary:
	var label = short_number(value)
	var font_size = 13
	while font_size > 9 and font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > TILE - 14:
		font_size -= 1
	var width = maxf(23, font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 8)
	return {"label": label, "font_size": font_size, "size": Vector2(width, 20)}

static func token_offset(size: Vector2, entry: int, age: float) -> Vector2:
	var travel = Vector2.ONE * TILE / 2 - size / 2 - Vector2.ONE * 2
	return (Vector2(FactorySim.DIRS[entry]) * travel).lerp(Vector2.ZERO, clampf(age / FactorySim.TRAVEL, 0, 1))

func _draw_underground(e: Dictionary):
	var center = (Vector2(e.pos) + Vector2.ONE * 0.5) * TILE
	draw_set_transform(center, float(e.dir) * PI / 2)
	if textures.has("belt"):
		draw_texture_rect(textures.belt, Rect2(-20, -20, 40, 40), false, Color(0.45, 0.52, 0.5, 0.4))
	draw_set_transform(Vector2.ZERO)

func _draw_tunnel_ports(e: Dictionary):
	var center = (Vector2(e.pos) + Vector2.ONE * 0.5) * TILE
	var forward = Vector2(FactorySim.DIRS[e.dir])
	var side = Vector2(-forward.y, forward.x)
	for end in [-1, 1]:
		var pos = center + forward * 18 * end
		draw_line(pos - side * 6, pos + side * 6, Color("3b514a"), 4, true)
		draw_line(pos - side * 5, pos + side * 5, Color("e1c668"), 1.3, true)
		_arrow(pos, e.dir, Color("c9a74d"), 0.4)
	if e.item:
		draw_circle(center - forward * 15, 3, COLORS.get(e.item, Color("d5ad35")))

func _token_style(value: int) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color("ffffff")
	style.border_color = COLORS.get(value, Color("637e72"))
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	return style

func _arrow(pos: Vector2, dir: int, color: Color, size: float = 1.0):
	var v = Vector2(FactorySim.DIRS[dir])
	var perpendicular = Vector2(-v.y, v.x)
	draw_line(pos - v * 6 * size, pos + v * 6 * size, color, 1.6)
	draw_line(pos + v * 6 * size, pos + perpendicular * 4 * size, color, 1.6)
	draw_line(pos + v * 6 * size, pos - perpendicular * 4 * size, color, 1.6)

func _center_text(center: Vector2, text: String, size: int, color: Color):
	var width = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, center + Vector2(-width / 2, size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

static func short_number(value: int) -> String:
	return "%dk" % int(value / 1000) if value >= 1000 else str(value)
