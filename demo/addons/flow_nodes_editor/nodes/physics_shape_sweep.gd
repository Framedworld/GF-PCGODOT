@tool
extends FlowNodeBase

const PhysicsShapeSweepSettings = preload("res://addons/flow_nodes_editor/nodes/physics_shape_sweep_settings.gd")

func _init():
	meta_node = {
		"title" : "Physics Shape Sweep",
		"settings" : PhysicsShapeSweepSettings,
		"ins" : [{ "label" : "In" }],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["Shape Sweep", "Shape Trace"],
		"category" : "Spatial",
		"queries_physics" : true,
		"tooltip" : "Sweeps a sphere or box from each point through the Godot physics world.",
	}

func _scene_root(ctx : FlowData.EvaluationContext) -> Node:
	if Engine.is_editor_hint():
		return EditorInterface.get_edited_scene_root()
	if ctx.owner and ctx.owner.get_tree():
		return ctx.owner
	return null

func _build_exclude_rids(root : Node) -> Array:
	var excludes : Array = []
	var group : String = settings.exclude_nodes_group.strip_edges()
	if group == "" or root == null or root.get_tree() == null:
		return excludes
	for node in root.get_tree().get_nodes_in_group(group):
		var body := node as CollisionObject3D
		if body:
			excludes.append(body.get_rid())
	return excludes

func _create_shape(point_size : Vector3) -> Shape3D:
	if settings.shape_type == PhysicsShapeSweepSettings.eShapeType.Box:
		var box := BoxShape3D.new()
		var ext : Vector3 = point_size * 0.5 if settings.use_point_size_for_shape else settings.half_extents
		box.size = Vector3(maxf(0.0001, ext.x * 2.0), maxf(0.0001, ext.y * 2.0), maxf(0.0001, ext.z * 2.0))
		return box
	var sphere := SphereShape3D.new()
	var r : float = maxf(point_size.x, maxf(point_size.y, point_size.z)) * 0.5 if settings.use_point_size_for_shape else settings.radius
	sphere.radius = maxf(0.0001, r)
	return sphere

func _resolve_vector_stream(in_data : FlowData.Data, name : String, in_size : int):
	var attr : String = name.strip_edges()
	if attr == "":
		return null
	var stream = in_data.findStream(attr)
	if stream == null:
		setError("Direction attribute '%s' not found" % attr)
		return null
	if stream.data_type != FlowData.DataType.Vector:
		setError("Direction attribute '%s' must be a Vector stream" % attr)
		return null
	if stream.container.size() != in_size and stream.container.size() != 1:
		setError("Direction attribute '%s' must have %d values or 1 value (got %d)" % [attr, in_size, stream.container.size()])
		return null
	return stream.container

func _resolve_scalar_stream(in_data : FlowData.Data, name : String, in_size : int):
	var attr : String = name.strip_edges()
	if attr == "":
		return null
	var stream = in_data.findStream(attr)
	if stream == null:
		setError("Distance attribute '%s' not found" % attr)
		return null
	if stream.data_type != FlowData.DataType.Float and stream.data_type != FlowData.DataType.Int:
		setError("Distance attribute '%s' must be Float or Int" % attr)
		return null
	if stream.container.size() != in_size and stream.container.size() != 1:
		setError("Distance attribute '%s' must have %d values or 1 value (got %d)" % [attr, in_size, stream.container.size()])
		return null
	return stream

