class_name BuildLayout
extends RefCounted

const FIELDS = {"belt": ["dir", "entry", "layer"], "multiplier": ["dir"], "splitter": ["dir", "mode", "ratio", "filters"], "logistics": ["dir", "outputs"], "stellar": ["dir", "outputs"]}
const COPY_LIMIT = 4096

static func config(e: Dictionary) -> Dictionary:
	if e.is_empty() or e.kind not in FIELDS: return {}
	var result = {"kind": e.kind, "pos": e.pos}
	for field in FIELDS[e.kind]: result[field] = e[field].duplicate() if e[field] is Array else e[field]
	return result

static func identity(e: Dictionary) -> String:
	return FactorySim.key(e.pos) + (":under" if e.get("layer", 0) == 1 else "")

static func matches(actual: Dictionary, expected: Dictionary) -> bool:
	if actual == expected: return true
	if not actual.is_empty() and not expected.is_empty() and actual.kind == "belt" and expected.kind == "belt" and expected.entry < 0:
		var inferred = expected.duplicate(true)
		inferred.entry = actual.entry
		return actual == inferred
	return false

static func extent(e: Dictionary) -> int:
	return 2 if WorldSim.is_station(e.kind) else 1

static func bounds(nodes: Array) -> Rect2i:
	var result = Rect2i()
	for node in nodes:
		var rect = Rect2i(node.pos, Vector2i.ONE * extent(node))
		result = rect if not result.has_area() else result.merge(rect)
	return result

static func in_region(sim: FactorySim, area: Rect2i) -> Array:
	var ids: Array = []
	for id in sim.entities:
		var e = sim.entities[id]
		if e.kind in FIELDS and area.intersects(Rect2i(e.pos, Vector2i.ONE * extent(e))): ids.append(id)
	ids.sort()
	return ids

static func copy(sim: FactorySim, ids: Array) -> Array:
	var nodes: Array = []
	for id in ids:
		var node = config(sim.entities.get(id, {}))
		if not node.is_empty(): nodes.append(node)
	if nodes.size() > COPY_LIMIT: return []
	var origin = bounds(nodes).position
	for node in nodes: node.pos -= origin
	return nodes

static func rotate(nodes: Array) -> Array:
	var result = nodes.duplicate(true)
	var height = bounds(nodes).size.y
	for node in result:
		node.pos = Vector2i(height - node.pos.y - extent(node), node.pos.x)
		node.dir = (node.dir + 1) % 4
		if node.kind == "belt" and node.entry >= 0: node.entry = (node.entry + 1) % 4
		if node.kind == "splitter":
			var filters = node.filters.duplicate()
			for i in range(4): node.filters[(i + 1) % 4] = filters[i]
		if WorldSim.is_station(node.kind):
			var outputs = node.outputs.duplicate()
			for i in range(8):
				var p = WorldSim.LOG_PORTS[i]
				var index = WorldSim.LOG_PORTS.find(Vector2i(1 - p.y, p.x))
				node.outputs[index] = outputs[i]
	return result

static func plan(sim: FactorySim, nodes: Array, origin: Vector2i) -> Dictionary:
	var before: Dictionary = {}
	var after: Dictionary = {}
	for original in nodes:
		var node = original.duplicate(true)
		node.pos += origin
		# Pasted straight lines use the same underground crossing rule as hand-painted lines.
		var ground = sim.at(node.pos)
		if node.kind == "belt" and node.layer == 0 and not ground.is_empty() and ground.kind == "belt" and ground.dir % 2 != node.dir % 2:
			if node.entry < 0 or node.entry == (node.dir + 2) % 4:
				node.layer = 1
				node.entry = (node.dir + 2) % 4
		var id = identity(node)
		if after.has(id): return {"valid": false, "reason": "蓝图线路在同一层重叠", "nodes": nodes_at(nodes, origin)}
		before[id] = config(sim.entities.get(id, {}))
		after[id] = node
	var reason = validate(sim, before, after, true)
	return {"valid": reason.is_empty(), "reason": reason, "nodes": after.values(), "before": before, "after": after}

static func nodes_at(nodes: Array, origin: Vector2i) -> Array:
	var result = nodes.duplicate(true)
	for node in result: node.pos += origin
	return result

