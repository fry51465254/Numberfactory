extends SceneTree

var checks = 0
var failures: Array = []
var scene
const MACHINE = Vector2i(10, 10)

func _initialize():
	call_deferred("run")

func verify(condition: bool, message: String):
	checks += 1
	if not condition: failures.append(message)

func advance(sim: FactorySim, steps: int):
	for i in range(steps): sim.tick()

func inject(sim: FactorySim, p: Vector2i, value: int, layer: int = 0):
	var e = sim.at(p, layer)
	assert(e.item == 0)
	e.item = value
	e.age = 0.0
	sim.emitted += FactorySim.prime_count(value)

func test_machine_sides():
	for rotation in range(4):
		for a in range(4):
			for b in range(a + 1, 4):
				for output in range(4):
					if output in [a, b]: continue
					var sim = FactorySim.new(false)
					sim.place(MACHINE, "multiplier", rotation)
					for facing in [a, b]: sim.build_belt(MACHINE + FactorySim.DIRS[facing], (facing + 2) % 4)
					sim.build_belt(MACHINE + FactorySim.DIRS[output], output)
					var machine = sim.at(MACHINE)
					var ports = sim.multiplier_ports(machine)
					verify(ports.inputs.size() == 2 and a in ports.inputs and b in ports.inputs and ports.outputs == [output], "Any pair of input sides and any remaining output, independent of rotation")
					inject(sim, MACHINE + FactorySim.DIRS[a], 2)
					inject(sim, MACHINE + FactorySim.DIRS[b], 3)
					advance(sim, 10)
					verify(machine.inputs[ports.slots.find(a)] == 2 and machine.inputs[ports.slots.find(b)] == 3, "Each side has its own one-item operand buffer")
					advance(sim, 29)
					verify(machine.output == 0, "Automatic ports do not shorten processing")
					advance(sim, 1)
					verify(machine.output == 6, "Any side pair multiplies in exactly one second")
					advance(sim, 10)
					verify(machine.output == 0 and sim.at(MACHINE + FactorySim.DIRS[output]).item == 6, "Product leaves through detected output only")
					verify(sim.total_mass() == sim.emitted, "Adaptive multiplication conserves all material")
	var single = FactorySim.new(false)
	single.place(MACHINE, "multiplier", 0)
	single.build_belt(MACHINE + Vector2i.RIGHT, 2)
	inject(single, MACHINE + Vector2i.RIGHT, 2)
	advance(single, 20)
	inject(single, MACHINE + Vector2i.RIGHT, 3)
	advance(single, 90)
	verify(single.at(MACHINE).inputs.count(0) == 1 and single.at(MACHINE).output == 0 and single.at(MACHINE + Vector2i.RIGHT).item == 3, "One input side cannot fill both operands")
	for facing in range(4):
		for turn in [-1, 1]:
			var sim = FactorySim.new(false)
			sim.place(MACHINE, "multiplier", 0)
			var flow = posmod(facing + turn, 4)
			var p = MACHINE + FactorySim.DIRS[facing]
			sim.build_belt(p, flow, (facing + 2) % 4)
			sim.build_belt(p + FactorySim.DIRS[flow], flow)
			sim.at(MACHINE).output = 6
			sim.emitted = 2
			advance(sim, 20)
			verify(sim.at(p + FactorySim.DIRS[flow]).item == 6 and sim.total_mass() == sim.emitted, "A bent first output belt works on any side of the machine")

