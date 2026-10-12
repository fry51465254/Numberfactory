class_name WorldSim
extends FactorySim

var world: WorldProgress
var generator: WorldGenerator
var loaded_chunks: Dictionary = {}
var sparse_from_ring: int = 0
var session_paused: bool = false
var _preview_key: String = ""
var _preview_resources: Dictionary = {}
var logistics_last_served: String = ""
const LOGISTICS_RATE = 6.0
const LOG_PORTS = [Vector2i(2, 0), Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, -1), Vector2i(1, -1)]

func _init(world_seed: int = 51465254, first_sparse_ring: int = 0):
	super(false)
	world = WorldProgress.new(world_seed)
	generator = WorldGenerator.new(world.seed_value, first_sparse_ring)
	reset(world_seed, first_sparse_ring)

func reset(world_seed: int = 51465254, first_sparse_ring: int = 0):
	sparse_from_ring = first_sparse_ring
	world = WorldProgress.new(world_seed)
	generator = WorldGenerator.new(world.seed_value, sparse_from_ring)
	_preview_key = ""
	_preview_resources = {}
	loaded_chunks.clear()
	session_paused = false
	logistics_last_served = ""
	entities.clear()
	occupancy.clear()
	delivered = {"research": 0, "exploration": 0, "hub": 0}
	recent = {"research": [], "exploration": [], "hub": []}
	elapsed = 0.0
	turn = 0
	emitted = 0
	discarded = 0
	_add_fixed("research", Vector2i(0, -1))
	ensure_area(Rect2i(-12, -8, 24, 16))
	for y in [-4, -3, 4, 5]:
		place(Vector2i(-6, y), "belt", 0)

func accessible(p: Vector2i) -> bool:
	return world != null and world.accessible(p)

func unlocked() -> bool:
	return world != null and world.expansions > 0

func complete() -> bool:
	return false

func ensure_area(area: Rect2i):
	var first = WorldGenerator.chunk_of(area.position)
	var last = WorldGenerator.chunk_of(area.end - Vector2i.ONE)
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1): ensure_chunk(Vector2i(x, y))

func ensure_chunk(chunk: Vector2i):
	var id = key(chunk)
	if loaded_chunks.has(id): return
	if not world.bounds().intersects(Rect2i(chunk * 8, Vector2i(8, 8))): return
	loaded_chunks[id] = true
	for deposit in generator.deposits(chunk):
		_add_fixed("source", deposit.pos, deposit.value)

func at(p: Vector2i, layer: int = 0) -> Dictionary:
	if accessible(p): ensure_chunk(WorldGenerator.chunk_of(p))
	return super(p, layer)

func can_place(p: Vector2i) -> bool:
	if accessible(p): ensure_chunk(WorldGenerator.chunk_of(p))
	return super(p)

func logistics_used() -> int:
	var count = 0
	for e in entities.values():
		if e.kind == "logistics": count += 1
	return count

func next_ring_resources() -> Dictionary:
	var stamp = "%d:%d:%d" % [world.seed_value, world.expansions, sparse_from_ring]
	if stamp == _preview_key: return _preview_resources
	var bounds = world.bounds().grow(8)
	var first = WorldGenerator.chunk_of(bounds.position)
	var last = WorldGenerator.chunk_of(bounds.end - Vector2i.ONE)
	var chunks: Array = []
	for x in range(first.x, last.x + 1):
		chunks.append(Vector2i(x, first.y))
		chunks.append(Vector2i(x, last.y))
	for y in range(first.y + 1, last.y):
		chunks.append(Vector2i(first.x, y))
		chunks.append(Vector2i(last.x, y))
	_preview_resources = {}
	for chunk in chunks:
		for deposit in generator.deposits(chunk):
			_preview_resources[deposit.value] = int(_preview_resources.get(deposit.value, 0)) + 1
	_preview_key = stamp
	return _preview_resources

func can_place_logistics(p: Vector2i) -> bool:
	if "logistics" not in world.technologies or logistics_used() >= world.logistics_capacity: return false
	for offset in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
		if not can_place(p + offset): return false
	return true

