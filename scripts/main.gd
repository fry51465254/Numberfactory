extends Node2D

const TITLES = {"source": "质数矿点", "belt": "传送带", "multiplier": "乘法机", "splitter": "分流器", "research": "研究站", "exploration": "探索站", "hub": "中央枢纽", "logistics": "物流站"}
const NONE_CELL = Vector2i(-1000000000, -1000000000)
const MIN_ZOOM = 0.02
var sim = WorldSim.new()
var board: BoardView
var camera: Camera2D
var ui: CanvasLayer
var root: Control
var workspace: Rect2
var accumulator = 0.0
var paused = false
var save_blocked = false
var autosave = 0.0
var refresh_timer = 0.0
var selected = NONE_CELL
var tool = "select"
var direction = 0
var painting = false
var panning = false
var last_paint = Vector2i(-1, -1)
var reverse_belt_drag = false
var stroke_layer = 0
var stroke_start_pending = false
var stroke_reverse_requested = false
var stroke_cells: Array = []
var stroke_undo: Array = []
var stroke_origin_geometry: Dictionary = {}
var stroke_retracted = false
var stroke_press_screen = Vector2.ZERO
var pause_button: Button
var status_label: Label
var inspector_title: Label
var inspector_status: Label
var inspector_detail: Label
var splitter_box: VBoxContainer
var mode_input: OptionButton
var ratio_input: SpinBox
var ratio_box: VBoxContainer
var filter_ports: Array = []
var primary_output: OptionButton
var underground_box: VBoxContainer
var goal_labels: Dictionary = {}
var goal_bars: Dictionary = {}
var rate_labels: Dictionary = {}
var buttons: Dictionary = {}
var complete_label: Label
var new_dialog: ConfirmationDialog
var last_unlock = false
var view_zoom = 0.9
var loading_ui = false
var toast_time = 0.0
var expansion_label: Label
var expansion_button: Button
var prime_label: Label
var prime_button: Button
var supply_label: Label
var tech_controls: Dictionary = {}
var seed_input: LineEdit
var logistics_box: VBoxContainer
var logistics_fields: Array = []
var problem_button: Button
var problem_cell = NONE_CELL
var research_feedback: AcceptDialog

func _ready():
	RenderingServer.set_default_clear_color(Color("edf0ef"))
	var args = OS.get_cmdline_user_args()
	if "--fresh" not in args and "--qa" not in args:
		if FileAccess.file_exists(SaveStore.PATH) and not SaveStore.load_game(sim):
			save_blocked = true
			push_warning("存档无法读取；保留原文件，新建世界后可重新保存。")
	paused = sim.session_paused
	board = BoardView.new()
	board.sim = sim
	add_child(board)
	camera = Camera2D.new()
	add_child(camera)
	camera.position = Vector2(-4 * 40, 0)
	camera.zoom = Vector2.ONE * view_zoom
	_build_ui()
	get_viewport().size_changed.connect(_layout)
	_layout()
	last_unlock = sim.unlocked()
	_refresh()
	if "--qa" in args and "--test" not in args:
		_run_visual_qa()

func _process(delta):
	if not paused:
		accumulator += minf(delta, 0.25)
		while accumulator >= FactorySim.STEP:
			sim.tick()
			accumulator -= FactorySim.STEP
	autosave += delta
	refresh_timer += delta
	toast_time = maxf(0, toast_time - delta)
	if autosave > 30 and "--qa" not in OS.get_cmdline_user_args():
		autosave = 0
		_save(false)
	if refresh_timer >= 0.2:
		refresh_timer = 0
		_refresh()
	board.selected = selected
	board.tool = tool
	board.direction = direction
	var mouse = get_viewport().get_mouse_position()
	board.hover = _cell(mouse) if workspace.has_point(mouse) else NONE_CELL

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if "--qa" not in OS.get_cmdline_user_args():
			_save(false)
		get_tree().quit()

