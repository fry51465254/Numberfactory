extends SceneTree

var checks = 0
var failures: Array = []

func verify(condition: bool, message: String):
	checks += 1
	if not condition: failures.append(message)

func _initialize():
	_test_unlock_and_quota()
	_test_inventory()
	_test_throughput()
	_test_save()
	_test_waiting_reasons()
	_test_simultaneous_io()
	_test_scarce_stock_fairness()
	_test_underground_ports()
	print("Logistics: %d checks, %d failures" % [checks, failures.size()])
	for message in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)

func fixture() -> WorldSim:
	var sim = WorldSim.new(42)
	sim.world.primes = [2, 3, 5, 7]
	sim.world.stage = 2
	sim.world.expansions = 8
	sim.world.last_prime_expansion = 8
	sim.world.technologies = ["ratio", "filter", "logistics"]
	sim.world.logistics_capacity = 2
	return sim

func run_steps(sim: WorldSim, steps: int):
	for i in range(steps): sim.tick()

func station(sim: WorldSim, p: Vector2i):
	verify(sim.place(p, "logistics", 0), "Place station %s" % p)

func attach(sim: WorldSim, p: Vector2i, slot: int, incoming: bool) -> Vector2i:
	var location = p + WorldSim.LOG_PORTS[slot]
	verify(sim.place(location, "belt", (int(slot / 2) + (2 if incoming else 0)) % 4), "Attach belt slot %d" % slot)
	return location

func inject(sim: WorldSim, p: Vector2i, value: int):
	sim.at(p).item = value
	sim.emitted += FactorySim.prime_count(value)

func _test_unlock_and_quota():
	var sim = WorldSim.new(42)
	verify(not sim.place(Vector2i(-4, 0), "logistics", 0), "Cannot build before technology")
	sim.world.technologies = ["logistics"]
	sim.world.logistics_capacity = 1
	station(sim, Vector2i(-4, 0))
	verify(sim.at(Vector2i(-3, 1)).kind == "logistics", "Station occupies all four cells")
	verify(not sim.place(Vector2i(4, 0), "logistics", 0), "Quota blocks excess station")
	verify(not sim.place(Vector2i(-3, 1), "belt", 0), "Station footprint rejects overlap")
	sim.world.logistics_stock = {"6": 10}
	verify(sim.remove(Vector2i(-3, 1)), "Remove from footprint corner")
	verify(sim.world.logistics_capacity == 1 and sim.logistics_used() == 0, "Removal returns allowance, not a reward")
	verify(sim.world.logistics_stock == {"6": 10}, "Removing station retains global inventory")
	station(sim, Vector2i(4, 0))
	verify(not sim.place(Vector2i(-4, 0), "logistics", 0), "Rebuilding cannot duplicate quota")

func _test_inventory():
	var sim = fixture()
	station(sim, Vector2i(-4, 0))
	station(sim, Vector2i(4, 0))
	var input = attach(sim, Vector2i(-4, 0), 4, true)
	var output = attach(sim, Vector2i(4, 0), 0, false)
	sim.at(Vector2i(4, 0)).outputs[0] = 6
	inject(sim, input, 6)
	run_steps(sim, 10)
	verify(sim.world.count(sim.world.logistics_stock, 6) == 1, "Deposit into shared logistics stock")
	verify(sim.at(output).item == 0, "New deposit cannot teleport and withdraw in same tick")
	verify(sim.world.research_stock.is_empty(), "Logistics deposit not research payment")
	run_steps(sim, 1)
	verify(sim.at(output).item == 6 and sim.world.count(sim.world.logistics_stock, 6) == 0, "Remote station withdraws selected product")
	verify(sim.total_mass() == sim.emitted, "Remote transport conserves mass")
	inject(sim, input, 3)
	run_steps(sim, 20)
	verify(sim.world.count(sim.world.logistics_stock, 3) == 1, "Accepts other input numbers")
	verify(sim.at(output).item == 6, "Selected product and blockage retained")
	verify(sim.total_mass() == sim.emitted, "Blocked transport conserves mass")
	var parallel = attach(sim, Vector2i(4, 0), 2, false)
	sim.at(parallel).dir = 0
	verify(sim.logistics_ports(sim.at(Vector2i(4, 0)))[2].mode == "none", "Parallel belt not an output")
	var competing = fixture()
	station(competing, Vector2i(-4, 0))
	station(competing, Vector2i(4, 0))
	competing.world.logistics_stock = {"12": 1}
	competing.emitted = 3
	for p in [Vector2i(-4, 0), Vector2i(4, 0)]:
		attach(competing, p, 0, false)
		competing.at(p).outputs[0] = 12
	run_steps(competing, 11)
	var count_items = int(competing.at(Vector2i(-2, 0)).item == 12) + int(competing.at(Vector2i(6, 0)).item == 12)
	verify(count_items == 1 and competing.world.count(competing.world.logistics_stock, 12) == 0, "Concurrent withdrawals reserve last item exactly once")
	verify(competing.total_mass() == competing.emitted, "Concurrent withdrawal conservation")

