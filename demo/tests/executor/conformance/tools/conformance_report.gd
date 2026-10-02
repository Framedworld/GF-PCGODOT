extends SceneTree

## Prints the node conformance report (WP9) as Markdown: the per-template
## result table, every failure, every skip and the static-scan findings.
## Not a test (the folder is .gdignore'd). From demo/:
##   godot --headless --path . -s res://tests/executor/conformance/tools/conformance_report.gd
## Optional user arguments after `--`:
##   --only=<template>[,<template>...]   run only these templates
##   --out=<path>                        also write the Markdown to this file
##   --include-known-bugs                also run the cases listed as known bugs

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")

func _initialize() -> void:
	# Run once the tree is live, so the harness's owner scene is inside it.
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var Report = load("res://tests/executor/conformance/conformance_report.gd")
	var Harness = load("res://tests/executor/conformance/conformance_harness.gd")
	var only := PackedStringArray()
	var out_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr(7).split(",", false)
		elif arg.begins_with("--out="):
			out_path = arg.substr(6)
		elif arg == "--include-known-bugs":
			Harness.include_known_bugs = true
	var markdown : String = Report.build(only)
	print(markdown)
	if out_path != "":
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		if file != null:
			file.store_string(markdown)
			file.close()
	quit()
