# r1_golden_purity_review_test.gd
# Adversarial review (WP13 R1): run settings are rebuilt from the compiled
# graph by assigning the saved values (FlowCompiledGraph.NodeDesc.new_settings),
# and untyped Array / Dictionary values are shared with graph.data, as
# dict_to_resource always did. An element that wrote into such a container
# would corrupt the saved graph and every later run. Pin that no stock node of
# the golden set does, in sequential, threaded and cached runs.
class_name R1GoldenPurityReviewTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")


static func _graphs_of(graph: FlowGraphResource, into: Array, visited: Dictionary) -> Array:
	if graph == null or visited.has(graph.get_instance_id()):
		return into
	visited[graph.get_instance_id()] = true
	into.append(graph)
	for n_data in graph.data.get("nodes", []):
		var settings = n_data.get("settings", {})
		if settings is Dictionary:
			var nested = settings.get("graph", null)
			if nested is FlowGraphResource:
				_graphs_of(nested, into, visited)
	return into

static func _fingerprints(graphs: Array) -> Array:
	var result := []
	for g in graphs:
		result.append(var_to_str(g.data).hash())
	return result

func _clear_gdunit_script_errors() -> void:
	var tctx = GdUnitThreadManager.get_current_context()
	if tctx == null:
		return
	var exec_ctx = tctx.get_execution_context()
	if exec_ctx != null and exec_ctx.error_monitor != null:
		exec_ctx.error_monitor.clear_logs()


func test_evaluation_never_writes_into_saved_graph_data(timeout := 1800000) -> void:
	var checked := 0
	var changed := []
	for path in GoldenGraphsTest.discover_files():
		var hosts := []   # [root to free, host]
		var ext : String = path.get_extension()
		if ext == "tscn" or ext == "scn":
			var packed = ResourceLoader.load(path)
			if not (packed is PackedScene):
				continue
			var root : Node = packed.instantiate()
			var flow_nodes := []
			if root is FlowGraphNode3D:
				flow_nodes.append(root)
			for n in root.find_children("*", "", true, false):
				if n is FlowGraphNode3D:
					flow_nodes.append(n)
			var graphs := {}
			for fn in flow_nodes:
				graphs[fn] = fn.graph
				fn.graph = null
			add_child(root)
			for fn in flow_nodes:
				fn.graph = graphs[fn]
				if fn.graph != null:
					hosts.append([root, fn])
			if hosts.is_empty():
				remove_child(root)
				root.free()
				continue
		else:
			var res = ResourceLoader.load(path)
			if not (res is FlowGraphResource):
				continue
			var host := FlowGraphNode3D.new()
			host.generate_on_ready = false
			host.graph = res
			add_child(host)
			hosts.append([host, host])
		for entry in hosts:
			var host : FlowGraphNode3D = entry[1]
			if not GoldenGraphsTest.skip_reason(host.graph).is_empty():
				continue
			var graphs := _graphs_of(host.graph, [], {})
			var before := _fingerprints(graphs)
			for mode in [[false, false], [true, false], [false, true], [false, true]]:
				host.threaded = mode[0]
				host.output_cache = mode[1]
				host.regenerate()
			host.cleanup()
			checked += 1
			if _fingerprints(graphs) != before:
				changed.append("%s::%s" % [path, host.name])
		var root_to_free : Node = hosts[0][0]
		if root_to_free.get_parent() != null:
			root_to_free.get_parent().remove_child(root_to_free)
		root_to_free.free()
		FlowOutputCache.clear()
	_clear_gdunit_script_errors()
	await get_tree().process_frame
	assert_int(checked).is_greater(10)
	assert_array(changed).is_empty()
