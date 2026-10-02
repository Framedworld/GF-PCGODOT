## Verbatim copy of nodes/grid.gd before the WP13-P1 performance rewrite
## (base d5bd9b6). Reference implementation for point_seed_stream_test.gd;
## not a registered node. Do not edit.
@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Grid",
		"settings" : GridNodeSettings,
		"ins" : [],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["Create Points Grid", "Create Points"],
		"category" : "Sampler",
		"tooltip" : "Generates a set of points in a grid spatial distribution,\nwhere the separation is step",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var output := FlowData.Data.new()
	var nx : int = getSettingValue( ctx, "x", 3 )
	var ny : int = getSettingValue( ctx, "y", 1 )
	var nz : int = getSettingValue( ctx, "z", 3 )
	var nsamples : int = nx * ny * nz
	output.addCommonStreams( nsamples )
	var spos := output.getVector3Container( FlowData.AttrPosition )
	var srot := output.getVector3Container( FlowData.AttrRotation )
	var ssize := output.getVector3Container( FlowData.AttrSize )
	assert( spos != null )
	#print( "Spos.size %d of type %s" % [ spos.size(), type_string(typeof(spos)) ])
	var idx := 0
	var origin : Vector3 = getSettingValue( ctx, "origin", Vector3.ZERO )
	var rotation : Vector3 = getSettingValue( ctx, "rotation", Vector3.ZERO )
	var step : Vector3 = getSettingValue( ctx, "step", Vector3.ONE )
	var size : Vector3 = Vector3.ONE * getSettingValue( ctx, "size", 1.0 )
	var transform = Transform3D( FlowData.eulerToBasis(rotation), origin )
	for iz in range( 0, nz ):
		for iy in range( 0, ny ):
			for ix in range( 0, nx ):
				var p := Vector3( ix, iy, iz ) * step
				spos[idx] = transform * p
				srot[idx] = rotation
				ssize[idx] = size
				idx += 1

	# Density + per-point seed streams (UE parity)
	var node_seed : int = effective_seed()
	var sdensity := PackedFloat32Array()
	sdensity.resize( nsamples )
	sdensity.fill( 1.0 )
	output.registerStream( FlowData.AttrDensity, sdensity, FlowData.DataType.Float )
	var sseed := PackedInt32Array()
	sseed.resize( nsamples )
	for i in range( nsamples ):
		sseed[i] = FlowData.point_seed( spos[i], node_seed )
	output.registerStream( FlowData.AttrSeed, sseed, FlowData.DataType.Int )

	set_output( 0, output )
