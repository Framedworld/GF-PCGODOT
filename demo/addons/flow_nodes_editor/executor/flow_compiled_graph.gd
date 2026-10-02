@tool
class_name FlowCompiledGraph
extends RefCounted

## A FlowGraphResource parsed once for repeated evaluation (Unreal's
## FPCGGraphCompiler output): node descriptors (template, name, node script,
## saved settings, a settings prototype), links, the execution order, finals,
## input and output nodes and the migrated graph data.
##
## FlowCompiledGraph.for_graph(graph) returns the instance cached on the graph
## object (FlowGraphResource._flow_compiled, never saved), so it lives exactly
## as long as the graph and keeps nothing alive that the graph's own data does
## not. It is rebuilt when graph.data changes (a new dictionary, or the same
## dictionary with different content: its hash is compared on every lookup)
## or when the node registry changes (a node directory registered or removed).
## The compiled graph refers back to the graph weakly.
##
## Elements are still created fresh for every run (FlowExecutor.build_state),
## and every run gets its own settings resources, duplicated from the
## prototype, because overrides and $param bindings write into them. The parts
## that need an element (the settings class, traits, connection lists with the
## virtual variable dependencies, the execution order) are filled from the
## first run's elements, so compiling never instantiates extra elements.

## One node of the compiled graph.
class NodeDesc:
	extends RefCounted
	var index : int = 0
	var name : StringName
	var template : String
	var node_script : Script
	var script_path : String
	## The node's saved settings and saved args_port dictionaries.
	var saved_settings : Dictionary = {}
	var saved_args_port : Dictionary = {}
	## Settings with the saved values (and the stabilized missing seed) applied,
	## built once from the first run's element. Never handed to an element. Null
	## until the first run prepared the descriptor.
	var settings_prototype : NodeSettings = null
	## How new_settings() rebuilds the run's settings: the settings script (or
	## null for the base NodeSettings), then exactly the assignments
	## FlowNodeIO.dict_to_resource makes for the saved values, already parsed:
	## [property, value, is_typed_array] in property-list order, then the
	## stabilized random_seed when the saved settings had none (-1 otherwise).
	var settings_script : Script = null
	var assignments : Array = []
	var stable_seed : int = -1
	## Connections where this node is the target / source, virtual variable
	## dependencies included, in the order the evaluator always built them.
	var deps : Array[Dictionary] = []
	var dependants : Array[Dictionary] = []
	## FlowNodeTraits of the template.
	var main_thread : bool = true
	var cacheable : bool = false
	## Settings the execution order depends on: [disabled, inspect_enabled,
	## debug_enabled, variable_name]. A run whose bindings change one of them
	## orders itself instead of using the compiled order.
	var order_signature : Array = []
	## FlowOutputCache settings key of the saved settings (filled on first use).
	var settings_key = null

	## Builds the settings prototype and traits from a fresh element of this
	## node (its settings class comes from the element's metadata).
	func prepare(element : FlowNodeBase) -> void:
		var meta = element.getMeta()
		var settings : NodeSettings
		# Nodes without a settings class (e.g. merge_points) fall back to the
		# base NodeSettings: the evaluator reads settings.disabled and
		# settings.debug_enabled on every node.
		if meta.has("settings") and meta.settings:
			settings = meta.settings.new()
		else:
			settings = NodeSettings.new()
		settings_script = settings.get_script()
		assignments = FlowNodeIO.settings_assignments(saved_settings, settings)
		_apply_assignments(settings)
		FlowNodeIO._stabilize_missing_seed(settings, name, template, saved_settings)
		if "random_seed" in settings and not saved_settings.has("random_seed"):
			stable_seed = int(settings.random_seed)
		var traits := FlowNodeTraits.for_element(element)
		main_thread = traits.main_thread
		cacheable = traits.cacheable
		order_signature = FlowCompiledGraph.order_signature_of(settings)
		settings_prototype = settings

	## Fresh settings for one run: a new settings object with the saved values
	## assigned exactly as dict_to_resource assigns them.
	func new_settings() -> NodeSettings:
		var settings : NodeSettings = settings_script.new() if settings_script != null else NodeSettings.new()
		_apply_assignments(settings)
		if stable_seed >= 0:
			settings.set("random_seed", stable_seed)
		return settings

	func _apply_assignments(settings : Resource) -> void:
		for assignment in assignments:
			if assignment[2]:
				var target_arr = settings.get(assignment[0])
				target_arr.clear()
				for item in assignment[1]:
					target_arr.append(item)
			else:
				settings.set(assignment[0], assignment[1])

