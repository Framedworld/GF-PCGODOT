# flow_node_widget_test.gd
# FlowNodeWidget: delegation to its element, element signals, settings
# watching and the optional widget_* hooks.
class_name FlowNodeWidgetTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")


func _element(template: String) -> FlowNodeBase:
	var element : FlowNodeBase = load(FlowNodeRegistry.get_node_script_path(template)).new()
	element.node_template = template
	element.name = "n_" + template
	var meta := element.getMeta()
	element.settings = meta.settings.new() if meta.has("settings") and meta.settings else NodeSettings.new()
	return element


func test_widget_delegates_element_state() -> void:
	var element := _element("grid")
	var widget := FlowNodeWidget.new()
	widget.name = "grid_node"
	widget.element = element
	assert_object(element.get_widget()).is_same(widget)
	assert_str(String(element.name)).is_equal("grid_node")
	assert_object(widget.settings).is_same(element.settings)
	assert_str(widget.node_template).is_equal("grid")
	widget.dirty = true
	assert_bool(element.dirty).is_true()
	widget.deps.append({ "from_node": &"a", "from_port": 0, "to_node": &"grid_node", "to_port": 0 })
	assert_int(element.deps.size()).is_equal(1)
	element.set_output(0, FlowData.Data.new())
	assert_int(widget.generated_bulks.size()).is_equal(1)
	assert_int(widget.num_generated_bulks).is_equal(1)
	widget.show_disconnected_inputs = true
	assert_bool(element.show_disconnected_inputs).is_true()
	# Node-specific members read through _get.
	assert_str(widget.getTitle()).is_equal(element.getTitle())
	widget.free()


func test_renaming_the_widget_renames_the_element() -> void:
	var element := _element("grid")
	var widget := FlowNodeWidget.new()
	widget.element = element
	add_child(widget)
	widget.name = "renamed"
	assert_str(String(element.name)).is_equal("renamed")
	remove_child(widget)
	widget.free()


func test_settings_changes_mark_the_element_dirty() -> void:
	var element := _element("grid")
	var widget := FlowNodeWidget.new()
	widget.element = element
	element.dirty = false
	element.settings.emit_changed()
	assert_bool(element.dirty).is_true()
	# A replaced settings resource is watched instead of the old one.
	var old_settings : NodeSettings = element.settings
	var new_settings : NodeSettings = old_settings.duplicate()
	element.settings = new_settings
	element.dirty = false
	old_settings.emit_changed()
	assert_bool(element.dirty).is_false()
	new_settings.emit_changed()
	assert_bool(element.dirty).is_true()
	widget.free()


func test_element_errors_reach_the_widget() -> void:
	var element := _element("grid")
	var widget := FlowNodeWidget.new()
	widget.element = element
	var notified := [0]
	widget.editor_state_changed.connect(func(): notified[0] += 1)
	element.setError("broken")
	assert_str(widget.err).is_equal("broken")
	assert_int(notified[0]).is_equal(1)
	widget.free()


func test_unbinding_disconnects_the_old_element() -> void:
	var first := _element("grid")
	var second := _element("grid")
	var widget := FlowNodeWidget.new()
	widget.element = first
	widget.element = second
	assert_object(first.get_widget()).is_null()
	assert_bool(first.error_changed.is_connected(widget._on_element_error_changed)).is_false()
	assert_object(second.get_widget()).is_same(widget)
	widget.free()
	# Once the widget is gone the element is a plain runtime element again.
	assert_object(second.get_widget()).is_null()


func test_widget_refresh_hook_sets_the_variable_title() -> void:
	var element := _element("set_variable")
	element.settings.variable_name = "loot"
	var widget := FlowNodeWidget.new()
	widget.element = element
	widget.initFromScript()
	widget.refreshFromSettings()
	assert_str(widget.title).is_equal("Set: loot")
	widget.free()


func test_reroute_uses_its_widget_subclass_and_draw_hook() -> void:
	var element := _element("reroute")
	assert_bool(element.has_method("widget_script")).is_true()
	var widget = element.widget_script().new()
	assert_bool(widget is FlowRerouteWidget).is_true()
	widget.element = element
	widget.initFromScript()
	widget.refreshFromSettings()
	assert_str(widget.title).is_equal("")
	assert_bool(element.has_method("widget_draw")).is_true()
	widget.free()


func test_hot_reload_rebinds_a_fresh_element() -> void:
	var element := _element("grid")
	element.settings.x = 7
	var widget := FlowNodeWidget.new()
	widget.name = "g"
	widget.element = element
	widget.rebind_script(element.get_script())
	assert_object(widget.element).is_not_same(element)
	assert_object(widget.element.settings).is_same(element.settings)
	assert_str(String(widget.element.name)).is_equal("g")
	assert_object(element.get_widget()).is_null()
	widget.free()