func execute(ctx : FlowData.EvaluationContext):
	var in_data : FlowData.Data = require_input(0, ctx)
	if in_data == null:
		return
	var in_size := in_data.size()
	if in_size == 0:
		set_output(0, in_data.duplicate())
		return
	var root := _scene_root(ctx)
	if root == null:
		setError("No scene root available to query the physics world")
		return
	if not root.has_method("get_world_3d"):
		setError("Scene root '%s' is not a Node3D — no 3D physics world to query" % root.name)
		return
	if root.get_world_3d() == null:
		setError("Scene root has no 3D world to query")
		return
	var state = root.get_world_3d().direct_space_state
	var positions = in_data.getContainerChecked(settings.position_attribute, FlowData.DataType.Vector)
	if positions == null or (positions.size() != in_size and positions.size() != 1):
		setError("Position attribute '%s' must be a Vector stream with %d values or 1 value" % [settings.position_attribute, in_size])
		return
	var pos_size : int = positions.size()

	var directions = null
	if settings.direction_mode == PhysicsShapeSweepSettings.eDirectionMode.FromAttribute:
		directions = _resolve_vector_stream(in_data, settings.direction_attribute, in_size)
		if directions == null:
			if settings.direction_attribute.strip_edges() == "":
				setError("Direction mode is FromAttribute but no direction attribute is set")
			return
	var distances = null
	if settings.distance_attribute.strip_edges() != "":
		distances = _resolve_scalar_stream(in_data, settings.distance_attribute, in_size)
		if distances == null:
			return
	var point_sizes = in_data.getVector3Container(FlowData.AttrSize)
	var has_point_sizes := point_sizes.size() == in_size

	var out_positions := PackedVector3Array()
	out_positions.resize(in_size)
	for i in range(in_size):
		out_positions[i] = positions[FlowData.bcast_idx(pos_size, i)]
	var hits := PackedByteArray()
	var safe_fractions := PackedFloat32Array()
	var unsafe_fractions := PackedFloat32Array()
	var colliders : Array = []
	hits.resize(in_size)
	safe_fractions.resize(in_size)
	unsafe_fractions.resize(in_size)
	colliders.resize(in_size)

	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = settings.collision_mask
	query.collide_with_bodies = settings.collide_with_bodies
	query.collide_with_areas = settings.collide_with_areas
	query.exclude = _build_exclude_rids(root)

	# The shape only varies per point when it follows the point size.
	var shared_shape : Shape3D = null
	if not settings.use_point_size_for_shape:
		shared_shape = _create_shape(Vector3.ONE)

	for i in range(in_size):
		var ppos : Vector3 = positions[FlowData.bcast_idx(pos_size, i)]
		var dir : Vector3 = settings.direction
		if directions != null:
			dir = directions[FlowData.bcast_idx(directions.size(), i)]
		if dir.length_squared() > 0.0000001:
			dir = dir.normalized()
		var dist : float = settings.distance
		if distances != null:
			dist = float(distances.container[FlowData.bcast_idx(distances.container.size(), i)])
		var motion := dir * maxf(0.0, dist)
		query.shape = shared_shape if shared_shape else _create_shape(point_sizes[i] if has_point_sizes else Vector3.ONE)
		query.transform = Transform3D(Basis.IDENTITY, ppos)
		query.motion = motion
		var result : PackedFloat32Array = state.cast_motion(query)
		var safe := 1.0
		var unsafe := 1.0
		if result.size() >= 2:
			safe = result[0]
			unsafe = result[1]
		var hit := unsafe < 1.0
		hits[i] = 1 if hit else 0
		safe_fractions[i] = safe
		unsafe_fractions[i] = unsafe
		out_positions[i] = ppos + motion * safe
		if hit and settings.out_collider_attribute.strip_edges() != "":
			# Query the rest info at the UNSAFE (penetrating) fraction — at the
			# safe fraction the shape is by definition just-not-touching and
			# get_rest_info would frequently come back empty.
			query.transform = Transform3D(Basis.IDENTITY, ppos + motion * unsafe)
			query.motion = Vector3.ZERO
			var rest : Dictionary = state.get_rest_info(query)
			if rest:
				colliders[i] = rest.get("collider", null)

	var out := in_data.duplicate()
	if settings.out_position_attribute.strip_edges() != "":
		out.registerStream(settings.out_position_attribute, out_positions, FlowData.DataType.Vector)
	if settings.out_hit_attribute.strip_edges() != "":
		out.registerStream(settings.out_hit_attribute, hits, FlowData.DataType.Bool)
	if settings.out_safe_fraction_attribute.strip_edges() != "":
		out.registerStream(settings.out_safe_fraction_attribute, safe_fractions, FlowData.DataType.Float)
	if settings.out_unsafe_fraction_attribute.strip_edges() != "":
		out.registerStream(settings.out_unsafe_fraction_attribute, unsafe_fractions, FlowData.DataType.Float)
	if settings.out_collider_attribute.strip_edges() != "":
		out.registerStream(settings.out_collider_attribute, colliders, FlowData.DataType.NodePath)
	set_output(0, out)