func _build_ui():
	ui = CanvasLayer.new()
	add_child(ui)
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	var theme = Theme.new()
	var font = load("res://assets/fonts/interface.tres")
	theme.default_font = font
	theme.default_font_size = 14
	theme.set_color("font_color", "Label", Color("283d36"))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style = StyleBoxFlat.new()
		style.bg_color = Color("f9fbfa") if state == "normal" else Color("e1eeea") if state == "hover" else Color("c8e5db") if state == "pressed" else Color("edf0ef")
		style.border_color = Color("cad8d1")
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		style.content_margin_left = 12
		style.content_margin_right = 12
		style.content_margin_top = 7
		style.content_margin_bottom = 7
		theme.set_stylebox(state, "Button", style)
		theme.set_color("font_%s_color" % state if state != "normal" else "font_color", "Button", Color("29463a"))
	var field_style = StyleBoxFlat.new()
	field_style.bg_color = Color.WHITE
	field_style.border_color = Color("cad8d1")
	field_style.set_border_width_all(1)
	field_style.set_corner_radius_all(3)
	field_style.content_margin_left = 8
	field_style.content_margin_top = 7
	field_style.content_margin_bottom = 7
	theme.set_stylebox("normal", "LineEdit", field_style)
	var readonly_style = field_style.duplicate()
	readonly_style.bg_color = Color("edf2ef")
	theme.set_stylebox("read_only", "LineEdit", readonly_style)
	theme.set_color("font_color", "LineEdit", Color("283d36"))
	theme.set_color("font_uneditable_color", "LineEdit", Color("81958a"))
	root.theme = theme

	var top = _panel("Top", Color("fbfcfb"))
	var top_row = HBoxContainer.new()
	top_row.position = Vector2(24, 12)
	top_row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_row.offset_left = 24
	top_row.offset_top = 12
	top_row.offset_right = -24
	top_row.offset_bottom = 54
	top_row.add_theme_constant_override("separation", 12)
	top.add_child(top_row)
	var title = _label("质数工厂", 22)
	top_row.add_child(title)
	var edition = _label("无限实验室", 12, Color("72877b"))
	edition.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_row.add_child(edition)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(spacer)
	complete_label = _label("", 14, Color("159486"))
	complete_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_row.add_child(complete_label)
	pause_button = _button("", "暂停 / 恢复", func():
		paused = not paused
		pause_button.icon = _icon("play" if paused else "pause")
		_refresh())
	pause_button.icon = _icon("play" if paused else "pause")
	top_row.add_child(pause_button)
	var save = _button("", "保存工厂", func(): _save(true))
	save.icon = _icon("save")
	top_row.add_child(save)
	var restart = _button("", "新建工厂", func(): new_dialog.popup_centered())
	restart.icon = _icon("restart")
	top_row.add_child(restart)

	var left = _panel("Left", Color("f7faf8"))
	var goal_scroll = ScrollContainer.new()
	goal_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	goal_scroll.offset_left = 20
	goal_scroll.offset_right = -20
	goal_scroll.offset_top = 20
	goal_scroll.offset_bottom = -166
	goal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	goal_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	goal_scroll.follow_focus = true
	goal_scroll.name = "Goals"
	left.add_child(goal_scroll)
	var goals = VBoxContainer.new()
	goals.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	goals.add_theme_constant_override("separation", 13)
	goal_scroll.add_child(goals)
	goals.add_child(_label("地图扩张", 17))
	expansion_label = _label("", 13)
	expansion_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goals.add_child(expansion_label)
	expansion_button = _button("扩张一圈", "消耗研究库存，四周同时增加 8 格", func(): _research_action("expand"))
	expansion_button.icon = _icon("fit")
	goals.add_child(expansion_button)
	goals.add_child(HSeparator.new())
	goals.add_child(_label("质数研究", 17))
	prime_label = _label("", 13)
	prime_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goals.add_child(prime_label)
	prime_button = _button("", "消耗研究库存，主动解锁下一种质数", func(): _research_action("prime"))
	prime_button.icon = _icon("multiply")
	goals.add_child(prime_button)
	goals.add_child(HSeparator.new())
	goals.add_child(_label("科技", 17))
	for technology in WorldProgress.TECHS:
		var id = technology
		var label = _label("", 13)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		goals.add_child(label)
		var button = _button({"ratio": "比例分流", "filter": "数字筛选", "logistics": "共享物流"}[id], "研究科技", func(): _research_action(id))
		button.icon = _icon("check")
		goals.add_child(button)
		tech_controls[id] = {"label": label, "button": button}
	var footer = VBoxContainer.new()
	footer.name = "Summary"
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_left = 20
	footer.offset_right = -20
	footer.offset_top = -154
	footer.offset_bottom = -16
	footer.add_theme_constant_override("separation", 8)
	left.add_child(footer)
	footer.add_child(HSeparator.new())
	supply_label = _label("", 13, Color("61766b"))
	supply_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	supply_label.max_lines_visible = 4
	supply_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	footer.add_child(supply_label)
	var find = _button("研究站", "回到研究站", func(): _focus_cell(Vector2i.ZERO))
	find.icon = _icon("locate")
	footer.add_child(find)

	var right = _panel("Right", Color("f7faf8"))
	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 18
	scroll.offset_right = -18
	scroll.offset_top = 20
	scroll.offset_bottom = -18
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	right.add_child(scroll)
	var inspector = VBoxContainer.new()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.add_theme_constant_override("separation", 14)
	scroll.add_child(inspector)
	inspector_title = _label("设备", 17)
	inspector.add_child(inspector_title)
	inspector_status = _label("", 13, Color("64796d"))
	inspector_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector.add_child(inspector_status)
	inspector_detail = _label("", 13)
	inspector_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector.add_child(inspector_detail)
	problem_button = _button("定位阻塞", "定位实际阻塞设备或断点", func(): _focus_cell(problem_cell))
	problem_button.icon = _icon("locate")
	inspector.add_child(problem_button)
	splitter_box = VBoxContainer.new()
	splitter_box.add_theme_constant_override("separation", 10)
	inspector.add_child(splitter_box)
	mode_input = OptionButton.new()
	mode_input.add_item("交替分流")
	mode_input.add_item("比例分流")
	mode_input.add_item("数字筛选")
	mode_input.item_selected.connect(_set_splitter_mode)
	splitter_box.add_child(mode_input)
	ratio_box = VBoxContainer.new()
	ratio_box.add_theme_constant_override("separation", 6)
	splitter_box.add_child(ratio_box)
	ratio_box.add_child(_label("主输出方向", 13))
	primary_output = OptionButton.new()
	for name in ["东", "南", "西", "北"]: primary_output.add_item(name)
	primary_output.item_selected.connect(func(v):
		var e = sim.at(selected)
		if not loading_ui and not e.is_empty() and e.kind == "splitter": e.dir = v)
	ratio_box.add_child(primary_output)
	ratio_box.add_child(_label("主输出 : 各其他输出", 13))
	ratio_input = _spin(1, 9, 1)
	ratio_input.suffix = ": 1"
	ratio_input.value_changed.connect(func(v):
		var e = sim.at(selected)
		if not loading_ui and not e.is_empty() and e.kind == "splitter": e.ratio = int(v))
	ratio_box.add_child(ratio_input)
	for facing in range(4):
		var port_direction = facing
		var label = _label("", 13)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		splitter_box.add_child(label)
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		splitter_box.add_child(row)
		var selector = OptionButton.new()
		for name in ["全部数字", "指定数字", "其余数字"]: selector.add_item(name)
		selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(selector)
		var number = _spin(2, FactorySim.MAX_VALUE, 2)
		number.custom_minimum_size.x = 100
		row.add_child(number)
		selector.item_selected.connect(func(index):
			var e = sim.at(selected)
			if not loading_ui and not e.is_empty() and e.kind == "splitter":
				e.filters[port_direction] = 0 if index == 0 else -1 if index == 2 else int(number.value)
				_refresh())
		number.value_changed.connect(func(value):
			var e = sim.at(selected)
			if not loading_ui and not e.is_empty() and e.kind == "splitter" and selector.selected == 1:
				e.filters[port_direction] = int(value))
		filter_ports.append({"label": label, "row": row, "selector": selector, "number": number})
	underground_box = VBoxContainer.new()
	inspector.add_child(underground_box)
	var remove_under = _button("拆除地下通道", "保留地面带，仅清空并拆除地下通道", func():
		sim.remove_underground(selected)
		_refresh_selection())
	remove_under.icon = _icon("trash")
	underground_box.add_child(remove_under)
	logistics_box = VBoxContainer.new()
	inspector.add_child(logistics_box)
	for slot in range(8):
		var index = slot
		var label = _label("", 13)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		logistics_box.add_child(label)
		var field = _spin(0, FactorySim.MAX_VALUE, 0)
		field.tooltip_text = "输出数字；0 表示关闭该出口"
		field.value_changed.connect(func(value):
			var e = sim.at(selected)
			if not loading_ui and not e.is_empty() and e.kind == "logistics": e.outputs[index] = int(value) if value >= 2 else 0)
		logistics_box.add_child(field)
		logistics_fields.append({"label": label, "field": field})
	var rotate = _button("旋转", "顺时针旋转 · R", _rotate)
	rotate.icon = _icon("rotate")
	inspector.add_child(rotate)
	var erase = _button("拆除", "拆除设备并清空缓存物料", func():
		if sim.remove(selected):
			selected = NONE_CELL
			_refresh_selection())
	erase.icon = _icon("trash")
	inspector.add_child(erase)

	var bottom = _panel("Bottom", Color("fbfcfb"))
	var bottom_row = HBoxContainer.new()
	bottom_row.position = Vector2(18, 13)
	bottom_row.add_theme_constant_override("separation", 8)
	bottom.add_child(bottom_row)
	for item in [["select", "选择", "pointer"], ["belt", "传送带", "belt"], ["multiplier", "乘法机", "multiply"], ["splitter", "分流器", "split"], ["erase", "拆除", "trash"], ["logistics", "物流站", "locate"]]:
		var id = item[0]
		var button = _button(item[1], item[1], func(): _set_tool(id))
		if id == "belt": button.tooltip_text = "传送带 · 拖动铺设；Shift 反向铺带"
		button.icon = _icon(item[2])
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(103, 38)
		buttons[id] = button
		bottom_row.add_child(button)
	var rotate_button = _button("", "旋转 · R", _rotate)
	rotate_button.icon = _icon("rotate")
	bottom_row.add_child(rotate_button)
	var fit = _button("", "地图总览", _fit_map)
	fit.icon = _icon("fit")
	bottom_row.add_child(fit)
	status_label = _label("", 12, Color("64796d"))
	status_label.position = Vector2(20, 57)
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	status_label.offset_left = 20
	status_label.offset_right = -20
	status_label.offset_top = 57
	bottom.add_child(status_label)
	research_feedback = AcceptDialog.new()
	research_feedback.title = "条件不足"
	research_feedback.ok_button_text = "知道了"
	research_feedback.get_label().add_theme_color_override("font_color", Color("edf0ef"))
	root.add_child(research_feedback)
	new_dialog = ConfirmationDialog.new()
	new_dialog.title = "新建工厂"
	new_dialog.dialog_text = ""
	new_dialog.ok_button_text = "重新开始"
	new_dialog.cancel_button_text = "取消"
	var new_content = VBoxContainer.new()
	new_content.custom_minimum_size.x = 360
	new_content.add_theme_constant_override("separation", 12)
	new_content.add_child(_label("当前布局、库存与研究将被清空。", 14, Color("edf0ef")))
	new_content.add_child(_label("世界种子", 13, Color("edf0ef")))
	new_dialog.add_child(new_content)
	seed_input = LineEdit.new()
	seed_input.placeholder_text = "世界种子"
	seed_input.text = str(sim.world.seed_value)
	new_content.add_child(seed_input)
	new_dialog.register_text_enter(seed_input)
	new_dialog.confirmed.connect(_new_world)
	root.add_child(new_dialog)
	_set_tool("select")