func test_input_limit_and_rebinding():
	var sim = FactorySim.new(false)
	sim.place(MACHINE, "multiplier", 0)
	for facing in [0, 1, 2]: sim.build_belt(MACHINE + FactorySim.DIRS[facing], (facing + 2) % 4)
	var machine = sim.at(MACHINE)
	var before = sim.serialize()
	var ports = sim.multiplier_ports(machine)
	verify(ports.inputs == [0, 1] and ports.rejected == [2] and machine.input_dirs == [0, 1], "First two connected sides stay selected even while paused")
	verify(sim.serialize() == before, "Port discovery is read-only")
	for facing in [0, 1, 2]: inject(sim, MACHINE + FactorySim.DIRS[facing], [2, 3, 5][facing])
	advance(sim, 45)
	verify(machine.output == 6 and sim.at(MACHINE + Vector2i.LEFT).item == 5, "Third input remains on the belt and cannot join a batch")
	verify(FlowDiagnostics.new(sim).describe(sim.at(MACHINE + Vector2i.LEFT)).text.contains("最多"), "Rejected input has a specific two-input diagnostic")
	sim.build_belt(MACHINE + Vector2i.UP, 3)
	advance(sim, 10)
	verify(sim.at(MACHINE + Vector2i.UP).item == 6 and sim.total_mass() == sim.emitted, "Fourth side can output while excess input waits")
	sim.remove(MACHINE + Vector2i.RIGHT)
	verify(sim.multiplier_ports(machine).inputs == [1, 2], "Removing an empty input permits the previously rejected side")
	var rebound = FactorySim.new(false)
	rebound.place(MACHINE, "multiplier", 0)
	rebound.build_belt(MACHINE + Vector2i.RIGHT, 2)
	inject(rebound, MACHINE + Vector2i.RIGHT, 2)
	advance(rebound, 10)
	rebound.remove(MACHINE + Vector2i.RIGHT)
	var cached = rebound.at(MACHINE)
	rebound.build_belt(MACHINE + Vector2i.LEFT, 0)
	inject(rebound, MACHINE + Vector2i.LEFT, 3)
	verify(cached.inputs == [2, 0] and cached.input_dirs == [0, 2], "Removed input retains its operand and the other slot accepts a new side")
	advance(rebound, 40)
	verify(cached.output == 6 and rebound.total_mass() == rebound.emitted, "Rewiring cannot discard or reinterpret a cached operand")
	rebound.build_belt(MACHINE + Vector2i.RIGHT, 0)
	advance(rebound, 10)
	verify(rebound.at(MACHINE + Vector2i.RIGHT).item == 6, "Former input side can become output after its operand is processed")
	var old = FactorySim.new(false)
	old.place(MACHINE, "multiplier", 0)
	old.build_belt(MACHINE + Vector2i.LEFT, 0)
	old.build_belt(MACHINE + Vector2i.UP, 1)
	inject(old, MACHINE + Vector2i.LEFT, 2)
	inject(old, MACHINE + Vector2i.UP, 3)
	advance(old, 20)
	var legacy = JSON.parse_string(JSON.stringify(old.serialize()))
	for entity in legacy.entities: entity.erase("input_dirs")
	var copy = FactorySim.new(false)
	verify(copy.restore(legacy) and copy.at(MACHINE).input_dirs == [2, 3], "Legacy directional buffers migrate without losing material or batch progress")
	advance(old, 20)
	advance(copy, 20)
	verify(JSON.stringify(copy.serialize()) == JSON.stringify(old.serialize()), "Migrated legacy batch continues identically")
	for invalid in [[0, 0], [-1, 3], [2, 5], [2.5, 3], [2], "east"]:
		var data = copy.serialize()
		for entity in data.entities:
			if entity.kind == "multiplier":
				entity.input_dirs = invalid
				entity.inputs = [2, 3]
		var state = copy.serialize()
		verify(not copy.restore(data) and copy.serialize() == state, "Invalid port binding is rejected transactionally")

