extends Node
class_name NodeDrawDebug

# This script is a separate helper script to store all the code associated with rendering the debug boxes in the 3D viewer

var node : FlowNodeBase

# Render
var scenario_rid : RID
var multimesh_rid : RID
var instance_rid : RID
var mesh_resource: Mesh = preload( "res://addons/flow_nodes_editor/resources/unit_cube.tres" )
var selection_color := Color.MAGENTA
	
func _ready():
	scenario_rid = _resolve_debug_scenario()
	
func _exit_tree():
	cleanup_multimesh_direct()
	
func cleanup_multimesh_direct():
	if instance_rid.is_valid():
		RenderingServer.free_rid(instance_rid)
		instance_rid = RID()

	if multimesh_rid.is_valid():
		RenderingServer.free_rid(multimesh_rid)
		multimesh_rid = RID()	

func create_multimesh_direct():
	if not mesh_resource:
		print("No mesh resource assigned")
		return
	
	cleanup_multimesh_direct()  # Clean up any existing
	_sync_instance_scenario()
	
	# Create MultiMesh resource
	multimesh_rid = RenderingServer.multimesh_create()
	
	# Setup MultiMesh
	RenderingServer.multimesh_set_mesh(multimesh_rid, mesh_resource.get_rid())
	#RenderingServer.multimesh_allocate_data(multimesh_rid, instance_count, RS.MULTIMESH_TRANSFORM_3D)
	
	# Create instance transforms
	#setup_instance_transforms()
	
	# Create rendering instance
	instance_rid = RenderingServer.instance_create()
	RenderingServer.instance_set_base(instance_rid, multimesh_rid)
	
	# Add to current scenario (viewport world)
	if scenario_rid.is_valid():
		RenderingServer.instance_set_scenario(instance_rid, scenario_rid)
	else:
		print("setupDebugDraw failed - no 3D scene scenario")
	
	# Set transform
	var global_transform : Transform3D = Transform3D.IDENTITY
	RenderingServer.instance_set_transform(instance_rid, global_transform)

func _sync_instance_scenario() -> void:
	var resolved := _resolve_debug_scenario()
	if resolved.is_valid() and resolved != scenario_rid:
		scenario_rid = resolved
	if instance_rid.is_valid() and scenario_rid.is_valid():
		RenderingServer.instance_set_scenario(instance_rid, scenario_rid)

func _resolve_debug_scenario() -> RID:
	var editor = node.getEditor() if node else null
	if editor:
		if editor.resource_owner and editor.resource_owner is Node3D:
			var owner := editor.resource_owner as Node3D
			if owner.is_inside_tree() and owner.get_world_3d():
				return owner.get_world_3d().scenario
		if editor.has_method("find_debug_world_node"):
			var world_node: Node3D = editor.call("find_debug_world_node")
			if world_node != null and world_node.is_inside_tree() and world_node.get_world_3d():
				return world_node.get_world_3d().scenario
	if Engine.is_editor_hint():
		var scene_root := EditorInterface.get_edited_scene_root()
		if scene_root is Node3D and scene_root.is_inside_tree() and scene_root.get_world_3d():
			return scene_root.get_world_3d().scenario
		if scene_root != null:
			var nested := scene_root.find_children("*", "Node3D", true, false)
			for candidate in nested:
				var node3d := candidate as Node3D
				if node3d != null and node3d.is_inside_tree() and node3d.get_world_3d():
					return node3d.get_world_3d().scenario
	var viewport = get_viewport()
	if viewport and viewport.get_world_3d():
		return viewport.get_world_3d().scenario
	return RID()

func setupColors( out_data : FlowData.Data ):
	var instance_count = out_data.size()
	var stream = _debug_modulation_stream(out_data)
	if stream != null:
		var intensities := _stream_to_intensities(stream, instance_count)
		if not intensities.is_empty():
			_apply_grayscale_colors(intensities)
			return

	var color : Color = node.settings.debug_color
	for idx in range( instance_count ):
		RenderingServer.multimesh_instance_set_color( multimesh_rid, idx, color )

func _debug_modulation_stream(out_data: FlowData.Data):
	var explicit_name := String(node.settings.debug_modulate_by).strip_edges()
	if explicit_name != "":
		var stream = out_data.findStream(explicit_name)
		if stream == null:
			node.setError("Attribute %s not found for debug modulation" % explicit_name)
			return null
		if not _can_modulate_stream(stream):
			node.setError("Attribute %s must be bool, int, float, vector, or color to modulate debug" % explicit_name)
			return null
		return stream

	var last_name := String(out_data.last_added_stream_name)
	if last_name != "" and not _is_debug_bookkeeping_stream(last_name):
		var last_stream = out_data.findStream(last_name)
		if last_stream != null and _can_modulate_stream(last_stream):
			return last_stream

	var preferred_names := [
		"density",
		"weight",
		"noise",
		"value",
		"center_bias",
		"distance_to_door",
		"type",
		"is_protected",
	]
	for preferred_name in preferred_names:
		var preferred_stream = out_data.findStream(preferred_name)
		if preferred_stream != null and _can_modulate_stream(preferred_stream):
			return preferred_stream

	for stream_name in out_data.streams.keys():
		if _is_debug_bookkeeping_stream(String(stream_name)):
			continue
		var candidate = out_data.streams[stream_name]
		if candidate != null and _can_modulate_stream(candidate):
			return candidate
	return null

