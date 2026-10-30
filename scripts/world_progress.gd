class_name WorldProgress
extends RefCounted

const MAX_VALUE = 999999
const MAX_SEED = 2147483647
const MIN_SEED = -2147483648
const INITIAL_HALF = 16
const RING_WIDTH = 8
const INTERVALS = [3, 5, 8, 12]
const LATER_INTERVAL_STEP = 4
const TECHS = ["ratio", "filter", "logistics", "interstellar", "ore1", "ore2"]

var seed_value: int = 51465254
var expansions: int = 0
var stage: int = 0
var last_prime_expansion: int = 0
var primes: Array = [2, 3]
var technologies: Array = []
var research_stock: Dictionary = {}
var lifetime: Dictionary = {}
var logistics_stock: Dictionary = {}
var spent_mass: int = 0
var logistics_capacity: int = 0
var expansion_cost: Dictionary = {}
var prime_cost: Dictionary = {}
var tech_costs: Dictionary = {}
var recipes: Array = []
var tier: int = 0
var growth_events: int:
	get: return expansions + local_stage() + technologies.size() - (3 if tier > 0 else 0)

func _init(world_seed: int = 51465254, planet_tier: int = 0):
	seed_value = clampi(world_seed, MIN_SEED, MAX_SEED)
	tier = clampi(planet_tier, 0, 2)
	primes = PlanetRules.prime_list(PlanetRules.STARTS[tier])
	stage = primes.size() - 2
	if tier > 0: technologies = ["ratio", "filter", "logistics"]
	if tier > 0: logistics_capacity = 2
	_generate_targets()

func half_size() -> int:
	return INITIAL_HALF + expansions * RING_WIDTH

func bounds() -> Rect2i:
	var half = half_size()
	return Rect2i(-half, -half, half * 2, half * 2)

func accessible(p: Vector2i) -> bool:
	return bounds().has_point(p)

static func is_prime(value: int) -> bool:
	if value < 2: return false
	var divisor = 2
	while divisor * divisor <= value:
		if value % divisor == 0: return false
		divisor += 1
	return true

static func next_prime(value: int) -> int:
	var candidate = value + 1
	while not is_prime(candidate): candidate += 1
	return candidate

static func interval(index: int) -> int:
	return INTERVALS[index] if index < INTERVALS.size() else INTERVALS[-1] + (index - INTERVALS.size() + 1) * LATER_INTERVAL_STEP

static func prime_ring(index: int) -> int:
	var total = 0
	for i in range(index + 1): total += interval(i)
	return total

func next_resource() -> int:
	var value = next_prime(primes[-1])
	return value if value <= PlanetRules.CAPS[tier] else 0

func local_stage() -> int:
	return stage - PlanetRules.initial_stage(tier)

func ore_level() -> int:
	return 2 if "ore2" in technologies else 1 if "ore1" in technologies else 0

func techs_for_planet() -> Array:
	return ["ratio", "filter", "logistics", "interstellar"] if tier == 0 else ["ratio", "filter", "logistics", "ore1", "ore2"]

func prime_ready() -> bool:
	return next_resource() > 0 and expansions - last_prime_expansion >= interval(local_stage())

func tech_available(technology: String) -> bool:
	if technology in technologies or technology not in techs_for_planet(): return false
	if technology == "interstellar": return expansions >= 8 and 7 in primes and "logistics" in technologies
	if technology == "ore1": return expansions >= 2
	if technology == "ore2": return expansions >= 5 and "ore1" in technologies
	if technology == "logistics": return 7 in primes and "filter" in technologies
	return technology == "ratio" or "ratio" in technologies

func count(stock: Dictionary, value: int) -> int:
	return int(stock.get(str(value), 0))

func deposit(value: int, quantity: int = 1) -> bool:
	if quantity <= 0 or value not in recipes: return false
	var id = str(value)
	research_stock[id] = count(research_stock, value) + quantity
	lifetime[id] = count(lifetime, value) + quantity
	return true

func can_pay(cost: Dictionary) -> bool:
	for value in cost:
		if count(research_stock, int(value)) < int(cost[value]): return false
	return not cost.is_empty()

func _pay(cost: Dictionary) -> bool:
	if not can_pay(cost): return false
	for value in cost:
		research_stock[value] -= int(cost[value])
		spent_mass += FactorySim.prime_count(int(value)) * int(cost[value])
	return true

func expand() -> bool:
	if not _pay(expansion_cost): return false
	expansions += 1
	if "logistics" in technologies: logistics_capacity += 1
	expansion_cost = _cost("expand", expansions)
	_register(expansion_cost)
	return true

