class_name FactorySim
extends RefCounted

const WIDTH = 32
const HEIGHT = 24
const MAX_VALUE = 999999
const STEP = 1.0 / 30.0
const TRAVEL = 1.0 / 3.0
const DIRS = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const TARGETS = {"research": 12, "exploration": 18, "hub": 30}
const GOALS = {"research": 60, "exploration": 30, "hub": 60}

var entities: Dictionary = {}
var occupancy: Dictionary = {}
var delivered = {"research": 0, "exploration": 0, "hub": 0}
var recent = {"research": [], "exploration": [], "hub": []}
var elapsed = 0.0
var turn = 0
var emitted = 0
var discarded = 0
var _vacate_cache: Dictionary = {}

func _init(fresh: bool = true):
	if fresh:
		reset()

static func key(p: Vector2i) -> String:
	return "%d,%d" % [p.x, p.y]

func reset():
	entities.clear()
	occupancy.clear()
	delivered = {"research": 0, "exploration": 0, "hub": 0}
	recent = {"research": [], "exploration": [], "hub": []}
	elapsed = 0.0
	turn = 0
	emitted = 0
	discarded = 0
	_add_fixed("source", Vector2i(3, 8), 2)
	_add_fixed("source", Vector2i(3, 15), 3)
	_add_fixed("source", Vector2i(24, 6), 5)
	_add_fixed("research", Vector2i(13, 4))
	_add_fixed("exploration", Vector2i(13, 19))
	_add_fixed("hub", Vector2i(26, 15))
	for y in [8, 9, 15, 16]:
		for x in range(5, 8):
			place(Vector2i(x, y), "belt", 0)

func _base(kind: String, p: Vector2i, direction: int) -> Dictionary:
	return {"kind": kind, "pos": p, "dir": direction, "item": 0,
		"age": 0.0, "inputs": [0, 0], "last_inputs": [0, 0], "output": 0,
		"progress": 0.0, "mode": 0, "ratio": 1, "cursor": 0,
		"filters": [0, 0, 0, 0], "layer": 0, "entry": -1, "value": 0, "charges": [0.0, 0.0],
		"outputs": [0, 0, 0, 0, 0, 0, 0, 0], "port_age": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
		"budget": 0.0, "log_recent": []}

func _add_fixed(kind: String, p: Vector2i, value: int = 0):
	var e = _base(kind, p, 0)
	e.value = value
	entities[key(p)] = e
	for y in range(2):
		for x in range(2):
			occupancy[key(p + Vector2i(x, y))] = key(p)

func unlocked() -> bool:
	return delivered.exploration >= 30

func complete() -> bool:
	return delivered.research >= 60 and unlocked() and delivered.hub >= 60

