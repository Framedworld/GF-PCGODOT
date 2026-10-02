@tool
extends FlowNodeBase

const LoadPCGDataAssetSettings = preload("res://addons/flow_nodes_editor/nodes/load_pcg_data_asset_settings.gd")

func _init():
	meta_node = {
		"title" : "Load PCG Data Asset",
		"settings" : LoadPCGDataAssetSettings,
		"ins" : [],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["Load PCG Data Asset"],
		"category" : "Input",
		"tooltip" : "Loads JSON or Resource-backed PCG point/attribute data into FlowData streams.\nNote: JSON numbers always parse as floats, so numeric JSON columns become Float streams (never Int).\nParsed JSON is cached per path + file modification time; a changed file is re-read automatically.",
	}

# Parsed-JSON cache shared by every Load PCG Data Asset node. Keyed by the
# resolved path, the file's modified time and every setting that changes the
# parsed result, so an edited file (new mtime) or a settings change misses.
# Callers always receive a duplicate(), never the cached instance.
const MAX_CACHE_ENTRIES := 32
static var _cache : Dictionary = {}
## Number of JSON parses actually performed (cache misses). Test/diagnostic aid.
static var parse_count : int = 0
## Number of evaluations served from the cache. Test/diagnostic aid.
static var cache_hits : int = 0
# Guards _cache and the counters: FlowExecutor's threaded mode may run several
# of these nodes at once (docs/PARITY_ROUND2.md WP1).
static var _cache_mutex := Mutex.new()

## Drops every cached parse result (and resets the diagnostic counters).
static func clear_cache() -> void:
	_cache_mutex.lock()
	_cache.clear()
	parse_count = 0
	cache_hits = 0
	_cache_mutex.unlock()

func _as_vector3(value) -> Dictionary:
	if value is Vector3:
		return { "ok": true, "value": value }
	if value is Array and value.size() >= 3:
		return { "ok": true, "value": Vector3(float(value[0]), float(value[1]), float(value[2])) }
	if value is Dictionary and value.has("x") and value.has("y") and value.has("z"):
		return { "ok": true, "value": Vector3(float(value.x), float(value.y), float(value.z)) }
	if value is String:
		var text := String(value).strip_edges()
		if text.begins_with("(") and text.ends_with(")"):
			text = text.substr(1, text.length() - 2)
		text = text.replace(",", " ").replace(";", " ").replace("|", " ")
		var parts := text.split(" ", false)
		if parts.size() == 3 and String(parts[0]).is_valid_float() and String(parts[1]).is_valid_float() and String(parts[2]).is_valid_float():
			return { "ok": true, "value": Vector3(float(parts[0]), float(parts[1]), float(parts[2])) }
	return { "ok": false, "value": Vector3.ZERO }

func _infer_variant_type(values : Array) -> int:
	var can_bool := true
	var can_int := true
	var can_float := true
	var can_vector := true
	for value in values:
		if value == null:
			continue
		var t := typeof(value)
		if can_bool and t != TYPE_BOOL:
			can_bool = false
		if can_int and t != TYPE_INT:
			can_int = false
		if can_float and t != TYPE_INT and t != TYPE_FLOAT:
			can_float = false
		# The Vector3 probe (string strip/replace/split) is the expensive one:
		# only run it while Vector is still a candidate.
		if can_vector and not _as_vector3(value).ok:
			can_vector = false
		if not (can_bool or can_int or can_float or can_vector):
			break
	if can_bool:
		return FlowData.DataType.Bool
	if can_int:
		return FlowData.DataType.Int
	if can_float:
		return FlowData.DataType.Float
	if can_vector:
		return FlowData.DataType.Vector
	return FlowData.DataType.String

func _register_variant_column(out : FlowData.Data, name : String, values : Array) -> void:
	var data_type := _infer_variant_type(values)
	match data_type:
		FlowData.DataType.Bool:
			var c := PackedByteArray()
			c.resize(values.size())
			for i in range(values.size()):
				c[i] = 1 if bool(values[i]) else 0
			out.registerStream(name, c, FlowData.DataType.Bool)
		FlowData.DataType.Int:
			var c := PackedInt32Array()
			c.resize(values.size())
			for i in range(values.size()):
				c[i] = int(values[i]) if values[i] != null else 0
			out.registerStream(name, c, FlowData.DataType.Int)
		FlowData.DataType.Float:
			var c := PackedFloat32Array()
			c.resize(values.size())
			for i in range(values.size()):
				c[i] = float(values[i]) if values[i] != null else 0.0
			out.registerStream(name, c, FlowData.DataType.Float)
		FlowData.DataType.Vector:
			var c := PackedVector3Array()
			c.resize(values.size())
			for i in range(values.size()):
				c[i] = _as_vector3(values[i]).value
			out.registerStream(name, c, FlowData.DataType.Vector)
		_:
			var c := PackedStringArray()
			c.resize(values.size())
			for i in range(values.size()):
				c[i] = "" if values[i] == null else str(values[i])
			out.registerStream(name, c, FlowData.DataType.String)

