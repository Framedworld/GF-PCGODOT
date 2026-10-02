@tool
extends VBoxContainer
class_name TableView

@onready var col_titles := %ColumnTitles
var columns : Array[ Label ] = []
var num_rows : int = 0
var col_starts : Array[ float ] = []
var col_widths : Array[ float ] = []
var style_titles = StyleBoxFlat.new()
var dragging := false

var separator : PackedScene = preload("res://addons/flow_nodes_editor/visualization/draggable_separator.tscn") 

signal cell_clicked( row : int, col : int )
signal row_double_clicked( row : int )
signal title_clicked( col : int )

func clearColumns():
	#print("Clearing rooms")
	num_rows = 0
	for child in col_titles.get_children():
		child.queue_free()
	for idx in range(col_titles.get_child_count()):
		col_titles.remove_child( col_titles.get_child( 0 ))
	columns.clear()
	col_starts.clear()
	col_widths.clear()
	$ScrollContainer.num_rows = num_rows
	$ScrollContainer.col_starts = col_starts

func addColumn( text : String, initial_width : int ):
	var parent = col_titles

	var lbl = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_stylebox_override( "normal", style_titles )
	#lbl.add_theme_font_size_override("font_size", 14)
	lbl.custom_minimum_size.x = initial_width

	var child_count = parent.get_child_count()
	if child_count== 0:
		parent.add_child( lbl )
	else:
		var hs := separator.instantiate()
		hs.size.y = 8
		hs.dragged.connect( splitDragged )
		parent.add_child( hs )
		parent.add_child( lbl )
			
	columns.append( lbl )
	
func dataScrolled( _offset : int ):
	$TitlesContainer.scroll_horizontal = $ScrollContainer.scroll_horizontal
	call_deferred( "refreshUI" )
	
func titlesScrolled( _offset : int ):
	$ScrollContainer.scroll_horizontal = $TitlesContainer.scroll_horizontal
	call_deferred( "refreshUI" )
	
func splitDragged( _offset : int ):
	if not is_visible_in_tree():
		return
	$TitlesContainer.position.x = 0
	var my_origin = get_global_transform().origin
	col_starts.clear()
	col_widths.clear()
	var idx = 0
	for col in columns:
		var pos = col.get_global_transform().origin
		
		# Confirm we have the layout correctly evaluated...
		if idx == 1 && col.position.x == 0:
			call_deferred( "refreshUI" )
			return
		var lbl_size = col.size
		#print( "cols %s size is %d. Pos %1.1f vs %1.1f vs %1.1f (%s)" % [ col.name, col.size.x, pos.x, my_origin.x, col.position.x, visible ])
		col_starts.append( pos.x - 4 - my_origin.x )
		col_widths.append( lbl_size.x + 2)
		idx += 1
	if col_starts.size() > 0:
		col_widths[ col_widths.size() - 1 ] -= 16
	$ScrollContainer.num_rows = num_rows
	$ScrollContainer.col_starts = col_starts
	$ScrollContainer.col_widths = col_widths
	$ScrollContainer/Contents.custom_minimum_size.x = col_titles.size.x
	$ScrollContainer/Contents.custom_minimum_size.y = num_rows * $ScrollContainer.line_height
	
	style_titles.bg_color = Color( 0.1, 0.1, 0.1 )	
	updateInfo()
	$ScrollContainer.queue_redraw()
	
func updateInfo():
	var ctxt : String = ""
	for idx in range( col_starts.size() ):
		ctxt = ctxt + " / %d - %d" % [ col_starts[idx], col_widths[idx] ] 
	$DebugInfo.text = ctxt

func refreshUI():
	splitDragged(0)

func commitColumns():
	addColumn( "", 0 )
	#print("Comminging columns %d" % col_starts.size())
	call_deferred( "refreshUI" )

func setCellCallback( new_cell_callback : Callable ):
	$ScrollContainer.cell_contents = new_cell_callback

func setColumnCallback( new_callback : Callable ):
	_owner_column_callback = new_callback
	$ScrollContainer.column_callback = _on_column_begins

