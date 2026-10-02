extends RefCounted

## Node conformance harness (WP9): drives one node element the way FlowExecutor
## does and checks it against the executor's contracts.
##
## For every template and every fixture case (conformance_fixtures.gd, with
## per-template adjustments from conformance_overrides.gd) it runs the element
## through FlowExecutor.execute_node, the evaluator's own per-node entry point,
## with its inputs wired from synthetic source elements, and checks:
##
##   1. mutation     the content_hash of every input Data is unchanged after
##                   every execution (no in-place writes into inputs);
##   2. determinism  two executions on fresh, equal inputs give equal outputs,
##                   errors included;
##   3. thread       for templates FlowNodeTraits marks threadable, execution
##                   on WorkerThreadPool equals main-thread execution; the
##                   worker run is WORKER_BATCH elements at once in one group
##                   task (a threaded-mode batch), so races on shared state in
##                   the node script surface too;
##   4. cache        for templates marked cacheable, a cold run through
##                   FlowOutputCache and a warm run (a cache hit) both equal a
##                   fresh uncached run, errors included.
##
## Outputs are compared through outputs_fingerprint(): every bulk and port, each
## Data digested by content (streams, tags, per-data attributes, kind, shape),
## plus the element's error messages in order. Unsaved resources inside streams
## are digested by their stored properties, not their identity, so a node that
## builds an equal resource on every run is still deterministic.
##
## Elements are RefCounted: the harness drops them and never calls free().

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const Fixtures = preload("res://tests/executor/conformance/conformance_fixtures.gd")
const Overrides = preload("res://tests/executor/conformance/conformance_overrides.gd")

const NODE_NAME := &"conformance_node"
const SOURCE_PREFIX := "conformance_src_"
## Graph seed of every harness evaluation (non-zero, so derive_seed is exercised).
const CTX_SEED := 1337

const CHECKS := [ "mutation", "determinism", "thread", "cache" ]

## Run the cases an override row lists under known_bugs too (report tool).
static var include_known_bugs : bool = false

## Collects the errors raised while the harness executes elements, from any
## thread: SCRIPT ERRORs (a crash inside a node script: a genuine bug) and
## other errors printed outside setError (setError copies are deferred and
## dropped by the harness, so whatever reaches here bypassed the node's error
## log and FlowNodeIO.last_errors).
class CaptureLogger extends Logger:
	var _mutex := Mutex.new()
	var _entries : Array = []

	func _log_error(_function : String, file : String, line : int, code : String, rationale : String, _editor_notify : bool, error_type : int, script_backtraces : Array[ScriptBacktrace]) -> void:
		# Warnings are counted (they reach every Logger too) but never listed.
		var warning := error_type != ERROR_TYPE_SCRIPT and error_type != ERROR_TYPE_ERROR
		var where := "%s:%d" % [ file, line ]
		for backtrace in script_backtraces:
			if backtrace != null and backtrace.get_frame_count() > 0:
				where = "%s:%d" % [ backtrace.get_frame_file(0), backtrace.get_frame_line(0) ]
				break
		var message := code if rationale == "" else "%s %s" % [ code, rationale ]
		_mutex.lock()
		_entries.append({ "script": error_type == ERROR_TYPE_SCRIPT, "warning": warning, "where": where, "message": message.strip_edges() })
		_mutex.unlock()

	func _log_message(_message : String, _error : bool) -> void:
		pass

	func count() -> int:
		_mutex.lock()
		var n := _entries.size()
		_mutex.unlock()
		return n

	## Distinct "where: message" strings logged since entry `from`, script
	## errors or the other errors.
	func unique_since(from : int, script_errors : bool) -> Array:
		var seen := []
		_mutex.lock()
		for i in range(from, _entries.size()):
			var entry : Dictionary = _entries[i]
			if entry.warning or entry.script != script_errors:
				continue
			var text := "%s: %s" % [ String(entry.where).replace("res://addons/flow_nodes_editor/", ""), entry.message ]
			if not seen.has(text):
				seen.append(text)
		_mutex.unlock()
		return seen

# --- Templates --------------------------------------------------------------------

