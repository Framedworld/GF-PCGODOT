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

var node : FlowNodeBase
var num_rows : int = 0
var num_cols : int = 0
var col_titles : Array[String]
var col_streams_names : Array[String]
var data : FlowData.Data 
var visible_rows : Array[int] = []

# The slot corresponds to InA, InB, or Out streams for example
# The setetings are not included
var current_bulk_index := 0
var current_port_index := 0
var is_output : bool = true

var container

func setNode( new_node : FlowNodeBase ):
	# If there was already one active... disabled it
	if node:
		%LabelTitle.text = "..."
		if node.settings:
			node.settings.inspect_enabled = false
			node.refreshFromSettings()
		
	if node != new_node and new_node:
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
	num_rows = data.size()
	col_titles.clear()
	col_streams_names.clear()
	for stream in data.streams.values():	
		var stream_name : String = stream.name
		match stream.data_type:
			FlowData.DataType.Vector:
				col_titles.append( "%s.X" % stream_name)
				col_titles.append( "%s.Y" % stream_name)
				col_titles.append( "%s.Z" % stream_name)
				col_streams_names.append( stream_name)
				col_streams_names.append( stream_name)
				col_streams_names.append( stream_name)
			_:
				col_titles.append( "%s" % stream_name)
				col_streams_names.append( stream_name)
	num_cols = col_titles.size()
	#print( col_titles )
	
func fmt( v : float ) -> String:
	return "%1.3f" % v

# When the draw of a column starts, we choose which fn will be used
# to display the data of that column. As all the datas of that column
# have the same type
func onColumnBegins( cell : DataTableContainer.CellContents ):
	cell.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	
	if cell.col == 0:
		tv.setCellCallback( getCellContentsIndex )
		return	
	
	# col = 0 is for the Index
	var data_col = cell.col - 1
	if data_col >= col_streams_names.size():
		tv.cell_contents = null
		return
		
	var stream_name = col_streams_names[ data_col ]
	var stream = data.streams.get( stream_name, null )
	if !stream:
		tv.cell_contents = null
		return
	container = stream.container
		
	var title = col_titles[ data_col ]
	if stream.data_type == FlowData.DataType.Vector:
		if title.ends_with(".X"):
			tv.setCellCallback( getCellContentsVectorX )
		elif title.ends_with(".Y"):
			tv.setCellCallback( getCellContentsVectorY )
		elif title.ends_with(".Z"):
			tv.setCellCallback( getCellContentsVectorZ )
	elif stream.data_type == FlowData.DataType.Bool:
		tv.setCellCallback( getCellContentsBool )
	elif stream.data_type == FlowData.DataType.Int:
		tv.setCellCallback( getCellContentsInt )
	elif stream.data_type == FlowData.DataType.Float:
		tv.setCellCallback( getCellContentsFloat )
	elif stream.data_type == FlowData.DataType.String:
		tv.setCellCallback( getCellContentsString )
		cell.alignment = HORIZONTAL_ALIGNMENT_LEFT
	elif stream.data_type == FlowData.DataType.Resource:
		tv.setCellCallback( getCellContentsResource )
		cell.alignment = HORIZONTAL_ALIGNMENT_LEFT
	elif stream.data_type == FlowData.DataType.NodePath or stream.data_type == FlowData.DataType.NodeMesh:
		tv.setCellCallback( getCellContentsNode )
		cell.alignment = HORIZONTAL_ALIGNMENT_LEFT
		
func getCellContentsVectorX(cell : DataTableContainer.CellContents ):
	var real_row = visible_rows[cell.row] if cell.row < visible_rows.size() else 0
	cell.text = fmt( container[ real_row ].x )
	
func getCellContentsVectorY(cell : DataTableContainer.CellContents ):
	var real_row = visible_rows[cell.row] if cell.row < visible_rows.size() else 0
	cell.text = fmt( container[ real_row ].y )
	
func getCellContentsVectorZ(cell : DataTableContainer.CellContents ):
	var real_row = visible_rows[cell.row] if cell.row < visible_rows.size() else 0
	cell.text = fmt( container[ real_row ].z )
	
func getCellContentsFloat(cell : DataTableContainer.CellContents ):
	var real_row = visible_rows[cell.row] if cell.row < visible_rows.size() else 0
	cell.text = fmt( container[ real_row ] )
	
func getCellContentsBool(cell : DataTableContainer.CellContents ):
	var real_row = visible_rows[cell.row] if cell.row < visible_rows.size() else 0
	cell.text = "True" if container[ real_row ] else "False"
	
