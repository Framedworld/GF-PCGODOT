@tool
extends PanelContainer
class_name FlowInspector

signal property_edited(prop_name: String)

const BASE_SETTINGS_PROPS = [
	"random_seed", "inspect_enabled", "debug_enabled", "debug_mode", "debug_scale",
	"debug_bulk", "debug_output", "debug_color", "debug_modulate_by", "title",
	"disabled", "trace", "resource_local_to_scene", "resource_path", "resource_name", "script"
]

var current_node: Node = null
var current_settings: Object = null
var editor: Control = null

var scroll_container: ScrollContainer
var content_vbox: VBoxContainer
var placeholder_label: Label

func _ready():
	custom_minimum_size.x = 268
	
	# Apply original dark theme panel colors
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1b1e28") # #1b1e28 node cards background
	sb.set_border_width_all(0)
	sb.border_width_left = 1
	sb.border_color = Color("252836") # #252836 border/separator
	add_theme_stylebox_override("panel", sb)
	
	# Create ScrollContainer
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll_container)
	
	# MarginContainer for spacing inside ScrollContainer
	var margin_container = MarginContainer.new()
	margin_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin_container.add_theme_constant_override("margin_left", 12)
	margin_container.add_theme_constant_override("margin_right", 12)
	margin_container.add_theme_constant_override("margin_top", 12)
	margin_container.add_theme_constant_override("margin_bottom", 12)
	scroll_container.add_child(margin_container)
	
	# Create ContentVBox
	content_vbox = VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_vbox.add_theme_constant_override("separation", 12)
	margin_container.add_child(content_vbox)
	
	# Create Placeholder Label
	placeholder_label = Label.new()
	placeholder_label.text = "Select a node to inspect its settings."
	placeholder_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	placeholder_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	placeholder_label.add_theme_color_override("font_color", Color("a1a1aa"))
	placeholder_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	placeholder_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(placeholder_label)
	
	edit(null)

func edit(target_node: Object):
	current_node = null if not target_node is Node else target_node
	current_settings = null
	
	# Clear existing children in ContentVBox
	for child in content_vbox.get_children():
		child.queue_free()
		content_vbox.remove_child(child)
		
	if target_node == null:
		scroll_container.visible = false
		placeholder_label.visible = true
		return
		
	scroll_container.visible = true
	placeholder_label.visible = false
	
	if target_node is GraphFrame:
		_populate_frame_properties(target_node)
	elif target_node is GraphNode:
		if target_node.node_template == "input":
			var editor_instance = target_node.getEditor()
			if editor_instance and editor_instance.current_resource:
				current_settings = editor_instance.current_resource
				_populate_graph_resource_properties(editor_instance.current_resource)
				return
		elif target_node.node_template == "output":
			var editor_instance = target_node.getEditor()
			if editor_instance and editor_instance.current_resource:
				current_settings = editor_instance.current_resource
				_populate_graph_resource_outputs(editor_instance.current_resource)
				return
		if "settings" in target_node and target_node.settings != null:
			current_settings = target_node.settings
			_populate_node_properties(target_node, target_node.settings)
		else:
			_populate_generic_node_properties(target_node)
	elif target_node is FlowGraphResource:
		current_settings = target_node
		_populate_graph_resource_properties(target_node)
	elif target_node is Resource:
		current_settings = target_node
		_populate_generic_resource_properties(target_node)

func _populate_frame_properties(frame: GraphFrame):
	# Header
	_add_header(frame.title, frame.name)
	
	# Frame Properties Container
	var prop_box = VBoxContainer.new()
	prop_box.add_theme_constant_override("separation", 8)
	content_vbox.add_child(prop_box)
	
	# Title
	prop_box.add_child(_create_row("Title", _create_string_input(frame, "title")))
	# Tint Color
	prop_box.add_child(_create_row("Tint Color", _create_color_input(frame, "tint_color")))
	# Tint Enabled
	prop_box.add_child(_create_row("Tint Enabled", _create_bool_input(frame, "tint_color_enabled")))

func _populate_generic_node_properties(node: GraphNode):
	_add_header(node.title, node.name)

