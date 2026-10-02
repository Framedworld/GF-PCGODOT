@tool
class_name FlowHTerrainAdapter
extends FlowTerrainAdapter

## Duck-typed adapter for the HTerrain plugin (Zylann's godot_heightmap_plugin).
## It never names a plugin class, so it works with an unmodified plugin and
## loads without it. Every call is guarded with has_method / property checks.
## It has only been run against fake classes implementing exactly the members
## listed here (tests/terrain/support/fake_terrain_plugins.gd), never against
## the real plugin.
##
## Members used (godot_heightmap_plugin 1.7.x for Godot 4, as recalled):
##   terrain.get_data() -> HTerrainData
##   terrain.get_internal_transform() -> Transform3D   cell space to world
##       (fallback when absent: the node transform scaled by the `map_scale`
##       property, shifted by half the grid when the `centered` property is true)
##   data.get_resolution() -> int                    samples per side
##   data.get_interpolated_height_at(Vector3) -> float
##       raw height at a fractional cell position (x, z = cell coordinates)
##   data.get_height_at(Vector2i) -> float           raw height of one cell (used
##       for the snapshot when present, else get_interpolated_height_at)
##   data.get_map_count(int) -> int                  number of splat maps
##   data.get_image(int, int) -> Image               map of a type and index
##   HTerrainData.CHANNEL_SPLAT                      script constant (2 when the
##       script does not expose it)
## The contract also named get_heightmap_aabb(); it is not called because its
## existence could not be confirmed. Bounds come from the height snapshot.
##
## Layers: each splat map holds four weights in R, G, B, A (the classic
## four-texture layout); layer k = map * 4 + channel is named "texture_<k>"
## unless options.layer_names renames it. The splat images are read with the
## Sample Terrain Layers convention over the cell grid (UV = cell / (resolution
## - 1)).

const DEFAULT_CHANNEL_SPLAT := 2

var terrain : Object = null
var data : Object = null
var resolution : int = 0
## Cell space (x, height, z) to world.
var xform : Transform3D = Transform3D.IDENTITY

var _inv : Transform3D
var _snapshot : FlowHeightfieldSurface = null
var _with_layers : FlowHeightfieldSurface = null
var _native : FlowSurfaceLayers = null
var _native_built := false

func _init( terrain_node : Object = null, adapter_options : Dictionary = {} ) -> void:
	super._init( adapter_options )
	terrain = terrain_node
	data = FlowTerrainAdapter.hterrain_data( terrain_node )
	if data == null:
		error = "not an HTerrain-like node (get_data() without get_interpolated_height_at / get_resolution)"
		return
	resolution = int( data.call( "get_resolution" ) )
	if resolution < 2:
		error = "terrain resolution %d is too small" % resolution
		return
	xform = _read_transform()
	_inv = xform.affine_inverse()

func get_type_name() -> String:
	return "HTerrain"

func _read_transform() -> Transform3D:
	if terrain.has_method( "get_internal_transform" ):
		var t = terrain.call( "get_internal_transform" )
		if t is Transform3D:
			return t
	var base := Transform3D.IDENTITY
	if terrain is Node3D:
		base = FlowSpatialSources.world_transform( terrain )
	var scale := Vector3.ONE
	if "map_scale" in terrain and terrain.get( "map_scale" ) is Vector3:
		scale = terrain.get( "map_scale" )
	var t := base * Transform3D( Basis.from_scale( scale ), Vector3.ZERO )
	if "centered" in terrain and bool( terrain.get( "centered" ) ):
		t = t * Transform3D( Basis.IDENTITY, Vector3( -( resolution - 1 ) * 0.5, 0.0, -( resolution - 1 ) * 0.5 ) )
	return t

## Height snapshot in cell space (every `step`-th cell, step chosen so at most
## max_resolution samples per side), placed by `xform`.
func _heightfield() -> FlowHeightfieldSurface:
	if _snapshot != null or data == null or resolution < 2:
		return _snapshot
	var step := maxi( 1, int( ceil( float( resolution ) / float( _max_resolution() ) ) ) )
	var n := int( floor( float( resolution - 1 ) / float( step ) ) ) + 1
	var heights := PackedFloat32Array()
	heights.resize( n * n )
	var direct := data.has_method( "get_height_at" )
	for j in range( n ):
		for i in range( n ):
			var cx := i * step
			var cz := j * step
			heights[j * n + i] = float( data.call( "get_height_at", Vector2i( cx, cz ) ) ) if direct else float( data.call( "get_interpolated_height_at", Vector3( cx, 0.0, cz ) ) )
	_snapshot = FlowHeightfieldSurface.new( heights, n, n, float( step ), Vector3.ZERO, xform )
	return _snapshot

func get_bounds() -> AABB:
	var hf := _heightfield()
	return hf.get_bounds() if hf != null else AABB()

func get_sample_spacing() -> float:
	return maxf( 1e-4, maxf( xform.basis.x.length(), xform.basis.z.length() ) )

## Live height: world (x, z) to cell space, clamped onto the grid, then
## get_interpolated_height_at.
func get_height( x : float, z : float ) -> float:
	if data == null:
		return NAN
	var l := _inv * Vector3( x, xform.origin.y, z )
	var cx := clampf( l.x, 0.0, float( resolution - 1 ) )
	var cz := clampf( l.z, 0.0, float( resolution - 1 ) )
	var h := float( data.call( "get_interpolated_height_at", Vector3( cx, 0.0, cz ) ) )
	return ( xform * Vector3( cx, h, cz ) ).y

