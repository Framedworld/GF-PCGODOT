# table_view_generic_cells_test.gd
# TableView resets the cell formatter to a generic str() one before calling the
# owner's column callback, so a column whose type the owner does not format
# (Color, Quaternion, Vector2, Vector4, Transform, Int64, Double) shows its
# values instead of reusing the previous column's typed formatter.
class_name TableViewGenericCellsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TableViewScene = preload("res://addons/flow_nodes_editor/visualization/table_view.tscn")
const CellContents = preload("res://addons/flow_nodes_editor/visualization/scroll_container.gd").CellContents

# Minimal stand-in for the data inspector: formats Float columns itself and
# leaves every other type to the table's fallback.
class FakeOwner:
	var container
	var float_column := false
	var tv
	func on_column(cell) -> void:
		if float_column:
			tv.setCellCallback(float_cell)
	func float_cell(cell) -> void:
		cell.text = "%1.3f" % container[cell.row]
	func _container_index_for_cell(row: int) -> int:
		return row

func _cell_text(tv, owner: FakeOwner, row: int) -> String:
	var cell = CellContents.new()
	cell.row = row
	tv._on_column_begins(cell)
	tv.get_node("ScrollContainer").cell_contents.call(cell)
	return cell.text

func test_unhandled_types_use_the_generic_formatter_after_a_float_column() -> void:
	var tv = auto_free(TableViewScene.instantiate())
	add_child(tv)
	var owner := FakeOwner.new()
	owner.tv = tv
	tv.setColumnCallback(owner.on_column)

	# A Float column handled by the owner...
	owner.float_column = true
	owner.container = PackedFloat32Array([0.5])
	assert_str(_cell_text(tv, owner, 0)).is_equal("0.500")

	# ...then columns of types the owner does not handle.
	owner.float_column = false
	var cases := [
		[PackedVector2Array([Vector2(1, 2)]), str(Vector2(1, 2))],
		[PackedVector4Array([Vector4(1, 2, 3, 4)]), str(Vector4(1, 2, 3, 4))],
		[PackedInt64Array([1 << 40]), str(1 << 40)],
		[PackedFloat64Array([0.125]), str(0.125)],
		[PackedColorArray([Color.RED]), str(Color.RED)],
		[FlowDataScript.Data.newContainerOfType(FlowDataScript.DataType.Transform), ""],
	]
	cases[5][0].append(Transform3D.IDENTITY)
	cases[5][1] = str(Transform3D.IDENTITY)
	for c in cases:
		owner.container = c[0]
		assert_str(_cell_text(tv, owner, 0)).is_equal(c[1])
	# Out of range rows stay blank.
	assert_str(_cell_text(tv, owner, 5)).is_equal("")
