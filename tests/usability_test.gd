extends SceneTree

var checks = 0
var failures: Array = []

func _initialize():
	call_deferred("run")

func verify(condition: bool, message: String):
	checks += 1
	if not condition: failures.append(message)

func mine_fixture(value: int = 2) -> LegacyBoardFixture:
	var sim = LegacyBoardFixture.new()
	sim._add_fixed("source", Vector2i(5, 5), value)
	if value not in sim.world.primes: sim.world.primes.append(value)
	return sim

func test_mines():
	for value in [2, 3, 5]:
		var sim = mine_fixture(value)
		var mine = sim.at(Vector2i(5, 5))
		var sockets = sim.source_sockets(mine)
		var counts = [0, 0, 0, 0, 0, 0, 0, 0]
		var last_turn = [-100, -100, -100, -100, -100, -100, -100, -100]
		var smallest_budget = INF
		for port in sockets: verify(sim.place(port.pos, "belt", port.facing), "Build outward source port %d" % port.index)
		verify(sim.source_connections(mine).size() == 8, "All perimeter cells automatically output")
		for tick in range(300):
			sim.tick()
			smallest_budget = minf(smallest_budget, mine.budget)
			for port in sockets:
				var belt = sim.at(port.pos)
				if belt.item:
					verify(belt.item == value and tick - last_turn[port.index] >= 10, "Correct prime and maximum three per second per outlet")
					last_turn[port.index] = tick
					counts[port.index] += 1
					sim.discarded += FactorySim.prime_count(belt.item)
					belt.item = 0
		var expected = int(sim.source_total_rate(mine) * 10)
		verify(abs(sim.emitted - expected) <= 1, "Eight outputs share fixed total rate %d: got %d expected %d" % [value, sim.emitted, expected])
		verify(counts.max() - counts.min() <= 1, "Round robin serves every side fairly")
		verify(sim.emitted == sim.total_mass(), "Source transfer conserves materials")
		verify(smallest_budget >= 0.0, "Fractional source credit never becomes a negative save value for prime %d" % value)
		for tick in range(900): sim.tick()
		var before = sim.emitted
		verify(mine.budget <= 1 + FactorySim.STEP * sim.source_total_rate(mine) + 0.000001, "Blocked source does not accumulate a backlog")
		for tick in range(300): sim.tick()
		verify(sim.emitted == before, "Full outlets stop production")
	for slot in range(8):
		var sim = mine_fixture()
		var mine = sim.at(Vector2i(5, 5))
		var port = sim.source_sockets(mine)[slot]
		sim.place(port.pos, "belt", (port.facing + 1) % 4)
		for tick in range(30): sim.tick()
		verify(sim.emitted == 0, "Parallel belt does not receive from mine")
		sim.redirect_belt(port.pos, (port.facing + 2) % 4)
		for tick in range(30): sim.tick()
		verify(sim.emitted == 0, "Inward belt does not receive from mine")
		sim.redirect_belt(port.pos, port.facing)
		for tick in range(30): sim.tick()
		verify(sim.at(port.pos).item == 2, "Live redirection enables any perimeter outlet")
	var crossing = mine_fixture()
	var port = crossing.source_sockets(crossing.at(Vector2i(5, 5)))[6]
	crossing.place(port.pos, "belt", 0)
	verify(crossing.build_belt(port.pos, 3, -1, true) == 1, "Source can feed a matching underground lane")
	for tick in range(20): crossing.tick()
	verify(crossing.at(port.pos).item == 0 and crossing.at(port.pos, 1).item == 2, "Crossed lanes never mix source materials")
	var direct = mine_fixture()
	direct.place(Vector2i(7, 5), "multiplier", 0)
	for tick in range(60): direct.tick()
	verify(direct.emitted == 0, "Automatic mine outlets require a belt")
	var real = WorldSim.new(42)
	var mine = real.at(Vector2i(-8, -4))
	for socket in real.source_sockets(mine):
		if real.at(socket.pos).is_empty(): real.place(socket.pos, "belt", socket.facing)
	for tick in range(123): real.tick()
	var copy = WorldSim.new()
	verify(copy.restore(JSON.parse_string(JSON.stringify(real.serialize()))), "Restore shared source budget, cursor and port timers")
	for tick in range(180):
		real.tick()
		copy.tick()
	verify(real.emitted == copy.emitted and real.total_mass() == copy.total_mass(), "Restored source continuation preserves all materials")
	verify(real.at(mine.pos).cursor == copy.at(mine.pos).cursor and is_equal_approx(real.at(mine.pos).budget, copy.at(mine.pos).budget), "Restored source scheduling remains identical")
	var fractional = WorldSim.new(42)
	for tick in range(120):
		fractional.tick()
		for p in [Vector2i(-6, 4), Vector2i(-6, 5)]:
			var belt = fractional.at(p)
			fractional.discarded += FactorySim.prime_count(belt.item)
			belt.item = 0
		if tick % 7 == 0:
			var restored = WorldSim.new()
			verify(restored.restore(JSON.parse_string(JSON.stringify(fractional.serialize()))), "Active fractional mining credit can be saved and restored at tick %d" % tick)
	var old_credit = fractional.serialize()
	for entity in old_credit.entities:
		if entity.kind == "source" and entity.value == 3: entity.budget = -0.000000000001
	verify(WorldSim.new().restore(old_credit), "Early preview floating-point residue does not invalidate physical inventory")
	for entity in old_credit.entities:
		if entity.kind == "source" and entity.value == 3: entity.budget = -0.1
	verify(not WorldSim.new().restore(old_credit), "Meaningfully negative mining credit is still rejected")

