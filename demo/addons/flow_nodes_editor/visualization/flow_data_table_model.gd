@tool
class_name FlowDataTableModel
extends RefCounted

## Table model of one FlowData.Data for the data inspector (data_inspector.gd):
## columns, cell text, sort keys and the text filter, as pure functions, so
## every DataType can be checked without drawing. The inspector only maps
## TableView callbacks onto it.
##
## Columns per stream type:
##   Bool                       one column, True / False
##   Int, Int64                 one column, integer text
##   Float                      one column, 3 decimals
##   Double                     one column, 6 decimals
##   Vector                     .X .Y .Z (3 decimals each)
##   Vector2                    .X .Y
##   Vector4, Quaternion        .X .Y .Z .W
##   Color                      .R .G .B .A
##   Transform                  .Pos.X/Y/Z, .Rot.X/Y/Z (Euler degrees, the
##                              point rotation convention), .Scale.X/Y/Z
##   String                     text, left aligned
##   Resource                   resource path ("[Class]" when it has none)
##   NodeMesh, NodePath         "$" + node name ("" for a freed node)
##   anything else              str(value)
## A stream holding one value for many rows (broadcast) shows that value on
## every row.
##
## Shape-only Data (a FlowSpatial on Data.shape and no points) shows a summary
## table instead: one row for the shape and, for composites, one row per
## operand (depth-first, indented, at most MAX_SHAPE_ROWS), with the columns
## Shape, Kind, Points, Bounds Min, Bounds Max, Size and Detail.

const MAX_SHAPE_ROWS := 64

const SHAPE_COLUMNS := [ "Shape", "Kind", "Points", "Bounds Min", "Bounds Max", "Size", "Detail" ]

## Component suffixes per multi-column type.
const COMPONENTS := {
	FlowData.DataType.Vector: [ "X", "Y", "Z" ],
	FlowData.DataType.Vector2: [ "X", "Y" ],
	FlowData.DataType.Vector4: [ "X", "Y", "Z", "W" ],
	FlowData.DataType.Quaternion: [ "X", "Y", "Z", "W" ],
	FlowData.DataType.Color: [ "R", "G", "B", "A" ],
	FlowData.DataType.Transform: [ "Pos.X", "Pos.Y", "Pos.Z", "Rot.X", "Rot.Y", "Rot.Z", "Scale.X", "Scale.Y", "Scale.Z" ],
}

const LEFT_ALIGNED_TYPES := [
	FlowData.DataType.String, FlowData.DataType.Resource,
	FlowData.DataType.NodeMesh, FlowData.DataType.NodePath,
]

class Column:
	extends RefCounted
	var title : String = ""
	## Stream name ("" for shape summary columns).
	var stream_name : String = ""
	var data_type : int = FlowData.DataType.Invalid
	## Component index for multi-column types, -1 for a whole value.
	var component : int = -1
	var alignment : int = HORIZONTAL_ALIGNMENT_RIGHT
	## The stream's container (null for shape summary columns).
	var container = null

var data : FlowData.Data
var columns : Array[Column] = []
var row_count : int = 0
## True when the table is the shape summary of a shape-only Data.
var is_shape_summary : bool = false
## Shape summary rows: Array of { depth, role, shape, cells : PackedStringArray }.
var shape_rows : Array = []

func _init( source : FlowData.Data = null ) -> void:
	set_data( source )

func set_data( source : FlowData.Data ) -> void:
	data = source
	columns.clear()
	shape_rows.clear()
	row_count = 0
	is_shape_summary = false
	if data == null:
		return
	if data.shape != null and data.size() == 0:
		_build_shape_summary()
		return
	row_count = data.size()
	for stream in data.streams.values():
		var stream_name := String( stream.name )
		var data_type := int( stream.data_type )
		var parts : Array = COMPONENTS.get( data_type, [] )
		if parts.is_empty():
			columns.append( _make_column( stream_name, stream_name, data_type, -1, stream.container ) )
		else:
			for k in range( parts.size() ):
				columns.append( _make_column( "%s.%s" % [ stream_name, parts[k] ], stream_name, data_type, k, stream.container ) )

