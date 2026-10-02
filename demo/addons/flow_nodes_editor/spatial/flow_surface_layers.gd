@tool
class_name FlowSurfaceLayers
extends RefCounted

## Paint-layer weights of a surface (UE landscape layer weights), carried by a
## surface shape (FlowHeightfieldSurface.layers, FlowMeshSurface.layers) so that
## samplers can write one weight attribute per layer onto the points they make.
##
## Immutable value object, like every FlowSpatial: the weights are copied into
## float grids at construction, so queries are pure reads (thread safe) and a
## later edit of the terrain or its splat images never changes a cached result.
##
## Lookup convention (the one Sample Terrain Layers uses, wrap mode Clamp):
##   local = world_to_layer * Vector3(x, 0, z)          (identity by default)
##   uv    = ((local.x - min.x) / (max.x - min.x), (local.z - min.y) / (max.y - min.y))
##   uv    clamped to [0, 1]
##   pixel = (clampi(floor(uv.x * (width - 1)), 0, width - 1), same for depth)
## i.e. nearest-lower texel, no filtering, each layer at its own resolution.
## Grid index is j * width + i, with i along local X and j along local Z (image
## x and y).

var names : PackedStringArray
## One PackedFloat32Array of weights (0..1) per name, row-major.
var grids : Array = []
## Grid size (width, depth) of each layer.
var sizes : Array = []
## Layer-space XZ rectangle mapped to UV 0..1 (x = X, y = Z).
var world_min : Vector2 = Vector2.ZERO
var world_max : Vector2 = Vector2.ONE
## World to layer space (identity for axis-aligned world rectangles; a terrain
## node's inverse transform for rotated or scaled terrains).
var world_to_layer : Transform3D = Transform3D.IDENTITY

var _index : Dictionary = {}
var _hash : int = 0

## `layer_sizes`: one Vector2i(width, depth) per layer, or a single entry shared
## by every layer.
func _init( layer_names : PackedStringArray = PackedStringArray(), layer_grids : Array = [], layer_sizes : Array = [], rect_min : Vector2 = Vector2.ZERO, rect_max : Vector2 = Vector2.ONE, to_layer : Transform3D = Transform3D.IDENTITY ) -> void:
	names = layer_names.duplicate()
	world_min = rect_min
	world_max = rect_max
	world_to_layer = to_layer
	for i in range( names.size() ):
		var sz := Vector2i.ZERO
		if i < layer_sizes.size():
			sz = layer_sizes[i]
		elif layer_sizes.size() == 1:
			sz = layer_sizes[0]
		sz = Vector2i( maxi( 0, sz.x ), maxi( 0, sz.y ) )
		var g := PackedFloat32Array()
		if i < layer_grids.size() and layer_grids[i] is PackedFloat32Array:
			g = ( layer_grids[i] as PackedFloat32Array ).duplicate()
		g.resize( sz.x * sz.y )
		grids.append( g )
		sizes.append( sz )
		_index[ names[i] ] = i
	_hash = hash( [ "surface_layers", names, grids, sizes, world_min, world_max, FlowSpatial.hash_transform( world_to_layer ) ] )

func content_hash() -> int:
	return _hash

func is_empty() -> bool:
	return names.is_empty()

func has_layer( layer_name : String ) -> bool:
	return _index.has( layer_name )

func layer_index( layer_name : String ) -> int:
	return int( _index.get( layer_name, -1 ) )

## Clamped UV of world (x, z), or Vector2(-1, -1) when the mapping is degenerate.
func world_to_uv( x : float, z : float ) -> Vector2:
	var range_x : float = world_max.x - world_min.x
	var range_z : float = world_max.y - world_min.y
	if absf( range_x ) < 1e-6 or absf( range_z ) < 1e-6:
		return Vector2( -1.0, -1.0 )
	var p := world_to_layer * Vector3( x, 0.0, z )
	var uv := Vector2( ( p.x - world_min.x ) / range_x, ( p.z - world_min.y ) / range_z )
	return Vector2( clampf( uv.x, 0.0, 1.0 ), clampf( uv.y, 0.0, 1.0 ) )

func _texel( li : int, uv : Vector2 ) -> float:
	var sz : Vector2i = sizes[li]
	if sz.x <= 0 or sz.y <= 0 or uv.x < 0.0:
		return 0.0
	var px : int = clampi( int( floor( uv.x * float( sz.x - 1 ) ) ), 0, sz.x - 1 )
	var py : int = clampi( int( floor( uv.y * float( sz.y - 1 ) ) ), 0, sz.y - 1 )
	return ( grids[li] as PackedFloat32Array )[py * sz.x + px]

## Weight of `layer_name` at world (x, z); 0 for an unknown layer.
func get_weight( layer_name : String, x : float, z : float ) -> float:
	var li := layer_index( layer_name )
	if li < 0:
		return 0.0
	return _texel( li, world_to_uv( x, z ) )

## Every layer's weight at world (x, z), in `names` order.
func get_weights( x : float, z : float ) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize( names.size() )
	var uv := world_to_uv( x, z )
	for li in range( names.size() ):
		out[li] = _texel( li, uv )
	return out

