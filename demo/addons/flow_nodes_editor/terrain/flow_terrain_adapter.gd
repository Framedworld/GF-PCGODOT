@tool
class_name FlowTerrainAdapter
extends RefCounted

## Uniform read access to a terrain (UE Landscape parity for Get Landscape Data
## and landscape layer weights), whatever stores it: a HeightMapShape3D, a
## heightmap Image, a MeshInstance3D, or a terrain plugin node (Terrain3D,
## HTerrain) reached by duck typing.
##
## Contract (docs/PARITY_ROUND2.md, WP6):
##   get_bounds() -> AABB                world-space box of the terrain
##   get_height(x, z) -> float           world height of the surface under (x, z);
##                                       positions beyond the terrain are clamped
##                                       onto its edge; NaN only over a hole
##   get_normal(x, z) -> Vector3         unit world normal (same clamping, never NaN)
##   get_layer_names() -> PackedStringArray
##   get_layer_weight(name, x, z) -> float   0..1, 0 for an unknown layer
##   to_surface() -> FlowSpatial         an immutable surface shape
##                                       (FlowHeightfieldSurface or FlowMeshSurface)
##                                       carrying the layer weights (FlowSurfaceLayers)
##
## Adapters read the scene, so they are created and queried on the main thread
## (get_surface_data and sample_terrain_layers are main-thread nodes). The
## shape returned by to_surface() copies everything it needs and is then safe
## anywhere.
##
## Options (Dictionary passed to the builders, all optional):
##   vertical_tolerance : float = -1    surface density band, see FlowHeightfieldSurface
##   max_resolution : int = 1024        cap on grid samples per axis for snapshots
##   layer_names : PackedStringArray    renames the adapter's layers in order
##   splat_layers : Array               FlowTerrainSplatLayer resources, extra
##                                      image layers over the terrain footprint
##   bounds : AABB                      explicit bounds (Terrain3D when its
##                                      regions cannot be read)

var options : Dictionary = {}
## Scene path (or a description) of the source, for data attributes and errors.
var source_name : String = ""
## Set by a builder that could not read its source; the adapter is unusable.
var error : String = ""

## Splat-image layers over get_bounds() (options.splat_layers), built lazily.
var _splat : FlowSurfaceLayers = null
var _splat_built := false

func _init( adapter_options : Dictionary = {} ) -> void:
	options = adapter_options

# --- contract ---------------------------------------------------------------------------

func get_type_name() -> String:
	return "Terrain"

func is_valid() -> bool:
	return error == ""

func get_bounds() -> AABB:
	return AABB()

## Grid spacing used by snapshots (to_surface) and by the default normal.
func get_sample_spacing() -> float:
	return 1.0

func get_height( _x : float, _z : float ) -> float:
	return NAN

## Default: central differences of get_height over the clamped neighbours,
## divided by the real distance between them, so edges give one-sided slopes.
func get_normal( x : float, z : float ) -> Vector3:
	var b := get_bounds()
	var d := maxf( get_sample_spacing(), 1e-4 )
	var p := clamp_xz( x, z )
	var xl := maxf( p.x - d, b.position.x )
	var xr := minf( p.x + d, b.end.x )
	var zb := maxf( p.y - d, b.position.z )
	var zf := minf( p.y + d, b.end.z )
	var hl := get_height( xl, p.y )
	var hr := get_height( xr, p.y )
	var hb := get_height( p.x, zb )
	var hf := get_height( p.x, zf )
	var sx := 0.0 if ( xr - xl ) <= 0.0 or is_nan( hl ) or is_nan( hr ) else ( hr - hl ) / ( xr - xl )
	var sz := 0.0 if ( zf - zb ) <= 0.0 or is_nan( hb ) or is_nan( hf ) else ( hf - hb ) / ( zf - zb )
	return Vector3( -sx, 1.0, -sz ).normalized()

## The adapter's own layers (renamed by options.layer_names), then the splat
## image layers whose names are not taken yet.
func get_layer_names() -> PackedStringArray:
	var out := _renamed( _native_layer_names() )
	var splat := _splat_layers()
	if splat != null:
		for n in splat.names:
			if not out.has( n ):
				out.append( n )
	return out

