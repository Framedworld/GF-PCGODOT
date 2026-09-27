@tool
extends FlowNodeBase

const TagsMutateSettings = preload("res://addons/flow_nodes_editor/nodes/tags_mutate_settings.gd")

func _init():
	meta_node = {
		"title" : "Tags",
		"category" : "Metadata",
		"settings" : TagsMutateSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Adds, removes, or replaces FlowData tags.",
	}

func _parse_tags() -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	for part in settings.tags_csv.split(","):
		var t = part.strip_edges()
		if t == "":
			continue
		var key = t if settings.case_sensitive else t.to_lower()
		if seen.has(key):
			continue
		seen[key] = true
		out.append(t)
	return out

func _has_tag(tags : PackedStringArray, query : String) -> bool:
	for t in tags:
		if settings.case_sensitive:
			if t == query:
				return true
		else:
			if t.to_lower() == query.to_lower():
				return true
	return false

func execute(_ctx : FlowData.EvaluationContext):
	var in_data : FlowData.Data = get_input(0)
	if in_data == null:
		setError("Input not found")
		return

	var tags_to_apply = _parse_tags()
	var out_data = in_data.duplicate()
	var curr = out_data.tags.duplicate()

	match settings.operation:
		TagsMutateSettings.eOperation.Add:
			for t in tags_to_apply:
				if not _has_tag(curr, t):
					curr.append(t)
		TagsMutateSettings.eOperation.Remove:
			var filtered := PackedStringArray()
			for t in curr:
				if not _has_tag(tags_to_apply, t):
					filtered.append(t)
			curr = filtered
		TagsMutateSettings.eOperation.Replace:
			curr = tags_to_apply

	out_data.tags = curr
	set_output(0, out_data)
