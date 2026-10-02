@tool
class_name FlowPointsVolume
extends FlowSpatial

## Point data seen as a spatial volume (UE: `UPCGPointData` is itself spatial
## data). Each point is its world AABB (position + effective bounds, the same
## boxes `difference` uses) with its own steepness; density at a position is the
## strongest box falloff covering it, multiplied by the point's density.
##
## Built when a composite needs points as an operand, e.g. "surface minus these
## points" (Difference with the shape kept). A uniform hash grid over the boxes
## keeps queries local.

var box_min : PackedVector3Array
var box_max : PackedVector3Array
var box_steepness : PackedFloat32Array
var box_density : PackedFloat32Array

var _bounds : AABB
var _cell : float = 1.0
var _cells : Dictionary = {}	# Vector3i -> PackedInt32Array

func _init( mins : PackedVector3Array = PackedVector3Array(), maxs : PackedVector3Array = PackedVector3Array(), steepnesses : PackedFloat32Array = PackedFloat32Array(), densities : PackedFloat32Array = PackedFloat32Array() ) -> void:
	box_min = mins.duplicate()
	box_max = maxs.duplicate()
	var n := mini( box_min.size(), box_max.size() )
	box_min.resize( n )
	box_max.resize( n )
	box_steepness = steepnesses.duplicate()
	box_density = densities.duplicate()
	if box_steepness.size() != n:
		box_steepness.resize( n )
		box_steepness.fill( 1.0 )
	if box_density.size() != n:
		box_density.resize( n )
		box_density.fill( 1.0 )
	_build()
	_hash = hash( [ "points_volume", box_min, box_max, box_steepness, box_density ] )

## Volume of a point Data (position + effective bounds, steepness and density).
static func from_data( data : FlowData.Data ) -> FlowPointsVolume:
	var positions := data.getVector3Container( FlowData.AttrPosition )
	var n := positions.size()
	var mins := PackedVector3Array()
	var maxs := PackedVector3Array()
	mins.resize( n )
	maxs.resize( n )
	if n > 0:
		var local := data.getEffectiveBounds()
		var lmin : PackedVector3Array = local.min
		var lmax : PackedVector3Array = local.max
		for i in range( n ):
			var li := i if i < lmin.size() else 0
			mins[i] = positions[i] + lmin[li]
			maxs[i] = positions[i] + lmax[li]
	var dens := PackedFloat32Array()
	var dsrc = data.getContainerChecked( FlowData.AttrDensity, FlowData.DataType.Float )
	if dsrc != null and dsrc.size() > 0:
		dens.resize( n )
		for i in range( n ):
			dens[i] = clampf( dsrc[FlowData.bcast_idx( dsrc.size(), i )], 0.0, 1.0 )
	return FlowPointsVolume.new( mins, maxs, data.getEffectiveSteepness() if n > 0 else PackedFloat32Array(), dens )

func _build() -> void:
	var n := box_min.size()
	if n == 0:
		_bounds = AABB()
		return
	_bounds = AABB( box_min[0], Vector3.ZERO )
	var avg := 0.0
	var largest := 0.0
	for i in range( n ):
		_bounds = _bounds.expand( box_min[i] ).expand( box_max[i] )
		var s := box_max[i] - box_min[i]
		var m := maxf( s.x, maxf( s.y, s.z ) )
		avg += m
		largest = maxf( largest, m )
	# Average box size, but never so small that the largest box spans more than
	# 16 cells per axis.
	_cell = maxf( maxf( avg / n, largest / 16.0 ), 1e-3 )
	for i in range( n ):
		var c0 := _cell_of( box_min[i] )
		var c1 := _cell_of( box_max[i] )
		for z in range( c0.z, c1.z + 1 ):
			for y in range( c0.y, c1.y + 1 ):
				for x in range( c0.x, c1.x + 1 ):
					var key := Vector3i( x, y, z )
					if not _cells.has( key ):
						_cells[key] = PackedInt32Array()
					_cells[key].append( i )

func _cell_of( p : Vector3 ) -> Vector3i:
	return Vector3i( floori( p.x / _cell ), floori( p.y / _cell ), floori( p.z / _cell ) )

func get_kind() -> int:
	return FlowData.Kind.Volume

func get_type_name() -> String:
	return "Points Volume"

func get_bounds() -> AABB:
	return _bounds

func get_point_count() -> int:
	return box_min.size()

func sample_density( world_pos : Vector3 ) -> float:
	var ids = _cells.get( _cell_of( world_pos ), null )
	if ids == null:
		return 0.0
	var best := 0.0
	for i in ids:
		var mn := box_min[i]
		var mx := box_max[i]
		var c := ( mn + mx ) * 0.5
		var h := ( mx - mn ) * 0.5
		var t := 0.0
		var outside := false
		for axis in range( 3 ):
			var ha : float = h[axis]
			var d : float = absf( world_pos[axis] - c[axis] )
			if ha <= 0.0:
				if d > 1e-6:
					outside = true
					break
				continue
			t = maxf( t, d / ha )
		if outside:
			continue
		best = maxf( best, FlowSpatial.falloff( t, box_steepness[i] ) * box_density[i] )
		if best >= 1.0:
			break
	return best
