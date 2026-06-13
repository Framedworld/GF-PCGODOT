@tool
extends FlowNodeBase

# GPU execution escape hatch (PARITY_ROADMAP "GPU execution").
#
# Runs a user-supplied GLSL compute shader over the incoming point streams via a
# local RenderingDevice. This is the pragmatic equivalent of UE's "Custom HLSL"
# node, NOT a transparent node-graph-on-GPU. Declared input stream bindings are
# packed into storage buffers, one invocation is dispatched per point, and the
# declared output buffers are read back and registered as new streams on a
# duplicate of the input Data.
#
# Defensive contract: every RenderingDevice step is guarded. If the device can't
# be created, the shader fails to compile, or any binding is malformed, the node
# calls setError() with a clear message and passes the input through UNCHANGED
# (graceful fallback) so it never crashes the editor. See
# docs/_roadmap_notes/gpu_compute_kernel.md for the full contract.

func _init():
	meta_node = {
		"title" : "Compute Kernel",
		"settings" : ComputeKernelNodeSettings,
		"ins" : [{ "label": "In", "multiple_connections" : false }],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["Compute Shader", "GPU Kernel", "Custom HLSL"],
		"category" : "Utility",
		"tooltip" :
			"Runs a user-supplied GLSL compute shader over the point streams via RenderingDevice.\n" +
			"Declare input stream -> binding and binding -> output stream mappings in the settings.\n" +
			"Vector3 streams are packed as vec4 (x,y,z,0) by default. If the GPU is unavailable or\n" +
			"the shader fails to compile the input passes through unchanged (graceful fallback).",
	}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Passes the input through unchanged on output 0 and reports an error. Returns
# null so callers can `return _fallback(...)`.
func _fallback( in_data : FlowData.Data, msg : String ):
	if msg:
		setError( msg )
	set_output( 0, in_data )
	return null

# Parse "name:binding" -> { "name": String, "binding": int } or null.
func _parse_input_binding( entry : String ):
	var parts := entry.strip_edges().split( ":" )
	if parts.size() != 2:
		return null
	var name := parts[0].strip_edges()
	var binding_str := parts[1].strip_edges()
	if name.is_empty() or not binding_str.is_valid_int():
		return null
	return { "name": name, "binding": binding_str.to_int() }

# Parse "binding:name:type" -> { "binding": int, "name": String, "type": String }
# or null. type is normalised to "float" or "vec3".
func _parse_output_binding( entry : String ):
	var parts := entry.strip_edges().split( ":" )
	if parts.size() != 3:
		return null
	var binding_str := parts[0].strip_edges()
	var name := parts[1].strip_edges()
	var type_str := parts[2].strip_edges().to_lower()
	if not binding_str.is_valid_int() or name.is_empty():
		return null
	if type_str != "float" and type_str != "vec3":
		return null
	return { "binding": binding_str.to_int(), "name": name, "type": type_str }

# Pack a stream container into a PackedFloat32Array per the packing convention.
# Returns null on unsupported type. point_count is the canonical element count.
func _pack_stream( stream, point_count : int, packing : int ):
	var floats := PackedFloat32Array()
	match stream.data_type:
		FlowData.DataType.Float:
			var src : PackedFloat32Array = stream.container
			floats.resize( point_count )
			for i in point_count:
				floats[i] = src[ FlowData.bcast_idx( src.size(), i ) ]
		FlowData.DataType.Int:
			var srci : PackedInt32Array = stream.container
			floats.resize( point_count )
			for i in point_count:
				floats[i] = float( srci[ FlowData.bcast_idx( srci.size(), i ) ] )
		FlowData.DataType.Vector:
			var srcv : PackedVector3Array = stream.container
			if packing == ComputeKernelNodeSettings.eVec3Packing.VEC4_PADDED:
				floats.resize( point_count * 4 )
				for i in point_count:
					var v : Vector3 = srcv[ FlowData.bcast_idx( srcv.size(), i ) ]
					floats[i * 4 + 0] = v.x
					floats[i * 4 + 1] = v.y
					floats[i * 4 + 2] = v.z
					floats[i * 4 + 3] = 0.0
			else:
				floats.resize( point_count * 3 )
				for i in point_count:
					var v : Vector3 = srcv[ FlowData.bcast_idx( srcv.size(), i ) ]
					floats[i * 3 + 0] = v.x
					floats[i * 3 + 1] = v.y
					floats[i * 3 + 2] = v.z
		_:
			return null
	return floats

