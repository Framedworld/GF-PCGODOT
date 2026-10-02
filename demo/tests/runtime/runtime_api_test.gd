# runtime_api_test.gd
#
# P0 runtime API (docs/RUNTIME_API_P0.md §1, §2, §3, §5, §6): FlowGraphNode3D
# generate/cleanup/seed, FlowNodeIO.make_context/evaluate, owner-less
# evaluation, generated-content ownership, boundary data and Data helpers.
class_name RuntimeApiTest extends GdUnitTestSuite

# flow_data.gd first: preloading a node script before it hits a pre-existing
# script-load cycle (node.gd <-> flow_nodes_io.gd <-> assets.gd).
const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const SpawnMeshesNode = preload("res://addons/flow_nodes_editor/nodes/spawn_meshes.gd")
const ApplyOnActorNode = preload("res://addons/flow_nodes_editor/nodes/apply_on_actor.gd")
const OutputNode = preload("res://addons/flow_nodes_editor/nodes/output.gd")
const LoopNode = preload("res://addons/flow_nodes_editor/nodes/loop.gd")
const OWNER_ERROR := "needs an owner node; generate through a FlowGraphNode3D or pass owner to FlowNodeIO.evaluate"


# --- graph builders ----------------------------------------------------------

func _node(node_name : String, template : String, node_settings : Dictionary = {}) -> Dictionary:
	return { "name": StringName(node_name), "template": template, "settings": node_settings }


func _link(from_node : String, to_node : String, from_port := 0, to_port := 0) -> Dictionary:
	return { "from_node": StringName(from_node), "from_port": from_port, "to_node": StringName(to_node), "to_port": to_port }


func _param(param_name : String, data_type : int = FlowData.DataType.Float) -> GraphInputParameter:
	var p := GraphInputParameter.new()
	p.name = param_name
	p.data_type = data_type
	return p


func _graph(nodes : Array, links : Array, in_names : Array = [], out_names : Array = []) -> FlowGraphResource:
	var g := FlowGraphResource.new()
	g.data = { "nodes": nodes, "links": links }
	var ins : Array[GraphInputParameter] = []
	for n in in_names:
		ins.append(_param(n))
	var outs : Array[GraphInputParameter] = []
	for n in out_names:
		outs.append(_param(n))
	g.in_params = ins
	g.out_params = outs
	return g


# grid (3x1x3, emits a per-point seed stream) -> attribute_random "r" -> output "out_val"
func _random_graph() -> FlowGraphResource:
	return _graph(
		[
			_node("grid", "grid", { "x": 3, "y": 1, "z": 3, "random_seed": 4242 }),
			_node("rand", "attribute_random", { "attribute_name": "r", "min_value": 0.0, "max_value": 1000.0, "random_seed": 99 }),
			_node("out", "output", { "name": "out_val" }),
		],
		[ _link("grid", "rand"), _link("rand", "out") ])


# grid -> spawn_meshes (optionally into a shared parent) -> output "out_val"
func _spawn_graph(spawn_parent_path : String = "") -> FlowGraphResource:
	return _graph(
		[
			_node("grid", "grid", { "x": 2, "y": 1, "z": 2 }),
			_node("spawn", "spawn_meshes", { "spawn_parent_path": spawn_parent_path, "use_vertex_colors": false }),
			_node("out", "output", { "name": "out_val" }),
		],
		[ _link("grid", "spawn"), _link("spawn", "out") ])


func _stream(outputs : Dictionary, out_name : String, stream_name : String):
	var data = outputs.get(out_name, null)
	assert_object(data).is_not_null()
	if data == null:
		return null
	return data.container(stream_name)


func _component(g : FlowGraphResource, parent : Node = self) -> FlowGraphNode3D:
	var c := FlowGraphNode3D.new()
	c.generate_on_ready = false
	c.graph = g
	parent.add_child(c)
	return c


func _legacy_evaluate(g : FlowGraphResource, owner_node : FlowGraphNode3D) -> Dictionary:
	var ctx = FlowData.EvaluationContext.new()
	ctx.owner = owner_node
	ctx.eval_id = 0
	ctx.gedit_nodes_by_name = {}
	ctx.runtime_params = {}
	return FlowNodeIO.evaluate_graph(g, {}, ctx, {}, 0)


func _generated_children(parent : Node) -> Array:
	return parent.get_children().filter(func(c): return c.has_meta("flow_owner"))


