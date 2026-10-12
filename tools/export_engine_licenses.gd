extends SceneTree

func _initialize():
	var directory = "res://build/web/licenses"
	DirAccess.make_dir_recursive_absolute(directory)
	var license_file = FileAccess.open(directory + "/Godot-LICENSE.txt", FileAccess.WRITE)
	if license_file == null:
		push_error("Cannot write engine license")
		quit(1)
		return
	license_file.store_string(Engine.get_license_text())
	license_file.close()
	var third_party = FileAccess.open(directory + "/Godot-third-party.json", FileAccess.WRITE)
	if third_party == null:
		push_error("Cannot write third-party notices")
		quit(1)
		return
	third_party.store_string(JSON.stringify({"copyright": Engine.get_copyright_info(), "licenses": Engine.get_license_info()}, "\t"))
	third_party.close()
	quit()