# ---------------------------------------------------------------------------
# Execute
# ---------------------------------------------------------------------------

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input( 0, ctx, "Input 'In'" )
	if in_data == null:
		return

	# Output is always a duplicate of the input so passthrough is well defined.
	var out_data : FlowData.Data = in_data.duplicate()
	var point_count := in_data.size()

	# Nothing to compute: emit the duplicate untouched.
	if point_count == 0:
		set_output( 0, out_data )
		return

	var packing : int = settings.vec3_packing
	var local_size_x : int = max( 1, settings.local_size_x )

	# --- Validate & collect input bindings ---------------------------------
	# Each: { binding:int, floats:PackedFloat32Array }
	var input_specs : Array = []
	for entry in settings.input_bindings:
		if entry.strip_edges().is_empty():
			continue
		var parsed = _parse_input_binding( entry )
		if parsed == null:
			return _fallback( out_data, "Malformed input binding '%s' (expected 'stream_name:binding_index')" % entry )
		var stream = in_data.findStream( parsed.name )
		if stream == null:
			return _fallback( out_data, "Input stream '%s' not found" % parsed.name )
		var floats = _pack_stream( stream, point_count, packing )
		if floats == null:
			return _fallback( out_data, "Input stream '%s' has unsupported type (only Float/Int/Vector3 can be packed)" % parsed.name )
		input_specs.append( { "binding": parsed.binding, "floats": floats } )

	# --- Validate & collect output bindings --------------------------------
	# Each: { binding:int, name:String, type:String, byte_size:int }
	var output_specs : Array = []
	for entry in settings.output_bindings:
		if entry.strip_edges().is_empty():
			continue
		var parsed = _parse_output_binding( entry )
		if parsed == null:
			return _fallback( out_data, "Malformed output binding '%s' (expected 'binding_index:stream_name:float|vec3')" % entry )
		var floats_per_point := 1
		if parsed.type == "vec3":
			floats_per_point = 4 if packing == ComputeKernelNodeSettings.eVec3Packing.VEC4_PADDED else 3
		parsed["byte_size"] = point_count * floats_per_point * 4
		output_specs.append( parsed )

	if output_specs.is_empty():
		return _fallback( out_data, "No valid output bindings declared; nothing to read back" )

	# --- Acquire the rendering device --------------------------------------
	var rd : RenderingDevice = RenderingServer.create_local_rendering_device()
	if rd == null:
		return _fallback( out_data, "create_local_rendering_device() returned null (no compute-capable GPU/driver). Input passed through unchanged." )

	# Track every RID we create so we can free them on any exit path.
	var rids : Array = []
	var result = _run_compute( rd, in_data, out_data, point_count, local_size_x, packing, input_specs, output_specs, rids )
	# Clean up GPU resources regardless of success/failure.
	for rid in rids:
		if rid != null and rid.is_valid():
			rd.free_rid( rid )
	rd.free()

	# _run_compute returns the populated out_data on success, or null after it
	# has already invoked _fallback().
	if result == null:
		return
	set_output( 0, out_data )