# --- §1 FlowGraphNode3D ------------------------------------------------------

func test_generate_returns_outputs_and_emits_generated() -> void:
	var c := _component(_random_graph())
	var received := []
	c.generated.connect(func(outputs): received.append(outputs))
	var outputs := c.generate()
	assert_bool(outputs.has("out_val")).is_true()
	assert_int(_stream(outputs, "out_val", "r").size()).is_equal(9)
	assert_int(received.size()).is_equal(1)
	assert_bool(received[0] == outputs).is_true()
	assert_bool(c.last_outputs == outputs).is_true()
	assert_bool(c.is_generating()).is_false()


func test_generate_merges_inputs_over_args_and_params() -> void:
	var g := _graph(
		[ _node("in", "input", { "name": "value" }), _node("out", "output", { "name": "value_out" }) ],
		[ _link("in", "out") ], ["value"], ["value_out"])
	var c := _component(g)
	c.args = { "value": 1.0 }
	c.params = { "knob": 3 }
	assert_float(_stream(c.generate(), "value_out", "value")[0]).is_equal(1.0)
	assert_float(_stream(c.generate({ "value": 5.0 }), "value_out", "value")[0]).is_equal(5.0)
	# args itself is not modified by per-call inputs
	assert_float(c.args["value"]).is_equal(1.0)


func test_execute_is_a_thin_wrapper_over_generate() -> void:
	var c := _component(_random_graph())
	var received := []
	c.generated.connect(func(outputs): received.append(outputs))
	c.execute()
	assert_int(received.size()).is_equal(1)
	assert_int(_stream(c.last_outputs, "out_val", "r").size()).is_equal(9)


func test_generate_on_ready_controls_automatic_generation() -> void:
	var off := FlowGraphNode3D.new()
	off.graph = _random_graph()
	off.generate_on_ready = false
	add_child(off)
	assert_bool(off.last_outputs.is_empty()).is_true()

	var on := FlowGraphNode3D.new()
	on.graph = _random_graph()
	add_child(on)
	assert_bool(on.last_outputs.has("out_val")).is_true()


func test_generate_async_emits_generated_on_completion() -> void:
	var c := _component(_random_graph())
	c.frame_budget_ms = 0.0
	var received := []
	c.generated.connect(func(outputs): received.append(outputs))
	c.generate_async()
	assert_bool(c.is_generating()).is_true()
	for i in range(30):
		if not received.is_empty():
			break
		await get_tree().process_frame
	assert_int(received.size()).is_equal(1)
	assert_bool(c.is_generating()).is_false()
	assert_int(_stream(c.last_outputs, "out_val", "r").size()).is_equal(9)


func test_generate_without_graph_returns_empty_silently() -> void:
	var c := _component(null)
	var received := []
	c.generated.connect(func(outputs): received.append(outputs))
	assert_bool(c.generate().is_empty()).is_true()
	assert_bool(received.is_empty()).is_true()
	# generate_on_ready with no graph is a silent no-op as well.
	var on := FlowGraphNode3D.new()
	on.graph = null
	add_child(on)
	assert_bool(on.last_outputs.is_empty()).is_true()


# --- §2 seed -----------------------------------------------------------------

func test_seed_zero_reproduces_legacy_output_bit_for_bit() -> void:
	var g := _random_graph()
	var c := _component(g)
	var legacy := _legacy_evaluate(g, c)
	c.seed = 0
	var outputs := c.generate()
	assert_array(_stream(outputs, "out_val", "r")).is_equal(_stream(legacy, "out_val", "r"))
	assert_array(_stream(outputs, "out_val", "seed")).is_equal(_stream(legacy, "out_val", "seed"))
	var evaluated := FlowNodeIO.evaluate(g, {}, 0, {}, c)
	assert_array(_stream(evaluated, "out_val", "r")).is_equal(_stream(legacy, "out_val", "r"))


func test_seed_changes_output_and_is_deterministic() -> void:
	var g := _random_graph()
	var base : PackedFloat32Array = _stream(FlowNodeIO.evaluate(g), "out_val", "r")
	var s5 : PackedFloat32Array = _stream(FlowNodeIO.evaluate(g, {}, 5), "out_val", "r")
	var s5_again : PackedFloat32Array = _stream(FlowNodeIO.evaluate(g, {}, 5), "out_val", "r")
	var s6 : PackedFloat32Array = _stream(FlowNodeIO.evaluate(g, {}, 6), "out_val", "r")
	assert_array(s5).is_equal(s5_again)
	assert_array(s5).is_not_equal(base)
	assert_array(s6).is_not_equal(s5)
	# The per-point seed stream written by the grid is decorrelated too.
	var seeds0 = _stream(FlowNodeIO.evaluate(g), "out_val", "seed")
	var seeds5 = _stream(FlowNodeIO.evaluate(g, {}, 5), "out_val", "seed")
	assert_array(seeds5).is_not_equal(seeds0)


