@tool
extends FlowNodeBase

var blue_noise_image : Image = preload("res://addons/flow_nodes_editor/resources/bluenoise256.png" )

class BNSample:
	var key : int
	var u : float
	var v : float

static var blue_noise_samples : Array[BNSample] = []
# Serializes the one-time table build: FlowExecutor's threaded mode may run
# several sample_points nodes at once (docs/PARITY_ROUND2.md WP1). The table is
# built into a local array and published whole, so readers see it empty or full.
static var _blue_noise_mutex := Mutex.new()

## Streams the sampler generates itself; never inherited from the input points.
const GENERATED_STREAMS := [
	FlowData.AttrPosition, FlowData.AttrRotation, FlowData.AttrRotationQuat,
	FlowData.AttrSize, FlowData.AttrBoundsMin, FlowData.AttrBoundsMax,
	FlowData.AttrDensity, FlowData.AttrSeed,
]

# Parent (input point) index of every generated sample. Filled by the samplers
# only while _track_parents is on (inherit_attributes), so the default path does
# no extra work.
var _track_parents : bool = false
var _sample_parents := PackedInt32Array()

## Marks every sample emitted so far beyond the recorded ones as a child of
## input point `parent_idx`. Called at the end of each input point's iteration.
func _record_parent( parent_idx : int, total_samples : int ) -> void:
	if not _track_parents:
		return
	var from := _sample_parents.size()
	if total_samples <= from:
		return
	_sample_parents.resize( total_samples )
	for k in range( from, total_samples ):
		_sample_parents[k] = parent_idx

