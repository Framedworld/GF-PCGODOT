@tool
extends FlowNodeBase

# UE PCG parity: Get Bounds / Spatial Data Bounds To Point. One output per input
# Data: the world AABB of its shape (shape-bearing Data) or of its points'
# effective bounds (position + bounds_min/bounds_max, else size).
# Points mode: a single point at the box centre, unit scale, bounds_min/max =
# -/+ half size, plus @data.bounds_min / @data.bounds_max (world corners).
# Shape mode: a FlowBoxVolume of the same box.

const GetBoundsSettings = preload("res://addons/flow_nodes_editor/nodes/get_bounds_settings.gd")

func _init():
	meta_node = {
		"title" : "Get Bounds",
		"settings" : GetBoundsSettings,
		"aliases" : ["Get Bounds", "Spatial Data Bounds To Point", "Bounds To Point"],
		"category" : "Spatial",
		"ins" : [{ "label" : "In" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "World bounds of the input: of its spatial shape, or of its points.\nOutputs one bounds point (or a box volume in Shape mode).",
	}

## World AABB of a Data: its shape's bounds, else the union of its points'
## effective boxes. `found` receives false when the Data is empty.
static func data_bounds( data : FlowData.Data ) -> Dictionary:
	if data.shape != null:
		return { "ok": true, "aabb": data.shape.get_bounds() }
	var positions := data.getVector3Container( FlowData.AttrPosition )
	if positions.is_empty() or positions.size() != data.size():
		return { "ok": false, "aabb": AABB() }
	var local := data.getEffectiveBounds()
	var aabb := AABB( positions[0] + local.min[0], Vector3.ZERO )
	for i in range( positions.size() ):
		aabb = aabb.expand( positions[i] + local.min[i] ).expand( positions[i] + local.max[i] )
	return { "ok": true, "aabb": aabb }

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input( 0, ctx, "Input 'In'" )
	if in_data == null:
		return
	var res := data_bounds( in_data )
	var aabb : AABB = res.aabb
	if settings.output_mode == GetBoundsSettings.eOutputMode.Shape:
		if not res.ok:
			set_output( 0, FlowData.Data.new() )
			return
		var shaped := FlowData.Data.from_shape( FlowBoxVolume.from_aabb( aabb, getSettingValue( ctx, "steepness", 1.0 ) ) )
		shaped.tags = in_data.tags.duplicate()
		set_output( 0, shaped )
		return
	var out := FlowData.Data.new()
	out.addCommonStreams( 1 if res.ok else 0 )
	if res.ok:
		out.getVector3Container( FlowData.AttrPosition )[0] = aabb.get_center()
		out.setSymmetricBounds( PackedVector3Array( [ aabb.size ] ) )
		out.set_data_attr( "bounds_min", aabb.position, FlowData.DataType.Vector )
		out.set_data_attr( "bounds_max", aabb.end, FlowData.DataType.Vector )
	out.tags = in_data.tags.duplicate()
	set_output( 0, out )