func accessible(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < WIDTH and p.y < HEIGHT and (p.x < 20 or unlocked())

func source_ports(e: Dictionary) -> int:
	return 1 if e.value == 5 else 2

func source_rate(e: Dictionary) -> float:
	return 3.0 if e.value == 2 else 2.0

func source_enabled(_e: Dictionary) -> bool:
	return true

func accepts_target(e: Dictionary, value: int) -> bool:
	return value == TARGETS[e.kind]

func receive_target(e: Dictionary, value: int):
	delivered[e.kind] += 1
	recent[e.kind].append(elapsed)

func splitter_unlocked(mode: int) -> bool:
	return mode == 0 or delivered.research >= (20 if mode == 1 else 60)

func simulation_entities() -> Dictionary:
	return entities

func restore_bounds(p: Vector2i, size: int) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x + size <= WIDTH and p.y + size <= HEIGHT

func valid_source(value: int) -> bool:
	return value in [2, 3, 5]

func propose_extra(_snapshot: Dictionary, _reserved: Dictionary, _moves: Array):
	pass

func propose_after(_snapshot: Dictionary, _reserved: Dictionary, _moves: Array):
	pass

func extra_can_receive(_e: Dictionary, _from: Vector2i) -> bool:
	return false

func extra_departure(_move: Dictionary) -> bool:
	return false

func extra_arrival(_move: Dictionary) -> bool:
	return false

func at(p: Vector2i, layer: int = 0) -> Dictionary:
	if layer == 1:
		return entities.get(key(p) + ":under", {})
	return entities.get(occupancy.get(key(p), ""), {})

func can_cross(p: Vector2i, direction: int) -> bool:
	var ground = at(p)
	if not accessible(p) or ground.is_empty() or ground.kind != "belt": return false
	if ground.dir % 2 == posmod(direction, 2): return false
	if ground.entry >= 0 and ground.entry != (ground.dir + 2) % 4: return false
	var under = at(p, 1)
	return under.is_empty() or under.dir == posmod(direction, 4)

func build_belt(p: Vector2i, direction: int, entry: int = -1, crossing: bool = false) -> int:
	direction = posmod(direction, 4)
	if crossing and can_cross(p, direction):
		if at(p, 1).is_empty():
			var under = _base("belt", p, direction)
			under.layer = 1
			under.entry = (direction + 2) % 4
			entities[key(p) + ":under"] = under
		return 1
	if crossing and not at(p).is_empty() and at(p).kind == "belt" and at(p).dir % 2 != direction % 2:
		return -1
	if at(p).is_empty():
		if not place(p, "belt", direction): return -1
	elif not redirect_belt(p, direction):
		return -1
	if entry >= 0: at(p).entry = entry
	return 0

func remove_underground(p: Vector2i) -> bool:
	var under = at(p, 1)
	if under.is_empty(): return false
	discarded += mass_of(under)
	entities.erase(key(p) + ":under")
	return true

func can_place(p: Vector2i) -> bool:
	return accessible(p) and not occupancy.has(key(p))

func place(p: Vector2i, kind: String, direction: int) -> bool:
	if not can_place(p) or kind not in ["belt", "multiplier", "splitter"]:
		return false
	entities[key(p)] = _base(kind, p, posmod(direction, 4))
	occupancy[key(p)] = key(p)
	return true

func remove(p: Vector2i) -> bool:
	var e = at(p)
	if e.is_empty() or e.kind not in ["belt", "multiplier", "splitter"]:
		return false
	remove_underground(p)
	discarded += mass_of(e)
	occupancy.erase(key(e.pos))
	entities.erase(key(e.pos))
	return true

func redirect_belt(p: Vector2i, direction: int) -> bool:
	var e = at(p)
	if not accessible(p) or e.is_empty() or e.kind != "belt":
		return false
	if not at(p, 1).is_empty() and posmod(direction, 2) != e.dir % 2:
		return false
	e.dir = posmod(direction, 4)
	if e.entry == e.dir:
		e.entry = -1
	return true

func _target_id(snapshot: Dictionary, from: Vector2i, destination: Vector2i) -> String:
	var id = occupancy.get(key(destination), "")
	var under_id = key(destination) + ":under"
	if snapshot.has(under_id):
		var entry = DIRS.find(from - destination)
		if entry == (snapshot[under_id].dir + 2) % 4: return under_id
		if not snapshot.has(id) or entry != (snapshot[id].dir + 2) % 4: return ""
	return id

func splitter_ports(e: Dictionary, snapshot: Dictionary = {}) -> Dictionary:
	if snapshot.is_empty(): snapshot = entities
	var ports = {"inputs": [], "outputs": []}
	for direction in range(4):
		var p = e.pos + DIRS[direction]
		if not accessible(p): continue
		for candidate in [occupancy.get(key(p), ""), key(p) + ":under"]:
			if snapshot.has(candidate) and snapshot[candidate].kind == "belt" and snapshot[candidate].dir == (direction + 2) % 4:
				if direction not in ports.inputs: ports.inputs.append(direction)
		var id = _target_id(snapshot, e.pos, p)
		if not snapshot.has(id): continue
		var neighbor = snapshot[id]
		if neighbor.kind == "belt":
			if neighbor.dir != (direction + 2) % 4 and (neighbor.dir == direction or neighbor.entry == (direction + 2) % 4):
				ports.outputs.append(direction)
		elif neighbor.kind == "multiplier":
			if neighbor.pos + DIRS[neighbor.dir] == e.pos:
				ports.inputs.append(direction)
			elif e.pos == neighbor.pos - DIRS[neighbor.dir] or e.pos == neighbor.pos + DIRS[(neighbor.dir + 3) % 4]:
				ports.outputs.append(direction)
		elif neighbor.kind in TARGETS:
			ports.outputs.append(direction)
		elif neighbor.kind == "source":
			for port in range(source_ports(neighbor)):
				if neighbor.pos + Vector2i(2, port) == e.pos:
					ports.inputs.append(direction)
	return ports

func _splitter_schedule(e: Dictionary, snapshot: Dictionary) -> Array:
	var connected = splitter_ports(e, snapshot).outputs
	var matching: Array = []
	if e.mode == 2 and splitter_unlocked(2):
		for direction in connected:
			if e.filters[direction] == e.item: matching.append(direction)
	var schedule: Array = []
	for offset in range(4):
		var direction = (e.dir + offset) % 4
		if direction not in connected: continue
		if e.mode == 2 and splitter_unlocked(2):
			if not matching.is_empty():
				if direction not in matching: continue
			elif e.filters[direction] > 0:
				continue
		var weight = e.ratio if e.mode == 1 and splitter_unlocked(1) and direction == e.dir else 1
		for i in range(weight): schedule.append(direction)
	return schedule

func _output_directions(e: Dictionary, snapshot: Dictionary) -> Array:
	if e.kind != "splitter": return [e.dir]
	var schedule = _splitter_schedule(e, snapshot)
	var result: Array = []
	for i in range(schedule.size()):
		var direction = schedule[posmod(e.cursor + i, schedule.size())]
		if direction not in result: result.append(direction)
	return result

func _next_splitter_cursor(e: Dictionary, snapshot: Dictionary, direction: int) -> int:
	var schedule = _splitter_schedule(e, snapshot)
	for i in range(schedule.size()):
		var index = posmod(e.cursor + i, schedule.size())
		if schedule[index] == direction: return (index + 1) % schedule.size()
	return 0

func tick(dt: float = STEP):
	elapsed += dt
	turn += 1
	var active = simulation_entities()
	for e in active.values():
		if not accessible(e.pos):
			continue
		if e.kind == "source":
			if not source_enabled(e): continue
			var per_port = source_rate(e)
			for port in range(source_ports(e)):
				e.charges[port] = minf(1.0, e.charges[port] + dt * per_port)
		elif e.kind == "multiplier":
			if e.output != 0:
				e.age += dt
			elif e.inputs[0] != 0 and e.inputs[1] != 0:
				# Keep both ingredients intact when their product is outside the number range.
				if e.inputs[0] * e.inputs[1] > MAX_VALUE:
					e.progress = 0.0
					continue
				e.progress += dt
				if e.progress + 0.000001 >= 1.0:
					e.output = e.inputs[0] * e.inputs[1]
					e.last_inputs = e.inputs.duplicate()
					e.inputs = [0, 0]
					e.progress = 0.0
					e.age = 0.0
		elif e.item != 0:
			e.age += dt

	# All acceptance decisions use one snapshot. Newly received items cannot move again.
	var snapshot = active.duplicate(true)
	_vacate_cache.clear()
	var reserved: Dictionary = {}
	var moves: Array = []
	propose_extra(snapshot, reserved, moves)
	var keys = snapshot.keys()
	keys.sort()
	var tie_order: Dictionary = {}
	for index in range(keys.size()):
		tie_order[keys[index]] = posmod(index - turn, keys.size())
	# Older waiting items win merges; rotating ties alone can starve a periodic stream.
	keys.sort_custom(func(left, right):
		if not is_equal_approx(float(snapshot[left].age), float(snapshot[right].age)):
			return snapshot[left].age > snapshot[right].age
		return tie_order[left] < tie_order[right])
	for id in keys:
		var e = snapshot[id]
		if not accessible(e.pos):
			continue
		if e.kind == "source":
			if not source_enabled(e): continue
			for port in range(source_ports(e)):
				if e.charges[port] >= 0.999999:
					var from = e.pos + Vector2i(1, port)
					_offer(snapshot, reserved, moves, id, from, from + Vector2i.RIGHT, e.value, port)
		elif e.kind in ["belt", "splitter", "multiplier"]:
			var value = e.output if e.kind == "multiplier" else e.item
			if value == 0 or e.age + 0.000001 < TRAVEL:
				continue
			var outputs = _output_directions(e, snapshot)
			for direction in outputs:
				if _offer(snapshot, reserved, moves, id, e.pos, e.pos + DIRS[direction], value, -1):
					if e.kind == "splitter": moves[-1].next_cursor = _next_splitter_cursor(e, snapshot, direction)
					break
	propose_after(snapshot, reserved, moves)
	# Remove proposals whose occupied destination cannot leave this same step.
	var changed = true
	while changed:
		changed = false
		var departures: Dictionary = {}
		for m in moves:
			departures[m.source] = true
		for index in range(moves.size() - 1, -1, -1):
			var m = moves[index]
			var receiver = snapshot[m.destination]
			if receiver.kind in ["belt", "splitter"] and receiver.item != 0 and not departures.has(m.destination):
				moves.remove_at(index)
				changed = true
	# Clear every departure before filling any destination, including occupied belt chains.
	for m in moves:
		if extra_departure(m): continue
		var producer = entities[m.source]
		if producer.kind == "source":
			producer.charges[m.port] = 0.0
			emitted += prime_count(m.value)
		elif producer.kind == "multiplier":
			producer.output = 0
			producer.age = 0.0
		else:
			producer.item = 0
			producer.age = 0.0
			if producer.kind == "splitter":
				producer.cursor = m.next_cursor
	for m in moves:
		if extra_arrival(m): continue
		var receiver = entities[m.destination]
		if receiver.kind in TARGETS:
			receive_target(receiver, m.value)
		elif receiver.kind == "multiplier":
			receiver.inputs[m.input] = m.value
		else:
			receiver.item = m.value
			receiver.age = 0.0
			receiver.entry = m.entry
	for kind in recent:
		while not recent[kind].is_empty() and recent[kind][0] < elapsed - 10.0:
			recent[kind].pop_front()

func _offer(snapshot: Dictionary, reserved: Dictionary, moves: Array, source: String,
		from: Vector2i, destination: Vector2i, value: int, port: int) -> bool:
	if not accessible(destination):
		return false
	var id = _target_id(snapshot, from, destination)
	if not snapshot.has(id):
		return false
	var e = snapshot[id]
	var input = -1
	var entry = DIRS.find(from - destination)
	if e.kind in TARGETS:
		if not accepts_target(e, value):
			return false
	elif e.kind == "multiplier":
		if from == e.pos - DIRS[e.dir]:
			input = 0
		elif from == e.pos + DIRS[(e.dir + 3) % 4]:
			input = 1
		else:
			return false
		if e.inputs[input] != 0:
			return false
	elif e.kind in ["belt", "splitter"]:
		if e.item != 0 and not _can_vacate(snapshot, id, {}):
			return false
		if e.kind == "splitter" and entry not in splitter_ports(e, snapshot).inputs:
			return false
		if e.kind == "belt" and entry == e.dir:
			return false
	else:
		return false
	var reservation = "%s:%d" % [id, input]
	if e.kind not in TARGETS and reserved.has(reservation):
		return false
	reserved[reservation] = true
	moves.append({"source": source, "destination": id, "value": value,
		"port": port, "input": input, "entry": entry})
	return true

func _can_vacate(snapshot: Dictionary, id: String, visited: Dictionary) -> bool:
	if _vacate_cache.has(id): return _vacate_cache[id]
	var result = _vacate_search(snapshot, id, visited)
	_vacate_cache[id] = result
	return result

func _vacate_search(snapshot: Dictionary, id: String, visited: Dictionary) -> bool:
	if visited.has(id):
		return true
	var e = snapshot[id]
	if e.age + 0.000001 < TRAVEL:
		return false
	visited[id] = true
	var outputs = _output_directions(e, snapshot)
	for direction in outputs:
		var p = e.pos + DIRS[direction]
		if not accessible(p): continue
		var target = _target_id(snapshot, e.pos, p)
		if not snapshot.has(target): continue
		var next = snapshot[target]
		if extra_can_receive(next, e.pos): return true
		if next.kind in TARGETS and accepts_target(next, e.item):
			return true
		if next.kind == "multiplier":
			if e.pos == next.pos - DIRS[next.dir] and next.inputs[0] == 0:
				return true
			if e.pos == next.pos + DIRS[(next.dir + 3) % 4] and next.inputs[1] == 0:
				return true
		if next.kind == "belt" or (next.kind == "splitter" and DIRS.find(e.pos - next.pos) in splitter_ports(next, snapshot).inputs):
			if next.kind == "belt" and e.pos == next.pos + DIRS[next.dir]: continue
			if next.item == 0 or _can_vacate(snapshot, target, visited.duplicate()):
				return true
	return false

func rate(kind: String) -> float:
	return recent[kind].size() / maxf(1.0, minf(10.0, elapsed))

static func factors(value: int) -> Array:
	var result: Array = []
	var n = value
	var divisor = 2
	while divisor * divisor <= n:
		while n % divisor == 0:
			result.append(divisor)
			n = int(n / divisor)
		divisor += 1
	if n > 1:
		result.append(n)
	return result

static func prime_count(value: int) -> int:
	return factors(value).size() if value > 1 else 0

static func mass_of(e: Dictionary) -> int:
	return prime_count(e.item) + prime_count(e.output) + prime_count(e.inputs[0]) + prime_count(e.inputs[1])

static func valid_number(value) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))

