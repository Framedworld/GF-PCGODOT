@tool
extends EditorInspectorPlugin

# Editor Inspector to show just the parameter associated to the Input Type
# So, if the input is defined as float, show only the cte_float member in the inspector

func _can_handle(obj: Object) -> bool:
	if FlowInspectorPropertyPolicy.is_creating_default_editor(obj):
		return false
	return obj is GraphInputParameter

func _parse_property(object: Object, type: Variant.Type, name: String, hint_type: PropertyHint, hint_string: String, usage_flags, wide: bool):
	var label := ""
	if name.begins_with("cte_"):
		var settings := object as GraphInputParameter
		if name == GraphInputParameter.value_property_name( settings.data_type ):
			label = FlowI18n.t(FlowInspectorPropertyPolicy.format_label(name))
		else:
			# Hide the attribute
			return true
	elif name == "name" or name == "data_type":
		label = FlowI18n.t(FlowInspectorPropertyPolicy.format_label(name))
	else:
		return true
	return _add_localized_property_editor(object, type, name, hint_type, hint_string, usage_flags, wide, label)

func _add_localized_property_editor(
	object: Object,
	type: Variant.Type,
	name: String,
	hint_type: PropertyHint,
	hint_string: String,
	usage_flags,
	wide: bool,
	label: String,
) -> bool:
	return FlowInspectorPropertyPolicy.add_localized_property_editor(
		self,
		object,
		type,
		name,
		hint_type,
		hint_string,
		usage_flags,
		wide,
		label
	)
