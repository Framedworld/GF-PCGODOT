extends SceneTree

## Node and data-layer benchmark (docs/_round2/WP13-P1.md). A script, not a
## test. Run from demo/ with
##
##   godot --headless --path . -s res://tests/perf/node_benchmark.gd
##
## It times the common node bodies and the FlowData primitives they are built
## from at 1k, 10k and 100k points, plus the executor's build and finalize
## phases, and prints one table row per case:
##
##   case | points | median ms per call | min ms | ns per point | runs
##
## Environment (all optional):
##   FLOW_NB_FILTER   comma-separated substrings; only cases whose name
##                    contains one of them run (e.g. "expression,filter")
##   FLOW_NB_SIZES    comma-separated point counts (default 1000,10000,100000)
##   FLOW_NB_SCALE    multiplies the number of timed runs (default 1.0)
##   FLOW_NB_FINGERPRINT=1
##                    instead of timing, prints an exact SHA-256 of every
##                    case's output (raw bytes of every container, stream
##                    order, types, tags, data attributes and the node error),
##                    so an optimization can be checked for byte-identical
##                    output: run before and after and diff the two outputs.
##
## Every node case runs the element the way the executor does for one
## evaluation (fresh element, preExecute, run over its connected bulks); the
## input Data are built once per size and never mutated by the nodes. Each
## timed run is measured on its own and the median is reported, because the
## build container is shared and single runs are noisy.

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")

const NODES_DIR := "res://addons/flow_nodes_editor/nodes/"

var _filters : PackedStringArray = PackedStringArray()
var _sizes : Array = [1000, 10000, 100000]
var _scale : float = 1.0
var _fingerprint : bool = false
var _rows : Array = []


func _initialize() -> void:
	var f := OS.get_environment("FLOW_NB_FILTER").strip_edges()
	if f != "":
		_filters = f.split(",", false)
	var s := OS.get_environment("FLOW_NB_SIZES").strip_edges()
	if s != "":
		_sizes = []
		for part in s.split(",", false):
			_sizes.append(int(part))
	if OS.has_environment("FLOW_NB_SCALE"):
		_scale = maxf(0.01, float(OS.get_environment("FLOW_NB_SCALE")))
	_fingerprint = OS.get_environment("FLOW_NB_FINGERPRINT") == "1"

	if not _fingerprint:
		print("node_benchmark: Godot %s, %d cores, native library %s" % [
			Engine.get_version_info().string, OS.get_processor_count(),
			"loaded" if ClassDB.class_exists("GDStreamUtils") else "MISSING"])
		print("%-44s %8s %11s %11s %10s %5s" % ["case", "points", "median ms", "min ms", "ns/point", "runs"])

	for n in _sizes:
		var inputs := _make_inputs(n)
		for case in _node_cases(n, inputs):
			_run_node_case(case, n)
		for case in _data_cases(n, inputs):
			_run_data_case(case, n)
	_run_executor_cases()
	quit(0)


# --- case selection and timing ------------------------------------------------------------

func _selected(case_name : String) -> bool:
	if _filters.is_empty():
		return true
	for f in _filters:
		if case_name.contains(f):
			return true
	return false

func _runs_for(n : int) -> int:
	var base := 15
	if n >= 100000:
		base = 3
	elif n >= 10000:
		base = 7
	return maxi(1, int(round(base * _scale)))

func _report(case_name : String, n : int, samples_us : Array, per_call_divisor : int = 1) -> void:
	samples_us.sort()
	var median_ms : float = float(samples_us[samples_us.size() / 2]) / 1000.0 / float(per_call_divisor)
	var min_ms : float = float(samples_us[0]) / 1000.0 / float(per_call_divisor)
	var ns_per_point : float = median_ms * 1.0e6 / float(maxi(n, 1)) if n > 0 else 0.0
	print("%-44s %8d %11.3f %11.3f %10.1f %5d" % [case_name, n, median_ms, min_ms, ns_per_point, samples_us.size()])


# --- inputs --------------------------------------------------------------------------------

## Deterministic point sets: position, rotation (non-zero Euler degrees so the
## Basis paths run), size, density, seed, plus a float "w", an int "group"
## (10 values) and a second float "h".
func _make_inputs(n : int) -> Dictionary:
	return {
		"points": _points(n, 42, 100.0),
		"points_b": _points(maxi(1, n / 10), 7, 100.0),
		"quarter": [_points(n / 4, 1, 100.0), _points(n / 4, 2, 100.0), _points(n / 4, 3, 100.0), _points(n - 3 * (n / 4), 4, 100.0)],
		"anchors_4": _points(maxi(1, n / 4), 5, 100.0),
		"anchors_16": _points(maxi(1, n / 16), 6, 100.0),
		"source_4": _points(4, 8, 2.0),
		"one_box": _one_box(),
	}

