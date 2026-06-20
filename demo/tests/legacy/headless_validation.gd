extends SceneTree

# Headless load-validation for CI. Parses every addon GDScript and loads every
# demo scene resource, failing the process (exit 1) if any returns null — which
# is what Godot does when a script has a parse/type error or a scene references
# a broken script. This is the gate that catches the class of breakage that a
# C++-only build job cannot see (the addon's GDScript never gets compiled there).
#
# Run from the project dir:
#   godot --headless --path . --script res://tests/legacy/headless_validation.gd
#
# Note: this validates that scripts COMPILE and scenes LOAD. Full graph
# evaluation additionally needs the native GDExtension (GDRTree/GDKdTree) built
# for the runner platform; that is covered by the build matrix in ci.yml.

const SCRIPT_ROOTS : Array[String] = [
	"res://addons/flow_nodes_editor",
]
const SCENE_ROOTS : Array[String] = [
	"res://demos",
	"res://scenes",
]

func _init() -> void:
	var failures : PackedStringArray = PackedStringArray()

	var script_count := 0
	for root in SCRIPT_ROOTS:
		for path in _find_files(root, "gd"):
			script_count += 1
			if ResourceLoader.load(path) == null:
				failures.append("script failed to load: %s" % path)
	print("Checked %d GDScript file(s)." % script_count)

	var scene_count := 0
	for root in SCENE_ROOTS:
		for path in _find_files(root, "tscn"):
			scene_count += 1
			if ResourceLoader.load(path) == null:
				failures.append("scene failed to load: %s" % path)
	print("Checked %d scene file(s)." % scene_count)

	if failures.size() > 0:
		for f in failures:
			push_error("VALIDATION: %s" % f)
		printerr("Headless validation FAILED with %d issue(s)." % failures.size())
		quit(1)
		return

	print("Headless validation PASSED (%d scripts, %d scenes)." % [script_count, scene_count])
	quit(0)

func _find_files(root : String, ext : String) -> PackedStringArray:
	var out : PackedStringArray = PackedStringArray()
	var dir := DirAccess.open(root)
	if dir == null:
		# A configured root that does not exist is not an error (e.g. no scenes/).
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := root.path_join(entry)
		if dir.current_is_dir():
			out.append_array(_find_files(full, ext))
		elif entry.get_extension() == ext:
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return out
