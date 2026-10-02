@tool
# FROZEN COPY of res://addons/flow_nodes_editor/nodes/filter_data_by_type.gd at commit 17c4524 (before
# WP2 spatial data). Loaded lazily (this folder is .gdignore-d, like tests/evaluator/probe_nodes) by
# tests/spatial/spatial_legacy_paths_test.gd to prove the
# current node produces byte-identical output for point inputs and default
# settings. Never edit; never register as a template.
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Filter Data By Type",
		"settings" : FilterDataByTypeNodeSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Inside" }, { "label" : "Outside" }],
		"aliases" : ["Filter Data By Type"],
		"category" : "Filter",
		"tooltip" : "Separates data based on their type, as dictated by the Target Type.\nPointData = has position/rotation/size streams; SplineData = has a NodePath 'node' stream; AttributeSet = any other non-empty data.",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input(0, ctx, "Input 'In'")
	if in_data == null:
		return

	var target = settings.target_type
	var match_found = false

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
		
	var empty_data = FlowData.Data.new()
	if match_found:
		set_output(0, in_data)
		set_output(1, empty_data)
	else:
		set_output(0, empty_data)
		set_output(1, in_data)