func _populate_node_properties(node: GraphNode, settings: Object):
	# Header
	_add_header(node.title, node.name)
	
	# Type-specific properties container
	var type_box = VBoxContainer.new()
	type_box.add_theme_constant_override("separation", 10)
	content_vbox.add_child(type_box)

	type_box.add_child(_create_row("Title", _create_string_input(settings, "title")))

	# Gather subclass-specific properties
	var props = settings.get_property_list()
	var has_custom_props = false
	
	for prop in props:
		if prop.name in BASE_SETTINGS_PROPS:
			continue
		if prop.usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		if settings.has_method("exposeParam") and not settings.exposeParam(prop.name):
			continue
			
		var ctrl = _create_control_for_property(settings, prop)
		if ctrl:
			type_box.add_child(_create_row(_format_label(prop.name), ctrl))
			has_custom_props = true
			
	if not has_custom_props:
		var lbl_empty = Label.new()
		lbl_empty.text = "No custom settings"
		lbl_empty.add_theme_color_override("font_color", Color("a1a1aa"))
		lbl_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		type_box.add_child(lbl_empty)
		
	# Separator before Common Settings
	var sep = HSeparator.new()
	sep.add_theme_stylebox_override("separator", _create_separator_stylebox())
	content_vbox.add_child(sep)
	
	# Collapsible Common Settings
	var common_header = Button.new()
	common_header.text = "▼ Common Settings"
	common_header.flat = true
	common_header.alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT
	common_header.add_theme_color_override("font_color", Color("22d3ee")) # Cyan #22d3ee accent
	common_header.add_theme_color_override("font_hover_color", Color.WHITE)
	content_vbox.add_child(common_header)
	
	var common_container = VBoxContainer.new()
	common_container.add_theme_constant_override("separation", 8)
	content_vbox.add_child(common_container)
	
	common_header.pressed.connect(func():
		common_container.visible = not common_container.visible
		if common_container.visible:
			common_header.text = "▼ Common Settings"
		else:
			common_header.text = "▶ Common Settings"
	)
	
	# Populate Common Settings
	for prop in props:
		if not prop.name in BASE_SETTINGS_PROPS:
			continue
		if prop.name in ["resource_local_to_scene", "resource_path", "resource_name", "script", "title", "disabled", "trace"]:
			continue
		if prop.usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		if settings.has_method("exposeParam") and not settings.exposeParam(prop.name):
			continue
			
		var ctrl = _create_control_for_property(settings, prop)
		if ctrl:
			common_container.add_child(_create_row(_format_label(prop.name), ctrl))

func _add_header(title_text: String, id_text: String):
	# Title bar panel matching #252836
	var header_panel = PanelContainer.new()
	var hb_style = StyleBoxFlat.new()
	hb_style.bg_color = Color("252836") # #252836 node headers background
	hb_style.set_corner_radius_all(4)
	hb_style.content_margin_left = 10
	hb_style.content_margin_right = 10
	hb_style.content_margin_top = 8
	hb_style.content_margin_bottom = 8
	header_panel.add_theme_stylebox_override("panel", hb_style)
	
	var header_vbox = VBoxContainer.new()
	header_vbox.add_theme_constant_override("separation", 2)
	header_panel.add_child(header_vbox)
	
	var lbl_title = Label.new()
	lbl_title.text = title_text
	lbl_title.add_theme_font_size_override("font_size", 14)
	lbl_title.add_theme_color_override("font_color", Color.WHITE)
	header_vbox.add_child(lbl_title)
	
	var lbl_id = Label.new()
	lbl_id.text = id_text
	lbl_id.add_theme_font_size_override("font_size", 10)
	lbl_id.add_theme_color_override("font_color", Color("a1a1aa"))
	header_vbox.add_child(lbl_id)
	
	content_vbox.add_child(header_panel)
	
	# Small space
	var spacer = Control.new()
	spacer.custom_minimum_size.y = 4
	content_vbox.add_child(spacer)

func _create_row(label_text: String, control: Control) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var lbl = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color("cbd5e1")) # light gray
	lbl.custom_minimum_size.x = 90
	lbl.clip_text = true
	row.add_child(lbl)
	
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row