func test_component_seed_drives_generation() -> void:
	var g := _random_graph()
	var c := _component(g)
	c.seed = 5
	assert_array(_stream(c.generate(), "out_val", "r")).is_equal(_stream(FlowNodeIO.evaluate(g, {}, 5), "out_val", "r"))


func test_effective_seed_formula() -> void:
	var node = OutputNode.new()
	node.settings = OutputNodeSettings.new()
	node.settings.random_seed = 77
	var ctx := FlowNodeIO.make_context(null, 0)
	node.preExecute(ctx)
	assert_int(node.effective_seed()).is_equal(77)
	assert_int(node.rng.seed).is_equal(77)
	ctx.seed = 31
	node.preExecute(ctx)
	var expected := int(hash([31, 77]) & 0x7fffffff)
	assert_int(node.effective_seed()).is_equal(expected)
	assert_int(node.rng.seed).is_equal(expected)


func test_derive_seed_is_the_shared_static_formula() -> void:
	assert_int(FlowNodeBase.derive_seed(0, 77)).is_equal(77)
	assert_int(FlowNodeBase.derive_seed(31, 77)).is_equal(int(hash([31, 77]) & 0x7fffffff))
	assert_int(FlowNodeBase.derive_seed(31, 77)).is_not_equal(FlowNodeBase.derive_seed(32, 77))


func test_subgraph_passes_seed_through() -> void:
	var inner := _random_graph()
	var outer := _graph(
		[ _node("sub", "subgraph", { "graph": inner }), _node("out", "output", { "name": "out_val" }) ],
		[ _link("sub", "out") ])
	for s in [0, 5]:
		var direct = _stream(FlowNodeIO.evaluate(inner, {}, s), "out_val", "r")
		var nested = _stream(FlowNodeIO.evaluate(outer, {}, s), "out_val", "r")
		assert_array(nested).is_equal(direct)


func _loop_graph() -> FlowGraphResource:
	# Body: item -> attribute_random "r" -> output "result". A one-element item
	# has no position/seed stream, so the random value depends only on the seed.
	var body := _graph(
		[
			_node("item_in", "input", { "name": "item" }),
			_node("rand", "attribute_random", { "attribute_name": "r", "min_value": 0.0, "max_value": 1000.0, "random_seed": 7 }),
			_node("result_out", "output", { "name": "result" }),
		],
		[ _link("item_in", "rand"), _link("rand", "result_out") ], ["item"], ["result"])
	return _graph(
		[
			_node("items_in", "input", { "name": "items" }),
			_node("loop", "loop", { "graph": body, "item_input_name": "item", "output_attribute_name": "result" }),
			_node("out", "output", { "name": "out_val" }),
		],
		[ _link("items_in", "loop"), _link("loop", "out") ], ["items"])


func test_loop_derives_per_iteration_seed() -> void:
	var g := _loop_graph()
	var items := FlowData.Data.new()
	items.registerStream("items", PackedFloat32Array([1.0, 2.0, 3.0]), FlowData.DataType.Float)
	var legacy : PackedFloat32Array = _stream(FlowNodeIO.evaluate(g, { "items": items }, 0), "out_val", "r")
	assert_int(legacy.size()).is_equal(3)
	# seed 0: every iteration runs with the same node seed (legacy behaviour)
	assert_float(legacy[1]).is_equal(legacy[0])
	assert_float(legacy[2]).is_equal(legacy[0])
	var seeded : PackedFloat32Array = _stream(FlowNodeIO.evaluate(g, { "items": items }, 9), "out_val", "r")
	assert_int(seeded.size()).is_equal(3)
	assert_float(seeded[1]).is_not_equal(seeded[0])
	assert_float(seeded[2]).is_not_equal(seeded[1])
	assert_array(_stream(FlowNodeIO.evaluate(g, { "items": items }, 9), "out_val", "r")).is_equal(seeded)


