# data_selector_translation_test.gd
# Pins FlowData.Data.findStream after the WP13-P1 change that skips
# translateStreamName and split(".") for names they would return unchanged
# (registerStream, which keeps its original selector handling, is pinned with
# it). The functions below carry the two methods exactly as they were before
# (base d5bd9b6, only qualified for use outside FlowData); every selector form
# (plain, "@last", Yaw/Pitch/Roll, "$" aliases, components, "@data.",
# front/up/right, index, malformed) must give the same result, the same Data
# and the same logged messages.
class_name DataSelectorTranslationTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const FDS = preload("res://addons/flow_nodes_editor/flow_data.gd")
const R = preload("res://tests/nodes/support/reference_compare.gd")

const T := FlowDataScript.DataType

# The previous bodies, as static functions of the Data `d` (a subclass of the
# inner Data class in a test script confuses the GDScript analyzer for other
# scripts, so they are not methods).
static func ref_findStream( d, name : String ):
	# Per-data attribute selector (UE @Data). "@data.<attr>" returns a
	# synthetic length-1 broadcast stream sourced from d.data_attrs, so the
	# value reads as a constant for every point under the broadcast rules.
	if name.length() > FDS.DataAttrPrefix.length() and name.begins_with( FDS.DataAttrPrefix ):
		var attr_name := name.substr( FDS.DataAttrPrefix.length() )
		var rec = d.data_attrs.get( attr_name, null )
		if rec == null:
			return null
		var bcast = FDS.Data.newContainerOfType( rec.data_type )
		if bcast == null:
			return null
		bcast.resize( 1 )
		FDS.Data.writeValue( bcast, 0, rec.value, rec.data_type )
		return {
			"data_type" : rec.data_type,
			"container" : bcast,
			"name" : name
		}

	name = d.translateStreamName( name )

	var name_lower := name.to_lower()
	if name_lower == "front" or name_lower == "up" or name_lower == "right":
		var rot_stream = d.streams.get(FDS.AttrRotation, null)
		if rot_stream != null:
			var eulers = rot_stream.container
			var new_container := PackedVector3Array()
			new_container.resize(eulers.size())
			for idx in range(eulers.size()):
				var basis := FDS.eulerToBasis(eulers[idx])
				match name_lower:
					"front":
						new_container[idx] = -basis.z
					"up":
						new_container[idx] = basis.y
					"right":
						new_container[idx] = basis.x
			return {
				"data_type": FDS.DataType.Vector,
				"container": new_container,
				"name": name
			}
		return null
	
	if name == "index":
		var new_container = PackedInt32Array()
		new_container.resize( d.size() )
		for idx in range( new_container.size() ):
			new_container[idx] = idx
		return {
			"data_type" : FDS.DataType.Int,
			"container" : new_container,
			"name" : "Index"
		}
		
	var parts = name.split( "." )
	if parts.size() == 2:
		#print( "findStream(%s) => %s (Streams:%s)" % [ name, parts, d.streams])
		var s0 = ref_findStream( d, parts[0] )
		if s0 == null:
			push_error( "Failed to find stream root %s" % parts[0] )
			return null
		#print( "searching (%s) in %s" % [ parts[1], s0])
		return d.getSubStream( s0, parts[1] )
	elif parts.size() > 2:
		return null
	return d.streams.get( name, null )