func _create_control_for_property(obj: Object, prop: Dictionary) -> Control:
	var prop_name = prop.name
	var prop_type = prop.type
	var val = obj.get(prop_name)
	
	if prop_type == TYPE_INT and prop.hint == PROPERTY_HINT_ENUM:
		var opt = OptionButton.new()
		var options = prop.hint_string.split(",")
		for idx in range(options.size()):
			opt.add_item(options[idx], idx)
		opt.selected = val
		opt.item_selected.connect(func(index):
			_on_value_changed(obj, prop_name, index)
		)
		opt.add_theme_font_size_override("font_size", 11)
		return opt
		
	match prop_type:
		TYPE_BOOL:
			var cb = CheckBox.new()
			cb.button_pressed = val
			cb.toggled.connect(func(pressed):
				_on_value_changed(obj, prop_name, pressed)
			)
			return cb
		TYPE_INT:
			var sb = SpinBox.new()
			sb.min_value = -999999
			sb.max_value = 999999
			sb.step = 1
			sb.value = val
			sb.value_changed.connect(func(new_val):
				_on_value_changed(obj, prop_name, int(new_val))
			)
			return sb
		TYPE_FLOAT:
			var sb = SpinBox.new()
			sb.min_value = -999999.0
			sb.max_value = 999999.0
			sb.step = 0.01
			sb.value = val
			sb.value_changed.connect(func(new_val):
				_on_value_changed(obj, prop_name, new_val)
			)
			return sb
		TYPE_STRING:
			return _create_string_input(obj, prop_name)
		TYPE_COLOR:
			return _create_color_input(obj, prop_name)
		TYPE_VECTOR3:
			return _create_vector3_input(obj, prop_name)
		TYPE_ARRAY:
			return _create_array_input(obj, prop_name, val if val is Array else [], prop)
		TYPE_DICTIONARY:
			return _create_dictionary_input(obj, prop_name, val if val is Dictionary else {})
		TYPE_OBJECT:
			var hbc = HBoxContainer.new()
			var lbl = Label.new()
			lbl.text = "None" if val == null else val.resource_path.get_file()
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.clip_text = true
			lbl.add_theme_font_size_override("font_size", 11)
			hbc.add_child(lbl)
			
			var btn = Button.new()
			btn.text = "..."
			btn.pressed.connect(func():
				_show_file_dialog_for_property(obj, prop_name, lbl, prop)
			)
			hbc.add_child(btn)
			return hbc
			
	return null

func _create_string_input(obj: Object, prop_name: String) -> LineEdit:
	var le = LineEdit.new()
	le.text = str(obj.get(prop_name))
	le.add_theme_font_size_override("font_size", 11)
	
	# Apply dark background stylebox #111318
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("111318")
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	le.add_theme_stylebox_override("normal", sb)
	
	le.text_submitted.connect(func(new_text):
		_on_value_changed(obj, prop_name, new_text)
	)
	le.focus_exited.connect(func():
		if str(obj.get(prop_name)) != le.text:
			_on_value_changed(obj, prop_name, le.text)
	)
	return le

func _create_bool_input(obj: Object, prop_name: String) -> CheckBox:
	var cb = CheckBox.new()
	cb.button_pressed = obj.get(prop_name)
	cb.toggled.connect(func(pressed):
		_on_value_changed(obj, prop_name, pressed)
	)
	return cb

func _create_color_input(obj: Object, prop_name: String) -> ColorPickerButton:
	var cpb = ColorPickerButton.new()
	cpb.color = obj.get(prop_name)
	cpb.color_changed.connect(func(new_color):
		_on_value_changed(obj, prop_name, new_color)
	)
	return cpb

func _create_vector3_input(obj: Object, prop_name: String) -> Control:
	var current_val = obj.get(prop_name)
	var value: Vector3 = current_val if current_val is Vector3 else Vector3.ZERO
	var hbc = HBoxContainer.new()
	hbc.add_theme_constant_override("separation", 4)
	for axis in ["x", "y", "z"]:
		var this_axis = axis
		var sb = SpinBox.new()
		sb.min_value = -999999.0
		sb.max_value = 999999.0
		sb.step = 0.01
		sb.custom_minimum_size.x = 52
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if axis == "x":
			sb.value = value.x
		elif axis == "y":
			sb.value = value.y
		else:
			sb.value = value.z
		sb.value_changed.connect(func(new_val):
			var current = obj.get(prop_name)
			var next: Vector3 = current if current is Vector3 else Vector3.ZERO
			if this_axis == "x":
				next.x = new_val
			elif this_axis == "y":
				next.y = new_val
			else:
				next.z = new_val
			_on_value_changed(obj, prop_name, next)
		)
		hbc.add_child(sb)
	return hbc

func _infer_array_mode(prop_name: String, prop: Dictionary, arr_val: Array) -> String:
	var hint = str(prop.get("hint_string", "")).to_lower()
	var hint_prefix = hint
	if hint.find(":") != -1:
		hint_prefix = hint.split(":")[0]
	if hint.find("packedscene") != -1 or prop_name == "scene_variants":
		return "packedscene"
	if hint.find("vector3") != -1 or prop_name in ["offsets", "rotations", "sizes"]:
		return "vector3"
	if hint.find("float") != -1 or prop_name == "scene_variant_weights":
		return "float"
	if hint.find("string") != -1 or prop_name == "labels":
		return "string"
	if hint_prefix == "9":
		return "vector3"
	if hint_prefix == "4":
		return "string"
	if hint_prefix == "3":
		return "float"
	if arr_val.size() > 0:
		var first = arr_val[0]
		if first is PackedScene:
			return "packedscene"
		match typeof(first):
			TYPE_VECTOR3:
				return "vector3"
			TYPE_FLOAT:
				return "float"
			TYPE_STRING:
				return "string"
	return "string"