func _can_modulate_stream(stream) -> bool:
	match int(stream.data_type):
		FlowData.DataType.Bool, FlowData.DataType.Int, FlowData.DataType.Float, FlowData.DataType.Vector, FlowData.DataType.Color:
			return true
		_:
			return false

func _stream_to_intensities(stream, instance_count: int) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	var count: int = mini(instance_count, stream.container.size())
	values.resize(count)
	match int(stream.data_type):
		FlowData.DataType.Bool, FlowData.DataType.Int, FlowData.DataType.Float:
			for idx in range(count):
				values[idx] = _safe_float(stream.container[idx])
		FlowData.DataType.Vector:
			for idx in range(count):
				var v: Vector3 = stream.container[idx]
				values[idx] = v.length()
		FlowData.DataType.Color:
			for idx in range(count):
				var c: Color = stream.container[idx]
				values[idx] = c.get_luminance()
		_:
			return PackedFloat32Array()
	return values

func _apply_grayscale_colors(values: PackedFloat32Array) -> void:
	if values.is_empty():
		return

	var min_value := INF
	var max_value := -INF
	for value in values:
		min_value = minf(min_value, value)
		max_value = maxf(max_value, value)

	var span := max_value - min_value
	var alpha := node.settings.debug_color.a
	for idx in range(values.size()):
		var normalized := values[idx]
		if span > 0.00001:
			normalized = (values[idx] - min_value) / span
		else:
			normalized = clampf(values[idx], 0.0, 1.0)
		var gray := lerpf(0.08, 1.0, clampf(normalized, 0.0, 1.0))
		RenderingServer.multimesh_instance_set_color(multimesh_rid, idx, Color(gray, gray, gray, alpha))

func _safe_float(value) -> float:
	var numeric := float(value)
	if is_nan(numeric) or is_inf(numeric):
		return 0.0
	return numeric

func _is_debug_bookkeeping_stream(stream_name: String) -> bool:
	var lower := stream_name.to_lower()
	return lower in [
		String(FlowData.AttrPosition),
		String(FlowData.AttrRotation),
		String(FlowData.AttrSize),
		"grid_cell",
		"cell_x",
		"cell_y",
		"room_id",
		"roomid",
		"door_id",
		"index",
		"source_index",
		"parent_index",
		"offset_index",
	]

func setupDraw():
	var s = node.settings
	if !s.debug_enabled or s.disabled:
		return
	_sync_instance_scenario()
		
	var num_bulks = node.generated_bulks.size()
	s.debug_bulk = clampi( s.debug_bulk, 0, maxi( 0, num_bulks - 1) )
	if s.debug_bulk >= num_bulks :
		return
	s.debug_output = clampi( s.debug_output, 0, node.generated_bulks[s.debug_bulk].size() - 1)
		
	var out_data : FlowData.Data = node.get_bulk_output(s.debug_bulk, s.debug_output)
	if not out_data || !out_data.hasStream( FlowData.AttrPosition ):
		print( "setupDebugDraw failed - out_data" )
		return
	var instance_count = out_data.size()
		
	if not multimesh_rid.is_valid() or RenderingServer.multimesh_get_instance_count(multimesh_rid) < instance_count:
		create_multimesh_direct()
		
	if not multimesh_rid.is_valid():
		print( "setupDebugDraw failed - multimesh_rid" )
		return
		
	var transforms := out_data.getTransformsStream()
	if transforms == null:
		print( "setupDebugDraw failed - positions/eulers" )
		return
	
	var debug_row = node.debug_row
	var allocated_count = instance_count
	if debug_row != -1 and debug_row < instance_count:
		allocated_count += 1
		
	var current_count = RenderingServer.multimesh_get_instance_count(multimesh_rid)
	if allocated_count != current_count:
		RenderingServer.multimesh_allocate_data(multimesh_rid, allocated_count, RenderingServer.MultimeshTransformFormat.MULTIMESH_TRANSFORM_3D, true )
	
	var time_start_loop = Time.get_ticks_usec()
	if node.settings.debug_mode == NodeSettings.eDebugMode.EXTENDS:
		var positions := transforms.positions
		var eulers := transforms.eulers
		var sizes := transforms.sizes
		for idx in range( instance_count ):
			var t := Transform3D( Basis.from_euler( eulers[idx] * PI / 180.0 ), positions[idx] ).scaled_local( sizes[idx] )
			RenderingServer.multimesh_instance_set_transform( multimesh_rid, idx, t)

	elif node.settings.debug_mode == NodeSettings.eDebugMode.ABSOLUTE:
		var abs_scale := Vector3.ONE * node.settings.debug_scale
		var positions := transforms.positions
		var eulers := transforms.eulers
		for idx in range( instance_count ):
			# Inlining the calls reduced from 40ms to 16ms
			var t := Transform3D( Basis.from_euler( eulers[idx] * PI / 180.0 ).scaled( abs_scale ), positions[idx] )
			RenderingServer.multimesh_instance_set_transform( multimesh_rid, idx, t)
	if node.settings.trace: print( "Debug.Loop: %f (%d)" % [ Time.get_ticks_usec() - time_start_loop, instance_count ] )
	setupColors( out_data )

	# Copy the transform and color at Nth and paste it at the end
	if allocated_count != instance_count:
		var t = RenderingServer.multimesh_instance_get_transform( multimesh_rid, debug_row)
		t = t.scaled_local( Vector3.ONE * 1.01 )
		RenderingServer.multimesh_instance_set_transform( multimesh_rid, instance_count, t)
		RenderingServer.multimesh_instance_set_color( multimesh_rid, instance_count, selection_color )
