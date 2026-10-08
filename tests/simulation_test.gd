extends SceneTree

var checks = 0
var failures: Array = []

func _initialize():
	_test_multiplier()
	_test_transport()
	_test_merges()
	_test_splitters()
	_test_sources()
	_test_progress_and_save()
	_test_full_factory()
	print("Simulation: %d checks, %d failures" % [checks, failures.size()])
	for message in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)

func verify(condition: bool, message: String):
	checks += 1
	if not condition: failures.append(message)

func empty() -> FactorySim:
	return FactorySim.new(false)

func run_for(sim: FactorySim, seconds: float):
	for step in range(roundi(seconds / FactorySim.STEP)):
		sim.tick()

func inject(sim: FactorySim, p: Vector2i, value: int):
	sim.at(p).item = value
	sim.at(p).age = 0.0
	sim.emitted += FactorySim.prime_count(value)

func belt(sim: FactorySim, p: Vector2i, direction: int = 0):
	verify(sim.place(p, "belt", direction), "Place belt at %s" % p)

func line(sim: FactorySim, points: Array):
	for i in range(points.size() - 1):
		var p: Vector2i = points[i]
		var finish: Vector2i = points[i + 1]
		var direction = FactorySim.DIRS.find(Vector2i(signi(finish.x - p.x), signi(finish.y - p.y)))
		while p != finish:
			if sim.at(p).is_empty(): sim.place(p, "belt", direction)
			else: sim.at(p).dir = direction
			p += FactorySim.DIRS[direction]
	if sim.at(points[-1]).is_empty(): sim.place(points[-1], "belt", 0)

func _test_multiplier():
	for pair in [[2, 3, 6], [6, 2, 12], [6, 3, 18], [6, 5, 30], [3, 3, 9]]:
		var sim = empty()
		sim.place(Vector2i(5, 5), "multiplier", 0)
		belt(sim, Vector2i(4, 5))
		belt(sim, Vector2i(5, 4), 1)
		inject(sim, Vector2i(4, 5), pair[0])
		inject(sim, Vector2i(5, 4), pair[1])
		run_for(sim, 0.34)
		verify(sim.at(Vector2i(5, 5)).output == 0, "No instant processing")
		run_for(sim, 29 * FactorySim.STEP)
		verify(sim.at(Vector2i(5, 5)).output == 0, "Batch cannot finish before one second")
		run_for(sim, FactorySim.STEP)
		verify(sim.at(Vector2i(5, 5)).output == pair[2], "Automatic multiplication %s" % [pair])
		verify(sim.total_mass() == sim.emitted, "Multiplication preserves prime mass")
		verify(sim.at(Vector2i(5, 5)).last_inputs == [pair[0], pair[1]], "Records actual operands")
	var sim = empty()
	sim.place(Vector2i(5, 5), "multiplier", 0)
	belt(sim, Vector2i(4, 5))
	inject(sim, Vector2i(4, 5), 3)
	run_for(sim, 3)
	verify(sim.at(Vector2i(4, 5)).item == 0 and sim.at(Vector2i(5, 5)).inputs == [3, 0], "Any operand accepted; missing port waits without consumption")
	verify(sim.at(Vector2i(5, 5)).output == 0 and sim.at(Vector2i(5, 5)).progress == 0, "Single operand cannot start processing")
	verify(sim.place(Vector2i(8, 8), "multiplier", 0), "Machine needs no recipe")
	verify(not sim.place(Vector2i(8, 8), "belt", 0), "Occupied cell rejected")
	verify(not sim.place(Vector2i(20, 8), "belt", 0), "Locked region rejected")
	for direction in range(4):
		var rotated = empty()
		var p = Vector2i(8, 8)
		rotated.place(p, "multiplier", direction)
		var rear = p - FactorySim.DIRS[direction]
		var left = p + FactorySim.DIRS[(direction + 3) % 4]
		belt(rotated, rear, direction)
		belt(rotated, left, (direction + 1) % 4)
		inject(rotated, rear, 2)
		inject(rotated, left, 3)
		run_for(rotated, 1.4)
		verify(rotated.at(p).output == 6, "Rotated machine ports %d" % direction)
	_test_changing_inputs()
	_test_overflow()