func _create_array_input(obj: Object, prop_name: String, arr_val: Array, prop: Dictionary) -> Control:
	var wrapper = VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 4)
	var mode = _infer_array_mode(prop_name, prop, arr_val)

	for idx in range(arr_val.size()):
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var this_idx = idx

		match mode:
			"vector3":
				var vec_val = arr_val[this_idx]
				var vec: Vector3 = vec_val if vec_val is Vector3 else Vector3.ZERO
				for axis in ["x", "y", "z"]:
					var this_axis = axis
					var sb_axis = SpinBox.new()
					sb_axis.min_value = -999999.0
					sb_axis.max_value = 999999.0
					sb_axis.step = 0.01
					sb_axis.custom_minimum_size.x = 48
					sb_axis.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					if axis == "x":
						sb_axis.value = vec.x
					elif axis == "y":
						sb_axis.value = vec.y
					else:
						sb_axis.value = vec.z
					sb_axis.value_changed.connect(func(new_val):
						var current_arr = obj.get(prop_name)
						var next: Array = current_arr.duplicate(true) if current_arr is Array else []
						var cur = next[this_idx]
						var next_vec: Vector3 = cur if cur is Vector3 else Vector3.ZERO
						if this_axis == "x":
							next_vec.x = new_val
						elif this_axis == "y":
							next_vec.y = new_val
						else:
							next_vec.z = new_val
						next[this_idx] = next_vec
						_on_value_changed(obj, prop_name, next)
					)
					row.add_child(sb_axis)
			"float":
				var sb = SpinBox.new()
				sb.min_value = -999999.0
				sb.max_value = 999999.0
				sb.step = 0.01
				sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				sb.value = float(arr_val[this_idx])
				sb.value_changed.connect(func(new_val):
					var current_arr = obj.get(prop_name)
					var next: Array = current_arr.duplicate(true) if current_arr is Array else []
					next[this_idx] = new_val
					_on_value_changed(obj, prop_name, next)
				)
				row.add_child(sb)
			"packedscene":
				var lbl = Label.new()
				var res = arr_val[this_idx]
				lbl.text = "None" if res == null else res.resource_path.get_file()
				lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				lbl.clip_text = true
				lbl.add_theme_font_size_override("font_size", 11)
				row.add_child(lbl)
				var btn_pick = Button.new()
				btn_pick.text = "..."
				btn_pick.pressed.connect(func():
					_show_file_dialog_for_array_resource(obj, prop_name, this_idx, lbl, "packedscene")
				)
				row.add_child(btn_pick)
			_:
				var le = LineEdit.new()
				le.text = str(arr_val[this_idx])
				le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				var sb_style := StyleBoxFlat.new()
				sb_style.bg_color = Color("111318")
				sb_style.set_corner_radius_all(3)
				sb_style.content_margin_left = 6
				sb_style.content_margin_right = 6
				le.add_theme_stylebox_override("normal", sb_style)
				le.text_submitted.connect(func(new_text):
					var current_arr = obj.get(prop_name)
					var next: Array = current_arr.duplicate(true) if current_arr is Array else []
					next[this_idx] = new_text
					_on_value_changed(obj, prop_name, next)
				)
				le.focus_exited.connect(func():
					var current_arr = obj.get(prop_name)
					var next: Array = current_arr.duplicate(true) if current_arr is Array else []
					if str(next[this_idx]) != le.text:
						next[this_idx] = le.text
						_on_value_changed(obj, prop_name, next)
				)
				row.add_child(le)

		var btn_remove = Button.new()
		btn_remove.text = "-"
		btn_remove.tooltip_text = "Remove item"
		btn_remove.pressed.connect(func():
			var current_arr = obj.get(prop_name)
			var next: Array = current_arr.duplicate(true) if current_arr is Array else []
			if this_idx >= 0 and this_idx < next.size():
				next.remove_at(this_idx)
				_on_value_changed(obj, prop_name, next)
			edit(current_node)
		)
		row.add_child(btn_remove)
		wrapper.add_child(row)

	var add_row = HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 4)
	var add_btn = Button.new()
	add_btn.text = "+ Add"
	add_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_btn.pressed.connect(func():
		var current_arr = obj.get(prop_name)
		var next: Array = current_arr.duplicate(true) if current_arr is Array else []
		match mode:
			"vector3":
				next.append(Vector3.ZERO)
			"float":
				next.append(1.0)
			"packedscene":
				next.append(null)
			_:
				next.append("")
		_on_value_changed(obj, prop_name, next)
		edit(current_node)
	)
	add_row.add_child(add_btn)
	wrapper.add_child(add_row)

	return wrapper

