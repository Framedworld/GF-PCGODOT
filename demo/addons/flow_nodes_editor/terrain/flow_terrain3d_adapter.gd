@tool
class_name FlowTerrain3DAdapter
extends FlowTerrainAdapter

## Duck-typed adapter for the Terrain3D plugin (TokisanGames). It never names a
## plugin class, so it works with an unmodified plugin and loads without it.
## Every call is guarded with has_method / property checks. It has only been
## run against fake classes implementing exactly the members listed here
## (tests/terrain/support/fake_terrain_plugins.gd), never against the real
## plugin.
##
## Members used (Terrain3D 1.0 API as recalled; `storage` is the pre-1.0 name of
## the data object and is accepted as well):
##   terrain.data (or terrain.storage)           property, the data object
##   data.get_height(Vector3) -> float            world height, NaN over holes
##   data.get_normal(Vector3) -> Vector3          world normal (NaN over holes)
##   data.get_texture_id(Vector3) -> Vector3      control map query:
##                                                (base id, overlay id, blend 0..1)
##   data.get_region_locations() -> Array         Vector2i region coordinates
##   data.get_height_range() -> Vector2           (min, max) height
##   terrain.region_size                          property, vertices per region side
##   terrain.vertex_spacing                       property (1.0 when absent;
##                                                `mesh_vertex_spacing` before 1.0)
##   terrain.assets                               property, Terrain3DAssets:
##   assets.get_texture_count() -> int, assets.get_texture(id) -> asset,
##   asset.get_name() -> String                   layer names (else "texture_<id>")
##
## Bounds: options.bounds when given; else the union of the regions
## (location * region_size * vertex_spacing, assumed to start at the region
## location, not centred on it) with get_height_range() for Y. Without regions
## and without options.bounds the adapter is invalid.
##
## Layer weights from the control map: a texture id weighs (1 - blend) as the
## base texture plus blend as the overlay texture at that position (1 when both
## are the same id), clamped to 0..1.

const MAX_PROBED_IDS := 32

var terrain : Object = null
var data : Object = null
var _bounds := AABB()
var _spacing := 1.0
var _names : PackedStringArray = PackedStringArray()
var _ids : PackedInt32Array = PackedInt32Array()
var _names_built := false

func _init( terrain_node : Object = null, adapter_options : Dictionary = {} ) -> void:
	super._init( adapter_options )
	terrain = terrain_node
	data = FlowTerrainAdapter.terrain3d_data( terrain_node )
	if data == null:
		error = "not a Terrain3D-like node (no data object with get_height and get_normal)"
		return
	_spacing = _read_spacing()
	_bounds = _read_bounds()
	if _bounds.size.x <= 0.0 or _bounds.size.z <= 0.0:
		error = "cannot read the terrain extent (no regions); set bounds"

func get_type_name() -> String:
	return "Terrain3D"

func _read_spacing() -> float:
	for prop in [ "vertex_spacing", "mesh_vertex_spacing" ]:
		if prop in terrain:
			var v = terrain.get( prop )
			if ( v is float or v is int ) and float( v ) > 0.0:
				return float( v )
	return 1.0

func _read_bounds() -> AABB:
	var explicit = options.get( "bounds", AABB() )
	if explicit is AABB and explicit.size.x > 0.0 and explicit.size.z > 0.0:
		return explicit
	if not data.has_method( "get_region_locations" ) or not ( "region_size" in terrain ):
		return AABB()
	var locations = data.call( "get_region_locations" )
	var region_world := float( terrain.get( "region_size" ) ) * _spacing
	if not ( locations is Array ) or locations.is_empty() or region_world <= 0.0:
		return AABB()
	var hmin := 0.0
	var hmax := 0.0
	if data.has_method( "get_height_range" ):
		var r = data.call( "get_height_range" )
		if r is Vector2 and r.is_finite():
			hmin = minf( r.x, r.y )
			hmax = maxf( r.x, r.y )
	var mn := Vector2( INF, INF )
	var mx := Vector2( -INF, -INF )
	for loc in locations:
		if not ( loc is Vector2i or loc is Vector2 ):
			continue
		mn = Vector2( minf( mn.x, loc.x * region_world ), minf( mn.y, loc.y * region_world ) )
		mx = Vector2( maxf( mx.x, ( loc.x + 1 ) * region_world ), maxf( mx.y, ( loc.y + 1 ) * region_world ) )
	if mn.x > mx.x:
		return AABB()
	return AABB( Vector3( mn.x, hmin, mn.y ), Vector3( mx.x - mn.x, hmax - hmin, mx.y - mn.y ) )

func get_bounds() -> AABB:
	return _bounds

func get_sample_spacing() -> float:
	return _spacing

func get_height( x : float, z : float ) -> float:
	if data == null:
		return NAN
	var p := clamp_xz( x, z )
	return float( data.call( "get_height", Vector3( p.x, 0.0, p.y ) ) )

func get_normal( x : float, z : float ) -> Vector3:
	if data == null:
		return Vector3.UP
	var p := clamp_xz( x, z )
	var n = data.call( "get_normal", Vector3( p.x, 0.0, p.y ) )
	if n is Vector3 and n.is_finite() and n.length_squared() > 1e-12:
		return n.normalized()
	return super.get_normal( x, z )

func _build_names() -> void:
	if _names_built:
		return
	_names_built = true
	if data == null or not data.has_method( "get_texture_id" ):
		return
	var assets = terrain.get( "assets" ) if "assets" in terrain else null
	if assets is Object and assets != null and assets.has_method( "get_texture_count" ) and assets.has_method( "get_texture" ):
		var count := int( assets.call( "get_texture_count" ) )
		for id in range( count ):
			var tex = assets.call( "get_texture", id )
			var n := ""
			if tex is Object and tex != null and tex.has_method( "get_name" ):
				n = str( tex.call( "get_name" ) )
			_names.append( n if n != "" and not _names.has( n ) else "texture_%d" % id )
			_ids.append( id )
		return
	# No asset list: the ids found on a 32 x 32 probe lattice, sorted.
	var seen := {}
	for j in range( 32 ):
		for i in range( 32 ):
			var x := lerpf( _bounds.position.x, _bounds.end.x, ( i + 0.5 ) / 32.0 )
			var z := lerpf( _bounds.position.z, _bounds.end.z, ( j + 0.5 ) / 32.0 )
			var t = data.call( "get_texture_id", Vector3( x, 0.0, z ) )
			if t is Vector3 and t.is_finite():
				seen[ int( t.x ) ] = true
				if t.z > 0.0:
					seen[ int( t.y ) ] = true
	var ids := seen.keys()
	ids.sort()
	for id in ids:
		if _ids.size() >= MAX_PROBED_IDS:
			break
		_names.append( "texture_%d" % id )
		_ids.append( id )

func _native_layer_names() -> PackedStringArray:
	_build_names()
	return _names

func _native_layer_weight( layer_name : String, x : float, z : float ) -> float:
	_build_names()
	var idx := _names.find( layer_name )
	if idx < 0 or data == null or not data.has_method( "get_texture_id" ):
		return 0.0
	var id := _ids[idx]
	var p := clamp_xz( x, z )
	var t = data.call( "get_texture_id", Vector3( p.x, 0.0, p.y ) )
	if not ( t is Vector3 ) or not t.is_finite():
		return 0.0
	var blend := clampf( t.z, 0.0, 1.0 )
	var w := 0.0
	if int( t.x ) == id:
		w += 1.0 - blend
	if int( t.y ) == id:
		w += blend
	return clampf( w, 0.0, 1.0 )
