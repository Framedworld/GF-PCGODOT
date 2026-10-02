extends RefCounted

## Helpers for the hierarchical-generation (WP5) suites: canonical point rows
## for order-independent comparison, the monolithic reference (the same graph
## through FlowNodeIO.evaluate, culled to the world bounds), and the stock
## scatter graphs used by the partition-invariance tests.

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")

## One row per point: [position, <every other stream value in stream-name
## order>]. Rows are sorted by position (x, z, y), then by the full row text.
static func rows(datas : Array) -> Array:
	var result : Array = []
	for data in datas:
		if not (data is FlowData.Data):
			continue
		var names : Array = []
		for stream_name in data.streams:
			if str(stream_name) != str(FlowData.AttrPosition):
				names.append(str(stream_name))
		names.sort()
		var positions : PackedVector3Array = data.getVector3Container(FlowData.AttrPosition)
		for i in range(data.size()):
			var row : Array = [positions[i] if i < positions.size() else Vector3.INF]
			for stream_name in names:
				var container = data.streams[StringName(stream_name)].container if data.streams.has(StringName(stream_name)) else data.streams[stream_name].container
				row.append([stream_name, container[FlowData.bcast_idx(container.size(), i)] if container.size() > 0 else null])
			result.append(row)
	result.sort_custom(_row_less)
	return result

static func _row_less(a : Array, b : Array) -> bool:
	var pa : Vector3 = a[0]
	var pb : Vector3 = b[0]
	if pa.x != pb.x:
		return pa.x < pb.x
	if pa.z != pb.z:
		return pa.z < pb.z
	if pa.y != pb.y:
		return pa.y < pb.y
	return var_to_str(a) < var_to_str(b)

## Half-open cull of a Data to `bounds` (the cull node's semantics).
static func cull(data : FlowData.Data, bounds : AABB) -> FlowData.Data:
	var keep := PackedInt32Array()
	var positions : PackedVector3Array = data.getVector3Container(FlowData.AttrPosition)
	for i in range(positions.size()):
		if FlowWorldGrid.owns(bounds, positions[i]):
			keep.append(i)
	return data.filter(keep)

## The graph evaluated once, owner-less, with `bounds_node`'s fallback bounds
## set to the world bounds, then culled to the world bounds.
static func monolithic(graph : FlowGraphResource, world_bounds : AABB, bounds_nodes : Array, output_name : String = "result", seed : int = 0) -> FlowData.Data:
	var overrides := {}
	for bounds_node in bounds_nodes:
		overrides["%s/fallback_bounds" % bounds_node] = world_bounds
	var outputs := FlowNodeIO.evaluate(graph, {}, seed, {}, null, overrides)
	var data = outputs.get(output_name)
	if not (data is FlowData.Data):
		return FlowData.Data.new()
	return cull(data, world_bounds)

## Outputs named `output_name` of every generated cell of `level`.
static func cell_outputs(world : FlowWorld3D, level : int, output_name : String = "result") -> Array:
	var result : Array = []
	for key in world.get_cells(FlowWorld3D.CellState.Generated):
		if key.x != level:
			continue
		var data = world.get_cell_outputs(key.x, Vector2i(key.y, key.z)).get(output_name)
		if data is FlowData.Data:
			result.append(data)
	return result

## A FlowWorld3D for `graph`, added under `parent`.
static func make_world(parent : Node, graph : FlowGraphResource, world_bounds : AABB, seed : int = 0) -> FlowWorld3D:
	var world := FlowWorld3D.new()
	world.graph = graph
	world.world_bounds = world_bounds
	world.seed = seed
	parent.add_child(world)
	return world

## A small deterministic heightmap image (gentle hills), size x size.
static func heightmap(size : int = 65) -> Image:
	var image := Image.create(size, size, false, Image.FORMAT_RF)
	for z in range(size):
		for x in range(size):
			var h := 0.5 + 0.25 * sin(x * 0.37) * cos(z * 0.23) + 0.1 * sin((x + z) * 0.11)
			image.set_pixel(x, z, Color(h, 0.0, 0.0))
	return image