func _create_dictionary_input(obj: Object, prop_name: String, dict_val: Dictionary) -> Control:
	var wrapper = VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 4)

	for key in dict_val.keys():
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var key_le = LineEdit.new()
		key_le.text = str(key)
		key_le.custom_minimum_size.x = 80
		key_le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(key_le)

		var value_le = LineEdit.new()
		value_le.text = str(dict_val[key])
		value_le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(value_le)

		var btn_remove = Button.new()
		btn_remove.text = "-"
		btn_remove.tooltip_text = "Remove entry"
		var original_key = key
		btn_remove.pressed.connect(func():
			var current_dict = obj.get(prop_name)
			var next: Dictionary = current_dict.duplicate(true) if current_dict is Dictionary else {}
			if next.has(original_key):
				next.erase(original_key)
				_on_value_changed(obj, prop_name, next)
			edit(current_node)
		)
		row.add_child(btn_remove)

		key_le.focus_exited.connect(func():
			var current_dict = obj.get(prop_name)
			var next: Dictionary = current_dict.duplicate(true) if current_dict is Dictionary else {}
			var new_key = key_le.text.strip_edges()
			if new_key == "":
				key_le.text = str(original_key)
				return
			var current_val = next[original_key] if next.has(original_key) else value_le.text
			if new_key != str(original_key):
				next.erase(original_key)
				next[new_key] = current_val
				_on_value_changed(obj, prop_name, next)
				edit(current_node)
		)

		value_le.focus_exited.connect(func():
			var current_dict = obj.get(prop_name)
			var next: Dictionary = current_dict.duplicate(true) if current_dict is Dictionary else {}
			var target_key = key_le.text.strip_edges()
			if target_key == "":
				target_key = str(original_key)
			next[target_key] = value_le.text
			_on_value_changed(obj, prop_name, next)
		)

		wrapper.add_child(row)

	var add_row = HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 4)
	var add_key = LineEdit.new()
	add_key.placeholder_text = "key"
	add_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(add_key)
	var add_value = LineEdit.new()
	add_value.placeholder_text = "value"
	add_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(add_value)
	var add_btn = Button.new()
	add_btn.text = "+"
	add_btn.pressed.connect(func():
		var key = add_key.text.strip_edges()
		if key == "":
			return
		var current_dict = obj.get(prop_name)
		var next: Dictionary = current_dict.duplicate(true) if current_dict is Dictionary else {}
		next[key] = add_value.text
		_on_value_changed(obj, prop_name, next)
		edit(current_node)
	)
	add_row.add_child(add_btn)
	wrapper.add_child(add_row)

	return wrapper

func _on_value_changed(obj: Object, prop_name: String, new_val):
	obj.set(prop_name, new_val)
	if obj is Resource:
		obj.emit_changed()
	property_edited.emit(prop_name)

func _show_file_dialog_for_property(obj: Object, prop_name: String, label: Label, prop: Dictionary = {}):
	var fd = FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_RESOURCES
	var hint = str(prop.get("hint_string", "")).to_lower()
	if hint.find("packedscene") != -1 or prop_name.find("scene") != -1:
		fd.add_filter("*.tscn,*.scn", "Scene Files")
		fd.add_filter("*.tres,*.res", "Resource Files")
	else:
		fd.add_filter("*.tres,*.res", "Resource Files")
		fd.add_filter("*.tscn,*.scn", "Scene Files")
	fd.file_selected.connect(func(path):
		var res = load(path)
		if res:
			_on_value_changed(obj, prop_name, res)
			label.text = path.get_file()
		fd.queue_free()
	)
	fd.canceled.connect(func():
		fd.queue_free()
	)
	add_child(fd)
	fd.popup_centered_ratio(0.4)

func _show_file_dialog_for_array_resource(obj: Object, prop_name: String, index: int, label: Label, mode: String):
	var fd = FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_RESOURCES
	if mode == "packedscene":
		fd.add_filter("*.tscn,*.scn", "Scene Files")
	else:
		fd.add_filter("*.tres,*.res", "Resource Files")
	fd.file_selected.connect(func(path):
		var res = load(path)
		if res:
			var current_arr = obj.get(prop_name)
			var next: Array = current_arr.duplicate(true) if current_arr is Array else []
			if index >= 0 and index < next.size():
				next[index] = res
				_on_value_changed(obj, prop_name, next)
				label.text = path.get_file()
		fd.queue_free()
	)
	fd.canceled.connect(func():
		fd.queue_free()
	)
	add_child(fd)
	fd.popup_centered_ratio(0.4)

func _format_label(name: String) -> String:
	var words = name.replace("_", " ").split(" ")
	for i in range(words.size()):
		words[i] = words[i].capitalize()
	return " ".join(words)

func _create_separator_stylebox() -> StyleBoxLine:
	var sbl = StyleBoxLine.new()
	sbl.color = Color("252836")
	sbl.thickness = 1
	return sbl