## Weak reference to the compiled FlowGraphResource.
var graph_ref : WeakRef
## graph.data at compile time (compared by identity) and its content hash.
var data_ref : Dictionary = {}
var data_hash : int = 0
var registry_version : int = -1
## The migrated graph data the descriptors were built from.
var graph_data : Dictionary = {}
var nodes : Array[NodeDesc] = []
var index_by_name : Dictionary = {}
var links : Array = []
## True once a run filled the connection lists and the execution order.
var ordered : bool = false
## Sequential execution order (indices into `nodes`), as
## FlowNodeIO.build_execution_order computes it for the saved settings.
var execution_order : PackedInt32Array = PackedInt32Array()
## Execution roots (outputs, finals, inspected or debugged nodes).
var finals : PackedInt32Array = PackedInt32Array()
var input_nodes : PackedInt32Array = PackedInt32Array()
var output_nodes : PackedInt32Array = PackedInt32Array()
## Errors found while compiling (unknown template, unloadable script);
## FlowExecutor reports them on every run, as the evaluator always did.
var errors : PackedStringArray = PackedStringArray()

## Hierarchical generation (WP5): node name -> level, the grid size (a power
## of two, int) set by the nearest grid_size marker upstream, the smallest one
## when several markers are upstream, or 0 (FlowWorldGrid.UNBOUNDED) when no
## marker is upstream. A grid_size marker is on its own level (or a smaller
## upstream one). Computed at compile time from the links, the virtual
## set_variable -> get_variable dependencies and the saved cell_size of each
## marker (overrides and $param bindings of cell_size are not seen).
var node_levels : Dictionary = {}
## Grid sizes used by the graph, coarsest first (the Unbounded level excluded).
var grid_sizes : PackedInt32Array = PackedInt32Array()
# level -> plan Dictionary (see level_plan()).
var _level_plans : Dictionary = {}

## Number of compilations since startup (tests and benchmarks read it).
static var compile_count : int = 0

static var _mutex := Mutex.new()

## The compiled form of `graph`, compiled now if missing or stale.
static func for_graph(graph : FlowGraphResource) -> FlowCompiledGraph:
	if graph == null:
		return null
	_mutex.lock()
	var compiled = graph._flow_compiled
	if compiled is FlowCompiledGraph and compiled.is_valid_for(graph):
		_mutex.unlock()
		return compiled
	compiled = compile(graph)
	graph._flow_compiled = compiled
	_mutex.unlock()
	return compiled

## Drops the compiled form of `graph`; the next evaluation compiles it again.
static func invalidate(graph : FlowGraphResource) -> void:
	if graph == null:
		return
	_mutex.lock()
	graph._flow_compiled = null
	_mutex.unlock()

## True while this compilation still describes `graph`.
func is_valid_for(graph : FlowGraphResource) -> bool:
	if graph_ref == null or graph_ref.get_ref() != graph:
		return false
	if registry_version != FlowNodeRegistry.get_version():
		return false
	var data : Dictionary = graph.data
	if not is_same(data, data_ref):
		return false
	return hash(data) == data_hash

## Parses `graph` into descriptors. Does not instantiate elements.
static func compile(graph : FlowGraphResource) -> FlowCompiledGraph:
	var compiled := FlowCompiledGraph.new()
	compile_count += 1
	compiled.graph_ref = weakref(graph)
	compiled.registry_version = FlowNodeRegistry.get_version()
	var raw_data : Dictionary = graph.data
	compiled.data_ref = raw_data
	compiled.data_hash = hash(raw_data)
	# Upgrade old graph data to the current format. Returns the resource's own
	# dictionary when already current; never writes back.
	compiled.graph_data = FlowGraphMigrations.migrate(raw_data)
	for n_data in compiled.graph_data.get("nodes", []):
		var template = n_data.template
		var script_path = FlowNodeRegistry.get_node_script_path(template)
		if script_path.is_empty():
			compiled.errors.append("Failed to resolve node script for template: %s. Make sure its provider addon registered its node directory before evaluation." % template)
			continue
		var node_script = load(script_path)
		if not node_script:
			compiled.errors.append("Failed to load node script for template: %s" % template)
			continue
		var desc := NodeDesc.new()
		desc.index = compiled.nodes.size()
		desc.name = n_data.name
		desc.template = template
		desc.node_script = node_script
		desc.script_path = script_path
		desc.saved_settings = n_data.get("settings", {})
		var saved_ports = n_data.get("args_port", {})
		desc.saved_args_port = saved_ports if saved_ports is Dictionary else {}
		compiled.index_by_name[desc.name] = desc.index
		compiled.nodes.append(desc)
	compiled.links = compiled.graph_data.get("links", [])
	compiled._compute_levels()
	return compiled

# --- Hierarchical levels (WP5) ------------------------------------------------------

const _UNBOUNDED_RANK := 0x7fffffff

## Level of node `node_name` (0 = Unbounded, also for unknown names).
func level_of(node_name) -> int:
	return int(node_levels.get(StringName(node_name), 0))

## True when the graph has at least one grid_size marker.
func has_hierarchy() -> bool:
	return not grid_sizes.is_empty()

## Depth of a level: 0 for Unbounded, 1 for the coarsest grid size, and so on.
func hierarchy_index(level : int) -> int:
	if level <= 0:
		return 0
	var i := grid_sizes.find(level)
	return i + 1 if i >= 0 else 0