func _points(n : int, seed_value : int, extent : float) -> FlowData.Data:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var d := FlowData.Data.new()
	d.addCommonStreams(n)
	var pos := d.getVector3Container(FlowData.AttrPosition)
	var rot := d.getVector3Container(FlowData.AttrRotation)
	var siz := d.getVector3Container(FlowData.AttrSize)
	var dens := PackedFloat32Array()
	dens.resize(n)
	var seeds := PackedInt32Array()
	seeds.resize(n)
	var w := PackedFloat32Array()
	w.resize(n)
	var h := PackedFloat32Array()
	h.resize(n)
	var group := PackedInt32Array()
	group.resize(n)
	for i in range(n):
		pos[i] = Vector3(rng.randf() * extent, rng.randf() * 2.0, rng.randf() * extent)
		rot[i] = Vector3(rng.randf_range(-30.0, 30.0), rng.randf_range(-180.0, 180.0), rng.randf_range(-30.0, 30.0))
		var s := rng.randf_range(0.5, 2.0)
		siz[i] = Vector3(s, s, s)
		dens[i] = rng.randf()
		seeds[i] = rng.randi() & 0x7fffffff
		w[i] = rng.randf_range(-1.0, 1.0)
		h[i] = rng.randf_range(0.0, 10.0)
		group[i] = rng.randi() % 10
	d.registerStream(FlowData.AttrDensity, dens, FlowData.DataType.Float)
	d.registerStream(FlowData.AttrSeed, seeds, FlowData.DataType.Int)
	d.registerStream("w", w, FlowData.DataType.Float)
	d.registerStream("h", h, FlowData.DataType.Float)
	d.registerStream("group", group, FlowData.DataType.Int)
	return d

func _one_box() -> FlowData.Data:
	var d := FlowData.Data.new()
	d.addCommonStreams(1)
	d.getVector3Container(FlowData.AttrSize)[0] = Vector3(100.0, 0.0, 100.0)
	d.getVector3Container(FlowData.AttrPosition)[0] = Vector3(50.0, 0.0, 50.0)
	return d


# --- node cases ---------------------------------------------------------------------------

## { name, template, settings: Dictionary, ports: Array (per port: Data or Array of Data) }
func _node_cases(n : int, inputs : Dictionary) -> Array:
	var pts : FlowData.Data = inputs.points
	var cases := [
		_nc("expression 'density * 0.5 + 0.25'", "expression", { "expression": "density * 0.5 + 0.25", "out_name": "density" }, [pts]),
		_nc("expression 'position.y + w'", "expression", { "expression": "position.y + w", "out_name": "pw" }, [pts]),
		_nc("expression 'Index % 2 == 0' (bool)", "expression", { "expression": "Index % 2 == 0", "out_name": "even" }, [pts]),
		_nc("expression 'sin(h) * density + k' (arg)", "expression", { "expression": "sin(h) * density + k", "out_name": "s", "args": { "k": 0.5 } }, [pts]),
		_nc("expression 'position * 2.0' (vector)", "expression", { "expression": "position * 2.0", "out_name": "p2" }, [pts]),
		_nc("density_filter [0.25, 0.75]", "density_filter", { "lower_bound": 0.25, "upper_bound": 0.75 }, [pts]),
		_nc("math_op density * w", "math_op", { "operation": MathOpNodeSettings.eOperation.Multiply, "in_nameA": "density", "in_nameB": "w", "out_name": "density" }, [pts, pts]),
		_nc("math_op position + position", "math_op", { "operation": MathOpNodeSettings.eOperation.Add, "in_nameA": "position", "in_nameB": "position", "out_name": "p2" }, [pts, pts]),
		_nc("add_attribute float", "add_attribute", { "name": "k", "data_type": FlowData.DataType.Float, "cte_float": 0.5 }, [pts]),
		_nc("attribute_filter_range h (float)", "attribute_filter_range", { "attribute_name": "h", "min_value": 2.0, "max_value": 6.0 }, [pts]),
		_nc("attribute_filter_range position (vector)", "attribute_filter_range", { "attribute_name": "position", "min_value": 20.0, "max_value": 80.0 }, [pts]),
		_nc("filter w > 0", "filter", { "in_nameA": "w", "condition": FilterNodeSettings.eCondition.Greater, "in_nameB": "0.0" }, [pts]),
		_nc("filter density < h (two streams)", "filter", { "in_nameA": "density", "condition": FilterNodeSettings.eCondition.Less, "in_nameB": "h" }, [pts, pts]),
		_nc("merge 4 inputs", "merge", {}, [inputs.quarter]),
		_nc("copy 4 sources x n/4 targets", "copy", { "mode": CopyNodeSettings.eMode.SourceToTargets }, [inputs.source_4, inputs.anchors_4]),
		_nc("transform (random offset/rot/scale)", "transform", { "offset_min": Vector3(-1, 0, -1), "offset_max": Vector3(1, 0, 1), "rotation_max": Vector3(0, 90, 0), "scale_min": Vector3(0.5, 0.5, 0.5), "scale_max": Vector3(1.5, 1.5, 1.5) }, [pts]),
		_nc("transform_points (local rotation)", "transform_points", { "offset_min": Vector3(-1, 0, -1), "offset_max": Vector3(1, 0, 1), "rotation_max": Vector3(0, 90, 0), "rotation_local_space": true }, [pts]),
		_nc("point_offsets 4 per anchor", "point_offsets", { "offsets": _vec_array([Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]) }, [inputs.anchors_4]),
		_nc("sample_points 16 per input (quasi random)", "sample_points", { "num_samples": 16 }, [inputs.anchors_16]),
		_nc("surface_sampler 1 box, n points", "surface_sampler", { "num_points": n }, [inputs.one_box]),
		_nc("difference A(n) - B(n/10) bounds box", "difference", {}, [pts, inputs.points_b]),
		_nc("self_pruning (bounds overlap)", "self_pruning", {}, [pts]),
		_nc("partition by group (10 values)", "partition", { "attribute_name": "group" }, [pts]),
		_nc("sort by density", "sort", { "sort_by": "density" }, [pts]),
		_nc("grid n points", "grid", { "x": int(sqrt(float(n))), "y": 1, "z": n / maxi(1, int(sqrt(float(n)))) }, []),
	]
	return cases