func _populate_graph_resource_properties(res: FlowGraphResource):
	_add_header("Graph Inputs", res.resource_path.get_file() if res.resource_path != "" else "Unsaved Resource")
	
	# Inputs list
	var list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 12)
	content_vbox.add_child(list_box)
	
	for idx in range(res.in_params.size()):
		var param = res.in_params[idx]
		if not param:
			continue
			
		var param_panel = PanelContainer.new()
		var p_style = StyleBoxFlat.new()
		p_style.bg_color = Color("252836") # card HSL background
		p_style.set_corner_radius_all(6)
		p_style.content_margin_left = 8
		p_style.content_margin_right = 8
		p_style.content_margin_top = 8
		p_style.content_margin_bottom = 8
		param_panel.add_theme_stylebox_override("panel", p_style)
		
		var param_vbox = VBoxContainer.new()
		param_vbox.add_theme_constant_override("separation", 6)
		param_panel.add_child(param_vbox)
		
		# Name row with Delete button
		var name_row = HBoxContainer.new()
		name_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var lbl_name = Label.new()
		lbl_name.text = "Name"
		lbl_name.add_theme_font_size_override("font_size", 11)
		lbl_name.custom_minimum_size.x = 50
		name_row.add_child(lbl_name)
		
		var le_name = LineEdit.new()
		le_name.text = param.name
		le_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le_name.add_theme_font_size_override("font_size", 11)
		
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("111318")
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		le_name.add_theme_stylebox_override("normal", sb)
		
		# Hook up focus/submitted to rename parameter and refresh
		le_name.text_submitted.connect(func(new_text):
			param.name = new_text
			param.emit_changed()
			res.emit_changed()
			property_edited.emit("in_params")
		)
		le_name.focus_exited.connect(func():
			if param.name != le_name.text:
				param.name = le_name.text
				param.emit_changed()
				res.emit_changed()
				property_edited.emit("in_params")
		)
		name_row.add_child(le_name)
		
		var btn_del = Button.new()
		btn_del.text = "X"
		btn_del.flat = true
		btn_del.add_theme_color_override("font_color", Color("ef4444"))
		btn_del.pressed.connect(func():
			res.in_params.remove_at(idx)
			res.emit_changed()
			property_edited.emit("in_params")
			edit(res) # refresh inspector
		)
		name_row.add_child(btn_del)
		param_vbox.add_child(name_row)
		
		# Type row
		var type_row = HBoxContainer.new()
		var lbl_type = Label.new()
		lbl_type.text = "Type"
		lbl_type.add_theme_font_size_override("font_size", 11)
		lbl_type.custom_minimum_size.x = 50
		type_row.add_child(lbl_type)
		
		var opt_type = OptionButton.new()
		opt_type.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		opt_type.add_theme_font_size_override("font_size", 11)
		
		var types_to_show = [
			FlowData.DataType.Bool,
			FlowData.DataType.Int,
			FlowData.DataType.Float,
			FlowData.DataType.Vector,
			FlowData.DataType.String,
			FlowData.DataType.Resource
		]
		for t_idx in range(types_to_show.size()):
			var t_val = types_to_show[t_idx]
			var t_name = FlowData.DataType.keys()[t_val]
			opt_type.add_item(t_name, t_val)
			if param.data_type == t_val:
				opt_type.selected = t_idx
				
		opt_type.item_selected.connect(func(id_index):
			var new_type = opt_type.get_item_id(id_index)
			param.data_type = new_type
			param.emit_changed()
			res.emit_changed()
			property_edited.emit("in_params")
			edit(res) # refresh to update value control type
		)
		type_row.add_child(opt_type)
		param_vbox.add_child(type_row)
		
		# Value row
		var val_row = HBoxContainer.new()
		var lbl_val = Label.new()
		lbl_val.text = "Value"
		lbl_val.add_theme_font_size_override("font_size", 11)
		lbl_val.custom_minimum_size.x = 50
		val_row.add_child(lbl_val)
		
		var val_ctrl: Control = null
		match param.data_type:
			FlowData.DataType.Bool:
				val_ctrl = CheckBox.new()
				val_ctrl.button_pressed = param.cte_bool
				val_ctrl.toggled.connect(func(pressed):
					param.cte_bool = pressed
					param.emit_changed()
					res.emit_changed()
					property_edited.emit("in_params")
				)
			FlowData.DataType.Int:
				val_ctrl = SpinBox.new()
				val_ctrl.min_value = -999999
				val_ctrl.max_value = 999999
				val_ctrl.step = 1
				val_ctrl.value = param.cte_int
				val_ctrl.value_changed.connect(func(new_val):
					param.cte_int = int(new_val)
					param.emit_changed()
					res.emit_changed()
					property_edited.emit("in_params")
				)
			FlowData.DataType.Float:
				val_ctrl = SpinBox.new()
				val_ctrl.min_value = -999999.0
				val_ctrl.max_value = 999999.0
				val_ctrl.step = 0.01
				val_ctrl.value = param.cte_float
				val_ctrl.value_changed.connect(func(new_val):
					param.cte_float = new_val
					param.emit_changed()
					res.emit_changed()
					property_edited.emit("in_params")
				)
			FlowData.DataType.Vector:
				var vec_hbox = HBoxContainer.new()
				vec_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				for axis in ["x", "y", "z"]:
					var sb_axis = SpinBox.new()
					sb_axis.min_value = -999999.0
					sb_axis.max_value = 999999.0
					sb_axis.step = 0.01
					sb_axis.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					if axis == "x":
						sb_axis.value = param.cte_vector.x
						sb_axis.value_changed.connect(func(nv):
							param.cte_vector.x = nv
							param.emit_changed()
							res.emit_changed()
							property_edited.emit("in_params")
						)
					elif axis == "y":
						sb_axis.value = param.cte_vector.y
						sb_axis.value_changed.connect(func(nv):
							param.cte_vector.y = nv
							param.emit_changed()
							res.emit_changed()
							property_edited.emit("in_params")
						)
					else:
						sb_axis.value = param.cte_vector.z
						sb_axis.value_changed.connect(func(nv):
							param.cte_vector.z = nv
							param.emit_changed()
							res.emit_changed()
							property_edited.emit("in_params")
						)
					vec_hbox.add_child(sb_axis)
				val_ctrl = vec_hbox
			FlowData.DataType.String:
				val_ctrl = LineEdit.new()
				val_ctrl.text = param.cte_string
				var val_sb := StyleBoxFlat.new()
				val_sb.bg_color = Color("111318")
				val_sb.set_corner_radius_all(3)
				val_sb.content_margin_left = 6
				val_sb.content_margin_right = 6
				val_ctrl.add_theme_stylebox_override("normal", val_sb)
				val_ctrl.text_submitted.connect(func(new_text):
					param.cte_string = new_text
					param.emit_changed()
					res.emit_changed()
					property_edited.emit("in_params")
				)
				val_ctrl.focus_exited.connect(func():
					if param.cte_string != val_ctrl.text:
						param.cte_string = val_ctrl.text
						param.emit_changed()
						res.emit_changed()
						property_edited.emit("in_params")
				)
			FlowData.DataType.Resource:
				var res_hbox = HBoxContainer.new()
				var res_lbl = Label.new()
				res_lbl.text = "None" if param.cte_resource == null else param.cte_resource.resource_path.get_file()
				res_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				res_lbl.clip_text = true
				res_lbl.add_theme_font_size_override("font_size", 11)
				res_hbox.add_child(res_lbl)
				
				var res_btn = Button.new()
				res_btn.text = "..."
				res_btn.pressed.connect(func():
					_show_file_dialog_for_param_resource(param, res_lbl, res)
				)
				res_hbox.add_child(res_btn)
				val_ctrl = res_hbox
				
		if val_ctrl:
			val_ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			val_row.add_child(val_ctrl)
		param_vbox.add_child(val_row)
		
		list_box.add_child(param_panel)
		
	# Add Parameter Button
	var btn_add = Button.new()
	btn_add.text = "+ Add Parameter"
	btn_add.add_theme_color_override("font_color", Color("22d3ee")) # Cyan
	btn_add.pressed.connect(func():
		var new_param = GraphInputParameter.new()
		new_param.name = "new_param_%d" % (res.in_params.size() + 1)
		new_param.data_type = FlowData.DataType.Float
		res.in_params.append(new_param)
		res.emit_changed()
		property_edited.emit("in_params")
		edit(res) # refresh
	)
	content_vbox.add_child(btn_add)