## Writes one Float stream per layer (`prefix + name`) onto `data`, sampled at
## its positions. Returns the first registerStream error, or "".
func write_streams( data : FlowData.Data, prefix : String ) -> String:
	var positions := data.getVector3Container( FlowData.AttrPosition )
	var n := positions.size()
	var values : Array = []
	for li in range( names.size() ):
		var v := PackedFloat32Array()
		v.resize( n )
		values.append( v )
	for i in range( n ):
		var uv := world_to_uv( positions[i].x, positions[i].z )
		for li in range( names.size() ):
			values[li][i] = _texel( li, uv )
	for li in range( names.size() ):
		var err = data.registerStream( prefix + names[li], values[li], FlowData.DataType.Float )
		if err:
			return str( err )
	return ""

# --- builders ---------------------------------------------------------------------------

## Channel of a Color, with the Sample Terrain Layers channel numbering
## (0 R, 1 G, 2 B, 3 A, 4 luminance).
static func channel_value( c : Color, channel : int ) -> float:
	match channel:
		0:
			return c.r
		1:
			return c.g
		2:
			return c.b
		3:
			return c.a
		_:
			return c.get_luminance()

## Weights read from images, one image and channel per layer, each covering
## the world XZ rectangle [rect_min, rect_max] at its own resolution (lookups
## then match Sample Terrain Layers texel for texel). Null or empty images give
## zero weights.
static func from_images( layer_names : PackedStringArray, images : Array, channels : PackedInt32Array, rect_min : Vector2, rect_max : Vector2, to_layer : Transform3D = Transform3D.IDENTITY ) -> FlowSurfaceLayers:
	var grids_out : Array = []
	var sizes_out : Array = []
	for li in range( layer_names.size() ):
		var img : Image = images[li] if li < images.size() and images[li] is Image else null
		var g := PackedFloat32Array()
		if img == null or img.is_empty():
			grids_out.append( g )
			sizes_out.append( Vector2i.ZERO )
			continue
		if img.is_compressed():
			img = img.duplicate()
			img.decompress()
		var w := img.get_width()
		var d := img.get_height()
		var ch : int = channels[li] if li < channels.size() else 0
		g.resize( w * d )
		for j in range( d ):
			for i in range( w ):
				g[j * w + i] = channel_value( img.get_pixel( i, j ), ch )
		grids_out.append( g )
		sizes_out.append( Vector2i( w, d ) )
	return FlowSurfaceLayers.new( layer_names, grids_out, sizes_out, rect_min, rect_max, to_layer )

## Snapshot of `weight_fn.call(name, x, z) -> float` on a grid_width x grid_depth
## lattice of world positions spanning [rect_min, rect_max] (corners included).
static func from_function( layer_names : PackedStringArray, weight_fn : Callable, rect_min : Vector2, rect_max : Vector2, grid_width : int, grid_depth : int ) -> FlowSurfaceLayers:
	var w := maxi( 1, grid_width )
	var d := maxi( 1, grid_depth )
	var grids_out : Array = []
	for li in range( layer_names.size() ):
		var g := PackedFloat32Array()
		g.resize( w * d )
		grids_out.append( g )
	for j in range( d ):
		var z := lerpf( rect_min.y, rect_max.y, float( j ) / float( maxi( 1, d - 1 ) ) )
		for i in range( w ):
			var x := lerpf( rect_min.x, rect_max.x, float( i ) / float( maxi( 1, w - 1 ) ) )
			for li in range( layer_names.size() ):
				grids_out[li][j * w + i] = clampf( float( weight_fn.call( layer_names[li], x, z ) ), 0.0, 1.0 )
	return FlowSurfaceLayers.new( layer_names, grids_out, [ Vector2i( w, d ) ], rect_min, rect_max )

## Same layers with new names (missing names keep the old one).
func renamed( new_names : PackedStringArray ) -> FlowSurfaceLayers:
	var out_names := names.duplicate()
	for i in range( mini( new_names.size(), out_names.size() ) ):
		if new_names[i] != "":
			out_names[i] = new_names[i]
	return FlowSurfaceLayers.new( out_names, grids, sizes, world_min, world_max, world_to_layer )

## Layers of `a` followed by the layers of `b` whose names `a` lacks (each keeps
## its own mapping only when both share it; otherwise use separate shapes).
static func merged( a : FlowSurfaceLayers, b : FlowSurfaceLayers ) -> FlowSurfaceLayers:
	if a == null:
		return b
	if b == null:
		return a
	var out_names := a.names.duplicate()
	var out_grids := a.grids.duplicate()
	var out_sizes := a.sizes.duplicate()
	for i in range( b.names.size() ):
		if not a.has_layer( b.names[i] ):
			out_names.append( b.names[i] )
			out_grids.append( b.grids[i] )
			out_sizes.append( b.sizes[i] )
	return FlowSurfaceLayers.new( out_names, out_grids, out_sizes, a.world_min, a.world_max, a.world_to_layer )