func test_loop_iteration_seed_formula() -> void:
	assert_int(LoopNode.iteration_seed(0, 3)).is_equal(0)
	assert_int(LoopNode.iteration_seed(9, 3)).is_equal(int(hash([9, 3]) & 0x7fffffff))
	assert_int(LoopNode.iteration_seed(9, 3)).is_equal(FlowNodeBase.derive_seed(9, 3))


# --- §3 FlowNodeIO -----------------------------------------------------------

func test_make_context_fields() -> void:
	var ctx := FlowNodeIO.make_context(null, 17, { "knob": 2 })
	assert_object(ctx.owner).is_null()
	assert_int(ctx.seed).is_equal(17)
	assert_int(ctx.component_id).is_equal(0)
	assert_int(ctx.eval_id).is_equal(0)
	assert_int(ctx.runtime_params["seed"]).is_equal(17)
	assert_int(ctx.runtime_params["knob"]).is_equal(2)

	var c := _component(_random_graph())
	c.overrides = { "rand/max_value": 5.0, "rand/min_value": 1.0 }
	var owned := FlowNodeIO.make_context(c, 3)
	assert_object(owned.owner).is_same(c)
	assert_int(owned.component_id).is_equal(c.get_instance_id())
	assert_dict(owned.overrides).is_equal({ "rand/max_value": 5.0, "rand/min_value": 1.0 })
	assert_int(owned.runtime_params["seed"]).is_equal(3)
	# Explicit overrides are merged over the owner's.
	var merged := FlowNodeIO.make_context(c, 3, {}, { "rand/max_value": 9.0, "grid/x": 2 })
	assert_dict(merged.overrides).is_equal({ "rand/max_value": 9.0, "rand/min_value": 1.0, "grid/x": 2 })
	assert_dict(c.overrides).is_equal({ "rand/max_value": 5.0, "rand/min_value": 1.0 })
	assert_dict(FlowNodeIO.make_context(null, 0, {}, { "a/b": 1 }).overrides).is_equal({ "a/b": 1 })


func test_child_context_copies_seed_component_and_overrides() -> void:
	var parent := FlowNodeIO.make_context(null, 11)
	parent.component_id = 99
	parent.overrides = { "a/b": 1 }
	var state : Dictionary = FlowNodeIO._build_evaluation_state(_random_graph(), {}, parent, {}, 1)
	var child = state["ctx"]
	assert_int(child.seed).is_equal(11)
	assert_int(child.component_id).is_equal(99)
	assert_dict(child.overrides).is_equal({ "a/b": 1 })
	assert_int(child.runtime_params["seed"]).is_equal(11)
	FlowNodeIO._finalize_evaluation(state)
	# The mirrored seed is local to each evaluation and never published upward.
	assert_int(parent.runtime_params["seed"]).is_equal(11)


func test_evaluate_without_owner() -> void:
	var outputs := FlowNodeIO.evaluate(_random_graph(), {}, 0, {}, null)
	assert_int(_stream(outputs, "out_val", "r").size()).is_equal(9)


func test_evaluate_without_owner_spawner_passes_input_through() -> void:
	var outputs := FlowNodeIO.evaluate(_spawn_graph())
	# spawn_meshes reports the owner error and forwards its 4 grid points.
	assert_int(_stream(outputs, "out_val", "position").size()).is_equal(4)


func test_spawner_without_owner_reports_documented_error() -> void:
	var points := FlowData.Data.new()
	points.addCommonStreams(3)
	var node = SpawnMeshesNode.new()
	node.name = "spawn"
	node.settings = SpawnMeshesNodeSettings.new()
	node.inputs = [points]
	var ctx := FlowNodeIO.make_context(null)
	node.preExecute(ctx)
	node.execute(ctx)
	assert_str(node.err).is_equal("Spawn Meshes " + OWNER_ERROR)
	assert_object(node.generated_bulks[0][0]).is_same(points)


func test_apply_on_actor_without_owner_reports_documented_error() -> void:
	var points := FlowData.Data.new()
	points.addCommonStreams(1)
	var node = ApplyOnActorNode.new()
	node.name = "apply"
	node.settings = ApplyOnActorNode.ApplyOnActorSettings.new()
	node.inputs = [points]
	var ctx := FlowNodeIO.make_context(null)
	node.preExecute(ctx)
	node.execute(ctx)
	assert_str(node.err).contains(OWNER_ERROR)
	assert_object(node.generated_bulks[0][0]).is_same(points)