func _new_world() -> bool:
	var text = seed_input.text.strip_edges()
	if not text.is_valid_int():
		_toast("种子必须是整数，当前工厂未改变")
		return false
	# Clamp before integer conversion, including text beyond the 64-bit range.
	var seed = int(clampf(float(text), WorldProgress.MIN_SEED, WorldProgress.MAX_SEED))
	sim.reset(seed)
	save_blocked = false
	selected = NONE_CELL
	paused = false
	accumulator = 0.0
	autosave = 0.0
	pause_button.icon = _icon("pause")
	view_zoom = 0.9
	camera.zoom = Vector2.ONE * view_zoom
	camera.position = Vector2(-160, 0)
	_layout()
	last_unlock = false
	_set_tool("select")
	_refresh_selection()
	_save(true)
	return true

func _panel(id: String, color: Color) -> Panel:
	var panel = Panel.new()
	panel.name = id
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("d4ded7")
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)
	return panel

func _column(parent: Control, margin: float) -> VBoxContainer:
	var column = VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = margin
	column.offset_top = margin
	column.offset_right = -margin
	column.offset_bottom = -margin
	column.add_theme_constant_override("separation", 15)
	parent.add_child(column)
	return column

func _label(text: String, size: int = 14, color: Color = Color("283d36")) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String, tip: String, action: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.tooltip_text = tip
	button.custom_minimum_size.y = 36
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	return button

func _icon(name: String) -> Texture2D:
	var path = "res://assets/icons/%s.svg" % name
	return load(path) if ResourceLoader.exists(path) else null

func _spin(min_value: int, max_value: int, value: int) -> SpinBox:
	var field = SpinBox.new()
	field.min_value = min_value
	field.max_value = max_value
	field.step = 1
	field.value = value
	field.custom_minimum_size = Vector2(0, 36)
	return field

