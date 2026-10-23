extends SceneTree

var checks = 0
var failures: Array = []
var scene

func _initialize():
	call_deferred("run")

func verify(condition: bool, message: String):
	checks += 1
	if not condition: failures.append(message)

func inject(sim: FactorySim, p: Vector2i, value: int, layer: int = 0):
	sim.at(p, layer).item = value
	sim.at(p, layer).age = 0.15
	sim.emitted += FactorySim.prime_count(value)

func fixture() -> LegacyBoardFixture:
	var sim = LegacyBoardFixture.new()
	sim.world.technologies = ["ratio", "filter", "logistics"]
	sim.world.logistics_capacity = 2
	sim.delivered.research = 60
	return sim

func test_copy_rotation():
	var sim = fixture()
	sim.build_belt(Vector2i(2, 4), 1, 2)
	sim.build_belt(Vector2i(4, 4), 0, 2)
	sim.build_belt(Vector2i(4, 4), 1, 3, true)
	sim.place(Vector2i(6, 4), "multiplier", 0)
	sim.place(Vector2i(8, 4), "splitter", 2)
	sim.at(Vector2i(8, 4)).filters = [2, -1, 6, 0]
	sim.at(Vector2i(8, 4)).mode = 2
	sim.at(Vector2i(8, 4)).ratio = 3
	sim.place(Vector2i(10, 4), "logistics", 0)
	sim.at(Vector2i(10, 4)).outputs = [2, 3, 5, 6, 7, 11, 13, 17]
	sim._add_fixed("source", Vector2i(2, 9), 2)
	sim._add_fixed("research", Vector2i(6, 9))
	inject(sim, Vector2i(2, 4), 12)
	inject(sim, Vector2i(4, 4), 6, 1)
	sim.at(Vector2i(6, 4)).inputs = [2, 3]
	sim.at(Vector2i(6, 4)).output = 6
	sim.emitted += 4
	var ids = BuildLayout.in_region(sim, Rect2i(1, 3, 12, 9))
	verify(ids.size() == 6, "Box selection includes both crossing layers and excludes fixed facilities")
	verify(BuildLayout.in_region(sim, Rect2i(11, 5, 1, 1)) == ["10,4"], "Selecting part of a 2x2 station selects the complete station")
	var nodes = BuildLayout.copy(sim, ids)
	verify(BuildLayout.bounds(nodes) == Rect2i(0, 0, 10, 2), "Clipboard has normalized compact bounds")
	for node in nodes:
		for runtime in ["item", "output", "inputs", "input_dirs", "progress", "age", "cursor", "budget", "charges", "log_recent"]:
			verify(not node.has(runtime), "Clipboard excludes live material and simulation state: " + runtime)
	var rotated = nodes.duplicate(true)
	for i in range(4): rotated = BuildLayout.rotate(rotated)
	verify(rotated == nodes, "Four rotations restore every coordinate and directional configuration")
	rotated = BuildLayout.rotate(nodes)
	verify(BuildLayout.bounds(rotated).size == Vector2i(2, 10), "Rotation handles rectangular blueprint bounds")
	for node in rotated:
		if node.kind == "splitter": verify(node.filters == [0, 2, -1, 6] and node.dir == 3 and node.ratio == 3, "Splitter filters and primary direction rotate together")
		if node.kind == "logistics": verify(node.outputs == [13, 17, 3, 2, 5, 6, 11, 7], "Eight logistics filters rotate with physical sockets")
	var mass = sim.total_mass()
	var world = sim.world.serialize()
	var plan = BuildLayout.plan(sim, nodes, Vector2i(2, 14))
	verify(plan.valid, "A complete mixed blueprint can be placed together")
	verify(BuildLayout.apply(sim, plan.before, plan.after).is_empty(), "Atomic mixed-device placement succeeds")
	for node in plan.nodes:
		var entity = sim.entities[BuildLayout.identity(node)]
		verify(BuildLayout.config(entity) == node, "Placed configuration matches clipboard")
		verify(FactorySim.mass_of(entity) == 0 and entity.progress == 0, "Copied device is empty and starts unprocessed")
	verify(sim.total_mass() == mass and sim.world.serialize() == world, "Copying does not clone resources, progress or quotas")
	verify(sim.total_mass() == sim.emitted, "Mixed original and copied factory conserves material")
	var blocked = BuildLayout.plan(sim, nodes, Vector2i(2, 14))
	verify(blocked.valid, "Identical existing blueprint is harmless and accepted")
	var snapshot = sim.serialize()
	var over_quota = BuildLayout.plan(sim, nodes, Vector2i(12, 14))
	verify(not over_quota.valid and sim.serialize() == snapshot, "Over-quota or out-of-bounds blueprint never partially places")
	var fixed = [{"kind": "multiplier", "pos": Vector2i.ZERO, "dir": 0}]
	var warehouse = nodes.filter(func(node): return node.kind == "logistics")[0].duplicate(true)
	warehouse.pos = Vector2i.ZERO
	var quota_plan = BuildLayout.plan(sim, [warehouse], Vector2i(15, 12))
	verify(not quota_plan.valid and quota_plan.reason.contains("额度"), "Whole-station copy cannot exceed the global building quota")
	verify(not BuildLayout.plan(sim, fixed, Vector2i(2, 9)).valid, "Ore cannot be overwritten at its anchor")
	verify(not BuildLayout.plan(sim, fixed, Vector2i(3, 10)).valid, "Ore cannot be overwritten at an interior cell")
	verify(not BuildLayout.plan(sim, fixed, Vector2i(6, 9)).valid, "Research cannot be overwritten")
	var copy = WorldSim.new()
	var real = WorldSim.new(42)
	var initial = BuildLayout.copy(real, BuildLayout.in_region(real, Rect2i(-12, -8, 24, 16)))
	var real_plan = BuildLayout.plan(real, initial, Vector2i(3, 5))
	verify(real_plan.valid and BuildLayout.apply(real, real_plan.before, real_plan.after).is_empty(), "Copy ordinary construction in a seeded infinite world")
	verify(copy.restore(JSON.parse_string(JSON.stringify(real.serialize()))), "Pasted construction is saved through the normal game format")