func _nc(case_name : String, template : String, settings : Dictionary, ports : Array) -> Dictionary:
	return { "name": case_name, "template": template, "settings": settings, "ports": ports }

func _vec_array(values : Array) -> Array[Vector3]:
	var out : Array[Vector3] = []
	for v in values:
		out.append(v)
	return out

func _new_settings(script : Script, values : Dictionary) -> NodeSettings:
	var probe = script.new()
	var meta : Dictionary = probe.meta_node
	var settings : NodeSettings = meta.settings.new() if meta.has("settings") and meta.settings else NodeSettings.new()
	for key in values:
		var current = settings.get(key)
		if current is Array and current.is_typed():
			current.clear()
			for item in values[key]:
				current.append(item)
		elif current is Dictionary:
			settings.set(key, values[key].duplicate())
		else:
			settings.set(key, values[key])
	return settings

## Runs `script` once like the executor does: fresh element, fake source
## elements holding the inputs, preExecute, run.
func _run_element(script : Script, template : String, settings : NodeSettings, ports : Array) -> FlowNodeBase:
	var ctx := FlowData.EvaluationContext.new()
	ctx.owner = null
	ctx.gedit_nodes_by_name = {}
	ctx.runtime_params = { "seed": 0 }
	var node : FlowNodeBase = script.new()
	node.name = "bench"
	node.node_template = template
	node.settings = settings
	var deps : Array[Dictionary] = []
	var k := 0
	for p in range(ports.size()):
		var port_inputs : Array = ports[p] if ports[p] is Array else [ports[p]]
		for data in port_inputs:
			var src := FlowNodeBase.new()
			src.name = "src%d" % k
			src.generated_bulks = [[data]]
			src.num_generated_bulks = 1
			ctx.gedit_nodes_by_name[src.name] = src
			deps.append({ "from_node": src.name, "from_port": 0, "to_node": node.name, "to_port": p })
			k += 1
	node.deps = deps
	node.preExecute(ctx)
	node.run(ctx)
	ctx.gedit_nodes_by_name = {}
	return node

func _run_node_case(case : Dictionary, n : int) -> void:
	if not _selected(case.name):
		return
	var script : Script = load(NODES_DIR + case.template + ".gd")
	var settings := _new_settings(script, case.settings)
	if _fingerprint:
		var node := _run_element(script, case.template, settings, case.ports)
		print("%s @%d: %s" % [case.name, n, _fingerprint_node(node)])
		return
	_run_element(script, case.template, settings, case.ports)  # warm-up
	var samples := []
	for r in range(_runs_for(n)):
		var t0 := Time.get_ticks_usec()
		var node := _run_element(script, case.template, settings, case.ports)
		samples.append(Time.get_ticks_usec() - t0)
		node = null
	_report(case.name, n, samples)


