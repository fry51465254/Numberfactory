extends SceneTree

var failures: Array = []
var checks = 0

func _initialize():
	call_deferred("run")

func verify(condition: bool, message: String):
	checks += 1
	if not condition: failures.append(message)

func run():
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.paused = true
	await process_frame
	for size in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = size
		await process_frame
		scene._layout()
		verify(scene.workspace.size.x > 700 and scene.workspace.size.y > 600, "Workspace remains usable at %s" % size)
		verify(scene.root.get_node("Bottom").position.y >= scene.root.get_node("Left").position.y + scene.root.get_node("Left").size.y, "Sidebar does not overlap toolbar")
	scene.buttons.multiplier.emit_signal("pressed")
	verify(scene.tool == "multiplier" and scene.inspector_detail.text.contains("输入 A"), "Multiplier tool shows its ports without recipe controls")
	scene._paint(Vector2i(8, 8))
	verify(scene.sim.at(Vector2i(8, 8)).kind == "multiplier" and not scene.sim.at(Vector2i(8, 8)).has("a"), "Build tool places adaptive machine")
	scene._set_tool("select")
	scene._paint(Vector2i(8, 8))
	verify(scene.inspector_title.text == "乘法机", "Selection shows correct inspector")
	scene._rotate()
	verify(scene.sim.at(Vector2i(8, 8)).dir == 1, "Selected machine rotates")
	var machine = scene.sim.at(Vector2i(8, 8))
	machine.inputs = [6, 3]
	scene._refresh()
	verify(scene.inspector_detail.text.contains("6 × 3 = 18") and scene.inspector_status.text.contains("加工中"), "Inspector previews the actual input pair")
	for i in range(30): scene.sim.tick()
	scene._refresh()
	verify(machine.output == 18 and scene.inspector_detail.text.contains("上次  6 × 3 = 18"), "Inspector preserves the last automatic calculation")
	machine.inputs = [999999, 2]
	machine.output = 0
	scene._refresh()
	verify(scene.inspector_status.text.contains("乘积超出 999999"), "Inspector explains overflow blockage")
	machine.inputs = [0, 5]
	scene._refresh()
	verify(scene.inspector_status.text.contains("等待输入 A"), "Inspector identifies the missing input port")
	scene._set_tool("belt")
	scene.direction = 0
	scene._paint(Vector2i(8, 10))
	verify(scene.sim.at(Vector2i(8, 10)).kind == "belt", "Belt placement works")
	scene.painting = true
	var release = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	scene._input(release)
	verify(not scene.painting, "Mouse release over UI ends painting")
	scene._set_tool("erase")
	scene._paint(Vector2i(8, 10))
	verify(scene.sim.at(Vector2i(8, 10)).is_empty(), "Erase tool works")
	scene.sim.place(Vector2i(9, 10), "splitter", 0)
	scene._set_tool("select")
	scene._paint(Vector2i(9, 10))
	verify(scene.mode_input.is_item_disabled(1) and scene.mode_input.is_item_disabled(2), "Research locks enforced in inspector")
	for technology in ["ratio", "filter"]:
		for value in scene.sim.world.tech_costs[technology]:
			scene.sim.world.deposit(int(value), scene.sim.world.tech_costs[technology][value])
		verify(scene.sim.world.research_tech(technology), "Pay new-world research for inspector unlock")
	scene._refresh()
	verify(not scene.mode_input.is_item_disabled(2), "Research unlock reflected in UI")
	scene.mode_input.item_selected.emit(2)
	verify(scene.sim.at(Vector2i(9, 10)).mode == 2, "Filter command works")
	scene.sim.place(Vector2i(10, 10), "belt", 0)
	scene._refresh()
	scene.filter_ports[0].selector.select(1)
	scene.filter_ports[0].selector.item_selected.emit(1)
	scene.filter_ports[0].number.value = 18
	verify(scene.sim.at(Vector2i(9, 10)).filters[0] == 18, "Per-direction filter updates selected machine")
	scene.pause_button.emit_signal("pressed")
	verify(not scene.paused, "Pause command resumes simulation")
	scene.pause_button.emit_signal("pressed")
	verify(scene.paused, "Pause command stops simulation")
	verify(scene.expansion_label.text.contains("下一圈矿点"), "Expansion shows mineral rewards before payment")
	verify(scene.seed_input.get_parent().get_child(0).text.contains("将被清空"), "New-world confirmation keeps destructive warning visible above seed")
	for prime in [5, 7]:
		while not scene.sim.world.prime_ready():
			var cost = scene.sim.world.expansion_cost
			for value in cost: scene.sim.world.deposit(int(value), int(cost[value]))
			scene.sim.world.expand()
		for value in scene.sim.world.prime_cost: scene.sim.world.deposit(int(value), int(scene.sim.world.prime_cost[value]))
		verify(scene.sim.world.research_prime(), "Pay prime gate for logistics UI fixture %d" % prime)
	for value in scene.sim.world.tech_costs.logistics: scene.sim.world.deposit(int(value), int(scene.sim.world.tech_costs.logistics[value]))
	verify(scene.sim.world.research_tech("logistics"), "Logistics UI fixture pays technology")
	scene._refresh()
	verify(not scene.buttons.logistics.disabled and scene.sim.world.logistics_capacity == 2, "Logistics tool unlocks with only two initial quotas")
	scene._set_tool("logistics")
	var station = Vector2i(-4, 0)
	scene._paint(station)
	verify(scene.sim.at(station).kind == "logistics", "UI places logistics station")
	scene._set_tool("belt")
	scene.direction = 0
	scene._paint(station + Vector2i(2, 0))
	verify(scene.sim.at(station + Vector2i(2, 0)).dir == 0, "New station output belt not forcibly snapped inward")
	scene.direction = 0
	scene._paint(station + Vector2i(0, 2))
	verify(scene.sim.at(station + Vector2i(0, 2)).dir == 0, "Parallel station belt keeps direction and stays disconnected")
	scene._set_tool("select")
	scene._paint(station)
	scene.logistics_fields[0].field.value = 18
	verify(scene.sim.at(station).outputs[0] == 18, "Manual numeric output field configures selected port")
	verify(scene.logistics_fields[0].label.text.contains("输出"), "Output port detected in logistics inspector")
	for slot in range(8):
		var location = station + WorldSim.LOG_PORTS[slot]
		scene.sim.remove(location)
		verify(scene.sim.place(location, "belt", int(slot / 2)), "Connect all eight output ports for maximum inspector density")
	scene._refresh_selection()
	for size in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = size
		scene._layout()
		for port in scene.logistics_fields: port.field.value = 999999
		await process_frame
		var right_scroll = scene.logistics_box.get_parent().get_parent()
		var previous_end = -INF
		for port in scene.logistics_fields:
			var rect = port.field.get_global_rect()
			verify(rect.position.y >= previous_end, "Logistics numeric fields never overlap at %s" % size)
			verify(rect.position.x >= right_scroll.get_global_rect().position.x and rect.end.x <= right_scroll.get_global_rect().end.x, "Logistics output stays within sidebar at %s" % size)
			var input = port.field.get_line_edit()
			verify(input.get_theme_font("font").get_string_size("999999", HORIZONTAL_ALIGNMENT_LEFT, -1, input.get_theme_font_size("font_size")).x < input.size.x - 20, "Full-range output number fits its editable field")
			previous_end = rect.end.y
		right_scroll.scroll_vertical = 1000000
		await process_frame
		verify(right_scroll.get_global_rect().intersects(scene.logistics_fields[-1].field.get_global_rect()), "Last output port remains reachable by scrolling")
		right_scroll.scroll_vertical = 0
	scene.sim.remove(station + Vector2i(2, 0))
	scene._set_tool("belt")
	scene.painting = true
	scene._begin_stroke(station + Vector2i.RIGHT)
	scene._drag_to(station + Vector2i(3, 0))
	verify(scene.sim.at(station + Vector2i(2, 0)).dir == 0 and scene.sim.at(station + Vector2i(3, 0)).dir == 0, "Dragging outward from station builds output route")
	scene._end_stroke()
	scene._fit_map()
	var fit_zoom = scene.view_zoom
	var wheel = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.position = scene.workspace.get_center()
	wheel.pressed = true
	scene._unhandled_input(wheel)
	verify(scene.view_zoom < fit_zoom, "Zooming out after grown-map overview cannot jump inward")
	var before_invalid_seed = scene.sim.serialize()
	scene.save_blocked = true
	scene._save(true)
	verify(scene.status_label.text.contains("原文件已保留"), "Invalid player save cannot be silently overwritten")
	scene.seed_input.text = "not-a-seed"
	verify(not scene._new_world() and scene.sim.serialize() == before_invalid_seed, "Invalid seed cannot erase the existing factory")
	verify(scene.save_blocked, "Invalid seed cannot bypass damaged-save protection")
	scene.seed_input.text = "999999999999999999999999999999999999"
	verify(scene._new_world() and scene.sim.world.seed_value == WorldProgress.MAX_SEED, "Oversized numeric seed clamps before integer conversion")
	verify(not scene.paused and scene.view_zoom == 0.9 and scene.tool == "select", "New world restores usable camera, tool and running state")
	verify(not scene.save_blocked and scene.accumulator == 0.0 and scene.autosave == 0.0, "Confirmed new world resets save protection and previous timing")
	verify(scene.camera.offset.is_equal_approx(-(scene.workspace.get_center() - scene.get_viewport_rect().size / 2) / scene.view_zoom), "New-world camera offset matches its reset zoom")
	scene.status_label.text = "QA save sentinel"
	scene._save(true)
	verify(scene.status_label.text == "QA save sentinel", "QA UI saving never touches the player's persistent save")
	_test_assets()
	print("Interface/assets: %d checks, %d failures" % [checks, failures.size()])
	for message in failures: push_error(message)
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _test_assets():
	var font = load("res://assets/fonts/interface.tres")
	verify(font.base_font is FontFile and not font.base_font.allow_system_fallback, "Chinese font is bundled without system fallback")
	for character in "质数研究扩张物流库存暂停":
		verify(font.has_char(character.unicode_at(0)), "Bundled font contains %s" % character)
	for name in ["floor", "belt", "belt_turn", "source", "multiplier", "splitter", "research", "exploration", "hub"]:
		var path = "res://assets/textures/%s.png" % BoardView.TEXTURE_FILES.get(name, name)
		verify(ResourceLoader.exists(path), "Texture available: %s" % name)
		if not ResourceLoader.exists(path): continue
		var texture = load(path)
		var image = texture.get_image()
		verify(not image.is_empty(), "Texture decodes: %s" % name)
		if name != "floor":
			verify(image.get_pixel(0, 0).a < 0.01, "Actual transparent corner: %s" % name)
			verify(texture.get_image().has_mipmaps(), "Mipmaps for small sprite readability: %s" % name)
		else:
			var seam = 0.0
			for i in range(40):
				var x = i * (image.get_width() - 1) / 39
				var y = i * (image.get_height() - 1) / 39
				seam += absf(image.get_pixel(x, 0).r - image.get_pixel(x, image.get_height() - 1).r)
				seam += absf(image.get_pixel(0, y).r - image.get_pixel(image.get_width() - 1, y).r)
			verify(seam / 80 < 0.05, "Floor opposite edges match in tone")