## Every stock template: the scripts in FlowNodeRegistry.DEFAULT_NODE_DIRECTORY
## whose instance is a FlowNodeBase, sorted by name.
static func stock_templates() -> Array:
	var templates := []
	var dir := DirAccess.open(FlowNodeRegistry.DEFAULT_NODE_DIRECTORY)
	for file_name in dir.get_files():
		if not file_name.ends_with(".gd") or file_name.ends_with("_settings.gd"):
			continue
		var script : Script = load(FlowNodeRegistry.DEFAULT_NODE_DIRECTORY.path_join(file_name))
		if script == null or not script.can_instantiate():
			continue
		var instance = script.new()
		if instance is FlowNodeBase:
			templates.append(file_name.get_basename())
		elif instance is Object and not (instance is RefCounted):
			instance.free()
	templates.sort()
	return templates

static func script_for(template : String) -> Script:
	return load(FlowNodeRegistry.DEFAULT_NODE_DIRECTORY.path_join(template + ".gd"))

## Where a template's effective traits come from: "meta" when its meta_node
## declares "pure" or "main_thread" (those win over the table), "table" when
## FlowNodeTraits.TABLE has a row, else "default".
static func traits_source(template : String, meta : Dictionary) -> String:
	if meta.has("pure") or meta.has("main_thread"):
		return "meta"
	if FlowNodeTraits.TABLE.has(template):
		return "table"
	return "default"

# --- One template -------------------------------------------------------------------

## Runs every check for `template` and returns its result record:
##   template, script_path, main_thread, cacheable, traits_source, table_row,
##   skip (reason or ""), owner_mode, cases (Array of case records), checks
##   ({ check -> { status: "pass" | "fail" | "skip", detail } }), worked
##   (cases that produced output without error), ms.
## `script` and `override` replace the stock script and the override row
## (the harness self-test drives fake nodes this way).
static func check_template(template : String, script : Script = null, override = null) -> Dictionary:
	var start_us := Time.get_ticks_usec()
	if script == null:
		script = script_for(template)
	if override == null:
		override = Overrides.for_template(template)
	var probe : FlowNodeBase = script.new()
	var meta : Dictionary = probe.meta_node
	var traits := FlowNodeTraits.resolve(template, meta)
	var result := {
		"template": template,
		"script_path": script.resource_path,
		"main_thread": traits.main_thread,
		"cacheable": traits.cacheable,
		"traits_source": traits_source(template, meta),
		"table_row": FlowNodeTraits.TABLE.get(template, null),
		"skip": String(override.get("skip", "")),
		"owner_mode": owner_mode(override),
		"note": String(override.get("note", "")),
		"cases": [],
		"checks": {},
		"worked": 0,
		"cache_hits": 0,
		"excluded": [],
		"ms": 0.0,
	}
	if result.skip != "":
		for check in CHECKS:
			result.checks[check] = { "status": "skip", "detail": result.skip }
		return result

	var spec := {
		"template": template,
		"script": script,
		"override": override,
		"settings": override.get("settings", {}),
		"num_ins": 0,
		"graph": FlowGraphResource.new(),
		"owner": _make_owner(result.owner_mode),
		"settings_key": null,
	}
	# The default settings pass, then one pass per settings variant (a mode the
	# defaults do not reach); variant cases are labelled "<case>@<variant>".
	var passes := [ [ "", spec.settings ] ]
	var variants : Dictionary = override.get("variants", {})
	for variant in variants:
		var merged : Dictionary = spec.settings.duplicate()
		merged.merge(variants[variant], true)
		passes.append([ variant, merged ])

	var known_bugs : Dictionary = override.get("known_bugs", {})
	var logger := CaptureLogger.new()
	OS.add_logger(logger)
	for settings_pass in passes:
		spec.settings = settings_pass[1]
		# Port count of the configured element (subgraph and loop derive their
		# ports from the graph in their settings).
		var configured := _make_element(spec)
		spec.num_ins = (configured.getMeta().get("ins", []) as Array).size()
		spec.settings_key = null
		if traits.cacheable:
			# FlowExecutor.build_state computes the settings part of the cache key
			# once per compiled-graph node and reuses it for every later run.
			spec.settings_key = FlowOutputCache.settings_values(configured.settings)
		for case in cases_for(spec.num_ins, override):
			var label := case_label(case)
			if settings_pass[0] != "":
				label += "@" + settings_pass[0]
			if known_bugs.has(label) and not include_known_bugs:
				result.excluded.append("%s (known bug: %s)" % [ label, known_bugs[label] ])
				continue
			var first_entry := logger.count()
			var record := _check_case(spec, case, traits, logger)
			record.case = label
			record.script_errors = logger.unique_since(first_entry, true)
			record.console_errors = logger.unique_since(first_entry, false)
			result.cases.append(record)
	OS.remove_logger(logger)

	if spec.owner != null and is_instance_valid(spec.owner):
		spec.owner.get_parent().remove_child(spec.owner)
		spec.owner.free()

	for case in result.cases:
		if case.worked:
			result.worked += 1
		if case.cache_hit:
			result.cache_hits += 1
	for check in CHECKS:
		result.checks[check] = _aggregate(result, check, traits, override)
	result.ms = float(Time.get_ticks_usec() - start_us) / 1000.0
	return result

