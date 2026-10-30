extends SceneTree

var checks = 0
var failures: Array = []
var scene

func verify(condition: bool, message: String):
	checks += 1
	if not condition: failures.append(message)

func difference(a, b, path: String = "") -> String:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return path + " field count differs"
		for id in a:
			if not b.has(id): return path + "/" + str(id) + " missing"
			var found = difference(a[id], b[id], path + "/" + str(id))
			if not found.is_empty(): return found
	elif a is Array and b is Array:
		if a.size() != b.size(): return path + " size differs"
		for i in range(a.size()):
			var found = difference(a[i], b[i], path + "/" + str(i))
			if not found.is_empty(): return found
	elif (typeof(a) == TYPE_FLOAT or typeof(b) == TYPE_FLOAT) and FactorySim.valid_number(a) and FactorySim.valid_number(b):
		if absf(float(a) - float(b)) > 0.00000001: return "%s: %.12f != %.12f" % [path, a, b]
	elif a != b: return "%s: %s != %s" % [path, str(a), str(b)]
	return ""

func fund(w: WorldProgress, cost: Dictionary):
	for value in cost: w.deposit(int(value), int(cost[value]))

func unlock(g: GalaxySim):
	var w = g.planets[0].world
	while w.expansions < 8:
		fund(w, w.expansion_cost)
		verify(w.expand(), "Pay home ring through normal progression")
		if w.prime_ready():
			fund(w, w.prime_cost)
			verify(w.research_prime(), "Pay home prime research")
	for technology in ["ratio", "filter", "logistics", "interstellar"]:
		fund(w, w.tech_costs[technology])
		verify(w.research_tech(technology), "Pay technology " + technology)
	g.sync_progress()

func _initialize():
	call_deferred("run")

func test_caps_and_generation():
	for tier in range(3):
		var w = WorldProgress.new(42, tier)
		var researches = 0
		while w.next_resource() > 0 and researches < 20:
			while not w.prime_ready():
				fund(w, w.expansion_cost)
				verify(w.expand(), "Tiered expansion paid")
			fund(w, w.prime_cost)
			verify(w.research_prime(), "Tiered prime research paid")
			researches += 1
		verify(w.primes[-1] == PlanetRules.CAPS[tier], "Research stops at planet cap")
		var before = w.serialize()
		verify(not w.research_prime() and w.serialize() == before and not w.prime_ready(), "Cap rejects repeated research without spending")
		fund(w, w.expansion_cost)
		verify(w.expand() and w.next_resource() == 0, "Expansion continues beyond final prime")
		var copy = WorldProgress.new()
		verify(copy.restore(w.serialize()) and copy.serialize() == w.serialize(), "Tiered progression roundtrip")
		if tier > 0:
			var early = WorldProgress.new(42, tier)
			verify(early.expansion_cost.values()[0] <= 6, "Foreign first bill has few units")
			verify(early.expansion_cost.keys().all(func(v): return PlanetRules.STARTS[tier] in FactorySim.factors(int(v))), "Foreign bill requires new local prime")
			verify(not early.tech_available("ore1"), "Composite mining is gated")
			for i in range(2):
				fund(early, early.expansion_cost)
				early.expand()
			fund(early, early.tech_costs.ore1)
			verify(early.research_tech("ore1") and early.ore_level() == 1, "One-step ore research is paid")
			var probe = WorldSim.new(42, 0, tier)
			probe.world = early
			var local_prime = PlanetRules.STARTS[tier]
			var factor = 2 if tier == 1 else 17
			verify(probe.source_enabled({"value": local_prime * factor}) and not probe.source_enabled({"value": local_prime * factor * (3 if tier == 1 else 2)}), "One-step unlock enables only the researched composite depth")
			for i in range(3):
				fund(early, early.expansion_cost)
				early.expand()
			fund(early, early.tech_costs.ore2)
			verify(early.research_tech("ore2") and early.ore_level() == 2, "Two-step ore research is paid")
			verify(probe.source_enabled({"value": local_prime * factor * (3 if tier == 1 else 2)}), "Two-step ore unlock actually activates its source")
			probe.ensure_area(probe.world.bounds())
			var restored_planet = WorldSim.new()
			verify(restored_planet.restore(probe.serialize()) and restored_planet.world.tier == tier, "Alien world with composite terrain restores into a fresh model")
	var counts = [0, 0, 0]
	var composites = [false, false]
	for seed_value in [42, 99, -123, 1001]:
		for tier in range(3):
			var a = WorldGenerator.new(seed_value, 0, tier, PlanetRules.CAPS[tier])
			var b = WorldGenerator.new(seed_value, 0, tier, PlanetRules.CAPS[tier])
			if tier > 0:
				var landing = WorldSim.new(seed_value, 0, tier)
				verify(landing.at(Vector2i(-8, -4)).value == PlanetRules.STARTS[tier] and landing.source_enabled(landing.at(Vector2i(-8, -4))), "Landing has enabled new prime")
			for ring in range(1, 18):
				for chunk in WorldGenerator.ring_chunks(ring):
					var deposits = a.deposits(chunk)
					verify(deposits == b.deposits(chunk), "Planet generation deterministic")
					counts[tier] += deposits.size()
					for deposit in deposits:
						var parts = FactorySim.factors(deposit.value)
						verify(parts.all(func(p): return p <= PlanetRules.CAPS[tier]), "Every ore obeys synthesis cap")
						if tier > 0:
							verify(deposit.value >= PlanetRules.STARTS[tier] and parts.size() <= 3, "Alien ore omits complete base materials and has at most two synthesis steps")
							if parts.size() > 1: composites[tier - 1] = true
	verify(counts[0] > counts[1] and counts[1] > counts[2], "Actual ore count decreases with difficulty")
	verify(composites == [true, true], "Both alien tiers generate composite shortcuts")
	print("Planet ore counts across four seeds: ", counts)