func test_plain_node3d_can_host_an_evaluation() -> void:
	var plain := Node3D.new()
	add_child(plain)
	var ctx := FlowNodeIO.make_context(plain, 1)
	assert_object(ctx.owner).is_same(plain)
	assert_int(ctx.component_id).is_equal(plain.get_instance_id())
	assert_dict(ctx.overrides).is_empty()
	assert_int(ctx.seed).is_equal(1)
	# Spawners parent under it and tag it; graph inputs fall back to defaults.
	var outputs := FlowNodeIO.evaluate(_spawn_graph(), {}, 0, {}, plain)
	assert_int(_stream(outputs, "out_val", "position").size()).is_equal(4)
	var spawned := _generated_children(plain)
	assert_int(spawned.size()).is_equal(1)
	assert_dict(spawned[0].get_meta("flow_owner")).is_equal({ "component": plain.get_instance_id(), "node": "spawn" })
	var g := _graph(
		[ _node("in", "input", { "name": "value" }), _node("out", "output", { "name": "value_out" }) ],
		[ _link("in", "out") ], ["value"], ["value_out"])
	assert_float(_stream(FlowNodeIO.evaluate(g, {}, 0, {}, plain), "value_out", "value")[0]).is_equal(0.0)


func test_eval_id_is_inherited_verbatim_and_is_not_a_seed() -> void:
	var g := _random_graph()
	var ctx = FlowData.EvaluationContext.new()
	ctx.eval_id = 987
	ctx.runtime_params = {}
	var state : Dictionary = FlowNodeIO._build_evaluation_state(g, {}, ctx, {}, 0)
	assert_int(state["ctx"].eval_id).is_equal(987)
	FlowNodeIO._finalize_evaluation(state)
	# Legacy callers that stash a seed in eval_id get the same output as eval_id 0.
	var with_id = _stream(FlowNodeIO.evaluate_graph(g, {}, ctx, {}, 0), "out_val", "r")
	var plain_ctx = FlowData.EvaluationContext.new()
	var without_id = _stream(FlowNodeIO.evaluate_graph(g, {}, plain_ctx, {}, 0), "out_val", "r")
	assert_array(with_id).is_equal(without_id)
	assert_int(FlowNodeIO.make_context(null, 5).eval_id).is_equal(0)


# --- §5 generated-content ownership --------------------------------------------

func test_spawned_content_is_tagged_with_component() -> void:
	var c := _component(_spawn_graph())
	c.generate()
	var spawned := _generated_children(c)
	assert_int(spawned.size()).is_equal(1)
	assert_dict(spawned[0].get_meta("flow_owner")).is_equal({ "component": c.get_instance_id(), "node": "spawn" })


func test_cleanup_removes_only_this_components_nodes() -> void:
	var root := Node3D.new()
	add_child(root)
	var shared := Node3D.new()
	shared.name = "Shared"
	root.add_child(shared)
	var g := _spawn_graph("../Shared")
	var a := _component(g, root)
	var b := _component(g, root)
	a.generate()
	b.generate()
	assert_int(_generated_children(shared).size()).is_equal(2)

	# Regenerating A through its spawner's clear_previous_instances must not
	# delete B's output (both spawners are named "spawn" and share a parent).
	a.generate()
	assert_int(_generated_children(shared).size()).is_equal(2)

	# Content saved by an older version (legacy String meta) under A.
	var legacy := Node3D.new()
	legacy.set_meta("flow_owner", "spawn")
	a.add_child(legacy)
	var b_legacy := Node3D.new()
	b_legacy.set_meta("flow_owner", "spawn")
	b.add_child(b_legacy)

	var cleaned := [false]
	a.cleaned_up.connect(func(): cleaned[0] = true)
	a.cleanup()
	assert_bool(cleaned[0]).is_true()
	var remaining := _generated_children(shared)
	assert_int(remaining.size()).is_equal(1)
	assert_int(int(remaining[0].get_meta("flow_owner").component)).is_equal(b.get_instance_id())
	assert_int(_generated_children(a).size()).is_equal(0)
	assert_int(_generated_children(b).size()).is_equal(1)


func test_cleanup_is_safe_without_generation() -> void:
	var c := _component(_random_graph())
	var cleaned := [0]
	c.cleaned_up.connect(func(): cleaned[0] += 1)
	c.cleanup()
	c.cleanup()
	assert_int(cleaned[0]).is_equal(2)