# --- data-layer cases ----------------------------------------------------------------------

## { name, run: Callable() -> Variant (the value fingerprinted), calls: int }
func _data_cases(n : int, inputs : Dictionary) -> Array:
	var pts : FlowData.Data = inputs.points
	var half := PackedInt32Array()
	for i in range(0, n, 2):
		half.append(i)
	var newf := PackedFloat32Array()
	newf.resize(n)
	newf.fill(0.5)
	var reg_target := pts.duplicate()
	var quat_pts := pts.duplicate()
	var quats := PackedVector4Array()
	var src_eulers := pts.getVector3Container(FlowData.AttrRotation)
	for i in range(src_eulers.size()):
		quats.append(FlowData.quatToVec4(FlowData.eulerToQuat(src_eulers[i])))
	quat_pts.registerStream(FlowData.AttrRotationQuat, quats, FlowData.DataType.Quaternion)
	return [
		{ "name": "Data.filter (every 2nd point, 8 streams)", "calls": 1, "run": func(): return pts.filter(half) },
		{ "name": "Data.duplicate (8 streams)", "calls": 1, "run": func(): return pts.duplicate() },
		{ "name": "Data.duplicate + write density", "calls": 1, "run": func():
			var d := pts.duplicate()
			var c : PackedFloat32Array = d.streams[FlowData.AttrDensity].container
			c[0] = 2.0
			return d },
		{ "name": "Data.content_hash", "calls": 1, "run": func(): return pts.content_hash() },
		{ "name": "Data.registerStream float (x100 calls)", "calls": 100, "run": func():
			for i in range(100):
				reg_target.registerStream("k", newf, FlowData.DataType.Float)
			return reg_target },
		{ "name": "Data.findStream 'density' (x100 calls)", "calls": 100, "run": func():
			var s = null
			for i in range(100):
				s = pts.findStream("density")
			return s.container },
		{ "name": "Data.findStream 'position.y'", "calls": 1, "run": func(): return pts.findStream("position.y").container },
		{ "name": "Data.getTransformsStream + atIndex all", "calls": 1, "run": func():
			var trs := pts.getTransformsStream()
			var out := PackedVector3Array()
			out.resize(trs.size())
			for i in range(trs.size()):
				var t := trs.atIndex(i)
				out[i] = t.basis.x + t.origin
			return out },
		{ "name": "Data.getTransformsStream + atIndex (quat)", "calls": 1, "run": func():
			var trs := quat_pts.getTransformsStream()
			var out := PackedVector3Array()
			out.resize(trs.size())
			for i in range(trs.size()):
				var t := trs.atIndex(i)
				out[i] = t.basis.x + t.origin
			return out },
		{ "name": "FlowData.eulerToBasis per point", "calls": 1, "run": func():
			var eulers := pts.getVector3Container(FlowData.AttrRotation)
			var out := PackedVector3Array()
			out.resize(eulers.size())
			for i in range(eulers.size()):
				var b := FlowData.eulerToBasis(eulers[i])
				out[i] = b.x + b.y * 2.0 + b.z * 3.0
			return out },
		{ "name": "Data.getEffectiveBounds", "calls": 1, "run": func():
			var b := pts.getEffectiveBounds()
			return [b.min, b.max] },
		{ "name": "Data.addCommonStreams", "calls": 1, "run": func():
			var d := FlowData.Data.new()
			d.addCommonStreams(n)
			return d },
	]

func _run_data_case(case : Dictionary, n : int) -> void:
	if not _selected(case.name):
		return
	var fn : Callable = case.run
	if _fingerprint:
		print("%s @%d: %s" % [case.name, n, _fingerprint_value(fn.call())])
		return
	fn.call()  # warm-up
	var samples := []
	for r in range(_runs_for(n)):
		var t0 := Time.get_ticks_usec()
		fn.call()
		samples.append(Time.get_ticks_usec() - t0)
	_report(case.name, n, samples, int(case.calls))


# --- executor phases -----------------------------------------------------------------------