func test_outputs_and_tunnels():
	var sim = FactorySim.new(false)
	sim.place(MACHINE, "multiplier", 0)
	for facing in [1, 3]: sim.build_belt(MACHINE + FactorySim.DIRS[facing], (facing + 2) % 4)
	for facing in [0, 2]: sim.build_belt(MACHINE + FactorySim.DIRS[facing], facing)
	var counts = [0, 0]
	for step in range(1500):
		for facing in [1, 3]:
			if sim.at(MACHINE + FactorySim.DIRS[facing]).item == 0: inject(sim, MACHINE + FactorySim.DIRS[facing], 2 if facing == 1 else 3)
		sim.tick()
		for slot in range(2):
			var belt = sim.at(MACHINE + FactorySim.DIRS[slot * 2])
			if belt.item != 0:
				verify(belt.item == 6, "Multiple outputs do not emit raw ingredients")
				counts[slot] += 1
				sim.discarded += FactorySim.prime_count(belt.item)
				belt.item = 0
	verify(counts.min() > 10 and counts.max() - counts.min() <= 1, "Products alternate fairly between connected outputs")
	inject(sim, MACHINE + Vector2i.RIGHT, 12)
	var continued = 0
	for step in range(180):
		for facing in [1, 3]:
			if sim.at(MACHINE + FactorySim.DIRS[facing]).item == 0: inject(sim, MACHINE + FactorySim.DIRS[facing], 2 if facing == 1 else 3)
		sim.tick()
		var belt = sim.at(MACHINE + Vector2i.LEFT)
		if belt.item:
			continued += 1
			sim.discarded += FactorySim.prime_count(belt.item)
			belt.item = 0
	verify(continued >= 3 and sim.at(MACHINE + Vector2i.RIGHT).item == 12 and sim.total_mass() == sim.emitted, "One blocked output falls back without duplication or ingredient loss")
	var copy = FactorySim.new(false)
	verify(copy.restore(JSON.parse_string(JSON.stringify(sim.serialize()))), "Adaptive ports, cursor and all live buffers restore")
	advance(sim, 60)
	advance(copy, 60)
	verify(JSON.stringify(copy.serialize()) == JSON.stringify(sim.serialize()), "Output scheduling remains identical after restore")
	for facing in range(4):
		for inward in [false, true]:
			var tunnel = FactorySim.new(false)
			tunnel.place(MACHINE, "multiplier", 0)
			var p = MACHINE + FactorySim.DIRS[facing]
			tunnel.build_belt(p, (facing + 1) % 4)
			var flow = (facing + 2) % 4 if inward else facing
			verify(tunnel.build_belt(p, flow, -1, true) == 1, "Build independent lane next to adaptive machine")
			if inward:
				inject(tunnel, p, 2, 1)
			else:
				tunnel.at(MACHINE).output = 6
				tunnel.emitted += 2
			advance(tunnel, 10)
			verify((2 in tunnel.at(MACHINE).inputs if inward else tunnel.at(p, 1).item == 6) and tunnel.at(p).item == 0, "Input/output resolves correct layer on every side")
			verify(tunnel.total_mass() == tunnel.emitted, "Adaptive tunnel ports conserve material")

func test_mine_bends():
	for facing in range(8):
		for turn in [-1, 1]:
			var sim = LegacyBoardFixture.new()
			sim._add_fixed("source", Vector2i(8, 8), 2)
			var mine = sim.at(Vector2i(8, 8))
			var port = sim.source_sockets(mine)[facing]
			var outgoing = posmod(port.facing + turn, 4)
			sim.build_belt(port.pos, outgoing, (port.facing + 2) % 4)
			sim.build_belt(port.pos + FactorySim.DIRS[outgoing], outgoing)
			verify(sim.source_connections(mine).size() == 1, "Both bends at every perimeter outlet connect by their entry side")
			advance(sim, 30)
			verify(sim.at(port.pos + FactorySim.DIRS[outgoing]).item == 2 and sim.total_mass() == sim.emitted, "Bent first tile activates the mine and actually carries ore")
			verify(FlowDiagnostics.new(sim).incoming(sim.at(port.pos)).has(mine), "Bent mine connection is visible to upstream diagnostics")
	var merged = LegacyBoardFixture.new()
	merged._add_fixed("source", Vector2i(8, 8), 2)
	merged.build_belt(Vector2i(10, 8), 3, 2)
	merged.build_belt(Vector2i(10, 9), 3)
	merged.build_belt(Vector2i(10, 7), 3)
	inject(merged, Vector2i(10, 9), 3)
	advance(merged, 10)
	verify(merged.at(Vector2i(10, 8)).item == 3 and merged.at(Vector2i(10, 8)).entry == 2 and merged.at(Vector2i(10, 8)).arrival_entry == 1, "Side merge changes only token arrival, never the mine-facing bend geometry")
	advance(merged, 20)
	verify(merged.source_connections(merged.at(Vector2i(8, 8))).size() == 1 and merged.at(Vector2i(10, 8)).item == 2 and merged.total_mass() == merged.emitted, "A side merge cannot silently disconnect the mine")