## The fixture cases of a template with `num_ins` declared inputs, as
## [primary, secondary] pairs ("" when the template has a single input).
static func cases_for(num_ins : int, override : Dictionary) -> Array:
	if num_ins == 0:
		return [ [ Fixtures.NO_INPUT, "" ] ]
	var primaries : Array = override.get("primary", Fixtures.PRIMARY)
	var cases := []
	if num_ins == 1:
		for p in primaries:
			cases.append([ p, "" ])
	else:
		var secondaries : Array = override.get("secondary", Fixtures.SECONDARY)
		for p in primaries:
			cases.append([ p, secondaries[0] ])
		for i in range(1, secondaries.size()):
			cases.append([ override.get("secondary_primary", "points"), secondaries[i] ])
	for extra in override.get("extra_cases", []):
		cases.append(extra)
	return cases

static func case_label(case : Array) -> String:
	return case[0] if case[1] == "" else "%s+%s" % [ case[0], case[1] ]

static func owner_mode(override : Dictionary) -> String:
	return String(override.get("owner", "scene"))

# Every execution of one case, compared.
static func _check_case(spec : Dictionary, case : Array, traits : Dictionary, logger : CaptureLogger = null) -> Dictionary:
	var first_entry := logger.count() if logger != null else 0
	var record := {
		"case": case_label(case),
		"errors": [],
		"worked": false,
		"summary": "",
		"mutation": "",
		"determinism": "",
		"thread": "skip",
		"concurrent": false,
		"cache": "skip",
		"cache_hit": false,
	}
	var first := execute(spec, case, "main")
	if first.has("fatal"):
		record.mutation = first.fatal
		record.determinism = first.fatal
		return record
	record.errors = first.errors
	record.summary = first.summary
	record.worked = first.worked
	var mutations := [ first.mutation ]

	var second := execute(spec, case, "main")
	mutations.append(second.mutation)
	if second.fingerprint != first.fingerprint:
		record.determinism = "run 1: %s / run 2: %s" % [ first.summary, second.summary ]

	if not traits.main_thread:
		record.thread = ""
		# A node that prints errors outside setError (a FlowData helper's
		# push_error, an engine error) would print them from several pool threads
		# at once in a batch. Script Loggers are called on the raising thread, and
		# a non-thread-safe one (a test harness's) crashes the process on
		# concurrent calls, so such cases run on one worker at a time. The main
		# runs above predict it: execution is deterministic.
		record.concurrent = logger == null or logger.count() == first_entry
		var workers := execute_worker_batch(spec, case, WORKER_BATCH if record.concurrent else 1)
		for k in range(workers.size()):
			var worker : Dictionary = workers[k]
			if worker.has("fatal"):
				record.thread = worker.fatal
				break
			mutations.append(worker.mutation)
			if worker.fingerprint != first.fingerprint:
				record.thread = "main: %s / worker %d of %d: %s" % [ first.summary, k + 1, workers.size(), worker.summary ]
				break

	if traits.cacheable:
		FlowOutputCache.clear()
		var cold := execute(spec, case, "cache")
		var hits_before := FlowOutputCache.hits
		var warm := execute(spec, case, "cache")
		record.cache_hit = FlowOutputCache.hits > hits_before
		FlowOutputCache.clear()
		mutations.append(cold.mutation)
		mutations.append(warm.mutation)
		record.cache = ""
		if cold.fingerprint != first.fingerprint:
			record.cache = "uncached: %s / cold: %s" % [ first.summary, cold.summary ]
		elif warm.fingerprint != first.fingerprint:
			record.cache = "uncached: %s / warm%s: %s" % [ first.summary, "" if record.cache_hit else " (miss)", warm.summary ]

	for mutation in mutations:
		if mutation != "":
			record.mutation = mutation
			break
	return record