static func _make_column( title : String, stream_name : String, data_type : int, component : int, container ) -> Column:
	var c := Column.new()
	c.title = title
	c.stream_name = stream_name
	c.data_type = data_type
	c.component = component
	c.container = container
	c.alignment = HORIZONTAL_ALIGNMENT_LEFT if LEFT_ALIGNED_TYPES.has( data_type ) else HORIZONTAL_ALIGNMENT_RIGHT
	return c

func column_count() -> int:
	return columns.size()

func titles() -> Array[String]:
	var out : Array[String] = []
	for c in columns:
		out.append( c.title )
	return out

## One entry per column: the stream each column reads ("" for summary columns).
func stream_names() -> Array[String]:
	var out : Array[String] = []
	for c in columns:
		out.append( c.stream_name )
	return out

## Index into `container` for table row `row` (broadcast streams map every
## row to their one value), or -1.
static func value_index( container, row : int ) -> int:
	if container == null:
		return -1
	var n : int = container.size()
	if n <= 0 or row < 0:
		return -1
	if row < n:
		return row
	if n == 1:
		return 0
	return -1

## Raw value of column `col` at data row `row` (the whole value for vectors),
## or null.
func raw_value( col : int, row : int ):
	if col < 0 or col >= columns.size():
		return null
	var c := columns[col]
	var i := value_index( c.container, row )
	if i < 0:
		return null
	return c.container[i]

# --- Cell text ----------------------------------------------------------------

## `v` with `digits` decimals. Negative zero, and negatives that round to zero,
## show as an unsigned zero (a zero rotation is often -0.0); the data keeps its
## value.
static func fmt_real( v : float, digits : int = 3 ) -> String:
	var text : String = ( "%1." + str( digits ) + "f" ) % v
	if text.begins_with( "-" ) and text.substr( 1 ).replace( "0", "" ).replace( ".", "" ).is_empty():
		return text.substr( 1 )
	return text

## Text of the cell at column `col`, data row `row`.
func cell_text( col : int, row : int ) -> String:
	if is_shape_summary:
		if row < 0 or row >= shape_rows.size() or col < 0 or col >= columns.size():
			return ""
		var cells : PackedStringArray = shape_rows[row].cells
		return cells[col] if col < cells.size() else ""
	if col < 0 or col >= columns.size():
		return ""
	var c := columns[col]
	var i := value_index( c.container, row )
	if i < 0:
		return ""
	return format_value( c.container[i], c.data_type, c.component )

## Text of one value of `data_type` (component `component` for multi-column
## types).
static func format_value( value, data_type : int, component : int = -1 ) -> String:
	if component >= 0:
		var n = component_number( value, data_type, component )
		return fmt_real( n ) if n != null else ""
	match data_type:
		FlowData.DataType.Bool:
			return FlowI18n.t( "True" ) if value else FlowI18n.t( "False" )
		FlowData.DataType.Int, FlowData.DataType.Int64:
			return "%d" % int( value ) if _is_number( value ) else str( value )
		FlowData.DataType.Float:
			return fmt_real( float( value ) ) if _is_number( value ) else str( value )
		FlowData.DataType.Double:
			return fmt_real( float( value ), 6 ) if _is_number( value ) else str( value )
		FlowData.DataType.String:
			return str( value )
		FlowData.DataType.Resource:
			return _resource_text( value )
		FlowData.DataType.NodePath, FlowData.DataType.NodeMesh:
			return _node_text( value )
	if value is Object:
		return _resource_text( value ) if value is Resource else _node_text( value )
	return str( value )

static func _is_number( value ) -> bool:
	return value is int or value is float or value is bool

static func _resource_text( value ) -> String:
	if not ( value is Object ) or not is_instance_valid( value ):
		return ""
	var res := value as Resource
	if res == null:
		return ""
	if not res.resource_path.is_empty():
		return res.resource_path
	return "[%s]" % res.get_class()

static func _node_text( value ) -> String:
	if not ( value is Object ) or not is_instance_valid( value ):
		return ""
	var node := value as Node
	return ( "$" + String( node.name ) ) if node else ""