func get_layer_weight( layer_name : String, x : float, z : float ) -> float:
	var native := _native_layer_names()
	var renamed := _renamed( native )
	var idx := renamed.find( layer_name )
	if idx >= 0:
		return clampf( _native_layer_weight( native[idx], x, z ), 0.0, 1.0 )
	var splat := _splat_layers()
	if splat != null:
		return splat.get_weight( layer_name, x, z )
	return 0.0

func to_surface() -> FlowSpatial:
	return _grid_surface()

## Cheap summary of what the adapter reads, for scene fingerprints: bounds and
## heights / layer weights probed on a 9 x 9 lattice.
func fingerprint() -> int:
	var b := get_bounds()
	var items : Array = [ get_type_name(), b, get_layer_names() ]
	var names := get_layer_names()
	for j in range( 9 ):
		for i in range( 9 ):
			var x := lerpf( b.position.x, b.end.x, i / 8.0 )
			var z := lerpf( b.position.z, b.end.z, j / 8.0 )
			items.append( get_height( x, z ) )
			for n in names:
				items.append( get_layer_weight( n, x, z ) )
	return items.hash()

# --- helpers for subclasses -----------------------------------------------------------------

## (x, z) clamped onto the XZ footprint of get_bounds().
func clamp_xz( x : float, z : float ) -> Vector2:
	var b := get_bounds()
	return Vector2( clampf( x, b.position.x, b.end.x ), clampf( z, b.position.z, b.end.z ) )

## Layer names the source itself provides (plugin texture ids, splat channels).
func _native_layer_names() -> PackedStringArray:
	return PackedStringArray()

func _native_layer_weight( _layer_name : String, _x : float, _z : float ) -> float:
	return 0.0

func _renamed( names : PackedStringArray ) -> PackedStringArray:
	var renames : PackedStringArray = options.get( "layer_names", PackedStringArray() )
	var out := names.duplicate()
	for i in range( mini( renames.size(), out.size() ) ):
		if renames[i] != "":
			out[i] = renames[i]
	return out

func _tolerance() -> float:
	return float( options.get( "vertical_tolerance", -1.0 ) )

func _max_resolution() -> int:
	return maxi( 2, int( options.get( "max_resolution", 1024 ) ) )

## Image layers from options.splat_layers, each image covering the rectangle
## of _splat_mapping() (the terrain footprint), built once.
func _splat_layers() -> FlowSurfaceLayers:
	if _splat_built:
		return _splat
	_splat_built = true
	var entries : Array = options.get( "splat_layers", [] )
	if entries.is_empty():
		return null
	var names := PackedStringArray()
	var images : Array = []
	var channels := PackedInt32Array()
	for e in entries:
		if not ( e is Object ) or e == null:
			continue
		var n := str( e.get( "layer_name" ) )
		if n == "" or names.has( n ):
			continue
		names.append( n )
		images.append( e.call( "get_layer_image" ) if e.has_method( "get_layer_image" ) else e.get( "image" ) )
		channels.append( int( e.get( "channel" ) ) )
	if names.is_empty():
		return null
	var m := _splat_mapping()
	_splat = FlowSurfaceLayers.from_images( names, images, channels, m.min, m.max, m.to_layer )
	return _splat

## Where layer images sit: { min : Vector2, max : Vector2 (layer-space XZ
## rectangle mapped to UV 0..1), to_layer : Transform3D (world to layer space) }.
## Default: the XZ footprint of get_bounds() in world space.
func _splat_mapping() -> Dictionary:
	var b := get_bounds()
	return { "min": Vector2( b.position.x, b.position.z ), "max": Vector2( b.end.x, b.end.z ), "to_layer": Transform3D.IDENTITY }

## Every layer (native and splat) as one FlowSurfaceLayers: splat layers keep
## their images; native layers are snapshotted on `w` x `d` grid points over the
## footprint (the same lattice as the height snapshot).
func _snapshot_layers( w : int, d : int ) -> FlowSurfaceLayers:
	var native := _native_layer_names()
	var b := get_bounds()
	var out : FlowSurfaceLayers = null
	if not native.is_empty():
		out = FlowSurfaceLayers.from_function( native, Callable( self, "_native_layer_weight" ), Vector2( b.position.x, b.position.z ), Vector2( b.end.x, b.end.z ), w, d )
		out = out.renamed( _renamed( native ) )
	var splat := _splat_layers()
	if splat != null:
		out = splat if out == null else FlowSurfaceLayers.merged( out, splat )
	return out

