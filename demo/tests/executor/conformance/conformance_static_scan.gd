extends RefCounted

## Static traits-consistency scan (WP9 check 5). A heuristic, for human review:
## it never fails the build.
##
## For every template FlowNodeTraits marks threadable (main_thread false) it
## reads the node script and every local script it extends, strips comments,
## and lists each line that references an API a worker thread must not touch
## (scene tree, evaluation-context state, servers, resource loading, editor)
## or shared mutable state. Each finding says whether it sits under an
## enclosing `if`/`elif` or a same-line conditional that looks like a guard
## (editor-hint, null/validity checks, trace flags); a guarded finding is
## usually harmless, an unguarded one needs a look.

## [label, regex]. REQUIRED are the APIs the WP9 contract names; EXTRA are
## further thread hazards worth a look.
const REQUIRED := [
	[ "get_tree", "\\bget_tree\\s*\\(" ],
	[ "ctx.owner", "\\b_?ctx\\.owner\\b" ],
	[ "ctx.variables", "\\b_?ctx\\.variables\\b" ],
	[ "ctx.runtime_params", "\\b_?ctx\\.runtime_params\\b" ],
	[ "RenderingServer", "\\bRenderingServer\\b" ],
	[ "PhysicsServer3D", "\\bPhysicsServer3D\\b" ],
	[ "ResourceLoader", "\\bResourceLoader\\b" ],
	[ "EditorInterface", "\\bEditorInterface\\b|\\beditor_interface\\s*\\(|\\beditor_edited_scene_root\\s*\\(" ],
	[ "Engine.get_main_loop", "\\bEngine\\.get_main_loop\\b" ],
]
const EXTRA := [
	[ "load()", "(?<![\\w.])load\\s*\\(" ],
	[ "static var", "^\\s*static\\s+var\\b" ],
	[ "global RNG", "(?<![\\w.])(randi|randf|randi_range|randf_range|randfn|randomize|seed)\\s*\\(" ],
	[ "scene node transform", "\\bglobal_(transform|position|basis)\\b" ],
	[ "get_viewport", "\\bget_viewport\\s*\\(" ],
	[ "PhysicsDirectSpaceState", "\\b(direct_space_state|get_world_3d)\\b" ],
	# Output that depends on files or project settings is not a pure function of
	# settings and inputs (cacheability).
	[ "file or project setting", "\\b(FileAccess|DirAccess|ProjectSettings)\\b" ],
	# Settings resources are fresh per run, but resources they reference (Curve,
	# Noise, Gradient, Mesh) are shared by every element built from the graph.
	[ "settings write", "\\bsettings\\.\\w+(\\.\\w+)?\\s*=[^=]|\\bsettings\\.\\w+\\.(set_|add_|clear|append|erase|resize|bake)" ],
]
const GUARD_HINTS := [
	"is_editor_hint", "is_instance_valid", "== null", "!= null", "is_inside_tree",
	"settings.trace", "is_ownerless_preview", "ctx.owner", "ctx and ", "has_meta",
]

static var _regex_cache : Dictionary = {}

## Findings for every threadable template among `templates`: Array of
## { template, script, line, label, required, code, guard } (guard is the
## guarding condition or "").
static func scan(templates : Array) -> Array:
	var findings := []
	for template in templates:
		var script : Script = load(FlowNodeRegistry.DEFAULT_NODE_DIRECTORY.path_join(template + ".gd"))
		if script == null:
			continue
		var element = script.new()
		var traits := FlowNodeTraits.resolve(template, element.meta_node)
		if traits.main_thread:
			continue
		for path in script_chain(script):
			findings.append_array(scan_source(template, path, FileAccess.get_file_as_string(path)))
	return findings

## `script` and every script it extends by path or class, up to node.gd
## (excluded: the base element's own helpers are reviewed separately).
static func script_chain(script : Script) -> Array:
	var chain := []
	var current := script
	while current != null:
		var path := current.resource_path
		if path == "" or path.ends_with("/node.gd") or chain.has(path):
			break
		chain.append(path)
		current = current.get_base_script()
	return chain

## Findings in one source text.
static func scan_source(template : String, path : String, source : String) -> Array:
	var findings := []
	var lines := source.split("\n")
	var code_lines := PackedStringArray()
	for line in lines:
		code_lines.append(strip_comment(line))
	for i in range(code_lines.size()):
		var code := code_lines[i]
		if code.strip_edges() == "":
			continue
		for group in [ [ REQUIRED, true ], [ EXTRA, false ] ]:
			for pattern in group[0]:
				if _regex(pattern[1]).search(code) == null:
					continue
				findings.append({
					"template": template,
					"script": path.get_file(),
					"line": i + 1,
					"label": pattern[0],
					"required": group[1],
					"code": lines[i].strip_edges(),
					"guard": guard_of(code_lines, i),
				})
	return findings

## The enclosing condition of line `index` that looks like a guard, or "".
static func guard_of(code_lines : PackedStringArray, index : int) -> String:
	var line := code_lines[index]
	# Same-line conditional expression: `a if cond else b`, `cond and a`.
	var stripped := line.strip_edges()
	if not stripped.begins_with("if ") and not stripped.begins_with("elif ") and " if " in stripped:
		var cond := stripped.substr(stripped.find(" if ") + 4)
		if _looks_like_guard(cond):
			return cond
	if stripped.begins_with("if ") or stripped.begins_with("elif "):
		if _looks_like_guard(stripped) and _guard_mentions_hit(stripped):
			return stripped
	var indent := _indent_of(line)
	for j in range(index - 1, -1, -1):
		var prev := code_lines[j]
		if prev.strip_edges() == "":
			continue
		var prev_indent := _indent_of(prev)
		if prev_indent >= indent:
			continue
		indent = prev_indent
		var head := prev.strip_edges()
		if head.begins_with("func ") or head.begins_with("static func "):
			break
		if (head.begins_with("if ") or head.begins_with("elif ") or head.begins_with("while ")) and _looks_like_guard(head):
			return head
		if indent == 0:
			break
	return ""

## `line` without its comment and with the contents of string literals blanked
## (quotes kept), so only code is matched.
static func strip_comment(line : String) -> String:
	var out := ""
	var in_string := ""
	var escaped := false
	for i in range(line.length()):
		var c := line[i]
		if in_string != "":
			if escaped:
				escaped = false
			elif c == "\\":
				escaped = true
			elif c == in_string:
				in_string = ""
				out += c
			continue
		if c == "\"" or c == "'":
			in_string = c
		elif c == "#":
			break
		out += c
	return out

static func _looks_like_guard(text : String) -> bool:
	for hint in GUARD_HINTS:
		if hint in text:
			return true
	return false

static func _guard_mentions_hit(text : String) -> bool:
	return "is_editor_hint" in text or "settings.trace" in text

static func _indent_of(line : String) -> int:
	var n := 0
	for c in line:
		if c == "\t":
			n += 4
		elif c == " ":
			n += 1
		else:
			break
	return n

static func _regex(pattern : String) -> RegEx:
	var re = _regex_cache.get(pattern, null)
	if re == null:
		re = RegEx.create_from_string(pattern)
		_regex_cache[pattern] = re
	return re
