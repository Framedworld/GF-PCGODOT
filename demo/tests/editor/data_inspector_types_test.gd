# data_inspector_types_test.gd
# WP7 requirement 2: the data inspector shows every DataType. The table model
# (FlowDataTableModel) is checked value by value; the real inspector scene is
# then driven through the same code paths the editor uses (setNode, refresh,
# the TableView column and cell callbacks, the text filter and column sorting)
# on a Data with one stream of every type and on shape-only Data. GdUnit fails
# a test on any script error, so "no script errors" is asserted by running them.
class_name DataInspectorTypesTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const INSPECTOR_SCENE := "res://addons/flow_nodes_editor/data_inspector.tscn"
const CellContents = preload("res://addons/flow_nodes_editor/visualization/scroll_container.gd").CellContents

var _nodes : Array = []

func after_test() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_nodes.clear()
	await get_tree().process_frame

## A Data with 4 rows and one stream of every DataType (plus a broadcast one).
func _all_types_data() -> FlowData.Data:
	var d := FlowData.Data.new()
	var n := 4
	var curve := Curve.new()
	curve.resource_path = ""
	var node3d : Node3D = auto_free(Node3D.new())
	node3d.name = "Lamp"
	for key in FlowData.DataType.keys():
		var t : int = FlowData.DataType[key]
		if t == FlowData.DataType.Invalid:
			continue
		var c = FlowData.Data.newContainerOfType(t)
		c.resize(n)
		for i in range(n):
			var v
			match t:
				FlowData.DataType.Bool: v = i % 2 == 0
				FlowData.DataType.Int: v = 10 - i
				FlowData.DataType.Float: v = 0.25 * i
				FlowData.DataType.Vector: v = Vector3(i, -i, 2 * i)
				FlowData.DataType.String: v = ["delta", "alpha", "charlie", "bravo"][i]
				FlowData.DataType.Resource: v = curve if i == 0 else null
				FlowData.DataType.NodeMesh, FlowData.DataType.NodePath: v = node3d if i == 1 else null
				FlowData.DataType.Color: v = Color(0.1 * i, 0.5, 1.0, 1.0)
				FlowData.DataType.Quaternion: v = Quaternion(Vector3.UP, 0.1 * i)
				FlowData.DataType.Vector2: v = Vector2(i, 3 - i)
				FlowData.DataType.Vector4: v = Vector4(i, 1, 2, 3)
				FlowData.DataType.Transform: v = Transform3D(Basis(Vector3.UP, deg_to_rad(30.0 * i)) * Basis.from_scale(Vector3(1, 2, 3)), Vector3(i, 5, -i))
				FlowData.DataType.Int64: v = (1 << 40) + i
				FlowData.DataType.Double: v = 0.1 + 1e-9 * i
			if v != null:
				FlowData.Data.writeValue(c, i, v, t)
		var err = d.registerStream("s_" + key.to_lower(), c, t)
		assert_bool(err == null or err == "" or err == OK).override_failure_message("register %s: %s" % [key, err]).is_true()
	# A broadcast stream (one value for every row).
	d.registerStream("bcast", PackedFloat32Array([0.5]), FlowData.DataType.Float)
	return d

func _expected_column_count() -> int:
	var n := 0
	for key in FlowData.DataType.keys():
		var t : int = FlowData.DataType[key]
		if t == FlowData.DataType.Invalid:
			continue
		n += FlowDataTableModel.COMPONENTS.get(t, [0]).size()
	return n + 1  # + bcast


# --- Model ----------------------------------------------------------------------------

func test_model_has_component_columns_for_every_type() -> void:
	var d := _all_types_data()
	var m := FlowDataTableModel.new(d)
	assert_int(m.row_count).is_equal(4)
	assert_int(m.column_count()).is_equal(_expected_column_count())
	var titles := m.titles()
	for t in ["s_vector.X", "s_vector.Z", "s_vector2.X", "s_vector2.Y", "s_vector4.W", "s_quaternion.W", "s_color.R", "s_color.A", "s_transform.Pos.X", "s_transform.Rot.Y", "s_transform.Scale.Z", "s_int64", "s_double", "s_bool", "bcast"]:
		assert_bool(titles.has(t)).override_failure_message("no column %s in %s" % [t, titles]).is_true()
	assert_bool(titles.has("s_vector2.Z")).is_false()


func _col(m: FlowDataTableModel, title: String) -> int:
	return m.titles().find(title)