func _rows_to_data(rows : Array, source_path : String) -> FlowData.Data:
	var headers : Array[String] = []
	var seen := {}
	for row in rows:
		if row is Dictionary:
			for key in row.keys():
				var name := String(key)
				if not seen.has(name):
					seen[name] = true
					headers.append(name)

	var out := FlowData.Data.new()
	for header in headers:
		var values : Array = []
		values.resize(rows.size())
		for i in range(rows.size()):
			var row = rows[i]
			values[i] = row.get(header, null) if row is Dictionary else null
		_register_variant_column(out, header, values)

	if settings.add_source_path and settings.source_path_attribute.strip_edges() != "":
		var paths := PackedStringArray()
		paths.resize(rows.size())
		for i in range(rows.size()):
			paths[i] = source_path
		out.registerStream(settings.source_path_attribute, paths, FlowData.DataType.String)
	return out

func _streams_to_data(streams : Dictionary, source_path : String) -> FlowData.Data:
	var out := FlowData.Data.new()
	var size := 0
	for name in streams.keys():
		var values = streams[name]
		if values is Array:
			size = maxi(size, values.size())
	for name in streams.keys():
		var values = streams[name]
		if not values is Array:
			continue
		var column : Array = values.duplicate()
		column.resize(size)
		_register_variant_column(out, String(name), column)
	if settings.add_source_path and settings.source_path_attribute.strip_edges() != "":
		var paths := PackedStringArray()
		paths.resize(size)
		for i in range(size):
			paths[i] = source_path
		out.registerStream(settings.source_path_attribute, paths, FlowData.DataType.String)
	return out

func _parse_json_asset(path : String) -> FlowData.Data:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		setError("Failed to parse JSON PCG data asset '%s'" % path)
		return null
	if parsed is Array:
		return _rows_to_data(parsed, path)
	if parsed is Dictionary:
		if parsed.has(settings.streams_property_name) and parsed[settings.streams_property_name] is Dictionary:
			return _streams_to_data(parsed[settings.streams_property_name], path)
		if parsed.has(settings.rows_property_name) and parsed[settings.rows_property_name] is Array:
			return _rows_to_data(parsed[settings.rows_property_name], path)
		if parsed.has("points") and parsed.points is Array:
			return _rows_to_data(parsed.points, path)
		return _rows_to_data([parsed], path)
	setError("Unsupported JSON shape in '%s'" % path)
	return null

func _parse_resource_asset(path : String) -> FlowData.Data:
	var res = load(path)
	if res == null:
		setError("Failed to load Resource PCG data asset '%s'" % path)
		return null
	var streams = res.get(settings.streams_property_name)
	if streams is Dictionary:
		return _streams_to_data(streams, path)
	var rows = res.get(settings.rows_property_name)
	if rows is Array:
		return _rows_to_data(rows, path)
	var points = res.get("points")
	if points is Array:
		return _rows_to_data(points, path)
	setError("Resource '%s' does not expose '%s', '%s', or 'points'" % [path, settings.streams_property_name, settings.rows_property_name])
	return null

## "path|mtime|length" identifying one on-disk revision of the file. mtime
## has 1 s resolution on most filesystems; the byte length guards the common
## "rewritten within the same second" case at the cost of an open().
func _file_revision(path : String) -> String:
	var length := -1
	var f := FileAccess.open(path, FileAccess.READ)
	if f != null:
		length = f.get_length()
		f.close()
	return "%s|%d|%d" % [path, FileAccess.get_modified_time(path), length]

func _parse_json_asset_cached(path : String, format : int) -> FlowData.Data:
	var revision := _file_revision(path)
	var key := "%s|%d|%s|%s|%s|%s" % [
		revision, format,
		settings.rows_property_name, settings.streams_property_name,
		str(settings.add_source_path), settings.source_path_attribute,
	]
	_cache_mutex.lock()
	var cached = _cache.get(key, null)
	if cached != null:
		cache_hits += 1
		_cache_mutex.unlock()
		return cached.duplicate()
	parse_count += 1
	_cache_mutex.unlock()
	var parsed := _parse_json_asset(path)
	if parsed == null:
		return null
	_cache_mutex.lock()
	if _cache.size() >= MAX_CACHE_ENTRIES:
		_cache.clear()
	# Drop stale entries of the same path (older mtime/length) so edits don't
	# pile up; entries for the same file revision but other settings are kept.
	var path_prefix := path + "|"
	var revision_prefix := revision + "|"
	for k in _cache.keys():
		var ks := String(k)
		if ks.begins_with(path_prefix) and not ks.begins_with(revision_prefix):
			_cache.erase(k)
	_cache[key] = parsed
	_cache_mutex.unlock()
	return parsed.duplicate()

func execute(ctx : FlowData.EvaluationContext):
	var path : String = str(getSettingValue(ctx, "asset_path", "")).strip_edges()
	if path == "":
		set_output(0, FlowData.Data.new())
		return
	if not FileAccess.file_exists(path):
		setError("PCG data asset path '%s' was not found" % path)
		return

	var format = settings.asset_format
	if format == LoadPCGDataAssetSettings.eAssetFormat.Auto:
		var ext := path.get_extension().to_lower()
		format = LoadPCGDataAssetSettings.eAssetFormat.Json if ext == "json" else LoadPCGDataAssetSettings.eAssetFormat.Resource

	var out : FlowData.Data = null
	if format == LoadPCGDataAssetSettings.eAssetFormat.Json:
		out = _parse_json_asset_cached(path, format)
	else:
		out = _parse_resource_asset(path)
	if out == null:
		return
	set_output(0, out)
