## Deterministic fingerprinting of graph evaluation results, shared by the
## seed-0 back-compat test. Hashes only what a graph *produces*: the streams of
## every node's generated bulks, the streams of every collected output (name,
## type, contents) and the generated subtrees in the scene (classes,
## transforms, MultiMesh buffers). Metadata that is allowed to change without
## changing output (flow_owner meta shape, auto-generated "@Class@123" node
## names, Data tags/data_attrs/kind) is deliberately ignored.
extends RefCounted

const GRAPH_DIRS := ["res://graphs", "res://demos"]
const ROOT_GRAPHS := ["res://graph00.tres", "res://graph01.tres", "res://graph02_curves.tres"]


## Standalone FlowGraphResource files, keyed by path -> FlowGraphResource.
static func collect_graph_resources() -> Dictionary:
	var result := {}
	var tres_paths : Array = ROOT_GRAPHS.duplicate()
	for dir in GRAPH_DIRS:
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".tres"):
				tres_paths.append(dir.path_join(file))
	for path in tres_paths:
		if not ResourceLoader.exists(path):
			continue
		var res = ResourceLoader.load(path)
		if res is FlowGraphResource:
			result[path] = res
	return result


## Demo scenes that contain at least one FlowGraphNode3D with a graph.
static func collect_demo_scenes() -> PackedStringArray:
	var result := PackedStringArray()
	for file in DirAccess.get_files_at("res://demos"):
		if not file.ends_with(".tscn"):
			continue
		var scene_path := "res://demos".path_join(file)
		var packed = ResourceLoader.load(scene_path)
		if not (packed is PackedScene):
			continue
		var state : SceneState = packed.get_state()
		var has_graph := false
		for node_idx in range(state.get_node_count()):
			for prop_idx in range(state.get_node_property_count(node_idx)):
				if state.get_node_property_value(node_idx, prop_idx) is FlowGraphResource:
					has_graph = true
		if has_graph:
			result.append(scene_path)
	return result


## Every FlowGraphNode3D under `root`, in tree order.
static func find_flow_nodes(root : Node) -> Array:
	var found := []
	if root is FlowGraphNode3D:
		found.append(root)
	for child in root.get_children():
		found.append_array(find_flow_nodes(child))
	return found


## Remove content a previous (editor) generation saved into the scene, so every
## evaluation starts from the same clean scene.
static func strip_generated(root : Node) -> void:
	for child in root.get_children():
		if child.has_meta("flow_owner"):
			root.remove_child(child)
			child.free()
		else:
			strip_generated(child)


## Legacy-convention evaluation that also fingerprints every node's generated
## bulks (not just the graph outputs), by driving the evaluator's three phases
## directly. Many demo graphs end in debug-draw or spawner nodes whose data is
## otherwise invisible; this makes every intermediate stream count.
## Returns { "outputs": Dictionary, "nodes": PackedByteArray }.
static func evaluate_with_node_hashes(graph : FlowGraphResource, args : Dictionary, ctx) -> Dictionary:
	var state : Dictionary = FlowNodeIO._build_evaluation_state(graph, args, ctx, {}, 0)
	if state.is_empty():
		return { "outputs": {}, "nodes": PackedByteArray() }
	for node in state["ordered_nodes"]:
		FlowNodeIO._execute_single_node(node, state["instances"], state["graph"], state["ctx"])
	var hctx := HashingContext.new()
	hctx.start(HashingContext.HASH_SHA256)
	var names : Array = state["instances"].keys()
	names.sort_custom(func(a, b): return str(a) < str(b))
	for node_name in names:
		var node = state["instances"][node_name]
		hctx.update(("node:%s|" % str(node_name)).to_utf8_buffer())
		for bulk_idx in range(node.generated_bulks.size()):
			var bulk : Array = node.generated_bulks[bulk_idx]
			for port_idx in range(bulk.size()):
				hctx.update(("bulk:%d:%d|" % [bulk_idx, port_idx]).to_utf8_buffer())
				_hash_data(hctx, bulk[port_idx])
	var nodes_hash := hctx.finish()
	var outputs : Dictionary = FlowNodeIO._finalize_evaluation(state)
	return { "outputs": outputs, "nodes": nodes_hash }


