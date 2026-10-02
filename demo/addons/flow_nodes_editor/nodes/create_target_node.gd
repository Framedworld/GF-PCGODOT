@tool
extends FlowNodeBase

## Create Target Node (Unreal's Create Target Actor): creates (or reuses) a named
## Node3D container under the owner and outputs a reference to it, so spawners
## can parent their content there through `spawn_parent_attribute`.
##
## Output: the input passed through with the per-data attribute
## "@data.<attribute_name>" holding the container (a NodePath-typed reference),
## or, when the input is not connected, an attribute set with a one-element
## `<attribute_name>` NodePath stream and the same per-data attribute.
##
## Ownership: the container carries `flow_owner` meta {component, node} like any
## spawned content, so FlowGraphNode3D.cleanup() frees it together with
## everything spawned under it. Re-running reuses the container of the same
## component and name instead of recreating it.

const META_TARGET_NAME := &"flow_target_name"

func _init():
	meta_node = {
		"title" : "Create Target Node",
		"settings" : CreateTargetNodeSettings,
		"aliases" : ["Create Target Actor"],
		"category" : "Spawner",
		"ins" : [{ "label" : "In" }],
		"outs" : [{ "label" : "Out" }],
		"main_thread" : true,
		"tooltip" : "Creates a named Node3D container (groups, owner policy) and outputs a reference to it.\nSpawners parent their content under it through spawn_parent_attribute (e.g. \"@data.target\").",
	}

func _find_existing( parent : Node, node_name : String, ctx ) -> Node3D:
	for child in parent.get_children():
		if not ( child is Node3D ) or child.is_queued_for_deletion():
			continue
		if not child.has_meta( "flow_owner" ) or not isOwnFlowContent( child.get_meta( "flow_owner" ), ctx ):
			continue
		if String( child.get_meta( META_TARGET_NAME, "" ) ) == node_name:
			return child
	return null

func _output( in_data, target : Node3D ) -> FlowData.Data:
	var attr : String = settings.attribute_name.strip_edges()
	if attr == "":
		attr = "target"
	var out := FlowData.Data.new()
	if in_data is FlowData.Data:
		# Shares the input's streams (like a pass-through) and adds the reference.
		out.streams = in_data.streams.duplicate()
		out.last_added_stream_name = in_data.last_added_stream_name
		out.copy_meta_from( in_data )
	else:
		out.registerStream( attr, Array( [ target ], TYPE_OBJECT, "Node", null ), FlowData.DataType.NodePath )
		out.kind = FlowData.Kind.AttrSet
	out.set_data_attr( attr, target, FlowData.DataType.NodePath )
	return out

func execute( ctx : FlowData.EvaluationContext ):
	var in_data = get_optional_input( 0 )
	if handleMissingOwner( ctx ):
		return
	var root : Node3D = ctx.owner
	if root == null or not is_instance_valid( root ):
		# Owner-less editor preview: nothing to create.
		set_output( 0, in_data if in_data is FlowData.Data else FlowData.Data.new() )
		return
	var node_name : String = settings.node_name.strip_edges()
	if node_name == "":
		setError( "Create Target Node needs a node_name" )
		set_output( 0, in_data if in_data is FlowData.Data else FlowData.Data.new() )
		return
	var parent : Node3D = FlowSpawnUtil.resolve_path_parent( self, root, settings.parent_path )

	var target := _find_existing( parent, node_name, ctx )
	if target == null:
		target = Node3D.new()
		target.name = node_name
		tagFlowContent( target, ctx )
		target.set_meta( META_TARGET_NAME, node_name )
		parent.add_child( target )
	else:
		tagFlowContent( target, ctx )

	if settings.owner_policy == CreateTargetNodeSettings.eOwnerPolicy.Transient:
		target.owner = null
	else:
		FlowSpawnUtil.claim_spawned( self, target, FlowSpawnUtil.scene_owner_for( root ), ctx )

	for group in settings.groups:
		var g := String( group ).strip_edges()
		if g != "" and not target.is_in_group( g ):
			target.add_to_group( g, true )

	if Engine.is_editor_hint():
		editor_mark_scene_unsaved()
	set_output( 0, _output( in_data, target ) )