static func validate(sim: FactorySim, before: Dictionary, after: Dictionary, paste: bool = false) -> String:
	for id in before:
		if not matches(config(sim.entities.get(id, {})), before[id]): return "设备布局已改变，无法执行这一步"
		if paste and not before[id].is_empty() and not matches(before[id], after.get(id, {})): return "位置已被占用"
	# Reveal terrain before validating the complete final occupancy, without producing items.
	for node in after.values():
		if node.is_empty(): continue
		if node.kind not in FIELDS: return "此设施不可复制"
		for y in range(extent(node)):
			for x in range(extent(node)):
				var p = node.pos + Vector2i(x, y)
				if not sim.accessible(p): return "蓝图超出已开放区域"
				sim.at(p)
	var occupied = sim.occupancy.duplicate()
	for p in occupied.keys():
		if occupied[p] in before and not before[occupied[p]].is_empty():
			occupied.erase(p)
	var stations = sim.logistics_used() if sim is WorldSim else 0
	var towers = sim.network.used if sim is WorldSim and sim.network != null else 0
	for node in before.values():
		if not node.is_empty() and node.kind == "logistics": stations -= 1
		if not node.is_empty() and node.kind == "stellar": towers -= 1
	for id in after:
		var node = after[id]
		if node.is_empty(): continue
		if id != identity(node): return "设备坐标无效"
		if node.kind == "logistics":
			if not sim is WorldSim or "logistics" not in sim.world.technologies: return "共享物流尚未研究"
			stations += 1
		if node.kind == "stellar":
			if not sim is WorldSim or sim.network == null or not sim.network.unlocked: return "星际物流尚未研究"
			towers += 1
		if node.get("layer", 0) == 1: continue
		for y in range(extent(node)):
			for x in range(extent(node)):
				var p = FactorySim.key(node.pos + Vector2i(x, y))
				if occupied.has(p): return "位置已被占用"
				occupied[p] = id
	if sim is WorldSim and stations > sim.world.logistics_capacity: return "物流站建造额度不足"
	if sim is WorldSim and sim.network != null and towers > sim.network.capacity: return "星际塔全局额度不足"
	var checked: Dictionary = {}
	for id in before.keys() + after.keys():
		var node = after.get(id, before.get(id, {}))
		if node.is_empty(): node = before.get(id, {})
		if node.is_empty(): continue
		var ground_id = FactorySim.key(node.pos)
		if checked.has(ground_id): continue
		checked[ground_id] = true
		var under = after.get(ground_id + ":under", config(sim.entities.get(ground_id + ":under", {})))
		if under.is_empty(): continue
		var ground = after.get(ground_id, config(sim.entities.get(ground_id, {})))
		if ground.is_empty() or ground.kind != "belt" or under.kind != "belt" or ground.dir % 2 == under.dir % 2: return "地下通道需要正交的地面直带"
		if ground.entry >= 0 and ground.entry != (ground.dir + 2) % 4: return "转弯处无法地下交叉"
		if under.entry != (under.dir + 2) % 4: return "地下通道只能直行"
	return ""

static func apply(sim: FactorySim, before: Dictionary, after: Dictionary) -> String:
	var reason = validate(sim, before, after)
	if not reason.is_empty(): return reason
	# Keep live entities when only configuration changes; recreate removed devices empty.
	for layer in [1, 0]:
		for id in before:
			var old = before[id]
			var next = after.get(id, {})
			if old.is_empty() or old.get("layer", 0) != layer: continue
			if not next.is_empty() and next.kind == old.kind: continue
			if layer == 1: sim.remove_underground(old.pos)
			else: sim.remove(old.pos)
	for layer in [0, 1]:
		for id in after:
			var node = after[id]
			if node.is_empty() or node.get("layer", 0) != layer: continue
			var entity = sim.entities.get(id, {})
			if entity.is_empty():
				if layer == 1: sim.build_belt(node.pos, node.dir, node.entry, true)
				else: sim.place(node.pos, node.kind, node.dir)
				entity = sim.entities[id]
			for field in FIELDS[node.kind]:
				if field == "entry" and node.entry < 0 and entity.entry >= 0: continue
				entity[field] = node[field].duplicate() if node[field] is Array else node[field]
	for node in after.values() + before.values():
		if not node.is_empty(): sim.refresh_neighbor_ports(node.pos)
	return ""
