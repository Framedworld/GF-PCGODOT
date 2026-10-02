# editor_widget_modes_test.gd
# WP7 requirement 4 (and 6): widgets rebuild their ports when a mode setting
# changes the element's ports (use_bounding_shape, projection_mode, ...),
# whatever path changed the setting; slot types follow; links into a port
# that disappears are dropped; parameter links move with their parameter;
# and saved links keep their indices. Extends the editor smoke harness: the
# same headless dock, every registered template, every bool / enum setting.
class_name EditorWidgetModesTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const EDITOR_SCENE := "res://addons/flow_nodes_editor/flow_editor.tscn"
const WidgetPortChecks = preload("res://tests/editor/support/widget_port_checks.gd")

## Nodes the WP2 and WP3 notes list, with the settings that select a mode.
## Every bool / enum setting of these nodes is switched; the ones named here
## must exist (a rename fails the test).
const LISTED_MODE_SETTINGS := {
	# WP2
	"surface_sampler": ["use_bounding_shape", "shape_sampling"],
	"projection": ["projection_mode"],
	"volume_sampler": ["apply_density_to_points"],
	"sample_spline": ["sampling_mode", "fill_curve", "fill_mode"],
	"difference": ["operation", "density_function"],
	"intersection": [],
	"union": [],
	"create_surface_from_spline": ["output_mode", "plane"],
	"create_surface_from_polygon": ["output_mode", "plane"],
	"make_bounds": ["output_mode"],
	"get_bounds": ["output_mode"],
	"get_spline_data": ["output_mode"],
	"get_surface_data": ["source", "output_mode"],
	"get_volume_data": ["output_mode", "mesh_volume"],
	"to_point": ["apply_density"],
	"filter_data_by_type": ["target_type"],
	# WP3
	"spawn_meshes": ["entry_selection", "reuse_instances"],
	"spawn_scenes": ["reuse_instances"],
	"spawn_nodes": ["reuse_instances"],
	"apply_on_actor": ["target_mode"],
	"spawn_spline_mesh": ["segmentation", "segment_selection", "forward_axis", "tangent_mode", "up_mode"],
	"create_target_node": ["owner_policy"],
}

## Flow inputs per mode, for the nodes whose ports depend on a setting.
## Everything else keeps its flow inputs whatever the mode.
const MODE_INPUTS := {
	"surface_sampler": { "use_bounding_shape": { false: ["In"], true: ["In", "Bounding Shape"] } },
	"projection": { "projection_mode": { 0: ["In"], 1: ["In", "Projection Target"] } },
}

var _editor : Control = null


# A fresh dock per test, freed in after_test(): GdUnit's orphan monitor walks
# every node reachable from the suite after each test whenever an orphan from
# an EARLIER suite still exists, and it cannot walk the dock (untyped members
# holding ints/arrays make its `as Node` cast fail with "Invalid cast"). With
# the dock gone before that walk, suite order no longer matters.
func before_test() -> void:
	_editor = load(EDITOR_SCENE).instantiate()
	add_child(_editor)
	_editor.set_process(false)
	await get_tree().process_frame


func after() -> void:
	if is_instance_valid(_editor):
		_editor.clear_graph()
		remove_child(_editor)
		_editor.free()
	_editor = null
	await get_tree().process_frame


func after_test() -> void:
	if is_instance_valid(_editor):
		_editor.clear_graph()
		remove_child(_editor)
		_editor.free()
	_editor = null
	await get_tree().process_frame


func _open_empty_graph() -> FlowGraphResource:
	var graph := FlowGraphResource.new()
	_editor.clear_graph()
	_editor.current_resource = graph
	_editor.resource_owner = null
	_editor.scanAvailableNodesIfNeeded()
	return graph


func _clear_gdunit_script_errors() -> void:
	var tctx = GdUnitThreadManager.get_current_context()
	if tctx == null:
		return
	var exec_ctx = tctx.get_execution_context()
	if exec_ctx != null and exec_ctx.error_monitor != null:
		exec_ctx.error_monitor.clear_logs()


