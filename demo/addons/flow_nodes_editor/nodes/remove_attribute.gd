@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Remove Attributes",
		"settings" : RemoveAttributeNodeSettings,
		"ins" : [{"label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["Delete Attributes"],
		"category" : "Metadata",
		"tooltip" : "Remove streams from the input connection.\nNames are matched exactly. Keep mode deletes everything except the listed names — including position/rotation/size if they are not listed.",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input(0, ctx)
	if in_data == null:
		return
	var out_data : FlowData.Data = in_data.duplicate()
	
	var streams_to_remove = settings.names
	if settings.keep_selected_attributes:
		var kept_names := {}
		for name in settings.names:
			kept_names[str(name)] = true
		streams_to_remove = out_data.streams.keys().filter( func( candidate ): 
			return not kept_names.has(str(candidate))
		)
	
	# Remove from the dict	
	for name in streams_to_remove:
		out_data.delStream( name )
		
	set_output( 0, out_data )