## Grid lattice size for a snapshot of the footprint at get_sample_spacing(),
## capped by max_resolution.
func _grid_size() -> Vector2i:
	var b := get_bounds()
	var cell := maxf( get_sample_spacing(), 1e-4 )
	var cap := _max_resolution()
	var w := clampi( int( ceil( b.size.x / cell - 1e-6 ) ) + 1, 2, cap )
	var d := clampi( int( ceil( b.size.z / cell - 1e-6 ) ) + 1, 2, cap )
	return Vector2i( w, d )

## Default to_surface(): get_height sampled on a world grid spanning exactly the
## footprint (square cells when both axes share a spacing, otherwise unit cells
## scaled per axis by the grid transform), with layer weights.
func _grid_surface() -> FlowSpatial:
	var b := get_bounds()
	if b.size.x <= 0.0 or b.size.z <= 0.0:
		return null
	var gs := _grid_size()
	var cx := b.size.x / float( gs.x - 1 )
	var cz := b.size.z / float( gs.y - 1 )
	if is_equal_approx( cx, cz ):
		# Square cells span the footprint exactly on both axes.
		var cell := maxf( cx, cz )
		var w := int( ceil( b.size.x / cell - 1e-6 ) ) + 1
		var d := int( ceil( b.size.z / cell - 1e-6 ) ) + 1
		var heights := PackedFloat32Array()
		heights.resize( w * d )
		for j in range( d ):
			for i in range( w ):
				heights[j * w + i] = get_height( b.position.x + i * cell, b.position.z + j * cell )
		var hf := FlowHeightfieldSurface.new( heights, w, d, cell, Vector3( b.position.x, 0.0, b.position.z ), Transform3D.IDENTITY, _tolerance() )
		return hf.attach_layers( _snapshot_layers( gs.x, gs.y ) )
	# Different spacings per axis: one square cell would overshoot the shorter
	# axis by up to a cell (clamped heights, density 1 beyond the terrain). Use
	# unit cells scaled per axis by the grid transform instead.
	var heights_xz := PackedFloat32Array()
	heights_xz.resize( gs.x * gs.y )
	for j in range( gs.y ):
		for i in range( gs.x ):
			heights_xz[j * gs.x + i] = get_height( b.position.x + i * cx, b.position.z + j * cz )
	var xform := Transform3D( Basis.from_scale( Vector3( cx, 1.0, cz ) ), Vector3( b.position.x, 0.0, b.position.z ) )
	var grid := FlowHeightfieldSurface.new( heights_xz, gs.x, gs.y, 1.0, Vector3.ZERO, xform, _tolerance() )
	return grid.attach_layers( _snapshot_layers( gs.x, gs.y ) )

# --- detection and construction ---------------------------------------------------------------

## The terrain object of a Terrain3D-like node: its `data` (Terrain3D 1.x,
## Terrain3DData) or, for older releases, its `storage` (Terrain3DStorage),
## provided it answers get_height(Vector3) and get_normal(Vector3). Null
## otherwise. Only property reads and has_method checks; nothing is called.
static func terrain3d_data( node : Object ) -> Object:
	if node == null or not is_instance_valid( node ):
		return null
	for prop in [ "data", "storage" ]:
		if not ( prop in node ):
			continue
		var d = node.get( prop )
		if d is Object and is_instance_valid( d ) and d.has_method( "get_height" ) and d.has_method( "get_normal" ):
			return d
	return null

static func is_terrain3d( node : Object ) -> bool:
	return terrain3d_data( node ) != null

## The HTerrainData of an HTerrain-like node: get_data() returning an object
## with get_interpolated_height_at(Vector3) and get_resolution(). Null otherwise.
static func hterrain_data( node : Object ) -> Object:
	if node == null or not is_instance_valid( node ) or not node.has_method( "get_data" ):
		return null
	# get_data() on a Terrain3D-like node is its data; do not mistake it.
	if is_terrain3d( node ):
		return null
	var d = node.call( "get_data" )
	if d is Object and is_instance_valid( d ) and d.has_method( "get_interpolated_height_at" ) and d.has_method( "get_resolution" ):
		return d
	return null