func _layout():
	var size = get_viewport_rect().size
	var left_width = 244.0
	var right_width = 260.0
	root.get_node("Top").size = Vector2(size.x, 68)
	root.get_node("Left").position = Vector2(0, 68)
	root.get_node("Left").size = Vector2(left_width, size.y - 154)
	root.get_node("Right").position = Vector2(size.x - right_width, 68)
	root.get_node("Right").size = Vector2(right_width, size.y - 154)
	root.get_node("Bottom").position = Vector2(0, size.y - 86)
	root.get_node("Bottom").size = Vector2(size.x, 86)
	workspace = Rect2(left_width, 68, size.x - left_width - right_width, size.y - 154)
	camera.offset = -(workspace.get_center() - size / 2) / view_zoom

func _cell(screen: Vector2) -> Vector2i:
	var world = board.get_global_transform_with_canvas().affine_inverse() * screen
	return Vector2i(floori(world.x / 40), floori(world.y / 40))

func _input(event):
	# Release can be consumed by a UI control after a drag begins on the board.
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if painting:
				if stroke_start_pending and not stroke_retracted: _paint(last_paint)
				if tool == "belt" and not stroke_retracted and not reverse_belt_drag and stroke_layer == 0 and not sim.at(last_paint).is_empty() and sim.at(last_paint).kind == "belt":
					_snap_belt_to_input(last_paint)
			_end_stroke()
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = false

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_set_tool("select")
		elif event.keycode == KEY_R:
			_rotate()
		elif event.keycode == KEY_SPACE:
			paused = not paused
			pause_button.icon = _icon("play" if paused else "pause")
		elif event.keycode == KEY_S and event.ctrl_pressed:
			_save(true)
		elif event.keycode == KEY_DELETE:
			if sim.remove(selected): _refresh_selection()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_6:
			_set_tool(["select", "belt", "multiplier", "splitter", "erase", "logistics"][event.keycode - KEY_1])
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			painting = false
			last_paint = Vector2i(-1, -1)
		if event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
			panning = false
		if not workspace.has_point(event.position):
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var before = board.get_global_transform_with_canvas().affine_inverse() * event.position
			view_zoom = clampf(view_zoom * (1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1 / 1.12), MIN_ZOOM, 2.0)
			camera.zoom = Vector2.ONE * view_zoom
			_layout()
			camera.force_update_scroll()
			var after = board.get_global_transform_with_canvas().affine_inverse() * event.position
			camera.position += before - after
			camera.force_update_scroll()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_set_tool("select")
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if tool == "select":
				_end_stroke()
				_paint(_pick_cell(event.position))
			else:
				painting = true
				stroke_press_screen = event.position
				_begin_stroke(_cell(event.position), event.shift_pressed)
	if event is InputEventMouseMotion:
		if panning:
			camera.position -= event.relative / view_zoom
		elif painting and workspace.has_point(event.position):
			if stroke_start_pending and event.position.distance_to(stroke_press_screen) < minf(4.0, 8.0 * view_zoom): return
			var cell = _cell(event.position)
			if tool in ["belt", "erase"]:
				_drag_to(cell)
			elif cell != last_paint:
				_paint(cell)

func _pick_cell(screen: Vector2) -> Vector2i:
	var cell = _cell(screen)
	var exact = sim.at(cell)
	if not exact.is_empty() and exact.kind != "belt": return exact.pos
	var point = board.get_global_transform_with_canvas().affine_inverse() * screen
	var tolerance = minf(5.0 / view_zoom, 6.0)
	var best = cell
	var distance = tolerance
	for y in range(-1, 2):
		for x in range(-1, 2):
			var candidate = sim.at(cell + Vector2i(x, y))
			if candidate.is_empty() or candidate.kind == "belt": continue
			var size = 2 if candidate.kind in ["source", "research", "logistics"] else 1
			var rect = Rect2(Vector2(candidate.pos) * 40, Vector2.ONE * 40 * size)
			var nearest = point.clamp(rect.position, rect.end)
			var gap = point.distance_to(nearest)
			if gap < distance:
				distance = gap
				best = candidate.pos
	return best

func _focus_cell(cell: Vector2i):
	if cell == NONE_CELL: return
	view_zoom = maxf(view_zoom, 0.8)
	camera.zoom = Vector2.ONE * view_zoom
	var e = sim.at(cell)
	var size = 2 if not e.is_empty() and e.kind in ["source", "research", "logistics"] else 1
	camera.position = (Vector2(e.pos if not e.is_empty() else cell) + Vector2.ONE * size / 2.0) * 40
	_layout()
	camera.force_update_scroll()

func _begin_stroke(cell: Vector2i, reverse: bool = false):
	reverse_belt_drag = reverse
	stroke_reverse_requested = reverse
	stroke_layer = 0
	stroke_start_pending = false
	stroke_cells = [cell]
	stroke_undo.clear()
	stroke_origin_geometry.clear()
	stroke_retracted = false
	var e = sim.at(cell)
	if tool == "belt" and sim.accessible(cell) and (e.is_empty() or e.kind == "belt"):
		stroke_origin_geometry = {"ground": _belt_geometry(cell, 0), "under": _belt_geometry(cell, 1)}
		last_paint = cell
		stroke_start_pending = true
		return
	if tool == "belt" and sim.accessible(cell) and not e.is_empty() and e.kind != "belt":
		last_paint = cell
		return
	if not _paint(cell):
		_end_stroke()

func _end_stroke():
	painting = false
	last_paint = Vector2i(-1, -1)
	reverse_belt_drag = false
	stroke_layer = 0
	stroke_start_pending = false
	stroke_reverse_requested = false
	stroke_cells.clear()
	stroke_undo.clear()
	stroke_origin_geometry.clear()
	stroke_retracted = false

func _drag_cells(destination: Vector2i) -> Array:
	var cells: Array = []
	var current = last_paint
	var delta = destination - current
	var step = Vector2i(signi(delta.x), signi(delta.y))
	var interval = Vector2(INF if delta.x == 0 else 1.0 / absi(delta.x), INF if delta.y == 0 else 1.0 / absi(delta.y))
	var boundary = interval * 0.5
	# Traverse the grid along the cursor segment instead of always going horizontal first.
	while current != destination:
		if current.x != destination.x and (current.y == destination.y or boundary.x <= boundary.y):
			current.x += step.x
			boundary.x += interval.x
		else:
			current.y += step.y
			boundary.y += interval.y
		cells.append(current)
	return cells

