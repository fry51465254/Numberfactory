extends SceneTree

var checks = 0
var failures: Array = []
var scene

func _initialize():
	call_deferred("run")

func verify(condition: bool, message: String):
	checks += 1
	if not condition:
		failures.append(message)

func reset_board():
	scene.sim = LegacyBoardFixture.new()
	scene.board.sim = scene.sim
	scene.selected = Vector2i(-1, -1)
	scene.direction = 0
	scene.camera.position = Vector2(12 * 40, 12 * 40)
	scene.view_zoom = 0.9
	scene.camera.zoom = Vector2.ONE * scene.view_zoom
	scene._layout()
	scene._set_tool("belt")
	scene.camera.force_update_scroll()

func screen(cell: Vector2i) -> Vector2:
	return scene.board.get_global_transform_with_canvas() * (Vector2(cell) * 40 + Vector2(20, 20))

func press(cell: Vector2i):
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = screen(cell)
	scene._unhandled_input(event)

func drag(cell: Vector2i):
	var event = InputEventMouseMotion.new()
	event.position = screen(cell)
	scene._unhandled_input(event)

func release():
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	scene._input(event)

func run():
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.paused = true
	await process_frame
	# The machine exists before either input route is painted.
	reset_board()
	var machine = Vector2i(12, 12)
	scene.sim.place(machine, "multiplier", 0)
	press(Vector2i(8, 12))
	drag(machine)
	release()
	press(Vector2i(9, 10))
	drag(Vector2i(9, 11))
	drag(Vector2i(12, 11))
	release()
	verify(scene.sim.at(Vector2i(12, 11)).dir == 1, "Input B belt snaps south to existing machine")
	verify(scene.sim.at(Vector2i(9, 11)).dir == 0, "Corner keeps outgoing direction")
	verify(scene.sim.at(Vector2i(9, 11)).entry == 3, "Empty corner remembers north input before any material arrives")
	verify(scene.sim.at(machine).kind == "multiplier" and scene.sim.at(machine).dir == 0, "Painting preserves prebuilt machine")
	inject(Vector2i(8, 12), 2)
	inject(Vector2i(9, 10), 3)
	for i in range(120): scene.sim.tick()
	verify(scene.sim.at(machine).output == 6, "Machine-first construction produces 6 through both input routes")
	verify(scene.sim.total_mass() == scene.sim.emitted, "Bending transport preserves material")
	# Beginning on an input device reverses the construction direction.
	for rotation in range(4):
		for port in range(2):
			reset_board()
			scene.sim.place(machine, "multiplier", rotation)
			var outward = -FactorySim.DIRS[rotation] if port == 0 else FactorySim.DIRS[(rotation + 3) % 4]
			press(machine)
			drag(machine + outward * 3)
			release()
			var endpoint = machine + outward * 3
			var e = scene.sim.at(endpoint)
			verify(not e.is_empty() and e.kind == "belt" and e.dir == FactorySim.DIRS.find(-outward), "Reverse paint feeds port %d rotation %d" % [port, rotation])
			if not e.is_empty():
				inject(endpoint, 2 if port == 0 else 3)
				for i in range(40): scene.sim.tick()
				verify(scene.sim.at(machine).inputs[port] == (2 if port == 0 else 3), "Reverse-built route actually delivers to rotated port")
	# Dragging farther than an occupied target stops at that target.
	reset_board()
	scene.sim.place(machine, "multiplier", 0)
	press(Vector2i(8, 12))
	drag(Vector2i(14, 12))
	release()
	verify(scene.sim.at(Vector2i(13, 12)).is_empty() and scene.sim.at(Vector2i(14, 12)).is_empty(), "Stroke cannot continue through machine")
	# Side without an input must not redirect a previous belt into the obstacle.
	reset_board()
	scene.sim.place(machine, "multiplier", 0)
	press(Vector2i(12, 14))
	drag(Vector2i(12, 13))
	var old_direction = scene.sim.at(Vector2i(12, 13)).dir
	drag(machine)
	release()
	verify(scene.sim.at(Vector2i(12, 13)).dir == old_direction, "Invalid machine side does not mutate preceding belt")
	# Clicking an existing belt redirects it without losing its cargo.
	reset_board()
	scene.sim.place(Vector2i(10, 12), "belt", 0)
	inject(Vector2i(10, 12), 2)
	scene.direction = 1
	press(Vector2i(10, 12))
	release()
	verify(scene.sim.at(Vector2i(10, 12)).dir == 1 and scene.sim.at(Vector2i(10, 12)).item == 2, "Reorient occupied belt preserves cargo")
	_test_bends()
	_test_device_endpoints(machine)
	if "--visual" in OS.get_cmdline_user_args():
		reset_board()
		scene.sim.place(machine, "multiplier", 0)
		press(Vector2i(8, 12))
		drag(machine)
		release()
		press(machine)
		drag(Vector2i(12, 10))
		drag(Vector2i(9, 10))
		release()
		scene._set_tool("select")
		scene._paint(machine)
		scene.camera.position = Vector2(11 * 40, 11.5 * 40)
		scene.view_zoom = 1.5
		scene.camera.zoom = Vector2.ONE * 1.5
		scene._layout()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://qa/belt_inputs_before_flow.png")
	print("Belt construction: %d checks, %d failures" % [checks, failures.size()])
	for message in failures: push_error(message)
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func inject(cell: Vector2i, value: int):
	scene.sim.at(cell).item = value
	scene.sim.at(cell).age = 0.0
	scene.sim.emitted += FactorySim.prime_count(value)

