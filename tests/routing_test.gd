extends SceneTree

var checks = 0
var failures: Array = []
var scene

func _initialize():
	call_deferred("run")

func verify(value: bool, message: String):
	checks += 1
	if not value: failures.append(message)

func advance(sim: FactorySim, steps: int = 10):
	for i in range(steps): sim.tick()

func inject(sim: FactorySim, p: Vector2i, value: int, layer: int = 0):
	var e = sim.at(p, layer)
	assert(e.item == 0)
	e.item = value
	e.age = 0
	sim.emitted += FactorySim.prime_count(value)

func drain(sim: FactorySim, p: Vector2i) -> int:
	var e = sim.at(p)
	var value = e.item
	sim.discarded += FactorySim.prime_count(value)
	e.item = 0
	return value

func junction(inputs: Array, outputs: Array) -> FactorySim:
	var sim = FactorySim.new(false)
	var p = Vector2i(8, 10)
	sim.place(p, "splitter", 0)
	for direction in inputs: sim.place(p + FactorySim.DIRS[direction], "belt", (direction + 2) % 4)
	for direction in outputs: sim.place(p + FactorySim.DIRS[direction], "belt", direction)
	return sim

func _test_four_way():
	var p = Vector2i(8, 10)
	for incoming in range(4):
		var outputs: Array = []
		for direction in range(4):
			if direction != incoming: outputs.append(direction)
		var sim = junction([incoming], outputs)
		var ports = sim.splitter_ports(sim.at(p))
		verify(ports.inputs == [incoming] and ports.outputs == outputs, "Automatic 1-to-3 port detection from side %d" % incoming)
		var counts = [0, 0, 0, 0]
		for i in range(360):
			var source = p + FactorySim.DIRS[incoming]
			if sim.at(source).item == 0: inject(sim, source, 6)
			sim.tick()
			for direction in outputs:
				if drain(sim, p + FactorySim.DIRS[direction]) == 6: counts[direction] += 1
		var distribution: Array = []
		for direction in outputs: distribution.append(counts[direction])
		verify(distribution.min() >= 10 and distribution.max() - distribution.min() <= 1, "Three outputs are fair at 3/sec from side %d: %s" % [incoming, counts])
		verify(sim.total_mass() == sim.emitted, "Four-way splitter conserves material")
	var merge = junction([2, 3], [0, 1])
	var merged = {2: 0, 3: 0}
	for i in range(600):
		for direction in [2, 3]:
			var source = p + FactorySim.DIRS[direction]
			if merge.at(source).item == 0: inject(merge, source, direction)
		merge.tick()
		for direction in [0, 1]:
			var value = drain(merge, p + FactorySim.DIRS[direction])
			if value: merged[value] += 1
	verify(merged[2] > 20 and merged[3] > 20, "Multiple input streams cannot starve: %s" % merged)
	verify(merge.total_mass() == merge.emitted, "Merge and split preserve material")
	merge.redirect_belt(p + Vector2i.UP, 3)
	verify(merge.splitter_ports(merge.at(p)).inputs == [2] and merge.splitter_ports(merge.at(p)).outputs == [0, 1, 3], "Changing connected belt direction updates ports immediately")
	merge.remove(p + Vector2i.RIGHT)
	verify(merge.splitter_ports(merge.at(p)).outputs == [1, 3], "Removing an output updates topology")
	var weighted = junction([2], [0, 1, 3])
	weighted.delivered.research = 20
	weighted.at(p).mode = 1
	weighted.at(p).ratio = 3
	var counts = [0, 0, 0, 0]
	for i in range(25):
		inject(weighted, p, 2)
		advance(weighted)
		for direction in [0, 1, 3]:
			if drain(weighted, p + FactorySim.DIRS[direction]): counts[direction] += 1
	verify(counts == [15, 5, 0, 5], "Ratio mode weights the primary port across all outputs")
	var blocked = junction([2], [0, 1, 3])
	inject(blocked, p + Vector2i.RIGHT, 12)
	counts = [0, 0, 0, 0]
	for i in range(20):
		inject(blocked, p, 2)
		advance(blocked)
		for direction in [1, 3]:
			if drain(blocked, p + FactorySim.DIRS[direction]): counts[direction] += 1
	verify(counts[1] == 10 and counts[3] == 10, "Blocked-port fallback remains fair between available outputs")
	verify(blocked.total_mass() == blocked.emitted, "Blocked fallback preserves material")
	var sealed = junction([0, 1, 2, 3], [])
	for direction in range(4): inject(sealed, p + FactorySim.DIRS[direction], direction + 2)
	advance(sealed, 90)
	var remaining = 0
	for direction in range(4):
		if sealed.at(p + FactorySim.DIRS[direction]).item: remaining += 1
	verify(sealed.at(p).item != 0 and remaining == 3 and sealed.total_mass() == sealed.emitted, "Four inputs without output stop safely with no dropped items")

