@tool
class_name FlowMeshSurface
extends FlowSpatial

## Surface data built from mesh triangles (UE: a static mesh / landscape used as
## a surface). Triangles are copied into world space at construction and indexed
## by a FlowTriangleGrid, so a query tests only the triangles of one grid cell.
##
## project(p): the vertical hit nearest to p's height when the vertical through p
## crosses the mesh, otherwise the nearest point on the mesh.
## project_vertical(x, z): the top-most hit (what the surface sampler uses).
## sample_density(p): 1 where the vertical through p crosses the mesh. With
## `vertical_tolerance` > 0 the hit nearest to p must also be within that height.

var grid : FlowTriangleGrid
var vertical_tolerance : float = -1.0

## `world_vertices`: three per triangle, already in world space (copied).
func _init( world_vertices : PackedVector3Array = PackedVector3Array(), tolerance : float = -1.0 ) -> void:
	grid = FlowTriangleGrid.new( world_vertices )
	vertical_tolerance = tolerance
	_hash = hash( [ "mesh_surface", grid.geometry_hash(), vertical_tolerance ] )

## Surface from one or more meshes, each with its local-to-world transform.
static func from_meshes( meshes : Array, transforms : Array, tolerance : float = -1.0 ) -> FlowMeshSurface:
	var verts := PackedVector3Array()
	for i in range( meshes.size() ):
		var xform : Transform3D = transforms[i] if i < transforms.size() else Transform3D.IDENTITY
		verts.append_array( FlowTriangleGrid.mesh_world_vertices( meshes[i], xform ) )
	return FlowMeshSurface.new( verts, tolerance )

## Surface from MeshInstance3D nodes (their world transforms when in the tree).
static func from_mesh_instances( instances : Array, tolerance : float = -1.0 ) -> FlowMeshSurface:
	var meshes := []
	var xforms := []
	for mi in instances:
		if mi is MeshInstance3D and mi.mesh != null:
			meshes.append( mi.mesh )
			xforms.append( mi.global_transform if mi.is_inside_tree() else mi.transform )
	return from_meshes( meshes, xforms, tolerance )

func get_kind() -> int:
	return FlowData.Kind.Surface

func get_type_name() -> String:
	return "Mesh Surface"

func get_bounds() -> AABB:
	return grid.bounds

func get_triangle_count() -> int:
	return grid.tri_count

func sample_density( world_pos : Vector3 ) -> float:
	if vertical_tolerance > 0.0:
		var hit := grid.vertical_hit( world_pos.x, world_pos.z, world_pos.y )
		if hit.is_empty():
			return 0.0
		return 1.0 if absf( hit.position.y - world_pos.y ) <= vertical_tolerance else 0.0
	return 1.0 if grid.count_column_candidates( world_pos.x, world_pos.z ) > 0 and not grid.vertical_hit( world_pos.x, world_pos.z ).is_empty() else 0.0

func project( world_pos : Vector3 ) -> Dictionary:
	var hit := grid.vertical_hit( world_pos.x, world_pos.z, world_pos.y )
	if hit.is_empty():
		hit = grid.nearest( world_pos )
		if hit.is_empty():
			return {}
	return { "position": hit.position, "normal": hit.normal, "density": 1.0 }

func project_vertical( x : float, z : float ) -> Dictionary:
	var hit := grid.vertical_hit( x, z )
	if hit.is_empty():
		return {}
	return { "position": hit.position, "normal": hit.normal, "density": 1.0 }
