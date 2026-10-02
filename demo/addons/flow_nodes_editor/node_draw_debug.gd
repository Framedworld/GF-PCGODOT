extends Node
class_name NodeDrawDebug

# This script is a separate helper script to store all the code associated with rendering the debug boxes in the 3D viewer
#
# Two layers per node:
#  - point cubes: one MultiMesh instance per point (unchanged behaviour);
#  - debug lines: spatial shapes (splines, boxes, spheres, surfaces, composites)
#    and per-point bounds boxes, built by FlowDebugShapes (pure data
#    preparation, tested numerically) and uploaded here as one PRIMITIVE_LINES
#    mesh with vertex colours.

var node : FlowNodeWidget

# Render
var scenario_rid : RID
var multimesh_rid : RID
var instance_rid : RID
var mesh_resource: Mesh = preload( "res://addons/flow_nodes_editor/resources/unit_cube.tres" )
var selection_color := Color.MAGENTA

# Debug lines (shapes and point bounds)
var lines_mesh_rid : RID
var lines_instance_rid : RID
var lines_material : StandardMaterial3D
## What the last setupDraw() drew as lines (FlowDebugShapes.Lines), or null.
var last_lines = null
# Point colours computed for the bounds boxes, reused by setupColors().
var _line_point_colors := PackedColorArray()
var _line_point_colors_for : FlowData.Data = null
	
func _ready():
	scenario_rid = _resolve_debug_scenario()
	
func _exit_tree():
	cleanup_multimesh_direct()
	cleanup_lines_direct()

func cleanup_lines_direct():
	if lines_instance_rid.is_valid():
		RenderingServer.free_rid(lines_instance_rid)
		lines_instance_rid = RID()
	if lines_mesh_rid.is_valid():
		RenderingServer.free_rid(lines_mesh_rid)
		lines_mesh_rid = RID()
	last_lines = null

## Uploads `lines` (FlowDebugShapes.Lines) as the node's debug line mesh.
## Empty lines free the mesh.
func upload_lines(lines) -> void:
	if lines == null or lines.points.is_empty():
		cleanup_lines_direct()
		last_lines = lines
		return
	if not lines_mesh_rid.is_valid():
		lines_mesh_rid = RenderingServer.mesh_create()
	else:
		RenderingServer.mesh_clear(lines_mesh_rid)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = lines.points
	arrays[Mesh.ARRAY_COLOR] = lines.colors
	RenderingServer.mesh_add_surface_from_arrays(lines_mesh_rid, RenderingServer.PRIMITIVE_LINES, arrays)
	if lines_material == null:
		lines_material = StandardMaterial3D.new()
		lines_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lines_material.vertex_color_use_as_albedo = true
		lines_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	RenderingServer.mesh_surface_set_material(lines_mesh_rid, 0, lines_material.get_rid())
	if not lines_instance_rid.is_valid():
		lines_instance_rid = RenderingServer.instance_create()
		RenderingServer.instance_set_base(lines_instance_rid, lines_mesh_rid)
		RenderingServer.instance_set_transform(lines_instance_rid, Transform3D.IDENTITY)
	if scenario_rid.is_valid():
		RenderingServer.instance_set_scenario(lines_instance_rid, scenario_rid)
	last_lines = lines
	
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
	if lines_instance_rid.is_valid() and scenario_rid.is_valid():
		RenderingServer.instance_set_scenario(lines_instance_rid, scenario_rid)

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
	# Named through Engine's singleton table: exported builds lack EditorInterface
	# and would fail to parse a direct reference, even behind is_editor_hint().
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		var ei : Object = Engine.get_singleton(&"EditorInterface")
		var scene_root := ei.call("get_edited_scene_root") as Node
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
	# Reuse the colours the bounds boxes were drawn with in this setupDraw()
	# (computing them again would report a bad debug_modulate_by twice).
	var colors : PackedColorArray = _line_point_colors if _line_point_colors_for == out_data else compute_point_colors( out_data )
	_line_point_colors_for = null
	_line_point_colors = PackedColorArray()
	for idx in range( colors.size() ):
		RenderingServer.multimesh_instance_set_color( multimesh_rid, idx, colors[idx] )

## Colour of each point cube: grey levels of the modulation stream (see
## _debug_modulation_stream), or debug_color for every point. With a
## modulation stream shorter than the Data, only its entries are coloured
## (the array is that long), as the point cubes always were.
func compute_point_colors( out_data : FlowData.Data ) -> PackedColorArray:
	var instance_count = out_data.size()
	var stream = _debug_modulation_stream(out_data)
	if stream != null:
		var intensities := _stream_to_intensities(stream, instance_count)
		if not intensities.is_empty():
			return grayscale_colors(intensities, node.settings.debug_color.a)
	var out := PackedColorArray()
	out.resize( instance_count )
	out.fill( node.settings.debug_color )
	return out

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
		"type",
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