# Returns out_data on success, or null after calling _fallback() on failure.
func _run_compute( rd : RenderingDevice, in_data : FlowData.Data, out_data : FlowData.Data,
		point_count : int, local_size_x : int, packing : int,
		input_specs : Array, output_specs : Array, rids : Array ):

	# --- Compile shader ----------------------------------------------------
	var shader_rid : RID = _create_shader( rd )
	if shader_rid == null or not shader_rid.is_valid():
		# _create_shader already reported via setError; do passthrough.
		return _fallback( out_data, "" )
	rids.append( shader_rid )

	# --- Create buffers + uniforms -----------------------------------------
	var uniforms : Array = []

	for spec in input_specs:
		var bytes : PackedByteArray = spec.floats.to_byte_array()
		# storage_buffer_create rejects zero-size; guard it.
		if bytes.size() == 0:
			bytes.resize( 4 )
		var buf : RID = rd.storage_buffer_create( bytes.size(), bytes )
		if not buf.is_valid():
			return _fallback( out_data, "Failed to create input storage buffer at binding %d" % spec.binding )
		rids.append( buf )
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u.binding = spec.binding
		u.add_id( buf )
		uniforms.append( u )

	# Output buffers (zero-initialised).
	for spec in output_specs:
		var size : int = max( 4, spec.byte_size )
		var zeros := PackedByteArray()
		zeros.resize( size )
		var buf : RID = rd.storage_buffer_create( size, zeros )
		if not buf.is_valid():
			return _fallback( out_data, "Failed to create output storage buffer at binding %d" % spec.binding )
		spec["rid"] = buf
		rids.append( buf )
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u.binding = spec.binding
		u.add_id( buf )
		uniforms.append( u )

	# Optional point_count params buffer.
	if settings.bind_point_count:
		var pc := PackedInt32Array( [ point_count ] )
		var pc_bytes : PackedByteArray = pc.to_byte_array()
		var buf : RID = rd.storage_buffer_create( pc_bytes.size(), pc_bytes )
		if not buf.is_valid():
			return _fallback( out_data, "Failed to create point_count params buffer at binding %d" % settings.point_count_binding )
		rids.append( buf )
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u.binding = settings.point_count_binding
		u.add_id( buf )
		uniforms.append( u )

	# --- Uniform set + pipeline --------------------------------------------
	var uniform_set : RID = rd.uniform_set_create( uniforms, shader_rid, 0 )
	if not uniform_set.is_valid():
		return _fallback( out_data, "uniform_set_create failed (check binding indices match the shader's set=0 layout)" )
	rids.append( uniform_set )

	var pipeline : RID = rd.compute_pipeline_create( shader_rid )
	if not pipeline.is_valid():
		return _fallback( out_data, "compute_pipeline_create failed" )
	rids.append( pipeline )

	# --- Dispatch ----------------------------------------------------------
	var groups_x : int = int( ceil( float( point_count ) / float( local_size_x ) ) )
	groups_x = max( 1, groups_x )

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline( compute_list, pipeline )
	rd.compute_list_bind_uniform_set( compute_list, uniform_set, 0 )
	rd.compute_list_dispatch( compute_list, groups_x, 1, 1 )
	rd.compute_list_end()

	rd.submit()
	rd.sync()

	# --- Read back ---------------------------------------------------------
	for spec in output_specs:
		var out_bytes : PackedByteArray = rd.buffer_get_data( spec.rid )
		var out_floats : PackedFloat32Array = out_bytes.to_float32_array()
		if spec.type == "float":
			var fc := PackedFloat32Array()
			fc.resize( point_count )
			for i in point_count:
				fc[i] = out_floats[i] if i < out_floats.size() else 0.0
			var err = out_data.registerStream( spec.name, fc, FlowData.DataType.Float )
			if err:
				return _fallback( out_data, "registerStream('%s') failed: %s" % [ spec.name, err ] )
		else: # vec3
			var stride := 4 if packing == ComputeKernelNodeSettings.eVec3Packing.VEC4_PADDED else 3
			var vc := PackedVector3Array()
			vc.resize( point_count )
			for i in point_count:
				var base : int = i * stride
				var x : float = out_floats[ base + 0 ] if base + 0 < out_floats.size() else 0.0
				var y : float = out_floats[ base + 1 ] if base + 1 < out_floats.size() else 0.0
				var z : float = out_floats[ base + 2 ] if base + 2 < out_floats.size() else 0.0
				vc[i] = Vector3( x, y, z )
			var err = out_data.registerStream( spec.name, vc, FlowData.DataType.Vector )
			if err:
				return _fallback( out_data, "registerStream('%s') failed: %s" % [ spec.name, err ] )

	return out_data

# Compiles the shader from inline source or a .glsl RDShaderFile. Reports errors
# via setError and returns an invalid RID on any failure.
func _create_shader( rd : RenderingDevice ) -> RID:
	var spirv : RDShaderSPIRV = null

	if settings.shader_mode == ComputeKernelNodeSettings.eShaderMode.FILE:
		var path : String = settings.shader_file_path
		if path.is_empty() or not ResourceLoader.exists( path ):
			setError( "Shader file path '%s' is empty or does not exist" % path )
			return RID()
		var shader_file = load( path )
		if shader_file == null or not (shader_file is RDShaderFile):
			setError( "Resource at '%s' is not a RDShaderFile (.glsl)" % path )
			return RID()
		spirv = shader_file.get_spirv()
		if spirv == null:
			setError( "Failed to get SPIR-V from '%s'" % path )
			return RID()
		var file_err : String = spirv.get_stage_compile_error( RenderingDevice.SHADER_STAGE_COMPUTE )
		if file_err and not file_err.is_empty():
			setError( "Compute shader compile error in '%s': %s" % [ path, file_err ] )
			return RID()
	else:
		var src : String = settings.shader_source
		if src.strip_edges().is_empty():
			setError( "Inline shader source is empty" )
			return RID()
		var shader_source := RDShaderSource.new()
		shader_source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
		shader_source.source_compute = src
		spirv = rd.shader_compile_spirv_from_source( shader_source )
		if spirv == null:
			setError( "Shader compilation returned null SPIR-V" )
			return RID()
		var compile_err : String = spirv.get_stage_compile_error( RenderingDevice.SHADER_STAGE_COMPUTE )
		if compile_err and not compile_err.is_empty():
			setError( "Compute shader compile error: %s" % compile_err )
			return RID()

	var shader_rid : RID = rd.shader_create_from_spirv( spirv )
	if not shader_rid.is_valid():
		setError( "shader_create_from_spirv failed (invalid shader)" )
		return RID()
	return shader_rid
