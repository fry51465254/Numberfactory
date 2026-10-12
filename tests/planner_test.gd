extends SceneTree

func _initialize():
	var sim = WorldSim.new(42)
	sim.world.expansions = 21
	sim.world.stage = 3
	sim.world.last_prime_expansion = 16
	sim.world.primes = [2, 3, 5, 7, 11]
	sim.world.recipes.append(65219)
	var factory = AutoFactory.new(sim)
	var produced = factory.produce({"65219": 3}, 9000)
	var conserved = sim.total_mass() == sim.emitted
	print("Planner regression: mined 7^2 * 11^3, delivered ", sim.world.count(sim.world.research_stock, 65219), ", conserved ", conserved)
	quit(0 if produced and conserved else 1)
