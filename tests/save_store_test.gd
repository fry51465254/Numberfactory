extends SceneTree

var checks = 0
var failures: Array = []
const PATH = "res://qa/test-world-save.json"

func verify(condition: bool, message: String):
	checks += 1
	if not condition: failures.append(message)

func _initialize():
	DirAccess.make_dir_recursive_absolute("res://qa")
	var sim = WorldSim.new(42)
	sim.world.primes = [2, 3, 5, 7]
	sim.world.stage = 2
	sim.world.expansions = 8
	sim.world.last_prime_expansion = 8
	sim.world.technologies = ["ratio", "filter", "logistics"]
	sim.world.logistics_capacity = 2
	sim.world.deposit(6, 9)
	sim.place(Vector2i(-4, 0), "logistics", 0)
	sim.place(Vector2i(4, 0), "logistics", 0)
	sim.place(Vector2i(-2, 0), "belt", 0)
	sim.at(Vector2i(-4, 0)).outputs[0] = 12
	sim.session_paused = true
	sim.place(Vector2i(-4, -2), "multiplier", 0)
	sim.at(Vector2i(-4, -2)).inputs = [2, 3]
	sim.world.logistics_stock = {"12": 7}
	sim.emitted = 41
	for i in range(7): sim.tick()
	verify(SaveStore.save_game(sim, PATH) == OK, "Write actual JSON save through atomic rename")
	var copy = WorldSim.new(123)
	verify(SaveStore.load_game(copy, PATH), "Load actual JSON file")
	verify(JSON.stringify(copy.serialize()) == JSON.stringify(sim.serialize()), "Full world, inventory, cached materials and pause identical")
	verify(copy.logistics_used() == 2 and copy.world.logistics_capacity == 2, "Actual file preserves used and total allowance")
	verify(copy.world.count(copy.world.research_stock, 6) == 9 and copy.world.count(copy.world.logistics_stock, 12) == 7, "Two independent inventories restored together")
	verify(copy.total_mass() == copy.emitted, "Restored mixed inventory and machinery conserve materials")
	var before = copy.serialize()
	verify(copy.serialize() == before, "Loading does not advance production")
	for i in range(30): sim.tick()
	verify(SaveStore.save_game(sim, PATH) == OK, "Atomic save overwrites existing file")
	verify(SaveStore.load_game(copy, PATH) and JSON.stringify(copy.serialize()) == JSON.stringify(sim.serialize()), "Overwrite restores exact current factory")
	verify(not FileAccess.file_exists(PATH + ".tmp"), "Successful save leaves no temporary file")
	DirAccess.remove_absolute(PATH)
	print("SaveStore: %d checks, %d failures" % [checks, failures.size()])
	for message in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)
