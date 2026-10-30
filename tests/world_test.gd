extends SceneTree

var checks = 0
var failures: Array = []

func verify(condition: bool, message: String):
	checks += 1
	if not condition: failures.append(message)

func _initialize():
	_test_generation()
	_test_progress()
	_test_production()
	_test_save()
	print("World: %d checks, %d failures" % [checks, failures.size()])
	for message in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)

func _test_generation():
	var a = WorldGenerator.new(42)
	var b = WorldGenerator.new(42)
	var c = WorldGenerator.new(99)
	var differences = 0
	for y in range(-8, 8):
		for x in range(-8, 8):
			var chunk = Vector2i(x, y)
			verify(a.deposits(chunk) == b.deposits(chunk), "Seed deterministic %s" % chunk)
			if a.deposits(chunk) != c.deposits(chunk): differences += 1
	verify(differences > 10, "Different seeds alter sparse deposit layout")
	verify(WorldGenerator.chunk_of(Vector2i(-1, -9)) == Vector2i(-1, -2), "Negative chunk floor")
	for stage in range(PlanetRules.prime_list(PlanetRules.CAPS[0]).size() - 2):
		var p = Vector2i(16 + (WorldProgress.prime_ring(stage) - 1) * 8 + 2, 2)
		var deposits = a.deposits(WorldGenerator.chunk_of(p))
		verify(deposits.size() == 1 and deposits[0].pos == p, "Guaranteed stage resource %d" % stage)
	var sim = WorldSim.new(42)
	verify(sim.world.bounds() == Rect2i(-16, -16, 32, 32), "Centered initial square")
	verify(sim.at(Vector2i(-8, -4)).value == 2 and sim.at(Vector2i(-8, 4)).value == 3, "Starter sources guaranteed")
	var before = sim.loaded_chunks.size()
	sim.at(Vector2i(10000, -10000))
	verify(sim.loaded_chunks.size() == before, "Locked distant query does not instantiate chunks")
	verify(not sim.accessible(Vector2i(16, 0)) and sim.accessible(Vector2i(-16, -16)), "Initial bounds edges")

func supply(progress: WorldProgress, cost: Dictionary):
	for value in cost:
		verify(progress.deposit(int(value), int(cost[value])), "Generated fee registered as research product")

func _test_progress():
	var w = WorldProgress.new(42)
	verify(w.expansion_cost == {"6": 20}, "First expansion teaches multiplication")
	verify(not w.expand(), "No expansion without stock")
	verify(not w.research_prime(), "Prime gate blocks early payment")
	var old_products = w.recipes.duplicate()
	for ordinal in range(3):
		supply(w, w.expansion_cost)
		var lifetime = w.lifetime.duplicate()
		verify(w.expand(), "Pay expansion %d" % ordinal)
		verify(w.lifetime == lifetime, "Spending retains lifetime deliveries")
		verify(w.bounds().size == Vector2i.ONE * (32 + 16 * (ordinal + 1)), "Regular square expansion")
	verify(w.primes == [2, 3] and w.prime_ready(), "Expansion only makes prime research available")
	supply(w, w.prime_cost)
	verify(w.research_prime() and w.primes == [2, 3, 5], "Prime 5 requires active research payment")
	verify(not w.tech_available("logistics"), "Logistics unavailable before 7")
	for product in old_products: verify(product in w.recipes, "Old research products retained")
	for ordinal in range(5):
		verify(w.prime_ready() == (ordinal >= 5), "Second prime spacing")
		supply(w, w.expansion_cost)
		verify(w.expand(), "Second stage expansion")
	verify(w.prime_ready(), "Five additional expansions open 7 research")
	supply(w, w.prime_cost)
	verify(w.research_prime() and 7 in w.primes, "Prime 7 unlock")
	for technology in ["ratio", "filter", "logistics"]:
		supply(w, w.tech_costs[technology])
		var quota = w.logistics_capacity
		verify(w.research_tech(technology), "Technology paid %s" % technology)
		verify(w.logistics_capacity == (2 if technology == "logistics" else quota), "First logistics unlock grants only two stations; no retroactive rewards")
		verify(not w.research_tech(technology), "No duplicate technology reward")
	for i in range(8):
		verify(not w.prime_ready(), "Next interval requires eight expansions")
		supply(w, w.expansion_cost)
		w.expand()
	verify(w.prime_ready(), "Third prime gate at eight expansions")
	for cost in [w.expansion_cost, w.prime_cost]:
		for value in cost:
			verify(int(value) <= FactorySim.MAX_VALUE, "Generated fee within exact numeric range")
			for prime in FactorySim.factors(int(value)): verify(prime in w.primes, "No future-prime circular dependency")

func _test_production():
	var sim = WorldSim.new(42)
	var p = Vector2i(-4, -4)
	verify(sim.place(p, "multiplier", 0), "Build at negative coordinate")
	verify(sim.place(p + Vector2i.LEFT, "belt", 0), "Rear input")
	verify(sim.place(p + Vector2i.UP, "belt", 1), "Side input")
	for pair in [[Vector2i.LEFT, 2], [Vector2i.UP, 3]]:
		sim.at(p + pair[0]).item = pair[1]
		sim.emitted += FactorySim.prime_count(pair[1])
	for i in range(42): sim.tick()
	verify(sim.at(p).output == 6, "Automatic multiplication on new world")
	verify(sim.total_mass() == sim.emitted, "New world multiplication conservation")
	verify(sim.place(Vector2i(-1, -1), "belt", 0), "Research input")
	sim.at(Vector2i(-1, -1)).item = 6
	sim.emitted += 2
	for i in range(11): sim.tick()
	verify(sim.world.count(sim.world.research_stock, 6) == 1, "Actual conveyor delivers research inventory")
	verify(sim.total_mass() == sim.emitted, "Research storage conservation")
	var stopped = sim.at(p).output
	sim.world.expansions = 20
	for i in range(30): sim.tick()
	verify(sim.at(p).output == stopped, "Expanding world preserves blocked outputs")
	var far = Vector2i(100, -100)
	verify(sim.place(far, "multiplier", 0), "Far negative/positive construction")
	sim.at(far).inputs = [2, 3]
	sim.emitted += 2
	for i in range(30): sim.tick()
	verify(sim.at(far).output == 6, "Offscreen production does not depend on camera")