func test_diagnostics():
	var sim = LegacyBoardFixture.new()
	var diagnostics = FlowDiagnostics.new(sim)
	sim.place(Vector2i(5, 5), "belt", 0)
	var belt = sim.at(Vector2i(5, 5))
	verify(diagnostics.describe(belt).text.contains("未连接"), "Empty disconnected belt is distinguishable from waiting for production")
	belt.item = 2
	belt.age = FactorySim.TRAVEL
	verify(diagnostics.describe(belt).cell == Vector2i(6, 5), "Missing downstream is located precisely")
	for x in range(6, 9):
		sim.place(Vector2i(x, 5), "belt", 0)
		sim.at(Vector2i(x, 5)).item = 2
		sim.at(Vector2i(x, 5)).age = FactorySim.TRAVEL
	sim._add_fixed("research", Vector2i(9, 5))
	var before = sim.serialize()
	var diagnosis = diagnostics.describe(belt)
	verify(diagnosis.warning and diagnosis.cell == Vector2i(9, 5) and diagnosis.text.contains("不接收数字 2"), "Blocked chain identifies rejecting research station, not adjacent belt")
	verify(sim.serialize() == before, "Diagnostics are read-only")
	sim.entities.erase("9,5")
	for p in [Vector2i(9, 5), Vector2i(10, 5), Vector2i(9, 6), Vector2i(10, 6)]: sim.occupancy.erase(FactorySim.key(p))
	sim.place(Vector2i(9, 5), "multiplier", 0)
	var machine = sim.at(Vector2i(9, 5))
	machine.inputs = [2, 0]
	verify(diagnostics.describe(belt).text.contains("输入 B"), "Full A input identifies missing B on downstream machine")
	sim.place(Vector2i(9, 4), "belt", 1)
	var broken_input = diagnostics.describe(machine)
	verify(broken_input.warning and broken_input.cell == Vector2i(9, 4) and broken_input.text.contains("未连接矿点"), "Connected input belt with no source locates the upstream break")
	verify(diagnostics.describe(belt).cell == Vector2i(9, 4), "Downstream machine waiting for B traces a broken upstream input")
	machine.inputs = [999999, 2]
	verify(diagnostics.describe(belt).text.contains("超出"), "Overflow is a specific obstruction")
	sim.place(Vector2i(10, 5), "belt", 0)
	sim.at(Vector2i(10, 5)).item = 6
	sim.at(Vector2i(10, 5)).age = FactorySim.TRAVEL
	machine.inputs = [2, 3]
	machine.output = 6
	verify(diagnostics.describe(belt).cell == Vector2i(11, 5), "Trace through machine uses cached output and identifies later missing link")
	var ports = diagnostics.machine_ports(machine)
	verify(ports.size() == 3 and ports[2].warning, "Machine input and output faults have separate port descriptors")
	var split_sim = LegacyBoardFixture.new()
	split_sim.delivered.research = 60
	split_sim.place(Vector2i(5, 5), "splitter", 0)
	split_sim.place(Vector2i(6, 5), "belt", 0)
	var splitter = split_sim.at(Vector2i(5, 5))
	splitter.mode = 2
	splitter.item = 6
	splitter.age = FactorySim.TRAVEL
	splitter.filters[0] = 12
	verify(FlowDiagnostics.new(split_sim).describe(splitter).text.contains("无匹配输出"), "Unmatched filter is explained")
	var loop = LegacyBoardFixture.new()
	for descriptor in [[Vector2i(5, 5), 0], [Vector2i(6, 5), 1], [Vector2i(6, 6), 2], [Vector2i(5, 6), 3]]:
		loop.place(descriptor[0], "belt", descriptor[1])
		loop.at(descriptor[0]).item = 2
		loop.at(descriptor[0]).age = FactorySim.TRAVEL
	verify(not FlowDiagnostics.new(loop).describe(loop.at(Vector2i(5, 5))).warning, "Movable full loop is not reported as a jam")
	loop.place(Vector2i(4, 5), "belt", 0)
	loop.at(Vector2i(4, 5)).item = 2
	loop.at(Vector2i(4, 5)).age = FactorySim.TRAVEL
	verify(FlowDiagnostics.new(loop).describe(loop.at(Vector2i(4, 5))).warning, "External input cannot insert an extra item into a full closed loop")

