extends RefCounted

## Synthetic inputs for the node conformance harness (WP9).
##
## Every builder is a pure function of its arguments: calling it twice gives
## two distinct Data objects with equal content (equal content_hash), so each
## execution of the harness gets fresh inputs and a cache lookup with fresh
## inputs still finds the entry stored by an earlier run. Object-valued
## streams reference a few shared resources (shared_mesh()), created once per
## process, so their identity is stable too.
##
## Primary fixtures feed input port 0. Secondary fixtures feed ports 1 and up
## of templates that declare two or more inputs.

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")

## Fixtures every template with at least one input runs on (port 0).
const PRIMARY := [
	"points",          # 12 points: canonical streams plus one attribute of every type
	"single",          # the same schema, 1 point
	"empty",           # FlowData.Data.new(): no streams at all
	"empty_schema",    # the full point schema with 0 rows
	"tagged",          # points carrying tags
	"data_attrs",      # points carrying per-data (@data) attributes
	"attr_set",        # an attribute set: Kind.AttrSet, attributes only, no position
	"spline",          # FlowSplineShape, 0 points
	"surface_polygon", # FlowPolygonSurface, 0 points
	"surface_heightfield", # FlowHeightfieldSurface, 0 points
	"surface_mesh",    # FlowMeshSurface, 0 points
	"volume_box",      # FlowBoxVolume, 0 points
	"volume_sphere",   # FlowSphereVolume, 0 points
	"composite",       # FlowCompositeShape (box minus sphere), 0 points
]

## Second-input variants for templates with two or more inputs. The first one
## is paired with every primary fixture; the others are paired with "points".
const SECONDARY := [ "points_b", "points", "empty", "attr_set", "volume_box" ]

## Fixture id used for templates that declare no input at all.
const NO_INPUT := "none"

const POINT_COUNT := 12
const POINT_COUNT_B := 8

## Names of the non-canonical point attributes of the point fixtures, one per type.
const ATTRIBUTES := {
	"f_attr": FlowData.DataType.Float,
	"i_attr": FlowData.DataType.Int,
	"b_attr": FlowData.DataType.Bool,
	"v_attr": FlowData.DataType.Vector,
	"s_attr": FlowData.DataType.String,
	"c_attr": FlowData.DataType.Color,
	"q_attr": FlowData.DataType.Quaternion,
	"r_attr": FlowData.DataType.Resource,
	"v2_attr": FlowData.DataType.Vector2,
	"v4_attr": FlowData.DataType.Vector4,
	"t_attr": FlowData.DataType.Transform,
	"i64_attr": FlowData.DataType.Int64,
	"d_attr": FlowData.DataType.Double,
}

static var _shared_mesh : ArrayMesh = null
static var _shared_mesh_mutex := Mutex.new()

## A small ArrayMesh (two triangles) shared by every fixture that carries a
## Resource attribute. Built from arrays, so nothing about it is lazy.
static func shared_mesh() -> ArrayMesh:
	_shared_mesh_mutex.lock()
	if _shared_mesh == null:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
			Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1),
			Vector3(-1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1),
		])
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([
			Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP,
		])
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_shared_mesh = mesh
	var result := _shared_mesh
	_shared_mesh_mutex.unlock()
	return result

## Builds the fixture `id`. Unknown ids return null (the harness reports them).
static func build(id : String) -> FlowData.Data:
	match id:
		"points":
			return points(POINT_COUNT)
		"points_b":
			return points(POINT_COUNT_B, Vector3(1.0, 0.0, 1.0), 7)
		"single":
			return points(1)
		"empty":
			return FlowDataScript.Data.new()
		"empty_schema":
			return points(0)
		"tagged":
			var d := points(POINT_COUNT)
			d.tags = PackedStringArray(["conformance_tag_a", "conformance_tag_b"])
			return d
		"data_attrs":
			var d := points(POINT_COUNT)
			d.set_data_attr("df_attr", 2.5, FlowData.DataType.Float)
			d.set_data_attr("di_attr", 3, FlowData.DataType.Int)
			d.set_data_attr("ds_attr", "conformance", FlowData.DataType.String)
			d.set_data_attr("dv_attr", Vector3(1, 2, 3), FlowData.DataType.Vector)
			d.set_data_attr("dc_attr", Color(0.25, 0.5, 0.75, 1.0), FlowData.DataType.Color)
			return d
		"attr_set":
			return attribute_set(4)
		"spline":
			return FlowDataScript.Data.from_shape(spline_shape())
		"surface_polygon":
			return FlowDataScript.Data.from_shape(polygon_surface())
		"surface_heightfield":
			return FlowDataScript.Data.from_shape(heightfield_surface())
		"surface_mesh":
			return FlowDataScript.Data.from_shape(mesh_surface())
		"volume_box":
			return FlowDataScript.Data.from_shape(box_volume())
		"volume_sphere":
			return FlowDataScript.Data.from_shape(sphere_volume())
		"composite":
			return FlowDataScript.Data.from_shape(FlowCompositeShape.new(FlowSpatial.Op.Difference, box_volume(), sphere_volume()))
		"dungeon_rooms":
			# What dungeon_room_candidates emits: room centers with sizes and ids.
			var d := points(3)
			d.registerStream("RoomID", PackedInt32Array([0, 1, 2]), FlowData.DataType.Int)
			d.registerStream("RoomWidth", PackedFloat32Array([2, 3, 2]), FlowData.DataType.Float)
			d.registerStream("RoomHeight", PackedFloat32Array([2, 2, 3]), FlowData.DataType.Float)
			return d
		"dungeon_cells":
			# What dungeon_expand_rooms / dungeon_connect_rooms emit: floor cells.
			var d := FlowDataScript.Data.new()
			d.addCommonStreams(6)
			var positions := d.getVector3Container(FlowData.AttrPosition)
			var types := PackedStringArray()
			for i in range(6):
				positions[i] = Vector3((i % 3) * 2.0, 0.0, (i / 3) * 2.0)
				types.append("Room" if i < 4 else "Corridor")
			d.registerStream("CellType", types, FlowData.DataType.String)
			return d
	return null