func _test_throughput():
	var sim = fixture()
	station(sim, Vector2i(-4, 0))
	var ports = []
	for i in range(8): ports.append(attach(sim, Vector2i(-4, 0), i, true))
	var delivered = 0
	var maximum = 0
	for step in range(300):
		for p in ports:
			if sim.at(p).item == 0: inject(sim, p, 2)
		sim.tick()
		var now = sim.world.count(sim.world.logistics_stock, 2)
		maximum = maxi(maximum, now - delivered)
		delivered = now
	verify(delivered >= 55 and delivered <= 60, "Station total rate at most six items/sec, observed %d/10sec" % delivered)
	verify(maximum == 1, "No single-step station burst")
	verify(sim.total_mass() == sim.emitted, "Full input saturation conservation")
	var one = fixture()
	station(one, Vector2i(-4, 0))
	var p = attach(one, Vector2i(-4, 0), 4, true)
	for step in range(300):
		if one.at(p).item == 0: inject(one, p, 3)
		one.tick()
	verify(one.world.count(one.world.logistics_stock, 3) == 30, "Single port limited to three items/sec")

func _test_save():
	var sim = fixture()
	sim.session_paused = true
	station(sim, Vector2i(-4, 0))
	sim.at(Vector2i(-4, 0)).outputs = [2, 3, 6, 12, 18, 0, 0, 0]
	sim.world.logistics_stock = {"6": 5, "18": 2}
	run_steps(sim, 4)
	var copy = WorldSim.new()
	verify(copy.restore(JSON.parse_string(JSON.stringify(sim.serialize()))), "Restore stations and bank")
	verify(copy.world.logistics_stock == sim.world.logistics_stock, "Shared inventory restored")
	verify(copy.session_paused, "Paused state survives save and load")
	verify(copy.at(Vector2i(-4, 0)).outputs == sim.at(Vector2i(-4, 0)).outputs, "Per-port product selections restored")
	verify(is_equal_approx(copy.at(Vector2i(-4, 0)).budget, sim.at(Vector2i(-4, 0)).budget), "Throughput budget restored")
	verify(copy.logistics_used() == 1 and copy.world.logistics_capacity == 2, "Used and total quotas restored")
	var bad = sim.serialize()
	bad.world.logistics_capacity = 0
	verify(not copy.restore(bad) and copy.logistics_used() == 1, "Restore cannot exceed quota and failure retains old factory")

func _test_waiting_reasons():
	var sim = fixture()
	var p = Vector2i(-4, 0)
	station(sim, p)
	var output = attach(sim, p, 0, false)
	var e = sim.at(p)
	var port = sim.logistics_ports(e)[0]
	verify(sim.logistics_port_state(e, port) == "未设置", "Unset output reason")
	e.outputs[0] = 6
	verify(sim.logistics_port_state(e, port) == "缺货", "Empty bank reason")
	sim.world.logistics_stock = {"6": 2}
	inject(sim, output, 6)
	verify(sim.logistics_port_state(e, port) == "下游堵塞", "Occupied dead-end output reason")
	sim.at(output).item = 0
	verify(sim.logistics_port_state(e, port) == "整站限速", "Station throughput wait reason")
	e.budget = 1.0
	verify(sim.logistics_port_state(e, port) == "端口限速", "Port cooldown wait reason")
	e.port_age[0] = FactorySim.TRAVEL
	verify(sim.logistics_port_state(e, port) == "就绪", "Ready output reason")

