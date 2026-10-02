@tool
class_name FlowHeightfieldSurface
extends FlowSpatial

## Height-field surface (UE `UPCGLandscapeData` equivalent): a regular grid of
## heights. Sample (i, j) sits at local (origin.x + i * cell_size,
## origin.y + height, origin.z + j * cell_size); `transform` maps local space to
## world space (a CollisionShape3D's global transform, for instance).
##
## The grid IS the acceleration structure: every query indexes its cell
## directly (O(1)), heights are bilinear, normals come from the bilinear gradient.
## "Vertical" means the local Y axis. Outside the grid footprint project() and
## project_vertical() miss and sample_density() is 0. NaN heights are holes
## (Terrain3D reports NaN there): a cell touching a NaN sample misses too.
##
## Builders: from_heightmap_shape (HeightMapShape3D + transform) and from_image
## (a heightmap Image, red channel or luminance, scaled by height_scale).

var heights : PackedFloat32Array
var width : int = 0		# samples along local X
var depth : int = 0		# samples along local Z
var cell_size : float = 1.0
var origin : Vector3 = Vector3.ZERO
var transform : Transform3D = Transform3D.IDENTITY
var vertical_tolerance : float = -1.0
## Optional paint-layer weights (terrain adapters). Set only through
## attach_layers() by a builder, before the shape is shared.
var layers : FlowSurfaceLayers = null

var _inv : Transform3D
var _bounds : AABB

func _init( height_values : PackedFloat32Array = PackedFloat32Array(), map_width : int = 0, map_depth : int = 0, cell : float = 1.0, local_origin : Vector3 = Vector3.ZERO, xform : Transform3D = Transform3D.IDENTITY, tolerance : float = -1.0 ) -> void:
	width = maxi( 0, map_width )
	depth = maxi( 0, map_depth )
	heights = height_values.duplicate()
	heights.resize( width * depth )
	cell_size = maxf( cell, 1e-6 )
	origin = local_origin
	transform = xform
	vertical_tolerance = tolerance
	_inv = transform.affine_inverse()
	_bounds = AABB()
	if width > 0 and depth > 0:
		var hmin := INF
		var hmax := -INF
		for h in heights:
			if is_nan( h ):
				continue
			hmin = minf( hmin, h )
			hmax = maxf( hmax, h )
		if hmin > hmax:
			hmin = 0.0
			hmax = 0.0
		var local := AABB( origin + Vector3( 0.0, hmin, 0.0 ), Vector3( ( width - 1 ) * cell_size, hmax - hmin, ( depth - 1 ) * cell_size ) )
		_bounds = transform * local
	_hash = hash( [ "heightfield", heights, width, depth, cell_size, origin, FlowSpatial.hash_transform( transform ), vertical_tolerance ] )

## From a HeightMapShape3D (centred on its CollisionShape3D, one unit per cell,
## as Godot's physics uses it) placed by `xform`.
static func from_heightmap_shape( shape : HeightMapShape3D, xform : Transform3D = Transform3D.IDENTITY ) -> FlowHeightfieldSurface:
	if shape == null:
		return null
	var w := shape.map_width
	var d := shape.map_depth
	var local_origin := Vector3( -( w - 1 ) * 0.5, 0.0, -( d - 1 ) * 0.5 )
	return FlowHeightfieldSurface.new( shape.map_data, w, d, 1.0, local_origin, xform )

## From a heightmap Image: pixel (x, y) is sample (i = x, j = y), height =
## red channel (0..1 for 8-bit formats, raw value for float formats) * height_scale.
## `centered` places the grid centre at the local origin.
static func from_image( image : Image, cell : float = 1.0, height_scale : float = 1.0, xform : Transform3D = Transform3D.IDENTITY, centered : bool = true ) -> FlowHeightfieldSurface:
	if image == null or image.is_empty():
		return null
	var img := image
	if img.is_compressed():
		img = image.duplicate()
		img.decompress()
	var w := img.get_width()
	var d := img.get_height()
	var values := PackedFloat32Array()
	values.resize( w * d )
	for j in range( d ):
		for i in range( w ):
			values[j * w + i] = img.get_pixel( i, j ).r * height_scale
	var local_origin := Vector3( -( w - 1 ) * 0.5 * cell, 0.0, -( d - 1 ) * 0.5 * cell ) if centered else Vector3.ZERO
	return FlowHeightfieldSurface.new( values, w, d, cell, local_origin, xform )

## Builder step: attach paint layers and fold them into the content hash.
## Call once, right after construction; shapes are immutable once shared.
func attach_layers( surface_layers : FlowSurfaceLayers ) -> FlowHeightfieldSurface:
	layers = surface_layers
	if layers != null:
		_hash = hash( [ _hash, layers.content_hash() ] )
	return self

