extends SceneTree

func _initialize() -> void:
	var destination := OS.get_environment("QA_RELEASE_DIR")
	var license_file := FileAccess.open(destination.path_join("LICENSE-Godot.txt"), FileAccess.WRITE)
	license_file.store_string(Engine.get_license_text())
	var copyrights := FileAccess.open(destination.path_join("COPYRIGHT-Godot.json"), FileAccess.WRITE)
	copyrights.store_string(JSON.stringify({"copyrights":Engine.get_copyright_info(),"licenses":Engine.get_license_info()}, "\t"))
	quit()