func _test_changing_inputs():
	var sim = empty()
	var p = Vector2i(5, 5)
	sim.place(p, "multiplier", 0)
	belt(sim, p + Vector2i.LEFT)
	belt(sim, p + Vector2i.UP, 1)
	var machine = sim.at(p)
	inject(sim, p + Vector2i.LEFT, 2)
	inject(sim, p + Vector2i.UP, 3)
	run_for(sim, 1.34)
	verify(machine.output == 6, "First automatic pair is processed")
	inject(sim, p + Vector2i.LEFT, 6)
	inject(sim, p + Vector2i.UP, 5)
	run_for(sim, 3)
	verify(machine.output == 6 and machine.inputs == [6, 5] and machine.progress == 0, "Blocked output preserves old product and next pair")
	verify(sim.total_mass() == sim.emitted, "Output backpressure conserves material")
	var saved = JSON.parse_string(JSON.stringify(sim.serialize()))
	var copy = empty()
	verify(copy.restore(saved) and copy.at(p).inputs == machine.inputs and copy.at(p).last_inputs == machine.last_inputs and copy.at(p).output == machine.output and is_equal_approx(copy.at(p).age, machine.age), "Adaptive buffers and last pair survive save")
	# Opening the output is enough; the next pair requires no configuration change.
	belt(sim, p + Vector2i.RIGHT)
	run_for(sim, 1.04)
	verify(sim.at(p + Vector2i.RIGHT).item == 6 and machine.output == 30, "Same machine automatically changes from 2x3 to 6x5")
	verify(machine.last_inputs == [6, 5] and sim.total_mass() == sim.emitted, "Changed inputs preserve history and mass")
	var legacy = JSON.parse_string(JSON.stringify(sim.serialize()))
	for e in legacy.entities:
		e.erase("last_inputs")
		e.a = 6
		e.b = 5
	var old_copy = empty()
	verify(old_copy.restore(legacy) and old_copy.at(p).output == 30 and old_copy.at(p).inputs == machine.inputs, "Old recipe saves retain products and buffers")
	verify(not old_copy.at(p).has("a") and old_copy.at(p).last_inputs == [0, 0], "Legacy recipes no longer restrict inputs")
	# Restore partway through a different batch and compare exact continued simulation.
	inject(sim, p + Vector2i.LEFT, 7)
	inject(sim, p + Vector2i.UP, 11)
	sim.remove(p + Vector2i.RIGHT)
	sim._add_fixed("hub", p + Vector2i.RIGHT)
	run_for(sim, 0.7)
	verify(machine.progress > 0 and machine.progress < 1, "Changed arbitrary pair is in progress")
	var mid = empty()
	var mid_save = JSON.parse_string(JSON.stringify(sim.serialize()))
	verify(mid.restore(mid_save), "Mid-batch save restores")
	var legacy_mid = mid_save.duplicate(true)
	for e in legacy_mid.entities:
		e.erase("last_inputs")
		e.a = 7
		e.b = 11
	var legacy_batch = empty()
	verify(legacy_batch.restore(legacy_mid) and legacy_batch.at(p).inputs == [7, 11] and is_equal_approx(legacy_batch.at(p).progress, machine.progress), "Old mid-batch save preserves ingredients and processing time")
	run_for(sim, 1)
	run_for(mid, 1)
	run_for(legacy_batch, 1)
	verify(JSON.stringify(mid.serialize()) == JSON.stringify(sim.serialize()) and machine.output == 77, "Save resumes the identical batch without offline advancement")
	verify(JSON.stringify(legacy_batch.serialize()) == JSON.stringify(sim.serialize()), "Old batch resumes as adaptive processing with identical output and progress")

func _test_overflow():
	var sim = empty()
	var p = Vector2i(5, 5)
	sim.place(p, "multiplier", 0)
	belt(sim, p + Vector2i.LEFT)
	belt(sim, p + Vector2i.UP, 1)
	inject(sim, p + Vector2i.LEFT, 999999)
	inject(sim, p + Vector2i.UP, 2)
	run_for(sim, 3)
	verify(sim.at(p).inputs == [999999, 2] and sim.at(p).output == 0 and sim.at(p).progress == 0, "Overflow retains both ingredients without invalid output")
	inject(sim, p + Vector2i.LEFT, 2)
	inject(sim, p + Vector2i.UP, 3)
	run_for(sim, 3)
	verify(sim.at(p + Vector2i.LEFT).item == 2 and sim.at(p + Vector2i.UP).item == 3, "Overflow backpressure stops upstream")
	verify(sim.total_mass() == sim.emitted, "Overflow conserves all material")
	var copy = empty()
	var saved = JSON.parse_string(JSON.stringify(sim.serialize()))
	verify(copy.restore(saved) and copy.at(p).inputs == [999999, 2], "Overflow buffers survive save")
	sim.remove(p)
	verify(sim.total_mass() == sim.emitted, "Removing overflow machine accounts for discarded ingredients")
	for pair in [[3, 333333, 999999], [999999, 999999, 0]]:
		var edge = empty()
		edge.place(p, "multiplier", 0)
		edge.at(p).inputs = [pair[0], pair[1]]
		run_for(edge, 2)
		verify(edge.at(p).output == pair[2], "Product boundary uses safe 64-bit multiplication %s" % [pair])