## Scatter graphs that share one shape: a level-`grid` execution-bounds node
## ("bounds") feeding `sampler` nodes, then a cull ("cull") and the output
## "result". `kind` picks the sampler:
##   "surface_ppsm"   surface_sampler on a heightfield, Bounding Shape = bounds
##   "surface_count"  the same in Count mode
##   "surface_points" surface_sampler point path (num_points in the bounds point)
##   "volume_shape"   volume_sampler on (big box intersect bounds)
##   "to_point"       to_point on the bounds box
##   "grid_fill"      grid_fill_bounds on the bounds point
##   "sample_points"  sample_points (uniform grid) on the bounds point
##   "sample_points_random" sample_points (quasi random) on the bounds point
##   "grid"           a fixed Unbounded grid passed whole to the cells
static func scatter_graph(kind : String, grid : int = 32) -> FlowGraphResource:
	var b = TestGraph.new()
	b.node("marker", "grid_size", {"cell_size": float(grid)})
	var points_mode := kind in ["surface_points", "grid_fill", "sample_points", "sample_points_random"]
	b.node("bounds", "get_execution_bounds", {"output_mode": 1 if points_mode else 0})
	b.link("marker", 0, "bounds", 0)
	b.node("cull", "cull_points_outside_bounds", {})
	b.node("out", "output", {"name": "result"})
	b.link("cull", 0, "out", 0)
	match kind:
		"surface_ppsm", "surface_count":
			b.node("surface", "get_surface_data", {"source": 1, "heightmap_image": heightmap(), "image_cell_size": 1.5, "image_height_scale": 4.0})
			var sampler := {"points_per_square_meter": 0.35, "use_bounding_shape": true, "random_seed": 77, "looseness": 1.0, "point_extents": Vector3(0.3, 0.3, 0.3)}
			if kind == "surface_count":
				sampler["shape_sampling"] = 1
				sampler["num_points"] = 60
			b.node("sampler", "surface_sampler", sampler)
			b.link("surface", 0, "sampler", 0)
			b.link("bounds", 0, "sampler", 1)
		"surface_points":
			b.node("sampler", "surface_sampler", {"num_points": 40, "random_seed": 5})
			b.link("bounds", 0, "sampler", 0)
		"volume_shape":
			b.node("box", "make_bounds", {"output_mode": 1, "size": Vector3(70.0, 6.0, 70.0), "center": Vector3(3.0, 0.0, -2.0)})
			b.node("isect", "intersection", {})
			b.node("sampler", "volume_sampler", {"voxel_size": Vector3(3.0, 3.0, 3.0)})
			b.link("box", 0, "isect", 0)
			b.link("bounds", 0, "isect", 1)
			b.link("isect", 0, "sampler", 0)
		"to_point":
			b.node("sampler", "to_point", {"voxel_size": Vector3(4.0, 8.0, 4.0)})
			b.link("bounds", 0, "sampler", 0)
		"grid_fill":
			b.node("sampler", "grid_fill_bounds", {"cell_size": Vector3(3.0, 1.0, 3.0), "copy_input_attributes": false})
			b.link("bounds", 0, "sampler", 0)
		"sample_points":
			b.node("sampler", "sample_points", {"distribution": 0, "sampling_distance": 2.5, "random_seed": 9})
			b.link("bounds", 0, "sampler", 0)
		"sample_points_random":
			b.node("sampler", "sample_points", {"distribution": 1, "num_samples": 50, "random_seed": 9})
			b.link("bounds", 0, "sampler", 0)
		"grid":
			# Unbounded source, passed whole to every cell through the marker.
			b.node("sampler", "grid", {"x": 30, "y": 1, "z": 30, "step": Vector3(2.5, 1.0, 2.5), "origin": Vector3(-37.0, 0.0, -37.0), "random_seed": 4})
			b.link("sampler", 0, "marker", 0)
			b.link("marker", 0, "cull", 0)
			return b.build()
	b.link("sampler", 0, "cull", 0)
	return b.build()
