@tool
class_name FlowSpatialSources
extends RefCounted

## Scene -> FlowSpatial builders shared by the Get Spline / Surface / Volume Data
## nodes. Every builder reads the scene once and copies what it needs, so the
## returned shapes never refer back to scene nodes or resources.

## Scene nodes a source node reads: the members of `group_name` (and, with
## `recursive`, their descendants), or every descendant of the scene root when no
## group is given. Nodes spawned by a flow graph (flow_owner meta on themselves
## or an ancestor) are skipped, as are nodes failing `accept` or lacking the
## `required_meta` boolean.
static func collect( owner : Node, group_name : String, recursive : bool, required_meta : StringName, accept : Callable ) -> Array:
	var out : Array = []
	if owner == null or not is_instance_valid( owner ):
		return out
	var candidates : Array = []
	if group_name != "":
		if owner.is_inside_tree():
			for n in owner.get_tree().get_nodes_in_group( group_name ):
				candidates.append( n )
				if recursive:
					_descendants( n, candidates )
	else:
		var root := _scene_root( owner )
		if root != null:
			if recursive:
				_descendants( root, candidates )
			else:
				candidates.append_array( root.get_children() )
	var seen := {}
	for n in candidates:
		if n == null or seen.has( n ):
			continue
		seen[n] = true
		if not accept.call( n ):
			continue
		if _is_generated( n ):
			continue
		if required_meta != &"" and not ( n.has_meta( required_meta ) and bool( n.get_meta( required_meta ) ) ):
			continue
		out.append( n )
	return out

static func _descendants( node : Node, out : Array ) -> void:
	for child in node.get_children():
		out.append( child )
		_descendants( child, out )

static func _scene_root( node : Node ) -> Node:
	var current := node as Node3D
	if current == null:
		return node
	while current.get_parent_node_3d():
		current = current.get_parent_node_3d()
	return current

static func _is_generated( node : Node ) -> bool:
	var current := node
	while current:
		if current.has_meta( "flow_owner" ):
			return true
		current = current.get_parent()
	return false

static func world_transform( node : Node3D ) -> Transform3D:
	return node.global_transform if node.is_inside_tree() else node.transform

## Scene fingerprint items for `nodes`: path, transform, visibility and the
## identity of the geometry they carry, so editing a curve, mesh or shape in
## place re-evaluates the source node.
static func fingerprint( owner : Node, nodes : Array ) -> int:
	var items := []
	if owner != null and is_instance_valid( owner ) and owner is Node3D:
		items.append( world_transform( owner ) )
	for n in nodes:
		if n == null or not is_instance_valid( n ):
			continue
		items.append( String( n.get_path() ) if n.is_inside_tree() else String( n.name ) )
		if n is Node3D:
			items.append( world_transform( n ) )
			items.append( n.visible )
		for prop in [ "curve", "mesh", "shape" ]:
			var res = n.get( prop )
			if res is Resource:
				items.append( res.get_instance_id() )
				if res is Curve3D:
					items.append( res.point_count )
					items.append( res.get_baked_length() )
				elif res is HeightMapShape3D:
					items.append( hash( res.map_data ) )
				else:
					for p in [ "size", "radius", "height" ]:
						var v = res.get( p )
						if v != null:
							items.append( v )
		for p in [ "size", "radius", "height" ]:
			if n.is_class( "CSGShape3D" ):
				var v = n.get( p )
				if v != null:
					items.append( v )
	return items.hash()

# --- volumes from scene nodes ---------------------------------------------------------

## Volume for a CollisionShape3D (Box, Sphere, Capsule, Cylinder, Concave;
## Convex approximated by the box of its points), or null.
static func volume_from_collision_shape( cs : CollisionShape3D, volume_steepness : float = 1.0 ) -> FlowSpatial:
	if cs == null or cs.shape == null or cs.disabled:
		return null
	var xform := world_transform( cs )
	var s : Shape3D = cs.shape
	if s is BoxShape3D:
		return FlowBoxVolume.new( xform, s.size * 0.5, volume_steepness )
	if s is SphereShape3D:
		return FlowSphereVolume.new( xform, s.radius, volume_steepness )
	if s is CapsuleShape3D:
		var cm := CapsuleMesh.new()
		cm.radius = s.radius
		cm.height = s.height
		return FlowMeshVolume.from_meshes( [ cm ], [ xform ] )
	if s is CylinderShape3D:
		var cy := CylinderMesh.new()
		cy.top_radius = s.radius
		cy.bottom_radius = s.radius
		cy.height = s.height
		return FlowMeshVolume.from_meshes( [ cy ], [ xform ] )
	if s is ConcavePolygonShape3D:
		var faces : PackedVector3Array = s.get_faces()
		var world := PackedVector3Array()
		world.resize( faces.size() )
		for i in range( faces.size() ):
			world[i] = xform * faces[i]
		return FlowMeshVolume.new( world )
	if s is ConvexPolygonShape3D:
		var pts : PackedVector3Array = s.points
		if pts.is_empty():
			return null
		var aabb := AABB( pts[0], Vector3.ZERO )
		for p in pts:
			aabb = aabb.expand( p )
		return FlowBoxVolume.new( xform * Transform3D( Basis.IDENTITY, aabb.get_center() ), aabb.size * 0.5, volume_steepness )
	return null

## Volume for a CSG root: a plain CSGBox3D / CSGSphere3D exactly, other CSG roots
## (combiners, boxes with child operations, ...) from their baked mesh, falling
## back to their AABB when the mesh is not available yet.
static func volume_from_csg( csg : Node3D, volume_steepness : float = 1.0 ) -> FlowSpatial:
	var xform := world_transform( csg )
	var has_csg_children := false
	for child in csg.get_children():
		if child.is_class( "CSGShape3D" ):
			has_csg_children = true
			break
	if csg.is_class( "CSGBox3D" ) and not has_csg_children:
		return FlowBoxVolume.new( xform, ( csg.get( "size" ) as Vector3 ) * 0.5, volume_steepness )
	if csg.is_class( "CSGSphere3D" ) and not has_csg_children:
		return FlowSphereVolume.new( xform, float( csg.get( "radius" ) ), volume_steepness )
	if csg.has_method( "get_meshes" ) and csg.has_method( "is_root_shape" ) and csg.call( "is_root_shape" ):
		var baked = csg.call( "get_meshes" )
		if baked is Array and baked.size() >= 2 and baked[1] is Mesh:
			return FlowMeshVolume.from_meshes( [ baked[1] ], [ xform * ( baked[0] as Transform3D ) ] )
	if csg.has_method( "get_aabb" ):
		var aabb : AABB = csg.call( "get_aabb" )
		return FlowBoxVolume.new( xform * Transform3D( Basis.IDENTITY, aabb.get_center() ), aabb.size * 0.5, volume_steepness )
	return null

## Volume for a MeshInstance3D: its oriented local AABB (default) or, with
## `closed_mesh`, the mesh itself as a FlowMeshVolume.
static func volume_from_mesh_instance( mi : MeshInstance3D, closed_mesh : bool, volume_steepness : float = 1.0 ) -> FlowSpatial:
	if mi == null or mi.mesh == null:
		return null
	var xform := world_transform( mi )
	if closed_mesh:
		return FlowMeshVolume.from_meshes( [ mi.mesh ], [ xform ] )
	var aabb := mi.mesh.get_aabb()
	return FlowBoxVolume.new( xform * Transform3D( Basis.IDENTITY, aabb.get_center() ), aabb.size * 0.5, volume_steepness )