## Number shown in a component column, or null when `value` does not have
## that component.
static func component_number( value, data_type : int, component : int ):
	match data_type:
		FlowData.DataType.Vector:
			if value is Vector3 and component < 3:
				return value[component]
		FlowData.DataType.Vector2:
			if ( value is Vector2 or value is Vector2i ) and component < 2:
				return float( value[component] )
		FlowData.DataType.Vector4, FlowData.DataType.Quaternion:
			if ( value is Vector4 or value is Quaternion ) and component < 4:
				return value[component]
		FlowData.DataType.Color:
			if value is Color and component < 4:
				return value[component]
		FlowData.DataType.Transform:
			if value is Transform3D and component < 9:
				var t : Transform3D = value
				if component < 3:
					return t.origin[component]
				if component < 6:
					return FlowData.basisToEuler( t.basis.orthonormalized() )[component - 3]
				return t.basis.get_scale()[component - 6]
	return null

# --- Sorting and filtering ---------------------------------------------------------

## Comparable key of column `col` at data row `row`: a number for numeric
## columns and components, a String otherwise, null for an empty cell.
func sort_value( col : int, row : int ):
	if is_shape_summary:
		var text := cell_text( col, row )
		return text if not text.is_empty() else null
	if col < 0 or col >= columns.size():
		return null
	var c := columns[col]
	var i := value_index( c.container, row )
	if i < 0:
		return null
	var value = c.container[i]
	if c.component >= 0:
		return component_number( value, c.data_type, c.component )
	match c.data_type:
		FlowData.DataType.Bool:
			return 1 if value else 0
		FlowData.DataType.Int, FlowData.DataType.Int64:
			return int( value ) if _is_number( value ) else str( value )
		FlowData.DataType.Float, FlowData.DataType.Double:
			return float( value ) if _is_number( value ) else str( value )
	# Text columns: an empty cell (no resource, a freed node, "") sorts last.
	var text := format_value( value, c.data_type, c.component )
	return text if not text.is_empty() else null

## True when `row` matches the filter: the lowercase filter text is found in
## the row index or in the text of any of its cells.
func row_matches( row : int, filter_lower : String ) -> bool:
	if filter_lower.is_empty():
		return true
	if filter_lower in str( row ):
		return true
	for col in range( columns.size() ):
		if filter_lower in cell_text( col, row ).to_lower():
			return true
	return false

## Rows that match the filter, in data order.
func filtered_rows( filter_text : String ) -> Array[int]:
	var out : Array[int] = []
	var filter_lower := filter_text.to_lower()
	for r in range( row_count ):
		if row_matches( r, filter_lower ):
			out.append( r )
	return out

## `rows` reordered by column `col` (stable; empty cells last).
func sorted_rows( rows : Array[int], col : int, ascending : bool ) -> Array[int]:
	var keys := {}
	for r in rows:
		keys[r] = sort_value( col, r )
	var out : Array[int] = rows.duplicate()
	out.sort_custom( func( a, b ): return sort_less( keys[a], keys[b], ascending, a, b ) )
	return out

## Order of two sort keys: nulls last whatever the direction, numbers
## numerically, numeric strings numerically, anything else as text; ties by
## row index.
static func sort_less( va, vb, asc : bool, row_a : int, row_b : int ) -> bool:
	if va == null or vb == null:
		if va == null and vb == null:
			return row_a < row_b
		return va != null
	if va is String and vb is String and va.is_valid_float() and vb.is_valid_float():
		va = va.to_float()
		vb = vb.to_float()
	var a_num = ( va is int ) or ( va is float )
	var b_num = ( vb is int ) or ( vb is float )
	if not ( a_num and b_num ) and not ( va is String and vb is String ):
		va = str( va )
		vb = str( vb )
	if va == vb:
		return row_a < row_b
	return ( va < vb ) if asc else ( va > vb )

# --- Shape summary -----------------------------------------------------------------

func _build_shape_summary() -> void:
	is_shape_summary = true
	for i in range( SHAPE_COLUMNS.size() ):
		var c := _make_column( SHAPE_COLUMNS[i], "", FlowData.DataType.String, -1, null )
		c.alignment = HORIZONTAL_ALIGNMENT_LEFT
		columns.append( c )
	_add_shape_rows( data.shape, 0, "" )
	row_count = shape_rows.size()

