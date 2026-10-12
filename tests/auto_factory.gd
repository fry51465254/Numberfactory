class_name AutoFactory
extends RefCounted

var sim: WorldSim
var reserved: Dictionary = {}

class CrossingGrid extends AStarGrid2D:
	var crossings: Dictionary = {}
	func _compute_cost(from: Vector2i, to: Vector2i) -> float:
		var axis = 0 if from.x != to.x else 1
		if crossings.has(from) and crossings[from] != axis: return INF
		if crossings.has(to) and crossings[to] != axis: return INF
		return 4.0 if crossings.has(to) else 1.0

func _init(model: WorldSim):
	sim = model

func build(value: int, factor_order: Array = []) -> bool:
	# Test-only planner builds ordinary machines and belts; it never injects materials.
	var ingredients = FactorySim.factors(value) if factor_order.is_empty() else factor_order.duplicate()
	var product = 1
	for ingredient in ingredients:
		if ingredient not in sim.world.primes: return false
		product *= int(ingredient)
	if product != value or ingredients.size() < 2: return false
	for id in sim.entities.keys():
		var e = sim.entities.get(id, {})
		if not e.is_empty() and e.kind in ["belt", "multiplier", "splitter", "logistics"]: sim.remove(e.pos)
	sim.ensure_area(sim.world.bounds())
	reserved.clear()
	var machines: Array = []
	var inputs: Array = []
	for i in range(ingredients.size() - 1):
		var p = Vector2i(-6 + i * 2, -7)
		if not sim.place(p, "multiplier", 0): return false
		machines.append(p)
		inputs.append({"pos": p + Vector2i.UP, "value": ingredients[i + 1], "direction": 1})
		if i > 0 and sim.build_belt(p + Vector2i.LEFT, 0, 2) < 0: return false
	inputs.push_front({"pos": machines[0] + Vector2i.LEFT, "value": ingredients[0], "direction": 0})
	for input in inputs:
		reserved[FactorySim.key(input.pos)] = true
		reserved[FactorySim.key(input.pos - FactorySim.DIRS[input.direction])] = true
	var output = machines[-1] + Vector2i.RIGHT
	reserved[FactorySim.key(output)] = true
	if not connect_path(output, Vector2i(2, 0), 2, 0):
		print("No route to research for product ", value)
		return false
	var used: Dictionary = {}
	for input in inputs:
		var sources: Array = []
		for e in sim.entities.values():
			if e.kind == "source" and e.value == input.value: sources.append(e)
		sources.sort_custom(func(a, b): return a.pos.distance_squared_to(input.pos) < b.pos.distance_squared_to(input.pos))
		var connected = false
		for source in sources:
			var outlets = sim.source_sockets(source)
			outlets.sort_custom(func(a, b): return a.pos.distance_squared_to(input.pos) < b.pos.distance_squared_to(input.pos))
			for outlet in outlets:
				var id = FactorySim.key(outlet.pos)
				if used.has(id): continue
				if connect_path(outlet.pos, input.pos, input.direction, outlet.facing):
					used[id] = true
					connected = true
					break
			if connected: break
		if not connected:
			print("No route for prime ", input.value, " to ", input.pos, ", candidate mines ", sources.size())
			return false
	return true

func connect_path(start: Vector2i, end: Vector2i, end_direction: int, start_direction: int = -1) -> bool:
	if not sim.at(start).is_empty() or not sim.at(end).is_empty(): return false
	var grid = CrossingGrid.new()
	grid.region = sim.world.bounds()
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for id in sim.occupancy:
		var coordinates = id.split(",")
		grid.set_point_solid(Vector2i(int(coordinates[0]), int(coordinates[1])))
	for e in sim.entities.values():
		if e.kind == "belt" and e.layer == 0 and sim.can_cross(e.pos, (e.dir + 1) % 4) and sim.at(e.pos, 1).is_empty():
			grid.set_point_solid(e.pos, false)
			grid.crossings[e.pos] = 1 - e.dir % 2
	for id in reserved:
		var coordinates = id.split(",")
		grid.set_point_solid(Vector2i(int(coordinates[0]), int(coordinates[1])))
	# A route passing another mine's outlet would legitimately receive that prime too.
	# Reserve unused outlets so this test planner does not contaminate its ingredients.
	for e in sim.entities.values():
		if e.kind == "source":
			for port in sim.source_sockets(e):
				var outlet = port.pos
				if grid.is_in_boundsv(outlet): grid.set_point_solid(outlet)
	grid.set_point_solid(start, false)
	var approach = end - FactorySim.DIRS[end_direction]
	if not sim.at(approach).is_empty(): return false
	grid.set_point_solid(approach, false)
	var departure = start if start_direction < 0 else start + FactorySim.DIRS[start_direction]
	if not grid.is_in_boundsv(departure) or grid.is_point_solid(departure): return false
	if departure != start: grid.set_point_solid(start)
	var path = grid.get_id_path(departure, approach)
	if path.is_empty(): return false
	if departure != start: path.insert(0, start)
	path.append(end)
	# Check the whole route before committing; a failed candidate leaves no stray belts.
	for i in range(path.size()):
		var direction = end_direction if i == path.size() - 1 else FactorySim.DIRS.find(path[i + 1] - path[i])
		if not sim.can_place(path[i]) and not sim.can_cross(path[i], direction): return false
	for i in range(path.size()):
		var direction = end_direction if i == path.size() - 1 else FactorySim.DIRS.find(path[i + 1] - path[i])
		var entry = -1 if i == 0 else FactorySim.DIRS.find(path[i - 1] - path[i])
		if sim.build_belt(path[i], direction, entry, true) < 0: return false
	return true

func produce(cost: Dictionary, max_steps: int = 18000) -> bool:
	for value in cost:
		if sim.world.count(sim.world.research_stock, int(value)) >= int(cost[value]): continue
		if not build(int(value)):
			print("Cannot build generated recipe ", value)
			return false
		var produced = false
		for i in range(max_steps):
			if sim.world.count(sim.world.research_stock, int(value)) >= int(cost[value]):
				produced = true
				break
			sim.tick()
			if i % 3000 == 2999: print("Producing ", value, " step ", i + 1, ", stock ", sim.world.research_stock)
		if not produced:
			for e in sim.entities.values():
				if e.kind == "multiplier": print("Stalled machine ", e.pos, ", inputs ", e.inputs, ", output ", e.output)
			return false
	return sim.world.can_pay(cost)