func _show_file_dialog_for_param_resource(param: GraphInputParameter, label: Label, parent_res: FlowGraphResource):
	var fd = FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_RESOURCES
	fd.file_selected.connect(func(path):
		var loaded_res = load(path)
		if loaded_res:
			param.cte_resource = loaded_res
			param.emit_changed()
			parent_res.emit_changed()
			property_edited.emit("in_params")
			label.text = path.get_file()
		fd.queue_free()
	)
	fd.canceled.connect(func():
		fd.queue_free()
	)
	add_child(fd)
	fd.popup_centered_ratio(0.4)

func _populate_graph_resource_outputs(res: FlowGraphResource):
	_add_header("Graph Outputs", res.resource_path.get_file() if res.resource_path != "" else "Unsaved Resource")
	
	# Outputs list
	var list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 12)
	content_vbox.add_child(list_box)
	
	for idx in range(res.out_params.size()):
		var param = res.out_params[idx]
		if not param:
			continue
			
		var param_panel = PanelContainer.new()
		var p_style = StyleBoxFlat.new()
		p_style.bg_color = Color("252836") # card HSL background
		p_style.set_corner_radius_all(6)
		p_style.content_margin_left = 8
		p_style.content_margin_right = 8
		p_style.content_margin_top = 8
		p_style.content_margin_bottom = 8
		param_panel.add_theme_stylebox_override("panel", p_style)
		
		var param_vbox = VBoxContainer.new()
		param_vbox.add_theme_constant_override("separation", 6)
		param_panel.add_child(param_vbox)
		
		# Name row with Delete button
		var name_row = HBoxContainer.new()
		name_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var lbl_name = Label.new()
		lbl_name.text = "Name"
		lbl_name.add_theme_font_size_override("font_size", 11)
		lbl_name.custom_minimum_size.x = 50
		name_row.add_child(lbl_name)
		
		var le_name = LineEdit.new()
		le_name.text = param.name
		le_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le_name.add_theme_font_size_override("font_size", 11)
		
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("111318")
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		le_name.add_theme_stylebox_override("normal", sb)
		
		# Hook up focus/submitted to rename parameter and refresh
		le_name.text_submitted.connect(func(new_text):
			param.name = new_text
			param.emit_changed()
			res.emit_changed()
			property_edited.emit("out_params")
		)
		le_name.focus_exited.connect(func():
			if param.name != le_name.text:
				param.name = le_name.text
				param.emit_changed()
				res.emit_changed()
				property_edited.emit("out_params")
		)
		name_row.add_child(le_name)
		
		var btn_del = Button.new()
		btn_del.text = "X"
		btn_del.flat = true
		btn_del.add_theme_color_override("font_color", Color("ef4444"))
		btn_del.pressed.connect(func():
			res.out_params.remove_at(idx)
			res.emit_changed()
			property_edited.emit("out_params")
			edit(res) # refresh inspector
		)
		name_row.add_child(btn_del)
		param_vbox.add_child(name_row)
		
		# Type row
		var type_row = HBoxContainer.new()
		var lbl_type = Label.new()
		lbl_type.text = "Type"
		lbl_type.add_theme_font_size_override("font_size", 11)
		lbl_type.custom_minimum_size.x = 50
		type_row.add_child(lbl_type)
		
		var opt_type = OptionButton.new()
		opt_type.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		opt_type.add_theme_font_size_override("font_size", 11)
		
		var types_to_show = [
			FlowData.DataType.Bool,
			FlowData.DataType.Int,
			FlowData.DataType.Float,
			FlowData.DataType.Vector,
			FlowData.DataType.String,
			FlowData.DataType.Resource
		]
		for t_idx in range(types_to_show.size()):
			var t_val = types_to_show[t_idx]
			var t_name = FlowData.DataType.keys()[t_val]
			opt_type.add_item(t_name, t_val)
			if param.data_type == t_val:
				opt_type.selected = t_idx
				
		opt_type.item_selected.connect(func(id_index):
			var new_type = opt_type.get_item_id(id_index)
			param.data_type = new_type
			param.emit_changed()
			res.emit_changed()
			property_edited.emit("out_params")
			edit(res) # refresh to update value control type
		)
		type_row.add_child(opt_type)
		param_vbox.add_child(type_row)
		
		list_box.add_child(param_panel)
		
	# Add Parameter Button
	var btn_add = Button.new()
	btn_add.text = "+ Add Parameter"
	btn_add.add_theme_color_override("font_color", Color("22d3ee")) # Cyan
	btn_add.pressed.connect(func():
		var new_param = GraphInputParameter.new()
		new_param.name = "new_out_%d" % (res.out_params.size() + 1)
		new_param.data_type = FlowData.DataType.Float
		res.out_params.append(new_param)
		res.emit_changed()
		property_edited.emit("out_params")
		edit(res) # refresh
	)
	content_vbox.add_child(btn_add)

func _populate_generic_resource_properties(res: Resource):
	_add_header(res.resource_path.get_file() if res.resource_path != "" else res.get_class(), res.get_class())
	
	var prop_box = VBoxContainer.new()
	prop_box.add_theme_constant_override("separation", 10)
	content_vbox.add_child(prop_box)
	
	var props = res.get_property_list()
	for prop in props:
		if prop.name in ["resource_local_to_scene", "resource_path", "resource_name", "script"]:
			continue
		if prop.usage & PROPERTY_USAGE_STORAGE == 0:
			continue
			
		var ctrl = _create_control_for_property(res, prop)
		if ctrl:
			prop_box.add_child(_create_row(_format_label(prop.name), ctrl))
