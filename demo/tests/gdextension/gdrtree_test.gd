# gdrtree_test.gd
class_name GDRTreeTest extends GdUnitTestSuite

func test_instantiation() -> void:
	var rtree = GDRTree.new()
	assert_object(rtree).is_not_null()

func test_clear() -> void:
	var rtree = GDRTree.new()
	# Add one box
	rtree.add(PackedVector3Array([Vector3(0, 0, 0)]), PackedVector3Array([Vector3(2, 2, 2)]))
	rtree.clear()
	# Overlaps query on empty tree
	var res = rtree.overlaps(PackedVector3Array([Vector3(0, 0, 0)]), PackedVector3Array([Vector3(2, 2, 2)]), true)
	assert_bool(res["result"]).is_true()
	assert_array(res["idxs_overlapped"]).is_empty()

func test_add_mismatched_inputs() -> void:
	var rtree = GDRTree.new()
	var centers = PackedVector3Array([Vector3(0, 0, 0)])
	var sizes = PackedVector3Array() # Empty
	assert_bool(rtree.add(centers, sizes)).is_false()

func test_overlaps() -> void:
	var rtree = GDRTree.new()
	# Add box at (0,0,0) of size (2,2,2) -> bounds [-1, 1]
	# Add box at (10,10,10) of size (2,2,2) -> bounds [9, 11]
	rtree.add(
		PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 10, 10)]),
		PackedVector3Array([Vector3(2, 2, 2), Vector3(2, 2, 2)])
	)
	
	# Test case 1: query box at (0, 0, 0) of size (1, 1, 1) -> completely inside first box
	# Query box at (20, 20, 20) of size (2, 2, 2) -> no overlap
	var query_centers = PackedVector3Array([Vector3(0, 0, 0), Vector3(20, 20, 20)])
	var query_sizes = PackedVector3Array([Vector3(1, 1, 1), Vector3(2, 2, 2)])
	
	# Overlaps returns a dictionary.
	# With return_overlapped = true, idxs_overlapped will return [0].
	var res = rtree.overlaps(query_centers, query_sizes, true)
	assert_bool(res["result"]).is_true()
	assert_array(res["idxs_overlapped"]).is_equal(PackedInt32Array([0]))
	
	# With return_overlapped = false, it returns the ones NOT overlapped, so [1].
	res = rtree.overlaps(query_centers, query_sizes, false)
	assert_bool(res["result"]).is_true()
	assert_array(res["idxs_overlapped"]).is_equal(PackedInt32Array([1]))

func test_self_prune() -> void:
	var rtree = GDRTree.new()
	
	# Try to insert:
	# 1. Box at (0, 0, 0) size (2, 2, 2) -> bounds [-1, 1]
	# 2. Box at (1, 0, 0) size (2, 2, 2) -> bounds [0, 2] (overlaps with first box)
	# 3. Box at (10, 10, 10) size (2, 2, 2) -> bounds [9, 11] (does not overlap)
	var centers = PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(1, 0, 0),
		Vector3(10, 10, 10)
	])
	var sizes = PackedVector3Array([
		Vector3(2, 2, 2),
		Vector3(2, 2, 2),
		Vector3(2, 2, 2)
	])
	
	# self_prune checks overlap of each box with already inserted ones.
	# Box 0: inserted (no boxes in tree yet). Overlapped = false.
	# Box 1: overlaps Box 0. Overlapped = true. Not inserted.
	# Box 2: does not overlap Box 0. Inserted. Overlapped = false.
	#
	# With return_overlapped = true, idxs_overlapped should return [1].
	var res = rtree.self_prune(centers, sizes, true)
	assert_bool(res["result"]).is_true()
	assert_array(res["idxs_overlapped"]).is_equal(PackedInt32Array([1]))
	
	# With return_overlapped = false, idxs_overlapped should return [0, 2] on a clean tree.
	var rtree2 = GDRTree.new()
	var res2 = rtree2.self_prune(centers, sizes, false)
	assert_bool(res2["result"]).is_true()
	assert_array(res2["idxs_overlapped"]).is_equal(PackedInt32Array([0, 2]))
