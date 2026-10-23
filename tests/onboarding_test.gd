extends SceneTree

var checks = 0
var failures: Array = []

func verify(condition: bool, message: String):
	checks += 1
	if not condition: failures.append(message)

func _initialize():
	var sim = WorldSim.new(42)
	var factory = AutoFactory.new(sim)
	for prime in [5, 7]:
		while not sim.world.prime_ready():
			var cost = sim.world.expansion_cost.duplicate()
			if not factory.produce(cost):
				verify(false, "Actual factory cannot supply expansion")
				finish(sim)
				return
			verify(sim.total_mass() == sim.emitted, "Real expansion production conserves every factor")
			verify(sim.world.expand(), "Pay expansion with actually mined products")
			print("Onboarding expansion ", sim.world.expansions, ", paid ", cost)
		verify(factory.produce(sim.world.prime_cost), "Produce the next prime research products")
		verify(sim.world.research_prime() and prime in sim.world.primes, "Actively research the new prime")
		verify(sim.total_mass() == sim.emitted, "Paid prime research conserves materials")
	for technology in ["ratio", "filter", "logistics"]:
		verify(factory.produce(sim.world.tech_costs[technology]), "Actual production supplies " + technology)
		verify(sim.world.research_tech(technology), "Purchase " + technology)
		verify(sim.total_mass() == sim.emitted, "Technology purchase conserves materials")
	verify(sim.world.primes == [2, 3, 5, 7] and sim.world.expansions == 8 and sim.world.logistics_capacity == 2, "Fresh sparse world reaches shared logistics through its actual progression")
	DirAccess.make_dir_recursive_absolute("res://qa")
	verify(SaveStore.save_game(sim, "res://qa/onboarding_checkpoint.json") == OK, "Save independent onboarding checkpoint")
	var copy = WorldSim.new()
	verify(SaveStore.load_game(copy, "res://qa/onboarding_checkpoint.json"), "Restore onboarding progress through actual file I/O")
	verify(JSON.stringify(copy.serialize()) == JSON.stringify(sim.serialize()), "Real progression and in-flight materials restore exactly")
	finish(sim)

func finish(sim: WorldSim):
	print("Onboarding: %d checks, %d failures; expansions %d, primes %s, simulated %.1f minutes" % [checks, failures.size(), sim.world.expansions, sim.world.primes, sim.elapsed / 60.0])
	for message in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)
