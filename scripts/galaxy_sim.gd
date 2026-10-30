class_name GalaxySim
extends RefCounted

var planets: Array = []
var network = StarNetwork.new()
var active_planet: int = 0
var growth_origin: int = 0
var pairs_awarded: int = 0
var turn: int = 0
var paused: bool = false

func _init(seed_value: int = 51465254):
	reset(seed_value)

func reset(seed_value: int = 51465254):
	network = StarNetwork.new()
	planets = [WorldSim.new(seed_value)]
	planets[0].network = network
	active_planet = 0
	growth_origin = 0
	pairs_awarded = 0
	turn = 0
	paused = false

func current() -> WorldSim:
	return planets[active_planet]

func growth_total() -> int:
	var result = 0
	for planet in planets: result += planet.world.growth_events
	return result

func sync_progress():
	if not network.unlocked and "interstellar" in planets[0].world.technologies:
		network.unlocked = true
		network.capacity = 2
		growth_origin = growth_total()
	if network.unlocked:
		var pairs = int((growth_total() - growth_origin) / PlanetRules.PAIR_INTERVAL)
		if pairs > pairs_awarded:
			network.capacity += (pairs - pairs_awarded) * 2
			pairs_awarded = pairs

func travel_reason(tier: int) -> String:
	if tier not in [0, 1, 2]: return "未知星球"
	if tier < planets.size(): return ""
	if not network.unlocked: return "起源星需扩张 8 圈、解锁质数 7 与共享物流，再研究星际物流"
	if tier == 2 and (planets.size() < 2 or 29 not in planets[1].world.primes): return "远岫星研究质数 29 后开放"
	return ""

func travel(tier: int) -> bool:
	sync_progress()
	if not travel_reason(tier).is_empty(): return false
	while planets.size() <= tier:
		var index = planets.size()
		var seed_value = clampi(planets[0].world.seed_value + index * 104729, WorldProgress.MIN_SEED, WorldProgress.MAX_SEED)
		var planet = WorldSim.new(seed_value, 0, index)
		planet.network = network
		planets.append(planet)
	active_planet = tier
	return true

func tick(dt: float = FactorySim.STEP):
	sync_progress()
	# Advance on committed withdrawals, preventing periodic supply from aliasing a tick rotation.
	var first = (network.last_planet + 1) % planets.size() if network.last_planet >= 0 else turn % planets.size()
	for offset in range(planets.size()): planets[(first + offset) % planets.size()].tick(dt)
	turn += 1

func total_mass() -> int:
	var result = 0
	for planet in planets: result += planet.total_mass()
	for value in network.stock: result += int(network.stock[value]) * FactorySim.prime_count(int(value))
	return result

func emitted_mass() -> int:
	var result = 0
	for planet in planets: result += planet.emitted
	return result

func serialize() -> Dictionary:
	sync_progress()
	return {"version": 4, "prime_cap": PlanetRules.PRIME_CAP, "active_planet": active_planet,
		"planets": planets.map(func(planet): return planet.serialize()), "stock": network.stock.duplicate(),
		"capacity": network.capacity, "growth_origin": growth_origin, "pairs_awarded": pairs_awarded,
		"turn": turn, "last_planet": network.last_planet, "paused": paused}

func restore(data: Dictionary) -> bool:
	if data.get("version") == 3:
		var home = WorldSim.new()
		if not home.restore(data) or home.world.tier != 0: return false
		var migrated = GalaxySim.new(home.world.seed_value)
		migrated.planets = [home]
		home.network = migrated.network
		migrated.paused = home.session_paused
		migrated.sync_progress()
		_adopt(migrated)
		return true
	if data.get("version") != 4 or data.get("prime_cap") != PlanetRules.PRIME_CAP: return false
	if not data.get("planets") is Array or data.planets.size() < 1 or data.planets.size() > 3: return false
	for field in ["active_planet", "capacity", "growth_origin", "pairs_awarded", "turn"]:
		if not FactorySim.valid_integer(data.get(field)) or int(data[field]) < 0: return false
	if int(data.active_planet) >= data.planets.size(): return false
	if not FactorySim.valid_integer(data.get("last_planet", -1)) or int(data.get("last_planet", -1)) < -1 or int(data.get("last_planet", -1)) >= data.planets.size(): return false
	if not data.get("stock") is Dictionary or not WorldProgress.valid_map(data.stock): return false
	for value in data.stock:
		if FactorySim.factors(int(value)).any(func(p): return p > PlanetRules.PRIME_CAP): return false
	var candidate = GalaxySim.new()
	candidate.planets.clear()
	candidate.network.capacity = int(data.capacity)
	# Restore tower entities against provisional quota, then verify progression below.
	candidate.network.unlocked = int(data.capacity) > 0
	for i in range(data.planets.size()):
		if not data.planets[i] is Dictionary: return false
		var planet = WorldSim.new(42, 0, i)
		planet.network = candidate.network
		if not planet.restore(data.planets[i]) or planet.world.tier != i: return false
		candidate.planets.append(planet)
		for e in planet.entities.values():
			if e.kind == "stellar": candidate.network.used += 1
	if candidate.network.used > candidate.network.capacity: return false
	var unlocked = "interstellar" in candidate.planets[0].world.technologies
	if unlocked != candidate.network.unlocked: return false
	if candidate.planets.size() > 1 and not unlocked: return false
	if candidate.planets.size() > 2 and 29 not in candidate.planets[1].world.primes: return false
	candidate.growth_origin = int(data.growth_origin)
	candidate.pairs_awarded = int(data.pairs_awarded)
	if unlocked:
		if candidate.growth_origin < 14 or candidate.growth_origin > candidate.growth_total(): return false
		var expected = int((candidate.growth_total() - candidate.growth_origin) / PlanetRules.PAIR_INTERVAL)
		if candidate.pairs_awarded != expected or candidate.network.capacity != 2 + expected * 2: return false
	elif candidate.growth_origin != 0 or candidate.pairs_awarded != 0 or not data.stock.is_empty(): return false
	candidate.network.stock = WorldProgress.integer_map(data.stock)
	candidate.network.last_planet = int(data.get("last_planet", -1))
	candidate.active_planet = int(data.active_planet)
	candidate.turn = int(data.turn)
	candidate.paused = bool(data.get("paused", false))
	_adopt(candidate)
	return true

func _adopt(candidate: GalaxySim):
	planets = candidate.planets
	network = candidate.network
	active_planet = candidate.active_planet
	growth_origin = candidate.growth_origin
	pairs_awarded = candidate.pairs_awarded
	turn = candidate.turn
	paused = candidate.paused
