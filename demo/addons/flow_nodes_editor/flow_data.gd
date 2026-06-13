extends Object
class_name FlowData

# Defines the DataTypes and Data class that is passed between nodes
# A FlowData.Data is basically a dict of streams, where each stream is:
#   Container: Continuous typed array of the actual data stored
#   data_type
#   name
# The storage is column oriented, not row oriented

enum DataType {
	Bool,
	Int,
	Float,
	Vector,
	String,
	Resource,
	NodeMesh,
	NodePath,
	Color,
	Invalid = 999
}

const AttrPosition : StringName = &"position"
const AttrRotation : StringName = &"rotation"
const AttrSize     : StringName = &"size"
const AttrDensity  : StringName = &"density"	# Float, 0..1, soft existence probability (UE $Density)
const AttrSeed     : StringName = &"seed"		# Int, per-point deterministic seed (UE $Seed)
const AttrNormal   : StringName = &"normal"		# Vector, surface normal where known

class EvaluationContext:
	var owner : FlowGraphNode3D
	var eval_id : int = 0
	var graph : FlowGraphResource
	var gedit_nodes_by_name : Dictionary
	var runtime_params : Dictionary = {}
	var variables : Dictionary = {}

## Deterministic per-point seed (UE $Seed parity): hashes the position
## quantized per component at *1000 (the same quantization mutate_seed.gd
## uses, so both produce agreeing values) combined with the node seed.
## Result is masked to a positive 31-bit int so it fits a PackedInt32Array.
static func point_seed( pos : Vector3, node_seed : int ) -> int:
	var px = int(round(pos.x * 1000.0))
	var py = int(round(pos.y * 1000.0))
	var pz = int(round(pos.z * 1000.0))
	return hash([px, py, pz, node_seed]) & 0x7fffffff

## Broadcast convention: a stream whose container holds a single element is a
## "broadcast" stream — that one value applies to every point. Streams with
## more than one element are read per point. Use this helper to compute the
## read index into a container that may be broadcast.
static func bcast_idx( container_size : int, i : int ) -> int:
	return i if container_size > 1 else 0

## Build a stable orthonormal Basis from a surface normal.
## - `normal` is the axis you want to align (default aligns to +Z).
## - `up` is your preferred up; a safe fallback is chosen if nearly parallel.
## - `axis` can be "z" (default), "y", or "x" for which axis the normal should align to.
static func basisFromNormal(normal: Vector3, up: Vector3 = Vector3.UP, axis: String = "z") -> Basis:
	var n := normal.normalized()
	if n.length() == 0.0 or not n.is_finite():
		return Basis.IDENTITY

	# Pick a safe up if nearly parallel to n
	var safe_up := up
	if abs(n.dot(safe_up)) > 0.999: # ~parallel
		# pick the axis least aligned with n
		safe_up = Vector3.UP if (abs(n.y) < 0.9) else Vector3.RIGHT

	# Build tangent/bitangent
	var t := safe_up.cross(n).normalized()    # tangent
	var b := n.cross(t)                       # bitangent; already unit-length if t,n are

	var basis: Basis
	match axis:
		"x":
			basis = Basis(n, t, b)            # X=n, Y=t, Z=b
		"y":
			basis = Basis(t, n, b)            # X=t, Y=n, Z=b
		_:
			basis = Basis(t, b, n)            # X=t, Y=b, Z=n (default: Z=n)

	return basis.orthonormalized()

# basis.get_euler() * 180.0 / PI		# <-- This is much faster
static func basisToEuler( basis : Basis ) -> Vector3:
	var euler = basis.get_euler()
	euler.x = rad_to_deg( euler.x )
	euler.y = rad_to_deg( euler.y )
	euler.z = rad_to_deg( euler.z )
	return euler

static func eulerToBasis( euler : Vector3) -> Basis:
	euler.x = deg_to_rad( euler.x )
	euler.y = deg_to_rad( euler.y )
	euler.z = deg_to_rad( euler.z )
	return Basis.from_euler( euler )

