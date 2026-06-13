@tool
extends PopupMenu
class_name SearchAddNodePopup

signal node_selected(template_name: String)
signal action_selected(item_id: int)
signal input_selected(input_idx: int)
signal output_selected(output_idx: int)

const IDM_COLLAPSE_TO_SUBGRAPH = 200
const IDM_NODE_BASE: int = 1000
const IDM_INPUT_BASE: int = 200000
const IDM_OUTPUT_BASE: int = 300000

var _id_to_item: Dictionary = {}
var _submenus: Dictionary = {}

const _CATEGORY_MAP := {
	"Black Lantern": ["bl_style_lab_source", "bl_building_mass", "bl_zone_carver", "bl_room_splitter", "bl_decorator_master", "bl_tactical_decorator", "bl_floor_data_to_points", "bl_floor_data_contract_points", "bl_validate_floor_data", "bl_room_style_template", "bl_style_context_source", "bl_style_context_points", "bl_style_anchor_points", "bl_sync_grid_cell", "bl_points_to_style_spec", "bl_style_spec_to_points", "bl_style_spec_merge", "bl_style_metadata_spec", "bl_smart_prop_scatter", "bl_points_to_floor_data_props"],
	"Control Flow": ["input", "output", "subgraph", "loop", "branch", "select", "select_multi", "switch", "get_loop_index"],
	"Debug": ["debug", "print_string", "sanity_check"],
	"Density": ["curve_remap_density", "density_remap", "distance_to_density"],
	"Filter": ["filter", "filter_data_by_tag", "filter_data_by_attribute", "filter_data_by_type", "attribute_filter_range", "point_filter_range", "self_pruning", "substract", "difference", "intersection", "union"],
	"Math": ["math_op", "expression", "reduce", "boolean"],
	"Metadata": ["add_attribute", "attribute_rename", "remove_attribute", "add_tags", "delete_tags", "replace_tags", "make_vector", "compose_vector", "decompose_vector", "attribute_random", "match_and_set", "mutate_seed", "random_color", "point_to_attribute_set", "attribute_set_to_point", "load_data_table", "data_table_row_to_attribute_set", "load_pcg_data_asset"],
	"Point Ops": ["bounds_modifier", "transform", "build_rotation_from_up", "combine_points", "duplicate_point", "point_offsets", "snap_to_grid", "point_neighborhood"],
	"Sampler": ["copy", "copy_points", "sample_mesh", "point_from_mesh", "point_from_player_pawn", "points_from_scene", "points_from_tilemap", "points_from_gridmap", "select_points", "sample_spline", "surface_sampler", "volume_sampler", "texture_sampler", "points_from_imported_scene", "load_alembic_file", "navigation_region_sampler"],
	"Spatial": ["create_spline", "distance", "ray_cast", "physics_overlap_query", "physics_shape_sweep", "clip_points_by_polygon", "clip_paths", "polygon_operation", "split_splines", "create_surface_from_spline", "create_surface_from_polygon"],
	"Assets": ["assets", "spawn_meshes", "spawn_scenes", "spawn_nodes", "apply_on_actor", "points_from_imported_scene", "load_alembic_file", "load_pcg_data_asset"],
	"Generators": ["grid", "noise", "relax", "dungeon_generator", "make_bounds", "grid_fill_bounds", "grid_connect_points", "grid_boundary"],
	"Utility": ["sort", "merge", "merge_points", "partition", "scan_meshes", "scan_splines", "scan_nodes", "sequence_sample", "size", "get_points_count", "get_data_count", "get_entries_count", "transform_points"]
}

func _ready():
	id_pressed.connect(_on_id_pressed)