func test_regenerate_replaces_output() -> void:
	var c := _component(_spawn_graph())
	c.generate()
	var outputs := c.regenerate()
	assert_bool(outputs.has("out_val")).is_true()
	assert_int(_generated_children(c).size()).is_equal(1)


func test_spawner_clears_legacy_string_meta_content() -> void:
	var c := _component(_spawn_graph())
	var legacy := MultiMeshInstance3D.new()
	legacy.set_meta("flow_owner", "spawn")
	c.add_child(legacy)
	c.generate()
	var spawned := _generated_children(c)
	assert_int(spawned.size()).is_equal(1)
	assert_bool(spawned[0].get_meta("flow_owner") is Dictionary).is_true()


func test_transient_output_leaves_spawned_nodes_unowned() -> void:
	var scene_root := Node3D.new()
	add_child(scene_root)
	var c := _component(_spawn_graph(), scene_root)
	c.owner = scene_root
	c.transient_output = true
	c.generate()
	var spawned := _generated_children(c)
	assert_int(spawned.size()).is_equal(1)
	assert_object(spawned[0].owner).is_null()


func test_assign_spawn_owner_honours_transient_output() -> void:
	var scene_root := Node3D.new()
	add_child(scene_root)
	var c := _component(_random_graph(), scene_root)
	var ctx := FlowNodeIO.make_context(c)
	var kept := Node3D.new()
	c.add_child(kept)
	FlowNodeBase.assignSpawnOwner(kept, scene_root, ctx)
	assert_object(kept.owner).is_same(scene_root)
	c.transient_output = true
	var transient := Node3D.new()
	c.add_child(transient)
	FlowNodeBase.assignSpawnOwner(transient, scene_root, ctx)
	assert_object(transient.owner).is_null()


# --- §6 boundary data ----------------------------------------------------------

func test_output_node_preserves_tags_data_attrs_and_kind() -> void:
	var in_data := FlowData.Data.new()
	in_data.registerStream("v", PackedFloat32Array([1.0, 2.0]), FlowData.DataType.Float)
	in_data.tags = PackedStringArray(["room", "north"])
	in_data.set_data_attr("room_id", 12)
	in_data.kind = FlowData.Kind.Spline
	var node = OutputNode.new()
	node.name = "out"
	node.settings = OutputNodeSettings.new()
	node.settings.name = "result"
	node.inputs = [in_data]
	var ctx := FlowNodeIO.make_context(null)
	node.preExecute(ctx)
	node.execute(ctx)
	var out : FlowData.Data = node.generated_bulks[0][0]
	assert_array(out.tags).is_equal(PackedStringArray(["room", "north"]))
	assert_int(out.get_data_attr("room_id")).is_equal(12)
	assert_int(out.kind).is_equal(FlowData.Kind.Spline)


func test_data_crosses_graph_boundaries_whole() -> void:
	var inner := _graph(
		[ _node("in", "input", { "name": "feed" }), _node("out", "output", { "name": "result" }) ],
		[ _link("in", "out") ], ["feed"], ["result"])
	var outer := _graph(
		[
			_node("in", "input", { "name": "feed" }),
			_node("sub", "subgraph", { "graph": inner }),
			_node("out", "output", { "name": "result" }),
		],
		[ _link("in", "sub"), _link("sub", "out") ], ["feed"], ["result"])
	var feed := FlowData.Data.new()
	feed.registerStream("v", PackedFloat32Array([3.0]), FlowData.DataType.Float)
	feed.tags = PackedStringArray(["t1"])
	feed.set_data_attr("direction", Vector3(1, 0, 0))
	feed.kind = FlowData.Kind.AttrSet
	for g in [inner, outer]:
		var result : FlowData.Data = FlowNodeIO.evaluate(g, { "feed": feed }).get("result")
		assert_object(result).is_not_null()
		assert_array(result.tags).is_equal(PackedStringArray(["t1"]))
		assert_that(result.first("@data.direction")).is_equal(Vector3(1, 0, 0))
		assert_that(result.first("direction")).is_equal(Vector3(1, 0, 0))
		assert_int(result.kind).is_equal(FlowData.Kind.AttrSet)
		assert_float(result.first("v")).is_equal(3.0)


# --- §6 Data helpers ----------------------------------------------------------

