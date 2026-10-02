@tool
extends Control

# This controls the data_inspector panel to visualize the selected node inputs/outputs
# Allow to specify the bulk and port index to visualize the data
# The red yellow appearing over the node

@export var data_ex : int = 0:
	set(new_value):
		data_ex = new_value
		refresh()

@onready var tv : TableView = %TableView
@onready var slot_selector : OptionButton = %SlotSelector
@onready var bulk_selector : OptionButton = %BulkSelector

var node : FlowNodeWidget
var num_rows : int = 0
var num_cols : int = 0
var col_titles : Array[String]
var col_streams_names : Array[String]
var data : FlowData.Data
var visible_rows : Array[int] = []
## Table model of `data` (columns, cell text, sort keys, filter); see
## visualization/flow_data_table_model.gd.
var model : FlowDataTableModel

# View-only column sorting state (never mutates the underlying FlowData)
var sort_col : int = -1
var sort_ascending : bool = true

# The slot corresponds to InA, InB, or Out streams for example
# The setetings are not included
var current_bulk_index := 0
var current_port_index := 0
var is_output : bool = true

var container
var _flow_editor: FlowEditor

func setNode( new_node : FlowNodeWidget ):
	# If there was already one active... disabled it
	if node:
		%LabelTitle.text = "..."
		if node.settings:
			node.settings.inspect_enabled = false
			node.refreshFromSettings()

	if node != new_node and new_node:
		if new_node.has_method("getLocalizedTitle"):
			%LabelTitle.text = new_node.getLocalizedTitle()
		else:
			%LabelTitle.text = new_node.get_title()
		new_node.settings.inspect_enabled = true
		current_bulk_index = new_node.settings.debug_bulk
		node = new_node
		node.setupDrawDebug()
	else:
		node = null
		refresh()
	populateSlots()

func setLabelNumber( label : Label, value : float ):
	var new_text = fmt( value )
	if new_text != label.text:
		label.text = new_text

func updateNumRowsAndCols():
	model = FlowDataTableModel.new( data )
	num_rows = model.row_count
	col_titles = model.titles()
	col_streams_names = model.stream_names()
	num_cols = col_titles.size()

func fmt( v : float ) -> String:
	return FlowDataTableModel.fmt_real( v )

# When the draw of a column starts, we choose which fn will be used
# to display the data of that column. Every data column reads its text from
# the table model (FlowDataTableModel), which formats each DataType, vector
# components included.
func onColumnBegins( cell : DataTableContainer.CellContents ):
	cell.alignment = HORIZONTAL_ALIGNMENT_RIGHT

	if cell.col == 0:
		tv.setCellCallback( getCellContentsIndex )
		return

	# col = 0 is for the Index
	var data_col = cell.col - 1
	if model == null or data_col >= model.column_count():
		# Nothing to show (the trailing filler column): no formatter, so the
		# table skips the column.
		container = null
		tv.setCellCallback( Callable() )
		return

	var column : FlowDataTableModel.Column = model.columns[ data_col ]
	container = column.container
	cell.alignment = column.alignment
	tv.setCellCallback( getCellContentsModel )

func _container_index_for_cell(cell_row: int) -> int:
	if container == null:
		return -1
	return FlowDataTableModel.value_index( container, _real_row( cell_row ) )

## Data row shown at table row `cell_row` (after filtering and sorting).
func _real_row( cell_row : int ) -> int:
	return visible_rows[cell_row] if cell_row >= 0 and cell_row < visible_rows.size() else cell_row

func getCellContentsModel( cell : DataTableContainer.CellContents ):
	cell.text = model.cell_text( cell.col - 1, _real_row( cell.row ) ) if model != null else ""

func getCellContentsIndex(cell : DataTableContainer.CellContents ):
	var real_row = visible_rows[cell.row] if cell.row < visible_rows.size() else cell.row
	cell.text = "%d" % real_row