## Clamped in cell space (the base clamps on the world bounds, which is the
## same for an unrotated terrain); slopes from live heights one cell apart.
func get_normal( x : float, z : float ) -> Vector3:
	if data == null:
		return Vector3.UP
	var l := _inv * Vector3( x, xform.origin.y, z )
	var cx := clampf( l.x, 0.0, float( resolution - 1 ) )
	var cz := clampf( l.z, 0.0, float( resolution - 1 ) )
	var x0 := maxf( cx - 1.0, 0.0 )
	var x1 := minf( cx + 1.0, float( resolution - 1 ) )
	var z0 := maxf( cz - 1.0, 0.0 )
	var z1 := minf( cz + 1.0, float( resolution - 1 ) )
	var hx0 := float( data.call( "get_interpolated_height_at", Vector3( x0, 0.0, cz ) ) )
	var hx1 := float( data.call( "get_interpolated_height_at", Vector3( x1, 0.0, cz ) ) )
	var hz0 := float( data.call( "get_interpolated_height_at", Vector3( cx, 0.0, z0 ) ) )
	var hz1 := float( data.call( "get_interpolated_height_at", Vector3( cx, 0.0, z1 ) ) )
	var sx := ( hx1 - hx0 ) / ( x1 - x0 ) if x1 > x0 else 0.0
	var sz := ( hz1 - hz0 ) / ( z1 - z0 ) if z1 > z0 else 0.0
	return FlowSpatial.transform_normal( xform, Vector3( -sx, 1.0, -sz ).normalized() )

## Cheap summary for scene fingerprints: transform, resolution, live heights on
## a 9 x 9 cell lattice and splat texels at the same cells (no snapshot).
func fingerprint() -> int:
	if data == null:
		return 0
	var items : Array = [ get_type_name(), xform, resolution ]
	var splats : Array = []
	if data.has_method( "get_image" ):
		var channel := _splat_channel()
		var count := int( data.call( "get_map_count", channel ) ) if data.has_method( "get_map_count" ) else 1
		for m in range( count ):
			var img = data.call( "get_image", channel, m )
			if img is Image and not img.is_empty():
				splats.append( img )
	for j in range( 9 ):
		for i in range( 9 ):
			var cx := ( resolution - 1 ) * i / 8.0
			var cz := ( resolution - 1 ) * j / 8.0
			items.append( float( data.call( "get_interpolated_height_at", Vector3( cx, 0.0, cz ) ) ) )
			for img in splats:
				items.append( img.get_pixel( clampi( int( cx * ( img.get_width() - 1 ) / maxf( 1.0, resolution - 1 ) ), 0, img.get_width() - 1 ), clampi( int( cz * ( img.get_height() - 1 ) / maxf( 1.0, resolution - 1 ) ), 0, img.get_height() - 1 ) ) )
	return items.hash()

func _splat_channel() -> int:
	var script = data.get_script() if data != null else null
	if script is Script:
		var consts : Dictionary = script.get_script_constant_map()
		if consts.has( "CHANNEL_SPLAT" ):
			return int( consts["CHANNEL_SPLAT"] )
	return DEFAULT_CHANNEL_SPLAT

## Splat maps as layers over the cell grid.
func _native_layers() -> FlowSurfaceLayers:
	if _native_built:
		return _native
	_native_built = true
	if data == null or not data.has_method( "get_image" ):
		return null
	var channel := _splat_channel()
	var count := int( data.call( "get_map_count", channel ) ) if data.has_method( "get_map_count" ) else 1
	var names := PackedStringArray()
	var images : Array = []
	var channels := PackedInt32Array()
	for m in range( count ):
		var img = data.call( "get_image", channel, m )
		if not ( img is Image ) or img.is_empty():
			continue
		for c in range( 4 ):
			names.append( "texture_%d" % ( m * 4 + c ) )
			images.append( img )
			channels.append( c )
	if names.is_empty():
		return null
	_native = FlowSurfaceLayers.from_images( names, images, channels, Vector2.ZERO, Vector2( resolution - 1, resolution - 1 ), _inv )
	return _native

func _native_layer_names() -> PackedStringArray:
	var l := _native_layers()
	return l.names if l != null else PackedStringArray()

func _native_layer_weight( layer_name : String, x : float, z : float ) -> float:
	var l := _native_layers()
	return l.get_weight( layer_name, x, z ) if l != null else 0.0

func _splat_mapping() -> Dictionary:
	return { "min": Vector2.ZERO, "max": Vector2( resolution - 1, resolution - 1 ), "to_layer": _inv }

## Native splat layers keep their images (no resampling).
func _snapshot_layers( _w : int, _d : int ) -> FlowSurfaceLayers:
	var out : FlowSurfaceLayers = null
	var native := _native_layers()
	if native != null:
		out = native.renamed( _renamed( native.names ) )
	var splat := _splat_layers()
	if splat != null:
		out = splat if out == null else FlowSurfaceLayers.merged( out, splat )
	return out

func to_surface() -> FlowSpatial:
	var hf := _heightfield()
	if hf == null:
		return null
	if _with_layers == null:
		_with_layers = hf.with_tolerance( _tolerance() )
		_with_layers.attach_layers( _snapshot_layers( hf.width, hf.depth ) )
	return _with_layers