func test_network_rules():
	var g = GalaxySim.new(42)
	verify(not g.travel(1) and not g.travel(2), "Travel is locked before interstellar research")
	unlock(g)
	verify(g.network.capacity == 2 and g.network.used == 0, "First tower pair has no retroactive rewards")
	verify(g.travel(1) and not g.travel(2), "Medium opens before hard")
	var medium = g.current()
	verify(medium.world.logistics_stock.is_empty() and medium.world.research_stock.is_empty(), "Colonies keep independent local inventories")
	for i in range(5):
		fund(medium.world, medium.world.expansion_cost)
		medium.world.expand()
		g.sync_progress()
	verify(g.network.capacity == 2, "Five growth actions do not grant a premature pair")
	fund(medium.world, medium.world.prime_cost)
	verify(medium.world.research_prime(), "Research also contributes to tower pair progress")
	g.sync_progress()
	verify(g.network.capacity == 4, "Six growth actions award exactly two towers")
	for i in range(4): g.sync_progress()
	verify(g.network.capacity == 4, "Repeated synchronization cannot farm quota")
	while medium.world.next_resource() != 0:
		while not medium.world.prime_ready():
			fund(medium.world, medium.world.expansion_cost)
			medium.world.expand()
		fund(medium.world, medium.world.prime_cost)
		medium.world.research_prime()
	verify(g.travel(2) and g.current().world.primes[-1] == 31, "Hard landing requires completed medium prime research and starts at 31")
	var sample = {"value": 31 * 17}
	verify(not g.current().source_enabled(sample), "Composite source is locked before ore research")
	verify(g.current().place(Vector2i(4, 4), "stellar", 0), "Build tower on hard planet")
	var before = g.network.used
	g.current().remove(Vector2i(5, 5))
	verify(g.network.used == before - 1, "Removing any occupied tower cell returns global quota")

func clear_buildables(sim: WorldSim):
	for e in sim.entities.values().duplicate():
		if e.kind in BuildLayout.FIELDS: sim.remove(e.pos)

