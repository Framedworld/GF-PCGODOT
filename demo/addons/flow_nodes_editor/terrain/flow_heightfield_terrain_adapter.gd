@tool
class_name FlowHeightfieldTerrainAdapter
extends FlowTerrainAdapter

## Shared base of the adapters whose terrain is a regular height grid
## (HeightMapShape3D, heightmap Image): queries go through
## FlowHeightfieldSurface.clamped_hit, so heights and normals beyond the grid
## are those of the nearest edge sample, in the grid's own (possibly rotated or
## scaled) frame. Splat images cover the grid footprint.

var _surface : FlowHeightfieldSurface = null
var _with_layers : FlowHeightfieldSurface = null

func _init( surface : FlowHeightfieldSurface = null, adapter_options : Dictionary = {} ) -> void:
	super._init( adapter_options )
	_surface = surface
	if _surface == null:
		error = "no height grid"

func get_type_name() -> String:
	return "Heightfield"

func get_heightfield() -> FlowHeightfieldSurface:
	return _surface

func get_bounds() -> AABB:
	return _surface.get_bounds() if _surface != null else AABB()

func get_sample_spacing() -> float:
	if _surface == null:
		return 1.0
	return _surface.cell_size * maxf( _surface.transform.basis.x.length(), _surface.transform.basis.z.length() )

func get_height( x : float, z : float ) -> float:
	if _surface == null:
		return NAN
	var hit := _surface.clamped_hit( x, z )
	return NAN if hit.is_empty() else float( hit.position.y )

func get_normal( x : float, z : float ) -> Vector3:
	if _surface == null:
		return Vector3.UP
	var hit := _surface.clamped_hit( x, z )
	if hit.is_empty():
		return super.get_normal( x, z )
	return hit.normal

func _splat_mapping() -> Dictionary:
	if _surface == null:
		return super._splat_mapping()
	var r := _surface.get_local_footprint()
	return { "min": r.position, "max": r.end, "to_layer": _surface.transform.affine_inverse() }

## The grid itself (no resampling), with the vertical tolerance of the options
## and every layer attached.
func to_surface() -> FlowSpatial:
	if _surface == null:
		return null
	if _with_layers == null:
		_with_layers = _surface.with_tolerance( _tolerance() )
		_with_layers.attach_layers( _snapshot_layers( _surface.width, _surface.depth ) )
	return _with_layers
