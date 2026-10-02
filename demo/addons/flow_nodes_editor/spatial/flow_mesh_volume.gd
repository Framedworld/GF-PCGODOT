@tool
class_name FlowMeshVolume
extends FlowSpatial

## Volume enclosed by a closed triangle mesh (UE: a mesh / CSG used as a
## volume). Inside test: parity of the triangles crossed by the upward vertical,
## using the FlowTriangleGrid column (one grid cell per query).
## Density is binary (1 inside, 0 outside): a mesh volume has no falloff, so
## steepness is ignored. Open meshes give unreliable parity.

var grid : FlowTriangleGrid

func _init( world_vertices : PackedVector3Array = PackedVector3Array() ) -> void:
	grid = FlowTriangleGrid.new( world_vertices )
	_hash = hash( [ "mesh_volume", grid.geometry_hash() ] )

static func from_meshes( meshes : Array, transforms : Array ) -> FlowMeshVolume:
	var verts := PackedVector3Array()
	for i in range( meshes.size() ):
		var xform : Transform3D = transforms[i] if i < transforms.size() else Transform3D.IDENTITY
		verts.append_array( FlowTriangleGrid.mesh_world_vertices( meshes[i], xform ) )
	return FlowMeshVolume.new( verts )

func get_kind() -> int:
	return FlowData.Kind.Volume

func get_type_name() -> String:
	return "Mesh Volume"

func get_bounds() -> AABB:
	return grid.bounds

func is_inside( world_pos : Vector3 ) -> bool:
	if not grid.bounds.grow( 1e-6 ).has_point( world_pos ):
		return false
	return grid.count_crossings_above( world_pos ) % 2 == 1

func sample_density( world_pos : Vector3 ) -> float:
	return 1.0 if is_inside( world_pos ) else 0.0