func place(p: Vector2i, kind: String, direction: int) -> bool:
	if kind != "logistics": return super(p, kind, direction)
	if not can_place_logistics(p): return false
	_add_fixed("logistics", p)
	return true

func remove(p: Vector2i) -> bool:
	var e = at(p)
	if e.is_empty() or e.kind != "logistics": return super(p)
	for offset in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]: occupancy.erase(key(e.pos + offset))
	entities.erase(key(e.pos))
	return true

func logistics_ports(e: Dictionary, snapshot: Dictionary = {}) -> Array:
	if snapshot.is_empty(): snapshot = entities
	var ports: Array = []
	for i in range(8):
		var facing = int(i / 2)
		var p = e.pos + LOG_PORTS[i]
		var id = _target_id(snapshot, p - DIRS[facing], p)
		var neighbor = snapshot.get(id, {})
		var mode = "none"
		for candidate in [occupancy.get(key(p), ""), key(p) + ":under"]:
			var incoming = snapshot.get(candidate, {})
			if not incoming.is_empty() and incoming.kind == "belt" and incoming.dir == (facing + 2) % 4:
				mode = "input"
				id = candidate
				break
		if mode == "none" and not neighbor.is_empty() and neighbor.kind == "belt" and neighbor.dir == facing:
			mode = "output"
		ports.append({"index": i, "pos": p, "from": p - DIRS[facing], "facing": facing, "mode": mode, "id": id})
	return ports

func logistics_port_state(e: Dictionary, port: Dictionary) -> String:
	if port.mode == "none": return "未连接"
	var id = port.id
	var neighbor = entities.get(id, {})
	if port.mode == "output":
		var value = int(e.outputs[port.index])
		if value == 0: return "未设置"
		if world.count(world.logistics_stock, value) == 0: return "缺货"
		_vacate_cache.clear()
		if neighbor.is_empty() or (neighbor.item != 0 and not _can_vacate(entities, id, {})): return "下游堵塞"
	elif neighbor.is_empty() or neighbor.item == 0:
		return "等待物料"
	if e.budget < 0.999999: return "整站限速"
	if e.port_age[port.index] + 0.000001 < TRAVEL: return "端口限速"
	return "就绪"

func tick(dt: float = STEP):
	for e in entities.values():
		if e.kind != "logistics": continue
		e.budget = minf(1.0, e.budget + dt * LOGISTICS_RATE)
		for i in range(8): e.port_age[i] = minf(TRAVEL, e.port_age[i] + dt)
		while not e.log_recent.is_empty() and e.log_recent[0] < elapsed - 10.0: e.log_recent.pop_front()
	super(dt)

func propose_extra(snapshot: Dictionary, reserved: Dictionary, moves: Array):
	if turn % 2 == 0: _propose_logistics(snapshot, reserved, moves)

func propose_after(snapshot: Dictionary, reserved: Dictionary, moves: Array):
	if turn % 2 != 0: _propose_logistics(snapshot, reserved, moves)

func _propose_logistics(snapshot: Dictionary, reserved: Dictionary, moves: Array):
	var ids = snapshot.keys().filter(func(id): return snapshot[id].kind == "logistics")
	ids.sort()
	if not ids.is_empty() and logistics_last_served in ids:
		var offset = (ids.find(logistics_last_served) + 1) % ids.size()
		ids = ids.slice(offset) + ids.slice(0, offset)
	for id in ids:
		var e = snapshot[id]
		var ports = logistics_ports(e, snapshot)
		for offset in range(8):
			var i = (e.cursor + offset) % 8
			var port = ports[i]
			var value = int(e.outputs[i])
			if port.mode != "output" or value < 2 or e.port_age[i] + 0.000001 < TRAVEL: continue
			var budget_id = "budget:" + id
			if e.budget - int(reserved.get(budget_id, 0)) < 0.999999: continue
			var stock_id = "stock:%d" % value
			if world.count(world.logistics_stock, value) <= int(reserved.get(stock_id, 0)): continue
			if _offer(snapshot, reserved, moves, id, port.from, port.pos, value, i):
				reserved[stock_id] = int(reserved.get(stock_id, 0)) + 1
				reserved[budget_id] = int(reserved.get(budget_id, 0)) + 1

