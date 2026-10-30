class_name PlanetRules
extends RefCounted

const PRIME_CAP = 43
const NAMES = ["起源", "远岫", "深空"]
const DIFFICULTIES = ["初始", "中等", "困难"]
const CAPS = [13, 29, PRIME_CAP]
const STARTS = [3, 17, 31]
const DENSITIES = [0.05, 0.02, 0.008]
const PAIR_INTERVAL = 6

static func prime_list(limit: int) -> Array:
	var result: Array = []
	for value in range(2, mini(limit, PRIME_CAP) + 1):
		if WorldProgress.is_prime(value): result.append(value)
	return result

static func initial_stage(tier: int) -> int:
	return prime_list(STARTS[tier]).size() - 2

static func local_primes(tier: int, limit: int) -> Array:
	return prime_list(mini(limit, CAPS[tier])).filter(func(p): return tier == 0 or p >= STARTS[tier])

static func resource_values(tier: int, limit: int, level: int = 2) -> Array:
	var result = local_primes(tier, limit)
	if tier > 0:
		for p in result.duplicate():
			if level >= 1: result.append(p * (2 if tier == 1 else 17))
			if level >= 2: result.append(p * (6 if tier == 1 else 17 * 2))
	return result