func _init():
	meta_node = {
		"title" : "Sample Points",
		"settings" : SamplePointsNodeSettings,
		"aliases" : ["Point Subdivision", "Blue Noise", "Quasi Random Points"],
		"category" : "Sampler",
		"ins" : [{ "label" : "In" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Subdivides each input point into a subgrid of regular points with the specified sampling distance.\nSupports uniform grid, quasi-random (golden ratio) and blue-noise distributions.\nEnable 'Inherit Attributes' to copy each input point's other attributes onto its samples.",
	}
	
func isUniformGridParam( prop ) -> bool:
	return (prop.name as String).begins_with("max") or prop.name == "sampling_distance" or prop.name == "new_size_factor"
	
func exposedAsInputNode( prop ):
	if settings.distribution == SamplePointsNodeSettings.eDistribution.UniformGrid:
		return isUniformGridParam( prop )
	return prop.name == "phase"

func onPropChanged( prop_name : String ):
	super.onPropChanged( prop_name )
	if prop_name == "distribution":
		initFromScript()

func uniformSampling( ctx : FlowData.EvaluationContext, in_trs : FlowData.TransformsStream, output : FlowData.Data ):
		
	var max_samples_x : int = getSettingValue( ctx, "max_x" )
	var max_samples_y : int = getSettingValue( ctx, "max_y" )
	var max_samples_z : int = getSettingValue( ctx, "max_z" )
	var new_size_factor : float = getSettingValue( ctx, "new_size_factor")
	var sampling_distance : float = getSettingValue( ctx, "sampling_distance")
	if sampling_distance <= 0.0:
		setError( "Sampling distance must be greater than zero" )
		return

	var spos := output.getVector3Container( FlowData.AttrPosition )
	var srot := output.getVector3Container( FlowData.AttrRotation )
	var ssize := output.getVector3Container( FlowData.AttrSize )

	# Grid cell extent (spacing * factor) — recorded as bounds; also written to
	# scale when the opt-in legacy bridge is on (restores old size-as-scale).
	var legacy : bool = settings.legacy_scale_from_extent
	var cell_extent : Vector3 = Vector3.ONE * sampling_distance * new_size_factor

	var num_points : int = in_trs.size()
	for i in num_points:
		var in_size := in_trs.sizes[ i ]
		
		var nx : int = max(1, int(in_size.x / sampling_distance))
		var ny : int = max(1, int(in_size.y / sampling_distance))
		var nz : int = max(1, int(in_size.z / sampling_distance))
		
		nx = mini( nx, max_samples_x )
		ny = mini( ny, max_samples_y )
		nz = mini( nz, max_samples_z )
		
		var nsamples : int = nx * ny * nz
		
		var idx := spos.size()
		var new_size := idx + nsamples
		spos.resize( new_size )
		srot.resize( new_size )
		ssize.resize( new_size )

		var origin : Vector3 = in_trs.positions[ i ]
		var rotation : Vector3 = in_trs.eulers[ i ]
		var step : Vector3 = Vector3.ONE * sampling_distance
		var transform = Transform3D( FlowData.eulerToBasis(rotation), origin )
		# Center the grid symmetrically around the origin (even counts included)
		var hx := (nx - 1) * 0.5
		var hy := (ny - 1) * 0.5
		var hz := (nz - 1) * 0.5
		for iz in range( 0, nz ):
			for iy in range( 0, ny ):
				for ix in range( 0, nx ):
					var p := Vector3( ix - hx, iy - hy, iz - hz ) * step
					spos[idx] = transform * p
					srot[idx] = rotation
					# UE parity: unit scale; the cell extent goes to bounds below.
					ssize[idx] = cell_extent if legacy else Vector3.ONE
					idx += 1
		_record_parent( i, idx )

	# Record each cell's extent as bounds, not scale, so spawned meshes are
	# placed at natural size instead of stretched to the cell.
	var npts := spos.size()
	if npts > 0:
		var extents := PackedVector3Array()
		extents.resize( npts )
		extents.fill( cell_extent )
		# Legacy bridge: no bounds streams, exactly as before the size->bounds change.
		if not legacy:
			output.setSymmetricBounds( extents )
	

func uniformDistributedSample1D( n : int, base : float) -> float:
	const g := 1.6180339887498948482
	const a1 : float = 1.0 / g
	var v : float = (base + a1 * n)
	return v - floor(v);
	
# The seed is the base, which should be a number between 0 and 1
# the n is a seq number, starting at zero.
func uniformDistributedSample2D( n : int, base: float) -> Vector2:
	const g := 1.32471795724474602596
	const a1 := 1.0 / g
	const a2 := 1.0 / (g * g)
	var t := Vector2(base + a1 * n, base + a2 * n)
	t.x = t.x - floor(t.x)
	t.y = t.y - floor(t.y)
	return t

func uniformDistributedSample2Das3D( n : int, base: float) -> Vector3:
	var p := uniformDistributedSample2D( n, base )
	return Vector3( p.x, 0, p.y )
	
func uniformDistributedSample3D( n : int, base : float) -> Vector3:
	var q = uniformDistributedSample2D( n, base )
	return Vector3(q.x, rng.randf(), q.y)

func quasiRandomSampling( ctx : FlowData.EvaluationContext, in_trs : FlowData.TransformsStream, output : FlowData.Data ):
	
	var samplerFn : Callable= uniformDistributedSample2Das3D if settings.distribution == SamplePointsNodeSettings.eDistribution.QuasiRandom2D else uniformDistributedSample3D
		
	var spos := output.getVector3Container( FlowData.AttrPosition )
	var srot := output.getVector3Container( FlowData.AttrRotation )
	var ssize := output.getVector3Container( FlowData.AttrSize )
	var phase : float = getSettingValue( ctx, "phase" )
	var point_size : Vector3 = Vector3.ONE * getSettingValue( ctx, "size")
	
	if settings.groups.size() < 1:
		setError( "Define number of points in the group array")
		return
		
	var save_group_id : bool = true if settings.out_group_id else false
	var out_group_container := PackedInt32Array()
	if save_group_id:
		out_group_container = output.addStream( settings.out_group_id, FlowData.DataType.Int )

	var qs_num_samples := 0
	for val : int in settings.groups:
		qs_num_samples += val
		
	if qs_num_samples < 0:
		qs_num_samples = 0
	
	for i : int in in_trs.size():
		
		# Alloc num_samples
		var idx := spos.size()
		var new_size := idx + qs_num_samples
		spos.resize( new_size )
		srot.resize( new_size )
		ssize.resize( new_size )
		if save_group_id:
			out_group_container.resize( new_size )
		
		var origin : Vector3 = in_trs.positions[ i ]
		var rotation : Vector3 = in_trs.eulers[ i ] 
		var size : Vector3 = in_trs.sizes[i]
		var transform = Transform3D( FlowData.eulerToBasis(rotation), origin )
		
		var offset := -size * 0.5
		if settings.distribution == SamplePointsNodeSettings.eDistribution.QuasiRandom2D:
			offset.y = 0.0
			
		var color_idx := 0
		var max_j : int = settings.groups[color_idx]
	
		#print( "num_samples is %d. Max_j starts at %d " % [ qs_num_samples, max_j ] )
		for j : int in qs_num_samples:
			var p : Vector3 = samplerFn.call( j, phase ) * size + offset
			spos[idx] = transform * p
			srot[idx] = rotation
			ssize[idx] = point_size
			if save_group_id:
				# Advance the group cursor, guarded against degenerate group
				# arrays (zero/negative counts or sums below qs_num_samples)
				while j >= max_j and color_idx + 1 < settings.groups.size():
					color_idx += 1
					max_j += settings.groups[ color_idx ]
				out_group_container[idx] = color_idx
			idx += 1
		_record_parent( i, idx )

func precomputeBlueNoiseSamples():
	_blue_noise_mutex.lock()
	if blue_noise_samples.is_empty():
		_build_blue_noise_samples()
	_blue_noise_mutex.unlock()

func _build_blue_noise_samples():
	var samples : Array[BNSample] = []
	# Normalize to RGBA8 so the 4-bytes-per-pixel layout below always holds
	var img : Image = blue_noise_image
	if img.get_format() != Image.FORMAT_RGBA8:
		img = blue_noise_image.duplicate()
		img.convert( Image.FORMAT_RGBA8 )
	var w : int = img.get_width()
	var h : int = img.get_height()
	var data : PackedByteArray = img.get_data()
	var grid_scale_x : float = 1.0 / float(w)
	var grid_scale_z : float = 1.0 / float(h)
	samples.resize( w * h )
	var idx : int = 0
	for z : int in range(h):
		for x : int in range(w):
			var offset = ( z * w + x ) * 4
			var tex_value = data[ offset ]
			var g : int = data[ offset + 1 ]
			var b : int = data[ offset + 2 ]
			var hash : int = g * 256 + b;
			var bns : BNSample = BNSample.new()
			bns.u = x * grid_scale_x
			bns.v = z * grid_scale_z
			bns.key = (tex_value << 16) + hash
			samples[idx] = bns
			idx += 1
	samples.sort_custom( func( a: BNSample, b : BNSample) -> bool:
		return a.key < b.key )
	blue_noise_samples = samples

func blueNoiseSampling( ctx : FlowData.EvaluationContext, in_trs : FlowData.TransformsStream, output : FlowData.Data ):

	var spos := output.getVector3Container( FlowData.AttrPosition )
	var srot := output.getVector3Container( FlowData.AttrRotation )
	var ssize := output.getVector3Container( FlowData.AttrSize )
	var phase : float = getSettingValue( ctx, "phase" )
	var point_size : Vector3 = Vector3.ONE * getSettingValue( ctx, "size")
	var num_samples : int = getSettingValue( ctx, "num_samples" )
	num_samples = maxi( 0, num_samples )

	if blue_noise_samples.size() == 0:
		precomputeBlueNoiseSamples()
	if blue_noise_samples.is_empty():
		setError( "Blue noise samples could not be loaded" )
		return

	var num_bn : int = blue_noise_samples.size()
	for i : int in in_trs.size():

		# Alloc output num_samples
		var idx := spos.size()
		var new_size := idx + num_samples
		spos.resize( new_size )
		srot.resize( new_size )
		ssize.resize( new_size )

		var origin : Vector3 = in_trs.positions[ i ]
		var rotation : Vector3 = in_trs.eulers[ i ]
		var size : Vector3 = in_trs.sizes[i]
		var transform = Transform3D( FlowData.eulerToBasis(rotation), origin )

		var max_size : float = maxf( size.x, size.z )
		var cell_size : Vector3 = Vector3( max_size, 1.0, max_size )

		# Add i + 256 so each point has a potentially different distribution
		var base_j : int = posmod( effective_seed() + i * 256, num_bn )
		var max_x = min( size.x, max_size ) * 0.5
		var max_z = min( size.z, max_size ) * 0.5
		if blue_noise_samples.is_empty():
			return
		for j in range( num_samples ):
			var bn_idx : int = ( j + base_j ) % num_bn
			var bns : BNSample = blue_noise_samples[bn_idx]
			var p := Vector3(bns.u - 0.5, 0, bns.v - 0.5) * cell_size
			if absf( p.x ) > max_x or absf( p.z ) > max_z:
				continue
			spos[idx] = transform * p
			srot[idx] = ( rotation )
			# UE parity: point scale is the configured point_size, independent of
			# the sampling region. Legacy bridge restores the old region multiply.
			ssize[idx] = (point_size * size) if settings.legacy_scale_from_extent else point_size
			idx += 1
			
		spos.resize( idx )
		srot.resize( idx )
		ssize.resize( idx )
		_record_parent( i, idx )
		
# Sampler convention (UE parity): outputs carry a density stream (1.0) and a
# per-point deterministic seed stream derived from the position + node seed.
func registerDensityAndSeedStreams( out_data : FlowData.Data ):
	var sdensity : PackedFloat32Array = out_data.addStream( FlowData.AttrDensity, FlowData.DataType.Float )
	sdensity.fill( 1.0 )
	var sseed : PackedInt32Array = out_data.addStream( FlowData.AttrSeed, FlowData.DataType.Int )
	var spos := out_data.getVector3Container( FlowData.AttrPosition )
	for i in sseed.size():
		sseed[i] = FlowData.point_seed( spos[i], effective_seed() )

## Copies every non-generated input stream onto the samples, gathering each
## sample's value from its parent input point (see _sample_parents).
func inheritInputAttributes( in_data : FlowData.Data, out_data : FlowData.Data ):
	for stream_name in in_data.streams:
		if GENERATED_STREAMS.has( StringName( stream_name ) ) or out_data.streams.has( stream_name ):
			continue
		var istream = in_data.streams[ stream_name ]
		var container
		if istream.container.size() == 1:
			# Broadcast stays broadcast (also covers a single input point).
			container = istream.container.duplicate()
		else:
			container = in_data.filteredStream( istream, _sample_parents )
		if container == null:
			continue
		out_data.registerStream( stream_name, container, istream.data_type )

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input( 0, ctx )
	if in_data == null:
		return
	var out_data := FlowData.Data.new()
	out_data.addCommonStreams( 0 )
	_track_parents = settings.inherit_attributes
	_sample_parents = PackedInt32Array()
	if in_data.size() == 0:
		# Keep the output shape consistent with the non-empty case
		registerDensityAndSeedStreams( out_data )
		if _track_parents:
			inheritInputAttributes( in_data, out_data )
		set_output( 0, out_data )
		return
	var in_trs : FlowData.TransformsStream = in_data.getTransformsStream()
	if in_trs == null:
		setError( "Input does not provide position, rotation or scale streams" )
		return

	# The region each input point is subdivided over = its bounds extent (UE
	# parity). getEffectiveBounds falls back to size when no bounds stream exists,
	# so legacy graphs that encoded the region in `size` still work unchanged,
	# while inputs that now carry unit scale + bounds subdivide the real region.
	var _eb := in_data.getEffectiveBounds()
	var _region := PackedVector3Array()
	_region.resize( in_trs.sizes.size() )
	for _i in _region.size():
		_region[_i] = _eb.max[_i] - _eb.min[_i]
	in_trs.sizes = _region

	if settings.distribution == SamplePointsNodeSettings.eDistribution.BlueNoise2D:
		blueNoiseSampling( ctx, in_trs, out_data )
	else:
		if settings.distribution == SamplePointsNodeSettings.eDistribution.UniformGrid:
			uniformSampling( ctx, in_trs, out_data )
		else:
			quasiRandomSampling( ctx, in_trs, out_data )

	registerDensityAndSeedStreams( out_data )
	if _track_parents:
		inheritInputAttributes( in_data, out_data )
	_track_parents = false
	set_output( 0, out_data )