func setup(p_node_types: Dictionary, p_inputs: Array, p_outputs: Array, p_has_selected_nodes: bool, p_req_in: int = FlowData.DataType.Invalid, p_req_out: int = FlowData.DataType.Invalid):
	clear()
	_id_to_item.clear()
	_clear_submenus()

	var next_node_id = IDM_NODE_BASE

	if p_has_selected_nodes and p_req_in == FlowData.DataType.Invalid and p_req_out == FlowData.DataType.Invalid:
		add_item("Collapse Selected to Subgraph", IDM_COLLAPSE_TO_SUBGRAPH)
		_id_to_item[IDM_COLLAPSE_TO_SUBGRAPH] = {"type": "action", "key": IDM_COLLAPSE_TO_SUBGRAPH}

	if p_req_in == FlowData.DataType.Invalid and p_req_out == FlowData.DataType.Invalid:
		for idx in range(p_inputs.size()):
			var input_name = p_inputs[idx].name
			var input_id = IDM_INPUT_BASE + idx
			add_item("Input: %s" % input_name, input_id)
			_id_to_item[input_id] = {"type": "input", "key": idx}

		for idx in range(p_outputs.size()):
			var output_name = p_outputs[idx].name
			var output_id = IDM_OUTPUT_BASE + idx
			add_item("Output: %s" % output_name, output_id)
			_id_to_item[output_id] = {"type": "output", "key": idx}

	var templates: Array = []
	for key in p_node_types.keys():
		var meta = p_node_types[key]
		if not meta.get("auto_register", true):
			continue

		if p_req_in != FlowData.DataType.Invalid or p_req_out != FlowData.DataType.Invalid:
			var has_compatible_port = false
			var ports = meta.ins if p_req_in != FlowData.DataType.Invalid else meta.outs
			var required_type = p_req_in if p_req_in != FlowData.DataType.Invalid else p_req_out
			for port in ports:
				if port.get("data_type", 0) == required_type:
					has_compatible_port = true
					break
			if not has_compatible_port:
				continue

		templates.append(key)

	templates.sort()
	var items_by_category: Dictionary = {}

	for key in templates:
		var meta = p_node_types[key]
		var title = str(meta.get("title", key))
		var item_data = {
			"type": "node",
			"key": key
		}
		if meta.has("tooltip"):
			item_data.tooltip = str(meta.tooltip)
		var category = _get_category_for_template(String(key))
		if not items_by_category.has(category):
			items_by_category[category] = []
		items_by_category[category].append({
			"id": next_node_id,
			"label": title,
			"data": item_data,
		})
		_id_to_item[next_node_id] = item_data
		next_node_id += 1

	if get_item_count() > 0 and not items_by_category.is_empty():
		add_separator()

	var categories: Array = items_by_category.keys()
	categories.sort()
	for category in categories:
		var submenu := PopupMenu.new()
		submenu.name = "Category_%s" % String(category).replace(" ", "_")
		submenu.id_pressed.connect(_on_id_pressed)
		add_child(submenu)
		_submenus[category] = submenu
		add_submenu_item(String(category), submenu.name)

		for node_item in items_by_category[category]:
			submenu.add_item(node_item.label, node_item.id)
			var tooltip = node_item.data.get("tooltip", "")
			if tooltip != "":
				var sub_idx = submenu.get_item_count() - 1
				submenu.set_item_tooltip(sub_idx, tooltip)

func _clear_submenus() -> void:
	for submenu in _submenus.values():
		if submenu is PopupMenu and is_instance_valid(submenu):
			submenu.queue_free()
	_submenus.clear()

func _get_category_for_template(template_name: String) -> String:
	for category in _CATEGORY_MAP.keys():
		if template_name in _CATEGORY_MAP[category]:
			return String(category)
	return "Utility"

func _on_id_pressed(id: int):
	var item = _id_to_item.get(id, {})
	if item.is_empty():
		return

	match item.type:
		"node":
			node_selected.emit(item.key)
		"action":
			action_selected.emit(item.key)
		"input":
			input_selected.emit(item.key)
		"output":
			output_selected.emit(item.key)

	hide()