func test_ports_and_fairness():
	var g = GalaxySim.new(42)
	unlock(g)
	g.travel(1)
	for planet in g.planets:
		planet.world.lifetime.clear()
		planet.world.research_stock.clear()
		clear_buildables(planet)
	var home = g.planets[0]
	verify(home.place(Vector2i(4, 4), "stellar", 0), "Build eight-input tower")
	var tower = home.at(Vector2i(4, 4))
	for port in home.logistics_ports(tower):
		home.build_belt(port.pos, (port.facing + 2) % 4)
		var belt = home.at(port.pos)
		belt.item = 2 if port.index % 2 == 0 else 3
		belt.age = FactorySim.TRAVEL
		home.emitted += 1
	verify(home.logistics_ports(tower).all(func(port): return port.mode == "input"), "All eight independent sockets can be inputs")
	for i in range(90): g.tick()
	verify(g.network.count(2) == 4 and g.network.count(3) == 4 and tower.log_recent.size() == 8, "All eight mixed input buffers accepted without loss")
	verify(g.total_mass() == g.emitted_mass(), "Eight-port intake conserves material")
	# Isolate periodic single-item supply and keep both consumers ready each cycle.
	g.network.stock.clear()
	home.discarded += 8
	for planet in g.planets: clear_buildables(planet)
	for planet in g.planets:
		verify(planet.place(Vector2i(4, 4), "stellar", 0), "Build competing interplanetary output")
		planet.build_belt(Vector2i(6, 4), 0)
		planet.at(Vector2i(4, 4)).outputs[0] = 2
	var received = [0, 0]
	for pulse in range(40):
		for i in range(2):
			var belt = g.planets[i].at(Vector2i(6, 4))
			if belt.item != 0:
				received[i] += 1
				belt.item = 0
				g.planets[i].discarded += 1
		g.network.stock["2"] = 1
		home.emitted += 1
		for i in range(16): g.tick()
	for i in range(2):
		if g.planets[i].at(Vector2i(6, 4)).item != 0: received[i] += 1
	verify(received[0] + received[1] == 40 and absi(received[0] - received[1]) <= 1, "Periodic scarce stock is fairly shared across planets without duplicate withdrawals")
	verify(g.total_mass() == g.emitted_mass(), "Competing global withdrawals conserve cargo")

func route(sim: WorldSim, points: Array, final_direction: int):
	var cells: Array = []
	for i in range(points.size() - 1):
		var p = points[i]
		while p != points[i + 1]:
			cells.append(p)
			p += Vector2i(signi(points[i + 1].x - p.x), signi(points[i + 1].y - p.y))
	cells.append(points[-1])
	for i in range(cells.size()):
		var direction = final_direction if i == cells.size() - 1 else FactorySim.DIRS.find(cells[i + 1] - cells[i])
		var entry = (direction + 2) % 4 if i == 0 else FactorySim.DIRS.find(cells[i - 1] - cells[i])
		verify(sim.build_belt(cells[i], direction, entry) >= 0, "Route real interplanetary production")