func get_layers() -> FlowSurfaceLayers:
	return layers

## Copy with another vertical tolerance (same grid, transform and layers).
func with_tolerance( tolerance : float ) -> FlowHeightfieldSurface:
	var out := FlowHeightfieldSurface.new( heights, width, depth, cell_size, origin, transform, tolerance )
	return out.attach_layers( layers )

## Local-space XZ footprint of the grid: Rect2(origin.xz, size).
func get_local_footprint() -> Rect2:
	return Rect2( Vector2( origin.x, origin.z ), Vector2( maxi( 0, width - 1 ) * cell_size, maxi( 0, depth - 1 ) * cell_size ) )

## World hit of the vertical through (x, z) with the position clamped onto the
## grid footprint first (in local space), so queries beyond the edge return the
## edge height and normal. {} only for an empty grid or a hole.
func clamped_hit( x : float, z : float ) -> Dictionary:
	if width < 2 or depth < 2:
		return {}
	var l := _inv * Vector3( x, transform.origin.y, z )
	var r := get_local_footprint()
	return _to_world( _local_hit( clampf( l.x, r.position.x, r.end.x ), clampf( l.z, r.position.y, r.end.y ) ) )

func get_kind() -> int:
	return FlowData.Kind.Surface

func get_type_name() -> String:
	return "Heightfield Surface"

func get_bounds() -> AABB:
	return _bounds

func get_height( i : int, j : int ) -> float:
	return heights[clampi( j, 0, depth - 1 ) * width + clampi( i, 0, width - 1 )]

## Local-space hit at local (lx, lz): { position (local), normal (local) } or {}.
func _local_hit( lx : float, lz : float ) -> Dictionary:
	if width < 2 or depth < 2:
		return {}
	var fx := ( lx - origin.x ) / cell_size
	var fz := ( lz - origin.z ) / cell_size
	if fx < -1e-6 or fz < -1e-6 or fx > width - 1 + 1e-6 or fz > depth - 1 + 1e-6:
		return {}
	var i := clampi( int( floor( fx ) ), 0, width - 2 )
	var j := clampi( int( floor( fz ) ), 0, depth - 2 )
	var u := clampf( fx - i, 0.0, 1.0 )
	var v := clampf( fz - j, 0.0, 1.0 )
	var h00 := heights[j * width + i]
	var h10 := heights[j * width + i + 1]
	var h01 := heights[( j + 1 ) * width + i]
	var h11 := heights[( j + 1 ) * width + i + 1]
	if is_nan( h00 ) or is_nan( h10 ) or is_nan( h01 ) or is_nan( h11 ):
		return {}
	var h := lerpf( lerpf( h00, h10, u ), lerpf( h01, h11, u ), v )
	var dhdx := ( lerpf( h10, h11, v ) - lerpf( h00, h01, v ) ) / cell_size
	var dhdz := ( lerpf( h01, h11, u ) - lerpf( h00, h10, u ) ) / cell_size
	var n := Vector3( -dhdx, 1.0, -dhdz ).normalized()
	return { "position": Vector3( lx, origin.y + h, lz ), "normal": n }

func _to_world( local_hit : Dictionary ) -> Dictionary:
	if local_hit.is_empty():
		return {}
	return {
		"position": transform * local_hit.position,
		"normal": FlowSpatial.transform_normal( transform, local_hit.normal ),
		"density": 1.0,
	}

func sample_density( world_pos : Vector3 ) -> float:
	var l := _inv * world_pos
	var hit := _local_hit( l.x, l.z )
	if hit.is_empty():
		return 0.0
	if vertical_tolerance > 0.0:
		var w : Vector3 = transform * hit.position
		return 1.0 if w.distance_to( world_pos ) <= vertical_tolerance else 0.0
	return 1.0

## BoundsBox overlap (FlowSpatial.box_overlap). The base XZ broad phase assumes
## the density column is world-vertical; when the local Y axis is not (XY / YZ
## planes, tilted transforms) the column runs along another world axis, so the
## sample set is evaluated without that broad phase.
func box_overlap( box_min : Vector3, box_max : Vector3 ) -> Vector2:
	if not FlowSpatial.column_is_world_y( transform ):
		return FlowSpatial.box_overlap_sampled( self, box_min, box_max )
	return super.box_overlap( box_min, box_max )

func project( world_pos : Vector3 ) -> Dictionary:
	var l := _inv * world_pos
	return _to_world( _local_hit( l.x, l.z ) )

func project_vertical( x : float, z : float ) -> Dictionary:
	# For a heightfield whose local Y is world Y (no tilt) any probe height works.
	var l := _inv * Vector3( x, transform.origin.y, z )
	return _to_world( _local_hit( l.x, l.z ) )
