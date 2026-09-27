@tool
extends FlowNodeBase

const NavigationRegionSamplerSettings = preload("res://addons/flow_nodes_editor/nodes/navigation_region_sampler_settings.gd")

func _init():
	meta_node = {
		"title" : "Navigation Region Sampler",
		"settings" : NavigationRegionSamplerSettings,
		"scans_scene" : true,
		"ins" : [],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["Navmesh Sampler"],
		"category" : "Sampler",
		"tooltip" : "Samples Godot NavigationRegion3D meshes into points.\nPolygons mode emits one point per navmesh polygon (with area and surface normal); Vertices mode emits one point per vertex (the polygon-index attribute then holds the vertex index).",
	}

func _scene_root(ctx : FlowData.EvaluationContext) -> Node:
	if Engine.is_editor_hint():
		return editor_edited_scene_root()
	if ctx.owner and ctx.owner.get_tree():
		return ctx.owner.get_tree().current_scene
	return null

func _collect_regions(root : Node) -> Array:
	if root == null:
		return []
	if settings.navigation_region_path != NodePath():
		var node = root.get_node_or_null(settings.navigation_region_path)
		if node and node.is_class("NavigationRegion3D"):
			return [node]
		setError("NavigationRegion path '%s' was not found or is not a NavigationRegion3D" % settings.navigation_region_path)
		return []
	var group : String = settings.group_name.strip_edges()
	if group != "" and root.get_tree():
		var out : Array = []
		for node in root.get_tree().get_nodes_in_group(group):
			if node and node.is_class("NavigationRegion3D"):
				out.append(node)
		if out.is_empty():
			setError("No NavigationRegion3D found in group '%s'" % group)
		return out
	return root.find_children("*", "NavigationRegion3D", true, false)

func _polygon_normal(points : PackedVector3Array) -> Vector3:
	# Newell's method — robust against degenerate triangles in the fan.
	if points.size() < 3:
		return Vector3.ZERO
	var n := Vector3.ZERO
	for i in range(points.size()):
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		n += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
	return n.normalized() if n.length_squared() > 0.0 else Vector3.ZERO

func _polygon_area(points : PackedVector3Array) -> float:
	if points.size() < 3:
		return 0.0
	var origin := points[0]
	var area := 0.0
	for i in range(1, points.size() - 1):
		area += ((points[i] - origin).cross(points[i + 1] - origin)).length() * 0.5
	return area

func computeSceneFingerprint(ctx : FlowData.EvaluationContext) -> Variant:
	var regions = filterOutGeneratedNodes(_collect_regions(_scene_root(ctx)))
	var extra := []
	for region in regions:
		var nav_mesh = region.get("navigation_mesh")
		if nav_mesh:
			extra.append(nav_mesh.get_instance_id())
			if nav_mesh.has_method("get_vertices"):
				extra.append(nav_mesh.get_vertices())
		else:
			extra.append(0)
	return hashSceneNodesForFingerprint(ctx, regions, extra)

func execute(ctx : FlowData.EvaluationContext):
	# Owner-less runtime evaluation: report it, still emit the empty schema.
	reportMissingOwner(ctx)
	var regions := _collect_regions(_scene_root(ctx))
	var positions := PackedVector3Array()
	var rotations := PackedVector3Array()
	var sizes := PackedVector3Array()
	var normals := PackedVector3Array()
	var region_refs : Array = []
	var polygon_indices := PackedInt32Array()
	var areas := PackedFloat32Array()

	for region in regions:
		var nav_mesh = region.get("navigation_mesh")
		if nav_mesh == null:
			continue
		var vertices : PackedVector3Array = nav_mesh.get_vertices() if nav_mesh.has_method("get_vertices") else PackedVector3Array()
		if vertices.is_empty():
			continue
		if settings.sample_mode == NavigationRegionSamplerSettings.eSampleMode.Polygons and nav_mesh.has_method("get_polygon_count") and nav_mesh.has_method("get_polygon"):
			for poly_idx in range(nav_mesh.get_polygon_count()):
				var indices = nav_mesh.get_polygon(poly_idx)
				if indices.size() == 0:
					continue
				var world_pts := PackedVector3Array()
				var center := Vector3.ZERO
				for vertex_idx in indices:
					if int(vertex_idx) < 0 or int(vertex_idx) >= vertices.size():
						continue
					var p = region.global_transform * vertices[int(vertex_idx)]
					world_pts.append(p)
					center += p
				if world_pts.is_empty():
					continue
				center /= float(world_pts.size())
				positions.append(center)
				rotations.append(Vector3.ZERO)
				sizes.append(settings.point_size)
				normals.append(_polygon_normal(world_pts))
				region_refs.append(region)
				polygon_indices.append(poly_idx)
				areas.append(_polygon_area(world_pts))
		else:
			for i in range(vertices.size()):
				positions.append(region.global_transform * vertices[i])
				rotations.append(Vector3.ZERO)
				sizes.append(settings.point_size)
				normals.append(Vector3.ZERO)
				region_refs.append(region)
				polygon_indices.append(i)
				areas.append(0.0)

	var out := FlowData.Data.new()
	out.addCommonStreams(positions.size())
	var op := out.getVector3Container(FlowData.AttrPosition)
	var orot := out.getVector3Container(FlowData.AttrRotation)
	var osize := out.getVector3Container(FlowData.AttrSize)
	for i in range(positions.size()):
		op[i] = positions[i]
		orot[i] = rotations[i]
		osize[i] = sizes[i]
	# Sampler conventions (UE parity): density 1.0 + deterministic per-point seed.
	var densities := PackedFloat32Array()
	densities.resize(positions.size())
	densities.fill(1.0)
	out.registerStream(FlowData.AttrDensity, densities, FlowData.DataType.Float)
	var seeds := PackedInt32Array()
	seeds.resize(positions.size())
	for i in range(positions.size()):
		seeds[i] = FlowData.point_seed(positions[i], effective_seed())
	out.registerStream(FlowData.AttrSeed, seeds, FlowData.DataType.Int)
	if settings.sample_mode == NavigationRegionSamplerSettings.eSampleMode.Polygons and normals.size() == positions.size():
		out.registerStream(FlowData.AttrNormal, normals, FlowData.DataType.Vector)
	if settings.out_region_attribute.strip_edges() != "":
		out.registerStream(settings.out_region_attribute, region_refs, FlowData.DataType.NodePath)
	if settings.out_polygon_index_attribute.strip_edges() != "":
		out.registerStream(settings.out_polygon_index_attribute, polygon_indices, FlowData.DataType.Int)
	if settings.out_area_attribute.strip_edges() != "":
		out.registerStream(settings.out_area_attribute, areas, FlowData.DataType.Float)
	set_output(0, out)