static func hash_outputs(outputs : Dictionary) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var names : Array = outputs.keys()
	names.sort_custom(func(a, b): return str(a) < str(b))
	for out_name in names:
		ctx.update(("output:%s|" % str(out_name)).to_utf8_buffer())
		_hash_data(ctx, outputs[out_name])
	return ctx.finish()


static func _hash_data(ctx : HashingContext, data) -> void:
	if not (data is FlowData.Data):
		ctx.update(("value:%s|" % type_string(typeof(data))).to_utf8_buffer())
		return
	var stream_names : Array = data.streams.keys()
	stream_names.sort_custom(func(a, b): return str(a) < str(b))
	for stream_name in stream_names:
		var stream : Dictionary = data.streams[stream_name]
		ctx.update(("stream:%s:%d|" % [str(stream_name), int(stream.data_type)]).to_utf8_buffer())
		ctx.update(_container_bytes(stream.container))


static func _container_bytes(container) -> PackedByteArray:
	match typeof(container):
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, \
		TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_VECTOR4_ARRAY, TYPE_PACKED_COLOR_ARRAY, \
		TYPE_PACKED_STRING_ARRAY:
			return var_to_bytes(container)
		TYPE_ARRAY:
			var parts := PackedStringArray()
			for item in container:
				parts.append(_object_signature(item))
			return ("[%s]" % ",".join(parts)).to_utf8_buffer()
	return ("?%s" % type_string(typeof(container))).to_utf8_buffer()


static func _object_signature(item) -> String:
	if item == null:
		return "null"
	if not is_instance_valid(item):
		return "freed"
	if item is Resource:
		if item.resource_path != "":
			return item.resource_path
		if item is Mesh:
			return "%s(%s,%d)" % [item.get_class(), str(item.get_aabb()), item.get_surface_count()]
		return item.get_class()
	if item is Node:
		return "%s:%s" % [item.get_class(), _stable_name(item)]
	return type_string(typeof(item))


static func _stable_name(node : Node) -> String:
	var node_name := str(node.name)
	# Auto-generated names embed a process-global counter; keep only the class.
	if node_name.begins_with("@"):
		return "@" + node.get_class()
	return node_name


## Fingerprint of everything spawned under `root`: every subtree whose root
## carries `flow_owner` meta, found anywhere below `root`, in tree order.
static func hash_generated(root : Node) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	_hash_generated_roots(ctx, root, "")
	return ctx.finish()


static func _hash_generated_roots(ctx : HashingContext, node : Node, prefix : String) -> void:
	var idx := 0
	for child in node.get_children():
		var key := "%s/%d" % [prefix, idx]
		if child.has_meta("flow_owner"):
			_hash_node(ctx, child, key)
		else:
			_hash_generated_roots(ctx, child, key)
		idx += 1


static func _hash_node(ctx : HashingContext, node : Node, key : String) -> void:
	key = "%s:%s:%s" % [key, node.get_class(), _stable_name(node)]
	ctx.update(key.to_utf8_buffer())
	if node is Node3D:
		ctx.update(var_to_bytes(node.transform))
	if node.scene_file_path != "":
		ctx.update(node.scene_file_path.to_utf8_buffer())
	if node is MultiMeshInstance3D and node.multimesh != null:
		var mm : MultiMesh = node.multimesh
		ctx.update(("mm:%d:%s|" % [mm.instance_count, _object_signature(mm.mesh)]).to_utf8_buffer())
		ctx.update(var_to_bytes(mm.buffer))
	elif node is MeshInstance3D:
		ctx.update(_object_signature(node.mesh).to_utf8_buffer())
	var idx := 0
	for child in node.get_children():
		_hash_node(ctx, child, "%s/%d" % [key, idx])
		idx += 1


static func combine(outputs_hash : PackedByteArray, generated_hash : PackedByteArray) -> String:
	return "%s:%s" % [outputs_hash.hex_encode(), generated_hash.hex_encode()]