func _add_shape_rows( shape : FlowSpatial, depth : int, role : String ) -> void:
	if shape == null or shape_rows.size() >= MAX_SHAPE_ROWS:
		return
	var b := shape.get_bounds()
	var cells := PackedStringArray()
	var indent := "  ".repeat( depth )
	cells.append( indent + ( role + ": " if not role.is_empty() else "" ) + shape_class_name( shape ) )
	cells.append( kind_name( shape.get_kind() ) )
	cells.append( str( data.size() ) if depth == 0 else "" )
	cells.append( _vec_text( b.position ) )
	cells.append( _vec_text( b.end ) )
	cells.append( _vec_text( b.size ) )
	cells.append( shape_detail( shape ) )
	shape_rows.append( { "depth": depth, "role": role, "shape": shape, "cells": cells } )
	if shape is FlowCompositeShape:
		_add_shape_rows( shape.a, depth + 1, "A" )
		_add_shape_rows( shape.b, depth + 1, "B" )

## World position to focus for a shape summary row (its bounds centre), or null.
func row_world_position( row : int ):
	if not is_shape_summary or row < 0 or row >= shape_rows.size():
		return null
	var shape : FlowSpatial = shape_rows[row].shape
	return shape.get_bounds().get_center()

static func _vec_text( v : Vector3 ) -> String:
	return "(%s, %s, %s)" % [ fmt_real( v.x ), fmt_real( v.y ), fmt_real( v.z ) ]

static func kind_name( kind : int ) -> String:
	var keys := FlowData.Kind.keys()
	return keys[kind] if kind >= 0 and kind < keys.size() else str( kind )

## The shape's script class (FlowSplineShape, ...), or its type name.
static func shape_class_name( shape : FlowSpatial ) -> String:
	var script = shape.get_script()
	if script is Script:
		var global_name := String( script.get_global_name() )
		if not global_name.is_empty():
			return global_name
	return shape.get_type_name()

## One line of shape-specific facts.
static func shape_detail( shape : FlowSpatial ) -> String:
	if shape is FlowCompositeShape:
		var fn_names := [ "Binary", "Minimum", "Multiply", "Subtract" ]
		var fn_name : String = fn_names[shape.density_function] if shape.density_function >= 0 and shape.density_function < fn_names.size() else str( shape.density_function )
		return "%s, density %s" % [ FlowSpatial.Op.keys()[shape.op], fn_name ]
	if shape is FlowSplineShape:
		return "%d points, length %s%s, tube %s" % [ shape.curve.point_count, fmt_real( shape.get_length() ), ", closed" if shape.closed else "", fmt_real( shape.half_width ) ]
	if shape is FlowPolygonSurface:
		return "%d vertices, area %s" % [ shape.polygon.size(), fmt_real( shape.get_area() ) ]
	if shape is FlowHeightfieldSurface:
		return "%dx%d samples, cell %s" % [ shape.width, shape.depth, fmt_real( shape.cell_size ) ]
	if shape is FlowMeshSurface:
		return "%d triangles" % shape.get_triangle_count()
	if shape is FlowMeshVolume:
		return "%d triangles" % ( shape.grid.tri_count if shape.grid != null else 0 )
	if shape is FlowBoxVolume:
		return "half extents %s, steepness %s" % [ _vec_text( shape.half_extents ), fmt_real( shape.steepness ) ]
	if shape is FlowSphereVolume:
		return "radius %s, steepness %s" % [ fmt_real( shape.radius ), fmt_real( shape.steepness ) ]
	if shape is FlowPointsVolume:
		return "%d boxes" % shape.get_point_count()
	return ""

## One line for the inspector's stats label.
func summary_text() -> String:
	if data == null:
		return ""
	var text := FlowI18n.t( "%d rows · %d streams · %d cols" ) % [ row_count if not is_shape_summary else data.size(), data.numFields(), columns.size() if not is_shape_summary else 0 ]
	if data.shape != null:
		text += " · %s %s (%s)" % [ FlowI18n.t( "shape" ), shape_class_name( data.shape ), kind_name( data.shape.get_kind() ) ]
	return text