static func valid_integer(value) -> bool:
	return valid_number(value) and float(value) == float(int(value))

func total_mass() -> int:
	var mass = discarded
	for e in entities.values():
		mass += mass_of(e)
	for kind in delivered:
		mass += delivered[kind] * prime_count(TARGETS[kind])
	return mass

func serialize() -> Dictionary:
	var data: Array = []
	for entity in entities.values():
		var e = entity.duplicate(true)
		e.pos = [entity.pos.x, entity.pos.y]
		data.append(e)
	return {"version": 2, "entities": data, "delivered": delivered.duplicate(),
		"elapsed": elapsed, "turn": turn, "emitted": emitted, "discarded": discarded}

func restore(data: Dictionary) -> bool:
	if (data.get("version", 0) != 1 and data.get("version", 0) != 2) or not data.get("entities") is Array or not data.get("delivered") is Dictionary:
		return false
	if not valid_number(data.get("elapsed", 0)) or float(data.get("elapsed", 0)) < 0: return false
	var new_entities: Dictionary = {}
	var new_occupancy: Dictionary = {}
	for raw in data.entities:
		if not raw is Dictionary or not raw.get("pos") is Array or raw.pos.size() != 2:
			return false
		var p = Vector2i(int(raw.pos[0]), int(raw.pos[1]))
		var kind = str(raw.get("kind", ""))
		if kind not in ["source", "research", "exploration", "hub", "belt", "multiplier", "splitter", "logistics"]:
			return false
		var size = 2 if kind in ["source", "research", "exploration", "hub", "logistics"] else 1
		if not restore_bounds(p, size):
			return false
		var e = _base(kind, p, posmod(int(raw.get("dir", 0)), 4))
		for field in e:
			if field not in ["kind", "pos", "dir"] and raw.has(field):
				e[field] = raw[field]
		for field in ["item", "output", "mode", "ratio", "cursor", "layer", "entry", "value"]:
			if not valid_integer(e[field]): return false
			e[field] = int(e[field])
		if not e.inputs is Array or e.inputs.size() != 2 or not e.charges is Array or e.charges.size() != 2 or not e.last_inputs is Array or e.last_inputs.size() != 2:
			return false
		for values in [e.inputs, e.last_inputs]:
			for value in values:
				if not valid_integer(value): return false
		e.inputs = [int(e.inputs[0]), int(e.inputs[1])]
		e.last_inputs = [int(e.last_inputs[0]), int(e.last_inputs[1])]
		if not e.outputs is Array or e.outputs.size() != 8 or not e.port_age is Array or e.port_age.size() != 8 or not e.log_recent is Array: return false
		for i in range(8):
			if not valid_integer(e.outputs[i]) or not valid_number(e.port_age[i]): return false
			e.outputs[i] = int(e.outputs[i])
			e.port_age[i] = clampf(float(e.port_age[i]), 0.0, TRAVEL)
			if e.outputs[i] < 0 or e.outputs[i] == 1 or e.outputs[i] > MAX_VALUE: return false
		for field in ["budget", "age", "progress"]:
			if not valid_number(e[field]) or float(e[field]) < 0: return false
		for time in e.log_recent:
			if not valid_number(time) or float(time) < 0 or float(time) > float(data.get("elapsed", 0)): return false
		e.budget = clampf(float(e.budget), 0.0, 1.0)
		if not e.filters is Array or e.filters.size() != 4: return false
		for i in range(4):
			if not valid_integer(e.filters[i]): return false
			e.filters[i] = int(e.filters[i])
			if e.filters[i] < -1 or e.filters[i] == 1 or e.filters[i] > MAX_VALUE: return false
		if kind == "splitter" and not raw.has("filters") and e.mode == 2:
			var legacy_filter = int(raw.get("filter", 2))
			if legacy_filter < 2 or legacy_filter > MAX_VALUE: return false
			e.filters[e.dir] = legacy_filter
			e.filters[(e.dir + 1) % 4] = -1
		for value in [e.item, e.output, e.inputs[0], e.inputs[1], e.last_inputs[0], e.last_inputs[1]]:
			if value < 0 or value == 1 or value > MAX_VALUE:
				return false
		if e.last_inputs[0] * e.last_inputs[1] > MAX_VALUE:
			return false
		if kind == "source" and not valid_source(e.value):
			return false
		e.ratio = clampi(e.ratio, 1, 9)
		e.mode = clampi(e.mode, 0, 2)
		for charge in e.charges:
			if not valid_number(charge): return false
		e.charges = [clampf(float(e.charges[0]), 0, 1), clampf(float(e.charges[1]), 0, 1)]
		if e.layer not in [0, 1] or (e.layer == 1 and kind != "belt"): return false
		var id = key(p) + (":under" if e.layer == 1 else "")
		if new_entities.has(id): return false
		new_entities[id] = e
		if e.layer == 1: continue
		for y in range(size):
			for x in range(size):
				var cell = key(p + Vector2i(x, y))
				if new_occupancy.has(cell):
					return false
				new_occupancy[cell] = key(p)
	for e in new_entities.values():
		if e.layer != 1: continue
		var ground = new_entities.get(key(e.pos), {})
		if ground.is_empty() or ground.kind != "belt" or ground.dir % 2 == e.dir % 2: return false
		if ground.entry >= 0 and ground.entry != (ground.dir + 2) % 4: return false
		if e.entry != (e.dir + 2) % 4: return false
	if data.get("version", 0) == 1:
		# Older splitters implicitly connected their front/right belts, including empty bends.
		for e in new_entities.values():
			if e.kind != "splitter": continue
			for facing in [e.dir, (e.dir + 1) % 4]:
				var neighbor = new_entities.get(key(e.pos + DIRS[facing]), {})
				if not neighbor.is_empty() and neighbor.kind == "belt" and neighbor.entry == -1 and neighbor.dir != (facing + 2) % 4 and not new_entities.has(key(neighbor.pos) + ":under"):
					neighbor.entry = (facing + 2) % 4
	var progress: Dictionary = {}
	for kind in GOALS:
		if not data.delivered.has(kind) or int(data.delivered[kind]) < 0:
			return false
		progress[kind] = int(data.delivered[kind])
	entities = new_entities
	occupancy = new_occupancy
	delivered = progress
	elapsed = maxf(0.0, float(data.get("elapsed", 0.0)))
	turn = int(data.get("turn", 0))
	emitted = int(data.get("emitted", 0))
	discarded = int(data.get("discarded", 0))
	recent = {"research": [], "exploration": [], "hub": []}
	return true
