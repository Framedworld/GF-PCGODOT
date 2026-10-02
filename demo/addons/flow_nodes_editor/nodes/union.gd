@tool
extends "res://addons/flow_nodes_editor/nodes/difference.gd"

func _init():
	meta_node = {
		"title" : "Union",
		"category" : "Spatial",
		"settings" : DifferenceNodeSettings,
		"ins" : [{ "label": "In A" }, { "label": "In B" }],
		"outs" : [{ "label" : "Out" }],
		"hide_inputs" : true,
		"tooltip" : "Union alias. Merges all incoming point sets.",
	}

func execute(ctx : FlowData.EvaluationContext):
	# Force the Union operation WITHOUT mutating the saved settings resource
	# (which would dirty/rewrite the shared .tres and make the inspector's
	# operation dropdown a lie). Mirror intersection.gd's duplicate-and-restore.
	var saved_settings = settings
	var forced_settings = settings.duplicate()
	forced_settings.operation = DifferenceNodeSettings.eOperation.Union
	settings = forced_settings
	super.execute(ctx)
	settings = saved_settings