func _test_save():
	var original = WorldSim.new(123)
	supply(original.world, original.world.expansion_cost)
	original.world.expand()
	original.place(Vector2i(-20, 0), "belt", 0)
	original.at(Vector2i(-20, 0)).item = 12
	original.at(Vector2i(-20, 0)).age = 0.17
	var data = JSON.parse_string(JSON.stringify(original.serialize()))
	var restored = WorldSim.new(999)
	verify(restored.restore(data), "Version 3 save accepted")
	verify(restored.world.serialize() == original.world.serialize(), "World goals, stock and quotas restored")
	verify(restored.at(Vector2i(-20, 0)).item == 12 and is_equal_approx(restored.at(Vector2i(-20, 0)).age, 0.17), "Cached item and age restored")
	verify(restored.elapsed == original.elapsed, "No offline elapsed-time advancement")
	verify(restored.generator.deposits(Vector2i(10, -10)) == original.generator.deposits(Vector2i(10, -10)), "Generator seed restored")
	var bad = data.duplicate(true)
	bad.world.primes = [2, 4]
	verify(not restored.restore(bad), "Corrupt prime state rejected")
	verify(restored.world.seed_value == 123, "Failed restore retains previous world")
	bad = data.duplicate(true)
	bad.loaded_chunks.append("not-a-chunk")
	verify(not restored.restore(bad), "Malformed chunk identifiers rejected")
	for corrupt in [{"6": -1}, {"6": 0}, {"06": 20}, {"6": 1.5}, {"6": "twenty"}]:
		bad = data.duplicate(true)
		bad.world.expansion_cost = corrupt
		verify(not restored.restore(bad), "Invalid generated cost rejected: %s" % corrupt)
	bad = data.duplicate(true)
	bad.world.tech_costs.erase("filter")
	verify(not restored.restore(bad), "Missing technology fee rejected before UI access")
	bad = data.duplicate(true)
	bad.world.research_stock = {"6": 999}
	verify(not restored.restore(bad), "Research stock cannot exceed lifetime delivered quantity")
	verify(WorldSim.new(9223372036854775807).world.seed_value == WorldProgress.MAX_SEED, "Seed bounded for exact browser JSON persistence")
	var min_seed = WorldSim.new(WorldProgress.MIN_SEED)
	verify(min_seed.world.seed_value == WorldProgress.MIN_SEED, "Signed 32-bit minimum seed supported")
	verify(restored.restore(JSON.parse_string(JSON.stringify(min_seed.serialize()))), "Minimum seed survives actual JSON restore")
	var late = WorldProgress.new(42)
	late.primes = [2, 3, 997, 1009, 499979]
	late.stage = 50
	for ordinal in range(12):
		for value in late._cost("expand", ordinal):
			verify(int(value) <= FactorySim.MAX_VALUE, "Very late prime fees cannot exceed numeric cap")
	var preview_sim = WorldSim.new(42)
	var generated_before = preview_sim.loaded_chunks.size()
	var preview = preview_sim.next_ring_resources().duplicate()
	verify(preview_sim.loaded_chunks.size() == generated_before, "Ring preview does not instantiate locked chunks")
	supply(preview_sim.world, preview_sim.world.expansion_cost)
	preview_sim.world.expand()
	var actual: Dictionary = {}
	for y in range(-3, 3):
		for x in range(-3, 3):
			if x >= -2 and x < 2 and y >= -2 and y < 2: continue
			for deposit in preview_sim.generator.deposits(Vector2i(x, y)):
				actual[deposit.value] = int(actual.get(deposit.value, 0)) + 1
	verify(actual == preview, "Displayed next-ring deposit counts match actual expansion")
	bad = data.duplicate(true)
	bad.loaded_chunks.erase("-3,0")
	verify(not restored.restore(bad), "Built factory cannot refer to missing generated chunk")
	bad = data.duplicate(true)
	for e in bad.entities:
		if e.kind == "source":
			e.value = 13
			break
	verify(not restored.restore(bad), "Restored minerals must match deterministic seed descriptions")
	bad = data.duplicate(true)
	bad.entities = bad.entities.filter(func(e): return e.kind != "source")
	verify(not restored.restore(bad), "Missing fixed minerals cannot silently erase guaranteed resources")
	bad = data.duplicate(true)
	bad.world.primes[0] = {}
	verify(not restored.restore(bad), "Malformed numeric arrays rejected without conversion errors")
	for corrupt in [1.5, "twelve", {}, null]:
		bad = data.duplicate(true)
		for e in bad.entities:
			if e.kind == "belt":
				e.item = corrupt
				break
		verify(not restored.restore(bad), "Corrupt material cannot truncate or crash after load: %s" % [corrupt])
