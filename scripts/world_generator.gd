class_name WorldGenerator
extends RefCounted

const CHUNK = 8
const CURRENT_VERSION = 2
const RANDOM_DENSITY = 0.05
const LEGACY_DENSITY = 0.7
var seed_value: int
var sparse_from_ring: int
var _fallbacks: Dictionary = {}
var tier: int = 0
var prime_limit: int = 13

func _init(world_seed: int = 51465254, first_sparse_ring: int = 0, planet_tier: int = 0, limit: int = 13):
	seed_value = world_seed
	sparse_from_ring = first_sparse_ring
	tier = planet_tier
	prime_limit = mini(limit, PlanetRules.PRIME_CAP)

static func chunk_of(p: Vector2i) -> Vector2i:
	return Vector2i(floori(float(p.x) / CHUNK), floori(float(p.y) / CHUNK))

static func ring_of(p: Vector2i) -> int:
	var radius = maxi(absi(p.x), absi(p.y))
	return maxi(0, floori(float(radius - 16) / 8) + 1)

static func chunk_ring(chunk: Vector2i) -> int:
	return maxi(0, maxi(maxi(chunk.x + 1, -chunk.x), maxi(chunk.y + 1, -chunk.y)) - 2)

static func ring_chunks(ring: int) -> Array:
	var half = 2 + ring
	var chunks: Array = []
	for x in range(-half, half):
		chunks.append(Vector2i(x, -half))
		chunks.append(Vector2i(x, half - 1))
	for y in range(-half + 1, half - 1):
		chunks.append(Vector2i(-half, y))
		chunks.append(Vector2i(half - 1, y))
	return chunks

func random_density(chunk: Vector2i) -> float:
	if tier > 0: return PlanetRules.DENSITIES[tier]
	return LEGACY_DENSITY if chunk_ring(chunk) < sparse_from_ring else RANDOM_DENSITY

func deposits(chunk: Vector2i) -> Array:
	if tier > 0: return _alien_deposits(chunk)
	var base = _base_deposits(chunk)
	var ring = chunk_ring(chunk)
	if ring == 0 or ring < sparse_from_ring: return base
	var fallback = _ring_fallback(ring)
	return [fallback] if not fallback.is_empty() and chunk_of(fallback.pos) == chunk else base

func _ring_fallback(ring: int) -> Dictionary:
	if _fallbacks.has(ring): return _fallbacks[ring]
	var empty: Array = []
	var replaceable: Array = []
	for chunk in ring_chunks(ring):
		var base = _base_deposits(chunk)
		for deposit in base:
			if deposit.value in [2, 3]:
				_fallbacks[ring] = {}
				return {}
		if base.is_empty(): empty.append(chunk)
		elif not _stage_deposit(chunk).is_empty(): continue
		replaceable.append(chunk)
	# Choose from the whole ring, never from whichever chunk happened to load first.
	var candidates = empty if not empty.is_empty() else replaceable
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value + ring * 83492791 + 20903
	var chosen = candidates[rng.randi_range(0, candidates.size() - 1)]
	var pos = chosen * CHUNK + Vector2i(rng.randi_range(1, 5), rng.randi_range(1, 5))
	var fallback = {"pos": pos, "value": 2 if rng.randi_range(0, 1) == 0 else 3}
	_fallbacks[ring] = fallback
	return fallback

func _stage_deposit(chunk: Vector2i) -> Dictionary:
	var prime = 3
	var index = 0
	var ring = chunk_ring(chunk)
	while WorldProgress.prime_ring(index) <= ring and WorldProgress.next_prime(prime) <= prime_limit:
		prime = WorldProgress.next_prime(prime)
		var guaranteed = Vector2i(18 + (WorldProgress.prime_ring(index) - 1) * 8, 2)
		if chunk_of(guaranteed) == chunk: return {"pos": guaranteed, "value": prime}
		index += 1
	return {}

func _base_deposits(chunk: Vector2i) -> Array:
	var result: Array = []
	# Fixed starter deposits are part of the generator, not overwritten terrain.
	for starter in [{"pos": Vector2i(-8, -4), "value": 2}, {"pos": Vector2i(-8, 4), "value": 3}]:
		if chunk_of(starter.pos) == chunk: result.append(starter)
	if chunk in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]: return result
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value + chunk.x * 73856093 + chunk.y * 19349663
	var p = chunk * CHUNK + Vector2i(rng.randi_range(1, 5), rng.randi_range(1, 5))
	var available: Array = [2, 3]
	var prime = 3
	var index = 0
	while WorldProgress.prime_ring(index) <= ring_of(p) and WorldProgress.next_prime(prime) <= prime_limit:
		prime = WorldProgress.next_prime(prime)
		available.append(prime)
		index += 1
	if rng.randf() < random_density(chunk) and result.is_empty():
		result.append({"pos": p, "value": available[rng.randi_range(0, available.size() - 1)]})
	# Every stage has a reserved, seed-independent location in its first eligible ring.
	# Its value exists before unlock, so exploring early cannot change the world.
	var stage = _stage_deposit(chunk)
	return [stage] if not stage.is_empty() else result

func _alien_deposits(chunk: Vector2i) -> Array:
	var first = PlanetRules.STARTS[tier]
	var starter = Vector2i(-8, -4)
	if chunk_of(starter) == chunk: return [{"pos": starter, "value": first}]
	# The landing square contains one new prime; all other deposits are sparse.
	if chunk in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]: return []
	var ring = chunk_ring(chunk)
	var index = 0
	var latest = first
	while WorldProgress.prime_ring(index) <= ring and WorldProgress.next_prime(latest) <= prime_limit:
		latest = WorldProgress.next_prime(latest)
		var guarantee = Vector2i(18 + (WorldProgress.prime_ring(index) - 1) * 8, 2)
		if chunk_of(guarantee) == chunk: return [{"pos": guarantee, "value": latest}]
		index += 1
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value + chunk.x * 73856093 + chunk.y * 19349663
	var p = chunk * CHUNK + Vector2i(rng.randi_range(1, 5), rng.randi_range(1, 5))
	if rng.randf() >= random_density(chunk): return []
	var level = 2 if ring >= 5 else 1 if ring >= 2 else 0
	var available = PlanetRules.resource_values(tier, latest, level)
	return [{"pos": p, "value": available[rng.randi_range(0, available.size() - 1)]}]
