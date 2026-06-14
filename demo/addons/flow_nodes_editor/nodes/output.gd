@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Output",
		"settings" : OutputNodeSettings,
		"ins" : [{ "label" : "In", "data_type" : FlowData.DataType.Float }],
		"outs" : [],
		"tooltip" : "Exposes an output parameter of the Subgraph",
		"aliases" : ["Output"],
		"auto_register" : true,
		"hide_outputs" : true
	}

func is_multi_port() -> bool:
	if node_template == "output":
		if settings and settings.name != "out_val" and settings.name != "":
			return false
		return true
	return false

func getMeta() -> Dictionary:
	if is_multi_port():
		var ins = []
		var editor = getEditor()
		if editor and editor.current_resource:
			for param in editor.current_resource.out_params:
				if param:
					ins.append({
						"label": param.name,
						"data_type": param.data_type
					})
		meta_node.ins = ins
		meta_node.title = "Outputs"
	else:
		meta_node.title = "Output"
		if settings:
			meta_node.ins = [{ "label" : settings.name, "data_type" : settings.data_type }]
		else:
			meta_node.ins = [{ "label" : "In", "data_type" : FlowData.DataType.Float }]
	return meta_node

func getTitle() -> String:
	if is_multi_port():
		return "Outputs"
	return settings.name if settings else "Output"

func refreshFromSettings():
	super.refreshFromSettings()
	if is_multi_port():
		pass
	else:
		if is_slot_enabled_left( 0 ):
			var color := getColorForFlowDataType( settings.data_type )
			set_slot_color_left( 0, color )

func onPropChanged( prop_name : String ):
	super.onPropChanged( prop_name )
	if prop_name == "data_type" or prop_name == "name":
		refreshFromSettings()

func _ready():
	super._ready()
	if is_multi_port():
		var editor = getEditor()
		if editor and editor.current_resource:
			if not editor.current_resource.in_params_changed.is_connected(_on_in_params_changed):
				editor.current_resource.in_params_changed.connect(_on_in_params_changed)
			initFromScript()

func _exit_tree():
	super._exit_tree()
	if is_multi_port():
		var editor = getEditor()
		if editor and editor.current_resource:
			if editor.current_resource.in_params_changed.is_connected(_on_in_params_changed):
				editor.current_resource.in_params_changed.disconnect(_on_in_params_changed)

func _on_in_params_changed():
	initFromScript()

func initFromScript():
	super.initFromScript()
	if is_multi_port():
		var spacer = Control.new()
		spacer.custom_minimum_size.y = 4
		add_child(spacer)
		
		var btn = Button.new()
		btn.text = "+ Add Output Parameter"
		btn.alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
		btn.add_theme_font_size_override("font_size", 10)
		if not btn.pressed.is_connected(_on_add_output_pressed_deferred):
			btn.pressed.connect(_on_add_output_pressed_deferred)
		add_child(btn)

func _on_add_output_pressed_deferred():
	call_deferred("_on_add_output_pressed")

func _on_add_output_pressed():
	var editor = getEditor()
	if editor and editor.current_resource:
		var index = 1
		var uname = "out_val"
		while editor._has_output_node_named(uname) or _has_out_param_named(editor.current_resource, uname):
			uname = "out_val_%d" % index
			index += 1
			
		var new_output = GraphInputParameter.new()
		new_output.name = uname
		new_output.data_type = FlowData.DataType.Float
		editor.current_resource.out_params.append( new_output )
		if editor.has_method("notifyGraphParametersEdited"):
			editor.call_deferred("notifyGraphParametersEdited", "out_params")
		else:
			editor.current_resource.in_params_changed.emit()
			editor.call_deferred("queueSave")

func _has_out_param_named(res, uname: String) -> bool:
	for param in res.out_params:
		if param and param.name == uname:
			return true
	return false

func execute( ctx : FlowData.EvaluationContext ):
	if is_multi_port():
		pass
	else:
		var in_data = get_optional_input( 0 )
		if in_data:
			var target_data = FlowData.Data.new()
			for stream_name in in_data.streams:
				var stream = in_data.streams[stream_name]
				target_data.registerStream(stream_name, stream.container, stream.data_type)

			if in_data.streams.size() == 0:
				set_output( 0, target_data )
				return
				
			var main_stream_name = in_data.last_added_stream_name
			if main_stream_name == "" or not in_data.hasStream(main_stream_name):
				main_stream_name = in_data.streams.keys()[in_data.streams.size() - 1]
				
			if in_data.streams.size() > 0 and not target_data.hasStream(settings.name):
				var main_stream = in_data.streams[main_stream_name]
				# Register the named output with the main stream's ACTUAL data_type, not
				# the port's declared settings.data_type. Forcing a declared type onto a
				# container of a different type (e.g. a Float main stream exposed through a
				# Vector-typed port) produces a mistyped stream that crashes downstream
				# filteredStream()/type-strict reads. The container's real type is correct.
				target_data.registerStream(settings.name, main_stream.container, main_stream.data_type)
				
			set_output( 0, target_data )
