@tool
extends FlowNodeBase

const PhysicsOverlapQuerySettings = preload("res://addons/flow_nodes_editor/nodes/physics_overlap_query_settings.gd")

func _init():
	meta_node = {
		"title" : "Physics Overlap Query",
		"settings" : PhysicsOverlapQuerySettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["World Volumetric Query"],
		"category" : "Spatial",
		"queries_physics" : true,
		"tooltip" : "Runs shape-overlap checks per point against the 3D physics world (Godot-specific query node).\nThe overlap count is capped at Max Results. In the editor the query sees the editor world's physics state, which may lag scene edits until physics frames run.",
	}

func _build_exclude_rids(root : Node) -> Array:
	var excludes : Array = []
	var group_name = settings.exclude_nodes_group.strip_edges()
	if group_name == "":
		return excludes
	var tree = root.get_tree()
	if tree == null:
		return excludes
	for n in tree.get_nodes_in_group(group_name):
		var body = n as CollisionObject3D
		if body:
			excludes.append(body.get_rid())
	return excludes

func _create_query_shape(point_size : Vector3) -> Shape3D:
	if settings.shape_type == PhysicsOverlapQuerySettings.eShapeType.Box:
		var box = BoxShape3D.new()
		var ext = settings.half_extents
		if settings.use_point_size_for_shape:
			ext = point_size * 0.5
		box.size = Vector3(maxf(0.0001, ext.x * 2.0), maxf(0.0001, ext.y * 2.0), maxf(0.0001, ext.z * 2.0))
		return box

	var sphere = SphereShape3D.new()
	var r = settings.radius
	if settings.use_point_size_for_shape:
		r = maxf(point_size.x, maxf(point_size.y, point_size.z)) * 0.5
	sphere.radius = maxf(0.0001, r)
	return sphere

func execute(_ctx : FlowData.EvaluationContext):
	var in_data : FlowData.Data = require_input(0, _ctx)
	if in_data == null:
		return
	if handleMissingOwner(_ctx):
		return

	var root = _ctx.owner if (_ctx and _ctx.owner) else (EditorInterface.get_edited_scene_root() if Engine.is_editor_hint() else null)
	if root == null:
		setError("No scene root available to query the physics world")
		return
	if not root.has_method("get_world_3d"):
		setError("Scene root '%s' is not a Node3D — no 3D physics world to query" % root.name)
		return

	var world = root.get_world_3d()
	if world == null:
		setError("Scene root has no 3D world to query")
		return
	var state = world.direct_space_state
	var in_size = in_data.size()
	if in_size == 0:
		set_output(0, in_data.duplicate())
		return

	var pos_stream = in_data.findStream(settings.position_attribute)
	if pos_stream == null or pos_stream.data_type != FlowData.DataType.Vector:
		setError("Position attribute '%s' must be a Vector stream" % settings.position_attribute)
		return
	if pos_stream.container.size() != in_size and pos_stream.container.size() != 1:
		setError("Position attribute '%s' must have %d values or 1 value (got %d)" % [settings.position_attribute, in_size, pos_stream.container.size()])
		return

	var point_sizes = in_data.getVector3Container(FlowData.AttrSize)
	var has_point_sizes = point_sizes.size() == in_size
	var query = PhysicsShapeQueryParameters3D.new()
	query.collision_mask = settings.collision_mask
	query.collide_with_bodies = settings.collide_with_bodies
	query.collide_with_areas = settings.collide_with_areas
	query.exclude = _build_exclude_rids(root)

	var hit_values := PackedByteArray()
	var count_values := PackedInt32Array()
	var first_colliders : Array = []
	hit_values.resize(in_size)
	count_values.resize(in_size)
	first_colliders.resize(in_size)

	# The shape only varies per point when it follows the point size.
	var shared_shape : Shape3D = null
	if not settings.use_point_size_for_shape:
		shared_shape = _create_query_shape(Vector3.ONE)

	var pos_size : int = pos_stream.container.size()
	for i in range(in_size):
		var pos : Vector3 = pos_stream.container[FlowData.bcast_idx(pos_size, i)]
		var psize = point_sizes[i] if has_point_sizes else Vector3.ONE
		query.shape = shared_shape if shared_shape else _create_query_shape(psize)
		query.transform = Transform3D(Basis.IDENTITY, pos)

		var results : Array = state.intersect_shape(query, settings.max_results)
		var count = results.size()
		hit_values[i] = 1 if count > 0 else 0
		count_values[i] = count
		if count > 0:
			first_colliders[i] = results[0].get("collider", null)

	var out_data = in_data.duplicate()
	if settings.out_hit_attribute.strip_edges() != "":
		out_data.registerStream(settings.out_hit_attribute, hit_values, FlowData.DataType.Bool)
	if settings.out_count_attribute.strip_edges() != "":
		out_data.registerStream(settings.out_count_attribute, count_values, FlowData.DataType.Int)
	if settings.out_first_collider_attribute.strip_edges() != "":
		out_data.registerStream(settings.out_first_collider_attribute, first_colliders, FlowData.DataType.NodePath)

	set_output(0, out_data)
