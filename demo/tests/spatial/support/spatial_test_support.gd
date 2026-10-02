extends RefCounted

## Helpers for the WP2 spatial node tests: run one node element on inputs,
## collect its bulks, compare Data byte for byte, build small scenes.
## Works whether FlowNodeBase is a Node (today) or a RefCounted element.

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const LEGACY_DIR := "res://tests/spatial/legacy"

## Runs `script` (a node script) with `settings` on `inputs`. `owner` becomes
## ctx.owner. Returns the node; release it with release().
static func run(script, settings, inputs : Array, owner : Node3D = null, graph_seed : int = 0, template : String = ""):
	var node = script.new()
	node.name = "spatial_test_node"
	if template != "":
		node.node_template = template
	node.settings = settings
	node.inputs = inputs
	var ctx := FlowDataScript.EvaluationContext.new()
	ctx.owner = owner
	ctx.seed = graph_seed
	ctx.gedit_nodes_by_name = {}
	node.preExecute(ctx)
	node.execute(ctx)
	return node

static func release(node) -> void:
	if node is Object and is_instance_valid(node) and not (node is RefCounted):
		node.free()

## Every Data the node emitted on `port`, one per bulk.
static func outputs(node, port : int = 0) -> Array:
	var out := []
	for bulk in node.generated_bulks:
		out.append(bulk[port] if port < bulk.size() else null)
	return out

static func output(node, port : int = 0, bulk : int = 0) -> FlowData.Data:
	var all := outputs(node, port)
	return all[bulk] if bulk < all.size() else null

## Lazily loaded frozen copy of a node script as of the pre-WP2 base commit.
static func legacy(name : String):
	return load(LEGACY_DIR.path_join("legacy_%s.gd" % name))

## Exact equality of two Data: stream order, names, types, containers (==, so
## float bits must match), last stream, tags, data attributes, kind and shape.
static func same_data(a : FlowData.Data, b : FlowData.Data) -> bool:
	if a == null or b == null:
		return a == b
	if a.streams.keys() != b.streams.keys():
		return false
	for k in a.streams:
		var sa : Dictionary = a.streams[k]
		var sb : Dictionary = b.streams[k]
		if sa.data_type != sb.data_type or sa.container != sb.container:
			return false
	return a.last_added_stream_name == b.last_added_stream_name \
		and a.tags == b.tags and a.data_attrs == b.data_attrs \
		and a.kind == b.kind and a.shape == b.shape

## Same bulks, ports, Data and error text.
static func same_node_output(a, b) -> bool:
	if a.err != b.err:
		return false
	if a.generated_bulks.size() != b.generated_bulks.size():
		return false
	for i in a.generated_bulks.size():
		var ba : Array = a.generated_bulks[i]
		var bb : Array = b.generated_bulks[i]
		if ba.size() != bb.size():
			return false
		for p in ba.size():
			if not same_data(ba[p], bb[p]):
				return false
	return true

static func points(positions : Array, sizes : Array = []) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.addCommonStreams(positions.size())
	var pos := d.getVector3Container(FlowData.AttrPosition)
	var siz := d.getVector3Container(FlowData.AttrSize)
	for i in positions.size():
		pos[i] = positions[i]
		if i < sizes.size():
			siz[i] = sizes[i]
	return d

static func line_curve(a : Vector3, b : Vector3) -> Curve3D:
	var c := Curve3D.new()
	c.add_point(a)
	c.add_point(b)
	return c

static func square_curve(half : float, closed_point : bool = true) -> Curve3D:
	var c := Curve3D.new()
	for p in [Vector3(-half, 0, -half), Vector3(half, 0, -half), Vector3(half, 0, half), Vector3(-half, 0, half)]:
		c.add_point(p)
	if closed_point:
		c.add_point(Vector3(-half, 0, -half))
	return c

static func plane_mesh(size : float = 10.0, subdiv : int = 9) -> PlaneMesh:
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.subdivide_width = subdiv
	plane.subdivide_depth = subdiv
	return plane
