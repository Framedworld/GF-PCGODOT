@tool
extends EditorInspectorPlugin

# Editor Inspector to show just the parameter associated to the Input Type
# So, if the input is defined as float, show only the cte_float member in the inspector

const DEFAULT_EDITOR_META := &"_flow_creating_default_editor"

func _can_handle(obj: Object) -> bool:
	if obj != null and obj.has_meta(DEFAULT_EDITOR_META):
		return false
	return obj is GraphInputParameter

func _parse_property(object: Object, type: Variant.Type, name: String, hint_type: PropertyHint, hint_string: String, usage_flags, wide: bool):
	var label := ""
	if name.begins_with("cte_"):
		var settings := object as GraphInputParameter
		var name_lc = FlowData.DataType.keys()[ settings.data_type ].to_lower()
		if name == "cte_" + name_lc:
			label = FlowI18n.t(_format_label(name))
		else:
			# Hide the attribute
			return true
	elif name == "name" or name == "data_type":
		label = FlowI18n.t(_format_label(name))
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
	if object != null:
		object.set_meta(DEFAULT_EDITOR_META, true)
	var editor := EditorInspector.instantiate_property_editor(
		object,
		type,
		name,
		hint_type,
		hint_string,
		usage_flags,
		wide
	)
	if object != null and object.has_meta(DEFAULT_EDITOR_META):
		object.remove_meta(DEFAULT_EDITOR_META)
	if editor == null:
		return false
	add_property_editor(name, editor, false, label)
	return true

func _format_label(property_name: String) -> String:
	return property_name.capitalize()