func test_model_cell_text_per_type() -> void:
	var m := FlowDataTableModel.new(_all_types_data())
	var expect := {
		"s_bool": ["True", "False"],
		"s_int": ["10", "9"],
		"s_float": ["0.000", "0.250"],
		"s_int64": [str((1 << 40)), str((1 << 40) + 1)],
		"s_double": ["0.100000", "0.100000"],
		"s_vector.Y": ["0.000", "-1.000"],
		"s_vector2.Y": ["3.000", "2.000"],
		"s_vector4.X": ["0.000", "1.000"],
		"s_color.G": ["0.500", "0.500"],
		"s_quaternion.W": ["1.000", "%1.3f" % cos(0.05)],
		"s_transform.Pos.Z": ["0.000", "-1.000"],
		"s_transform.Rot.Y": ["0.000", "30.000"],
		"s_transform.Scale.Y": ["2.000", "2.000"],
		"s_string": ["delta", "alpha"],
		"s_nodepath": ["", "$Lamp"],
		"s_nodemesh": ["", "$Lamp"],
		"bcast": ["0.500", "0.500"],
	}
	for title in expect:
		var col := _col(m, title)
		assert_int(col).override_failure_message("no column " + title).is_greater_equal(0)
		for row in range(2):
			assert_str(m.cell_text(col, row)).override_failure_message("%s row %d" % [title, row]).is_equal(expect[title][row])
	# A Resource without a path shows its class; a missing one is blank.
	var res_col := _col(m, "s_resource")
	assert_str(m.cell_text(res_col, 0)).is_equal("[Curve]")
	assert_str(m.cell_text(res_col, 1)).is_equal("")
	# Out of range rows and columns are blank.
	assert_str(m.cell_text(0, 99)).is_equal("")
	assert_str(m.cell_text(999, 0)).is_equal("")


func test_model_sorts_every_column_both_ways() -> void:
	var m := FlowDataTableModel.new(_all_types_data())
	var rows : Array[int] = [0, 1, 2, 3]
	for col in range(m.column_count()):
		for asc in [true, false]:
			var sorted := m.sorted_rows(rows, col, asc)
			var copy := sorted.duplicate()
			copy.sort()
			assert_array(copy).override_failure_message("column %s" % m.columns[col].title).is_equal([0, 1, 2, 3])
	# Numeric columns sort numerically, string columns as text.
	assert_array(m.sorted_rows(rows, _col(m, "s_int"), true)).is_equal([3, 2, 1, 0])
	assert_array(m.sorted_rows(rows, _col(m, "s_int64"), false)).is_equal([3, 2, 1, 0])
	assert_array(m.sorted_rows(rows, _col(m, "s_vector2.Y"), true)).is_equal([3, 2, 1, 0])
	assert_array(m.sorted_rows(rows, _col(m, "s_transform.Rot.Y"), false)).is_equal([3, 2, 1, 0])
	assert_array(m.sorted_rows(rows, _col(m, "s_string"), true)).is_equal([1, 3, 2, 0])
	# Empty cells sort last in both directions.
	assert_int(m.sorted_rows(rows, _col(m, "s_nodepath"), true)[0]).is_equal(1)
	assert_int(m.sorted_rows(rows, _col(m, "s_nodepath"), false)[0]).is_equal(1)


func test_model_filter_matches_displayed_text_of_every_type() -> void:
	var m := FlowDataTableModel.new(_all_types_data())
	assert_array(m.filtered_rows("")).is_equal([0, 1, 2, 3])
	assert_array(m.filtered_rows("ALPHA")).is_equal([1])
	assert_array(m.filtered_rows("$lamp")).is_equal([1])
	assert_array(m.filtered_rows("[curve]")).is_equal([0])
	assert_array(m.filtered_rows(str((1 << 40) + 3))).is_equal([3])
	assert_array(m.filtered_rows("60.000")).is_equal([2])  # Transform rotation Y of row 2
	assert_array(m.filtered_rows("zzz-no-match")).is_equal([])
	for text in ["0", "1.000", "true", "false", "-", ".", "w", "$"]:
		m.filtered_rows(text)