func _belt_geometry(cell: Vector2i, layer: int) -> Array:
	var e = sim.at(cell, layer)
	return [e.dir, e.entry] if not e.is_empty() and e.kind == "belt" else []

func _restore_belt_geometry(cell: Vector2i, layer: int, geometry: Array):
	var e = sim.at(cell, layer)
	if not geometry.is_empty() and not e.is_empty() and e.kind == "belt":
		e.dir = geometry[0]
		e.entry = geometry[1]

func _undo_stroke_step():
	var record = stroke_undo.pop_back()
	var tail = stroke_cells.pop_back()
	if record.ground.is_empty():
		sim.remove(tail)
	else:
		if record.under.is_empty(): sim.remove_underground(tail)
		_restore_belt_geometry(tail, 0, record.ground)
		_restore_belt_geometry(tail, 1, record.under)
	_restore_belt_geometry(record.from, record.layer, record.previous)
	sim.refresh_neighbor_ports(tail)
	sim.refresh_neighbor_ports(record.from)
	last_paint = record.from
	stroke_layer = record.layer
	direction = record.direction
	if stroke_undo.is_empty() and not stroke_origin_geometry.is_empty():
		if stroke_origin_geometry.ground.is_empty():
			sim.remove(last_paint)
		else:
			if stroke_origin_geometry.under.is_empty(): sim.remove_underground(last_paint)
			_restore_belt_geometry(last_paint, 0, stroke_origin_geometry.ground)
			_restore_belt_geometry(last_paint, 1, stroke_origin_geometry.under)
		sim.refresh_neighbor_ports(last_paint)
		stroke_layer = 0
		stroke_start_pending = true
		stroke_retracted = true
	_refresh_selection()

func _drag_to(cell: Vector2i):
	for next in _drag_cells(cell):
		if not painting: return
		if tool == "belt" and stroke_cells.size() > 1 and next == stroke_cells[-2]:
			_undo_stroke_step()
			continue
		var current = last_paint
		var step = next - current
		if tool == "erase":
			_paint(next)
			continue
		var previous = sim.at(current, stroke_layer)
		var target = sim.at(next)
		var flow = FactorySim.DIRS.find(-step if reverse_belt_drag else step)
		if stroke_start_pending:
			if not sim.accessible(next) or (not target.is_empty() and target.kind != "belt" and not _accepts_belt(current, next)):
				_end_stroke()
				return
			if not target.is_empty() and target.kind == "belt" and target.dir % 2 != flow % 2 and not sim.can_cross(next, flow):
				_end_stroke()
				return
			stroke_start_pending = false
			stroke_retracted = false
			stroke_layer = sim.build_belt(current, flow, -1, true)
			if stroke_layer < 0:
				_end_stroke()
				return
			previous = sim.at(current, stroke_layer)
		if stroke_layer == 1 and flow != previous.dir:
			_end_stroke()
			_toast("地下交叉段只能直行")
			return
		if not previous.is_empty() and previous.kind != "belt":
			if not target.is_empty() and target.pos == previous.pos:
				last_paint = next
				if stroke_undo.is_empty(): stroke_cells = [next]
				continue
			if previous.kind in ["multiplier", "splitter", "logistics"]:
				reverse_belt_drag = stroke_reverse_requested or (not target.is_empty() and target.kind == "belt" and target.dir == FactorySim.DIRS.find(-step))
			elif previous.kind in FactorySim.TARGETS:
				reverse_belt_drag = true
			elif not _device_outputs_to(current, next):
				_end_stroke()
				return
			elif previous.kind == "source":
				reverse_belt_drag = false
		if not target.is_empty() and target.kind != "belt":
			var connected = _device_outputs_to(next, current) if reverse_belt_drag else _accepts_belt(current, next)
			if connected and not previous.is_empty() and previous.kind == "belt":
				if reverse_belt_drag:
					previous.entry = FactorySim.DIRS.find(step)
				else:
					sim.redirect_belt(current, FactorySim.DIRS.find(step))
			if connected:
				_end_stroke()
			else:
				_toast("乘法机最多连接两个输入方向" if target.kind == "multiplier" else "此方向无法接入设备")
			return
		# Validate the next cell before altering any existing segment's direction.
		if not sim.accessible(next) or (not sim.can_place(next) and target.kind != "belt"):
			_end_stroke()
			return
		flow = FactorySim.DIRS.find(-step if reverse_belt_drag else step)
		if not target.is_empty() and target.kind == "belt" and target.dir % 2 != flow % 2 and not sim.can_cross(next, flow):
			_end_stroke()
			_toast("仅直线传送带可地下交叉")
			return
		var record = {"from": current, "layer": stroke_layer, "previous": _belt_geometry(current, stroke_layer), "ground": _belt_geometry(next, 0), "under": _belt_geometry(next, 1), "direction": direction}
		if reverse_belt_drag:
			if not previous.is_empty() and previous.kind == "belt":
				if FactorySim.DIRS.find(step) == previous.dir:
					_end_stroke()
					return
				if stroke_layer == 0: previous.entry = FactorySim.DIRS.find(step)
			direction = FactorySim.DIRS.find(-step)
		else:
			if not previous.is_empty() and previous.kind == "belt" and stroke_layer == 0:
				if not sim.redirect_belt(current, FactorySim.DIRS.find(step)):
					_end_stroke()
					return
			direction = FactorySim.DIRS.find(step)
		if not _paint(next, -1 if reverse_belt_drag else FactorySim.DIRS.find(-step), true):
			_end_stroke()
			return
		stroke_cells.append(next)
		stroke_undo.append(record)

func _accepts_belt(from: Vector2i, destination: Vector2i) -> bool:
	var e = sim.at(destination)
	if e.is_empty() or not sim.accessible(from) or not sim.accessible(destination):
		return false
	if e.kind == "multiplier":
		var facing = FactorySim.DIRS.find(from - e.pos)
		var slots = sim.multiplier_ports(e).slots
		return facing >= 0 and (facing in slots or -1 in slots)
	if e.kind == "splitter":
		return FactorySim.DIRS.has(from - e.pos)
	return e.kind in FactorySim.TARGETS or e.kind == "logistics"