func research_prime() -> bool:
	if not prime_ready() or next_resource() * 2 > MAX_VALUE: return false
	if not _pay(prime_cost): return false
	primes.append(next_resource())
	stage += 1
	last_prime_expansion = expansions
	if "logistics" in technologies: logistics_capacity += 1
	_generate_targets()
	return true

func research_tech(technology: String) -> bool:
	if not tech_available(technology) or not _pay(tech_costs[technology]): return false
	technologies.append(technology)
	if technology == "logistics": logistics_capacity = 2
	elif "logistics" in technologies: logistics_capacity += 1
	return true

func _cost(category: String, ordinal: int) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value + ordinal * 104729 + stage * 7919 + category.hash()
	var cost: Dictionary = {}
	if tier > 0:
		# Early colonies need few units, but every bill includes their new prime.
		var newest = int(primes[-1])
		var quantity = 4 + expansions * (2 + tier) + local_stage() * 3
		var factor = 2 if tier == 1 else 17
		cost[str(newest * factor)] = quantity
		if expansions >= 3 or category != "expand": cost[str(newest * factor * (3 if tier == 1 else 2))] = maxi(3, int(quantity / 2))
		return cost
	if stage == 0 and category == "expand" and ordinal == 0: return {"6": 20}
	var count_products = mini(3, 1 + int(ordinal / 3) + int(stage / 2))
	var compatible = primes.filter(func(prime): return int(prime) * int(primes[-1]) <= MAX_VALUE)
	for i in range(count_products):
		var value = int(primes[-1]) * int(compatible[0 if i == 0 else rng.randi_range(0, compatible.size() - 1)])
		var factors_needed = 2 + mini(3, int((stage + ordinal + i) / 3))
		for f in range(factors_needed - 2):
			var prime = int(primes[rng.randi_range(0, primes.size() - 1)])
			if value * prime <= MAX_VALUE: value *= prime
		var id = str(value)
		cost[id] = int(cost.get(id, 0)) + 12 + ordinal * 2 + stage * 4 + i * 3
	return cost

func _register(cost: Dictionary):
	for value in cost:
		if int(value) not in recipes: recipes.append(int(value))
	recipes.sort()

func _generate_targets():
	expansion_cost = _cost("expand", expansions)
	prime_cost = _cost("prime", stage + 1)
	for technology in techs_for_planet():
		if technology not in technologies or not tech_costs.has(technology):
			tech_costs[technology] = _cost(technology, TECHS.find(technology) + 1)
	_register(expansion_cost)
	_register(prime_cost)
	for cost in tech_costs.values(): _register(cost)

func serialize() -> Dictionary:
	return {"seed": seed_value, "tier": tier, "growth_events": growth_events, "expansions": expansions, "stage": stage,
		"last_prime_expansion": last_prime_expansion, "primes": primes.duplicate(),
		"technologies": technologies.duplicate(), "research_stock": research_stock.duplicate(),
		"lifetime": lifetime.duplicate(), "logistics_stock": logistics_stock.duplicate(),
		"spent_mass": spent_mass, "logistics_capacity": logistics_capacity,
		"expansion_cost": expansion_cost.duplicate(), "prime_cost": prime_cost.duplicate(),
		"tech_costs": tech_costs.duplicate(true), "recipes": recipes.duplicate()}

