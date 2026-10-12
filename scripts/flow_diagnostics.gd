class_name FlowDiagnostics
extends RefCounted

const NONE = Vector2i(-1000000000, -1000000000)
const DIRECTIONS = ["东", "南", "西", "北"]
var sim: FactorySim
var remaining = 0

func _init(factory: FactorySim):
	sim = factory

func result(message: String, warning: bool = false, cell: Vector2i = NONE) -> Dictionary:
	return {"text": message, "warning": warning, "cell": cell}

func entity_at(p: Vector2i, layer: int = 0) -> Dictionary:
	var id = FactorySim.key(p) + ":under" if layer == 1 else sim.occupancy.get(FactorySim.key(p), "")
	return sim.entities.get(id, {})

func identity(e: Dictionary) -> String:
	return FactorySim.key(e.pos) + (":under" if e.layer == 1 else "")

func coordinate(p: Vector2i) -> String:
	return "（%d, %d）" % [p.x, p.y]

func incoming(e: Dictionary, input_slot: int = -1) -> Array:
	var found: Array = []
	var directions: Array = range(4)
	if e.kind == "multiplier":
		var ports = sim.multiplier_ports(e)
		directions = ports.inputs if input_slot < 0 else [ports.slots[input_slot]] if ports.slots[input_slot] >= 0 else []
	for facing in directions:
		if e.kind == "belt" and facing == e.dir: continue
		var p = e.pos + FactorySim.DIRS[facing]
		for layer in range(2):
			var neighbor = entity_at(p, layer)
			if neighbor.is_empty(): continue
			if e.kind in ["belt", "splitter"] and sim._target_id(sim.entities, p, e.pos) != identity(e): continue
			var connected = false
			match neighbor.kind:
				"belt":
					connected = neighbor.pos + FactorySim.DIRS[neighbor.dir] == e.pos
				"multiplier":
					connected = (facing + 2) % 4 in sim.multiplier_ports(neighbor).outputs
				"splitter":
					connected = (facing + 2) % 4 in sim.splitter_ports(neighbor).outputs
				"source":
					for port in sim.source_connections(neighbor):
						if port.pos == e.pos: connected = true
				"logistics":
					if sim is WorldSim:
						for port in sim.logistics_ports(neighbor):
							if port.pos == e.pos and port.mode == "output": connected = true
			if connected and neighbor not in found: found.append(neighbor)
	return found

func upstream(e: Dictionary) -> Dictionary:
	var queue: Array = [{"entity": e, "via": NONE}]
	var visited: Dictionary = {}
	var last = e.pos
	for _step in range(128):
		if queue.is_empty(): return result("未连接矿点、乘法机或物流输出；断点或闭环 " + coordinate(last), true, last)
		var node = queue.pop_front()
		var current = node.entity
		var id = identity(current)
		if visited.has(id):
			continue
		visited[id] = true
		last = current.pos
		if current.kind == "source":
			if not sim.source_enabled(current): return result("矿点 %d 尚未研究 %s" % [current.value, coordinate(current.pos)], true, current.pos)
			return result("等待矿点 %d 出料 %s" % [current.value, coordinate(current.pos)])
		if current.kind == "multiplier":
			if current.output != 0: return result("等待上游乘法机输出 " + coordinate(current.pos))
			if current.inputs[0] * current.inputs[1] > FactorySim.MAX_VALUE:
				return result("上游乘法机乘积超出 999999 " + coordinate(current.pos), true, current.pos)
			if current.inputs[0] == 0 or current.inputs[1] == 0:
				var slot = 0 if current.inputs[0] == 0 else 1
				return result("等待上游乘法机输入 %s %s" % ["A" if slot == 0 else "B", coordinate(current.pos)], incoming(current, slot).is_empty(), current.pos)
			return result("等待上游乘法机加工 " + coordinate(current.pos))
		if current.kind == "logistics" and sim is WorldSim:
			for port in sim.logistics_ports(current):
				if port.mode != "output" or port.pos != node.via: continue
				var value = current.outputs[port.index]
				if value == 0: return result("物流站 %s %s%d 输出未设置" % [coordinate(current.pos), DIRECTIONS[port.facing], port.index % 2 + 1], true, current.pos)
				if sim.world.count(sim.world.logistics_stock, value) == 0: return result("物流库存缺少数字 %d %s" % [value, coordinate(current.pos)], true, current.pos)
			return result("等待物流站输出 " + coordinate(current.pos))
		var producers = incoming(current)
		if producers.is_empty(): last = current.pos
		for producer in producers: queue.append({"entity": producer, "via": current.pos})
	return result("上游路径较长或存在循环；已检查 128 格")

func logistics_output(e: Dictionary, port: Dictionary) -> Dictionary:
	var value = int(e.outputs[port.index])
	if value == 0: return result("输出数字未设置", true, e.pos)
	if sim.world.count(sim.world.logistics_stock, value) == 0: return result("物流库存缺少数字 %d" % value, true, e.pos)
	return downstream({"pos": port.from, "kind": "belt", "dir": port.facing, "layer": 0}, value)

func downstream(e: Dictionary, value: int, direction: int = -1) -> Dictionary:
	remaining = 128
	return _walk(e, value, direction, {})

