# load_data_table_test.gd
class_name LoadDataTableTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const LoadDataTableNode = preload("res://addons/flow_nodes_editor/nodes/load_data_table.gd")
const LoadDataTableSettings = preload("res://addons/flow_nodes_editor/nodes/load_data_table_settings.gd")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _output(node) -> FlowData.Data:
	if node.generated_bulks.is_empty(): return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty(): return null
	return bulk[0]

func _run(settings) -> LoadDataTableNode:
	var node = LoadDataTableNode.new()
	node.name = "test_node"
	node.settings = settings
	node.inputs = []
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

## Write text to a user:// temp file and return its absolute path.
func _write_temp(filename: String, content: String) -> String:
	var path = "user://" + filename
	var f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(content)
	f.close()
	return path

func _default_settings() -> LoadDataTableSettings:
	var s = LoadDataTableSettings.new()
	s.first_row_is_header = true
	s.delimiter = LoadDataTableSettings.eDelimiter.Comma
	s.trim_values = true
	s.infer_column_types = true
	s.add_row_index = false
	s.add_source_path = false
	return s

# ---------------------------------------------------------------------------
# Error-path tests
# ---------------------------------------------------------------------------

func test_empty_path_produces_no_error() -> void:
	var s = _default_settings()
	s.table_path = ""
	var node = _run(s)
	assert_str(node.err).is_empty()
	node.free()

