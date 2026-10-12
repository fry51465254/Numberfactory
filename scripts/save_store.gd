class_name SaveStore
extends RefCounted

const PATH = "user://number_factory_world_v3.json"

static func save_game(sim: FactorySim, path: String = PATH) -> Error:
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(sim.serialize()))
	file.flush()
	file.close()
	return DirAccess.rename_absolute(path + ".tmp", path)

static func load_game(sim: FactorySim, path: String = PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var data = JSON.parse_string(file.get_as_text())
	return data is Dictionary and sim.restore(data)
