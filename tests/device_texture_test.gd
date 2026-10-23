extends SceneTree

class SpritePreview extends BoardView:
	var entity: Dictionary
	func _draw():
		if not entity.is_empty(): _draw_entity(entity)

var checks = 0
var failures: Array = []
var scene

func _initialize():
	call_deferred("run")

func verify(condition: bool, message: String):
	checks += 1
	if not condition: failures.append(message)

func dark(c: Color) -> bool:
	return c.a > 0.9 and c.r > 0.14 and c.r < 0.45 and c.g < 0.5 and c.b < 0.55

func track_runs(image: Image, side: int) -> Array:
	var result: Array = []
	var size = image.get_width()
	var start = -1
	for i in range(size + 1):
		var p = Vector2i(i, int(size * 0.06)) if side == 0 else Vector2i(i, int(size * 0.94)) if side == 1 else Vector2i(int(size * 0.06), i) if side == 2 else Vector2i(int(size * 0.94), i)
		if i < size and dark(image.get_pixelv(p)):
			if start < 0: start = i
		elif start >= 0:
			if i - start > size * 0.025: result.append(Vector2(start, i - 1) / size)
			start = -1
	return result

func warp(value: float, source: Array, destination: Array) -> float:
	for i in range(source.size() - 1):
		if value <= source[i + 1]: return lerpf(destination[i], destination[i + 1], inverse_lerp(source[i], source[i + 1], value))
	return destination[-1]

func test_assets():
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/texture_manifest.json"))
	for name in BoardView.DEVICE_UV:
		var spec = BoardView.DEVICE_UV[name]
		var texture = scene.board.textures[name]
		var image = texture.get_image()
		verify(image.get_size() == Vector2i(1254, 1254), "Calibrated source is the preserved full-resolution GPT PNG: " + name)
		verify(image.has_mipmaps(), "Tiny devices have mipmaps: " + name)
		for p in [Vector2i.ZERO, Vector2i(1253, 0), Vector2i(0, 1253), Vector2i(1253, 1253)]:
			verify(image.get_pixelv(p).a < 0.01, "Real transparent corner, not an opaque background: " + name)
		verify(image.get_pixel(627, 627).a > 0.95, "Quiet label center stays opaque: " + name)
		var selected = manifest.assets.filter(func(asset): return asset.name == name)
		verify(selected.size() == 1 and selected[0].path == texture.resource_path and selected[0].tool == "built-in image_gen", "Manifest selects the actual workspace asset: " + name)
		verify(selected[0].display_pixels == 40 * spec.size and selected[0].render_alignment.source_pixels == 1254, "Manifest scale agrees with renderer: " + name)
		var arrays = scene.board.device_meshes[name].surface_get_arrays(0)
		verify(arrays[Mesh.ARRAY_VERTEX].size() == spec.x.size() * spec.y.size(), "All calibration anchors are present: " + name)
		verify(arrays[Mesh.ARRAY_INDEX].size() == (spec.x.size() - 1) * (spec.y.size() - 1) * 6, "Calibration has no missing grid cells: " + name)
		for axis in [spec.x, spec.y]:
			verify(axis.size() == spec.dest.size() and axis[0] == 0.0 and axis[-1] == 1.0, "Calibration retains the complete image: " + name)
			for i in range(axis.size() - 1): verify(axis[i] < axis[i + 1] and spec.dest[i] < spec.dest[i + 1], "Calibration cannot fold or mirror a port: " + name)
		for side in range(4):
			var runs = track_runs(image, side)
			verify(runs.size() == spec.size, "Correct passive socket count at every edge: " + name)
			if runs.size() != spec.size: continue
			var source = spec.x if side < 2 else spec.y
			for i in range(runs.size()):
				var center = warp((runs[i].x + runs[i].y) / 2, source, spec.dest) * 40 * spec.size
				var expected = 0.0 if spec.size == 1 else -20.0 if i == 0 else 20.0
				verify(absf(center - expected) < 0.3, "Socket center aligns to the real belt grid within 0.3px: " + name)
				var width = (warp(runs[i].y, source, spec.dest) - warp(runs[i].x, source, spec.dest)) * 40 * spec.size
				verify(absf(width - 6.4) < 0.6, "Socket width matches existing conveyors: " + name)
	verify(scene.board.textures.logistics.resource_path != scene.board.textures.hub.resource_path, "Logistics has its own eight-port storage sprite")

