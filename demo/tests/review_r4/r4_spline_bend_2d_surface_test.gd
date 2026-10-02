# r4_spline_bend_2d_surface_test.gd
# Review R4: FlowSplineBend.bend_arrays typed the vertex array as
# PackedVector3Array, so a mesh with a 2D-vertex surface (ArrayMesh built
# with PackedVector2Array vertices, as MeshInstance2D meshes are) raised a
# SCRIPT ERROR and then an engine error from add_surface_from_arrays. Such a
# surface cannot be bent in 3D: it is skipped, the other surfaces are bent.
class_name R4SplineBend2DSurfaceTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")

func before_test() -> void:
	FlowSplineBend.clear_cache()

func after_test() -> void:
	FlowSplineBend.clear_cache()

func _mixed_mesh() -> ArrayMesh:
	var m := ArrayMesh.new()
	var a3 := []
	a3.resize(Mesh.ARRAY_MAX)
	a3[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)])
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a3)
	var a2 := []
	a2.resize(Mesh.ARRAY_MAX)
	a2[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)])
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2)
	return m

func _curve() -> Curve3D:
	var c := Curve3D.new()
	c.add_point(Vector3.ZERO)
	c.add_point(Vector3(0, 0, 4))
	return c

func test_2d_surface_is_skipped_and_3d_surface_bent() -> void:
	var m := _mixed_mesh()
	assert_int(m.get_surface_count()).is_equal(2)
	var bent := FlowSplineBend.bend_mesh(m, _curve(), 0.0, 4.0)
	assert_int(bent.get_surface_count()).is_equal(1)
	var verts : PackedVector3Array = bent.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_int(verts.size()).is_equal(3)
	# The 3D surface is stretched over the 4 m segment along +Z.
	assert_float(verts[2].z).is_equal_approx(4.0, 0.001)