func refresh():

	if tv == null:
		return

	tv.clearColumns()
	tv.setColumnCallback( onColumnBegins )

	data = null
	model = null

	if node:

		if is_output:
			if current_bulk_index >= node.generated_bulks.size():
				current_bulk_index = 0

			if node.settings.debug_bulk != current_bulk_index:
				print( "Updating node.settings.debug_bulk to %d" % [ current_bulk_index ])
				node.settings.debug_bulk = current_bulk_index
				node.setupDrawDebug()

			data = node.get_bulk_output( current_bulk_index, current_port_index )
			#print( "Requesting out bulk %d:%d -> %s" % [ current_bulk_index, current_port_index, data ])
			#data.dump( "Data refresh")
		else:
			data = node.get_bulk_input( current_bulk_index, current_port_index )

	if data != null:

		updateNumRowsAndCols()
		var filter_text := ""
		if has_node("%FilterEdit"):
			filter_text = %FilterEdit.text
		update_visible_rows(filter_text)
		apply_sort()

		# Stats: row/col summary
		%LabelStats.text = model.summary_text()

		# Index column
		tv.addColumn( "#", 0 )
		tv.num_rows = visible_rows.size()
		var row_height := get_theme_default_font_size()
		tv.setRowHeight( row_height )

		# Auto-size columns based on header text width
		var base_font = ThemeDB.fallback_font
		var header_font_size = 12
		for title in col_titles:
			var text_w = base_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, header_font_size).x
			var col_w = int(max(text_w + 16, 60)) # min 60px, pad 16px
			if model.is_shape_summary:
				col_w = maxi(col_w, 150) # shape names, bounds and details are long
			tv.addColumn( title, col_w )

	tv.commitColumns()

func onCellClicked( row : int, col : int ):
	tv.setSelectedRow( row )
	if node:
		if row < visible_rows.size():
			node.debug_row = visible_rows[row]
		else:
			node.debug_row = row
		node.setupDrawDebug()

func _data_row_count() -> int:
	if data == null:
		return 0
	var max_rows := 0
	for stream in data.streams.values():
		var container = stream.get("container", [])
		if container != null:
			max_rows = maxi(max_rows, container.size())
	return max_rows

func _get_row_world_position(real_row: int) -> Variant:
	if data == null or real_row < 0:
		return null
	# Shape summary rows focus on the shape's bounds.
	if model != null and model.is_shape_summary:
		return model.row_world_position(real_row)
	if real_row >= _data_row_count():
		return null
	if data.hasStream(FlowData.AttrPosition):
		var positions := data.getVector3Container(FlowData.AttrPosition)
		if real_row < positions.size():
			return positions[real_row]
	for stream_name in data.streams.keys():
		var stream = data.streams[stream_name]
		if stream.data_type == FlowData.DataType.Vector:
			var vectors := data.getVector3Container(stream_name)
			if real_row < vectors.size():
				return vectors[real_row]
	var transforms := data.getTransformsStream()
	if transforms != null and real_row < transforms.positions.size():
		return transforms.positions[real_row]
	return null

func _on_table_row_double_clicked(row: int) -> void:
	if row < 0:
		return
	onCellClicked(row, 0)
	if row >= visible_rows.size():
		return
	var world_position := _get_row_world_position(visible_rows[row])
	if world_position == null:
		return
	var editor := _get_flow_editor()
	if editor and editor.has_method("focus_viewport_on_point"):
		editor.focus_viewport_on_point(world_position)

func _get_flow_editor() -> FlowEditor:
	if _flow_editor != null:
		return _flow_editor
	if node and node.has_method("getEditor"):
		var from_node = node.getEditor()
		if from_node is FlowEditor:
			return from_node as FlowEditor
	var current: Node = self
	while current:
		if current is FlowEditor:
			return current as FlowEditor
		current = current.get_parent()
	return null

func onTitleClicked( col : int ):
	if col < 0 or data == null:
		return
	if sort_col == col:
		sort_ascending = not sort_ascending
	else:
		sort_col = col
		sort_ascending = true
	apply_sort()
	if tv:
		tv.refreshUI()

# Returns a comparable value for the given data row in the given table column.
# Column 0 is the index column; data columns are the model's columns.
func _row_sort_value( real_row : int, col : int ):
	if col == 0:
		return real_row
	if model == null:
		return null
	return model.sort_value( col - 1, real_row )

# Reorders visible_rows by the current sort column/direction. View-only:
# the underlying FlowData streams are never touched.
func apply_sort():
	if sort_col < 0 or data == null or visible_rows.is_empty():
		return
	var keys := {}
	for r in visible_rows:
		keys[r] = _row_sort_value( r, sort_col )
	var asc = sort_ascending
	visible_rows.sort_custom(func(a, b):
		return _sort_rows_less( keys[a], keys[b], asc, a, b )
	)

