extends SceneTree

var checks = 0
var failures: Array = []

func verify(condition: bool, message: String):
	checks += 1
	if not condition: failures.append(message)

func route(sim: WorldSim, points: Array, end_direction: int):
	var path: Array = []
	for i in range(points.size() - 1):
		var p: Vector2i = points[i]
		var end: Vector2i = points[i + 1]
		var step = Vector2i(signi(end.x - p.x), signi(end.y - p.y))
		while p != end:
			path.append(p)
			p += step
	path.append(points[-1])
	for i in range(path.size()):
		var direction = end_direction if i == path.size() - 1 else FactorySim.DIRS.find(path[i + 1] - path[i])
		var entry = -1 if i == 0 else FactorySim.DIRS.find(path[i - 1] - path[i])
		verify(sim.build_belt(path[i], direction, entry, true) >= 0, "Build real logistics production route %s" % path[i])

func _initialize():
	var sim = WorldSim.new()
	if not SaveStore.load_game(sim, "res://qa/growth_checkpoint.json"):
		push_error("Complete real-production growth checkpoint must load with current code")
		quit(1)
		return
	verify(sim.world.expansions == 29 and sim.world.stage == 4, "Fresh growth reaches 29 expansions and four paid prime stages")
	verify(sim.world.primes == [2, 3, 5, 7, 11, 13], "Real progression unlocks every named prime")
	verify(sim.world.bounds() == Rect2i(-248, -248, 496, 496), "Final growth square expands symmetrically")
	verify(sim.world.technologies == ["ratio", "filter", "logistics"] and sim.world.logistics_capacity == 25, "Paid technologies and post-unlock rewards persist")
	var new_products = sim.world.lifetime.keys().filter(func(value): return 13 in FactorySim.factors(int(value)))
	verify(not new_products.is_empty() and sim.world.spent_mass > 0, "New 13 products were actually delivered and spent")
	verify(sim.total_mass() == sim.emitted, "Complete growth checkpoint conserves all prime factors")
	var copy = WorldSim.new()
	verify(copy.restore(JSON.parse_string(JSON.stringify(sim.serialize()))), "Latest restore accepts complete grown factory")
	verify(JSON.stringify(copy.serialize()) == JSON.stringify(sim.serialize()), "All world state and live materials restore exactly without offline time")
	for i in range(120):
		sim.tick()
		copy.tick()
	verify(JSON.stringify(copy.serialize()) == JSON.stringify(sim.serialize()), "Restored final production continues identically")
	_real_logistics(sim)
	print("Growth checkpoint: %d checks, %d failures" % [checks, failures.size()])
	for message in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)

func _real_logistics(sim: WorldSim):
	# Reconfigure the paid world using only ordinary construction, never injected stock.
	for id in sim.entities.keys():
		var e = sim.entities.get(id, {})
		if not e.is_empty() and e.kind in ["belt", "multiplier", "splitter", "logistics"]: sim.remove(e.pos)
	verify(sim.place(Vector2i(-4, -2), "multiplier", 0), "Build adaptive producer after complete growth")
	var input_station = Vector2i(-1, -3)
	var output_station = Vector2i(4, 2)
	verify(sim.place(input_station, "logistics", 0) and sim.place(output_station, "logistics", 0), "Use earned allowances for two remote stations")
	sim.at(output_station).outputs[4] = 6
	route(sim, [Vector2i(-6, -4), Vector2i(-5, -4), Vector2i(-5, -2)], 0)
	route(sim, [Vector2i(-6, 4), Vector2i(-3, 4), Vector2i(-3, -3), Vector2i(-4, -3)], 1)
	route(sim, [Vector2i(-3, -2), Vector2i(-2, -2), Vector2i(-2, -3)], 0)
	route(sim, [Vector2i(3, 2), Vector2i(2, 2), Vector2i(2, 0)], 2)
	var before = sim.world.count(sim.world.lifetime, 6)
	for i in range(900): sim.tick()
	verify(sim.world.count(sim.world.lifetime, 6) >= before + 10, "Actual mined 2x3 traverses shared bank and reaches research")
	verify(sim.total_mass() == sim.emitted, "Real remote production and underground crossing conserve materials")
	verify(sim.at(input_station).log_recent.size() > 0 and sim.at(output_station).log_recent.size() > 0, "Both stations perform actual transfers")
	sim.remove(Vector2i(3, 2))
	for i in range(150): sim.tick()
	verify(sim.world.count(sim.world.logistics_stock, 6) > 0, "Blocked remote output stores real products without loss")
	sim.session_paused = true
	verify(SaveStore.save_game(sim, "res://qa/full-cycle-logistics.json") == OK, "Save fully grown actual factory with both inventories and stations")
	var restored = WorldSim.new()
	verify(SaveStore.load_game(restored, "res://qa/full-cycle-logistics.json"), "Load actual end-to-end growth and logistics save")
	verify(JSON.stringify(restored.serialize()) == JSON.stringify(sim.serialize()), "Real bank, earned quotas, ports, research and cached materials remain identical")