static func _aggregate(result : Dictionary, check : String, traits : Dictionary, override : Dictionary) -> Dictionary:
	if check == "thread" and traits.main_thread:
		return { "status": "skip", "detail": "main-thread template" }
	if check == "cache" and not traits.cacheable:
		return { "status": "skip", "detail": "not cacheable" }
	var failures := []
	for case in result.cases:
		var value : String = case[check]
		if value != "" and value != "skip":
			failures.append("%s: %s" % [ case.case, value ])
	if failures.is_empty():
		var detail := ""
		if check == "cache" and result.cache_hits < result.cases.size():
			detail = "%d of %d warm runs hit" % [ result.cache_hits, result.cases.size() ]
		return { "status": "pass", "detail": detail }
	return { "status": "fail", "detail": "; ".join(failures) }

# --- One execution --------------------------------------------------------------------

## Elements a worker run executes at once on the pool (like one threaded-mode
## batch), so shared mutable state inside a node shows up as a race.
const WORKER_BATCH := 3

## Executes the template once on fresh fixtures. `mode` is "main" (calling
## thread), "worker" (WORKER_BATCH elements, each on fresh inputs, as one
## WorkerThreadPool group task while the calling thread waits; see
## execute_worker_batch) or "cache" (main thread with FlowOutputCache on).
## Returns
##   fingerprint  outputs_fingerprint() of the generated bulks and errors
##   summary      human-readable digest of the same
##   errors       the element's error messages, in order
##   worked       true when it produced a non-empty output and no error
##   mutation     "" or which input changed
## or { "fatal": reason } when the fixtures cannot be built.
static func execute(spec : Dictionary, case : Array, mode : String) -> Dictionary:
	if mode == "worker":
		var runs := execute_worker_batch(spec, case, 1)
		return runs[0]
	var run := _prepare(spec, case, mode)
	if run.has("fatal"):
		return run
	FlowExecutor.execute_node(run.element, run.instances, spec.graph, run.ctx)
	return _collect(run, case, mode)

## Runs `count` fresh executions of the case concurrently on WorkerThreadPool
## (one group task, high priority, like FlowExecutor's threaded batches, with
## the same main-thread prewarm of shared Curve/Gradient settings resources)
## and returns their execute() records.
static func execute_worker_batch(spec : Dictionary, case : Array, count : int) -> Array:
	var runs := []
	for i in range(count):
		var run := _prepare(spec, case, "worker")
		if run.has("fatal"):
			return [ run ]
		FlowExecutor._prewarm_shared_resources(run.element)
		runs.append(run)
	var graph : FlowGraphResource = spec.graph
	var task := WorkerThreadPool.add_group_task(func(k : int):
		var run : Dictionary = runs[k]
		FlowExecutor.execute_node(run.element, run.instances, graph, run.ctx), count, -1, true, "conformance")
	WorkerThreadPool.wait_for_group_task_completion(task)
	var records := []
	for run in runs:
		records.append(_collect(run, case, "worker"))
	return records

# Fresh inputs, element, source elements and context for one execution.
static func _prepare(spec : Dictionary, case : Array, mode : String) -> Dictionary:
	var inputs := build_inputs(spec, case)
	if inputs.has(null):
		return { "fatal": "fixture %s could not be built (scene fixtures need the scene owner)" % [ case ] }
	var before := []
	for data in inputs:
		before.append([ data.content_hash(), data_digest(data) ])

	var element := _make_element(spec)
	var instances := {}
	var deps : Array[Dictionary] = []
	for port in range(inputs.size()):
		var source := FlowNodeBase.new()
		source.name = StringName(SOURCE_PREFIX + str(port))
		source.node_template = "conformance_source"
		source.generated_bulks = [ [ inputs[port] ] ]
		source.num_generated_bulks = 1
		instances[source.name] = source
		var conn := { "from_node": source.name, "from_port": 0, "to_node": NODE_NAME, "to_port": port }
		deps.append(conn)
		source.dependants.append(conn)
	element.deps = deps
	instances[NODE_NAME] = element
	if mode == "cache" and spec.settings_key != null:
		element.set_meta(FlowOutputCache.SETTINGS_KEY_META, spec.settings_key)

	var ctx := _make_ctx(spec, instances)
	if mode == "cache":
		ctx.set_meta(FlowExecutor.OUTPUT_CACHE_META, true)
		ctx.set_meta(FlowOutputCache.FINGERPRINT_MEMO_META, {})
	var error_log := []
	ctx.set_meta(FlowNodeBase.ERROR_LOG_META, error_log)
	# Errors are read back from the log; route the console copies through the
	# deferred queue (as threaded mode does) and drop them to keep the run quiet.
	element._defer_error_push = true
	return {
		"inputs": inputs,
		"before": before,
		"element": element,
		"instances": instances,
		"ctx": ctx,
		"error_log": error_log,
	}