func _sort_rows_less( va, vb, asc : bool, row_a : int, row_b : int ) -> bool:
	return FlowDataTableModel.sort_less( va, vb, asc, row_a, row_b )

func update_visible_rows(filter_text : String):
	visible_rows.clear()
	if data == null:
		return
	if model == null or model.data != data:
		updateNumRowsAndCols()
	visible_rows = model.filtered_rows( filter_text )

func _on_filter_edit_text_changed(new_text : String):
	update_visible_rows(new_text)
	apply_sort()
	if tv:
		tv.num_rows = visible_rows.size()
		tv.commitColumns()
		
func set_flow_editor(editor: FlowEditor) -> void:
	_flow_editor = editor

func _ready():
	tv.cell_clicked.connect( onCellClicked )
	if not tv.row_double_clicked.is_connected(_on_table_row_double_clicked):
		tv.row_double_clicked.connect(_on_table_row_double_clicked)
	refresh_localized_text()
	if not tv.title_clicked.is_connected(onTitleClicked):
		tv.title_clicked.connect( onTitleClicked )

	# Style the header elements for a compact, polished look
	if has_node("%LabelTitle"):
		%LabelTitle.add_theme_color_override("font_color", Color("22d3ee"))
	if has_node("%LabelStats"):
		%LabelStats.add_theme_color_override("font_color", Color("8b95a5"))

	refresh()

func refresh_localized_text() -> void:
	if has_node("VBoxContainer/HBoxContainer/BtnRefresh"):
		$VBoxContainer/HBoxContainer/BtnRefresh.tooltip_text = FlowI18n.t("Refresh data")
	if has_node("VBoxContainer/HBoxFilter/LabelFilter"):
		$VBoxContainer/HBoxFilter/LabelFilter.text = FlowI18n.t("Filter:")
	if has_node("%FilterEdit"):
		%FilterEdit.placeholder_text = FlowI18n.t("Filter rows...")
	if node and has_node("%LabelTitle"):
		if node.has_method("getLocalizedTitle"):
			%LabelTitle.text = node.getLocalizedTitle()
		else:
			%LabelTitle.text = node.get_title()
	populateSlots()
	refresh()

func _on_btn_refresh_pressed():
	refresh()

func _on_slot_selector_item_selected(index: int) -> void:
	print( "_on_slot_selector_item_selected %d node: %s" % [ index, node ] )
	if not node:
		return

	var meta = node.getMeta()
	if index < meta.outs.size():
		is_output = true
		current_port_index = index
		if current_bulk_index >= node.generated_bulks.size():
			current_bulk_index = 0
		print( "Selected output Bulk:%d Port:%d" % [ current_bulk_index, current_port_index ] )
	else:
		current_port_index = index - meta.outs.size()
		is_output = false
		print( "Selected input Bulk:%d Port:%d" % [ current_bulk_index, current_port_index ] )

	current_bulk_index = 0
	populateBulks()
	refresh()

func _on_bulk_selector_item_selected(index):
	print( "bulk_selector changed to %d node: %s" % [ index, node ] )
	current_bulk_index = index
	refresh()

func populateSlots():
	slot_selector.clear()

	if not node:
		return

	var meta = node.getMeta()

	var idx = 0
	for slot in meta.outs:
		slot_selector.add_item( FlowI18n.tn(slot.label), idx )
		idx +=1

	for slot in meta.ins:
		slot_selector.add_item( FlowI18n.tn(slot.label), idx )
		idx +=1
	populateBulks()

func populateBulks():
	bulk_selector.clear()
	if is_output:
		for bulk_idx in range( node.generated_bulks.size() ):
			bulk_selector.add_item( FlowI18n.t("Out Bulk %d") % [bulk_idx], bulk_idx )
	else:
		for bulk_idx in range( node.input_bulks.size() ):
			bulk_selector.add_item( FlowI18n.t("In Bulk %d") % [bulk_idx], bulk_idx )
	if bulk_selector.get_item_count() > 0:
		current_bulk_index = clampi(current_bulk_index, 0, bulk_selector.get_item_count() - 1)
		bulk_selector.select( current_bulk_index )
