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
	scene.sim.delivered.research = 60
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
	_test_assets()
	print("Interface/assets: %d checks, %d failures" % [checks, failures.size()])
	for message in failures: push_error(message)
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _test_assets():
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