func test_history():
	var sim = fixture()
	var history = BuildHistory.new()
	history.begin(sim, "line")
	for x in range(3, 8):
		history.watch(Vector2i(x, 6))
		sim.build_belt(Vector2i(x, 6), 0, 2)
	history.commit()
	verify(history.undo_stack.size() == 1, "An entire drag records one action")
	inject(sim, Vector2i(7, 6), 12)
	for i in range(4): sim.tick()
	var elapsed = sim.elapsed
	var world = sim.world.serialize()
	verify(history.undo().is_empty() and sim.entities.is_empty(), "Undo removes the complete newly built line")
	verify(sim.discarded == 3 and sim.total_mass() == sim.emitted, "Undo accounts for live materials without rewinding production")
	verify(sim.elapsed == elapsed and sim.world.serialize() == world, "Undo preserves simulation time and all progression")
	verify(history.redo().is_empty() and sim.entities.size() == 5, "Redo restores the complete line")
	verify(sim.at(Vector2i(7, 6)).item == 0 and sim.total_mass() == sim.emitted, "Redo does not duplicate removed material")
	inject(sim, Vector2i(4, 6), 6)
	history.begin(sim, "rotate")
	history.watch(Vector2i(4, 6))
	sim.redirect_belt(Vector2i(4, 6), 1)
	history.commit()
	var before_live = sim.at(Vector2i(4, 6)).duplicate(true)
	verify(history.undo().is_empty() and sim.at(Vector2i(4, 6)).dir == 0, "Undo configuration preserves the same live entity")
	verify(sim.at(Vector2i(4, 6)).item == before_live.item and sim.at(Vector2i(4, 6)).age == before_live.age, "Live cargo and age are not rolled back by undo")
	history.begin(sim, "new edit")
	history.watch(Vector2i(9, 6))
	sim.place(Vector2i(9, 6), "multiplier", 0)
	history.commit()
	verify(history.redo_stack.is_empty(), "New construction clears the redo branch")
	var node = [{"kind": "belt", "pos": Vector2i.ZERO, "dir": 1, "entry": 3, "layer": 0}]
	var crossing = fixture()
	crossing.build_belt(Vector2i(10, 10), 0, 2)
	inject(crossing, Vector2i(10, 10), 6)
	var original = crossing.at(Vector2i(10, 10)).duplicate(true)
	var plan = BuildLayout.plan(crossing, node, Vector2i(10, 10))
	verify(plan.valid and plan.nodes[0].layer == 1, "Pasted straight belts automatically cross older straight lines underground")
	history.attach(crossing)
	history.begin(crossing, "paste tunnel")
	history.watch(Vector2i(10, 10))
	verify(BuildLayout.apply(crossing, plan.before, plan.after).is_empty(), "Place blueprint on the independent underground layer")
	history.commit()
	inject(crossing, Vector2i(10, 10), 10, 1)
	verify(history.undo().is_empty() and crossing.at(Vector2i(10, 10), 1).is_empty(), "Undo pasted crossing removes only its new lane")
	verify(crossing.at(Vector2i(10, 10)) == original and crossing.total_mass() == crossing.emitted, "Older lane and live material survive crossing undo")
	verify(history.redo().is_empty() and crossing.at(Vector2i(10, 10), 1).item == 0, "Redo crossing is empty and conserves resources")
	var bend = fixture()
	bend.build_belt(Vector2i(10, 10), 0, 3)
	verify(not BuildLayout.plan(bend, node, Vector2i(10, 10)).valid, "Blueprint cannot tunnel through an old bend")
	var station_sim = fixture()
	station_sim.place(Vector2i(5, 5), "logistics", 0)
	station_sim.at(Vector2i(5, 5)).outputs = [2, 3, 5, 6, 7, 11, 13, 17]
	station_sim.world.logistics_stock = {"6": 8}
	station_sim.emitted += 16
	history.attach(station_sim)
	history.begin(station_sim, "erase warehouse")
	history.watch(Vector2i(6, 6))
	station_sim.remove(Vector2i(6, 6))
	history.commit()
	verify(history.undo().is_empty() and station_sim.logistics_used() == 1, "Undo deletion restores the whole 2x2 station from an interior selection")
	verify(station_sim.at(Vector2i(5, 5)).outputs[7] == 17 and station_sim.world.logistics_stock == {"6": 8}, "Restoring a station retains configuration without copying its shared bank")
	verify(station_sim.total_mass() == station_sim.emitted, "Station undo preserves the global inventory ledger")
	var mined = fixture()
	mined._add_fixed("source", Vector2i(2, 6), 2)
	history.attach(mined)
	history.begin(mined, "single outlet")
	history.watch(Vector2i(4, 6))
	mined.place(Vector2i(4, 6), "belt", 0)
	history.commit()
	for i in range(20): mined.tick()
	verify(mined.at(Vector2i(4, 6)).item == 2 and mined.at(Vector2i(4, 6)).entry == 2, "First real delivery infers the initially unspecified entry side")
	verify(history.undo().is_empty() and mined.at(Vector2i(4, 6)).is_empty() and mined.total_mass() == mined.emitted, "Live entry inference cannot prevent undoing a placed conveyor")
	verify(history.redo().is_empty() and mined.at(Vector2i(4, 6)).item == 0, "Redo after inferred-entry removal does not copy ore")
	var stale = fixture()
	history.attach(stale)
	history.begin(stale, "build")
	history.watch(Vector2i(8, 8))
	stale.place(Vector2i(8, 8), "belt", 0)
	history.commit()
	stale.redirect_belt(Vector2i(8, 8), 2)
	var unchanged = stale.serialize()
	verify(not history.undo().is_empty() and stale.serialize() == unchanged and history.undo_stack.size() == 1, "Stale history fails atomically and remains available")
	var many = FactorySim.new(false)
	history.attach(many)
	for i in range(BuildHistory.LIMIT + 4):
		var p = Vector2i(i % 18, i / 18)
		history.begin(many, "place")
		history.watch(p)
		many.place(p, "belt", 0)
		history.commit()
	verify(history.undo_stack.size() == BuildHistory.LIMIT, "Undo history has a bounded memory limit")
	for i in range(BuildHistory.LIMIT): verify(history.undo().is_empty(), "Every retained history step can undo")
	verify(many.entities.size() == 4, "History limit preserves older unrecorded construction")
	history.clear()
	verify(history.undo_stack.is_empty() and history.redo_stack.is_empty() and not history.active, "History can be reset for a new world")