func test_real_transport() -> GalaxySim:
	var g = GalaxySim.new(42)
	unlock(g)
	g.travel(1)
	var home = g.planets[0]
	var alien = g.planets[1]
	# Unit progression fixtures are isolated from the production and conservation evidence.
	for p in g.planets:
		p.world.research_stock.clear()
		p.world.lifetime.clear()
		p.world.spent_mass = 0
		clear_buildables(p)
	verify(home.place(Vector2i(-4, -4), "stellar", 0), "Home tower built")
	verify(alien.place(Vector2i(-4, -4), "stellar", 0), "Alien tower built")
	verify(not home.place(Vector2i(4, 4), "stellar", 0), "Third tower refused globally")
	route(home, [Vector2i(-6, -4), Vector2i(-5, -4)], 0)
	route(home, [Vector2i(-6, 4), Vector2i(-6, -3), Vector2i(-5, -3)], 0)
	home.at(Vector2i(-6, 4)).entry = 2
	verify(alien.place(Vector2i(-1, -3), "multiplier", 0), "Alien multiplier built")
	var tower = alien.at(Vector2i(-4, -4))
	tower.outputs[1] = 2
	route(alien, [Vector2i(-2, -3)], 0)
	route(alien, [Vector2i(-6, -4), Vector2i(-6, -6), Vector2i(-1, -6), Vector2i(-1, -4)], 1)
	alien.at(Vector2i(-6, -4)).entry = 2
	route(alien, [Vector2i(-1, -2), Vector2i(-1, -1)], 0)
	for i in range(1800):
		g.tick()
		if i % 90 == 0: verify(g.total_mass() == g.emitted_mass(), "Cross-world real mining conserves every prime factor")
	verify(alien.world.count(alien.world.lifetime, 34) >= 10, "Imported 2 and landing 17 produce research product 34")
	verify(g.network.count(3) > 10 and home.world.logistics_stock.is_empty(), "One tower simultaneously imports multiple numbers without using local bank")
	verify(home.logistics_ports(home.at(Vector2i(-4, -4))).filter(func(port): return port.mode == "input").size() == 2, "Two simultaneous tower input ports detected")
	var amount = alien.world.count(alien.world.research_stock, 34)
	verify(alien.world.expand() and alien.world.count(alien.world.research_stock, 34) == amount - 4, "Actually produced foreign bill pays first expansion")
	# Return a newly mined alien prime through the same global network.
	for p in [Vector2i(-6, -4), Vector2i(-6, -5), Vector2i(-6, -6)]: alien.remove(p)
	route(alien, [Vector2i(-6, -4), Vector2i(-5, -4)], 0)
	home.at(Vector2i(-4, -4)).outputs[0] = 17
	route(home, [Vector2i(-2, -4), Vector2i(1, -4)], 0)
	var emitted_before = home.emitted
	for i in range(600): g.tick()
	verify(home.emitted > emitted_before and home.at(Vector2i(1, -4)).item == 17, "Off-screen home keeps producing while receiving alien prime")
	verify(g.network.count(17) > 0 and g.total_mass() == g.emitted_mass(), "Bidirectional stellar transfers conserve resources")
	var station_nodes = BuildLayout.copy(home, [FactorySim.key(Vector2i(-4, -4))])
	verify(not BuildLayout.plan(home, station_nodes, Vector2i(6, 6)).valid, "Blueprint cannot bypass global tower allowance")
	return g

func test_saves(g: GalaxySim):
	g.paused = true
	var snapshot = JSON.parse_string(JSON.stringify(g.serialize()))
	var copy = GalaxySim.new(99)
	verify(copy.restore(snapshot), "Restore all planets, global inventory and active landing")
	verify(JSON.stringify(copy.serialize()) == JSON.stringify(g.serialize()), "Galaxy JSON roundtrip exact")
	for i in range(120):
		g.tick()
		copy.tick()
	var delta = difference(copy.serialize(), g.serialize())
	if not delta.is_empty(): print("Continuation difference: ", delta)
	verify(delta.is_empty() and copy.total_mass() == copy.emitted_mass(), "Restored worlds continue with exact cargo and sub-nanosecond timer tolerance")
	DirAccess.make_dir_recursive_absolute("res://qa")
	verify(SaveStore.save_game(g, "res://qa/galaxy-checkpoint.json") == OK, "Atomic galaxy file save")
	verify(SaveStore.load_game(copy, "res://qa/galaxy-checkpoint.json"), "Actual galaxy file load")
	var before = copy.serialize()
	for field in ["capacity", "pairs_awarded", "active_planet", "prime_cap"]:
		var bad = g.serialize().duplicate(true)
		bad[field] = 999
		verify(not copy.restore(bad) and copy.serialize() == before, "Invalid galaxy " + field + " rejected atomically")
	var bad = g.serialize().duplicate(true)
	bad.stock["47"] = 1
	verify(not copy.restore(bad) and copy.serialize() == before, "Beyond-cap cargo rejected")
	bad = g.serialize().duplicate(true)
	bad.planets[1].world.tech_costs.ore1 = "invalid"
	verify(not copy.restore(bad) and copy.serialize() == before, "Malformed new research costs rejected atomically")
	bad = g.serialize().duplicate(true)
	bad.planets[1].world.growth_events += 100
	verify(not copy.restore(bad) and copy.serialize() == before, "Forged growth count cannot grant tower pairs")
	var legacy = WorldSim.new(42).serialize()
	legacy.world.erase("tier")
	legacy.world.erase("growth_events")
	for id in ["interstellar", "ore1", "ore2"]: legacy.world.tech_costs.erase(id)
	legacy.erase("generation_limit")
	verify(copy.restore(legacy) and copy.planets.size() == 1 and copy.current().world.tier == 0, "Legacy world migrates into a single home planet")
	verify(copy.serialize().version == 4 and copy.network.capacity == 0, "Migration has no free stellar quota")

