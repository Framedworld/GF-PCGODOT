@tool
class_name FlowMeshTerrainAdapter
extends FlowTerrainAdapter

## A terrain mesh (MeshInstance3D, or meshes with transforms) through
## FlowMeshSurface: get_height is the top-most vertical hit. Beyond the mesh
## footprint the position is clamped onto the bounds; if the vertical still
## misses (a gap or a non-rectangular footprint) the nearest point of the mesh
## answers. Splat images cover the XZ footprint of the mesh bounds.

var _surface : FlowMeshSurface = null
var _attached := false

func _init( meshes : Array = [], transforms : Array = [], adapter_options : Dictionary = {} ) -> void:
	super._init( adapter_options )
	if meshes.is_empty():
		error = "no mesh"
		return
	_surface = FlowMeshSurface.from_meshes( meshes, transforms, _tolerance() )
	if _surface.get_triangle_count() == 0:
		error = "the mesh has no triangles"

static func from_mesh_instance( mi : MeshInstance3D, adapter_options : Dictionary = {} ) -> FlowMeshTerrainAdapter:
	if mi == null or mi.mesh == null:
		return FlowMeshTerrainAdapter.new( [], [], adapter_options )
	return FlowMeshTerrainAdapter.new( [ mi.mesh ], [ FlowSpatialSources.world_transform( mi ) ], adapter_options )

func get_type_name() -> String:
	return "Mesh"

func get_bounds() -> AABB:
	return _surface.get_bounds() if _surface != null else AABB()

## Mean triangle edge, estimated from the footprint area and triangle count.
func get_sample_spacing() -> float:
	if _surface == null or _surface.get_triangle_count() == 0:
		return 1.0
	var b := get_bounds()
	return maxf( 1e-3, sqrt( maxf( b.size.x * b.size.z, 1e-6 ) * 2.0 / float( _surface.get_triangle_count() ) ) )

func _hit( x : float, z : float ) -> Dictionary:
	if _surface == null:
		return {}
	var p := clamp_xz( x, z )
	var hit := _surface.project_vertical( p.x, p.y )
	if hit.is_empty():
		hit = _surface.grid.nearest( Vector3( p.x, get_bounds().get_center().y, p.y ) )
	return hit

func get_height( x : float, z : float ) -> float:
	var hit := _hit( x, z )
	return NAN if hit.is_empty() else float( hit.position.y )

func get_normal( x : float, z : float ) -> Vector3:
	var hit := _hit( x, z )
	if hit.is_empty():
		return Vector3.UP
	var n : Vector3 = hit.normal
	return n.normalized() if n.is_finite() and n.length_squared() > 0.0 else Vector3.UP

## The mesh surface itself, with the splat layers attached.
func to_surface() -> FlowSpatial:
	if _surface == null:
		return null
	if not _attached:
		_attached = true
		_surface.attach_layers( _snapshot_layers( 2, 2 ) )
	return _surface
