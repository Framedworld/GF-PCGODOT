# transforms_stream_inline_test.gd
# Pins FlowData.TransformsStream.basisAt / atIndex / atIndexAbsScale after the
# WP13-P1 change that inlined the Euler and quaternion conversions: every
# result must equal, bit for bit, the composition of the public helpers they
# were defined with (FlowData.eulerToBasis, quatToBasis(vec4ToQuat())).
class_name TransformsStreamInlineTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")

const T := FlowDataScript.DataType

static func _data(n : int, with_quats : bool) -> FlowData.Data:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var d := FlowDataScript.Data.new()
	d.addCommonStreams(n)
	var pos := d.getVector3Container("position")
	var rot := d.getVector3Container("rotation")
	var siz := d.getVector3Container("size")
	var specials := [Vector3.ZERO, Vector3(90, 0, 0), Vector3(0, 90, 0), Vector3(0, 0, 90), Vector3(-90, 180, -180),
		Vector3(1e-7, -1e-7, 360), Vector3(720.5, -1080.25, 33.3), Vector3(89.9999, 0.0001, -89.9999)]
	var quats := PackedVector4Array()
	for i in range(n):
		pos[i] = Vector3(rng.randf_range(-1e3, 1e3), rng.randf_range(-10, 10), rng.randf_range(-1e3, 1e3))
		rot[i] = specials[i] if i < specials.size() else Vector3(rng.randf_range(-360, 360), rng.randf_range(-360, 360), rng.randf_range(-360, 360))
		siz[i] = Vector3(rng.randf_range(0.01, 5), rng.randf_range(-2, 5), rng.randf_range(0.01, 5))
		var q := Quaternion(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() if i > 0 else Vector3.UP, rng.randf_range(-PI, PI))
		quats.append(Vector4(q.x, q.y, q.z, q.w) if i != 1 else Vector4(0.1, 0.2, 0.3, 0.4))
	if with_quats:
		d.registerStream("rotation_quat", quats, T.Quaternion)
	return d

static func _reference_basis(trs : FlowData.TransformsStream, id : int) -> Basis:
	if trs.use_quats:
		return FlowDataScript.quatToBasis(FlowDataScript.vec4ToQuat(trs.quats[id]))
	return FlowDataScript.eulerToBasis(trs.eulers[id])

func _check(with_quats : bool) -> void:
	var n := 2000
	var trs := _data(n, with_quats).getTransformsStream()
	assert_bool(trs.use_quats).is_equal(with_quats)
	var mismatches := 0
	if with_quats:
		# getTransformsStream derives the Euler stream from the quaternions.
		for i in range(n):
			var expected_euler := FlowDataScript.quatToEuler(FlowDataScript.vec4ToQuat(trs.quats[i]))
			if var_to_bytes(trs.eulers[i]) != var_to_bytes(expected_euler):
				mismatches += 1
	for i in range(n):
		var basis := _reference_basis(trs, i)
		var expected := Transform3D(basis.scaled(trs.sizes[i]), trs.positions[i])
		var expected_abs := Transform3D(basis.scaled(Vector3.ONE * 0.75), trs.positions[i])
		if var_to_bytes(trs.basisAt(i)) != var_to_bytes(basis):
			mismatches += 1
		if var_to_bytes(trs.atIndex(i)) != var_to_bytes(expected):
			mismatches += 1
		if var_to_bytes(trs.atIndexAbsScale(i, 0.75)) != var_to_bytes(expected_abs):
			mismatches += 1
	assert_int(mismatches).is_equal(0)

func test_euler_path_is_bit_identical() -> void:
	_check(false)

func test_quaternion_path_is_bit_identical() -> void:
	_check(true)