func reset_scene():
	scene._set_tool("select")
	scene.sim = fixture()
	scene.board.sim = scene.sim
	scene.history.attach(scene.sim)
	scene.group_selection.clear()
	scene.clipboard_nodes.clear()
	scene.selected = scene.NONE_CELL
	scene.camera.position = Vector2(10, 10) * 40
	scene.view_zoom = 1.0
	scene.camera.zoom = Vector2.ONE
	scene._layout()
	scene.camera.force_update_scroll()
	scene._refresh_selection()

func screen(cell: Vector2i) -> Vector2:
	return scene.board.get_global_transform_with_canvas() * ((Vector2(cell) + Vector2.ONE * 0.5) * 40)

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

func key(code: int, ctrl: bool = false, shift: bool = false):
	var event = InputEventKey.new()
	event.pressed = true
	event.keycode = code
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	scene._unhandled_input(event)

func test_ui():
	reset_scene()
	scene._set_tool("belt")
	press(Vector2i(5, 8))
	drag(Vector2i(9, 8))
	drag(Vector2i(9, 10))
	release()
	verify(scene.history.undo_stack.size() == 1 and scene.sim.entities.size() == 7, "Mouse drag commits one undoable seven-cell route")
	inject(scene.sim, Vector2i(9, 10), 6)
	key(KEY_Z, true)
	verify(scene.sim.entities.is_empty() and scene.sim.total_mass() == scene.sim.emitted, "Ctrl+Z undoes a live route without duplicating resources")
	key(KEY_Y, true)
	verify(scene.sim.entities.size() == 7 and scene.sim.at(Vector2i(9, 10)).item == 0, "Ctrl+Y recreates the complete route empty")
	scene._set_tool("select")
	press(Vector2i(5, 8))
	drag(Vector2i(9, 10))
	verify(scene.box_selecting and scene.board.selection_area.has_area(), "Dragging the selection tool shows a marquee")
	release()
	verify(scene.group_selection.size() == 7 and scene.inspector_title.text.contains("7"), "Mouse release selects the complete group")
	verify(scene.rotation_buttons.all(func(button): return button.disabled), "Placed groups disable single-device rotation controls")
	var previous_direction = scene.direction
	key(KEY_R)
	verify(scene.direction == previous_direction, "R on a placed group leaves the build direction unchanged")
	key(KEY_C, true)
	verify(scene.clipboard_nodes.size() == 7 and not scene.edit_buttons.paste.disabled, "Ctrl+C copies selected layout and enables paste")
	key(KEY_V, true)
	verify(scene.pasting and scene.tool == "select", "Ctrl+V enters placement preview")
	verify(scene.rotation_buttons.all(func(button): return not button.disabled), "Blueprint preview enables whole-layout rotation controls")
	key(KEY_R)
	verify(BuildLayout.bounds(scene.clipboard_nodes).size == Vector2i(3, 5), "R rotates the entire rectangular clipboard")
	scene._preview_paste(Vector2i(12, 8))
	verify(scene.board.blueprint_valid and scene.board.blueprint_nodes.size() == 7, "Preview includes every rotated device")
	press(Vector2i(12, 8))
	release()
	verify(scene.sim.entities.size() == 14 and scene.history.undo_stack.size() == 2, "One click pastes the whole group as one action")
	var before = scene.sim.serialize()
	verify(not scene._place_blueprint(Vector2i(18, 22)) and scene.sim.serialize() == before, "Invalid full blueprint cannot partially place from UI")
	key(KEY_Z, true)
	verify(scene.sim.entities.size() == 7, "Undo removes only the last pasted group")
	key(KEY_Z, true, true)
	verify(scene.sim.entities.size() == 14, "Ctrl+Shift+Z redoes a pasted group")
	key(KEY_ESCAPE)
	verify(not scene.pasting and scene.board.blueprint_nodes.is_empty() and scene.clipboard_nodes.size() == 7, "Escape cancels preview while retaining copied layout")
	scene._select_box(Rect2i(12, 8, 3, 5))
	key(KEY_DELETE)
	verify(scene.sim.entities.size() == 7, "Delete removes the selected batch")
	key(KEY_Z, true)
	verify(scene.sim.entities.size() == 14, "Undo restores the complete batch deletion")
	reset_scene()
	scene.sim.place(Vector2i(10, 10), "splitter", 0)
	scene._paint(Vector2i(10, 10))
	inject(scene.sim, Vector2i(10, 10), 6)
	scene._set_splitter_mode(2)
	scene._edit_setting("filters", 12, 0)
	key(KEY_Z, true)
	verify(scene.sim.at(Vector2i(10, 10)).filters[0] == 0 and scene.sim.at(Vector2i(10, 10)).item == 6, "Undo a filter edit retains the live buffered product")
	key(KEY_Z, true)
	verify(scene.sim.at(Vector2i(10, 10)).mode == 0 and scene.mode_input.selected == 0, "Undo mode updates the inspector and configuration together")
	for size in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = size
		scene._layout()
		await process_frame
		for button in scene.edit_buttons.values():
			verify(scene.root.get_node("Bottom").get_global_rect().encloses(button.get_global_rect()), "Copy/paste/undo/redo buttons fit within toolbar at %s" % size)
	verify(scene.sim.total_mass() == scene.sim.emitted, "Construction workflow preserves the material ledger")
	var field = LineEdit.new()
	field.custom_minimum_size = Vector2(100, 30)
	scene.root.add_child(field)
	await process_frame
	field.grab_focus()
	var actions = scene.history.undo_stack.size()
	key(KEY_Z, true)
	verify(scene.history.undo_stack.size() == actions, "Text editing keeps its own Ctrl+Z instead of undoing factory construction")
	press(Vector2i(10, 10))
	release()
	verify(get_root().gui_get_focus_owner() != field, "Clicking the board releases text focus for factory shortcuts")
	field.queue_free()