static func ref_registerStream( d, name : String, container, data_type : int = FDS.DataType.Invalid ):
	if not name:
		print( "registerStream empty name!. Container size:", container.size() )
		push_error("registerStream name can't be empty of data_type %d" % [ data_type ] )
		return null
	if container == null:
		push_error("registerStream. Can't register a null container with name %s" %  name )
		return null
	# Per-data attribute selector (UE @Data). "@data.<attr>" writes into
	# d.data_attrs instead of creating a per-point stream. The container is
	# read as a broadcast: element 0 (if any) is stored as the data value.
	if name.length() > FDS.DataAttrPrefix.length() and name.begins_with( FDS.DataAttrPrefix ):
		var attr_name := name.substr( FDS.DataAttrPrefix.length() )
		if data_type == FDS.DataType.Invalid:
			data_type = FDS.Data._inferContainerType( container )
		if data_type == FDS.DataType.Invalid:
			return "Invalid container type"
		if container.size() > 1:
			# Semantics unchanged this round (element 0 wins), but a
			# multi-element write is almost always a bug upstream.
			push_warning( "registerStream('%s'): per-data attribute got %d elements; only element 0 is kept" % [ name, container.size() ] )
		var value = container[0] if container.size() > 0 else null
		d.data_attrs[ attr_name ] = { "value" : value, "data_type" : data_type }
		d.last_added_stream_name = name
		return null
	name = d.translateStreamName( name )
	var parts = name.split( "." )
	if parts.size() == 2:
		var s0 = d.streams.get( parts[0], null )
		if s0 == null:
			return "Failed to find stream %s" % parts[0] 
		return d.setSubStream( s0, parts[1], container )
	elif parts.size() > 2:
		return "Too many '.' in stream name"
	else:
		if data_type == FDS.DataType.Invalid:
			data_type = FDS.Data._inferContainerType( container )

		if data_type == FDS.DataType.Invalid:
			print( "Invalid data type ", name, " Container:", container)
			return "Invalid container type"

		# Canonical attributes have one fixed type (CANONICAL_ATTRIBUTE_TYPES).
		var canonical_error := FDS.canonical_type_error( name, data_type )
		if canonical_error != "":
			push_error( "registerStream: " + canonical_error )
			return canonical_error

		# A container that is not the declared type's storage is refused when
		# either side is an extended type (Vector2, Vector4, Transform, Int64,
		# Double), so a mistyped stream fails here instead of downstream.
		if not FDS.Data.containerMatchesType( container, data_type ):
			var mismatch := "registerStream: '%s' declared %s but the container is a %s; registration refused" % [
				name, FDS._data_type_label( data_type ), type_string( typeof( container ) ) ]
			if FDS.Data.isExtendedType( data_type ) or FDS.Data.isExtendedType( FDS.Data._inferContainerType( container ) ):
				push_error( mismatch )
				return mismatch
			# Historical types keep registering (third-party nodes may rely on
			# it) but no longer silently.
			push_warning( mismatch.replace( "; registration refused", "" ) )

		if d.streams.has(name) and d.streams[name].data_type != data_type:
			push_warning("Stream name conflict: '%s' already exists with data_type %d, overwriting with data_type %d" % [name, d.streams[name].data_type, data_type])

		# Stream-length invariant (engine-hardening). Once a Data carries
		# points, every per-point stream must be either d.size()==point count
		# or a length-1 broadcast. A registration of any other non-empty
		# length silently corrupts downstream per-point reads, so warn
		# clearly. We measure against the established point count d.size()
		# (which ignores the stream being (re)written when it replaces an
		# existing one). Exempt: empty containers (register-empty-then-fill
		# idiom) and broadcast (size 1). Warn-only — never hard-error — to
		# avoid breaking legitimate mid-construction build-up idioms.
		var point_count : int = d.size()
		if point_count > 0 and container.size() > 1 and container.size() != point_count:
			# d.size() can equal the stream being overwritten; recompute the
			# point count from the *other* d.streams so an overwrite of the
			# very first stream doesn't false-positive against itself.
			var other_count := 0
			for existing_name in d.streams:
				if existing_name == name:
					continue
				var existing_size : int = d.streams[existing_name].container.size()
				if existing_size > 1:
					other_count = existing_size
					break
			if other_count > 0 and container.size() != other_count:
				push_warning("registerStream: stream '%s' has %d elements but this Data holds %d points — per-point streams must match the point count or be length 1 (broadcast). Downstream per-point reads may be corrupted." % [name, container.size(), other_count])

		d.streams[ name ] = {
			"container" : container,
			"name" : name,
			"data_type" : data_type
		}
	d.last_added_stream_name = name
	#print( "Registered stream %s : %s " % [ name, d.streams[ name ] ])
	return null


const NAMES := ["density", "k", "@last", "Yaw", "Pitch", "Roll", "yaw", "$Density", "$density", "$Position.X",
	"$Scale", "$Nope", "$", "position.x", "position.W", "size.y.z", "a.", ".b", "@data.level", "@data.", "@data",
	"Front", "up", "RIGHT", "index", "Index", "", "missing.x", "rotation.z", "$Color", "$Index"]

static func _fill(d : FlowData.Data) -> FlowData.Data:
	d.addCommonStreams(3)
	d.registerStream("density", PackedFloat32Array([0.1, 0.5, 0.9]), T.Float)
	d.getVector3Container("rotation")[1] = Vector3(10, 20, 30)
	d.set_data_attr("level", 2)
	return d

static func _value_bytes(v) -> PackedByteArray:
	if v is Dictionary:
		return var_to_bytes(var_to_str(v))
	return var_to_bytes(v)

func _logged(fn : Callable) -> Array:
	var logger := R.CaptureLogger.new()
	OS.add_logger(logger)
	var result = fn.call()
	OS.remove_logger(logger)
	R.clear_gdunit_script_errors()
	return [_value_bytes(result), logger.messages]

func test_find_stream_matches_the_previous_implementation() -> void:
	var ref := _fill(FlowDataScript.Data.new())
	var cur := _fill(FlowDataScript.Data.new())
	for name in NAMES:
		var expected := _logged(func(): return ref_findStream(ref, name))
		var actual := _logged(func(): return cur.findStream(name))
		assert_array(actual).override_failure_message("findStream('%s') differs" % name).is_equal(expected)

func test_register_stream_matches_the_previous_implementation() -> void:
	var containers := [PackedFloat32Array([1, 2, 3]), PackedFloat32Array([7]), PackedVector3Array([Vector3.ONE, Vector3.ONE, Vector3.ONE]),
		PackedInt32Array([1, 2]), PackedFloat64Array([1, 2, 3])]
	for name in NAMES:
		for container in containers:
			for data_type in [T.Invalid, T.Float, T.Vector, T.Double]:
				var ref := _fill(FlowDataScript.Data.new())
				var cur := _fill(FlowDataScript.Data.new())
				var expected := _logged(func(): return ref_registerStream(ref, name, container.duplicate(), data_type))
				var actual := _logged(func(): return cur.registerStream(name, container.duplicate(), data_type))
				expected.append(R.data_bytes(ref))
				actual.append(R.data_bytes(cur))
				assert_array(actual).override_failure_message("registerStream('%s', %s, %d) differs" % [name, type_string(typeof(container)), data_type]).is_equal(expected)
