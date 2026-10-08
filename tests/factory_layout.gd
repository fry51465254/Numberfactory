extends RefCounted

static func route(sim: FactorySim, points: Array):
	for i in range(points.size() - 1):
		var p: Vector2i = points[i]
		var end: Vector2i = points[i + 1]
		var direction = FactorySim.DIRS.find(Vector2i(signi(end.x - p.x), signi(end.y - p.y)))
		while p != end:
			if sim.at(p).is_empty(): sim.place(p, "belt", direction)
			else: sim.at(p).dir = direction
			p += FactorySim.DIRS[direction]
	if sim.at(points[-1]).is_empty(): sim.place(points[-1], "belt", 0)

static func shared(sim: FactorySim):
	for e in sim.entities.values().duplicate():
		if e.kind == "belt": sim.remove(e.pos)
	# One 2 outlet branches into the two consuming machines.
	route(sim, [Vector2i(5, 8), Vector2i(9, 8)])
	sim.place(Vector2i(10, 8), "splitter", 0)
	route(sim, [Vector2i(10, 9), Vector2i(10, 10), Vector2i(8, 10), Vector2i(8, 14)])
	sim.at(Vector2i(8, 14)).dir = 1
	route(sim, [Vector2i(11, 8), Vector2i(11, 14), Vector2i(10, 14)])
	sim.at(Vector2i(11, 8)).entry = 2
	sim.at(Vector2i(10, 14)).dir = 1
	route(sim, [Vector2i(5, 15), Vector2i(7, 15)])
	sim.place(Vector2i(8, 15), "multiplier", 0)
	sim.place(Vector2i(9, 15), "splitter", 0)
	sim.place(Vector2i(10, 15), "multiplier", 0)
	route(sim, [Vector2i(11, 15), Vector2i(12, 15), Vector2i(12, 6), Vector2i(13, 6)])
	sim.at(Vector2i(13, 6)).dir = 3
	route(sim, [Vector2i(5, 16), Vector2i(8, 16)])
	sim.place(Vector2i(9, 16), "multiplier", 0)
	route(sim, [Vector2i(10, 16), Vector2i(13, 16), Vector2i(13, 18)])
	sim.at(Vector2i(13, 18)).dir = 1

static func hub(sim: FactorySim):
	sim.remove(Vector2i(10, 15))
	sim.place(Vector2i(10, 15), "multiplier", 0)
	for y in range(8, 15): sim.remove(Vector2i(11, y))
	sim.remove(Vector2i(10, 14))
	for y in range(6, 16): sim.remove(Vector2i(12, y))
	for p in [Vector2i(11, 15), Vector2i(13, 6)]: sim.remove(p)
	route(sim, [Vector2i(26, 6), Vector2i(29, 6), Vector2i(29, 13), Vector2i(10, 13), Vector2i(10, 14)])
	sim.at(Vector2i(10, 14)).dir = 1
	route(sim, [Vector2i(11, 15), Vector2i(18, 15), Vector2i(18, 14), Vector2i(26, 14)])
	sim.at(Vector2i(26, 14)).dir = 1