func reset_scene():
	scene._end_stroke()
	scene.sim = LegacyBoardFixture.new()
	scene.board.sim = scene.sim
	scene.camera.position = Vector2(10 * 40, 10 * 40)
	scene.view_zoom = 0.9
	scene.camera.zoom = Vector2.ONE * scene.view_zoom
	scene._layout()
	scene.camera.force_update_scroll()
	scene.direction = 3
	scene._set_tool("belt")

func press(cell: Vector2i, reverse: bool = false):
	scene.painting = true
	scene._begin_stroke(cell, reverse)

func release():
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	scene._input(event)

func test_gestures():
	for index in range(8):
		for turn in [-1, 1]:
			reset_scene()
			scene.sim._add_fixed("source", Vector2i(8, 8), 2)
			var mine = scene.sim.at(Vector2i(8, 8))
			var port = scene.sim.source_sockets(mine)[index]
			var outgoing = posmod(port.facing + turn, 4)
			press(port.from)
			scene._drag_to(port.pos)
			scene._drag_to(port.pos + FactorySim.DIRS[outgoing] * 2)
			release()
			var first = scene.sim.at(port.pos)
			verify(first.dir == outgoing and first.entry == (port.facing + 2) % 4, "Mine-first gesture can bend on its first belt tile")
			advance(scene.sim, 40)
			verify(scene.sim.at(port.pos + FactorySim.DIRS[outgoing] * 2).item == 2, "Player-painted immediate bend delivers actual ore")
	for facing in range(4):
		for inward in [false, true]:
			reset_scene()
			scene.sim.place(MACHINE, "multiplier", 0)
			press(MACHINE, inward)
			scene._drag_to(MACHINE + FactorySim.DIRS[facing] * 2)
			release()
			verify(scene.sim.at(MACHINE + FactorySim.DIRS[facing]).dir == ((facing + 2) % 4 if inward else facing), "Machine-first drag is outward; Shift reverses it on any side")
	reset_scene()
	press(Vector2i(6, 6))
	verify(scene.sim.at(Vector2i(6, 6)).is_empty(), "Mouse-down defers direction until actual movement")
	scene._drag_to(Vector2i(14, 12))
	var close = true
	for cell in scene.stroke_cells:
		var offset = cell - Vector2i(6, 6)
		close = close and absf(offset.x * 6 - offset.y * 8) / 10.0 <= 0.8
	verify(close and scene.stroke_cells.size() == 15, "Fast diagonal movement follows the cursor rather than a horizontal-first L")
	release()
	reset_scene()
	scene.sim.place(Vector2i(9, 11), "multiplier", 0)
	press(Vector2i(6, 10))
	scene._drag_to(Vector2i(9, 10))
	verify(scene.sim.at(Vector2i(9, 10)).dir == 0, "Endpoint does not snap toward a device during an active drag")
	scene._drag_to(Vector2i(12, 10))
	release()
	verify(scene.sim.at(Vector2i(9, 10)).dir == 0, "Continuing past a machine leaves the intended straight route")
	reset_scene()
	press(Vector2i(6, 10))
	scene._drag_to(Vector2i(9, 10))
	scene._drag_to(Vector2i(9, 12))
	scene._drag_to(Vector2i(9, 10))
	verify(scene.sim.at(Vector2i(9, 11)).is_empty() and scene.sim.at(Vector2i(9, 12)).is_empty() and scene.sim.at(Vector2i(9, 10)).dir == 0, "Retracing a new bend removes only the new tail and restores the corner")
	scene._drag_to(Vector2i(12, 10))
	release()
	verify(scene.sim.at(Vector2i(12, 10)).dir == 0, "A retraced stroke can continue in a new direction")
	reset_scene()
	scene.sim.build_belt(Vector2i(9, 10), 0, 2)
	inject(scene.sim, Vector2i(9, 10), 6)
	var original = scene.sim.at(Vector2i(9, 10)).duplicate(true)
	press(Vector2i(6, 10))
	scene._drag_to(Vector2i(10, 10))
	scene._drag_to(Vector2i(8, 10))
	verify(scene.sim.at(Vector2i(9, 10)) == original, "Retracing across an older belt preserves its geometry and cargo")
	release()
	reset_scene()
	scene.sim.build_belt(Vector2i(9, 10), 0, 2)
	inject(scene.sim, Vector2i(9, 10), 6)
	original = scene.sim.at(Vector2i(9, 10)).duplicate(true)
	press(Vector2i(9, 10))
	scene._drag_to(Vector2i(9, 12))
	scene._drag_to(Vector2i(9, 10))
	release()
	verify(scene.sim.at(Vector2i(9, 10)) == original and scene.sim.at(Vector2i(9, 10), 1).is_empty(), "Fully retracting a crossing removes the new origin tunnel without modifying the old lane")
	reset_scene()
	press(Vector2i(6, 10))
	scene._drag_to(Vector2i(9, 10))
	scene._drag_to(Vector2i(6, 10))
	release()
	verify(scene.sim.entities.is_empty(), "Fully retracting a new stroke leaves no ghost origin tile")
	reset_scene()
	scene.sim._add_fixed("source", Vector2i(8, 8), 2)
	press(Vector2i(9, 8))
	scene._drag_to(Vector2i(13, 8))
	advance(scene.sim, 120)
	scene._drag_to(Vector2i(9, 8))
	release()
	verify(scene.sim.emitted > 0 and scene.sim.total_mass() == scene.sim.emitted and scene.sim.entities.size() == 1, "Retracting a live mined route accounts for removed cargo and never restores stale materials")
	reset_scene()
	var location = scene.board.get_global_transform_with_canvas() * (Vector2(8, 8) * 40 + Vector2(39, 20))
	var down = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = location
	scene._unhandled_input(down)
	var jitter = InputEventMouseMotion.new()
	jitter.position = location + Vector2(2, 0)
	scene._unhandled_input(jitter)
	verify(scene.stroke_start_pending and scene.sim.at(Vector2i(9, 8)).is_empty(), "Tiny press jitter cannot create or rotate an adjacent segment")
	release()