func getCellContentsInt(cell : DataTableContainer.CellContents ):
	var real_row = visible_rows[cell.row] if cell.row < visible_rows.size() else 0
	cell.text = "%d" % container[ real_row ]
	
func getCellContentsIndex(cell : DataTableContainer.CellContents ):
	var real_row = visible_rows[cell.row] if cell.row < visible_rows.size() else cell.row
	cell.text = "%d" % real_row
	
func getCellContentsString(cell : DataTableContainer.CellContents ):
	var real_row = visible_rows[cell.row] if cell.row < visible_rows.size() else 0
	cell.text = container[ real_row ]
	
func getCellContentsResource(cell : DataTableContainer.CellContents ):
	var real_row = visible_rows[cell.row] if cell.row < visible_rows.size() else 0
	var res = container[ real_row ] as Resource
	cell.text = res.resource_path if res else ""
			
func getCellContentsNode(cell : DataTableContainer.CellContents ):
	var real_row = visible_rows[cell.row] if cell.row < visible_rows.size() else 0
	var node = container[ real_row ] as Node3D
	cell.text = ( "$" + node.name ) if node else ""
		
func refresh():
	
	if tv == null:
		return

	tv.clearColumns()
	tv.setColumnCallback( onColumnBegins )
	
	data = null
	
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
		
		# Stats: row/col summary
		%LabelStats.text = "%d rows · %d streams · %d cols" % [ num_rows, data.numFields(), num_cols]
		
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

func update_visible_rows(filter_text : String):
	visible_rows.clear()
	if data == null:
		return
	
	if filter_text.is_empty():
		for i in range(data.size()):
			visible_rows.append(i)
	else:
		var filter_lower = filter_text.to_lower()
		for i in range(data.size()):
			var matched = false
			if filter_lower in str(i):
				matched = true
			else:
				for stream in data.streams.values():
					if i >= stream.container.size():
						continue
					var val = stream.container[i]
					match stream.data_type:
						FlowData.DataType.Vector:
							if val is Vector3:
								if filter_lower in fmt(val.x).to_lower() or filter_lower in fmt(val.y).to_lower() or filter_lower in fmt(val.z).to_lower():
									matched = true
									break
						FlowData.DataType.Float:
							if filter_lower in fmt(val).to_lower():
								matched = true
								break
						FlowData.DataType.Bool:
							var b_str = "true" if val else "false"
							if filter_lower in b_str:
								matched = true
								break
						FlowData.DataType.Int:
							if filter_lower in str(val).to_lower():
								matched = true
								break
						FlowData.DataType.String:
							if filter_lower in str(val).to_lower():
								matched = true
								break
						FlowData.DataType.Resource:
							var res = val as Resource
							if res and filter_lower in res.resource_path.to_lower():
								matched = true
								break
						FlowData.DataType.NodePath, FlowData.DataType.NodeMesh:
							var node_val = val as Node3D
							if node_val and filter_lower in ("$" + node_val.name).to_lower():
								matched = true
								break
			if matched:
				visible_rows.append(i)

func _on_filter_edit_text_changed(new_text : String):
	update_visible_rows(new_text)
	if tv:
		tv.num_rows = visible_rows.size()
		tv.commitColumns()

func _ready():
	tv.cell_clicked.connect( onCellClicked )
	
	# Style the header elements for a compact, polished look
	if has_node("%LabelTitle"):
		%LabelTitle.add_theme_color_override("font_color", Color("22d3ee"))
	if has_node("%LabelStats"):
		%LabelStats.add_theme_color_override("font_color", Color("8b95a5"))
	
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
		slot_selector.add_item( slot.label, idx )
		idx +=1

	for slot in meta.ins:
		slot_selector.add_item( slot.label, idx )
		idx +=1
	populateBulks()
	
func populateBulks():
	bulk_selector.clear()
	if is_output:
		for bulk_idx in range( node.generated_bulks.size() ):
			bulk_selector.add_item( "Out Bulk %d" % bulk_idx, bulk_idx )
	else:
		for bulk_idx in range( node.input_bulks.size() ):
			bulk_selector.add_item( "In Bulk %d" % bulk_idx, bulk_idx )
	if bulk_selector.get_item_count() > 0:
		current_bulk_index = clampi(current_bulk_index, 0, bulk_selector.get_item_count() - 1)
		bulk_selector.select( current_bulk_index )