# The owner's column callback picks a typed cell formatter per column. A column
# whose type it does not handle (Color, Quaternion and the extended types
# Vector2, Vector4, Transform, Int64, Double) used to keep the PREVIOUS
# column's formatter, which errors on a value of another type. Reset to a
# generic str() formatter first; the owner's callback overrides it as before.
var _owner_column_callback : Callable

func _on_column_begins( cell ):
	$ScrollContainer.cell_contents = _generic_cell_contents
	if _owner_column_callback.is_valid():
		_owner_column_callback.call( cell )

# Reads the owner's current `container` (and its visible-row mapping when it
# has one) and shows str(value). Duck-typed so the table stays data-agnostic.
func _generic_cell_contents( cell ):
	cell.text = ""
	var owner = _owner_column_callback.get_object() if _owner_column_callback.is_valid() else null
	if owner == null or not is_instance_valid( owner ):
		return
	var container = owner.get( "container" )
	if container == null or not ( container is Array or typeof( container ) >= TYPE_PACKED_BYTE_ARRAY ):
		return
	var idx = cell.row
	if owner.has_method( "_container_index_for_cell" ):
		idx = owner._container_index_for_cell( cell.row )
	if not ( idx is int ) or idx < 0 or idx >= container.size():
		return
	var value = container[ idx ]
	if value is Object:
		cell.text = str( value.get( "resource_path" ) if value is Resource else value.get( "name" ) ) if is_instance_valid( value ) else ""
	else:
		cell.text = str( value )

func _ready():
	$TitlesContainer.get_h_scroll_bar().value_changed.connect( titlesScrolled )
	$ScrollContainer.get_h_scroll_bar().value_changed.connect( dataScrolled )
	var contents: Control = $ScrollContainer.get_node_or_null("Contents") as Control
	if contents:
		contents.mouse_filter = Control.MOUSE_FILTER_STOP
		if not contents.gui_input.is_connected(_on_contents_gui_input):
			contents.gui_input.connect(_on_contents_gui_input)

func setSelectedRow( new_row : int ):
	$ScrollContainer.selected_row = new_row
	call_deferred( "refreshUI" )

func setRowHeight( new_height : float ):
	$ScrollContainer.font_size = new_height
	$ScrollContainer.line_height = new_height * 1.4
	
func findColAtX(ex: float) -> int:
	if col_starts.size() < 2:
		return -1
	ex -= $ScrollContainer.scroll_horizontal
	if ex < col_starts[0]:
		return 0
	for col in range(col_starts.size() - 1):
		if ex >= col_starts[col] and ex < col_starts[col + 1]:
			return col
	return col_starts.size() - 2

## [param viewport_relative]: true for ScrollContainer / viewport coords; false for Contents content coords.
func _row_at_local_position(local_pos: Vector2, viewport_relative: bool = true) -> int:
	if $ScrollContainer.line_height <= 0:
		return -1
	var content_y := local_pos.y
	if viewport_relative:
		content_y += float($ScrollContainer.scroll_vertical)
	var row := int(floor(content_y / float($ScrollContainer.line_height)))
	if row < 0 or row >= $ScrollContainer.num_rows:
		return -1
	return row

func _emit_cell_click_at(event: InputEvent, viewport_relative: bool) -> void:
	var row := _row_at_local_position(event.position, viewport_relative)
	if row < 0:
		return
	var col := findColAtX(event.position.x)
	if col < 0:
		col = 0
	cell_clicked.emit(row, col)

func _handle_table_pointer_event(event: InputEvent, viewport_relative: bool) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and event.double_click:
				var row := _row_at_local_position(event.position, viewport_relative)
				if row >= 0:
					row_double_clicked.emit(row)
					accept_event()
				return
			if event.pressed:
				dragging = true
				_emit_cell_click_at(event, viewport_relative)
			else:
				if dragging:
					_emit_cell_click_at(event, viewport_relative)
				dragging = false
	elif event is InputEventMouseMotion and dragging:
		_emit_cell_click_at(event, viewport_relative)

func _on_contents_gui_input(event: InputEvent) -> void:
	_handle_table_pointer_event(event, false)

func _on_column_titles_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var col = findColAtX( event.position.x )
				title_clicked.emit( col )

func _on_visibility_changed() -> void:
	if visible:
		call_deferred( "refreshUI" )