func _device_outputs_to(from: Vector2i, destination: Vector2i) -> bool:
	var e = sim.at(from)
	if e.is_empty() or not sim.accessible(from) or not sim.accessible(destination):
		return false
	if e.kind == "splitter": return FactorySim.DIRS.has(destination - e.pos)
	if e.kind == "multiplier":
		return FactorySim.DIRS.has(destination - e.pos)
	if e.kind == "source":
		for port in sim.source_sockets(e):
			if destination == port.pos: return true
	if e.kind == "logistics":
		for port in sim.logistics_ports(e):
			if destination == port.pos: return true
	return false

func _snap_belt_to_input(cell: Vector2i):
	var e = sim.at(cell)
	var candidates: Array = []
	for facing in range(4):
		var neighbor = sim.at(cell + FactorySim.DIRS[facing])
		if not neighbor.is_empty() and neighbor.kind == "logistics": continue
		if facing != e.entry and _accepts_belt(cell, cell + FactorySim.DIRS[facing]):
			candidates.append(facing)
	if candidates.size() == 1:
		sim.redirect_belt(cell, candidates[0])

func _paint(cell: Vector2i, entry: int = -1, crossing: bool = false) -> bool:
	last_paint = cell
	if tool == "select":
		if sim.accessible(cell):
			selected = cell if not sim.at(cell).is_empty() else NONE_CELL
			_refresh_selection()
	elif tool == "erase":
		if sim.remove(cell):
			_refresh_selection()
	else:
		var placed = false
		if tool == "belt":
			stroke_layer = sim.build_belt(cell, direction, entry, crossing)
			placed = stroke_layer >= 0
		else:
			placed = sim.place(cell, tool, direction)
		if placed:
			selected = cell
			_refresh_selection()
		else:
			_toast("土地尚未开放" if not sim.accessible(cell) else "物流站额度不足或占地被占用" if tool == "logistics" else "此格已被占用，无法放置")
			return false
	return true

func _set_tool(value: String):
	if value == "logistics" and "logistics" not in sim.world.technologies:
		_toast("质数 7 开放后可研究共享物流")
		return
	tool = value
	_end_stroke()
	for id in buttons:
		buttons[id].set_pressed_no_signal(id == value)
	_refresh_selection()

func _rotate():
	var e = sim.at(selected)
	if tool == "select" and not e.is_empty() and e.kind in ["belt", "multiplier", "splitter"]:
		if e.kind == "multiplier" and (e.inputs[0] != 0 or e.inputs[1] != 0):
			_toast("待输入物料加工完成后可旋转")
			return
		if e.kind == "belt":
			if not sim.redirect_belt(selected, e.dir + 1): _toast("交叉位置不能转弯")
		else:
			e.dir = (e.dir + 1) % 4
	else:
		direction = (direction + 1) % 4
	_refresh_selection()

func _fit_map():
	var side = sim.world.half_size() * 2 * 40 + 60
	view_zoom = clampf(minf(workspace.size.x / side, workspace.size.y / side), MIN_ZOOM, 2.0)
	camera.zoom = Vector2.ONE * view_zoom
	camera.position = Vector2.ZERO
	_layout()

func _refresh_selection():
	var e = sim.at(selected)
	loading_ui = true
	if not e.is_empty() and e.kind == "splitter":
		mode_input.select(e.mode)
		ratio_input.value = e.ratio
		primary_output.select(e.dir)
		for facing in range(4):
			var value = e.filters[facing]
			filter_ports[facing].selector.select(0 if value == 0 else 2 if value == -1 else 1)
			filter_ports[facing].number.value = maxi(2, value)
	if not e.is_empty() and e.kind == "logistics":
		for i in range(8): logistics_fields[i].field.value = e.outputs[i]
	loading_ui = false
	_refresh()

