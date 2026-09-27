@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Switch",
		"settings" : SwitchNodeSettings,
		"aliases" : ["Switch"],
		"category" : "ControlFlow",
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out 0" }, { "label" : "Out 1" }, { "label" : "Out 2" }, { "label" : "Out 3" }],
		"tooltip" : "Routes the input to one of up to 4 outputs based on an index attribute or value.\nThe selection is constant per evaluation: in attribute mode only element [0] of the attribute is read\n— there is no per-point routing. Indices are clamped to 0..3.",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input( 0, ctx )
	if in_data == null:
		# require_input already emitted/handled output 0; keep the remaining
		# outputs populated in the silent editor-preview path
		if is_ownerless_preview(ctx):
			for i in range(1, 4):
				set_output(i, FlowData.Data.new())
		return

	var select_idx : int = settings.index
	if settings.use_attribute and settings.attribute_name != "":
		var stream = in_data.findStream(settings.attribute_name)
		if stream and stream.container.size() > 0:
			select_idx = int(stream.container[0])

	select_idx = clamp(select_idx, 0, 3)
	for i in range(4):
		if i == select_idx:
			set_output(i, in_data)
		else:
			# A fresh Data per output: sharing one instance would alias
			# downstream mutations between outputs
			set_output(i, FlowData.Data.new())
