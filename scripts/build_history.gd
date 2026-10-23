class_name BuildHistory
extends RefCounted

const LIMIT = 100
var sim: FactorySim
var undo_stack: Array = []
var redo_stack: Array = []
var active = false
var pending: Dictionary = {}
var title = ""
var revision = 0

func attach(factory: FactorySim):
	if sim == factory: return
	sim = factory
	clear()

func clear():
	undo_stack.clear()
	redo_stack.clear()
	pending.clear()
	active = false
	revision += 1

func begin(factory: FactorySim, label: String):
	attach(factory)
	if active: return
	active = true
	pending.clear()
	title = label

func watch(p: Vector2i):
	if not active: return
	var ground = sim.at(p)
	var id = BuildLayout.identity(ground) if not ground.is_empty() and ground.kind in BuildLayout.FIELDS else FactorySim.key(p)
	for candidate in [id, FactorySim.key(p) + ":under"]:
		if not pending.has(candidate): pending[candidate] = BuildLayout.config(sim.entities.get(candidate, {}))

func commit():
	if not active: return
	var before: Dictionary = {}
	var after: Dictionary = {}
	for id in pending:
		var current = BuildLayout.config(sim.entities.get(id, {}))
		if not BuildLayout.matches(current, pending[id]):
			before[id] = pending[id]
			after[id] = current
	active = false
	pending.clear()
	if before.is_empty(): return
	undo_stack.append({"before": before, "after": after, "title": title})
	if undo_stack.size() > LIMIT: undo_stack.pop_front()
	redo_stack.clear()
	revision += 1

func undo() -> String:
	commit()
	if undo_stack.is_empty(): return "没有可撤销的建造操作"
	var action = undo_stack[-1]
	var reason = BuildLayout.apply(sim, action.after, action.before)
	if not reason.is_empty(): return reason
	undo_stack.pop_back()
	redo_stack.append(action)
	revision += 1
	return ""

func redo() -> String:
	commit()
	if redo_stack.is_empty(): return "没有可重做的建造操作"
	var action = redo_stack[-1]
	var reason = BuildLayout.apply(sim, action.before, action.after)
	if not reason.is_empty(): return reason
	redo_stack.pop_back()
	undo_stack.append(action)
	revision += 1
	return ""