func test_missing_file_sets_error() -> void:
	var s = _default_settings()
	s.table_path = "res://this_file_does_not_exist_ever.csv"
	var node = _run(s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_missing_file_error_mentions_path() -> void:
	var s = _default_settings()
	s.table_path = "res://no_such_file.csv"
	var node = _run(s)
	assert_str(node.err).contains("no_such_file.csv")
	node.free()

# ---------------------------------------------------------------------------
# Basic CSV parsing: column count and row count
# ---------------------------------------------------------------------------

func test_basic_csv_row_and_column_count() -> void:
	var csv = "name,age,score\nAlice,30,9.5\nBob,25,8.0\n"
	var path = _write_temp("test_basic.csv", csv)
	var s = _default_settings()
	s.table_path = path
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	# 3 data rows, 3 columns (name, age, score)
	var name_stream = out.findStream("name")
	assert_object(name_stream).is_not_null()
	assert_int(name_stream.container.size()).is_equal(2)
	node.free()

# ---------------------------------------------------------------------------
# Type inference: Int column
# ---------------------------------------------------------------------------

func test_infers_int_column() -> void:
	var csv = "id,value\n1,10\n2,20\n3,30\n"
	var path = _write_temp("test_int.csv", csv)
	var s = _default_settings()
	s.table_path = path
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var id_stream = out.findStream("id")
	assert_object(id_stream).is_not_null()
	# Container should be PackedInt32Array
	assert_int(id_stream.container[0]).is_equal(1)
	assert_int(id_stream.container[1]).is_equal(2)
	assert_int(id_stream.container[2]).is_equal(3)
	node.free()

# ---------------------------------------------------------------------------
# Type inference: Float column
# ---------------------------------------------------------------------------

func test_infers_float_column() -> void:
	var csv = "x\n1.5\n2.5\n3.5\n"
	var path = _write_temp("test_float.csv", csv)
	var s = _default_settings()
	s.table_path = path
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var x_stream = out.findStream("x")
	assert_object(x_stream).is_not_null()
	assert_float(x_stream.container[0]).is_equal_approx(1.5, 0.001)
	assert_float(x_stream.container[1]).is_equal_approx(2.5, 0.001)
	assert_float(x_stream.container[2]).is_equal_approx(3.5, 0.001)
	node.free()

# ---------------------------------------------------------------------------
# Type inference: Bool column
# ---------------------------------------------------------------------------

func test_infers_bool_column() -> void:
	var csv = "flag\ntrue\nfalse\ntrue\n"
	var path = _write_temp("test_bool.csv", csv)
	var s = _default_settings()
	s.table_path = path
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var flag_stream = out.findStream("flag")
	assert_object(flag_stream).is_not_null()
	assert_int(flag_stream.container[0]).is_equal(1)
	assert_int(flag_stream.container[1]).is_equal(0)
	assert_int(flag_stream.container[2]).is_equal(1)
	node.free()

# ---------------------------------------------------------------------------
# Type inference: String column (mixed types -> falls back to String)
# ---------------------------------------------------------------------------

func test_infers_string_column_for_mixed() -> void:
	var csv = "label\nhello\n42\nworld\n"
	var path = _write_temp("test_string.csv", csv)
	var s = _default_settings()
	s.table_path = path
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var label_stream = out.findStream("label")
	assert_object(label_stream).is_not_null()
	# String container
	assert_str(String(label_stream.container[0])).is_equal("hello")
	assert_str(String(label_stream.container[2])).is_equal("world")
	node.free()

# ---------------------------------------------------------------------------
# Type inference disabled: all columns become String
# ---------------------------------------------------------------------------

func test_no_type_inference_all_strings() -> void:
	var csv = "id,value\n1,10\n2,20\n"
	var path = _write_temp("test_no_infer.csv", csv)
	var s = _default_settings()
	s.table_path = path
	s.infer_column_types = false
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var id_stream = out.findStream("id")
	assert_object(id_stream).is_not_null()
	# Without inference, container should be PackedStringArray
	assert_str(String(id_stream.container[0])).is_equal("1")
	assert_str(String(id_stream.container[1])).is_equal("2")
	node.free()

# ---------------------------------------------------------------------------
# Vector column (quoted "x,y,z" in comma-delimited file)
# ---------------------------------------------------------------------------

func test_infers_vector_column_quoted() -> void:
	var csv = "pos\n\"1,2,3\"\n\"4,5,6\"\n"
	var path = _write_temp("test_vector.csv", csv)
	var s = _default_settings()
	s.table_path = path
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream("pos")
	assert_object(pos_stream).is_not_null()
	var v0 = pos_stream.container[0]
	assert_bool(Vector3(1, 2, 3).is_equal_approx(v0)).is_true()
	var v1 = pos_stream.container[1]
	assert_bool(Vector3(4, 5, 6).is_equal_approx(v1)).is_true()
	node.free()

# ---------------------------------------------------------------------------
# Tab delimiter
# ---------------------------------------------------------------------------

func test_tab_delimiter() -> void:
	var csv = "a\tb\n10\t20\n30\t40\n"
	var path = _write_temp("test_tab.tsv", csv)
	var s = _default_settings()
	s.table_path = path
	s.delimiter = LoadDataTableSettings.eDelimiter.Tab
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var a_stream = out.findStream("a")
	assert_object(a_stream).is_not_null()
	assert_int(a_stream.container[0]).is_equal(10)
	assert_int(a_stream.container[1]).is_equal(30)
	node.free()

# ---------------------------------------------------------------------------
# Semicolon delimiter
# ---------------------------------------------------------------------------

func test_semicolon_delimiter() -> void:
	var csv = "x;y\n1;2\n3;4\n"
	var path = _write_temp("test_semi.csv", csv)
	var s = _default_settings()
	s.table_path = path
	s.delimiter = LoadDataTableSettings.eDelimiter.Semicolon
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var x_stream = out.findStream("x")
	assert_object(x_stream).is_not_null()
	assert_int(x_stream.container[0]).is_equal(1)
	node.free()

# ---------------------------------------------------------------------------
# Pipe delimiter
# ---------------------------------------------------------------------------

func test_pipe_delimiter() -> void:
	var csv = "col1|col2\nfoo|bar\nbaz|qux\n"
	var path = _write_temp("test_pipe.csv", csv)
	var s = _default_settings()
	s.table_path = path
	s.delimiter = LoadDataTableSettings.eDelimiter.Pipe
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var col1_stream = out.findStream("col1")
	assert_object(col1_stream).is_not_null()
	assert_str(String(col1_stream.container[0])).is_equal("foo")
	assert_str(String(col1_stream.container[1])).is_equal("baz")
	node.free()

# ---------------------------------------------------------------------------
# first_row_is_header = false: auto-generated column names
# ---------------------------------------------------------------------------

func test_no_header_generates_column_names() -> void:
	var csv = "1,2,3\n4,5,6\n"
	var path = _write_temp("test_noheader.csv", csv)
	var s = _default_settings()
	s.table_path = path
	s.first_row_is_header = false
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	# Expect columns named column_0, column_1, column_2
	assert_object(out.findStream("column_0")).is_not_null()
	assert_object(out.findStream("column_1")).is_not_null()
	assert_object(out.findStream("column_2")).is_not_null()
	# Values are all rows (no header consumed)
	var c0 = out.findStream("column_0")
	assert_int(c0.container.size()).is_equal(2)
	node.free()

# ---------------------------------------------------------------------------
# Duplicate header names get unique suffixes
# ---------------------------------------------------------------------------

func test_duplicate_headers_made_unique() -> void:
	var csv = "x,x,x\n1,2,3\n"
	var path = _write_temp("test_dup.csv", csv)
	var s = _default_settings()
	s.table_path = path
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream("x")).is_not_null()
	assert_object(out.findStream("x_1")).is_not_null()
	assert_object(out.findStream("x_2")).is_not_null()
	node.free()