## Every bool / enum property a node's own settings declare (not the common
## NodeSettings ones), as [name, values].
static func mode_properties(settings: NodeSettings) -> Array:
	var common := {}
	for p in NodeSettings.new().get_property_list():
		common[p.name] = true
	var out := []
	for p in settings.get_property_list():
		if common.has(p.name):
			continue
		if not (p.usage & PROPERTY_USAGE_EDITOR) or not (p.usage & PROPERTY_USAGE_STORAGE):
			continue
		if p.type == TYPE_BOOL:
			out.append([p.name, [false, true]])
		elif p.type == TYPE_INT and p.hint == PROPERTY_HINT_ENUM:
			# FlowData.DataType's Invalid (999) is not a value to pick: nodes
			# index DataType.keys() with their data_type (a pre-existing limit).
			out.append([p.name, enum_values(p.hint_string).filter(func(v): return v != FlowData.DataType.Invalid)])
	return out


## Values of an enum hint string ("A,B:5,C" -> [0, 5, 6]).
static func enum_values(hint_string: String) -> Array:
	var out := []
	var next := 0
	for item in hint_string.split(","):
		var parts := item.split(":")
		if parts.size() > 1 and parts[1].strip_edges().is_valid_int():
			next = parts[1].strip_edges().to_int()
		out.append(next)
		next += 1
	return out


static func _input_labels(widget: FlowNodeWidget) -> Array:
	var out := []
	for in_data in widget.getMeta().get("ins", []):
		out.append(str(in_data.get("label", "")))
	return out


# --- Every template, every mode setting ---------------------------------------------------

## Builds a widget for every registered template and switches every bool / enum
## setting through all its values with a plain settings edit (settings.changed,
## no onPropChanged): the ports always match the element's metadata afterwards.
func test_every_template_rebuilds_ports_for_every_mode_setting(timeout := 600000) -> void:
	_open_empty_graph()
	var templates : Array = _editor.node_types.keys()
	templates.sort()
	assert_int(templates.size()).is_greater(100)
	var failures := []
	var changed_ports := {}
	var switched := 0
	var index := 0
	for template in templates:
		index += 1
		var widget = _editor.addNodeFromTemplate(template, "m_%d" % index)
		if not (widget is FlowNodeWidget):
			failures.append("%s: no widget" % template)
			continue
		widget.show_disconnected_inputs = true
		widget.initFromScript()
		for problem in WidgetPortChecks.port_mismatches(widget):
			failures.append("%s (default): %s" % [template, problem])
		var initial_signature = widget.port_signature()
		for prop in mode_properties(widget.settings):
			var prop_name : String = prop[0]
			var original = widget.settings.get(prop_name)
			for value in prop[1]:
				widget.settings.set(prop_name, value)
				widget.settings.emit_changed()
				switched += 1
				for problem in WidgetPortChecks.port_mismatches(widget):
					failures.append("%s.%s = %s: %s" % [template, prop_name, value, problem])
				if widget.port_signature() != initial_signature:
					changed_ports[template] = true
			widget.settings.set(prop_name, original)
			widget.settings.emit_changed()
			if widget.port_signature() != initial_signature:
				failures.append("%s.%s: restoring %s did not restore the ports" % [template, prop_name, original])
	assert_int(switched).is_greater(300)
	# The nodes whose ports depend on a setting were all seen changing.
	for template in ["surface_sampler", "projection", "add_attribute", "sample_points"]:
		if not changed_ports.has(template):
			failures.append("%s: no setting changed its ports" % template)
	assert_array(failures).override_failure_message("\n".join(failures.slice(0, 40))).is_empty()