func _refresh():
	if root == null:
		return
	var w = sim.world
	expansion_label.text = "%d × %d → %d × %d\n第 %d 圈\n%s" % [w.half_size() * 2, w.half_size() * 2, w.half_size() * 2 + 16, w.half_size() * 2 + 16, w.expansions + 1, _cost_text(w.expansion_cost)]
	var resource_lines = PackedStringArray()
	var next_resources = sim.next_ring_resources()
	var resources = next_resources.keys()
	resources.sort()
	for prime in resources: resource_lines.append("%d × %d%s" % [prime, next_resources[prime], "（未研究）" if prime not in w.primes else ""])
	expansion_label.text += "\n下一圈矿点\n" + "、".join(resource_lines)
	if "logistics" in w.technologies: expansion_label.text += "\n物流额度 +1"
	_action_style(expansion_button, w.can_pay(w.expansion_cost), _cost_text(w.expansion_cost))
	prime_label.text = "质数 %d\n扩张 %d / %d\n%s" % [w.next_resource(), w.expansions - w.last_prime_expansion, WorldProgress.interval(w.stage), _cost_text(w.prime_cost)]
	if "logistics" in w.technologies: prime_label.text += "\n物流额度 +1"
	prime_button.text = "研究质数 %d" % w.next_resource()
	var prime_limit = w.next_resource() * 2 > FactorySim.MAX_VALUE
	if prime_limit: prime_label.text += "\n已达到当前整数范围的质数上限"
	_action_style(prime_button, not prime_limit and w.prime_ready() and w.can_pay(w.prime_cost), prime_label.text)
	for technology in tech_controls:
		var control = tech_controls[technology]
		control.label.text = "已研究" if technology in w.technologies else _cost_text(w.tech_costs[technology])
		if technology not in w.technologies:
			if technology == "logistics": control.label.text += "\n物流站额度 +2"
			elif "logistics" in w.technologies: control.label.text += "\n物流额度 +1"
		if technology == "logistics" and 7 not in w.primes: control.label.text = "需要质数 7 与数字筛选\n" + control.label.text
		control.button.disabled = technology in w.technologies
		_action_style(control.button, w.tech_available(technology) and w.can_pay(w.tech_costs[technology]), control.label.text)
	var prime_names = ", ".join(w.primes.map(func(p): return str(p)))
	var prime_summary = prime_names if w.primes.size() <= 4 else "%d 种 · 最新 %d" % [w.primes.size(), w.primes[-1]]
	supply_label.text = "已开放质数  %s\n物流站  %d / %d\n种子  %d\n近期交付  %.2f 个/秒" % [prime_summary, sim.logistics_used(), w.logistics_capacity, w.seed_value, sim.rate("research")]
	supply_label.tooltip_text = "已开放质数  " + prime_names + "\n" + supply_label.text
	buttons.logistics.disabled = "logistics" not in w.technologies
	complete_label.text = "存档异常 · 已禁止覆盖" if save_blocked else "已暂停" if paused else ""
	if toast_time == 0:
		status_label.text = "第 %d 圈   ·   %d 个已生成区块   ·   %s" % [w.expansions, sim.loaded_chunks.size(), "已暂停" if paused else "运行中"]
	var e = sim.at(selected)
	var diagnostics = FlowDiagnostics.new(sim)
	board.problem_ports = []
	board.problem_cell = NONE_CELL
	problem_cell = NONE_CELL
	problem_button.visible = false
	splitter_box.visible = not e.is_empty() and e.kind == "splitter"
	underground_box.visible = not sim.at(selected, 1).is_empty()
	logistics_box.visible = not e.is_empty() and e.kind == "logistics"
	mode_input.set_item_disabled(1, not sim.splitter_unlocked(1))
	mode_input.set_item_disabled(2, not sim.splitter_unlocked(2))
	ratio_input.editable = sim.splitter_unlocked(1)
	if not e.is_empty() and e.kind == "splitter":
		var ports = sim.splitter_ports(e)
		ratio_box.visible = e.mode == 1
		for facing in range(4):
			var port = filter_ports[facing]
			port.row.visible = e.mode == 2 and facing in ports.outputs
			port.label.text = ["东", "南", "西", "北"][facing] + " · " + ("输入" if facing in ports.inputs else "输出" if facing in ports.outputs else "未连接")
			if e.item and facing in ports.outputs and facing not in sim._output_directions(e, sim.entities): port.label.text += " · 筛选不匹配 %d" % e.item
			port.selector.disabled = e.mode != 2 or not sim.splitter_unlocked(2) or facing not in ports.outputs
			port.number.editable = not port.selector.disabled and port.selector.selected == 1
	if e.is_empty():
		inspector_title.text = "建造乘法机" if tool == "multiplier" else "设备"
		inspector_status.text = "未选择设备" if tool == "select" else "方向 · " + ["东", "南", "西", "北"][direction]
		inspector_detail.text = ""
		if tool == "multiplier":
			inspector_detail.text = "输入 A / B · 未连接\n输出 · 未连接\n加工周期  1 秒"
		return
	inspector_title.text = TITLES[e.kind]
	inspector_status.text = "坐标 %d, %d" % [e.pos.x, e.pos.y]
	match e.kind:
		"source":
			var recent_output = e.log_recent.filter(func(time): return time >= sim.elapsed - 10.0).size()
			inspector_detail.text = "原料  %d\n总产量上限  %d 个 / 秒\n已连接出口  %d / 8\n实际出料  %.2f 个 / 秒\n%s" % [e.value, sim.source_total_rate(e), sim.source_connections(e).size(), recent_output / maxf(1.0, minf(10.0, sim.elapsed)), "已开放" if sim.source_enabled(e) else "等待质数研究"]
		"multiplier":
			var product = e.inputs[0] * e.inputs[1]
			inspector_detail.text = "输入 A  %s\n输入 B  %s\n输出缓存  %s\n加工周期  1 秒" % [str(e.inputs[0]) if e.inputs[0] else "空", str(e.inputs[1]) if e.inputs[1] else "空", str(e.output) if e.output else "空"]
			if product != 0:
				inspector_detail.text += "\n\n当前  %d × %d = %d" % [e.inputs[0], e.inputs[1], product]
				if product <= FactorySim.MAX_VALUE:
					inspector_detail.text += "\n" + _factor_text(product)
			elif e.last_inputs[0] != 0 and e.last_inputs[1] != 0:
				inspector_detail.text += "\n\n上次  %d × %d = %d" % [e.last_inputs[0], e.last_inputs[1], e.last_inputs[0] * e.last_inputs[1]]
			if e.output:
				inspector_detail.text += "\n" + _factor_text(e.output)
			for port in diagnostics.machine_ports(e):
				inspector_detail.text += "\n\n" + port.text
				if port.warning and port.facing >= 0: board.problem_ports.append(port.facing)
		"belt", "splitter":
			inspector_detail.text = "方向  %s\n运输  3 个 / 秒\n物料  %s" % [["东", "南", "西", "北"][e.dir], str(e.item) if e.item else "空"]
			if e.item: inspector_detail.text += "\n" + _factor_text(e.item)
			if e.kind == "splitter":
				var ports = sim.splitter_ports(e)
				inspector_detail.text = "输入  %d 路\n输出  %d 路\n运输  3 个 / 秒\n物料  %s" % [ports.inputs.size(), ports.outputs.size(), str(e.item) if e.item else "空"]
				if e.item: inspector_detail.text += "\n" + _factor_text(e.item)
			var under = sim.at(selected, 1)
			if not under.is_empty():
				inspector_detail.text += "\n\n地下  %s\n物料  %s" % [["东", "南", "西", "北"][under.dir], str(under.item) if under.item else "空"]
				if under.item: inspector_detail.text += "\n" + _factor_text(under.item)
				inspector_detail.text += "\n" + diagnostics.describe(under).text
		"logistics":
			inspector_detail.text = "合计上限  6 个/秒\n每口上限  3 个/秒\n实际  %.2f 个/秒\n\n物流库存\n%s" % [e.log_recent.size() / maxf(1.0, minf(10.0, sim.elapsed)), _stock_text(w.logistics_stock)]
			for port in sim.logistics_ports(e):
				var i = port.index
				logistics_fields[i].label.text = "%s%d · %s" % [["东", "南", "西", "北"][port.facing], i % 2 + 1, {"input": "输入", "output": "输出", "none": "未连接"}[port.mode]]
				logistics_fields[i].field.visible = port.mode == "output"
				if port.mode != "none":
					logistics_fields[i].label.text += " · " + sim.logistics_port_state(e, port)
				if port.mode == "output":
					var state = diagnostics.logistics_output(e, port)
					logistics_fields[i].label.text += "\n" + state.text
					if state.warning and problem_cell == NONE_CELL:
						problem_cell = state.cell
						board.problem_cell = state.cell
						problem_button.visible = true
		"research":
			inspector_detail.text = "研究库存 / 累计\n"
			for value in w.recipes:
				inspector_detail.text += "%d   %d / %d\n%s\n" % [value, w.count(w.research_stock, value), w.count(w.lifetime, value), _factor_text(value)]
	if e.kind in ["belt", "splitter", "multiplier"]:
		var diagnosis = diagnostics.describe(e)
		inspector_status.text = "坐标 %d, %d\n%s" % [e.pos.x, e.pos.y, diagnosis.text]
		if diagnosis.warning:
			problem_cell = diagnosis.cell
			board.problem_cell = problem_cell
			problem_button.visible = problem_cell != NONE_CELL
			if e.kind in ["belt", "splitter"] and e.item:
				var outputs = sim.splitter_ports(e).outputs if e.kind == "splitter" else [e.dir]
				for facing in outputs:
					if facing not in sim._output_directions(e, sim.entities) or diagnostics.downstream(e, e.item, facing).warning: board.problem_ports.append(facing)