func run():
	test_machine_sides()
	test_input_limit_and_rebinding()
	test_outputs_and_tunnels()
	test_mine_bends()
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.paused = true
	await process_frame
	test_gestures()
	if "--visual" in OS.get_cmdline_user_args(): await visual()
	print("Adaptive ports and gestures: %d checks, %d failures" % [checks, failures.size()])
	for message in failures: push_error(message)
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func visual():
	reset_scene()
	scene.sim._add_fixed("source", Vector2i(14, 8), 2)
	scene.sim._add_fixed("source", Vector2i(8, 5), 3)
	scene.sim._add_fixed("research", Vector2i(6, 12))
	scene.sim.place(MACHINE, "multiplier", 0)
	press(Vector2i(14, 8))
	scene._drag_to(Vector2i(13, 8))
	scene._drag_to(Vector2i(13, 10))
	scene._drag_to(MACHINE)
	release()
	press(Vector2i(8, 6))
	scene._drag_to(Vector2i(8, 7))
	scene._drag_to(Vector2i(10, 7))
	scene._drag_to(MACHINE)
	release()
	press(MACHINE)
	scene._drag_to(Vector2i(8, 10))
	scene._drag_to(Vector2i(8, 12))
	release()
	press(MACHINE)
	scene._drag_to(Vector2i(10, 13))
	scene._drag_to(Vector2i(8, 13))
	release()
	advance(scene.sim, 360)
	verify(scene.sim.world.count(scene.sim.world.lifetime, 6) >= 4 and scene.sim.total_mass() == scene.sim.emitted, "Visual fixture actually mines bent inputs and delivers adaptive outputs")
	scene.camera.position = Vector2(10.5 * 40, 9.5 * 40)
	scene.view_zoom = 1.3
	scene.camera.zoom = Vector2.ONE * 1.3
	scene._layout()
	scene.camera.force_update_scroll()
	scene._set_tool("select")
	scene._paint(MACHINE)
	await capture("machine")
	scene._paint(Vector2i(13, 8))
	await capture("mine_bend")
	scene.sim.redirect_belt(MACHINE + Vector2i.DOWN, 3)
	scene._paint(MACHINE)
	await capture("excess_input")

func capture(name: String):
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://qa")
	image.save_png("res://qa/adaptive_%s_%dx%d.png" % [name, image.get_width(), image.get_height()])
	verify(not image.is_empty(), "Rendered automatic ports and immediate bend: " + name)
