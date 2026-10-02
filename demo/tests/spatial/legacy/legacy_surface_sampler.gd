@tool
# FROZEN COPY of res://addons/flow_nodes_editor/nodes/surface_sampler.gd at commit 17c4524 (before
# WP2 spatial data). Loaded lazily (this folder is .gdignore-d, like tests/evaluator/probe_nodes) by
# tests/spatial/spatial_legacy_paths_test.gd to prove the
# current node produces byte-identical output for point inputs and default
# settings. Never edit; never register as a template.
extends FlowNodeBase

const SurfaceSamplerNodeSettings = preload("res://addons/flow_nodes_editor/nodes/surface_sampler_settings.gd")

func _init():
	meta_node = {
		"title" : "Surface Sampler",
		"settings" : SurfaceSamplerNodeSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["Surface Sampler"],
		"category" : "Sampler",
		"tooltip" : "Samples points randomly inside the bounds of the input points,\nor across the world-space AABBs of a 'node' mesh stream (Get Landscape Data idiom).",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input(0, ctx, "Input 'In'")
	if in_data == null:
		return
	if in_data.size() == 0:
		set_output(0, FlowData.Data.new())
		return
		
	# Sampling regions: either point transforms (position/rotation/size), or —
	# UE parity for the Get Landscape Data -> Surface Sampler idiom — a 'node'
	# stream of MeshInstance3Ds (from scan_meshes), whose world-space AABBs
	# become the regions to sample.
	var centers : PackedVector3Array = PackedVector3Array()
	var sizes : PackedVector3Array = PackedVector3Array()
	var eulers : PackedVector3Array = PackedVector3Array()
	var in_trs = in_data.getTransformsStream()
	if in_trs != null:
		for i in range(in_trs.size()):
			centers.append(in_trs.positions[i])
			sizes.append(in_trs.sizes[i])
			eulers.append(in_trs.eulers[i])
	else:
		var node_stream = in_data.findStream("node")
		if node_stream == null:
			setError("Input does not provide position/rotation/size streams or a 'node' mesh stream")
			return
		for obj in node_stream.container:
			var mi := obj as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var aabb : AABB = mi.mesh.get_aabb()
			var gt : Transform3D = mi.global_transform
			centers.append(gt * aabb.get_center())
			sizes.append(aabb.size * gt.basis.get_scale())
			eulers.append(FlowData.basisToEuler(gt.basis.orthonormalized()))
		if centers.is_empty():
			setError("'node' stream contains no MeshInstance3D with a mesh")
			return

	var seed_val = derive_seed(graph_seed, int(getSettingValue(ctx, "random_seed", 12345)))
	var num_pts = getSettingValue(ctx, "num_points", 40)
	var pt_size = getSettingValue(ctx, "point_size", Vector3.ONE)

	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val

	var out_data := FlowData.Data.new()
	out_data.addCommonStreams(0)

	var spos := out_data.getVector3Container(FlowData.AttrPosition)
	var srot := out_data.getVector3Container(FlowData.AttrRotation)
	var ssize := out_data.getVector3Container(FlowData.AttrSize)

	var total_samples = centers.size() * num_pts
	spos.resize(total_samples)
	srot.resize(total_samples)
	ssize.resize(total_samples)

	var idx = 0
	for i in range(centers.size()):
		var center = centers[i]
		var size = sizes[i]
		var rotation = eulers[i]
		var basis = FlowData.eulerToBasis(rotation)
		
		var half_size = size * 0.5
		
		for j in range(num_pts):
			# Generate local point in [-half_size, half_size]
			var lx = rng.randf_range(-half_size.x, half_size.x)
			var ly = rng.randf_range(-half_size.y, half_size.y)
			var lz = rng.randf_range(-half_size.z, half_size.z)
			var local_pt = Vector3(lx, ly, lz)
			
			# Transform to world space
			spos[idx] = center + (basis * local_pt)
			srot[idx] = rotation
			ssize[idx] = pt_size
			idx += 1

	# Density + per-point seed streams (UE parity)
	var sdensity := PackedFloat32Array()
	sdensity.resize(total_samples)
	sdensity.fill(1.0)
	out_data.registerStream(FlowData.AttrDensity, sdensity, FlowData.DataType.Float)
	var sseed := PackedInt32Array()
	sseed.resize(total_samples)
	for i in range(total_samples):
		sseed[i] = FlowData.point_seed(spos[i], seed_val)
	out_data.registerStream(FlowData.AttrSeed, sseed, FlowData.DataType.Int)

	set_output(0, out_data)