func extra_can_receive(e: Dictionary, from: Vector2i) -> bool:
	if e.kind != "logistics" or e.budget < 0.999999: return false
	for port in logistics_ports(e):
		if port.pos == from and port.mode == "input" and e.port_age[port.index] + 0.000001 >= TRAVEL: return true
	return false

func _offer(snapshot: Dictionary, reserved: Dictionary, moves: Array, source: String,
		from: Vector2i, destination: Vector2i, value: int, port: int) -> bool:
	var id = _target_id(snapshot, from, destination)
	var e = snapshot.get(id, {})
	if e.is_empty() or e.kind != "logistics": return super(snapshot, reserved, moves, source, from, destination, value, port)
	# A station accepts only adjacent incoming belts, never machines or other stations.
	if snapshot[source].kind != "belt": return false
	for input_port in logistics_ports(e, snapshot):
		if input_port.pos != from or input_port.mode != "input": continue
		var budget_id = "budget:" + id
		var port_id = "port:%s:%d" % [id, input_port.index]
		if reserved.has(port_id) or e.budget - int(reserved.get(budget_id, 0)) < 0.999999: return false
		if e.port_age[input_port.index] + 0.000001 < TRAVEL: return false
		reserved[budget_id] = int(reserved.get(budget_id, 0)) + 1
		reserved[port_id] = true
		moves.append({"source": source, "destination": id, "value": value,
			"port": port, "input": input_port.index, "entry": DIRS.find(from - destination)})
		return true
	return false

func extra_departure(move: Dictionary) -> bool:
	var e = entities[move.source]
	if e.kind != "logistics": return false
	var value = str(move.value)
	world.logistics_stock[value] -= 1
	# Advance only on committed transfers, so periodic supply cannot lock a station out.
	logistics_last_served = move.source
	e.budget -= 1.0
	e.port_age[move.port] = 0.0
	e.cursor = (move.port + 1) % 8
	e.log_recent.append(elapsed)
	return true

func extra_arrival(move: Dictionary) -> bool:
	var e = entities[move.destination]
	if e.kind != "logistics": return false
	var value = str(move.value)
	world.logistics_stock[value] = world.count(world.logistics_stock, move.value) + 1
	e.budget -= 1.0
	e.port_age[move.input] = 0.0
	e.log_recent.append(elapsed)
	return true

func source_ports(e: Dictionary) -> int:
	return 2 if e.value in [2, 3] else 1

func source_rate(e: Dictionary) -> float:
	return 3.0 if e.value == 2 else 2.0

func source_enabled(e: Dictionary) -> bool:
	return e.value in world.primes

func source_shared_rate() -> bool:
	return true

func source_sockets(e: Dictionary) -> Array:
	var sockets: Array = []
	for i in range(8):
		var facing = int(i / 2)
		var p = e.pos + LOG_PORTS[i]
		sockets.append({"index": i, "pos": p, "from": p - DIRS[facing], "facing": facing})
	return sockets

func splitter_unlocked(mode: int) -> bool:
	return mode == 0 or ("ratio" if mode == 1 else "filter") in world.technologies

func accepts_target(e: Dictionary, value: int) -> bool:
	return e.kind == "research" and value in world.recipes

func receive_target(e: Dictionary, value: int):
	if world.deposit(value): super(e, value)

func simulation_entities() -> Dictionary:
	var active: Dictionary = {}
	for id in entities:
		var e = entities[id]
		if e.kind != "source":
			active[id] = e
			if e.kind == "belt":
				var incoming: Array = [e.dir]
				if e.entry >= 0 and (e.entry + 2) % 4 not in incoming: incoming.append((e.entry + 2) % 4)
				for facing in incoming:
					var from = e.pos - DIRS[facing]
					var source_id = occupancy.get(key(from), "")
					var source = entities.get(source_id, {})
					if not source.is_empty() and source.kind == "source" and source_enabled(source) and _target_id(entities, from, e.pos) == id and belt_connects_from(e, (facing + 2) % 4):
						active[source_id] = source
	return active

func restore_bounds(p: Vector2i, size: int) -> bool:
	return world.accessible(p) and world.accessible(p + Vector2i.ONE * (size - 1))