func _test_transport():
	var sim = empty()
	for x in range(2, 8): belt(sim, Vector2i(x, 5))
	inject(sim, Vector2i(2, 5), 2)
	run_for(sim, FactorySim.TRAVEL)
	verify(sim.at(Vector2i(3, 5)).item == 2, "Moves exactly one cell per interval")
	verify(sim.at(Vector2i(4, 5)).item == 0, "Cannot cross multiple cells in one step")
	run_for(sim, 5)
	verify(sim.at(Vector2i(7, 5)).item == 2, "End of line holds item")
	verify(sim.total_mass() == sim.emitted, "Blocked belt conserves items")
	var full = empty()
	for x in range(2, 8):
		belt(full, Vector2i(x, 5))
		inject(full, Vector2i(x, 5), 12)
	full._add_fixed("research", Vector2i(8, 5))
	run_for(full, FactorySim.TRAVEL)
	verify(full.delivered.research == 1, "Full belt advances atomically")
	verify(full.at(Vector2i(2, 5)).item == 0, "Full belt vacates upstream in same step")
	verify(full.total_mass() == full.emitted, "Atomic movement conserves all items")
	var wrong = empty()
	belt(wrong, Vector2i(4, 5))
	wrong._add_fixed("research", Vector2i(5, 5))
	inject(wrong, Vector2i(4, 5), 18)
	run_for(wrong, 2)
	verify(wrong.delivered.research == 0 and wrong.at(Vector2i(4, 5)).item == 18, "Consumer rejects wrong number")
	verify(wrong.remove(Vector2i(4, 5)) and wrong.total_mass() == wrong.emitted, "Removal accounts for discarded material")

func _test_splitters():
	var sim = empty()
	sim.place(Vector2i(5, 5), "splitter", 0)
	belt(sim, Vector2i(6, 5))
	belt(sim, Vector2i(5, 6), 1)
	var counts = [0, 0]
	for i in range(10):
		inject(sim, Vector2i(5, 5), 2)
		run_for(sim, FactorySim.TRAVEL)
		for port in range(2):
			var e = sim.at(Vector2i(6, 5) if port == 0 else Vector2i(5, 6))
			if e.item:
				counts[port] += 1
				sim.discarded += FactorySim.prime_count(e.item)
				e.item = 0
	verify(counts == [5, 5], "Alternating splitter fair")
	sim.delivered.research = 20
	sim.at(Vector2i(5, 5)).mode = 1
	sim.at(Vector2i(5, 5)).ratio = 3
	sim.at(Vector2i(5, 5)).cursor = 0
	counts = [0, 0]
	for i in range(8):
		inject(sim, Vector2i(5, 5), 3)
		run_for(sim, FactorySim.TRAVEL)
		for port in range(2):
			var e = sim.at(Vector2i(6, 5) if port == 0 else Vector2i(5, 6))
			if e.item:
				counts[port] += 1
				e.item = 0
	verify(counts == [6, 2], "3:1 splitter distribution")
	sim.delivered.research = 60
	sim.at(Vector2i(5, 5)).mode = 2
	sim.at(Vector2i(5, 5)).filters = [2, -1, 0, 0]
	inject(sim, Vector2i(5, 5), 3)
	run_for(sim, FactorySim.TRAVEL)
	verify(sim.at(Vector2i(5, 6)).item == 3, "Filter sends nonmatching number right")
	sim.at(Vector2i(5, 6)).item = 0
	sim.at(Vector2i(6, 5)).item = 12
	sim.at(Vector2i(6, 5)).age = 0
	inject(sim, Vector2i(5, 5), 2)
	run_for(sim, 1)
	verify(sim.at(Vector2i(5, 5)).item == 2, "Filter does not misroute when chosen port blocked")
	sim.at(Vector2i(5, 5)).mode = 0
	run_for(sim, FactorySim.TRAVEL)
	verify(sim.at(Vector2i(5, 6)).item == 2, "Basic splitter uses unblocked alternative")

