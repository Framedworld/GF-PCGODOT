# gdstreamutils_test.gd
class_name GDStreamUtilsTest extends GdUnitTestSuite

func test_get_sorted_indices_i32() -> void:
	# Test normal sorting
	var values = PackedInt32Array([10, -5, 20, 0])
	var sorted_indices = GDStreamUtils.get_sorted_indices_i32(values)
	assert_array(sorted_indices).is_equal(PackedInt32Array([1, 3, 0, 2]))
	
	# Test empty array
	assert_array(GDStreamUtils.get_sorted_indices_i32(PackedInt32Array())).is_empty()
	
	# Test single element
	assert_array(GDStreamUtils.get_sorted_indices_i32(PackedInt32Array([42]))).is_equal(PackedInt32Array([0]))

func test_get_sorted_indices_f32() -> void:
	# Test normal sorting
	var values = PackedFloat32Array([3.14, -1.1, 0.0, 2.71])
	var sorted_indices = GDStreamUtils.get_sorted_indices_f32(values)
	assert_array(sorted_indices).is_equal(PackedInt32Array([1, 2, 3, 0]))
	
	# Test NaN handling
	var nan_val = NAN
	var values_with_nan = PackedFloat32Array([nan_val, 1.5, -0.5])
	var sorted_indices_nan = GDStreamUtils.get_sorted_indices_f32(values_with_nan)
	# -0.5 (index 2) < 1.5 (index 1) < NaN (index 0)
	assert_array(sorted_indices_nan).is_equal(PackedInt32Array([2, 1, 0]))

func test_get_sorted_indices_string() -> void:
	var values = PackedStringArray(["zebra", "apple", "Monkey", "banana"])
	var sorted_indices = GDStreamUtils.get_sorted_indices_string(values)
	# Note: String comparison is lexicographical, capital letters are sorted before lowercase:
	# "Monkey" (Index 2) < "apple" (Index 1) < "banana" (Index 3) < "zebra" (Index 0)
	assert_array(sorted_indices).is_equal(PackedInt32Array([2, 1, 3, 0]))