static func integer_map(data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id in data: result[str(id)] = int(data[id])
	return result

static func valid_map(data: Dictionary, positive: bool = false) -> bool:
	for id in data:
		if not str(id).is_valid_int() or str(int(id)) != str(id) or int(id) < 2 or int(id) > MAX_VALUE: return false
		if typeof(data[id]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(data[id])): return false
		if float(data[id]) != float(int(data[id])) or int(data[id]) < (1 if positive else 0): return false
	return not positive or not data.is_empty()

func restore(data: Dictionary) -> bool:
	for field in ["seed", "expansions", "stage", "last_prime_expansion", "spent_mass", "logistics_capacity"]:
		if not FactorySim.valid_integer(data.get(field)): return false
	if not FactorySim.valid_integer(data.get("tier", 0)) or int(data.get("tier", 0)) not in [0, 1, 2]: return false
	tier = int(data.get("tier", 0))
	for field in ["research_stock", "lifetime", "logistics_stock", "expansion_cost", "prime_cost", "tech_costs"]:
		if not data.get(field) is Dictionary: return false
	for field in ["primes", "technologies", "recipes"]:
		if not data.get(field) is Array: return false
	for field in ["primes", "recipes"]:
		for value in data[field]:
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) != float(int(value)): return false
	var saved_primes = data.primes.map(func(value): return int(value))
	var saved_recipes = data.recipes.map(func(value): return int(value))
	if int(data.get("expansions", -1)) < 0 or int(data.get("stage", -1)) < 0: return false
	if data.primes.size() != int(data.stage) + 2: return false
	var expected = 2
	for prime in data.primes:
		if int(prime) != expected: return false
		if int(prime) > PlanetRules.PRIME_CAP: return false
		expected = next_prime(expected)
	if saved_primes.size() < PlanetRules.prime_list(PlanetRules.STARTS[tier]).size(): return false
	if tier > 0 and saved_primes[-1] > PlanetRules.CAPS[tier]: return false
	for technology in data.technologies:
		if technology not in TECHS: return false
	if data.technologies.size() != data.technologies.reduce(func(found, t):
		if t not in found: found.append(t)
		return found, []).size(): return false
	if "filter" in data.technologies and "ratio" not in data.technologies: return false
	if "logistics" in data.technologies and (7 not in saved_primes or "filter" not in data.technologies): return false
	if "interstellar" in data.technologies and (tier != 0 or int(data.expansions) < 8 or "logistics" not in data.technologies): return false
	if "ore1" in data.technologies and (tier == 0 or int(data.expansions) < 2): return false
	if "ore2" in data.technologies and ("ore1" not in data.technologies or int(data.expansions) < 5): return false
	if tier > 0 and ["ratio", "filter", "logistics"].any(func(t): return t not in data.technologies): return false
	for field in ["research_stock", "lifetime", "logistics_stock", "expansion_cost", "prime_cost"]:
		if not valid_map(data[field], field in ["expansion_cost", "prime_cost"]): return false
	for technology in ["ratio", "filter", "logistics"]:
		if not data.tech_costs.get(technology) is Dictionary or not valid_map(data.tech_costs[technology], true): return false
	for id in data.tech_costs:
		if id not in TECHS or not data.tech_costs[id] is Dictionary or not valid_map(data.tech_costs[id], true): return false
	for value in data.recipes:
		if int(value) < 4 or int(value) > MAX_VALUE: return false
		for prime in FactorySim.factors(int(value)):
			if prime not in saved_primes: return false
	for cost in [data.expansion_cost, data.prime_cost] + data.tech_costs.values():
		for value in cost:
			if int(value) not in saved_recipes: return false
	for field in ["research_stock", "lifetime"]:
		for value in data[field]:
			if int(value) not in saved_recipes: return false
	for value in data.research_stock:
		if int(data.research_stock[value]) > int(data.lifetime.get(value, 0)): return false
	for field in ["seed", "expansions", "stage", "last_prime_expansion", "spent_mass", "logistics_capacity"]:
		if not data.has(field): return false
	seed_value = int(data.seed)
	if seed_value < MIN_SEED or seed_value > MAX_SEED: return false
	expansions = int(data.expansions)
	stage = int(data.stage)
	last_prime_expansion = int(data.last_prime_expansion)
	spent_mass = int(data.spent_mass)
	logistics_capacity = int(data.logistics_capacity)
	if last_prime_expansion < 0 or last_prime_expansion > expansions or spent_mass < 0 or logistics_capacity < 0: return false
	if (local_stage() == 0 and last_prime_expansion != 0) or (local_stage() > 0 and last_prime_expansion < prime_ring(local_stage() - 1)): return false
	if logistics_capacity > expansions + stage + data.technologies.size() + 2: return false
	primes = saved_primes
	technologies = data.technologies.duplicate()
	recipes = saved_recipes
	research_stock = integer_map(data.research_stock)
	lifetime = integer_map(data.lifetime)
	logistics_stock = integer_map(data.logistics_stock)
	expansion_cost = integer_map(data.expansion_cost)
	prime_cost = integer_map(data.prime_cost)
	tech_costs.clear()
	for technology in data.tech_costs:
		if technology not in TECHS or not data.tech_costs[technology] is Dictionary: return false
		tech_costs[technology] = integer_map(data.tech_costs[technology])
	# Add new research without rerolling legacy bills or the existing catalogue.
	for technology in techs_for_planet():
		if not tech_costs.has(technology):
			tech_costs[technology] = _cost(technology, TECHS.find(technology) + 1)
			_register(tech_costs[technology])
	if not FactorySim.valid_integer(data.get("growth_events", growth_events)): return false
	if int(data.get("growth_events", growth_events)) != growth_events or growth_events < 0: return false
	return true
