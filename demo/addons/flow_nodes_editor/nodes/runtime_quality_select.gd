@tool
extends FlowNodeBase

# UE PCG parity: Runtime Quality Select. Forwards the input pin of the current
# quality level when that pin is enabled in the settings, otherwise "Default".
# The level is resolved like Runtime Quality Branch (shared helpers in
# runtime_quality_branch.gd). Like select and select_multi, the selection runs
# once per bulk of the Default pin.

const QualityBranch = preload("res://addons/flow_nodes_editor/nodes/runtime_quality_branch.gd")

func _init():
	if not QualityBranch._setting_registered:
		QualityBranch.ensure_project_setting()
	meta_node = {
		"title" : "Runtime Quality Select",
		"settings" : RuntimeQualitySelectNodeSettings,
		"aliases" : ["Runtime Quality Select", "Quality Select", "Scalability Select", "LOD Select"],
		"category" : "ControlFlow",
		"pure" : false,
		"ins" : [{ "label": "Default" }, { "label": "Low" }, { "label": "Medium" }, { "label": "High" }, { "label": "Epic" }, { "label": "Cinematic" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Forwards the input of the current quality level (Low 0 .. Cinematic 4) when that pin is enabled in the settings,\notherwise the Default input. An enabled but unconnected pin gives an empty output.\nLevel: quality_override, else the runtime parameter \"quality\", else the project setting flow_nodes/quality_level (default 0).",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var level := QualityBranch.quality_level( ctx, settings.quality_override )
	var pin := QualityBranch.pin_for_level( level, settings.level_pins() )
	var selected = get_optional_input( pin )
	if not ( selected is FlowData.Data ):
		selected = FlowData.Data.new()
	set_output( 0, selected )