## Fixtures that reference nodes of the evaluation owner's scene (see
## conformance_harness._make_owner): "scene_meshes" is what scan_meshes emits
## for its MeshInstance3D, "scene_paths" what scan_splines emits for its Path3D.
## Returns null without an owner or for other ids.
static func build_scene(id : String, owner : Node3D) -> FlowData.Data:
	if owner == null:
		return null
	match id:
		"scene_meshes":
			var mesh_instance := owner.get_node_or_null("ConformanceMesh") as MeshInstance3D
			if mesh_instance == null:
				return null
			var d := FlowDataScript.Data.new()
			d.registerStream("node", [ mesh_instance ], FlowData.DataType.NodeMesh)
			d.registerStream("mesh", [ mesh_instance.mesh ], FlowData.DataType.Resource)
			return d
		"scene_paths":
			var path := owner.get_node_or_null("ConformancePath") as Path3D
			if path == null:
				return null
			var d := FlowDataScript.Data.new()
			d.registerStream("node", [ path ], FlowData.DataType.NodePath)
			d.registerStream("curve", [ path.curve ], FlowData.DataType.Resource)
			return d
	return null

## Fixtures that need no scene.
const SPECIAL := [ "dungeon_rooms", "dungeon_cells" ]
## Fixtures built from the owner scene (build_scene).
const SCENE := [ "scene_meshes", "scene_paths" ]

## Every fixture id the library knows that needs no scene.
static func all_ids() -> Array:
	var ids := PRIMARY.duplicate()
	for id in SECONDARY + SPECIAL:
		if not ids.has(id):
			ids.append(id)
	return ids

## `count` points with every canonical stream (position, rotation, size,
## density, seed, normal, bounds_min, bounds_max, steepness) and one attribute
## of every DataType (ATTRIBUTES). Positions lie on a jittered 4-wide grid
## spaced 2 m apart in XZ, starting at `offset`; `salt` varies the values.
static func points(count : int, offset : Vector3 = Vector3.ZERO, salt : int = 0) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	var position := PackedVector3Array()
	var rotation := PackedVector3Array()
	var size := PackedVector3Array()
	var density := PackedFloat32Array()
	var seeds := PackedInt32Array()
	var normal := PackedVector3Array()
	var bounds_min := PackedVector3Array()
	var bounds_max := PackedVector3Array()
	var steepness := PackedFloat32Array()
	for i in range(count):
		var k := i + salt
		var jitter := Vector3(_frac(k, 1) * 0.5, _frac(k, 2) * 0.25, _frac(k, 3) * 0.5)
		position.append(offset + Vector3(float(i % 4) * 2.0, 0.0, float(i / 4) * 2.0) + jitter)
		rotation.append(Vector3(0.0, float((k * 37) % 360), 0.0))
		size.append(Vector3.ONE * (0.5 + _frac(k, 4)))
		density.append(0.05 + 0.9 * _frac(k, 5))
		seeds.append(1000 + k * 31)
		normal.append(Vector3(_frac(k, 6) - 0.5, 1.0, _frac(k, 7) - 0.5).normalized())
		bounds_min.append(Vector3(-0.5, -0.25, -0.5))
		bounds_max.append(Vector3(0.5, 0.75, 0.5))
		steepness.append(0.5)
	d.registerStream(FlowData.AttrPosition, position, FlowData.DataType.Vector)
	d.registerStream(FlowData.AttrRotation, rotation, FlowData.DataType.Vector)
	d.registerStream(FlowData.AttrSize, size, FlowData.DataType.Vector)
	d.registerStream(FlowData.AttrDensity, density, FlowData.DataType.Float)
	d.registerStream(FlowData.AttrSeed, seeds, FlowData.DataType.Int)
	d.registerStream(FlowData.AttrNormal, normal, FlowData.DataType.Vector)
	d.registerStream(FlowData.AttrBoundsMin, bounds_min, FlowData.DataType.Vector)
	d.registerStream(FlowData.AttrBoundsMax, bounds_max, FlowData.DataType.Vector)
	d.registerStream(FlowData.AttrSteepness, steepness, FlowData.DataType.Float)
	_add_typed_attributes(d, count, salt)
	return d

