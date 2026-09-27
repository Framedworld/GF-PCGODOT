# RuntimeEditorClassReferencesTest.gd
# Exported builds have no editor classes (EditorInterface, EditorPlugin,
# EditorSettings, ...), and a script that merely NAMES one fails to parse there,
# even inside an `if Engine.is_editor_hint()` block. Every script the runtime can
# load must therefore reach the editor through Engine.get_singleton(&"EditorInterface")
# (see FlowNodeBase.editor_interface()). This suite walks the scripts reachable
# from the runtime entry points and fails on any editor class named in code.
class_name RuntimeEditorClassReferencesTest extends GdUnitTestSuite

const ADDON := "res://addons/flow_nodes_editor/"

## Runtime entry points. Every node script and every settings resource is added too.
const RUNTIME_ROOTS := [
	"flow_nodes_io.gd", "node.gd", "flow_data.gd", "flow_node.gd", "connectors_row.gd",
	"node_draw_debug.gd", "flow_i18n.gd", "flow_variable_eval.gd", "flow_node_registry.gd",
	"flow_graph_migrations.gd", "flow_graph_resource.gd", "graph_input_parameter.gd",
	"node_settings.gd",
]

## Scripts that only ever run inside the editor; they may name editor classes but
## must never be reached from a runtime script.
const EDITOR_ONLY_MARKERS := [
	"plugin.gd", "flow_editor", "data_inspector", "search_add_node_popup",
	"inspector_plugin", "graph_input_parameter_inspector", "flow_inspector_property_policy",
	"flow_native_property_rows", "flow_graph_parameters_editor",
]

var _editor_class_re := RegEx.create_from_string("\\bEditor[A-Z]\\w*")
var _path_re := RegEx.create_from_string("res://addons/flow_nodes_editor/[\\w/\\.]+\\.(?:gd|tscn)")
var _rel_load_re := RegEx.create_from_string("(?:preload|load)\\(\\s*\"([^\":]+\\.(?:gd|tscn))\"")
var _word_re := RegEx.create_from_string("\\b[A-Z]\\w+\\b")


# Removes comments and replaces string literals by "" (keeping line structure), so
# only code remains: `&"EditorInterface"` and `# EditorInterface ...` are not code.
static func strip_comments_and_strings(src: String) -> String:
	var out := ""
	var i := 0
	var n := src.length()
	while i < n:
		var ch := src[i]
		if ch == "#":
			while i < n and src[i] != "\n":
				i += 1
			continue
		if ch == "\"" or ch == "'":
			var triple := src.substr(i, 3) == ch + ch + ch
			var close := ch + ch + ch if triple else ch
			i += close.length()
			while i < n:
				if src[i] == "\\":
					i += 2
					continue
				if src.substr(i, close.length()) == close:
					i += close.length()
					break
				if src[i] == "\n":
					out += "\n"
					if not triple:
						i += 1
						break
				i += 1
			out += "\"\""
			continue
		out += ch
		i += 1
	return out


## [line_number, line] for every code line of `src` naming an editor class.
func editor_class_lines(src: String) -> Array:
	var hits := []
	var lines := strip_comments_and_strings(src).split("\n")
	for idx in range(lines.size()):
		if _editor_class_re.search(lines[idx]) != null:
			hits.append([idx + 1, lines[idx].strip_edges()])
	return hits


func _class_paths() -> Dictionary:
	var by_name := {}
	for entry in ProjectSettings.get_global_class_list():
		var path := str(entry.path)
		if path.begins_with(ADDON):
			by_name[str(entry["class"])] = path
	return by_name