## The WP2 and WP3 nodes: their mode settings exist, switching them keeps the
## flow inputs (or sets them, for the two mode-dependent nodes) and the
## outputs, and the ports stay consistent.
func test_wp2_wp3_nodes_mode_settings() -> void:
	_open_empty_graph()
	var failures := []
	var index := 0
	for template in LISTED_MODE_SETTINGS:
		index += 1
		var widget = _editor.addNodeFromTemplate(template, "w_%d" % index)
		if not (widget is FlowNodeWidget):
			failures.append("%s: not registered" % template)
			continue
		for prop_name in LISTED_MODE_SETTINGS[template]:
			if not (prop_name in widget.settings):
				failures.append("%s has no setting %s" % [template, prop_name])
		var default_ins := _input_labels(widget)
		var default_outs : int = widget.getMeta().get("outs", []).size()
		for prop in mode_properties(widget.settings):
			var prop_name : String = prop[0]
			var original = widget.settings.get(prop_name)
			for value in prop[1]:
				widget.settings.set(prop_name, value)
				widget.settings.emit_changed()
				var expected : Array = default_ins
				var per_mode : Dictionary = MODE_INPUTS.get(template, {}).get(prop_name, {})
				if per_mode.has(value):
					expected = per_mode[value]
				var labels := _input_labels(widget)
				if labels != expected:
					failures.append("%s.%s = %s: inputs %s, expected %s" % [template, prop_name, value, labels, expected])
				if widget.getMeta().get("outs", []).size() != default_outs:
					failures.append("%s.%s = %s: output count changed" % [template, prop_name, value])
				for problem in WidgetPortChecks.port_mismatches(widget):
					failures.append("%s.%s = %s: %s" % [template, prop_name, value, problem])
				# The rows really exist: one enabled left slot per flow input.
				for i in range(labels.size()):
					if not widget.is_slot_enabled_left(i):
						failures.append("%s.%s = %s: no slot for input %d" % [template, prop_name, value, i])
			widget.settings.set(prop_name, original)
			widget.settings.emit_changed()
	assert_array(failures).override_failure_message("\n".join(failures)).is_empty()


# --- Links across a mode change -------------------------------------------------------------

func _connections_into(node_name: StringName) -> Dictionary:
	# to_port -> [from_node, from_port]
	var out := {}
	for c in _editor.gedit.get_connection_list():
		if c.to_node == node_name:
			out[c.to_port] = [String(c.from_node), c.from_port]
	return out


func _toggle(widget: FlowNodeWidget, prop: String, value, through_inspector: bool) -> void:
	widget.settings.set(prop, value)
	if through_inspector:
		# What FlowEditor.onNodePropertyChanged does for the inspected node.
		widget.onPropChanged(prop)
		widget.refreshFromSettings()
	widget.settings.emit_changed()


func _check_link_behaviour(template: String, prop: String, off_value, on_value, through_inspector: bool) -> void:
	var graph := _open_empty_graph()
	var src_in = _editor.addNodeFromTemplate("grid", "src_in")
	var src_param = _editor.addNodeFromTemplate("grid", "src_param")
	var src_extra = _editor.addNodeFromTemplate("grid", "src_extra")
	var w : FlowNodeWidget = _editor.addNodeFromTemplate(template, "target")
	w.show_disconnected_inputs = true
	w.initFromScript()
	# The first parameter: in the default mode it sits right after the single
	# flow input, exactly where it was before the mode setting existed.
	var param_name : String = w.getExposedParams()[0].name
	assert_int(w.args_ports_by_name[param_name].port).is_equal(1)
	_editor.connect_nodes(&"src_in", 0, &"target", 0)
	_editor.connect_nodes(&"src_param", 0, &"target", 1)

	# Mode on: a second flow input appears; the parameter link moves with its
	# parameter, the flow link stays.
	_toggle(w, prop, on_value, through_inspector)
	assert_int(w.getMeta().ins.size()).is_equal(2)
	assert_int(w.args_ports_by_name[param_name].port).is_equal(2)
	var conns := _connections_into(&"target")
	assert_that(conns.get(0)).is_equal(["src_in", 0])
	assert_that(conns.get(2)).is_equal(["src_param", 0])
	assert_bool(conns.has(1)).is_false()
	assert_bool(w.is_slot_enabled_left(1)).is_true()

	# Wire the new input, save, reload: every link keeps its index.
	_editor.connect_nodes(&"src_extra", 0, &"target", 1)
	FlowNodeIO.saveToResource(_editor)
	var saved_links := {}
	for link in graph.data.links:
		if link.to_node == &"target":
			saved_links[link.to_port] = String(link.from_node)
	assert_that(saved_links).is_equal({ 0: "src_in", 1: "src_extra", 2: "src_param" })
	_editor.clear_graph()
	_editor.current_resource = graph
	FlowNodeIO.loadFromResource(_editor)
	w = _editor.gedit_nodes_by_name[&"target"]
	assert_int(w.getMeta().ins.size()).is_equal(2)
	conns = _connections_into(&"target")
	assert_that(conns.get(0)).is_equal(["src_in", 0])
	assert_that(conns.get(1)).is_equal(["src_extra", 0])
	assert_that(conns.get(2)).is_equal(["src_param", 0])

	# Mode off: the link into the removed input is dropped (it must not land
	# on the parameter that takes port 1), the parameter link moves back.
	_toggle(w, prop, off_value, through_inspector)
	assert_int(w.getMeta().ins.size()).is_equal(1)
	assert_int(w.args_ports_by_name[param_name].port).is_equal(1)
	conns = _connections_into(&"target")
	assert_that(conns.get(0)).is_equal(["src_in", 0])
	assert_that(conns.get(1)).is_equal(["src_param", 0])
	assert_int(conns.size()).is_equal(2)
	assert_array(_editor.get_connected_sources(&"target", 1)).is_equal([[&"src_param", 0]])


