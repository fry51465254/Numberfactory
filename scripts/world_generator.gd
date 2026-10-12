class_name WorldGenerator
extends RefCounted

const CHUNK = 8
var seed_value: int

func _init(world_seed: int = 51465254):
	seed_value = world_seed

static func chunk_of(p: Vector2i) -> Vector2i:
	return Vector2i(floori(float(p.x) / CHUNK), floori(float(p.y) / CHUNK))

static func ring_of(p: Vector2i) -> int:
	var radius = maxi(absi(p.x), absi(p.y))
	return maxi(0, floori(float(radius - 16) / 8) + 1)

func deposits(chunk: Vector2i) -> Array:
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
	while WorldProgress.prime_ring(index) <= ring_of(p):
		prime = WorldProgress.next_prime(prime)
		available.append(prime)
		index += 1
	if rng.randf() < 0.7 and result.is_empty():
		result.append({"pos": p, "value": available[rng.randi_range(0, available.size() - 1)]})
	# Every stage has a reserved, seed-independent location in its first eligible ring.
	# Its value exists before unlock, so exploring early cannot change the world.
	for i in range(available.size() - 2):
		var guaranteed = Vector2i(16 + (WorldProgress.prime_ring(i) - 1) * 8 + 2, 2)
		if chunk_of(guaranteed) == chunk:
			return [{"pos": guaranteed, "value": available[i + 2]}]
	return result