func _action_style(button: Button, ready: bool, hint: String):
	button.modulate = Color.WHITE if ready else Color("aab6b0")
	button.tooltip_text = hint

func _research_action(action: String):
	var w = sim.world
	var cost = w.expansion_cost if action == "expand" else w.prime_cost if action == "prime" else w.tech_costs[action]
	var reasons = PackedStringArray()
	if action == "prime":
		if w.next_resource() * 2 > FactorySim.MAX_VALUE: reasons.append("已达到整数范围上限")
		elif not w.prime_ready(): reasons.append("还需扩张 %d 圈" % (WorldProgress.interval(w.stage) - w.expansions + w.last_prime_expansion))
	elif action not in ["expand", "prime"] and not w.tech_available(action):
		if action in w.technologies: reasons.append("该科技已研究")
		elif action == "logistics": reasons.append("需要质数 7 与数字筛选")
		else: reasons.append("需要先研究比例分流")
	for value in cost:
		var missing = int(cost[value]) - w.count(w.research_stock, int(value))
		if missing > 0: reasons.append("数字 %s 还缺 %d 个" % [value, missing])
	if not reasons.is_empty():
		_toast("；".join(reasons))
		research_feedback.dialog_text = "\n".join(reasons)
		research_feedback.popup_centered(Vector2i(360, 180))
		return
	var success = w.expand() if action == "expand" else w.research_prime() if action == "prime" else w.research_tech(action)
	_toast(("已开放下一圈土地" if action == "expand" else "新质数已研究" if action == "prime" else "科技已研究") + (" · 物流额度增加" if "logistics" in w.technologies else "") if success else "条件不足，未消耗库存")
	_refresh()

func _cost_text(cost: Dictionary) -> String:
	var lines = PackedStringArray()
	for value in cost:
		var stock = sim.world.count(sim.world.research_stock, int(value))
		lines.append("%s · 库存 %d / 需要 %d\n%s\n%s" % [value, stock, cost[value], "还缺 %d 个" % maxi(0, int(cost[value]) - stock) if stock < int(cost[value]) else "库存充足", _factor_text(int(value))])
	return "\n".join(lines)

func _stock_text(stock: Dictionary) -> String:
	var lines = PackedStringArray()
	for value in stock:
		if int(stock[value]) > 0: lines.append("%s · %d" % [value, stock[value]])
	return "\n".join(lines) if not lines.is_empty() else "空"

func _factor_text(value: int) -> String:
	var parts = PackedStringArray()
	for factor in FactorySim.factors(value): parts.append(str(factor))
	return " = ".join([str(value), " × ".join(parts)])

func _set_splitter_mode(index: int):
	var e = sim.at(selected)
	if not e.is_empty() and e.kind == "splitter":
		if sim.splitter_unlocked(index):
			e.mode = index
			_refresh()

func _toast(message: String):
	status_label.text = message
	toast_time = 4.0

func _save(show_message: bool):
	if save_blocked:
		if show_message: _toast("存档无法读取，原文件已保留")
		return
	if "--qa" in OS.get_cmdline_user_args(): return
	sim.session_paused = paused
	var result = SaveStore.save_game(sim)
	if show_message or result != OK:
		_toast("工厂已保存" if result == OK else "保存失败 · 错误 %d" % result)

func _run_visual_qa():
	paused = true
	if "--demo" in OS.get_cmdline_user_args():
		var factory = load("res://tests/auto_factory.gd").new(sim)
		if factory.produce(sim.world.expansion_cost): sim.world.expand()
		selected = Vector2i(-6, -7)
		_refresh_selection()
	await get_tree().process_frame
	if "--detail" in OS.get_cmdline_user_args():
		camera.position = Vector2(-4 * 40, -4 * 40)
	else:
		_fit_map()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image = get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://qa")
	var suffix = "_demo" if "--demo" in OS.get_cmdline_user_args() else ""
	if "--detail" in OS.get_cmdline_user_args(): suffix += "_detail"
	if "--completed" in OS.get_cmdline_user_args(): suffix += "_completed"
	if "--splitter" in OS.get_cmdline_user_args(): suffix += "_splitter"
	image.save_png("res://qa/viewport_%dx%d%s.png" % [image.get_width(), image.get_height(), suffix])
	print("QA screenshot saved: ", image.get_size())
	get_tree().quit()