func _test_bends():
	for incoming in range(4):
		for turn in [-1, 1]:
			reset_board()
			var corner = Vector2i(12, 12)
			var outgoing = posmod(incoming + turn, 4)
			var start = corner - FactorySim.DIRS[incoming] * 2
			var finish = corner + FactorySim.DIRS[outgoing] * 2
			press(start)
			drag(corner)
			drag(finish)
			release()
			var e = scene.sim.at(corner)
			verify(e.dir == outgoing and e.entry == (incoming + 2) % 4, "Empty bend geometry %d/%d" % [incoming, outgoing])
			inject(start, 6)
			for i in range(60): scene.sim.tick()
			verify(scene.sim.at(finish).item == 6 and scene.sim.total_mass() == scene.sim.emitted, "Bend transports and conserves material %d/%d" % [incoming, outgoing])

func _test_device_endpoints(machine: Vector2i):
	reset_board()
	scene.sim.place(machine, "multiplier", 0)
	press(machine)
	drag(Vector2i(15, 12))
	release()
	verify(scene.sim.at(Vector2i(13, 12)).dir == 0, "Machine output supports forward painting")
	reset_board()
	scene.sim._add_fixed("source", Vector2i(6, 12), 2)
	scene.sim.place(Vector2i(12, 12), "multiplier", 0)
	press(Vector2i(12, 12))
	drag(Vector2i(7, 12))
	release()
	verify(scene.sim.at(Vector2i(8, 12)).dir == 0 and scene.sim.at(Vector2i(6, 12)).kind == "source", "Reverse route terminates at source output without replacing source")
	reset_board()
	scene.sim._add_fixed("source", Vector2i(6, 12), 2)
	press(Vector2i(6, 12))
	drag(Vector2i(10, 12))
	release()
	verify(scene.sim.at(Vector2i(8, 12)).dir == 0 and scene.sim.at(Vector2i(10, 12)).kind == "belt", "Source-first stroke leaves through real outlet")
	reset_board()
	scene.sim._add_fixed("research", Vector2i(12, 12))
	press(Vector2i(12, 12))
	drag(Vector2i(9, 12))
	release()
	verify(scene.sim.at(Vector2i(9, 12)).dir == 0, "Consumer-first stroke builds inward")
	reset_board()
	scene.sim.place(Vector2i(12, 12), "multiplier", 0)
	scene._fit_map()
	scene.camera.position = Vector2(16 * 40, 12 * 40)
	scene.camera.force_update_scroll()
	press(Vector2i(10, 12))
	drag(Vector2i(10, 24))
	release()
	var edge = scene.sim.at(Vector2i(10, 23))
	verify(not edge.is_empty() and edge.dir == 1 and not scene.painting, "Boundary stops stroke without invalid cells")
