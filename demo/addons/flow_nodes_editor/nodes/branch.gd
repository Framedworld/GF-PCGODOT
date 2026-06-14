@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Branch",
		"settings" : BranchNodeSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out A" }, { "label" : "Out B" }],
		"tooltip" : "Routes the WHOLE input set to Out A or Out B.\nThe decision is the static Branch Value, or the FIRST element of the named Boolean attribute\n(this is a per-set decision, not per point — use a filter node for per-point routing).",
		"aliases" : ["Branch"],
		"category" : "ControlFlow",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input(0, ctx)
	if in_data == null:
		return

	var select_a : bool = settings.branch_value
	if settings.use_attribute:
		if settings.attribute_name.strip_edges() == "":
			push_warning("Branch: 'Use Attribute' is on but Attribute Name is empty — falling back to Branch Value")
		else:
			var stream = in_data.findStream(settings.attribute_name)
			if stream == null:
				if ctx.owner == null and Engine.is_editor_hint():
					var empty_data = FlowData.Data.new()
					set_output(0, empty_data)
					set_output(1, empty_data)
					return
				setError("Attribute '%s' not found" % settings.attribute_name)
				return
			if stream.container.size() > 0:
				var val = stream.container[0]
				if val is bool or val is int or val is float:
					select_a = bool(val)
				else:
					# Same truthy-string set boolean.gd accepts
					select_a = str(val).strip_edges().to_lower() in ["true", "1", "yes", "on"]
			else:
				push_warning("Branch: attribute '%s' is empty — falling back to Branch Value" % settings.attribute_name)

	# The unselected output still carries the input's schema (zero rows) so a
	# downstream merge/filter sees the expected streams instead of a bare empty set.
	var empty_data = in_data.emptyLike()
	if select_a:
		set_output(0, in_data)
		set_output(1, empty_data)
	else:
		set_output(0, empty_data)
		set_output(1, in_data)
