extends RefCounted

## Fakes of the terrain plugin APIs the duck-typed adapters call. Each fake
## implements EXACTLY the members FlowTerrain3DAdapter / FlowHTerrainAdapter use
## (see the headers of those scripts), and nothing else, so these tests check
## the adapters against the assumed API. They were never compared with the real
## Terrain3D or HTerrain plugins.

# --- Terrain3D (TokisanGames), 1.0 API as recalled ------------------------------------

## Terrain3DTextureAsset: only get_name().
class FakeTextureAsset extends RefCounted:
	var _name : String
	func _init(n : String) -> void:
		_name = n
	func get_name() -> String:
		return _name

## Terrain3DAssets: get_texture_count() and get_texture(id).
class FakeTerrain3DAssets extends RefCounted:
	var textures : Array = []
	func get_texture_count() -> int:
		return textures.size()
	func get_texture(id : int):
		return textures[id] if id >= 0 and id < textures.size() else null

## Terrain3DData. Height h(x, z) = 2 + 0.1 x + 0.05 z inside the regions, NaN
## outside them and in the hole [10, 14] x [10, 14]. Control map: base texture
## 0 for x < 0 else 1; overlay texture 2 blended at 0.25 where z > 0.
class FakeTerrain3DData extends RefCounted:
	var region_locations : Array = []
	var region_world : float = 64.0
	var height_offset : float = 2.0
	var calls : Dictionary = {}

	func _count(m : String) -> void:
		calls[m] = int(calls.get(m, 0)) + 1

	func _inside(p : Vector3) -> bool:
		if p.x >= 10.0 and p.x <= 14.0 and p.z >= 10.0 and p.z <= 14.0:
			return false
		for loc in region_locations:
			var x0 : float = loc.x * region_world
			var z0 : float = loc.y * region_world
			if p.x >= x0 and p.x <= x0 + region_world and p.z >= z0 and p.z <= z0 + region_world:
				return true
		return false

	func get_height(global_position : Vector3) -> float:
		_count("get_height")
		if not _inside(global_position):
			return NAN
		return height_offset + 0.1 * global_position.x + 0.05 * global_position.z

	func get_normal(global_position : Vector3) -> Vector3:
		_count("get_normal")
		if not _inside(global_position):
			return Vector3(NAN, NAN, NAN)
		return Vector3(-0.1, 1.0, -0.05).normalized()

	func get_texture_id(global_position : Vector3) -> Vector3:
		_count("get_texture_id")
		if not _inside(global_position):
			return Vector3(NAN, NAN, NAN)
		var base := 0.0 if global_position.x < 0.0 else 1.0
		var blend := 0.25 if global_position.z > 0.0 else 0.0
		return Vector3(base, 2.0, blend)

	func get_region_locations() -> Array:
		_count("get_region_locations")
		return region_locations

	func get_height_range() -> Vector2:
		_count("get_height_range")
		return Vector2(height_offset - 9.6, height_offset + 9.6)

## Terrain3D node: the `data` property (and its getter get_data(), which a
## GDExtension property also has), region_size, vertex_spacing, assets.
class FakeTerrain3D extends Node3D:
	var data : Object
	var region_size : int = 32
	var vertex_spacing : float = 2.0
	var assets : Object
	func get_data() -> Object:
		return data

## Pre-1.0 Terrain3D: the data object is called `storage`; no assets, no
## regions (bounds must be given).
class FakeTerrain3DLegacy extends Node3D:
	var storage : Object

# --- HTerrain (Zylann), godot_heightmap_plugin 1.7.x API as recalled ------------------------

## HTerrainData. Raw height of cell (cx, cz) = 0.5 cx + 0.25 cz. Splat maps
## (RGBA8, one per index) are given by the test.
class FakeHTerrainData extends Resource:
	const CHANNEL_HEIGHT = 0
	const CHANNEL_NORMAL = 1
	const CHANNEL_SPLAT = 2
	var resolution : int = 17
	var splat_maps : Array = []
	var calls : Dictionary = {}

	func _count(m : String) -> void:
		calls[m] = int(calls.get(m, 0)) + 1

	func _raw(cx : float, cz : float) -> float:
		return 0.5 * cx + 0.25 * cz

	func get_resolution() -> int:
		_count("get_resolution")
		return resolution

	func get_interpolated_height_at(pos : Vector3) -> float:
		_count("get_interpolated_height_at")
		return _raw(clampf(pos.x, 0.0, resolution - 1), clampf(pos.z, 0.0, resolution - 1))

	func get_height_at(x : int, y : int) -> float:
		_count("get_height_at")
		return _raw(clampi(x, 0, resolution - 1), clampi(y, 0, resolution - 1))

	func get_map_count(map_type : int) -> int:
		_count("get_map_count")
		return splat_maps.size() if map_type == CHANNEL_SPLAT else 1

	func get_image(map_type : int, index : int = 0) -> Image:
		_count("get_image")
		if map_type == CHANNEL_SPLAT and index >= 0 and index < splat_maps.size():
			return splat_maps[index]
		return null

## HTerrain node: get_data() and get_internal_transform().
class FakeHTerrain extends Node3D:
	var _data : Object
	var internal_transform : Transform3D = Transform3D.IDENTITY
	func get_data() -> Object:
		return _data
	func get_internal_transform() -> Transform3D:
		return internal_transform

## HTerrain without get_internal_transform(): the adapter falls back to the node
## transform, map_scale and centered.
class FakeHTerrainNoInternal extends Node3D:
	var _data : Object
	var map_scale : Vector3 = Vector3.ONE
	var centered : bool = false
	func get_data() -> Object:
		return _data

# --- builders ---------------------------------------------------------------------------

static func terrain3d(regions : Array = [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)], with_assets : bool = true) -> FakeTerrain3D:
	var t := FakeTerrain3D.new()
	t.name = "Terrain3D"
	var d := FakeTerrain3DData.new()
	d.region_locations = regions
	d.region_world = t.region_size * t.vertex_spacing
	t.data = d
	if with_assets:
		var a := FakeTerrain3DAssets.new()
		a.textures = [FakeTextureAsset.new("grass"), FakeTextureAsset.new("rock"), FakeTextureAsset.new("sand")]
		t.assets = a
	return t

static func splat_image(res : int, fn : Callable) -> Image:
	var img := Image.create(res, res, false, Image.FORMAT_RGBA8)
	for y in res:
		for x in res:
			img.set_pixel(x, y, fn.call(x, y))
	return img

static func hterrain(res : int = 17, xform : Transform3D = Transform3D.IDENTITY, splats : int = 2) -> FakeHTerrain:
	var t := FakeHTerrain.new()
	t.name = "HTerrain"
	var d := FakeHTerrainData.new()
	d.resolution = res
	for m in splats:
		d.splat_maps.append(splat_image(res, func(x, y): return Color(float(x) / (res - 1), float(y) / (res - 1), 0.5 if m == 0 else 0.0, 1.0 - float(x) / (res - 1))))
	t._data = d
	t.internal_transform = xform
	return t
