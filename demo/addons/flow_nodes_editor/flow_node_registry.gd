@tool
extends Object
class_name FlowNodeRegistry

## Resolves node templates ("grid", "my_game_room_loop", ...) to node scripts.
##
## Templates are looked up, in order, in:
##   1. DEFAULT_NODE_DIRECTORY (the stock nodes shipped with the addon),
##   2. the directories listed in the project setting `flow_nodes/node_directories`,
##   3. directories added at runtime with register_node_directory().
## The first directory containing `<template>.gd` wins, so projects cannot shadow a
## stock node by accident.
##
## Renamed or removed templates can be kept loadable through `template_aliases`
## ("old_template" -> "new_template"); see docs/DEPRECATIONS.md.

const DEFAULT_NODE_DIRECTORY := "res://addons/flow_nodes_editor/nodes"

## Project setting holding extra node directories (PackedStringArray of res:// paths).
const SETTING_NODE_DIRECTORIES := "flow_nodes/node_directories"

## Old template name -> new template name. Consulted by get_node_script_path when the
## requested template has no script of its own; the first use of each alias logs a
## deprecation warning. Stock aliases live in STOCK_TEMPLATE_ALIASES; projects may add
## their own at startup (FlowNodeRegistry.template_aliases["old"] = "new").
static var template_aliases : Dictionary = {}

## Aliases shipped with the addon. Empty until a stock template is renamed.
const STOCK_TEMPLATE_ALIASES := {}

static var _extra_node_directories: Array[String] = []
static var _settings_node_directories: Array[String] = []
static var _settings_raw := PackedStringArray()
static var _settings_loaded := false
static var _warned_aliases : Dictionary = {}
static var _version := 0

## Registers `flow_nodes/node_directories` with the editor so it shows in
## Project Settings with a directory-list hint. Safe to call repeatedly; the value is
## only written when missing, and a value equal to the default is not saved to
## project.godot.
static func ensure_project_setting() -> void:
	if not ProjectSettings.has_setting(SETTING_NODE_DIRECTORIES):
		ProjectSettings.set_setting(SETTING_NODE_DIRECTORIES, PackedStringArray())
	ProjectSettings.set_initial_value(SETTING_NODE_DIRECTORIES, PackedStringArray())
	ProjectSettings.set_as_basic(SETTING_NODE_DIRECTORIES, true)
	ProjectSettings.add_property_info({
		"name": SETTING_NODE_DIRECTORIES,
		"type": TYPE_PACKED_STRING_ARRAY,
		"hint": PROPERTY_HINT_TYPE_STRING,
		"hint_string": "%d/%d:" % [TYPE_STRING, PROPERTY_HINT_DIR],
	})

static func register_node_directory(directory_path: String) -> void:
	var normalized := _normalize_directory_path(directory_path)
	if normalized.is_empty():
		return
	if normalized == DEFAULT_NODE_DIRECTORY:
		return
	if normalized in _extra_node_directories:
		return
	_extra_node_directories.append(normalized)
	_version += 1

static func unregister_node_directory(directory_path: String) -> void:
	var normalized := _normalize_directory_path(directory_path)
	var index := _extra_node_directories.find(normalized)
	if index == -1:
		return
	_extra_node_directories.remove_at(index)
	_version += 1

static func get_node_directories() -> Array[String]:
	_sync_project_setting()
	var directories: Array[String] = [DEFAULT_NODE_DIRECTORY]
	for directory_path in _settings_node_directories:
		if not directory_path in directories:
			directories.append(directory_path)
	for directory_path in _extra_node_directories:
		if not directory_path in directories:
			directories.append(directory_path)
	return directories

static func get_node_script_path(template_name: String) -> String:
	if template_name.begins_with("input_"):
		return DEFAULT_NODE_DIRECTORY + "/input.gd"
	if template_name.begins_with("output_"):
		return DEFAULT_NODE_DIRECTORY + "/output.gd"

	var script_path := _find_template_script(template_name)
	if not script_path.is_empty():
		return script_path

	var alias_target := alias_for_missing_template(template_name)
	if not alias_target.is_empty():
		return _find_template_script(alias_target)
	return ""

static func has_template_aliases() -> bool:
	return not template_aliases.is_empty() or not STOCK_TEMPLATE_ALIASES.is_empty()

## When `template_name` has no script of its own but is aliased to a template that
## does, returns that template (warning once per old name); otherwise "".
## Aliases only apply to missing templates, so a project that still ships a script
## under the old name keeps using it.
static func alias_for_missing_template(template_name: String) -> String:
	if template_name.is_empty() or not has_template_aliases():
		return ""
	if template_name.begins_with("input_") or template_name.begins_with("output_"):
		return ""
	var alias_target := resolve_template_alias(template_name)
	if alias_target == template_name:
		return ""
	if not _find_template_script(template_name).is_empty():
		return ""
	if _find_template_script(alias_target).is_empty():
		return ""
	if not _warned_aliases.has(template_name):
		_warned_aliases[template_name] = true
		push_warning("Flow node template '%s' is deprecated; using '%s'. Re-save the graph to update it. See docs/DEPRECATIONS.md." % [template_name, alias_target])
	return alias_target

## Follows template_aliases (then STOCK_TEMPLATE_ALIASES) until a template with no
## further alias is reached. Returns `template_name` unchanged when it has no alias.
static func resolve_template_alias(template_name: String) -> String:
	var current := template_name
	var seen := {}
	while not seen.has(current):
		seen[current] = true
		var next = template_aliases.get(current, STOCK_TEMPLATE_ALIASES.get(current, null))
		if next == null or String(next).is_empty():
			break
		current = String(next)
	return current

## Clears the one-time alias warnings (tests use this to observe the warning again).
static func reset_alias_warnings() -> void:
	_warned_aliases.clear()

static func get_version() -> int:
	_sync_project_setting()
	return _version

static func _find_template_script(template_name: String) -> String:
	if template_name.is_empty():
		return ""
	for directory_path in get_node_directories():
		var script_path := "%s/%s.gd" % [directory_path, template_name]
		if ResourceLoader.exists(script_path, "Script"):
			return script_path
	return ""

## Re-reads the project setting when its value changed (Project Settings edit, a test,
## or a game changing it at startup) and bumps the registry version so the editor
## rescans. Cheap when nothing changed: one get_setting and one array compare.
static func _sync_project_setting() -> void:
	var raw = ProjectSettings.get_setting(SETTING_NODE_DIRECTORIES, PackedStringArray())
	var packed := PackedStringArray()
	if raw is PackedStringArray or raw is Array:
		for entry in raw:
			packed.append(str(entry))
	elif raw is String and not String(raw).strip_edges().is_empty():
		packed = String(raw).split(",", false)
	if _settings_loaded and packed == _settings_raw:
		return
	_settings_loaded = true
	_settings_raw = packed
	var normalized: Array[String] = []
	for entry in packed:
		var directory_path := _normalize_directory_path(entry)
		if directory_path.is_empty() or directory_path == DEFAULT_NODE_DIRECTORY:
			continue
		if directory_path in normalized:
			continue
		normalized.append(directory_path)
	if normalized != _settings_node_directories:
		_settings_node_directories = normalized
		_version += 1

static func _normalize_directory_path(directory_path: String) -> String:
	var normalized := directory_path.strip_edges().replace("\\", "/")
	while normalized.ends_with("/"):
		normalized = normalized.trim_suffix("/")
	return normalized