func _test_filters_and_save():
	var p = Vector2i(8, 10)
	var sim = junction([2], [0, 1, 3])
	sim.delivered.research = 60
	sim.emitted += 60 * FactorySim.prime_count(12)
	sim.at(p).mode = 2
	sim.at(p).filters = [2, 3, 0, -1]
	for pair in [[2, 0], [3, 1], [5, 3], [12, 3]]:
		inject(sim, p, pair[0])
		advance(sim)
		verify(sim.at(p + FactorySim.DIRS[pair[1]]).item == pair[0], "Filter %d goes to side %d" % pair)
		for direction in [0, 1, 3]: drain(sim, p + FactorySim.DIRS[direction])
	inject(sim, p + Vector2i.RIGHT, 12)
	inject(sim, p, 2)
	advance(sim, 90)
	verify(sim.at(p).item == 2 and sim.at(p + Vector2i.DOWN).item == 0 and sim.at(p + Vector2i.UP).item == 0, "Blocked exact match cannot leak to remaining/all-number outputs")
	var restored = FactorySim.new(false)
	var saved = JSON.parse_string(JSON.stringify(sim.serialize()))
	verify(restored.restore(saved), "Four-port filter save restores")
	verify(restored.at(p).filters == [2, 3, 0, -1] and restored.at(p).item == 2, "Save retains filters, buffered value and cursor")
	drain(sim, p + Vector2i.RIGHT)
	drain(restored, p + Vector2i.RIGHT)
	advance(sim)
	advance(restored)
	verify(JSON.stringify(sim.serialize()) == JSON.stringify(restored.serialize()), "Filter save resumes identical routing")
	verify(sim.total_mass() == sim.emitted, "Filtering conserves material")
	var legacy = sim.serialize()
	legacy.version = 1
	for e in legacy.entities:
		e.erase("layer")
		e.erase("filters")
		e.filter = 18
		if e.kind == "splitter":
			e.item = 18
			e.age = FactorySim.TRAVEL
		if e.pos == [9, 10]:
			e.dir = 1
			e.entry = -1
			e.item = 0
	var old = FactorySim.new(false)
	var legacy_json = JSON.parse_string(JSON.stringify(legacy))
	verify(old.restore(legacy_json) and old.at(p).filters == [18, -1, 0, 0], "Version 1 directional filter migrates")
	verify(old.at(p + Vector2i.RIGHT).entry == 2 and 0 in old.splitter_ports(old.at(p)).outputs, "Legacy empty corner output is inferred during migration")
	advance(old)
	verify(old.at(p + Vector2i.RIGHT).item == 18, "Migrated legacy splitter keeps its original filtered route")
	var invalid = sim.serialize()
	invalid.entities[0].filters = [1, 0, 0, 0]
	verify(not restored.restore(invalid), "Invalid numeric filters are rejected transactionally")

func crossing(horizontal: int, vertical: int) -> FactorySim:
	var sim = FactorySim.new(false)
	for x in range(4, 9): sim.build_belt(Vector2i(x, 10), horizontal)
	for y in range(8, 13): sim.build_belt(Vector2i(6, y), vertical, -1, true)
	return sim