func test_shape_only_data_has_a_summary_row() -> void:
	var curve := Curve3D.new()
	curve.add_point(Vector3.ZERO)
	curve.add_point(Vector3(10, 0, 0))
	var d := FlowData.Data.from_shape(FlowSplineShape.new(curve))
	var m := FlowDataTableModel.new(d)
	assert_bool(m.is_shape_summary).is_true()
	assert_int(m.row_count).is_equal(1)
	assert_array(m.titles()).is_equal(FlowDataTableModel.SHAPE_COLUMNS)
	assert_str(m.cell_text(0, 0)).is_equal("FlowSplineShape")
	assert_str(m.cell_text(1, 0)).is_equal("Spline")
	assert_str(m.cell_text(2, 0)).is_equal("0")
	assert_str(m.cell_text(6, 0)).contains("length 10.000")
	assert_str(m.summary_text()).contains("FlowSplineShape")
	var bounds := d.shape.get_bounds()
	assert_str(m.cell_text(3, 0)).is_equal("(%1.3f, %1.3f, %1.3f)" % [bounds.position.x, bounds.position.y, bounds.position.z])
	assert_that(m.row_world_position(0)).is_equal(bounds.get_center())


func test_composite_summary_lists_its_operands() -> void:
	var a := FlowBoxVolume.from_aabb(AABB(Vector3.ZERO, Vector3.ONE * 4))
	var b := FlowSphereVolume.at(Vector3(4, 0, 0), 1.0)
	var d := FlowData.Data.from_shape(FlowCompositeShape.new(FlowSpatial.Op.Difference, a, b, FlowSpatial.DENSITY_MULTIPLY))
	var m := FlowDataTableModel.new(d)
	assert_int(m.row_count).is_equal(3)
	assert_str(m.cell_text(0, 0)).is_equal("FlowCompositeShape")
	assert_str(m.cell_text(6, 0)).is_equal("Difference, density Multiply")
	assert_str(m.cell_text(0, 1)).is_equal("  A: FlowBoxVolume")
	assert_str(m.cell_text(0, 2)).is_equal("  B: FlowSphereVolume")
	assert_str(m.cell_text(1, 0)).is_equal("Volume")
	assert_str(m.cell_text(6, 2)).contains("radius 1.000")
	for col in range(m.column_count()):
		m.sorted_rows([0, 1, 2] as Array[int], col, true)
	assert_array(m.filtered_rows("sphere")).is_equal([2])


func test_every_shape_class_has_a_summary() -> void:
	var shapes := [
		FlowSplineShape.new(Curve3D.new()),
		FlowPolygonSurface.new(PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2(0, 1)])),
		FlowHeightfieldSurface.new(PackedFloat32Array([0, 0, 0, 0]), 2, 2),
		FlowMeshSurface.from_meshes([PlaneMesh.new()], [Transform3D.IDENTITY]),
		FlowMeshVolume.from_meshes([BoxMesh.new()], [Transform3D.IDENTITY]),
		FlowBoxVolume.new(),
		FlowSphereVolume.new(),
		FlowPointsVolume.new(PackedVector3Array([Vector3.ZERO]), PackedVector3Array([Vector3.ONE])),
		FlowSpatial.new(),
	]
	for shape in shapes:
		var m := FlowDataTableModel.new(FlowData.Data.from_shape(shape))
		assert_int(m.row_count).is_equal(1)
		assert_str(m.cell_text(0, 0)).is_not_empty()
		if not (shape.get_script() == FlowSpatial):
			assert_str(m.cell_text(6, 0)).override_failure_message("no detail for %s" % m.cell_text(0, 0)).is_not_empty()


# --- The inspector scene ---------------------------------------------------------------

func _inspector() -> Control:
	var inspector : Control = auto_free(load(INSPECTOR_SCENE).instantiate())
	add_child(inspector)
	return inspector

func _widget_with(data: FlowData.Data) -> FlowNodeWidget:
	var element : FlowNodeBase = load(FlowNodeRegistry.get_node_script_path("copy")).new()
	element.node_template = "copy"
	element.settings = element.getMeta().settings.new()
	var widget : FlowNodeWidget = auto_free(FlowNodeWidget.new())
	widget.name = "inspected"
	widget.element = element
	element.generated_bulks = [[data]]
	add_child(widget)
	return widget

## Draws every column the way DataTableContainer.drawCol does: the column
## callback, then the cell callback for each visible row. Returns the texts.
func _draw_all_cells(inspector) -> Array:
	var tv = inspector.tv
	var scroll = tv.get_node("ScrollContainer")
	var texts := []
	for col in range(inspector.col_titles.size() + 2):
		var cell = CellContents.new()
		cell.col = col
		cell.row = 0
		scroll.column_callback.call(cell)
		var callback : Callable = scroll.cell_contents
		var column_texts := []
		if callback.is_valid():
			for row in range(inspector.visible_rows.size()):
				cell.row = row
				callback.call(cell)
				column_texts.append(cell.text)
		texts.append(column_texts)
	return texts