# Follow occupied conveyors to the first real obstruction, using no simulation caches.
func _walk(e: Dictionary, value: int, direction: int, visited: Dictionary) -> Dictionary:
	remaining -= 1
	if remaining <= 0: return result("下游路径较长；已检查 128 格")
	var id = identity(e)
	if visited.has(id):
		return result("下游为循环传送带") if id == visited.keys()[0] else result("下游闭环已满，无法加入新物料 " + coordinate(e.pos), true, e.pos)
	visited = visited.duplicate()
	visited[id] = true
	var outputs = [direction] if direction >= 0 else sim._output_directions(e, sim.entities)
	if outputs.is_empty(): return result("乘法机未连接输出传送带 " + coordinate(e.pos), true, e.pos) if e.kind == "multiplier" else result("分流器无匹配输出：数字 %d %s" % [value, coordinate(e.pos)], true, e.pos)
	var obstruction = result("下游畅通")
	for facing in outputs:
		var destination = e.pos + FactorySim.DIRS[facing]
		var target = sim.entities.get(sim._target_id(sim.entities, e.pos, destination), {})
		var state: Dictionary
		if target.is_empty():
			state = result("地下交叉段方向不匹配 " + coordinate(destination), true, destination) if not entity_at(destination).is_empty() else result("%s口未连接下游 %s" % [DIRECTIONS[facing], coordinate(destination)], true, destination)
		elif target.kind in FactorySim.TARGETS:
			state = result("下游畅通") if value < 2 or sim.accepts_target(target, value) else result("%s %s 不接收数字 %d" % [{"research": "研究站", "exploration": "探索站", "hub": "枢纽"}[target.kind], coordinate(target.pos), value], true, target.pos)
		elif target.kind == "multiplier":
			var slot = sim.multiplier_input(target, e.pos)
			if slot < 0:
				state = result("乘法机最多接入两个输入；此方向未接入 %s" % coordinate(target.pos), true, target.pos)
			elif target.inputs[slot] == 0:
				state = result("下游畅通")
			elif target.output != 0:
				state = _walk(target, target.output, -1, visited)
			elif target.inputs[0] * target.inputs[1] > FactorySim.MAX_VALUE:
				state = result("乘法机乘积超出 999999 " + coordinate(target.pos), true, target.pos)
			elif target.inputs[1 - slot] == 0:
				var supply = upstream_input(target, 1 - slot)
				state = result("乘法机等待输入 %s %s · %s" % ["B" if slot == 0 else "A", coordinate(target.pos), supply.text], supply.warning, supply.cell if supply.warning else target.pos)
			else:
				state = result("等待乘法机加工完成 " + coordinate(target.pos))
		elif target.kind in ["belt", "splitter"]:
			var entry = FactorySim.DIRS.find(e.pos - target.pos)
			if (target.kind == "belt" and entry == target.dir) or (target.kind == "splitter" and entry not in sim.splitter_ports(target).inputs):
				state = result("传送带方向不兼容 " + coordinate(target.pos), true, target.pos)
			elif target.item == 0:
				state = result("下游畅通")
			elif target.age + 0.000001 < FactorySim.TRAVEL:
				state = result("等待下游传送周期 " + coordinate(target.pos))
			else:
				state = _walk(target, target.item, -1, visited)
		elif target.kind == "logistics" and sim is WorldSim:
			state = result("物流输入未连接 " + coordinate(target.pos), true, target.pos)
			for port in sim.logistics_ports(target):
				if port.mode == "input" and port.pos == e.pos:
					state = result("等待物流站吞吐额度 " + coordinate(target.pos))
		else:
			state = result("下游是矿点，不能接收物料 " + coordinate(target.pos), true, target.pos)
		if not state.warning: return state
		obstruction = state
	return obstruction

func describe(e: Dictionary) -> Dictionary:
	if e.kind == "multiplier":
		if e.output != 0: return downstream(e, e.output)
		if e.inputs[0] * e.inputs[1] > FactorySim.MAX_VALUE: return result("乘积超出 999999；输入 A / B 的乘积不可加工", true, e.pos)
		if e.inputs[0] != 0 and e.inputs[1] != 0: return result("加工中")
		var slot = 0 if e.inputs[0] == 0 else 1
		var facing = sim.multiplier_ports(e).slots[slot]
		var supply = upstream_input(e, slot)
		return result("等待输入 %s · %s · %s" % ["A" if slot == 0 else "B", DIRECTIONS[facing] + "口" if facing >= 0 else "未连接端口", supply.text], supply.warning, supply.cell if supply.warning else e.pos)
	if e.item == 0: return upstream(e)
	if e.age + 0.000001 < FactorySim.TRAVEL: return result("运输中")
	return downstream(e, e.item)

func machine_ports(e: Dictionary) -> Array:
	var ports: Array = []
	var connected = sim.multiplier_ports(e)
	for slot in range(2):
		var facing = connected.slots[slot]
		var state = result("缓存 %d" % e.inputs[slot]) if e.inputs[slot] else upstream_input(e, slot)
		if e.inputs[0] * e.inputs[1] > FactorySim.MAX_VALUE:
			state = result("缓存 %d · 两输入的乘积超限" % e.inputs[slot], true, e.pos)
		ports.append({"facing": facing, "text": "输入 %s · %s · %s" % ["A" if slot == 0 else "B", DIRECTIONS[facing] + "口" if facing >= 0 else "未连接端口", state.text], "warning": state.warning})
	for facing in connected.rejected:
		ports.append({"facing": facing, "text": "%s口未接入 · 最多两个输入方向" % DIRECTIONS[facing], "warning": true})
	if connected.outputs.is_empty():
		ports.append({"facing": -1, "text": "输出未连接", "warning": true})
	for facing in connected.outputs:
		var state = downstream(e, e.output if e.output else e.inputs[0] * e.inputs[1], facing)
		ports.append({"facing": facing, "text": "输出 · %s口 · %s" % [DIRECTIONS[facing], state.text], "warning": state.warning})
	return ports

func upstream_input(e: Dictionary, slot: int) -> Dictionary:
	var producers = incoming(e, slot)
	if producers.is_empty(): return result("未连接上游", true, e.pos)
	return upstream(producers[0]) if producers[0].kind in ["belt", "splitter"] else result("已连接上游")