func gallery():
	scene.sim = LegacyBoardFixture.new()
	scene.board.sim = scene.sim
	scene.sim.world.technologies = ["ratio", "filter", "logistics"]
	scene.sim.world.logistics_capacity = 1
	scene.sim.delivered.research = 60
	var mine = Vector2i(4, 6)
	scene.sim._add_fixed("source", mine, 3)
	for port in scene.sim.source_sockets(scene.sim.at(mine)): scene.sim.build_belt(port.pos, port.facing, (port.facing + 2) % 4)
	var machine = Vector2i(12, 6)
	scene.sim.place(machine, "multiplier", 0)
	for facing in range(4): scene.sim.build_belt(machine + FactorySim.DIRS[facing], (facing + 2) % 4 if facing in [0, 3] else facing)
	var splitter = Vector2i(12, 12)
	scene.sim.place(splitter, "splitter", 0)
	for facing in range(4): scene.sim.build_belt(splitter + FactorySim.DIRS[facing], (facing + 2) % 4 if facing in [2, 3] else facing)
	var station = Vector2i(4, 12)
	verify(scene.sim.place(station, "logistics", 0), "Build logistics visual fixture within its quota")
	for port in scene.sim.logistics_ports(scene.sim.at(station)):
		var inward = port.index % 2 == 0
		scene.sim.build_belt(port.pos, (port.facing + 2) % 4 if inward else port.facing, -1 if inward else (port.facing + 2) % 4)
		if not inward: scene.sim.at(station).outputs[port.index] = 6
	scene.camera.position = Vector2(8.5, 9.0) * 40
	scene.view_zoom = 1.0
	scene.camera.zoom = Vector2.ONE
	scene._layout()
	scene.camera.force_update_scroll()
	scene._set_tool("select")
	for record in [["source", mine], ["multiplier", machine], ["splitter", splitter], ["logistics", station]]:
		scene._paint(record[1])
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var image = root.get_texture().get_image()
		image.save_png("res://qa/device_textures_%s_%dx%d.png" % [record[0], image.get_width(), image.get_height()])
		verify(not image.is_empty(), "Rendered eight-port/four-port fixture: " + record[0])
	await native_sizes()

func native_sizes():
	var viewport = SubViewport.new()
	viewport.size = Vector2i(320, 96)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var offset = 8
	for name in ["multiplier", "splitter", "source", "logistics"]:
		var board = SpritePreview.new()
		board.sim = LegacyBoardFixture.new()
		board.entity = board.sim._base(name, Vector2i.ZERO, 0)
		if name == "source": board.entity.value = 3
		board.position = Vector2(offset, 8)
		viewport.add_child(board)
		offset += 40 * BoardView.DEVICE_UV[name].size + 16
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image = viewport.get_texture().get_image()
	image.save_png("res://qa/device_textures_native.png")
	offset = 8
	for name in ["multiplier", "splitter", "source", "logistics"]:
		var size = 40 * BoardView.DEVICE_UV[name].size
		var solid = 0
		for y in range(size):
			for x in range(size):
				if image.get_pixel(offset + x, 8 + y).a > 0.5: solid += 1
		verify(solid > size * size * 0.25, "Native-sized sprite is nonblank with visible silhouette: " + name)
		offset += size + 16
	viewport.queue_free()

func run():
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.paused = true
	await process_frame
	test_assets()
	if "--visual" in OS.get_cmdline_user_args(): await gallery()
	print("Adaptive device textures: %d checks, %d failures" % [checks, failures.size()])
	for message in failures: push_error(message)
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