func test_inspector_shows_every_type_without_script_errors() -> void:
	var d := _all_types_data()
	var inspector = _inspector()
	inspector.setNode(_widget_with(d))
	inspector.refresh()  # what FlowEditor does after setNode
	assert_object(inspector.data).is_same(d)
	assert_int(inspector.col_titles.size()).is_equal(_expected_column_count())
	assert_int(inspector.visible_rows.size()).is_equal(4)
	assert_str(inspector.get_node("%LabelStats").text).contains("4 rows")
	var texts : Array = _draw_all_cells(inspector)
	# Column 0 is the index; data columns follow in model order.
	assert_array(texts[0]).is_equal(["0", "1", "2", "3"])
	var col : int = inspector.col_titles.find("s_int64") + 1
	assert_str(texts[col][3]).is_equal(str((1 << 40) + 3))
	col = inspector.col_titles.find("s_transform.Rot.Y") + 1
	assert_str(texts[col][2]).is_equal("60.000")
	# The trailing filler column has no formatter (the old code assigned a
	# property TableView does not have here).
	assert_array(texts[texts.size() - 1]).is_empty()
	assert_bool(inspector.tv.get_node("ScrollContainer").cell_contents.is_valid()).is_false()


func test_inspector_filter_and_sort_on_every_column() -> void:
	var d := _all_types_data()
	var inspector = _inspector()
	inspector.setNode(_widget_with(d))
	inspector.refresh()  # what FlowEditor does after setNode
	for text in ["alpha", "$lamp", "true", "0.250", "1099511627779", "[curve]", "60.000", "nothing-matches", ""]:
		inspector._on_filter_edit_text_changed(text)
		_draw_all_cells(inspector)
	inspector._on_filter_edit_text_changed("alpha")
	assert_array(inspector.visible_rows).is_equal([1])
	inspector._on_filter_edit_text_changed("")
	for col in range(inspector.col_titles.size() + 1):
		inspector.onTitleClicked(col)
		_draw_all_cells(inspector)
		inspector.onTitleClicked(col)
		_draw_all_cells(inspector)
		assert_int(inspector.visible_rows.size()).is_equal(4)
	# Sorting by s_int ascending puts row 3 (value 7) first.
	inspector.sort_col = inspector.col_titles.find("s_int") + 1
	inspector.sort_ascending = true
	inspector.apply_sort()
	assert_array(inspector.visible_rows).is_equal([3, 2, 1, 0])
	# Clicking a row selects it for the debug draw.
	inspector.onCellClicked(0, 1)
	assert_int(inspector.node.debug_row).is_equal(3)


func test_inspector_shape_only_data_summary() -> void:
	var a := FlowBoxVolume.from_aabb(AABB(Vector3.ZERO, Vector3.ONE * 2))
	var b := FlowSphereVolume.at(Vector3(2, 0, 0), 1.0)
	var d := FlowData.Data.from_shape(FlowCompositeShape.new(FlowSpatial.Op.Union, a, b))
	var inspector = _inspector()
	inspector.setNode(_widget_with(d))
	inspector.refresh()  # what FlowEditor does after setNode
	assert_array(inspector.col_titles).is_equal(FlowDataTableModel.SHAPE_COLUMNS)
	assert_int(inspector.visible_rows.size()).is_equal(3)
	assert_str(inspector.get_node("%LabelStats").text).contains("FlowCompositeShape")
	var texts : Array = _draw_all_cells(inspector)
	assert_str(texts[1][0]).is_equal("FlowCompositeShape")
	assert_str(texts[2][0]).is_equal("Volume")
	assert_str(texts[3][0]).is_equal("0")
	inspector._on_filter_edit_text_changed("sphere")
	assert_array(inspector.visible_rows).is_equal([2])
	inspector._on_filter_edit_text_changed("")
	for col in range(inspector.col_titles.size() + 1):
		inspector.onTitleClicked(col)
		_draw_all_cells(inspector)
	# Double-click focus target of a summary row: its bounds centre.
	assert_that(inspector._get_row_world_position(1)).is_equal(a.get_bounds().get_center())


func test_inspector_handles_empty_and_null_data() -> void:
	var inspector = _inspector()
	inspector.setNode(_widget_with(FlowData.Data.new()))
	inspector.refresh()  # what FlowEditor does after setNode
	assert_int(inspector.visible_rows.size()).is_equal(0)
	_draw_all_cells(inspector)
	inspector._on_filter_edit_text_changed("x")
	inspector.setNode(null)
	assert_object(inspector.data).is_null()
	_draw_all_cells(inspector)
