# fake_rendering_device.gd
# A RenderingDevice double for compute_kernel tests: there is no GPU headless,
# so RenderingServer.create_local_rendering_device() returns null there.
#
# It models the part of RenderingDevice that matters for cleanup:
# - uniform_set_create() makes the set depend on its shader and on every RID
#   bound in its uniforms; compute_pipeline_create() makes the pipeline depend
#   on its shader.
# - free_rid() frees every live dependent first (recursively), then the RID.
# - free_rid() on a RID that is not live is the engine's "Attempted to free
#   invalid ID" error; it is recorded as an "invalid_free" event instead.
# - RIDs still live when the device itself is freed are recorded as "leak".
#
# Every event goes to `events`, an Array the test keeps a reference to, so it
# can still be read after the node has called free() on the device.
extends Object

var events : Array
# "", "shader", "input_buffer", "output_buffer", "uniform_set" or "pipeline":
# that create call returns an invalid RID.
var fail_at : String = ""
var dispatched_groups : Vector3i = Vector3i.ZERO

var _next_id : int = 1000
var _live : Dictionary = {}		# int id -> { "kind": String, "deps": Array[int] }
var _data : Dictionary = {}		# int id -> PackedByteArray
var _buffers_created : int = 0
var _input_buffer_count : int = 0

func _init( p_events : Array, p_input_buffer_count : int = 1 ) -> void:
	events = p_events
	_input_buffer_count = p_input_buffer_count

func _make( kind : String, deps : Array = [] ) -> RID:
	_next_id += 1
	_live[_next_id] = { "kind": kind, "deps": deps }
	events.append( [ "create", kind, _next_id ] )
	return rid_from_int64( _next_id )

func kind_of( rid : RID ) -> String:
	return _live[rid.get_id()].kind if _live.has( rid.get_id() ) else ""

func is_live( rid : RID ) -> bool:
	return _live.has( rid.get_id() )

func live_count() -> int:
	return _live.size()

# --- RenderingDevice API used by compute_kernel.gd ---------------------------

func shader_compile_spirv_from_source( _src : RDShaderSource, _allow_cache : bool = true ) -> RDShaderSPIRV:
	return RDShaderSPIRV.new()

func shader_create_from_spirv( _spirv : RDShaderSPIRV, _name : String = "" ) -> RID:
	if fail_at == "shader":
		return RID()
	return _make( "shader" )

func storage_buffer_create( size : int, data : PackedByteArray = PackedByteArray(), _usage : int = 0, _bits : int = 0 ) -> RID:
	var is_input := _buffers_created < _input_buffer_count
	_buffers_created += 1
	if fail_at == "input_buffer" and is_input:
		return RID()
	if fail_at == "output_buffer" and not is_input:
		return RID()
	var rid := _make( "buffer" )
	var bytes := data.duplicate()
	bytes.resize( size )
	_data[rid.get_id()] = bytes
	return rid

func uniform_set_create( uniforms : Array, shader : RID, _set : int ) -> RID:
	if fail_at == "uniform_set":
		return RID()
	var deps : Array = [ shader.get_id() ]
	for u in uniforms:
		for id in u.get_ids():
			deps.append( id.get_id() )
	return _make( "uniform_set", deps )

func compute_pipeline_create( shader : RID, _constants : Array = [] ) -> RID:
	if fail_at == "pipeline":
		return RID()
	return _make( "pipeline", [ shader.get_id() ] )

func compute_list_begin() -> int:
	return 1

func compute_list_bind_compute_pipeline( _list : int, pipeline : RID ) -> void:
	events.append( [ "bind_pipeline", is_live( pipeline ) ] )

func compute_list_bind_uniform_set( _list : int, uniform_set : RID, _set : int ) -> void:
	events.append( [ "bind_uniform_set", is_live( uniform_set ) ] )

func compute_list_dispatch( _list : int, x : int, y : int, z : int ) -> void:
	dispatched_groups = Vector3i( x, y, z )

func compute_list_end() -> void:
	pass

func submit() -> void:
	pass

func sync() -> void:
	pass

func buffer_get_data( rid : RID, _offset : int = 0, _size : int = 0 ) -> PackedByteArray:
	return _data.get( rid.get_id(), PackedByteArray() )

func uniform_set_is_valid( rid : RID ) -> bool:
	return kind_of( rid ) == "uniform_set"

func compute_pipeline_is_valid( rid : RID ) -> bool:
	return kind_of( rid ) == "pipeline"

func free_rid( rid : RID ) -> void:
	var id := rid.get_id()
	if not _live.has( id ):
		events.append( [ "invalid_free", id ] )
		return
	_free_internal( id, false )

func _free_internal( id : int, cascaded : bool ) -> void:
	# Dependents go first, as RenderingDevice::_free_dependencies does.
	for other in _live.keys():
		if _live.has( other ) and id in _live[other].deps:
			_free_internal( other, true )
	var kind : String = _live[id].kind
	_live.erase( id )
	_data.erase( id )
	events.append( [ "cascade_free" if cascaded else "free", kind, id ] )

func _notification( what : int ) -> void:
	if what == NOTIFICATION_PREDELETE:
		for id in _live:
			events.append( [ "leak", _live[id].kind, id ] )
		events.append( [ "device_freed" ] )