# A wrapper around the Position/Rotation/Scale streams
class TransformsStream:
	var positions : PackedVector3Array
	var eulers : PackedVector3Array
	var sizes : PackedVector3Array
	func atIndex( id: int ) -> Transform3D:
		var basis := FlowData.eulerToBasis( eulers[id] )
		return Transform3D( basis.scaled( sizes[id] ), positions[id] )
	
	func atIndexAbsScale( id: int, scale: float ) -> Transform3D:
		var basis := FlowData.eulerToBasis( eulers[id] )
		return Transform3D( basis.scaled( Vector3.ONE * scale ), positions[id] )

	func size() -> int:
		return positions.size()

# The basic information that is passed between nodes
class Data:
	var streams : Dictionary = {}
	var last_added_stream_name : String
	var tags : PackedStringArray = PackedStringArray()


	static func newContainerOfType( data_type : DataType ):
		match data_type:
			DataType.Bool:
				return PackedByteArray()
			DataType.Int:
				return PackedInt32Array()
			DataType.Float:
				return PackedFloat32Array()
			DataType.Vector:
				return PackedVector3Array()
			DataType.String:
				return PackedStringArray()
			DataType.Resource:
				return Array([], TYPE_OBJECT, "Resource", null)
			DataType.NodeMesh:
				return Array([], TYPE_OBJECT, "Node", null)
			DataType.NodePath:
				return Array([], TYPE_OBJECT, "Node", null)
			DataType.Color:
				return PackedColorArray()
			_:
				push_error( "newContainerOfType(%d) type not supported" % [ data_type ])
		return null

	static func writeValue( container, index : int, value, data_type : DataType ) -> void:
		match data_type:
			DataType.Bool:
				var typed_container : PackedByteArray = container
				typed_container[index] = 1 if bool(value) else 0
			DataType.Int:
				var typed_container : PackedInt32Array = container
				typed_container[index] = int(value)
			DataType.Float:
				var typed_container : PackedFloat32Array = container
				typed_container[index] = float(value)
			DataType.Vector:
				var typed_container : PackedVector3Array = container
				typed_container[index] = value
			DataType.String:
				var typed_container : PackedStringArray = container
				typed_container[index] = str(value)
			DataType.Resource:
				var typed_container : Array = container
				typed_container[index] = value
			DataType.NodeMesh:
				var typed_container : Array = container
				typed_container[index] = value
			DataType.NodePath:
				var typed_container : Array = container
				typed_container[index] = value
			DataType.Color:
				var typed_container : PackedColorArray = container
				typed_container[index] = value
			_:
				push_error( "writeValue(%d) type not supported" % [ data_type ])
	
	func numFields() -> int:
		return streams.size()
		
	func size() -> int:
		if streams.size() == 0:
			return 0
		var key0 = streams.keys()[0]
		return streams[ key0 ].container.size()
	
	func hasStream( name : StringName ) -> bool:
		return streams.has( name )
		
	func hasStreamOfType( name : StringName, data_type : DataType ) -> bool:
		return streams.has( name ) and streams[ name ].data_type == data_type
	
	func getContainerChecked( name : String, data_type : DataType ):
		var stream = streams.get( name, null )
		if stream and stream.data_type == data_type:
			return stream.container
		return null
		
	# converts 'Yaw' into "Rotation.Y" 
	func translateStreamName( name : String ):
		if name == "@last":
			if not last_added_stream_name:
				push_error( "@last is not valid" )
			return last_added_stream_name
		if name == "Yaw":
			return "%s.Y" % FlowData.AttrRotation
		if name == "Pitch":
			return "%s.X" % FlowData.AttrRotation
		if name == "Roll":
			return "%s.Z" % FlowData.AttrRotation
		return name
		
	func getSubStreamIndex(  sub_comp : String ):
		var sc_up = sub_comp.to_upper()
		if sc_up == "X" or sc_up == "R":
			return 0
		elif sc_up == "Y" or sc_up == "G":
			return 1
		elif sc_up == "Z" or sc_up == "B":
			return 2
		elif sc_up == "W" or sc_up == "A":
			return 3
		return -1
	
	func getSubStream( stream : Dictionary, sub_comp : String ):
		var subcomp_idx = getSubStreamIndex( sub_comp )
		if subcomp_idx == -1:
			push_error( "Invalid sub_stream name %s" % sub_comp )
			return null
		if stream.data_type != DataType.Vector and stream.data_type != DataType.Color:
			push_error( "getSubStream.Parent stream must be of type Vector or Color" )
			return null
		if stream.data_type == DataType.Vector and subcomp_idx == 3:
			push_error( "Vector parent does not support W/A component" )
			return null
		var big_container = stream.container
		var new_container = PackedFloat32Array()
		new_container.resize( big_container.size() )
		for idx in range( big_container.size() ):
			new_container[idx] = big_container[idx][ subcomp_idx ]
		return {
			"data_type" : DataType.Float,
			"container" : new_container,
			"name" : "%s.%s" % [ stream.name, sub_comp ]
		}
		
	func setSubStream( stream : Dictionary, sub_comp : String, sub_container  ):
		var subcomp_idx = getSubStreamIndex( sub_comp )
		if subcomp_idx == -1:
			return "Invalid sub stream name %s" % sub_comp
		if stream.data_type != DataType.Vector and stream.data_type != DataType.Color:
			return "setSubStream.Parent stream must be of type Vector or Color"
		if stream.data_type == DataType.Vector and subcomp_idx == 3:
			return "Vector parent does not support W/A component"
		var big_container = stream.container
		if sub_container.size() != big_container.size():
			return "Container sizes do not match (%d vs %d)" % [sub_container.size(), big_container.size()]
		#print( "big_container %s[%d] << %s" % [ big_container, subcomp_idx, sub_container ])
		# Because we are mutating the container (part of it), we need to create
		# a new copy of the original and insert it as the new current container
		# Fixes bug expresion updating position.y and refreshing
		big_container = big_container.duplicate()
		for idx in range( big_container.size() ):
			var item = big_container[idx]
			item[subcomp_idx] = sub_container[idx]
			big_container[idx] = item
		stream.container = big_container
		
	func findStream( name : String ):
		name = translateStreamName( name )
		
		var name_lower := name.to_lower()
		if name_lower == "front" or name_lower == "up" or name_lower == "right":
			var rot_stream = streams.get(AttrRotation, null)
			if rot_stream != null:
				var eulers = rot_stream.container
				var new_container := PackedVector3Array()
				new_container.resize(eulers.size())
				for idx in range(eulers.size()):
					var basis := FlowData.eulerToBasis(eulers[idx])
					match name_lower:
						"front":
							new_container[idx] = -basis.z
						"up":
							new_container[idx] = basis.y
						"right":
							new_container[idx] = basis.x
				return {
					"data_type": DataType.Vector,
					"container": new_container,
					"name": name
				}
			return null
		
		if name == "index":
			var new_container = PackedInt32Array()
			new_container.resize( size() )
			for idx in range( new_container.size() ):
				new_container[idx] = idx
			return {
				"data_type" : DataType.Int,
				"container" : new_container,
				"name" : "Index"
			}
			
		var parts = name.split( "." )
		if parts.size() == 2:
			#print( "findStream(%s) => %s (Streams:%s)" % [ name, parts, streams])
			var s0 = findStream( parts[0] )
			if s0 == null:
				push_error( "Failed to find stream root %s" % parts[0] )
				return null
			#print( "searching (%s) in %s" % [ parts[1], s0])
			return getSubStream( s0, parts[1] )
		elif parts.size() > 2:
			return null
		return streams.get( name, null )
	
	func registerStream( name : String, container, data_type : DataType = FlowData.DataType.Invalid ):
		if not name:
			print( "registerStream empty name!. Container size:", container.size() )
			push_error("registerStream name can't be empty of data_type %d" % [ data_type ] )
			return null
		if container == null:
			push_error("registerStream. Can't register a null container with name %s" %  name )
			return null			
		name = translateStreamName( name )
		var parts = name.split( "." )
		if parts.size() == 2:
			var s0 = streams.get( parts[0], null )
			if s0 == null:
				return "Failed to find stream %s" % parts[0] 
			return setSubStream( s0, parts[1], container )
		elif parts.size() > 2:
			return "Too many '.' in stream name"
		else:
			if container is PackedFloat32Array:
				data_type = FlowData.DataType.Float
			elif container is PackedInt32Array:
				data_type = FlowData.DataType.Int
			elif container is PackedVector3Array:
				data_type = FlowData.DataType.Vector
			elif container is PackedColorArray:
				data_type = FlowData.DataType.Color
			elif container is PackedStringArray:
				data_type = FlowData.DataType.String
			elif container is PackedByteArray:
				data_type = FlowData.DataType.Bool
			
			if data_type == FlowData.DataType.Invalid:
				print( "Invalid data type ", name, " Container:", container)
				return "Invalid container type"

			if streams.has(name) and streams[name].data_type != data_type:
				push_warning("Stream name conflict: '%s' already exists with data_type %d, overwriting with data_type %d" % [name, streams[name].data_type, data_type])

			# Length validation: when the Data already has streams, the new
			# container should match their element count. Exempt: length-1
			# broadcast streams and empty containers (register-empty-then-fill
			# idiom). Verbose-only because build-up idioms (merge's offset
			# padding) legitimately register mismatched sizes mid-construction;
			# run with --verbose when debugging stream-length corruption.
			if container.size() > 1 and streams.size() > 0:
				for existing_name in streams:
					if existing_name == name:
						continue
					var existing_size : int = streams[existing_name].container.size()
					if existing_size > 1 and existing_size != container.size():
						print_verbose("registerStream: stream '%s' has %d elements but Data streams have %d — lengths should match (or be 1 for broadcast)" % [name, container.size(), existing_size])
						break

			streams[ name ] = {
				"container" : container,
				"name" : name,
				"data_type" : data_type
			}
		last_added_stream_name = name
		#print( "Registered stream %s : %s " % [ name, streams[ name ] ])
		return null
	
	func addStream( name : String, data_type : DataType):
		if not name:
			push_error("addStream: name can't be empty" )
			return null
		var sz := size()
		var new_container = newContainerOfType(data_type)
		if sz:
			new_container.resize( sz )
		registerStream( name, new_container, data_type )
		return new_container
	
	func delStream( name : String):
		if streams.has( name ):
			streams.erase( name )
		
	func cloneStream( name : String ):
		var prev_stream = findStream( name )
		if not prev_stream:
			push_error("cloneStream: Data does not have a stream named %s" % name )
			return null
		var new_container
		match prev_stream.data_type:
			DataType.Bool:
				new_container = PackedByteArray( prev_stream.container )
			DataType.Int:
				new_container = PackedInt32Array( prev_stream.container )
			DataType.Float:
				new_container = PackedFloat32Array( prev_stream.container )
			DataType.Vector:
				new_container = PackedVector3Array( prev_stream.container )
				#print( "Duped container vec3 %s %s" % [ name, new_container ])
			DataType.Color:
				new_container = PackedColorArray( prev_stream.container )
			DataType.String:
				new_container = PackedStringArray( prev_stream.container )
			_:  # Resource
				new_container = prev_stream.container.duplicate()	
		prev_stream.container = new_container
		return new_container
		
	func filteredStream( old_stream : Dictionary, indices : PackedInt32Array ):
		var new_size : int = indices.size()
		var source_container = old_stream.container
		if size() > 1 and source_container.size() == 1:
			return source_container.duplicate()
		match old_stream.data_type:
			
			DataType.Bool:
				var old_container : PackedByteArray = old_stream.container
				var new_container := PackedByteArray( )
				new_container.resize( new_size )
				for idx in range( new_size ):
					new_container[idx] = old_container[ indices[idx] ]
				return new_container
				
			DataType.Int:
				var old_container : PackedInt32Array = old_stream.container
				var new_container := PackedInt32Array( )
				new_container.resize( new_size )
				for idx in range( new_size ):
					new_container[idx] = old_container[ indices[idx] ]
				return new_container
				
			DataType.Float:
				var old_container : PackedFloat32Array = old_stream.container
				var new_container := PackedFloat32Array( )
				new_container.resize( new_size )
				for idx in range( new_size ):
					new_container[idx] = old_container[ indices[idx] ]
				return new_container
				
			DataType.Vector:
				var old_container : PackedVector3Array = old_stream.container
				var new_container := PackedVector3Array(  )		
				new_container.resize( new_size )
				for idx in range( new_size ):
					new_container[idx] = old_container[ indices[idx] ]
				return new_container
				
			DataType.Color:
				var old_container : PackedColorArray = old_stream.container
				var new_container := PackedColorArray( )
				new_container.resize( new_size )
				for idx in range( new_size ):
					new_container[idx] = old_container[ indices[idx] ]
				return new_container
				
			DataType.String:
				var old_container : PackedStringArray = old_stream.container
				var new_container : PackedStringArray
				new_container.resize( new_size )
				for idx in range( new_size ):
					new_container[idx] = old_container[ indices[idx] ]
				return new_container
				
			DataType.Resource:
				var old_container : Array[ Resource ] = old_stream.container
				var new_container : Array[ Resource ] = []
				new_container.resize( new_size )
				for idx in range( new_size ):
					new_container[idx] = old_container[ indices[idx] ]
				return new_container
			DataType.NodeMesh:
				var old_container : Array = old_stream.container
				var new_container : Array = []
				new_container.resize( new_size )
				for idx in range( new_size ):
					new_container[idx] = old_container[ indices[idx] ]
				return new_container
			DataType.NodePath:
				var old_container : Array = old_stream.container
				var new_container : Array = []
				new_container.resize( new_size )
				for idx in range( new_size ):
					new_container[idx] = old_container[ indices[idx] ]
				return new_container
				
		return null

	func duplicate() -> Data:
		var s := Data.new()
		for name in streams:
			s.streams[name] = streams[name].duplicate()
			s.streams[name]["container"] = streams[name]["container"].duplicate()
		s.last_added_stream_name = last_added_stream_name
		s.tags = tags.duplicate()
		return s
		
	func filter( indices : PackedInt32Array ) -> Data:
		var new_data := Data.new()
		for old_stream in streams.values():
			var new_container = filteredStream( old_stream, indices )
			new_data.registerStream( old_stream.name, new_container, old_stream.data_type )
		new_data.tags = tags.duplicate()
		return new_data

	func dump( title : String ):
		print( "== %s (%d streams) ==" % [title, streams.size()] )
		for stream in streams.values():
			print( "%s (%s) %d elems" % [ stream.name, stream.data_type, stream.container.size() ] )
			for data in stream.container:
				print( "  %s" % str(data ))

	func addCommonStreams( num_points : int ):
		
		# Initialize with zeros
		var spos = addStream( FlowData.AttrPosition, FlowData.DataType.Vector )
		spos.resize( num_points )
		var srot = addStream( FlowData.AttrRotation, FlowData.DataType.Vector )
		srot.resize( num_points )
		
		# Initialize with ones
		var ssizes : PackedVector3Array = addStream( FlowData.AttrSize, FlowData.DataType.Vector )
		ssizes.resize( num_points )
		var init_value := Vector3.ONE
		for idx : int in range( num_points ):
			ssizes[idx] = init_value

	func getVector3Container( stream_name : StringName ) -> PackedVector3Array:
		var container = getContainerChecked( stream_name, DataType.Vector )
		if container == null:
			container = PackedVector3Array()
		return container

	func getTransformsStream() -> TransformsStream:
		if not (streams.has(AttrPosition) and streams.has(AttrRotation) and streams.has(AttrSize)):
			return null
		var trs := TransformsStream.new()
		trs.positions = getVector3Container( AttrPosition )
		trs.eulers = getVector3Container( AttrRotation )
		trs.sizes = getVector3Container( AttrSize )
		if trs.positions.is_empty() or trs.eulers.is_empty() or trs.sizes.is_empty():
			return null
		if trs.sizes.size() == trs.positions.size() && trs.sizes.size() == trs.eulers.size():
			return trs
		return null