# ---------------------------------------------------------------------------
# Header spaces replaced with underscores
# ---------------------------------------------------------------------------

func test_header_spaces_replaced_with_underscores() -> void:
	var csv = "first name,last name\nAlice,Smith\n"
	var path = _write_temp("test_spaces.csv", csv)
	var s = _default_settings()
	s.table_path = path
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream("first_name")).is_not_null()
	assert_object(out.findStream("last_name")).is_not_null()
	node.free()

# ---------------------------------------------------------------------------
# trim_values: leading/trailing whitespace stripped
# ---------------------------------------------------------------------------

func test_trim_values_strips_whitespace() -> void:
	var csv = "val\n  hello  \n  world  \n"
	var path = _write_temp("test_trim.csv", csv)
	var s = _default_settings()
	s.table_path = path
	s.trim_values = true
	s.infer_column_types = false
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var v = out.findStream("val")
	assert_str(String(v.container[0])).is_equal("hello")
	assert_str(String(v.container[1])).is_equal("world")
	node.free()

# ---------------------------------------------------------------------------
# trim_values = false: whitespace preserved
# ---------------------------------------------------------------------------

func test_no_trim_preserves_whitespace() -> void:
	var csv = "val\n  hello  \n"
	var path = _write_temp("test_notrim.csv", csv)
	var s = _default_settings()
	s.table_path = path
	s.trim_values = false
	s.infer_column_types = false
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var v = out.findStream("val")
	assert_str(String(v.container[0])).is_equal("  hello  ")
	node.free()

# ---------------------------------------------------------------------------
# add_row_index emits a zero-based Int stream
# ---------------------------------------------------------------------------

func test_add_row_index_stream() -> void:
	var csv = "name\nAlice\nBob\nCarol\n"
	var path = _write_temp("test_rowindex.csv", csv)
	var s = _default_settings()
	s.table_path = path
	s.add_row_index = true
	s.row_index_attribute = "row_index"
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var idx = out.findStream("row_index")
	assert_object(idx).is_not_null()
	assert_int(idx.container.size()).is_equal(3)
	assert_int(idx.container[0]).is_equal(0)
	assert_int(idx.container[1]).is_equal(1)
	assert_int(idx.container[2]).is_equal(2)
	node.free()

# ---------------------------------------------------------------------------
# add_row_index with blank attribute name: stream NOT added
# ---------------------------------------------------------------------------

