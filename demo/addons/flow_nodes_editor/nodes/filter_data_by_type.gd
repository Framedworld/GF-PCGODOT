@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Filter Data By Type",
		"settings" : FilterDataByTypeNodeSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Inside" }, { "label" : "Outside" }],
		"aliases" : ["Filter Data By Type"],
		"category" : "Filter",
		"tooltip" : "Separates data based on their type, as dictated by the Target Type.\nSpatial data is classified by its shape (spline / surface / volume).\nOtherwise: PointData = has position/rotation/size streams; SplineData = has a NodePath 'node' stream; AttributeSet = any other non-empty data.",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input(0, ctx, "Input 'In'")
	if in_data == null:
		return

	var target = settings.target_type
	var match_found = false

	# Spatial data: classify by the shape itself. A union of splines (Get Spline
	# Data, Merged) still counts as spline data.
	if in_data.shape != null:
		var all_splines := true
		for leaf in in_data.shape.union_leaves():
			if not ( leaf is FlowSplineShape ):
				all_splines = false
				break
		var shape_kind : int = FlowData.Kind.Spline if all_splines else in_data.shape.get_kind()
		match target:
			FilterDataByTypeNodeSettings.eTargetType.SplineData:
				match_found = shape_kind == FlowData.Kind.Spline
			FilterDataByTypeNodeSettings.eTargetType.SurfaceData:
				match_found = shape_kind == FlowData.Kind.Surface
			FilterDataByTypeNodeSettings.eTargetType.VolumeData:
				match_found = shape_kind == FlowData.Kind.Volume
			FilterDataByTypeNodeSettings.eTargetType.SpatialData:
				match_found = true
			_:
				match_found = false
		_route( in_data, match_found )
		return

	# Prefer the explicit `kind` marker (spatial data type lattice) when a source
	# node has set it to a non-default value. Falls back to the historical
	# stream-shape heuristic when kind is unset/default (Points), so older data
	# and graphs that never stamp `kind` behave exactly as before.
	if in_data.kind != FlowData.Kind.Points:
		match target:
			FilterDataByTypeNodeSettings.eTargetType.PointData:
				# Explicit non-Points kind means this is not plain point data.
				match_found = false
			FilterDataByTypeNodeSettings.eTargetType.SplineData:
				match_found = in_data.kind == FlowData.Kind.Spline
			FilterDataByTypeNodeSettings.eTargetType.AttributeSet:
				match_found = in_data.kind == FlowData.Kind.AttrSet
			FilterDataByTypeNodeSettings.eTargetType.SurfaceData:
				match_found = in_data.kind == FlowData.Kind.Surface
			FilterDataByTypeNodeSettings.eTargetType.VolumeData:
				match_found = in_data.kind == FlowData.Kind.Volume
			FilterDataByTypeNodeSettings.eTargetType.SpatialData:
				match_found = in_data.kind in [ FlowData.Kind.Spline, FlowData.Kind.Surface, FlowData.Kind.Volume ]
	else:
		var has_rotation = in_data.hasStream(FlowData.AttrRotation) or in_data.hasStream(FlowData.AttrRotationQuat)
		var has_points = in_data.hasStream(FlowData.AttrPosition) and has_rotation and in_data.hasStream(FlowData.AttrSize)
		var has_splines = in_data.hasStream("node") and in_data.streams["node"].data_type == FlowData.DataType.NodePath

		if target == FilterDataByTypeNodeSettings.eTargetType.PointData:
			match_found = has_points
		elif target == FilterDataByTypeNodeSettings.eTargetType.SplineData:
			match_found = has_splines
		elif target == FilterDataByTypeNodeSettings.eTargetType.AttributeSet:
			match_found = not has_points and not has_splines and in_data.streams.size() > 0
		elif target == FilterDataByTypeNodeSettings.eTargetType.SpatialData:
			match_found = has_splines

	_route( in_data, match_found )

func _route( in_data : FlowData.Data, match_found : bool ) -> void:
	var empty_data = FlowData.Data.new()
	if match_found:
		set_output(0, in_data)
		set_output(1, empty_data)
	else:
		set_output(0, empty_data)
		set_output(1, in_data)