func test_data_scalar_infers_types() -> void:
	assert_int(FlowData.Data.scalar("f", 1.5).streams["f"].data_type).is_equal(FlowData.DataType.Float)
	assert_int(FlowData.Data.scalar("i", 3).streams["i"].data_type).is_equal(FlowData.DataType.Int)
	assert_int(FlowData.Data.scalar("b", true).streams["b"].data_type).is_equal(FlowData.DataType.Bool)
	assert_int(FlowData.Data.scalar("s", "x").streams["s"].data_type).is_equal(FlowData.DataType.String)
	assert_int(FlowData.Data.scalar("v", Vector3.ONE).streams["v"].data_type).is_equal(FlowData.DataType.Vector)
	assert_int(FlowData.Data.scalar("c", Color.RED).streams["c"].data_type).is_equal(FlowData.DataType.Color)
	var mesh := BoxMesh.new()
	var res := FlowData.Data.scalar("m", mesh)
	assert_int(res.streams["m"].data_type).is_equal(FlowData.DataType.Resource)
	assert_object(res.first("m")).is_same(mesh)
	var explicit := FlowData.Data.scalar("n", 2, FlowData.DataType.Float)
	assert_int(explicit.streams["n"].data_type).is_equal(FlowData.DataType.Float)
	assert_float(explicit.first("n")).is_equal(2.0)
	assert_int(FlowData.Data.scalar("x", 4).size()).is_equal(1)
	assert_bool(FlowData.Data.scalar("b", true).first("b")).is_true()


func test_data_first_and_container_accept_all_selectors() -> void:
	var d := FlowData.Data.new()
	d.addCommonStreams(2)
	var pos : PackedVector3Array = d.container("position")
	pos[0] = Vector3(4, 5, 6)
	d.registerStream("position", pos, FlowData.DataType.Vector)
	var rot : PackedVector3Array = d.container("rotation")
	rot[0] = Vector3(0, 90, 0)
	d.registerStream("rotation", rot, FlowData.DataType.Vector)
	d.registerStream("label", PackedStringArray(["a", "b"]), FlowData.DataType.String)
	d.set_data_attr("level", 3)

	assert_that(d.first("position")).is_equal(Vector3(4, 5, 6))
	assert_float(d.first("position.x")).is_equal(4.0)
	assert_float(d.first("Yaw")).is_equal(90.0)
	assert_str(d.first("@last")).is_equal("a")
	assert_int(d.first("@data.level")).is_equal(3)
	assert_int(d.first("level")).is_equal(3)
	assert_str(d.first("missing", "fallback")).is_equal("fallback")
	assert_object(d.first("missing.x")).is_null()
	assert_object(d.first("")).is_null()

	assert_bool(d.container("label") is PackedStringArray).is_true()
	assert_int(d.container("label").size()).is_equal(2)
	assert_float(d.container("position.y")[0]).is_equal(5.0)
	assert_int(d.container("@data.level")[0]).is_equal(3)
	assert_object(d.container("missing")).is_null()

	var empty := FlowData.Data.new()
	assert_object(empty.first("@last")).is_null()
	assert_int(empty.first("x", 7)).is_equal(7)


func test_data_attr_helpers() -> void:
	var d := FlowData.Data.new()
	d.set_data_attr("flag", true)
	d.set_data_attr("name", "hall")
	d.set_data_attr("count", 2.0, FlowData.DataType.Int)
	assert_bool(d.get_data_attr("flag")).is_true()
	assert_str(d.get_data_attr("name")).is_equal("hall")
	assert_int(d.data_attrs["count"].data_type).is_equal(FlowData.DataType.Int)
	assert_int(typeof(d.get_data_attr("count"))).is_equal(TYPE_INT)
	assert_int(d.get_data_attr("count")).is_equal(2)
	assert_str(d.get_data_attr("missing", "none")).is_equal("none")
	# Readable through the @data selector like any registered attribute.
	assert_str(d.findStream("@data.name").container[0]).is_equal("hall")
	# Attributes registered through the selector read back the same way.
	d.registerStream("@data.opened", PackedByteArray([1]), FlowData.DataType.Bool)
	assert_bool(d.get_data_attr("opened")).is_true()
	# A multi-element @data write keeps element 0 (and warns); unchanged semantics.
	d.registerStream("@data.first_of_many", PackedInt32Array([4, 5, 6]), FlowData.DataType.Int)
	assert_int(d.get_data_attr("first_of_many")).is_equal(4)
