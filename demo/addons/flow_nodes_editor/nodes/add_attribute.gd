@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Add Attribute",
		"settings" : AddAttributeNodeSettings,
		"ins" : [{ "label": "In" }], 
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Add a new constant stream to the input set\nIf the input is not given a single entry with the constant value is created.",
		"aliases" : ["Add Attribute", "Create Attribute"],
		"category" : "Metadata",
	}
	
func getTitle() -> String:
	return "%s - %s" % [ settings.name, FlowData.DataType.keys()[settings.data_type] ]

func exposedAsInputNode( prop ):
	if prop.name.begins_with( "cte_" ):
		var name_lc = FlowData.DataType.keys()[ settings.data_type ].to_lower()
		return prop.name == "cte_" + name_lc
	return false

func onPropChanged( prop_name : String ):
	super.onPropChanged( prop_name )
	if prop_name == "data_type":
		initFromScript()

func execute( ctx : FlowData.EvaluationContext ):
	if settings.name.strip_edges() == "":
		setError( "Attribute name can't be empty" )
		return

	var in_data : FlowData.Data = get_optional_input(0)
	var out_data : FlowData.Data
	var out_size := 1
	if in_data:
		out_data = in_data.duplicate()
		out_size = in_data.size()
	else:
		out_data = FlowData.Data.new()

	var new_val
	match settings.data_type:
		FlowData.DataType.Bool:
			new_val = 1 if getSettingValue( ctx, "cte_bool") else 0
		FlowData.DataType.Int:
			new_val = getSettingValue( ctx, "cte_int" )
		FlowData.DataType.Float:
			new_val = getSettingValue( ctx, "cte_float" )
		FlowData.DataType.Vector:
			new_val = getSettingValue( ctx, "cte_vector" )
		FlowData.DataType.Color:
			new_val = getSettingValue( ctx, "cte_color" )
		FlowData.DataType.String:
			new_val = getSettingValue( ctx, "cte_string" )
		FlowData.DataType.Resource:
			new_val = getSettingValue( ctx, "cte_resource" )
		_:
			setError( "Data type %s is not supported by Add Attribute" % FlowData.DataType.keys()[settings.data_type] )
			return

	var container = out_data.newContainerOfType( settings.data_type )
	if container == null:
		setError( "Failed to create a container of type %s" % FlowData.DataType.keys()[settings.data_type] )
		return

	# Per-Data domain: store a single value into Data.data_attrs (addressable as
	# "@data.<name>") rather than a per-point stream. The "@data." prefix routes
	# registerStream() to the per-data dictionary; a length-1 container is enough.
	var target_name : String = settings.name
	if settings.domain == AddAttributeNodeSettings.eDomain.PerData:
		target_name = FlowData.DataAttrPrefix + settings.name
		container.resize( 1 )
		container.fill( new_val )
	else:
		container.resize( out_size )
		container.fill( new_val )

	var err = out_data.registerStream( target_name, container, settings.data_type )
	if err:
		setError( err )
		return
	set_output( 0, out_data )