func test_ui():
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.paused = true
	await process_frame
	var stock = scene.sim.world.research_stock.duplicate()
	scene.expansion_button.emit_signal("pressed")
	verify(not scene.expansion_button.disabled and scene.status_label.text.contains("数字 6 还缺 20") and scene.research_feedback.visible, "Insufficient expansion click explains exactly what is missing")
	scene.research_feedback.hide()
	scene.prime_button.emit_signal("pressed")
	verify(scene.status_label.text.contains("还需扩张 3 圈") and scene.status_label.text.contains("还缺"), "Prime research shows both land and resource prerequisites")
	scene.research_feedback.hide()
	verify(scene.sim.world.research_stock == stock and scene.sim.world.expansions == 0, "Rejected actions consume nothing")
	verify(scene.expansion_label.text.contains("库存") and scene.expansion_label.text.contains("需要") and scene.expansion_label.text.contains("还缺"), "Costs identify stock, requirement and deficit")
	var pos = Vector2i(8, 8)
	scene.sim.place(pos, "multiplier", 0)
	scene.sim.place(pos + Vector2i.RIGHT, "belt", 0)
	scene._set_tool("select")
	for zoom in [0.45, 0.9, 1.5, 2.0]:
		scene.view_zoom = zoom
		scene.camera.zoom = Vector2.ONE * zoom
		scene.camera.position = (Vector2(pos) + Vector2.ONE * 0.5) * 40
		scene._layout()
		scene.camera.force_update_scroll()
		var transform = scene.board.get_global_transform_with_canvas()
		var press = InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = transform * (Vector2(pos) * 40 + Vector2(37, 20))
		scene._unhandled_input(press)
		var motion = InputEventMouseMotion.new()
		motion.position = transform * (Vector2(pos) * 40 + Vector2(42, 20))
		motion.relative = Vector2(5 * zoom, 0)
		scene._unhandled_input(motion)
		verify(scene.selected == pos and not scene.painting, "Click jitter cannot replace machine selection at zoom %s" % zoom)
		verify(scene._pick_cell(motion.position) == pos, "Device-edge tolerance at zoom %s" % zoom)
		var belt_center = transform * ((Vector2(pos + Vector2i.RIGHT) + Vector2.ONE * 0.5) * 40)
		verify(scene._pick_cell(belt_center) == pos + Vector2i.RIGHT, "Belt centers remain selectable at zoom %s" % zoom)
	var original = scene.sim
	for slot in range(8):
		scene.sim = mine_fixture()
		scene.board.sim = scene.sim
		var source = scene.sim.at(Vector2i(5, 5))
		var port = scene.sim.source_sockets(source)[slot]
		scene._set_tool("belt")
		scene.painting = true
		scene._begin_stroke(port.from)
		scene._drag_to(port.pos + FactorySim.DIRS[port.facing])
		verify(scene.sim.at(port.pos).kind == "belt" and scene.sim.at(port.pos).dir == port.facing, "Drag from anywhere on mine body connects perimeter outlet %d" % slot)
		for tick in range(30): scene.sim.tick()
		verify(scene.sim.emitted > 0, "Body-dragged outlet actually produces on each side")
		scene._end_stroke()
	scene.sim = original
	scene.board.sim = original
	scene._set_tool("select")
	for size in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = size
		scene._layout()
		await process_frame
		var left = scene.root.get_node("Left")
		var footer = left.get_node("Summary")
		var scroll = left.get_node("Goals")
		verify(footer.get_global_rect().end.y <= scene.root.get_node("Bottom").position.y, "Fixed sidebar summary never overlaps toolbar")
		verify(scroll.get_global_rect().end.y <= footer.get_global_rect().position.y, "Scrolling goals do not overlap fixed controls")
		scroll.scroll_vertical = 1000000
		await process_frame
		verify(scroll.get_global_rect().encloses(scene.tech_controls.logistics.button.get_global_rect()), "Last research button fully reachable by scrolling at %s" % size)
		verify(left.get_global_rect().encloses(footer.get_child(-1).get_global_rect()), "Research locate button always fully visible")
		var saved_primes = scene.sim.world.primes.duplicate()
		scene.sim.world.primes = [2, 3, 5, 7, 11, 13]
		scene._refresh()
		await process_frame
		verify(scene.supply_label.tooltip_text.contains("2, 3, 5, 7, 11, 13") and left.get_global_rect().encloses(footer.get_child(-1).get_global_rect()), "Late-game prime summary cannot push fixed controls below toolbar")
		scene.sim.world.primes = saved_primes
	scene.queue_free()
	await process_frame

func run():
	test_mines()
	test_diagnostics()
	await test_ui()
	print("Usability: %d checks, %d failures" % [checks, failures.size()])
	for message in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)