func valid_source(value: int) -> bool:
	return value <= MAX_VALUE and WorldProgress.is_prime(value)

func total_mass() -> int:
	var mass = discarded
	for e in entities.values(): mass += mass_of(e)
	for value in world.lifetime: mass += int(world.lifetime[value]) * prime_count(int(value))
	for value in world.logistics_stock: mass += int(world.logistics_stock[value]) * prime_count(int(value))
	return mass

func serialize() -> Dictionary:
	var data = super()
	data.version = 3
	data.world = world.serialize()
	data.loaded_chunks = loaded_chunks.keys()
	data.paused = session_paused
	data.logistics_last_served = logistics_last_served
	data.generation_version = WorldGenerator.CURRENT_VERSION
	data.sparse_from_ring = sparse_from_ring
	return data

func restore(data: Dictionary) -> bool:
	if int(data.get("version", 0)) != 3 or not data.get("world") is Dictionary or not data.get("loaded_chunks") is Array or not data.get("entities") is Array: return false
	var candidate = WorldProgress.new()
	if not candidate.restore(data.world): return false
	var generation_version = data.get("generation_version", 1)
	if not valid_integer(generation_version) or int(generation_version) not in [1, WorldGenerator.CURRENT_VERSION]: return false
	var first_sparse_ring = candidate.expansions + 1
	if int(generation_version) == WorldGenerator.CURRENT_VERSION:
		var cutoff = data.get("sparse_from_ring")
		if not valid_integer(cutoff) or int(cutoff) < 0 or int(cutoff) > candidate.expansions + 1: return false
		first_sparse_ring = int(cutoff)
	elif data.has("sparse_from_ring"):
		return false
	var chunks: Dictionary = {}
	for raw in data.loaded_chunks:
		var coordinates = str(raw).split(",")
		if coordinates.size() != 2 or not coordinates[0].is_valid_int() or not coordinates[1].is_valid_int(): return false
		var chunk = Vector2i(int(coordinates[0]), int(coordinates[1]))
		if key(chunk) != str(raw) or chunks.has(str(raw)) or not candidate.bounds().intersects(Rect2i(chunk * 8, Vector2i.ONE * 8)): return false
		chunks[str(raw)] = true
	var stations = 0
	var sources: Dictionary = {}
	var research_count = 0
	for raw in data.entities:
		if not raw is Dictionary or not raw.get("pos") is Array or raw.pos.size() != 2: return false
		for coordinate in raw.pos:
			if typeof(coordinate) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(coordinate)) or float(coordinate) != float(int(coordinate)): return false
			if int(coordinate) < -WorldProgress.MAX_SEED or int(coordinate) > WorldProgress.MAX_SEED: return false
		var p = Vector2i(int(raw.pos[0]), int(raw.pos[1]))
		if not chunks.has(key(WorldGenerator.chunk_of(p))): return false
		if raw.get("kind") == "logistics": stations += 1
		if raw.get("kind") == "source": sources[key(p)] = int(raw.get("value", 0))
		if raw.get("kind") == "research":
			research_count += 1
			if p != Vector2i(0, -1): return false
		if raw.get("kind") in ["exploration", "hub"]: return false
	if research_count != 1: return false
	var candidate_generator = WorldGenerator.new(candidate.seed_value, first_sparse_ring)
	var expected_sources: Dictionary = {}
	for id in chunks:
		var coordinates = id.split(",")
		for deposit in candidate_generator.deposits(Vector2i(int(coordinates[0]), int(coordinates[1]))):
			expected_sources[key(deposit.pos)] = deposit.value
	if sources != expected_sources: return false
	if stations > candidate.logistics_capacity or (stations > 0 and "logistics" not in candidate.technologies): return false
	var previous = world
	world = candidate
	var compatible = data.duplicate(true)
	compatible.version = 2
	if not super(compatible):
		world = previous
		return false
	generator = candidate_generator
	sparse_from_ring = first_sparse_ring
	loaded_chunks = chunks
	session_paused = bool(data.get("paused", false))
	logistics_last_served = str(data.get("logistics_last_served", ""))
	return true
