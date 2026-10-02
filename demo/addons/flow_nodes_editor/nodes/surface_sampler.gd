@tool
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
		"tooltip" : "Samples points randomly inside the bounds of the input points,\nor across the world-space AABBs of a 'node' mesh stream (Get Landscape Data idiom).\nSurface data (Get Surface Data, composites) is sampled on the surface itself, UE style.",
	}

## UE parity: with use_bounding_shape the node gains a "Bounding Shape" input.
## Off (default) keeps today's single input, so saved parameter-port links keep
## their indices.
func getMeta() -> Dictionary:
	if settings != null and settings.get( "use_bounding_shape" ) == true:
		meta_node.ins = [{ "label": "In" }, { "label": "Bounding Shape" }]
	else:
		meta_node.ins = [{ "label": "In" }]
	return meta_node

## Rebuild the ports when the setting that changes them is edited (same
## pattern as sample_points). Guarded with has_method so the element stays valid
## when the port-building code lives on an editor widget.
func onPropChanged( prop_name : String ):
	super.onPropChanged( prop_name )
	if prop_name == "use_bounding_shape" and has_method( "initFromScript" ):
		call( "initFromScript" )

## The bounding input as a shape (spatial data, or point boxes), or null.
func _bounding_shape() -> FlowSpatial:
	if settings.get( "use_bounding_shape" ) != true:
		return null
	var raw = get_optional_input( 1 )
	if not ( raw is FlowData.Data ):
		return null
	if raw.shape != null:
		return raw.shape
	if raw.size() > 0 and raw.hasStream( FlowData.AttrPosition ):
		return FlowPointsVolume.from_data( raw )
	return null

## Surface data input: sample the surface itself (FlowSpatial.sample_surface),
## restricted to the bounding shape when one is connected.
func _execute_shape( ctx : FlowData.EvaluationContext, in_data : FlowData.Data, seed_val : int ) -> void:
	var shape : FlowSpatial = in_data.shape
	if shape.get_kind() != FlowData.Kind.Surface:
		setError( "Surface Sampler needs surface data; got %s (use Volume Sampler, Sample Spline or To Point)" % shape.get_type_name() )
		return
	var bounding := _bounding_shape()
	if bounding != null:
		shape = FlowCompositeShape.new( FlowSpatial.Op.Intersection, shape, bounding, FlowSpatial.DENSITY_BINARY )
	var opts := {
		"points_per_square_meter": float( getSettingValue( ctx, "points_per_square_meter", 0.1 ) ),
		"point_extents": getSettingValue( ctx, "point_extents", Vector3.ONE ),
		"looseness": float( getSettingValue( ctx, "looseness", 1.0 ) ),
		"apply_density": bool( getSettingValue( ctx, "apply_density_to_points", true ) ),
		"point_steepness": float( getSettingValue( ctx, "point_steepness", 0.5 ) ),
		"keep_zero_density": bool( getSettingValue( ctx, "keep_zero_density_points", false ) ),
		"align_to_normal": bool( getSettingValue( ctx, "align_to_normal", false ) ),
		"point_size": getSettingValue( ctx, "point_size", Vector3.ONE ),
		"max_candidates": int( getSettingValue( ctx, "max_candidates", FlowSpatial.DEFAULT_MAX_CANDIDATES ) ),
		"seed": seed_val,
	}
	if settings.get( "shape_sampling" ) == SurfaceSamplerNodeSettings.eShapeSampling.Count:
		opts["num_points"] = maxi( 0, int( getSettingValue( ctx, "num_points", 40 ) ) )
	var errors : Array = []
	var out := FlowSpatial.sample_surface( shape, opts, errors )
	if errors.size() > 0:
		setError( errors[0] )
	out.tags = in_data.tags.duplicate()
	out.data_attrs = in_data.data_attrs.duplicate( true )
	set_output( 0, out )

## Point inputs with a bounding shape: keep the samples inside it, scaling their
## density by the bounding density.
func _apply_bounding( out_data : FlowData.Data, bounding : FlowSpatial ) -> FlowData.Data:
	var positions := out_data.getVector3Container( FlowData.AttrPosition )
	var dens : PackedFloat32Array = out_data.getContainerChecked( FlowData.AttrDensity, FlowData.DataType.Float )
	var keep := PackedInt32Array()
	for i in range( positions.size() ):
		var b := bounding.sample_density( positions[i] )
		if b > 0.0:
			dens[i] = dens[i] * b
			keep.append( i )
	out_data.registerStream( FlowData.AttrDensity, dens, FlowData.DataType.Float )
	return out_data.filter( keep )

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input(0, ctx, "Input 'In'")
	if in_data == null:
		return
	if in_data.shape != null:
		_execute_shape(ctx, in_data, derive_seed(graph_seed, int(getSettingValue(ctx, "random_seed", 12345))))
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

	var bounding := _bounding_shape()
	if bounding != null:
		out_data = _apply_bounding(out_data, bounding)

	set_output(0, out_data)