func _test_crossings():
	var p = Vector2i(6, 10)
	for horizontal in [0, 2]:
		for vertical in [1, 3]:
			var sim = FactorySim.new(false)
			sim.build_belt(p, horizontal)
			inject(sim, p, 12)
			var original = sim.at(p).duplicate(true)
			verify(sim.build_belt(p, vertical, -1, true) == 1 and sim.at(p) == original, "Crossing keeps the first lane and its cargo unchanged %d/%d" % [horizontal, vertical])
			verify(sim.build_belt(p, vertical, -1, true) == 1 and sim.entities.size() == 2, "Repainting tunnel is idempotent")
			verify(sim.build_belt(p, (vertical + 2) % 4, -1, true) == -1, "Opposite tunnel flow cannot overwrite an existing crossing")
			sim = crossing(horizontal, vertical)
			var start_h = p - FactorySim.DIRS[horizontal] * 2
			var start_v = p - FactorySim.DIRS[vertical] * 2
			var finish_h = p + FactorySim.DIRS[horizontal] * 2
			var finish_v = p + FactorySim.DIRS[vertical] * 2
			var counts = [0, 0]
			for i in range(300):
				if sim.at(start_h).item == 0: inject(sim, start_h, 6)
				if sim.at(start_v).item == 0: inject(sim, start_v, 10)
				sim.tick()
				var h = drain(sim, finish_h)
				var v = drain(sim, finish_v)
				if h: counts[0] += 1
				if v: counts[1] += 1
				if h != 0 and h != 6 or v != 0 and v != 10:
					failures.append("Crossing swapped channels")
			verify(counts[0] == counts[1] and counts[0] >= 25 and counts[0] <= 30, "Both crossing channels retain 3/sec throughput %d/%d: %s" % [horizontal, vertical, counts])
			verify(sim.total_mass() == sim.emitted, "Crossing conserves prime mass")
	var blocked = crossing(0, 1)
	for x in range(4, 9): inject(blocked, Vector2i(x, 10), 6)
	var delivered = 0
	for i in range(180):
		if blocked.at(Vector2i(6, 8)).item == 0: inject(blocked, Vector2i(6, 8), 10)
		blocked.tick()
		if drain(blocked, Vector2i(6, 12)) == 10: delivered += 1
	verify(delivered >= 14 and blocked.at(p).item == 6, "Blocked surface has no effect on underground throughput")
	verify(blocked.total_mass() == blocked.emitted, "Independent blockage conserves material")
	var copy = FactorySim.new(false)
	var saved = JSON.parse_string(JSON.stringify(blocked.serialize()))
	verify(copy.restore(saved), "Crossing save restores")
	verify(copy.at(p).item == blocked.at(p).item and copy.at(p, 1).item == blocked.at(p, 1).item, "Both crossing buffers survive save")
	advance(copy, 30)
	advance(blocked, 30)
	verify(copy.entities.size() == blocked.entities.size() and copy.total_mass() == blocked.total_mass() and copy.turn == blocked.turn, "Crossing resume preserves exact flow")
	for id in blocked.entities:
		verify(copy.entities[id].item == blocked.entities[id].item and is_equal_approx(copy.entities[id].age, blocked.entities[id].age), "Restored crossing preserves item and travel time at " + id)
	var ground = blocked.at(p).duplicate(true)
	verify(blocked.remove_underground(p) and blocked.at(p) == ground and blocked.total_mass() == blocked.emitted, "Removing tunnel preserves surface and accounts for cargo")
	verify(copy.remove(p) and copy.at(p, 1).is_empty() and copy.total_mass() == copy.emitted, "Removing crossing clears both lanes without losing accounting")
	var malformed = crossing(0, 1).serialize()
	malformed.entities.reverse()
	verify(copy.restore(malformed), "Save restoration does not depend on layer ordering")
	for e in malformed.entities:
		if e.layer == 1: e.dir = 0
	verify(not copy.restore(malformed), "Parallel overlapping lanes are rejected")
	var curved = FactorySim.new(false)
	curved.build_belt(p, 0, 3)
	verify(curved.build_belt(p, 1, -1, true) == -1 and curved.at(p).entry == 3, "Crossings cannot corrupt an existing bend")
	verify(curved.build_belt(Vector2i(20, 10), 1, -1, true) == -1, "Underground construction respects locked regions")
	for old_direction in [1, 3]:
		for new_direction in [0, 2]:
			var vertical_first = FactorySim.new(false)
			vertical_first.build_belt(p, old_direction)
			inject(vertical_first, p, 18)
			var original = vertical_first.at(p).duplicate(true)
			verify(vertical_first.build_belt(p, new_direction, -1, true) == 1 and vertical_first.at(p) == original, "Vertical-first crossing preserves old lane %d/%d" % [old_direction, new_direction])
	var adjacent = FactorySim.new(false)
	for y in range(9, 12):
		for x in range(4, 9): adjacent.build_belt(Vector2i(x, y), 0)
	for y in range(8, 13): adjacent.build_belt(Vector2i(6, y), 1, -1, true)
	inject(adjacent, Vector2i(6, 8), 30)
	for y in range(9, 12):
		advance(adjacent)
		verify(adjacent.at(Vector2i(6, y), 1).item == 30, "Adjacent crossings advance only one layer-cell at a time, row %d" % y)
	advance(adjacent)
	verify(adjacent.at(Vector2i(6, 12)).item == 30 and adjacent.total_mass() == adjacent.emitted, "Consecutive tunnels emerge onto the correct surface lane")
	for flow in [0, 2]:
		var connected = FactorySim.new(false)
		connected.place(Vector2i(8, 10), "splitter", 0)
		connected.build_belt(Vector2i(9, 10), 1)
		connected.build_belt(Vector2i(9, 10), flow, -1, true)
		connected.build_belt(Vector2i(7, 10), flow)
		connected.build_belt(Vector2i(10, 10), flow)
		var ports = connected.splitter_ports(connected.at(Vector2i(8, 10)))
		verify(0 in (ports.outputs if flow == 0 else ports.inputs), "Splitter detects the correct adjacent underground channel %d" % flow)
		inject(connected, Vector2i(7, 10) if flow == 0 else Vector2i(10, 10), 18)
		advance(connected, 40)
		verify(connected.at(Vector2i(10, 10) if flow == 0 else Vector2i(7, 10)).item == 18 and connected.at(Vector2i(9, 10)).item == 0, "Splitter and adjacent tunnel exchange only their connected stream")

