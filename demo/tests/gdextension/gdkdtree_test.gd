# gdkdtree_test.gd
class_name GDKdTreeTest extends GdUnitTestSuite

func test_instantiation() -> void:
	var kdtree = GDKdTree.new()
	assert_object(kdtree).is_not_null()

func test_empty_tree() -> void:
	var kdtree = GDKdTree.new()
	# Querying empty tree should return -1 or array of -1
	assert_int(kdtree.find_nearest_idx(Vector3(1, 2, 3))).is_equal(-1)
	
	var query_points = PackedVector3Array([Vector3(1, 1, 1), Vector3(2, 2, 2)])
	var nearest_indices = kdtree.find_nearest_indices(query_points)
	assert_array(nearest_indices).is_equal(PackedInt32Array([-1, -1]))

func test_single_point() -> void:
	var kdtree = GDKdTree.new()
	kdtree.set_points(PackedVector3Array([Vector3(5, 5, 5)]))
	
	assert_int(kdtree.find_nearest_idx(Vector3(0, 0, 0))).is_equal(0)
	assert_int(kdtree.find_nearest_idx(Vector3(100, 100, 100))).is_equal(0)

func test_nearest_neighbor_search() -> void:
	var kdtree = GDKdTree.new()
	var points = PackedVector3Array([
		Vector3(0, 0, 0),       # Index 0
		Vector3(10, 0, 0),      # Index 1
		Vector3(0, 10, 0),      # Index 2
		Vector3(0, 0, 10)       # Index 3
	])
	kdtree.set_points(points)
	
	# Verify exact matches
	assert_int(kdtree.find_nearest_idx(Vector3(0, 0, 0))).is_equal(0)
	assert_int(kdtree.find_nearest_idx(Vector3(10, 0, 0))).is_equal(1)
	
	# Verify midpoints/proximity
	assert_int(kdtree.find_nearest_idx(Vector3(1, 0, 0))).is_equal(0)
	assert_int(kdtree.find_nearest_idx(Vector3(9, 0, 0))).is_equal(1)
	assert_int(kdtree.find_nearest_idx(Vector3(0, 6, 0))).is_equal(2)
	assert_int(kdtree.find_nearest_idx(Vector3(0, 0, 6))).is_equal(3)

func test_find_nearest_indices() -> void:
	var kdtree = GDKdTree.new()
	var points = PackedVector3Array([
		Vector3(1, 1, 1),
		Vector3(-1, -1, -1)
	])
	kdtree.set_points(points)
	
	var query = PackedVector3Array([
		Vector3(2, 2, 2),
		Vector3(-2, -2, -2),
		Vector3(0.1, 0.1, 0.1)
	])
	
	var results = kdtree.find_nearest_indices(query)
	assert_array(results).is_equal(PackedInt32Array([0, 1, 0]))