## An attribute set (Kind.AttrSet): `count` rows of f_attr, i_attr, s_attr,
## v_attr and c_attr, no spatial streams.
static func attribute_set(count : int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	var f := PackedFloat32Array()
	var n := PackedInt32Array()
	var s := PackedStringArray()
	var v := PackedVector3Array()
	var c := PackedColorArray()
	for i in range(count):
		f.append(0.5 + float(i))
		n.append(i * 2)
		s.append(_label(i))
		v.append(Vector3(i, i * 0.5, -i))
		c.append(Color(_frac(i, 8), _frac(i, 9), _frac(i, 10), 1.0))
	d.registerStream("f_attr", f, FlowData.DataType.Float)
	d.registerStream("i_attr", n, FlowData.DataType.Int)
	d.registerStream("s_attr", s, FlowData.DataType.String)
	d.registerStream("v_attr", v, FlowData.DataType.Vector)
	d.registerStream("c_attr", c, FlowData.DataType.Color)
	d.kind = FlowData.Kind.AttrSet
	return d

static func spline_shape() -> FlowSplineShape:
	var curve := Curve3D.new()
	curve.add_point(Vector3(0, 0, 0))
	curve.add_point(Vector3(4, 0, 2), Vector3(-1, 0, 0), Vector3(1, 0, 0))
	curve.add_point(Vector3(8, 0, 0))
	return FlowSplineShape.new(curve, Transform3D.IDENTITY, false, 1.0, 1.0)

static func polygon_surface() -> FlowPolygonSurface:
	var polygon := PackedVector2Array([Vector2(0, 0), Vector2(6, 0), Vector2(6, 6), Vector2(0, 6)])
	return FlowPolygonSurface.new(polygon, Transform3D.IDENTITY, 0.0)

static func heightfield_surface() -> FlowHeightfieldSurface:
	var heights := PackedFloat32Array()
	for z in range(4):
		for x in range(4):
			heights.append(0.25 * float((x * 3 + z * 5) % 4))
	return FlowHeightfieldSurface.new(heights, 4, 4, 2.0)

static func mesh_surface() -> FlowMeshSurface:
	return FlowMeshSurface.new(PackedVector3Array([
		Vector3(0, 0, 0), Vector3(6, 0, 0), Vector3(6, 0.5, 6),
		Vector3(0, 0, 0), Vector3(6, 0.5, 6), Vector3(0, 0, 6),
	]))

static func box_volume() -> FlowBoxVolume:
	return FlowBoxVolume.new(Transform3D(Basis.IDENTITY, Vector3(3, 0, 3)), Vector3(3, 2, 3), 1.0)

static func sphere_volume() -> FlowSphereVolume:
	return FlowSphereVolume.at(Vector3(2, 0, 2), 2.0, 0.5)

static func _add_typed_attributes(d : FlowData.Data, count : int, salt : int) -> void:
	for attr_name in ATTRIBUTES:
		var data_type : int = ATTRIBUTES[attr_name]
		var container = FlowDataScript.Data.newContainerOfType(data_type)
		container.resize(count)
		for i in range(count):
			FlowDataScript.Data.writeValue(container, i, _typed_value(data_type, i + salt), data_type)
		d.registerStream(attr_name, container, data_type)

static func _typed_value(data_type : int, k : int):
	match data_type:
		FlowData.DataType.Float:
			return 0.1 + float(k % 5) * 0.75
		FlowData.DataType.Int:
			return k % 3
		FlowData.DataType.Bool:
			return k % 2 == 0
		FlowData.DataType.Vector:
			return Vector3(k, -k * 0.5, 1.0 + _frac(k, 11))
		FlowData.DataType.String:
			return _label(k)
		FlowData.DataType.Color:
			return Color(_frac(k, 12), _frac(k, 13), _frac(k, 14), 1.0)
		FlowData.DataType.Quaternion:
			return Quaternion(Vector3.UP, float(k) * 0.3)
		FlowData.DataType.Resource:
			return shared_mesh()
		FlowData.DataType.Vector2:
			return Vector2(k * 0.5, 1.0 - k * 0.25)
		FlowData.DataType.Vector4:
			return Vector4(k, k + 1, k + 2, k + 3)
		FlowData.DataType.Transform:
			return Transform3D(Basis(Vector3.UP, float(k) * 0.2), Vector3(k, 0, -k))
		FlowData.DataType.Int64:
			return 5000000000 + k
		FlowData.DataType.Double:
			return 1.0 / 3.0 + float(k)
	return null

static func _label(k : int) -> String:
	return ["alpha", "beta", "gamma"][k % 3]

# Deterministic value in [0, 1) from an index and a channel.
static func _frac(k : int, channel : int) -> float:
	var h := (k * 73856093) ^ (channel * 19349663)
	return float(posmod(h, 1000)) / 1000.0