func press(p: Vector2i):
	scene.painting = true
	scene._begin_stroke(p)

func release():
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	scene._input(event)

func _test_builder():
	for reversed in [false, true]:
		scene.sim = FactorySim.new(false)
		scene.board.sim = scene.sim
		scene._set_tool("belt")
		for x in range(4, 10): scene.sim.build_belt(Vector2i(x, 10), 0)
		var ground = scene.sim.at(Vector2i(6, 10)).duplicate(true)
		if reversed:
			scene.sim.place(Vector2i(6, 14), "multiplier", 1)
			press(Vector2i(6, 14))
			scene._drag_to(Vector2i(6, 8))
		else:
			press(Vector2i(6, 8))
			scene._drag_to(Vector2i(6, 13))
		release()
		verify(scene.sim.at(Vector2i(6, 10)) == ground and scene.sim.at(Vector2i(6, 10), 1).dir == 1, "Dragging %s creates tunnel and preserves original line" % ["backwards" if reversed else "forwards"])
		verify(scene.sim.at(Vector2i(6, 11)).dir == 1 and scene.sim.at(Vector2i(6, 9)).dir == 1, "Dragging exits the tunnel onto normal surface belts")
		inject(scene.sim, Vector2i(4, 10), 6)
		inject(scene.sim, Vector2i(6, 8), 10)
		advance(scene.sim, 90)
		verify(scene.sim.at(Vector2i(9, 10)).item == 6 and (scene.sim.at(Vector2i(6, 14)).inputs[0] == 10 if reversed else scene.sim.at(Vector2i(6, 13)).item == 10), "Player-built crossing transports both real streams")
		verify(scene.sim.total_mass() == scene.sim.emitted, "Player-built crossing preserves all material")
	scene.sim = FactorySim.new(false)
	scene.board.sim = scene.sim
	scene.sim.place(Vector2i(8, 10), "splitter", 0)
	for direction in range(4):
		scene._set_tool("belt")
		press(Vector2i(8, 10))
		scene._drag_to(Vector2i(8, 10) + FactorySim.DIRS[direction] * 2)
		release()
	verify(scene.sim.splitter_ports(scene.sim.at(Vector2i(8, 10))).outputs.size() == 4, "Splitter-first construction creates outputs on all four sides")
	scene._set_tool("select")
	scene._paint(Vector2i(8, 10))
	scene.sim.delivered.research = 60
	scene.mode_input.select(2)
	scene.mode_input.item_selected.emit(2)
	scene._refresh()
	verify(not scene.filter_ports[3].selector.disabled and scene.filter_ports[3].label.text.contains("输出"), "Inspector detects north output and enables its filter")
	scene.sim = FactorySim.new(false)
	scene.board.sim = scene.sim
	scene.sim.build_belt(Vector2i(8, 10), 0)
	inject(scene.sim, Vector2i(8, 10), 12)
	var original = scene.sim.at(Vector2i(8, 10)).duplicate(true)
	scene._set_tool("belt")
	press(Vector2i(8, 10))
	scene._drag_to(Vector2i(8, 12))
	release()
	verify(scene.sim.at(Vector2i(8, 10)) == original and not scene.sim.at(Vector2i(8, 10), 1).is_empty(), "A drag beginning on an old lane creates an underground start without rotating the old lane")
	scene._set_tool("select")
	scene._paint(Vector2i(8, 10))
	verify(scene.underground_box.visible and scene.inspector_detail.text.contains("地下"), "Crossing inspector shows independent underground state")
	for child in scene.underground_box.get_children():
		if child is Button: child.pressed.emit()
	verify(scene.sim.at(Vector2i(8, 10), 1).is_empty() and scene.sim.at(Vector2i(8, 10)) == original, "Inspector can remove only the underground lane")
	scene.sim.build_belt(Vector2i(19, 10), 2)
	var edge = scene.sim.at(Vector2i(19, 10)).duplicate(true)
	scene._set_tool("belt")
	press(Vector2i(19, 10))
	scene._drag_to(Vector2i(20, 10))
	release()
	verify(scene.sim.at(Vector2i(19, 10)) == edge and scene.sim.at(Vector2i(19, 10), 1).is_empty(), "A blocked first drag step cannot change the old lane")