# Reads one finished execution back and releases its context.
static func _collect(run : Dictionary, case : Array, mode : String) -> Dictionary:
	var element : FlowNodeBase = run.element
	element._deferred_error_pushes.clear()
	var mutation := ""
	var inputs : Array = run.inputs
	for port in range(inputs.size()):
		# content_hash (the cache's view) and the digest, which also sees changes
		# inside unsaved resources referenced by the input.
		if [ inputs[port].content_hash(), data_digest(inputs[port]) ] != run.before[port]:
			mutation = "input %d (%s) changed in a %s run: %s" % [ port, case[0] if port == 0 else case[1], mode, describe_data(inputs[port]) ]
			break
	var errors := []
	for entry in run.error_log:
		errors.append(String(entry.message))
	var bulks : Array = element.generated_bulks.duplicate()
	run.ctx.gedit_nodes_by_name = {}
	return {
		"fingerprint": outputs_fingerprint(bulks, errors),
		"summary": describe(bulks, errors),
		"errors": errors,
		"worked": errors.is_empty() and _has_output(bulks),
		"mutation": mutation,
	}

## Fresh inputs for `case`, one Data per declared input port: port 0 gets the
## primary fixture, every other port the secondary one.
static func build_inputs(spec : Dictionary, case : Array) -> Array:
	var inputs := []
	if case[0] == Fixtures.NO_INPUT:
		return inputs
	for port in range(spec.num_ins):
		var id : String = case[0] if port == 0 else case[1]
		if id.begins_with("scene_"):
			inputs.append(Fixtures.build_scene(id, spec.owner))
		else:
			inputs.append(Fixtures.build(id))
	return inputs

static func _make_element(spec : Dictionary) -> FlowNodeBase:
	var element : FlowNodeBase = spec.script.new()
	element.name = NODE_NAME
	element.node_template = spec.template
	var meta : Dictionary = element.meta_node
	var settings : NodeSettings
	if meta.has("settings") and meta.settings:
		settings = meta.settings.new()
	else:
		settings = NodeSettings.new()
	var values : Dictionary = spec.get("settings", {})
	for prop in values:
		var value = values[prop]
		settings.set(prop, value.call() if value is Callable else value)
	element.settings = settings
	element.refreshFromSettings()
	return element

static func _make_ctx(spec : Dictionary, instances : Dictionary) -> FlowData.EvaluationContext:
	var ctx := FlowDataScript.EvaluationContext.new()
	ctx.owner = spec.owner
	ctx.seed = CTX_SEED
	ctx.graph = spec.graph
	ctx.gedit_nodes_by_name = instances
	ctx.runtime_params = (spec.override.get("runtime_params", {}) as Dictionary).duplicate(true)
	ctx.runtime_params["seed"] = CTX_SEED
	var variables = spec.override.get("variables", null)
	ctx.variables = variables.call() if variables is Callable else {}
	return ctx

## The evaluation owner for `mode`: "none" (owner-less evaluation) or "scene"
## (a Node3D in the running SceneTree holding a Path3D, a MeshInstance3D and a
## box collision body, so scene readers find something to read).
static func _make_owner(mode : String) -> Node3D:
	if mode != "scene":
		return null
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var owner := Node3D.new()
	owner.name = "ConformanceOwner"
	var path := Path3D.new()
	path.name = "ConformancePath"
	path.curve = Fixtures.spline_shape().curve.duplicate()
	owner.add_child(path)
	var mesh := MeshInstance3D.new()
	mesh.name = "ConformanceMesh"
	mesh.mesh = Fixtures.shared_mesh()
	mesh.position = Vector3(2, 0, 2)
	owner.add_child(mesh)
	var body := StaticBody3D.new()
	body.name = "ConformanceBody"
	var shape := CollisionShape3D.new()
	shape.name = "ConformanceShape"
	var box := BoxShape3D.new()
	box.size = Vector3(4, 2, 4)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(3, 0, 3)
	owner.add_child(body)
	tree.root.add_child(owner)
	return owner