func test_surface_sampler_links_follow_use_bounding_shape() -> void:
	_check_link_behaviour("surface_sampler", "use_bounding_shape", false, true, false)


func test_surface_sampler_links_follow_use_bounding_shape_from_the_inspector() -> void:
	_check_link_behaviour("surface_sampler", "use_bounding_shape", false, true, true)


func test_projection_links_follow_projection_mode() -> void:
	_check_link_behaviour("projection", "projection_mode", ProjectionNodeSettings.eProjectionMode.Physics, ProjectionNodeSettings.eProjectionMode.Surface, false)


func test_projection_links_follow_projection_mode_from_the_inspector() -> void:
	_check_link_behaviour("projection", "projection_mode", ProjectionNodeSettings.eProjectionMode.Physics, ProjectionNodeSettings.eProjectionMode.Surface, true)


## Exposed parameters that depend on a setting (add_attribute's cte_<type>,
## sample_points' distribution parameters) are rebuilt with their slot types.
func test_exposed_parameters_follow_their_mode_setting() -> void:
	_open_empty_graph()
	var w : FlowNodeWidget = _editor.addNodeFromTemplate("add_attribute", "attr")
	w.show_disconnected_inputs = true
	w.initFromScript()
	for t in [FlowData.DataType.Vector2, FlowData.DataType.Transform, FlowData.DataType.Vector4, FlowData.DataType.Quaternion, FlowData.DataType.Float]:
		w.settings.data_type = t
		w.settings.emit_changed()
		assert_array(WidgetPortChecks.port_mismatches(w)).is_empty()
		var expected_param : String = "cte_" + FlowData.DataType.keys()[t].to_lower()
		assert_bool(w.args_ports_by_name.has(expected_param)).override_failure_message("no %s port" % expected_param).is_true()
		assert_int(w.get_slot_type_left(w.args_ports_by_name[expected_param].port)).is_equal(t)
	var sp : FlowNodeWidget = _editor.addNodeFromTemplate("sample_points", "sp")
	sp.show_disconnected_inputs = true
	sp.initFromScript()
	# Default QuasiRandom2D exposes "phase"; UniformGrid exposes the grid
	# parameters instead.
	var quasi_random : Array = sp.args_ports_by_name.keys()
	sp.settings.distribution = SamplePointsNodeSettings.eDistribution.UniformGrid
	sp.settings.emit_changed()
	assert_bool(sp.args_ports_by_name.keys() != quasi_random).is_true()
	assert_bool(sp.args_ports_by_name.has("max_x")).is_true()
	assert_array(WidgetPortChecks.port_mismatches(sp)).is_empty()
