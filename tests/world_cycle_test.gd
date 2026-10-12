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
		verify(sim.build_belt(path[i], direction, entry, true) >= 0, "Build actual production belt %s" % path[i])

func produce(sim: WorldSim, cost: Dictionary) -> bool:
	for i in range(9000):
		if sim.world.can_pay(cost): return true
		sim.tick()
	return false

func _initialize():
	var sim = WorldSim.new(42)
	verify(sim.place(Vector2i(-4, -2), "multiplier", 0), "Place starter multiplier")
	route(sim, [Vector2i(-6, -4), Vector2i(-5, -4), Vector2i(-5, -2)], 0)
	route(sim, [Vector2i(-6, 4), Vector2i(-3, 4), Vector2i(-3, -3), Vector2i(-4, -3)], 1)
	route(sim, [Vector2i(-3, -2), Vector2i(-2, -2), Vector2i(-2, -1), Vector2i(-1, -1)], 0)
	verify(not sim.at(Vector2i(-3, -2), 1).is_empty(), "Real production crosses underground")
	for i in range(3):
		verify(produce(sim, sim.world.expansion_cost), "Mined products pay expansion %d" % i)
		var before = sim.world.count(sim.world.lifetime, 6)
		verify(sim.world.expand(), "Spend actual delivered stock")
		verify(sim.world.count(sim.world.lifetime, 6) == before, "Lifetime preserved after spending")
		verify(sim.total_mass() == sim.emitted, "Full source-to-research-to-expansion conservation")
	verify(sim.world.prime_ready() and 5 not in sim.world.primes, "Prime awaits voluntary research")
	verify(produce(sim, sim.world.prime_cost), "Mined products pay prime 5 research")
	verify(sim.world.research_prime(), "Research prime 5 using actual stock")
	var five = Vector2i(34, 2)
	verify(sim.at(five).value == 5 and sim.source_enabled(sim.at(five)), "New mine immediately obtainable inside opened square")
	verify(sim.place(five + Vector2i(2, 0), "belt", 0), "Connect newly available resource")
	for i in range(20): sim.tick()
	verify(sim.at(five + Vector2i(2, 0)).item == 5, "New resource actually produces")
	verify(sim.total_mass() == sim.emitted, "Conservation after new-prime production")
	var copy = WorldSim.new()
	verify(copy.restore(JSON.parse_string(JSON.stringify(sim.serialize()))), "Restore live factory after full first-stage cycle")
	verify(copy.total_mass() == sim.total_mass() and copy.emitted == sim.emitted, "Live factory material restored exactly")
	for i in range(300):
		sim.tick()
		copy.tick()
	verify(copy.world.serialize() == sim.world.serialize(), "Restored factory continues identically")
	for order in [[2, 2, 3], [3, 2, 2]]:
		var alternate = WorldSim.new(42)
		alternate.world.recipes.append(12)
		var planner = AutoFactory.new(alternate)
		verify(planner.build(12, order), "Build a real-mined alternate path %s" % str(order))
		verify(produce(alternate, {"12": 5}), "Actual %s production delivers the same research product 12" % str(order))
		var final_machine = alternate.at(Vector2i(-4, -7))
		verify(final_machine.last_inputs == [order[0] * order[1], order[2]], "Adaptive last machine uses intermediate 4 or 6 without a recipe")
		verify(alternate.total_mass() == alternate.emitted, "Alternate production path conserves all prime factors")
	print("World cycle: %d checks, %d failures; expansions %d, primes %s, lifetime %s" % [checks, failures.size(), sim.world.expansions, sim.world.primes, sim.world.lifetime])
	for message in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)