func _run_executor_cases() -> void:
	if not _selected("executor"):
		return
	var graph := _build_47_node_graph()
	FlowNodeIO.evaluate(graph)
	if _fingerprint:
		var out := FlowNodeIO.evaluate(graph)
		print("executor 47-node graph: %s" % _fingerprint_value(out.get("result")))
		return
	var build := []
	var body := []
	var fin := []
	var total := []
	var compile_lookup := []
	var runs := maxi(1, int(round(200 * _scale)))
	for r in range(runs):
		var parent := FlowNodeIO.make_context(null, 0, {})
		var t0 := Time.get_ticks_usec()
		FlowCompiledGraph.for_graph(graph)
		var t1 := Time.get_ticks_usec()
		var ex := FlowExecutor.new()
		ex.begin(graph, {}, parent)
		var t2 := Time.get_ticks_usec()
		for node in ex.state["ordered_nodes"]:
			ex._run_element(node)
		var t3 := Time.get_ticks_usec()
		ex._index = ex._node_count
		ex.finalize()
		var t4 := Time.get_ticks_usec()
		ex = null
		var t5 := Time.get_ticks_usec()
		compile_lookup.append(t1 - t0)
		build.append(t2 - t1)
		body.append(t3 - t2)
		fin.append(t5 - t3)
		total.append(t5 - t0)
	_report("executor: FlowCompiledGraph.for_graph (47)", 50, compile_lookup)
	_report("executor: build_state (47 elements)", 50, build)
	_report("executor: node bodies (47 elements)", 50, body)
	_report("executor: finalize + release (47)", 50, fin)
	_report("executor: whole evaluation (47)", 50, total)

## The executor_benchmark.gd scenario A graph: grid (5x10) -> 4 branches of 11
## trivial nodes -> merge -> output.
func _build_47_node_graph() -> FlowGraphResource:
	var nodes := []
	var links := []
	var add_node := func(node_name : String, template : String, settings : Dictionary):
		nodes.append({ "name": StringName(node_name), "template": template, "settings": settings, "position": Vector2.ZERO, "args_port": {}, "show_disconnected_inputs": false })
	var add_link := func(a : String, ap : int, b : String, bp : int):
		links.append({ "from_node": StringName(a), "from_port": ap, "to_node": StringName(b), "to_port": bp, "keep_alive": false })
	add_node.call("grid", "grid", { "x": 5, "y": 1, "z": 10, "random_seed": 7 })
	add_node.call("merge", "merge", {})
	add_node.call("out", "output", { "name": "result" })
	for b in range(4):
		var prev := "grid"
		for stage in range(11):
			var node_name := "b%d_%02d" % [b, stage]
			match stage % 4:
				0:
					add_node.call(node_name, "add_attribute", { "name": "w%d" % stage, "data_type": FlowData.DataType.Float, "cte_float": 0.25 * float(b + 1) })
				1:
					add_node.call(node_name, "math_op", { "operation": 1, "in_nameA": "density", "in_nameB": "w%d" % (stage - 1), "out_name": "density" })
				2:
					add_node.call(node_name, "expression", { "expression": "density * 0.5 + 0.25", "out_name": "density" })
				3:
					add_node.call(node_name, "density_filter", { "lower_bound": 0.0, "upper_bound": 1.0 })
			add_link.call(prev, 0, node_name, 0)
			if stage % 4 == 1:
				add_link.call(prev, 0, node_name, 1)
			prev = node_name
		add_link.call(prev, 0, "merge", 0)
	add_link.call("merge", 0, "out", 0)
	var graph := FlowGraphResource.new()
	graph.data = { "type": "flow_graph_nodes", "version": 1, "min_pos": Vector2.ZERO, "nodes": nodes, "links": links, "frames": [] }
	return graph


# --- exact fingerprints --------------------------------------------------------------------

func _fingerprint_node(node : FlowNodeBase) -> String:
	var parts := [str(node.err)]
	for bulk in node.generated_bulks:
		for data in bulk:
			parts.append(_data_bytes(data))
	return _sha(parts)

func _fingerprint_value(value) -> String:
	if value is FlowData.Data:
		return _sha([_data_bytes(value)])
	if value is Array:
		var parts := []
		for v in value:
			parts.append(_fingerprint_value(v))
		return _sha(parts)
	if value is Dictionary:
		return _sha([var_to_bytes(value)])
	return _sha([var_to_bytes(value)])

func _data_bytes(data) -> PackedByteArray:
	if not (data is FlowData.Data):
		return var_to_bytes(str(data))
	var out := PackedByteArray()
	for stream_name in data.streams:
		var stream : Dictionary = data.streams[stream_name]
		out.append_array(var_to_bytes([str(stream_name), str(stream.get("name", "")), int(stream.data_type)]))
		out.append_array(var_to_bytes(stream.container))
	out.append_array(var_to_bytes([data.last_added_stream_name, data.tags, int(data.kind), data.data_attrs]))
	return out

func _sha(parts : Array) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for p in parts:
		var bytes : PackedByteArray = p if p is PackedByteArray else var_to_bytes(p)
		if bytes.size() > 0:
			ctx.update(bytes)
	return ctx.finish().hex_encode().substr(0, 16)