static func is_hterrain( node : Object ) -> bool:
	return hterrain_data( node ) != null

## True for nodes auto-detection looks for: terrain plugin nodes, recognised by
## their methods (not their class names, so unmodified plugin classes work).
static func is_terrain_plugin_node( node : Object ) -> bool:
	return is_terrain3d( node ) or is_hterrain( node )

## Adapter for `node`, or null when the node is not a terrain source.
## Accepted: Terrain3D-like and HTerrain-like nodes, a CollisionShape3D with a
## HeightMapShape3D, a MeshInstance3D with a mesh.
static func for_node( node : Node, adapter_options : Dictionary = {} ) -> FlowTerrainAdapter:
	if node == null or not is_instance_valid( node ):
		return null
	var adapter : FlowTerrainAdapter = null
	if is_terrain3d( node ):
		adapter = FlowTerrain3DAdapter.new( node, adapter_options )
	elif is_hterrain( node ):
		adapter = FlowHTerrainAdapter.new( node, adapter_options )
	elif node is CollisionShape3D and ( node as CollisionShape3D ).shape is HeightMapShape3D:
		adapter = FlowHeightMapShapeTerrainAdapter.from_collision_shape( node, adapter_options )
	elif node is MeshInstance3D and ( node as MeshInstance3D ).mesh != null:
		adapter = FlowMeshTerrainAdapter.from_mesh_instance( node, adapter_options )
	if adapter != null:
		adapter.source_name = String( node.get_path() ) if node.is_inside_tree() else String( node.name )
	return adapter

## Finds the terrain to read. With `explicit_path` (relative to `owner`, or
## absolute) that node must be a terrain source. Without it, the scene (or the
## members of `group_name` and their descendants) is scanned for terrain plugin
## nodes; exactly one must exist.
## Returns { adapter : FlowTerrainAdapter or null, node : Node or null, error : String }.
static func detect( owner : Node, explicit_path : NodePath = NodePath(), group_name : String = "", adapter_options : Dictionary = {} ) -> Dictionary:
	if owner == null or not is_instance_valid( owner ):
		return { "adapter": null, "node": null, "error": "no owner node to search the scene from" }
	if not explicit_path.is_empty():
		var n := owner.get_node_or_null( explicit_path )
		if n == null:
			return { "adapter": null, "node": null, "error": "terrain node path '%s' does not resolve from %s" % [ str( explicit_path ), owner.name ] }
		var a := for_node( n, adapter_options )
		if a == null:
			return { "adapter": null, "node": n, "error": "node '%s' is not a terrain (expected a Terrain3D or HTerrain node, a CollisionShape3D with a HeightMapShape3D, or a MeshInstance3D)" % str( explicit_path ) }
		if not a.is_valid():
			return { "adapter": null, "node": n, "error": "terrain '%s': %s" % [ str( explicit_path ), a.error ] }
		return { "adapter": a, "node": n, "error": "" }
	var found := FlowSpatialSources.collect( owner, group_name, true, &"", func( n ): return FlowTerrainAdapter.is_terrain_plugin_node( n ) )
	if found.is_empty():
		return { "adapter": null, "node": null, "error": "no terrain node found%s (looked for Terrain3D-like nodes whose data answers get_height/get_normal and HTerrain-like nodes whose get_data() answers get_interpolated_height_at); set terrain_node_path, or use the Scene source for meshes and HeightMapShape3D" % ( " in group '%s'" % group_name if group_name != "" else "" ) }
	if found.size() > 1:
		var paths := PackedStringArray()
		for n in found:
			paths.append( String( n.get_path() ) if n.is_inside_tree() else String( n.name ) )
		return { "adapter": null, "node": null, "error": "ambiguous terrain: %d terrain nodes found (%s); set terrain_node_path or a group_name that selects one" % [ found.size(), ", ".join( paths ) ] }
	var adapter := for_node( found[0], adapter_options )
	if adapter == null or not adapter.is_valid():
		return { "adapter": null, "node": found[0], "error": "terrain '%s': %s" % [ found[0].name, adapter.error if adapter != null else "unsupported" ] }
	return { "adapter": adapter, "node": found[0], "error": "" }
