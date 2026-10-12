extends SceneTree

class DryGenerator extends WorldGenerator:
	func random_density(_chunk: Vector2i) -> float:
		return 0.0

var checks = 0
var failures: Array = []

func verify(condition: bool, message: String):
	checks += 1
	if not condition: failures.append(message)

func ring_deposits(generator: WorldGenerator, ring: int, reverse: bool = false) -> Dictionary:
	var deposits: Dictionary = {}
	var chunks = WorldGenerator.ring_chunks(ring)
	if reverse: chunks.reverse()
	for chunk in chunks:
		for deposit in generator.deposits(chunk): deposits[FactorySim.key(deposit.pos)] = deposit
	return deposits

func square_deposits(generator: WorldGenerator, half: int) -> Dictionary:
	var deposits: Dictionary = {}
	for y in range(-half / 8, half / 8):
		for x in range(-half / 8, half / 8):
			for deposit in generator.deposits(Vector2i(x, y)): deposits[FactorySim.key(deposit.pos)] = deposit
	return deposits

func _initialize():
	_test_rings()
	_test_migration()
	_test_preview()
	print("Generation: %d checks, %d failures" % [checks, failures.size()])
	for message in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)

func _test_rings():
	verify(WorldGenerator.RANDOM_DENSITY == 0.05, "New worlds use the chosen five-percent density")
	var seeds: Array = [0, -1, 42, 99, 51465254, WorldProgress.MIN_SEED, WorldProgress.MAX_SEED]
	for seed_value in range(20): seeds.append(seed_value * 7919)
	for seed_value in seeds:
		var generator = WorldGenerator.new(seed_value)
		var shuffled = WorldGenerator.new(seed_value)
		for ring in range(1, 41):
			var actual = ring_deposits(generator, ring)
			verify(not actual.is_empty(), "Every expansion ring has at least one mine")
			verify(actual.values().any(func(deposit): return deposit.value in [2, 3]), "Every expansion ring has an immediately usable prime")
			verify(actual == ring_deposits(shuffled, ring, true), "Exploration order never changes a ring")
			var old_half = 16 + (ring - 1) * 8
			var inner = Rect2i(-old_half, -old_half, old_half * 2, old_half * 2)
			var outer = inner.grow(8)
			var valid = true
			for deposit in actual.values():
				valid = valid and outer.encloses(Rect2i(deposit.pos, Vector2i(2, 2))) and not inner.intersects(Rect2i(deposit.pos, Vector2i(2, 2)))
			verify(valid, "Guarantees occupy the newly opened band, including negative edges")
	for seed_value in seeds.slice(0, 7):
		var dry = DryGenerator.new(seed_value)
		for ring in range(1, 41):
			var deposits = ring_deposits(dry, ring)
			var basics = deposits.values().filter(func(deposit): return deposit.value in [2, 3])
			verify(basics.size() == 1, "A completely empty random ring adds exactly one usable fallback")
			verify(deposits.size() <= 2, "Fallback does not inflate sparse rings")
			for stage in range(5):
				if WorldProgress.prime_ring(stage) != ring: continue
				var pos = Vector2i(18 + (ring - 1) * 8, 2)
				verify(deposits.has(FactorySim.key(pos)) and deposits[FactorySim.key(pos)].value not in [2, 3], "Fallback preserves new-prime guarantees")
	var legacy = WorldGenerator.new(51465254, 4)
	var sparse = WorldGenerator.new(51465254)
	verify(square_deposits(legacy, 40).size() == 69, "Original seventy-percent terrain remains byte-for-byte reproducible")
	verify(square_deposits(sparse, 40).size() < 20, "Five-percent density remains sparse after fallback")
	var mixed = WorldGenerator.new(51465254, 2)
	verify(ring_deposits(mixed, 1) == ring_deposits(legacy, 1), "Already-open rings retain old terrain")
	verify(ring_deposits(mixed, 2) == ring_deposits(sparse, 2), "New rings use sparse terrain and safety rules")

func _test_migration():
	var old = WorldSim.new(42, 4)
	old.world.expansions = 3
	old.ensure_area(old.world.bounds())
	old.place(Vector2i(-4, -2), "multiplier", 0)
	old.at(Vector2i(-4, -2)).inputs = [2, 3]
	old.emitted += 2
	old.world.deposit(6, 7)
	old.emitted += 14
	var legacy_data = JSON.parse_string(JSON.stringify(old.serialize()))
	legacy_data.erase("generation_version")
	legacy_data.erase("sparse_from_ring")
	var restored = WorldSim.new()
	verify(restored.restore(legacy_data), "Old saves upgrade without regenerating ore")
	verify(restored.sparse_from_ring == 4, "Legacy save cutover begins at its next expansion")
	verify(restored.world.serialize() == old.world.serialize() and restored.total_mass() == old.total_mass(), "Migration preserves all material and progress")
	var restored_entities = restored.serialize().entities
	var old_entities = old.serialize().entities
	verify(restored_entities == old_entities, "Existing machines, ore, buffers and configuration remain intact")
	var new_data = restored.serialize()
	var copy = WorldSim.new()
	verify(copy.restore(JSON.parse_string(JSON.stringify(new_data))), "Generation cutover persists after saving again")
	verify(copy.sparse_from_ring == 4 and copy.serialize() == restored.serialize(), "Repeated restore cannot move the cutover")
	for invalid in [-1, 5, 1.5, "four", null]:
		var bad = new_data.duplicate(true)
		bad.sparse_from_ring = invalid
		var before = copy.serialize()
		verify(not copy.restore(bad) and copy.serialize() == before, "Invalid cutover metadata is transactional")
	var unknown = new_data.duplicate(true)
	unknown.generation_version = 999
	verify(not copy.restore(unknown), "Unknown terrain versions are rejected")
	copy.world.expansions += 1
	copy.ensure_area(copy.world.bounds())
	var new_ring = ring_deposits(WorldGenerator.new(42), 4)
	verify(new_ring.values().all(func(deposit): return copy.at(deposit.pos).get("value", 0) == deposit.value), "First new expansion instantiates sparse ores after legacy migration")
	var expanded = WorldSim.new()
	verify(expanded.restore(JSON.parse_string(JSON.stringify(copy.serialize()))) and expanded.serialize() == copy.serialize(), "Mixed legacy and sparse land restores after expansion")
	var sparse = WorldSim.new(42)
	verify(WorldSim.new().restore(JSON.parse_string(JSON.stringify(sparse.serialize()))), "New sparse saves validate their fixed deposits")

func _test_preview():
	var sim = WorldSim.new(51465254)
	for ring in range(1, 13):
		var loaded = sim.loaded_chunks.duplicate()
		var predicted = sim.next_ring_resources().duplicate()
		verify(sim.loaded_chunks == loaded, "Preview does not instantiate unopened land")
		verify(predicted.get(2, 0) + predicted.get(3, 0) >= 1, "Preview includes the usable ring guarantee")
		var actual: Dictionary = {}
		for deposit in ring_deposits(sim.generator, ring).values(): actual[deposit.value] = int(actual.get(deposit.value, 0)) + 1
		verify(actual == predicted, "Preview and actual expansion agree exactly")
		sim.world.expansions += 1
	var old = WorldSim.new(51465254, 1)
	old._preview_key = "stale"
	old._preview_resources = {2: 999}
	old.reset(51465254)
	verify(old.sparse_from_ring == 0 and old.generator.sparse_from_ring == 0, "New-world reset adopts the new rules")
	verify(old._preview_key.is_empty() and old._preview_resources.is_empty(), "Reset invalidates previous cached previews")