func _addon_scripts(dir_path: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for d in dir.get_directories():
		if d != "native" and d != "bin":
			_addon_scripts(dir_path.path_join(d), out)


func _references(path: String, class_paths: Dictionary) -> Array:
	var raw := FileAccess.get_file_as_string(path)
	var found := {}
	if path.ends_with(".tscn"):
		for m in _path_re.search_all(raw):
			found[m.get_string()] = true
		return found.keys()
	# Paths live in string literals, so scan the comment-free source for those...
	var no_comments := ""
	for line in raw.split("\n"):
		var hash_at := line.find("#")
		no_comments += (line if hash_at < 0 else line.substr(0, hash_at)) + "\n"
	for m in _path_re.search_all(no_comments):
		found[m.get_string()] = true
	for m in _rel_load_re.search_all(no_comments):
		found[path.get_base_dir().path_join(m.get_string(1)).simplify_path()] = true
	# ...and the string-free code for class_name references.
	for m in _word_re.search_all(strip_comments_and_strings(raw)):
		var target = class_paths.get(m.get_string(), null)
		if target != null and target != path:
			found[target] = true
	return found.keys()


## Runtime-reachable scripts (and scenes) -> the file that first reached them.
func runtime_reachable() -> Dictionary:
	var class_paths := _class_paths()
	var all_scripts := []
	_addon_scripts(ADDON.trim_suffix("/"), all_scripts)
	var queue := []
	for r in RUNTIME_ROOTS:
		queue.append([ADDON + r, "<root>"])
	for p in all_scripts:
		if p.begins_with(ADDON + "nodes/") or p.ends_with("_settings.gd"):
			queue.append([p, "<root>"])
	var seen := {}
	while not queue.is_empty():
		var item = queue.pop_back()
		if seen.has(item[0]) or not FileAccess.file_exists(item[0]):
			continue
		seen[item[0]] = item[1]
		for ref in _references(item[0], class_paths):
			if not seen.has(ref):
				queue.append([ref, item[0]])
	return seen


func _is_editor_only(path: String) -> bool:
	for marker in EDITOR_ONLY_MARKERS:
		if path.get_file().begins_with(marker) or path.get_file().contains(marker):
			return true
	return false


func test_runtime_reachable_set_covers_the_runtime() -> void:
	var reachable := runtime_reachable()
	for r in RUNTIME_ROOTS:
		assert_bool(reachable.has(ADDON + r)).override_failure_message("root %s missing" % r).is_true()
	for p in [ "nodes/spawn_scenes.gd", "nodes/apply_on_actor.gd", "nodes/expression_settings.gd", "connectors_row.tscn" ]:
		assert_bool(reachable.has(ADDON + p)).override_failure_message("%s not reached" % p).is_true()
	assert_int(reachable.size()).is_greater(100)


func test_runtime_never_reaches_editor_only_scripts() -> void:
	var offenders := []
	var reachable := runtime_reachable()
	for p in reachable:
		if _is_editor_only(p):
			offenders.append("%s (reached from %s)" % [p, reachable[p]])
	assert_array(offenders).override_failure_message(
		"editor-only scripts reachable from runtime scripts:\n  " + "\n  ".join(offenders)).is_empty()


func test_runtime_scripts_name_no_editor_class() -> void:
	# EditorInterface, EditorPlugin, EditorInspectorPlugin, EditorUndoRedoManager,
	# EditorFileSystem, EditorSettings, ... none may appear as code in a script
	# the runtime can load; use FlowNodeBase.editor_interface() / Engine.get_singleton.
	var offenders := []
	for p in runtime_reachable():
		if not p.ends_with(".gd"):
			continue
		for hit in editor_class_lines(FileAccess.get_file_as_string(p)):
			offenders.append("%s:%d: %s" % [p, hit[0], hit[1]])
	assert_array(offenders).override_failure_message(
		"runtime-reachable scripts name editor-only classes:\n  " + "\n  ".join(offenders)).is_empty()


func test_checker_flags_code_but_not_comments_or_strings() -> void:
	var src := "\n".join([
		"if Engine.is_editor_hint():",
		"\tEditorInterface.mark_scene_as_unsaved()",          # 2: flagged
		"\tvar ei = Engine.get_singleton(&\"EditorInterface\")", # string: fine
		"# EditorInterface.get_edited_scene_root() in a comment",
		"var s := \"\"\"EditorPlugin",
		"EditorSettings\"\"\"",                                # triple-quoted: fine
		"func f(p: EditorProperty) -> void: pass",              # 7: flagged
		"var font = get_theme_font(\"bold\", \"EditorFonts\")",  # string: fine
		"var x = EditorInterface(",                             # 9: flagged
	])
	var lines := editor_class_lines(src).map(func(h): return h[0])
	assert_array(lines).is_equal([2, 7, 9])


func test_editor_helpers_are_inert_outside_the_editor() -> void:
	# Headless test runs are not the editor: the helpers must answer null / no-op
	# rather than touching EditorInterface.
	assert_bool(Engine.is_editor_hint()).is_false()
	assert_object(FlowNodeBase.editor_interface()).is_null()
	assert_object(FlowNodeBase.editor_edited_scene_root()).is_null()
	FlowNodeBase.editor_mark_scene_unsaved()