## Types the debug draw can modulate by: numbers by value, vectors by length,
## colours by luminance.
const MODULATION_TYPES := [
	FlowData.DataType.Bool, FlowData.DataType.Int, FlowData.DataType.Float,
	FlowData.DataType.Int64, FlowData.DataType.Double,
	FlowData.DataType.Vector, FlowData.DataType.Vector2, FlowData.DataType.Vector4,
	FlowData.DataType.Quaternion, FlowData.DataType.Color,
]

static func _can_modulate_stream(stream) -> bool:
	return MODULATION_TYPES.has(int(stream.data_type))

static func _stream_to_intensities(stream, instance_count: int) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	var count: int = mini(instance_count, stream.container.size())
	values.resize(count)
	match int(stream.data_type):
		FlowData.DataType.Bool, FlowData.DataType.Int, FlowData.DataType.Float, FlowData.DataType.Int64, FlowData.DataType.Double:
			for idx in range(count):
				values[idx] = _safe_float(stream.container[idx])
		FlowData.DataType.Vector:
			for idx in range(count):
				var v: Vector3 = stream.container[idx]
				values[idx] = v.length()
		FlowData.DataType.Vector2:
			for idx in range(count):
				var v2: Vector2 = stream.container[idx]
				values[idx] = _safe_float(v2.length())
		FlowData.DataType.Vector4, FlowData.DataType.Quaternion:
			for idx in range(count):
				var v4: Vector4 = stream.container[idx]
				values[idx] = _safe_float(v4.length())
		FlowData.DataType.Color:
			for idx in range(count):
				var c: Color = stream.container[idx]
				values[idx] = c.get_luminance()
		_:
			return PackedFloat32Array()
	return values

## Grey level per value: the values normalised to their range (or clamped to
## 0..1 when they are all equal), mapped to 0.08..1, with `alpha`.
static func grayscale_colors(values: PackedFloat32Array, alpha: float) -> PackedColorArray:
	var out := PackedColorArray()
	if values.is_empty():
		return out

	var min_value := INF
	var max_value := -INF
	for value in values:
		min_value = minf(min_value, value)
		max_value = maxf(max_value, value)

	var span := max_value - min_value
	out.resize(values.size())
	for idx in range(values.size()):
		var normalized := values[idx]
		if span > 0.00001:
			normalized = (values[idx] - min_value) / span
		else:
			normalized = clampf(values[idx], 0.0, 1.0)
		var gray := lerpf(0.08, 1.0, clampf(normalized, 0.0, 1.0))
		out[idx] = Color(gray, gray, gray, alpha)
	return out

static func _safe_float(value) -> float:
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
		"roomid",
		"index",
		"source_index",
		"parent_index",
		"offset_index",
	]

## Options FlowDebugShapes.build_for_data() gets from the node's debug
## settings: debug_color for shapes, the point cube colours (modulation) for
## bounds boxes, bounds boxes only in EXTENDS mode, the inspected row.
func line_options( out_data : FlowData.Data, has_points : bool ) -> Dictionary:
	var s = node.settings
	var extends_mode : bool = s.debug_mode == NodeSettings.eDebugMode.EXTENDS
	var draw_bounds := extends_mode and has_points and FlowDebugShapes.has_point_bounds( out_data )
	return {
		"color": s.debug_color,
		"draw_point_bounds": draw_bounds,
		"point_colors": _point_colors_for_lines( out_data ) if draw_bounds else PackedColorArray(),
		"selected_row": node.debug_row,
		"selection_color": selection_color,
	}

func _point_colors_for_lines( out_data : FlowData.Data ) -> PackedColorArray:
	_line_point_colors = compute_point_colors( out_data )
	_line_point_colors_for = out_data
	return _line_point_colors

func _setup_lines( out_data : FlowData.Data, has_points : bool ) -> void:
	var lines = FlowDebugShapes.build_for_data( out_data, line_options( out_data, has_points ) )
	if node.settings.trace and lines.truncated:
		print( "Debug.Lines truncated: %s" % ", ".join( lines.notes ) )
	upload_lines( lines )

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
	if not out_data:
		cleanup_lines_direct()
		print( "setupDebugDraw failed - out_data" )
		return
	var has_points := out_data.hasStream( FlowData.AttrPosition )
	_setup_lines( out_data, has_points )
	if not has_points:
		# Shape-only Data: the lines are the whole debug draw.
		if multimesh_rid.is_valid():
			RenderingServer.multimesh_allocate_data(multimesh_rid, 0, RenderingServer.MultimeshTransformFormat.MULTIMESH_TRANSFORM_3D, true )
		if out_data.shape == null:
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