func run():
	var original_size = root.size
	test_copy_rotation()
	test_history()
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.paused = true
	await process_frame
	await test_ui()
	if "--visual" in OS.get_cmdline_user_args():
		root.size = original_size
		await visual()
	print("Build tools: %d checks, %d failures" % [checks, failures.size()])
	for message in failures: push_error(message)
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func visual():
	reset_scene()
	scene.set_process(false)
	scene.sim.place(Vector2i(7, 8), "multiplier", 0)
	for row in [[Vector2i(5, 8), 0, 2], [Vector2i(6, 8), 0, 2], [Vector2i(7, 6), 1, 3], [Vector2i(7, 7), 1, 3], [Vector2i(8, 8), 0, 2], [Vector2i(9, 8), 0, 2], [Vector2i(11, 8), 0, 2]]:
		scene.sim.build_belt(row[0], row[1], row[2])
	scene.sim.place(Vector2i(10, 8), "splitter", 0)
	scene._select_box(Rect2i(5, 6, 7, 3))
	scene.board.selected = scene.selected
	await capture("selected")
	var baseline = root.get_texture().get_image()
	scene._copy_selection()
	scene._start_paste()
	scene._rotate()
	var anchor = Vector2i(13, 9)
	scene._preview_paste(anchor)
	scene.toast_time = 0
	scene._refresh()
	await capture("preview")
	var image = root.get_texture().get_image()
	var node = scene.clipboard_nodes.filter(func(e): return e.kind == "multiplier")[0]
	var point = Vector2i(screen(node.pos + anchor))
	var color = image.get_pixelv(point)
	var previous = baseline.get_pixelv(point)
	verify(absf(color.r - previous.r) + absf(color.g - previous.g) + absf(color.b - previous.b) > 0.02, "Placement ghost draws visible device pixels at its actual target")
	scene._preview_paste(Vector2i(19, 10))
	scene._refresh()
	await capture("blocked")
	verify(not scene.board.blueprint_valid and scene.inspector_status.text.contains("开放"), "Locked blueprint is red and explains its placement failure")
	scene._place_blueprint(anchor)
	scene._set_tool("select")
	scene._select_box(Rect2i(anchor, BuildLayout.bounds(scene.clipboard_nodes).size))
	await capture("pasted")
	verify(scene.history.undo_stack.size() == 1, "Visual paste is one undoable batch")

func capture(name: String):
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://qa")
	image.save_png("res://qa/build_tools_%s_%dx%d.png" % [name, image.get_width(), image.get_height()])
	verify(not image.is_empty(), "Rendered construction tools: " + name)