# --- Fingerprints ------------------------------------------------------------------

## Content fingerprint of an element's generated bulks and its errors.
static func outputs_fingerprint(bulks : Array, errors : Array) -> Array:
	var parts := [ bulks.size() ]
	for bulk in bulks:
		var digests := []
		if bulk is Array:
			for item in bulk:
				digests.append(data_digest(item))
		else:
			digests.append(value_digest(bulk))
		parts.append(digests)
	parts.append(errors.duplicate())
	return parts

## Content digest of one output slot (a Data, null or anything else).
static func data_digest(data) -> int:
	if data == null:
		return 0
	if not (data is FlowData.Data):
		return hash([ "non-data", type_string(typeof(data)), value_digest(data) ])
	var h : int = hash([ int(data.kind), data.last_added_stream_name, Array(data.tags) ])
	for stream_name in data.streams:
		var stream : Dictionary = data.streams[stream_name]
		h = hash([ h, stream_name, int(stream.data_type), _container_digest(stream.container) ])
	for attr_name in data.data_attrs:
		var rec = data.data_attrs[attr_name]
		if rec is Dictionary:
			h = hash([ h, attr_name, int(rec.get("data_type", -1)), value_digest(rec.get("value", null)) ])
		else:
			h = hash([ h, attr_name, value_digest(rec) ])
	if data.shape != null:
		h = hash([ h, data.shape.get_type_name(), data.shape.content_hash() ])
	return h

static func _container_digest(container) -> int:
	if container is Array:
		var h : int = container.size()
		# Object streams usually repeat a few resources; digest each one once.
		var memo := {}
		for element in container:
			var digest
			if element is Object and is_instance_valid(element):
				var id : int = element.get_instance_id()
				digest = memo.get(id, null)
				if digest == null:
					digest = value_digest(element)
					memo[id] = digest
			else:
				digest = value_digest(element)
			h = hash([ h, digest ])
		return h
	return hash(container)

## Digest of one value: plain values by hash(); saved resources by path; unsaved
## resources by class and stored properties (two levels deep); nodes by class
## and name; other objects by class.
static func value_digest(value, depth : int = 2) -> int:
	if value is Object:
		if not is_instance_valid(value):
			return 0
		if value is Resource:
			if value.resource_path != "":
				return hash(value.resource_path)
			var parts := [ value.get_class() ]
			if depth > 0:
				for prop in value.get_property_list():
					if (prop.usage & PROPERTY_USAGE_STORAGE) == 0:
						continue
					parts.append(prop.name)
					parts.append(value_digest(value.get(prop.name), depth - 1))
			return hash(parts)
		if value is Node:
			return hash([ value.get_class(), String(value.name) ])
		return hash(value.get_class())
	if value is Array:
		var h : int = value.size()
		for element in value:
			h = hash([ h, value_digest(element, depth) ])
		return h
	if value is Dictionary:
		var h : int = value.size()
		for key in value:
			h = hash([ h, value_digest(key, depth), value_digest(value[key], depth) ])
		return h
	return hash(value)

## Short human-readable description of bulks and errors (failure messages).
static func describe(bulks : Array, errors : Array) -> String:
	var parts := []
	for b in range(bulks.size()):
		var bulk = bulks[b]
		var ports := []
		if bulk is Array:
			for item in bulk:
				ports.append(describe_data(item))
		parts.append("bulk %d [%s]" % [ b, ", ".join(ports) ])
	var text := "%d bulk(s) %s" % [ bulks.size(), "; ".join(parts) ]
	if not errors.is_empty():
		text += " errors=%s" % [ errors ]
	return text

static func describe_data(data) -> String:
	if data == null:
		return "null"
	if not (data is FlowData.Data):
		return type_string(typeof(data))
	var text := "size=%d streams=%d kind=%d digest=%d" % [ data.size(), data.streams.size(), int(data.kind), data_digest(data) ]
	if not data.tags.is_empty():
		text += " tags=%d" % data.tags.size()
	if not data.data_attrs.is_empty():
		text += " data_attrs=%d" % data.data_attrs.size()
	if data.shape != null:
		text += " shape=%s" % data.shape.get_type_name()
	return text

static func _has_output(bulks : Array) -> bool:
	for bulk in bulks:
		if not (bulk is Array):
			continue
		for item in bulk:
			if item is FlowData.Data and (item.size() > 0 or item.shape != null or not item.data_attrs.is_empty()):
				return true
	return false