func run():
	_test_four_way()
	_test_filters_and_save()
	_test_crossings()
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.paused = true
	await process_frame
	_test_builder()
	if "--visual" in OS.get_cmdline_user_args():
		await _visual()
	print("Routing: %d checks, %d failures" % [checks, failures.size()])
	for message in failures: push_error(message)
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _visual():
	scene.sim = FactorySim.new(false)
	scene.sim.delivered.research = 60
	scene.sim.delivered.exploration = 30
	scene.board.sim = scene.sim
	var p = Vector2i(10, 10)
	scene.sim.place(p, "splitter", 0)
	for x in range(5, 17):
		if x != 10: scene.sim.build_belt(Vector2i(x, 10), 0, 2)
	for y in range(5, 17):
		if y != 10: scene.sim.build_belt(Vector2i(10, y), 1, 3)
	for y in range(7, 16): scene.sim.build_belt(Vector2i(13, y), 1, 3, true)
	for x in range(7, 17): scene.sim.build_belt(Vector2i(x, 13), 0, 2, true)
	scene.sim.at(p).mode = 2
	scene.sim.at(p).filters = [12, 18, 0, 0]
	scene.sim.at(p).item = 18
	scene.sim.at(p).age = 0.5
	scene.sim.at(Vector2i(7, 10)).item = 12
	scene.sim.at(Vector2i(10, 7)).item = 18
	scene.sim.at(Vector2i(13, 10)).item = 12
	scene.sim.at(Vector2i(13, 10), 1).item = 30
	scene.sim.at(Vector2i(10, 13), 1).item = 6
	scene.sim.at(Vector2i(13, 8)).item = 30
	scene.camera.position = Vector2(10.5 * 40, 10.5 * 40)
	scene.view_zoom = 1.35
	scene.camera.zoom = Vector2.ONE * 1.35
	scene._layout()
	scene.camera.force_update_scroll()
	scene._set_tool("select")
	for cell in [p, Vector2i(13, 10)]:
		scene._paint(cell)
		await process_frame
		await RenderingServer.frame_post_draw
		var image = root.get_texture().get_image()
		DirAccess.make_dir_recursive_absolute("res://qa")
		var name = "splitter" if cell == p else "crossing"
		image.save_png("res://qa/routing_%s_%dx%d.png" % [name, image.get_width(), image.get_height()])
		verify(not image.is_empty(), "Rendered routing inspector: " + name)