func _test_simultaneous_io():
	var sim = fixture()
	var p = Vector2i(-4, 0)
	station(sim, p)
	var input = attach(sim, p, 4, true)
	var output = attach(sim, p, 0, false)
	sim.at(p).outputs[0] = 6
	sim.world.logistics_stock = {"6": 100}
	sim.emitted = 200
	var withdrawn = 0
	for step in range(600):
		if sim.at(input).item == 0: inject(sim, input, 2)
		if sim.at(output).item != 0:
			verify(sim.at(output).item == 6, "Configured output never substitutes input number")
			withdrawn += 1
			sim.discarded += FactorySim.prime_count(sim.at(output).item)
			sim.at(output).item = 0
		sim.tick()
	var received = sim.world.count(sim.world.logistics_stock, 2)
	verify(received > 40 and withdrawn > 40, "Simultaneous input/output cannot starve either direction")
	verify(received + withdrawn <= 120, "Mixed station traffic obeys shared six/sec cap")
	verify(absi(received - withdrawn) <= 2, "Equally ready input and output remain balanced")
	verify(sim.total_mass() == sim.emitted, "Mixed two-number traffic conserves all materials")
	var direct = fixture()
	station(direct, p)
	verify(direct.place(p + Vector2i(-1, 0), "multiplier", 0), "Machine next to station")
	direct.at(p + Vector2i(-1, 0)).output = 6
	run_steps(direct, 40)
	verify(direct.world.logistics_stock.is_empty() and direct.at(p + Vector2i(-1, 0)).output == 6, "Machine cannot deposit directly without a belt")

func _test_scarce_stock_fairness():
	var sim = fixture()
	var outputs: Array = []
	for p in [Vector2i(-4, 0), Vector2i(4, 0)]:
		station(sim, p)
		outputs.append(attach(sim, p, 0, false))
		sim.at(p).outputs[0] = 6
	var counts = [0, 0]
	for step in range(1200):
		if step % 10 == 0:
			sim.world.logistics_stock["6"] = sim.world.count(sim.world.logistics_stock, 6) + 1
			sim.emitted += 2
		for i in range(2):
			if sim.at(outputs[i]).item == 6:
				counts[i] += 1
				sim.discarded += 2
				sim.at(outputs[i]).item = 0
		sim.tick()
	verify(counts[0] > 0 and counts[1] > 0 and absi(counts[0] - counts[1]) <= 1, "Periodic scarce stock shared fairly: %s" % [counts])
	verify(sim.total_mass() == sim.emitted, "Scarce-stock round-robin conserves materials")
	var copy = WorldSim.new()
	verify(copy.restore(JSON.parse_string(JSON.stringify(sim.serialize()))) and copy.logistics_last_served == sim.logistics_last_served, "Successful-transfer cursor survives save/reload")

func _test_underground_ports():
	var sim = fixture()
	var p = Vector2i(-4, 0)
	station(sim, p)
	var east = p + Vector2i(2, 0)
	verify(sim.place(east, "belt", 1) and sim.build_belt(east, 0, 2, true) == 1, "Output crossing keeps perpendicular surface belt")
	sim.at(p).outputs[0] = 6
	sim.world.logistics_stock = {"6": 1}
	sim.emitted = 2
	run_steps(sim, 11)
	verify(sim.at(east).item == 0 and sim.at(east, 1).item == 6, "Logistics output selects matching underground channel")
	var west = p + Vector2i.LEFT
	verify(sim.place(west, "belt", 1) and sim.build_belt(west, 0, 2, true) == 1, "Input crossing creates independent underground channel")
	sim.at(west, 1).item = 3
	sim.emitted += 1
	run_steps(sim, 11)
	verify(sim.world.count(sim.world.logistics_stock, 3) == 1 and sim.at(west).item == 0, "Underground belt feeds input without touching ground channel")
	verify(sim.total_mass() == sim.emitted, "Logistics crossing input/output conserve materials")