func _test_merges():
	var sim = empty()
	for p in [Vector2i(3, 5), Vector2i(4, 5), Vector2i(5, 5)]: sim.place(p, "belt", 0)
	sim.place(Vector2i(4, 4), "belt", 1)
	sim._add_fixed("research", Vector2i(6, 5))
	for x in range(5): sim.place(Vector2i(x, 0), "belt", 0)
	var counts = [0, 0]
	var entrances = [Vector2i(3, 5), Vector2i(4, 4)]
	for i in range(400):
		for p in entrances:
			if sim.at(p).item == 0: inject(sim, p, 12)
		sim.tick()
		for index in range(2):
			if sim.at(entrances[index]).item == 0: counts[index] += 1
	verify(counts[0] > 10 and counts[1] > 10, "Periodic merge cannot starve either input: %s" % [counts])
	verify(sim.total_mass() == sim.emitted, "Merge conserves material")

func _test_sources():
	var sim = empty()
	sim._add_fixed("source", Vector2i(2, 5), 2)
	for y in [5, 6]:
		for x in range(4, 18): sim.place(Vector2i(x, y), "belt", 0)
	for i in range(120): sim.tick()
	verify(sim.emitted >= 22 and sim.emitted <= 24, "2 source produces 6/sec through full belts")
	verify(sim.total_mass() == sim.emitted, "Source network mass conserved")
	run_for(sim, 15)
	var before = sim.emitted
	run_for(sim, 10)
	verify(sim.emitted == before, "Blocked source does not accumulate inventory")

func _test_progress_and_save():
	var sim = FactorySim.new()
	sim.delivered.research = 60
	sim.delivered.exploration = 30
	sim.delivered.hub = 60
	verify(sim.complete() and sim.unlocked(), "All permanent goals unlock completion")
	verify(sim.place(Vector2i(21, 8), "splitter", 1), "Unlocked region buildable")
	inject(sim, Vector2i(21, 8), 18)
	sim.at(Vector2i(21, 8)).mode = 2
	sim.at(Vector2i(21, 8)).filters = [0, 18, -1, 0]
	var restored = empty()
	var json = JSON.parse_string(JSON.stringify(sim.serialize()))
	verify(restored.restore(json), "JSON save round trip")
	verify(restored.at(Vector2i(21, 8)).item == 18 and restored.at(Vector2i(21, 8)).filters == [0, 18, -1, 0], "Save preserves buffered material and four-way filters")
	verify(restored.complete(), "Save preserves permanent goals")
	var count = restored.delivered.duplicate()
	run_for(restored, 100)
	verify(restored.delivered == count, "Progress never expires")
	verify(not restored.restore({"version": 99}), "Invalid save rejected")
	verify(restored.complete(), "Invalid save does not mutate running game")
	DirAccess.make_dir_recursive_absolute("res://qa")
	var path = "res://qa/test-save.json"
	verify(SaveStore.save_game(sim, path) == OK, "Actual save file written")
	sim.delivered.hub = 61
	verify(SaveStore.save_game(sim, path) == OK, "Atomic save overwrites previous file")
	verify(SaveStore.load_game(restored, path) and restored.delivered.hub == 61, "Actual save file restored")

func _test_full_factory():
	# A concrete shared-6 factory, driven entirely by its fixed prime sources.
	var sim = FactorySim.new()
	var layout = load("res://tests/factory_layout.gd")
	layout.shared(sim)
	run_for(sim, 300)
	verify(sim.delivered.research >= 60, "Shared 6 factory completes research: %d" % sim.delivered.research)
	verify(sim.delivered.exploration >= 30, "Shared 6 factory completes exploration: %d" % sim.delivered.exploration)
	verify(sim.total_mass() == sim.emitted, "Shared 6 factory conserves mass")
	if not sim.unlocked(): return
	layout.hub(sim)
	run_for(sim, 300)
	verify(sim.delivered.hub >= 60 and sim.complete(), "Complete all goals from actual sources: %s" % sim.delivered)
	verify(sim.total_mass() == sim.emitted, "Final factory conserves mass")
