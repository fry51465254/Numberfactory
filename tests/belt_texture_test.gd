extends SceneTree

var checks = 0
var failures: Array = []

func _initialize():
	call_deferred("run")

func verify(condition: bool, message: String):
	checks += 1
	if not condition: failures.append(message)

func _dark(c: Color) -> bool:
	return c.a > 0.9 and c.r > 0.14 and c.r < 0.45 and c.g < 0.5 and c.b < 0.55

func _track_run(image: Image, vertical: bool, depth: float) -> Vector2:
	var longest = Vector2(-1, -1)
	var start = -1
	for i in range(image.get_width()):
		var p = Vector2i(i, int(image.get_height() * depth)) if vertical else Vector2i(int(image.get_width() * (1 - depth)), i)
		if _dark(image.get_pixelv(p)):
			if start < 0: start = i
		elif start >= 0:
			if i - start > longest.y - longest.x:
				longest = Vector2(start, i - 1)
			start = -1
	if start >= 0 and image.get_width() - start > longest.y - longest.x:
		longest = Vector2(start, image.get_width() - 1)
	return longest / image.get_width()

func _warp(value: float, source: Array) -> float:
	for i in range(3):
		if value <= source[i + 1]:
			return lerpf(BoardView.TURN_DEST[i], BoardView.TURN_DEST[i + 1], inverse_lerp(source[i], source[i + 1], value))
	return 0.5

func run():
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.paused = true
	await process_frame
	var texture = scene.board.textures.belt_turn
	var image = texture.get_image()
	verify(image.get_size() == Vector2i(1254, 1254), "Port calibration matches the selected GPT asset")
	verify(image.has_mipmaps() and image.get_pixel(0, 0).a < 0.01, "Calibrated sprite retains transparency and mipmaps")
	var top = _track_run(image, true, 0.05)
	var east = _track_run(image, false, 0.05)
	var straight = _track_run(scene.board.textures.belt.get_image(), false, 0.5)
	var top_center = _warp((top.x + top.y) / 2, BoardView.TURN_SOURCE_X) * 40
	var east_center = _warp((east.x + east.y) / 2, BoardView.TURN_SOURCE_Y) * 40
	var straight_center = ((straight.x + straight.y) / 2 - 0.5) * 40
	verify(absf(top_center - straight_center) < 0.25, "Top track matches straight track within a quarter pixel")
	verify(absf(east_center - straight_center) < 0.25, "East track matches straight track within a quarter pixel")
	var top_width = (_warp(top.y, BoardView.TURN_SOURCE_X) - _warp(top.x, BoardView.TURN_SOURCE_X)) * 40
	var east_width = (_warp(east.y, BoardView.TURN_SOURCE_Y) - _warp(east.x, BoardView.TURN_SOURCE_Y)) * 40
	var straight_width = (straight.y - straight.x) * 40
	verify(absf(top_width - straight_width) < 0.5 and absf(east_width - straight_width) < 0.5, "Both elbow ports match straight track width")
	for direction in range(4):
		for turn in [-1, 1]:
			var entry = posmod(direction + turn, 4)
			var flip = -1 if turn == 1 else 1
			var input = Vector2(0, -20 * flip).rotated(direction * PI / 2)
			var output = Vector2(20, 0).rotated(direction * PI / 2)
			verify(input.is_equal_approx(Vector2(FactorySim.DIRS[entry]) * 20) and output.is_equal_approx(Vector2(FactorySim.DIRS[direction]) * 20), "Calibrated ports remain aligned after rotation/mirror %d/%d" % [direction, turn])
	if DisplayServer.get_name() != "headless":
		scene.sim = FactorySim.new(false)
		scene.sim.delivered.exploration = 30
		scene.board.sim = scene.sim
		for incoming in range(4):
			for turn in [-1, 1]:
				var corner = Vector2i(3 + incoming * 4, 9 if turn == -1 else 14)
				var outgoing = posmod(incoming + turn, 4)
				var from = corner - FactorySim.DIRS[incoming]
				var to = corner + FactorySim.DIRS[outgoing]
				scene.sim.place(from, "belt", incoming)
				scene.sim.place(corner, "belt", outgoing)
				scene.sim.place(to, "belt", outgoing)
				scene.sim.at(corner).entry = posmod(incoming + 2, 4)
				scene.sim.at(to).entry = posmod(outgoing + 2, 4)
		var machine = Vector2i(8, 17)
		scene.sim.place(machine, "multiplier", 0)
		scene.sim.at(machine).inputs = [7, 11]
		scene.sim.at(machine).progress = 0.45
		scene._set_tool("select")
		scene._paint(machine)
		scene.camera.position = Vector2(9.5 * 40, 11.5 * 40)
		for zoom in [1.0, 2.0]:
			scene.view_zoom = zoom
			scene.camera.zoom = Vector2.ONE * zoom
			scene._layout()
			scene.camera.force_update_scroll()
			await process_frame
			await RenderingServer.frame_post_draw
			var capture = root.get_texture().get_image()
			DirAccess.make_dir_recursive_absolute("res://qa")
			capture.save_png("res://qa/belt_turns_%dx%d_%dx.png" % [capture.get_width(), capture.get_height(), int(zoom)])
			verify(not capture.is_empty(), "Rendered corner inspection at zoom %d" % int(zoom))
	print("Belt texture: %d checks, %d failures" % [checks, failures.size()])
	for message in failures: push_error(message)
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