func test_add_row_index_blank_name_skipped() -> void:
	var csv = "name\nAlice\n"
	var path = _write_temp("test_rowindex_blank.csv", csv)
	var s = _default_settings()
	s.table_path = path
	s.add_row_index = true
	s.row_index_attribute = ""
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	# No row_index stream should exist when attribute name is blank
	assert_object(out.findStream("")).is_null()
	node.free()

# ---------------------------------------------------------------------------
# add_source_path emits a String stream with the file path
# ---------------------------------------------------------------------------

func test_add_source_path_stream() -> void:
	var csv = "val\n1\n2\n"
	var path = _write_temp("test_srcpath.csv", csv)
	var s = _default_settings()
	s.table_path = path
	s.add_source_path = true
	s.source_path_attribute = "source_path"
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var sp = out.findStream("source_path")
	assert_object(sp).is_not_null()
	assert_int(sp.container.size()).is_equal(2)
	assert_str(String(sp.container[0])).is_equal(path)
	assert_str(String(sp.container[1])).is_equal(path)
	node.free()

# ---------------------------------------------------------------------------
# Quoted fields containing the delimiter are parsed as one cell
# ---------------------------------------------------------------------------

func test_quoted_field_with_delimiter_inside() -> void:
	var csv = "note,value\n\"hello, world\",42\n"
	var path = _write_temp("test_quoted.csv", csv)
	var s = _default_settings()
	s.table_path = path
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var note_stream = out.findStream("note")
	assert_object(note_stream).is_not_null()
	assert_str(String(note_stream.container[0])).is_equal("hello, world")
	node.free()

# ---------------------------------------------------------------------------
# Escaped quotes ("") inside a quoted field
# ---------------------------------------------------------------------------

func test_escaped_double_quotes_in_field() -> void:
	var csv = "text\n\"say \"\"hello\"\"\"\n"
	var path = _write_temp("test_escape_quotes.csv", csv)
	var s = _default_settings()
	s.table_path = path
	s.infer_column_types = false
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var text_stream = out.findStream("text")
	assert_object(text_stream).is_not_null()
	assert_str(String(text_stream.container[0])).is_equal("say \"hello\"")
	node.free()

# ---------------------------------------------------------------------------
# Empty file produces no error and no streams (or empty data)
# ---------------------------------------------------------------------------

func test_empty_file_produces_no_error() -> void:
	var path = _write_temp("test_empty.csv", "")
	var s = _default_settings()
	s.table_path = path
	var node = _run(s)
	assert_str(node.err).is_empty()
	node.free()

# ---------------------------------------------------------------------------
# Single header row only (no data rows) produces zero-size streams
# ---------------------------------------------------------------------------

func test_header_only_produces_zero_rows() -> void:
	var csv = "name,age\n"
	var path = _write_temp("test_headeronly.csv", csv)
	var s = _default_settings()
	s.table_path = path
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var name_stream = out.findStream("name")
	assert_object(name_stream).is_not_null()
	assert_int(name_stream.container.size()).is_equal(0)
	node.free()

# ---------------------------------------------------------------------------
# CRLF line endings parsed correctly
# ---------------------------------------------------------------------------

func test_crlf_line_endings() -> void:
	var csv = "a,b\r\n1,2\r\n3,4\r\n"
	var path = _write_temp("test_crlf.csv", csv)
	var s = _default_settings()
	s.table_path = path
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var a_stream = out.findStream("a")
	assert_object(a_stream).is_not_null()
	assert_int(a_stream.container.size()).is_equal(2)
	assert_int(a_stream.container[0]).is_equal(1)
	assert_int(a_stream.container[1]).is_equal(3)
	node.free()

# ---------------------------------------------------------------------------
# Blank column header falls back to "column_N"
# ---------------------------------------------------------------------------

func test_blank_header_becomes_column_index_name() -> void:
	var csv = ",value\nhello,42\n"
	var path = _write_temp("test_blankheader.csv", csv)
	var s = _default_settings()
	s.table_path = path
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	# Blank first header -> "column_0"
	assert_object(out.findStream("column_0")).is_not_null()
	assert_object(out.findStream("value")).is_not_null()
	node.free()