## Every level the graph uses, coarsest first, Unbounded (0) included when a
## node is on it.
func levels() -> PackedInt32Array:
	var result := PackedInt32Array()
	for node_name in node_levels:
		if int(node_levels[node_name]) == 0:
			result.append(0)
			break
	result.append_array(grid_sizes)
	return result

## Execution plan of one level, cached:
##   "run"     : Dictionary node name -> true, the nodes executed on this level
##   "preseed" : Array of node names on coarser levels with a link into a node
##               of this level (their outputs are handed in from the coarser
##               cell that contains the cell being generated)
##   "capture" : Array of node names of this level with a link into a node of
##               a finer level (their outputs are kept for finer cells)
func level_plan(level : int) -> Dictionary:
	var plan = _level_plans.get(level)
	if plan != null:
		return plan
	var run := {}
	for node_name in node_levels:
		if int(node_levels[node_name]) == level:
			run[node_name] = true
	var preseed : Array = []
	var capture : Array = []
	for link in links:
		var src := StringName(link.get("from_node", &""))
		var dst := StringName(link.get("to_node", &""))
		if not node_levels.has(src) or not node_levels.has(dst):
			continue
		var src_level := int(node_levels[src])
		var dst_level := int(node_levels[dst])
		if dst_level == level and FlowWorldGrid.is_coarser(src_level, level) and not preseed.has(src):
			preseed.append(src)
		if src_level == level and FlowWorldGrid.is_coarser(level, dst_level) and not capture.has(src):
			capture.append(src)
	plan = { "run": run, "preseed": preseed, "capture": capture }
	_level_plans[level] = plan
	return plan

# Fixed point over the links: a node's rank is the smallest marker size among
# itself and its upstream nodes (Unbounded ranks as +infinity). Monotone
# decreasing, so it terminates on graphs with cycles too.
func _compute_levels() -> void:
	node_levels = {}
	grid_sizes = PackedInt32Array()
	_level_plans = {}
	var rank := {}
	var set_by_variable := {}
	var get_by_variable := {}
	for desc in nodes:
		var r := _UNBOUNDED_RANK
		if desc.template == "grid_size":
			r = FlowWorldGrid.snap_grid_size(float(desc.saved_settings.get("cell_size", 64.0)))
		rank[desc.name] = r
		if desc.template == "set_variable" or desc.template == "get_variable":
			var variable_name := String(desc.saved_settings.get("variable_name", "")).strip_edges()
			if not variable_name.is_empty():
				var bucket : Dictionary = set_by_variable if desc.template == "set_variable" else get_by_variable
				if not bucket.has(variable_name):
					bucket[variable_name] = []
				bucket[variable_name].append(desc.name)
	var edges : Array = []
	for link in links:
		var src := StringName(link.get("from_node", &""))
		var dst := StringName(link.get("to_node", &""))
		if rank.has(src) and rank.has(dst):
			edges.append([src, dst])
	for variable_name in get_by_variable:
		for src in set_by_variable.get(variable_name, []):
			for dst in get_by_variable[variable_name]:
				edges.append([src, dst])
	var changed := true
	while changed:
		changed = false
		for edge in edges:
			var candidate : int = rank[edge[0]]
			if candidate < int(rank[edge[1]]):
				rank[edge[1]] = candidate
				changed = true
	var sizes := {}
	for node_name in rank:
		var r : int = rank[node_name]
		var level := 0 if r == _UNBOUNDED_RANK else r
		node_levels[node_name] = level
		if level > 0:
			sizes[level] = true
	var sorted : Array = sizes.keys()
	sorted.sort()
	sorted.reverse()
	for size in sorted:
		grid_sizes.append(int(size))

## Records the connection lists and execution order computed on one run's
## elements (`descs` and `elements` side by side, `ordered_nodes` in execution
## order). Called by FlowExecutor for a run whose settings match the saved ones.
func store_order(descs : Array, elements : Array, ordered_nodes : Array) -> void:
	for i in range(elements.size()):
		var element : FlowNodeBase = elements[i]
		descs[i].deps = element.deps.duplicate()
		descs[i].dependants = element.dependants.duplicate()
	execution_order = PackedInt32Array()
	for element in ordered_nodes:
		execution_order.append(index_by_name[element.name])
	finals = PackedInt32Array()
	input_nodes = PackedInt32Array()
	output_nodes = PackedInt32Array()
	for i in range(elements.size()):
		var element : FlowNodeBase = elements[i]
		var index : int = descs[i].index
		if FlowNodeIO._is_topo_final_root(element) and not element.settings.disabled:
			finals.append(index)
		if element.node_template == "input" or element.node_template.begins_with("input_"):
			input_nodes.append(index)
		if element.node_template == "output" or element.node_template.begins_with("output_"):
			output_nodes.append(index)
	ordered = true

## Settings values the execution order depends on.
static func order_signature_of(settings : NodeSettings) -> Array:
	if settings == null:
		return []
	var variable_name = settings.get("variable_name") if "variable_name" in settings else null
	return [settings.disabled, settings.inspect_enabled, settings.debug_enabled, variable_name]