func test_interface():
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.paused = true
	unlock(scene.galaxy)
	scene._travel(1)
	verify(scene.sim == scene.galaxy.current() and scene.board.sim == scene.sim, "Travel binds board to current planet")
	scene._set_tool("stellar")
	verify(scene.tool == "stellar", "Stellar tower tool enabled after research")
	verify(scene._paint(Vector2i(4, 4)), "Tower placed via game UI")
	scene._set_tool("select")
	scene._paint(Vector2i(4, 4))
	scene._refresh_selection()
	verify(scene.logistics_box.visible and scene.inspector_title.text == "星际物流塔", "Tower output configuration shown")
	scene._edit_setting("outputs", 17, 0)
	scene._history_action(false)
	verify(scene.sim.at(Vector2i(4, 4)).outputs[0] == 0, "Tower output configuration undo supported")
	scene._history_action(false)
	verify(scene.galaxy.network.used == 0, "Undo tower building returns global allowance")
	scene._history_action(true)
	verify(scene.galaxy.network.used == 1, "Redo tower building consumes global allowance")
	var tower = scene.sim.at(Vector2i(4, 4))
	for port in scene.sim.logistics_ports(tower):
		var incoming = port.index % 2 == 0
		scene.sim.build_belt(port.pos, (port.facing + 2) % 4 if incoming else port.facing, -1 if incoming else (port.facing + 2) % 4)
		if not incoming: tower.outputs[port.index] = 17
	scene._paint(Vector2i(4, 4))
	scene.camera.position = Vector2(2, 1) * 40
	scene._layout()
	scene._refresh_selection()
	verify(scene.sim.logistics_ports(tower).filter(func(port): return port.mode == "input").size() == 4, "Inspector fixture has all eight mixed ports")
	for size in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = size
		scene._layout()
		scene._refresh()
		await process_frame
		verify(scene.root.get_node("Bottom").get_global_rect().encloses(scene.buttons.stellar.get_global_rect()), "Stellar tool fits toolbar at " + str(size))
		verify(scene.root.get_node("Top").get_global_rect().encloses(scene.planet_selector.get_global_rect()), "Planet selector fits header at " + str(size))
		var right_scroll = scene.logistics_box.get_parent().get_parent()
		right_scroll.scroll_vertical = 1000000
		await process_frame
		verify(right_scroll.get_global_rect().intersects(scene.logistics_fields[-1].field.get_global_rect()), "Last stellar output remains reachable by scrolling at " + str(size))
		right_scroll.scroll_vertical = 0
		await process_frame
		if "--visual" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://qa/galaxy_%dx%d.png" % [size.x, size.y])
	scene._travel(0)
	verify(scene.sim.world.tier == 0 and scene.galaxy.planets.size() == 2, "Return home retains alien layout")
	scene.sim.world.primes = PlanetRules.prime_list(PlanetRules.CAPS[0])
	scene.sim.world.stage = scene.sim.world.primes.size() - 2
	scene.sim.world.expansions = 28
	scene.sim.world.last_prime_expansion = 28
	scene._refresh()
	verify(scene.prime_button.disabled and scene.prime_button.text == "质数研究完成" and not scene.prime_label.text.contains("质数 0"), "Capped research UI has an explicit finished state")
	scene.queue_free()
	await process_frame

func run():
	test_caps_and_generation()
	test_network_rules()
	test_ports_and_fairness()
	var g = test_real_transport()
	test_saves(g)
	await test_interface()
	print("Galaxy: %d checks, %d failures" % [checks, failures.size()])
	for message in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)
