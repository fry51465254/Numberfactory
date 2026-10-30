extends SceneTree

var checks = 0
var failures: Array = []
var galaxy = GalaxySim.new(42)

func verify(condition: bool, message: String) -> bool:
	checks += 1
	if not condition: failures.append(message)
	return condition

func pay(sim: WorldSim, action: String) -> bool:
	var cost = sim.world.expansion_cost if action == "expand" else sim.world.prime_cost if action == "prime" else sim.world.tech_costs[action]
	var factory = AutoFactory.new(sim, galaxy)
	if not verify(factory.produce(cost), "Real interplanetary production supplies tier %d %s %s" % [sim.world.tier, action, cost]): return false
	verify(galaxy.total_mass() == galaxy.emitted_mass(), "All planets conserve resources before payment")
	var success = sim.world.expand() if action == "expand" else sim.world.research_prime() if action == "prime" else sim.world.research_tech(action)
	if not verify(success, "Pay actual production for " + action): return false
	galaxy.sync_progress()
	DirAccess.make_dir_recursive_absolute("res://qa")
	verify(SaveStore.save_game(galaxy, "res://qa/galaxy-growth-live.json") == OK, "Checkpoint actual interplanetary growth")
	print("Galaxy growth tier ", sim.world.tier, " action ", action, ", ring ", sim.world.expansions, ", largest prime ", sim.world.primes[-1])
	return true

func clear(sim: WorldSim):
	for e in sim.entities.values().duplicate():
		if e.kind in BuildLayout.FIELDS: sim.remove(e.pos)

func export_mines(sim: WorldSim, values: Array) -> bool:
	clear(sim)
	if not verify(sim.place(Vector2i(-4, -4), "stellar", 0), "Build real export tower"): return false
	var planner = AutoFactory.new(sim, galaxy)
	for i in range(values.size()):
		var source = sim.entities.values().filter(func(e): return e.kind == "source" and e.value == values[i])[0]
		var outlet = source.pos + Vector2i(2, 0)
		var destination = Vector2i(-5, -4 + i)
		if outlet.distance_squared_to(destination) == 1:
			if not verify(sim.build_belt(outlet, 0, 2) >= 0 and sim.build_belt(destination, 0, 2) >= 0, "Wire adjacent real mine to stellar export"): return false
		elif not verify(planner.connect_path(outlet, destination, 0, 0), "Wire real mine to stellar export"): return false
	return true

func _initialize():
	if "--resume" in OS.get_cmdline_user_args():
		if not verify(SaveStore.load_game(galaxy, "res://qa/galaxy-growth-live.json"), "Resume actual-production checkpoint"): finish(); return
	var home = galaxy.current()
	home = galaxy.planets[0]
	for prime in [5, 7]:
		if prime in home.world.primes: continue
		while not home.world.prime_ready():
			if not pay(home, "expand"): finish(); return
		if not pay(home, "prime"): finish(); return
	for technology in ["ratio", "filter", "logistics", "interstellar"]:
		if technology in home.world.technologies: continue
		if not pay(home, technology): finish(); return
	verify(galaxy.network.capacity >= 2, "Real stellar research grants first pair")
	if not export_mines(home, [2, 3]): finish(); return
	verify(galaxy.travel(1), "Travel to medium with actual home progression")
	var medium = galaxy.current()
	if medium.at(Vector2i(4, 4)).is_empty() and not verify(medium.place(Vector2i(4, 4), "stellar", 0), "Build medium import tower"): finish(); return
	for tier in [1, 2]:
		var sim = galaxy.current()
		while sim.world.next_resource() > 0:
			while not sim.world.prime_ready():
				if not pay(sim, "expand"): finish(); return
				if sim.world.expansions >= 2 and "ore1" not in sim.world.technologies and not pay(sim, "ore1"): finish(); return
				if sim.world.expansions >= 5 and "ore2" not in sim.world.technologies and not pay(sim, "ore2"): finish(); return
			if not pay(sim, "prime"): finish(); return
		verify(sim.world.primes[-1] == PlanetRules.CAPS[tier] and not sim.world.research_prime(), "Real planet reaches capped synthesis tree")
		if not pay(sim, "expand"): finish(); return
		verify(sim.world.next_resource() == 0, "Expansion using the final prime does not grow beyond the cap")
		if tier == 1:
			if not export_mines(medium, [17]): finish(); return
			verify(galaxy.travel(2), "Actual medium progression unlocks hard planet")
			if galaxy.current().at(Vector2i(4, 4)).is_empty() and not verify(galaxy.current().place(Vector2i(4, 4), "stellar", 0), "Build hard import tower"): finish(); return
	verify(galaxy.total_mass() == galaxy.emitted_mass(), "Full real interplanetary growth conserves all materials")
	DirAccess.make_dir_recursive_absolute("res://qa")
	verify(SaveStore.save_game(galaxy, "res://qa/galaxy-growth-checkpoint.json") == OK, "Save full real interplanetary checkpoint")
	var restored = GalaxySim.new()
	verify(SaveStore.load_game(restored, "res://qa/galaxy-growth-checkpoint.json"), "Restore full real interplanetary progression")
	verify(JSON.stringify(restored.serialize()) == JSON.stringify(galaxy.serialize()), "All real factories, cargo, research and tower quotas restored")
	finish()

func finish():
	print("Galaxy growth: %d checks, %d failures; tiers %d, cap %d, towers %d/%d" % [checks, failures.size(), galaxy.planets.size(), galaxy.current().world.primes[-1], galaxy.network.used, galaxy.network.capacity])
	for message in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)
