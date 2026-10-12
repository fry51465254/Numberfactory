extends SceneTree

var checks = 0
var failures: Array = []

func verify(condition: bool, message: String):
	checks += 1
	if not condition: failures.append(message)

func _initialize():
	var sim = WorldSim.new(42)
	if "--resume" in OS.get_cmdline_user_args():
		if not SaveStore.load_game(sim, "res://qa/growth_checkpoint.json"):
			push_error("No valid actual-production checkpoint to resume")
			quit(1)
			return
	var factory = AutoFactory.new(sim)
	for prime in [5, 7, 11, 13]:
		if prime in sim.world.primes: continue
		while not sim.world.prime_ready():
			var built = factory.produce(sim.world.expansion_cost)
			verify(built, "Actual mined production pays expansion %d, %s" % [sim.world.expansions + 1, sim.world.expansion_cost])
			if not built: _finish(sim); return
			verify(sim.total_mass() == sim.emitted, "Conservation before expansion")
			verify(sim.world.expand(), "Pay actual expansion")
			_checkpoint(sim)
			print("Growth expansion ", sim.world.expansions, ", deliveries ", sim.world.lifetime)
		verify(factory.produce(sim.world.prime_cost), "Produce prime research ingredients %d" % prime)
		verify(sim.world.research_prime() and prime in sim.world.primes, "Pay active prime research %d" % prime)
		verify(sim.total_mass() == sim.emitted, "Conservation after research")
		print("Growth prime ", prime, " unlocked")
		if prime == 7:
			for technology in ["ratio", "filter", "logistics"]:
				if technology in sim.world.technologies: continue
				var built = factory.produce(sim.world.tech_costs[technology])
				verify(built, "Real factory supplies technology %s" % technology)
				if not built: _finish(sim); return
				verify(sim.world.research_tech(technology), "Technology purchased %s" % technology)
				verify(sim.total_mass() == sim.emitted, "Conservation after technology")
		_checkpoint(sim)
	verify(factory.produce(sim.world.expansion_cost), "Produce products containing newly unlocked 13")
	verify(sim.world.expand(), "Pay expansion using new 13 products")
	_checkpoint(sim)
	var copy = WorldSim.new()
	verify(copy.restore(JSON.parse_string(JSON.stringify(sim.serialize()))), "Restore multi-stage live factory")
	verify(copy.world.serialize() == sim.world.serialize() and copy.total_mass() == sim.total_mass(), "Inventories, targets, quotas and live materials preserved")
	_finish(sim)

func _checkpoint(sim: WorldSim):
	DirAccess.make_dir_recursive_absolute("res://qa")
	verify(SaveStore.save_game(sim, "res://qa/growth_checkpoint.json") == OK, "Save actual-production checkpoint without advancing time")

func _finish(sim: WorldSim):
	print("Growth: %d checks, %d failures; expansions %d, primes %s, logistics quota %d" % [checks, failures.size(), sim.world.expansions, sim.world.primes, sim.world.logistics_capacity])
	for message in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)
