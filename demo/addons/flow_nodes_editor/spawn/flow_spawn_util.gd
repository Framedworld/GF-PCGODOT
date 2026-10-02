@tool
class_name FlowSpawnUtil
extends RefCounted

## Helpers shared by the spawner nodes (spawn_meshes, spawn_scenes, spawn_nodes,
## spawn_spline_mesh, create_target_node, apply_on_actor).
##
## The `element` parameters are the calling FlowNodeBase element. They stay
## untyped on purpose: this file must load without pulling node.gd in (the node
## scripts and node.gd form a preload cycle), and the element only needs the
## FlowNodeBase helper API (setError, isOwnFlowContent, flowOwnerMeta,
## assignSpawnOwner).

enum eEntrySelection {
	## Weighted random pick per point, seeded by the point's $Seed (or its position).
	Weighted,
	## An Int/Float attribute holds the entry index (clamped to the entry list).
	AttributeIndex,
	## A String attribute holds the entry name (FlowMeshSpawnEntry.get_match_name),
	## or a Resource attribute holds the Mesh itself.
	AttributeName,
	## Point index modulo the number of entries.
	Cycle,
}

# --- Scene ownership -----------------------------------------------------------

## The node that should own spawned content so it is saved with the scene: the
## running scene, else the top-most owned ancestor of `root` (same rule the
## spawners have always used).
static func scene_owner_for( root : Node ) -> Node:
	if root == null:
		return null
	var tree := root.get_tree()
	if tree and tree.current_scene:
		return tree.current_scene
	var top : Node = root
	while top.get_parent() and top.owner:
		top = top.get_parent()
	return top

## True when the evaluation's component asked for transient output.
static func is_transient( ctx ) -> bool:
	return ctx != null and ctx.owner != null and is_instance_valid( ctx.owner ) and ctx.owner.get( "transient_output" ) == true

## (Re)assign the scene owner of a spawned or reused node and its flow_owner meta.
## A reused node whose component turned transient loses its owner.
static func claim_spawned( element, node : Node, scene_owner : Node, ctx ) -> void:
	element.tagFlowContent( node, ctx )
	if is_transient( ctx ):
		node.owner = null
		return
	element.assignSpawnOwner( node, scene_owner, ctx )

## A pooled MultiMeshInstance3D must draw like a fresh one: its instance
## transforms are relative to it, so a transform or visibility changed since
## the previous generation would move or hide every instance.
static func reset_reused_instance( node : Node3D ) -> void:
	node.transform = Transform3D.IDENTITY
	node.visible = true

## Assign the scene owner to a helper child (collision body, shape) of spawned content.
static func own_child( element, node : Node, scene_owner : Node, ctx ) -> void:
	element.assignSpawnOwner( node, scene_owner, ctx )

## Adds spawned content `node` under `parent` so that its name is unique among
## its siblings and never a fast-path "@Class@N" auto-name.
##
## Godot's default add_child() names a node whose name is taken (or empty)
## "@<Class>@<N>" from a process-global counter without checking the siblings.
## Such names are saved with the scene, and the counter restarts in the next
## session, so a later auto-name can equal a saved sibling's name: the parent
## then holds two children with one name, lookups by name return the wrong node
## and its name index loses an entry. A named node whose name is taken (by a
## user node, another component's content in a shared parent, or another
## spawner of the same graph) gets the first free "<name>_<k>", k >= 2
## (see unique_child_name). An unnamed node keeps the auto-name, as before,
## unless a sibling holds an auto-name the counter has not reached yet (one
## loaded from a saved scene); then it gets a readable name.
static func add_spawned_child( parent : Node, node : Node ) -> void:
	if String( node.name ) != "":
		node.name = unique_child_name( parent, String( node.name ), node )
		parent.add_child( node )
	elif _auto_name_may_collide( parent ):
		parent.add_child( node, true )
	else:
		parent.add_child( node )

## Renames spawned content `node` (a pooled node already under its parent, or a
## node about to be added with add_spawned_child) to `wanted`, or to the first
## free "<wanted>_<k>" when a sibling holds that name.
static func set_spawned_name( node : Node, wanted : String ) -> void:
	node.name = wanted
	var parent := node.get_parent()
	if parent != null:
		node.name = unique_child_name( parent, String( node.name ), node )

## `wanted` when no child of `parent` other than `node` has that name, else the
## first free "<wanted>_<k>" with k >= 2. Deterministic, and one lookup per
## candidate (Godot's readable naming instead counts the trailing number up
## through every taken name, quadratic when two spawners share a parent).
static func unique_child_name( parent : Node, wanted : String, node : Node = null ) -> String:
	var holder := parent.get_node_or_null( NodePath( wanted ) )
	if holder == null or holder == node:
		return wanted
	var k := 2
	while true:
		var candidate := "%s_%d" % [ wanted, k ]
		holder = parent.get_node_or_null( NodePath( candidate ) )
		if holder == null or holder == node:
			return candidate
		k += 1
	return wanted

# True when a child of `parent` has an "@Class@N" name with N past the current
# auto-name counter, so a later fast-path name could equal it.
static func _auto_name_may_collide( parent : Node ) -> bool:
	var counter := -1
	for child in parent.get_children( true ):
		var child_name := String( child.name )
		if not child_name.begins_with( "@" ):
			continue
		if counter < 0:
			counter = _auto_name_counter()
		if child_name.get_slice( "@", 2 ).to_int() > counter:
			return true
	return false

# The number of the most recent fast-path auto-name (the next one is higher).
static func _auto_name_counter() -> int:
	var probe := Node.new()
	var a := Node.new()
	a.name = "Probe"
	probe.add_child( a )
	var b := Node.new()
	b.name = "Probe"
	probe.add_child( b )
	var counter := String( b.name ).get_slice( "@", 2 ).to_int()
	probe.free()
	return counter

# --- Spawn parents -------------------------------------------------------------

## Node path string relative to the owner (spawn_parent_path), or the owner itself.
static func resolve_path_parent( element, root : Node3D, path : String ) -> Node3D:
	path = path.strip_edges()
	if path == "":
		return root
	var n = root.get_node_or_null( path )
	if n is Node3D:
		return n
	element.setError( "Spawn parent path '%s' is invalid or not a Node3D" % path )
	return root

static func _value_to_parent( value, root : Node ) -> Node3D:
	if typeof( value ) == TYPE_OBJECT:
		if not is_instance_valid( value ):
			return null
		return value as Node3D
	if value is NodePath or value is String or value is StringName:
		var text := String( value ).strip_edges()
		if text == "" or root == null:
			return null
		return root.get_node_or_null( NodePath( text ) ) as Node3D
	return null

## Per-point spawn parents read from `attr` (a per-point stream, a one-element
## broadcast stream or a per-data attribute such as `@data.target`, holding a
## Node3D reference, a NodePath or a path String relative to the owner).
## Returns { "ok": bool, "parents": Array (one Node3D per point) }. Points whose
## value is not a live Node3D fall back to `fallback` and are reported through
## setError. A missing attribute is an error (ok = false).
static func resolve_attribute_parents( element, in_data, attr : String, root : Node3D, fallback : Node3D ) -> Dictionary:
	attr = attr.strip_edges()
	var n : int = in_data.size()
	var has_stream = in_data.container( attr ) != null
	var data_name := attr.substr( FlowData.DataAttrPrefix.length() ) if attr.begins_with( FlowData.DataAttrPrefix ) else attr
	if not has_stream and not in_data.data_attrs.has( data_name ):
		element.setError( "Spawn parent attribute '%s' not found" % attr )
		return { "ok": false, "parents": [] }
	var parents : Array = []
	parents.resize( n )
	var by_value := {}
	var missing := 0
	for i in range( n ):
		var value = in_data.value_at( attr, i )
		var parent : Node3D = null
		if typeof( value ) == TYPE_OBJECT:
			parent = _value_to_parent( value, root )
		else:
			var cache_key = value
			if by_value.has( cache_key ):
				parent = by_value[ cache_key ]
			else:
				parent = _value_to_parent( value, root )
				by_value[ cache_key ] = parent
		if parent == null:
			missing += 1
			parent = fallback
		parents[i] = parent
	if missing > 0:
		element.setError( "Spawn parent attribute '%s': %d point(s) do not reference a live Node3D; spawned under the default parent" % [ attr, missing ] )
	return { "ok": true, "parents": parents }

## One spawn parent for the whole Data from `attr` (element 0 of the stream, or
## the per-data attribute). Falls back to `fallback` with setError when the
## attribute is missing or does not reference a live Node3D.
static func resolve_single_parent( element, in_data, attr : String, root : Node3D, fallback : Node3D ) -> Node3D:
	attr = attr.strip_edges()
	var value = in_data.value_at( attr, 0 )
	if value == null and in_data.container( attr ) == null:
		element.setError( "Spawn parent attribute '%s' not found" % attr )
		return fallback
	var parent := _value_to_parent( value, root )
	if parent == null:
		element.setError( "Spawn parent attribute '%s' does not reference a live Node3D; spawned under the default parent" % attr )
		return fallback
	return parent

## Distinct parents of `parents`, in first-appearance order, plus `extra` first.
static func unique_parents( parents : Array, extra : Node = null ) -> Array:
	var seen := {}
	var out : Array = []
	if extra != null:
		seen[ extra ] = true
		out.append( extra )
	for p in parents:
		if p != null and not seen.has( p ):
			seen[ p ] = true
			out.append( p )
	return out

# --- Property overrides ----------------------------------------------------------

## Validates `overrides` (point attribute name -> node property path) against
## `in_data`. Returns the prepared list, or null after setError when an
## attribute has a size that is neither 1 nor the point count. Attributes that
## do not exist are reported through setError and skipped.
static func prepare_property_overrides( element, in_data, overrides : Dictionary ) -> Variant:
	var prepared : Array = []
	var n : int = in_data.size()
	for key in overrides.keys():
		var attr := String( key ).strip_edges()
		var path := String( overrides[key] ).strip_edges()
		if attr == "" or path == "":
			continue
		var stream = in_data.findStream( attr ) if in_data.container( attr ) != null else null
		if stream == null and in_data.data_attrs.has( attr ):
			stream = in_data.findStream( FlowData.DataAttrPrefix + attr )
		if stream == null:
			element.setError( "Property override attribute '%s' not found" % attr )
			continue
		var size : int = stream.container.size()
		if size != n and size != 1:
			element.setError( "Property override attribute '%s' must have %d values or 1 value (got %d)" % [ attr, n, size ] )
			return null
		prepared.append( { "attr": attr, "path": path, "stream": stream } )
	return prepared

## Resolves a property path relative to `root`. Returns [node, property NodePath]
## or [] when it does not resolve. Accepted forms:
##   "light_energy"                      property of root
##   "position:x", ":position:x"         nested property of root (leading ':' forces root)
##   "Child/Light:light_energy"          property of a descendant
##   "%Mesh:material_override:albedo_color"  unique-name lookup, nested property
## A path whose node part is a plain name that is also a property of root
## ("position:x") is read as a property path on root. With `instance_scoped`
## (spawned instances) a "%Name" match must lie inside root: Godot falls back to
## root's owner scene when root owns no such unique node. Without it (Apply On
## Actor targets, which live in the scene) Godot's lookup is used as is.
static func resolve_property_target( root : Node, path : String, instance_scoped : bool = true ) -> Array:
	if root == null or path == "":
		return []
	var node : Node = root
	var prop := ""
	if path.begins_with( ":" ):
		prop = path.substr( 1 )
	elif not path.contains( ":" ):
		prop = path
	else:
		var np := NodePath( path )
		var names := np.get_concatenated_names()
		var subs := np.get_concatenated_subnames()
		if not names.begins_with( "%" ) and not names.contains( "/" ) and has_property( root, names ):
			prop = path
		else:
			node = root.get_node_or_null( NodePath( names ) )
			prop = subs
			# "%Name" falls back to root's owner scene when root owns no such
			# unique node; stay inside the instance.
			if instance_scoped and node != null and names.begins_with( "%" ) and node != root and not root.is_ancestor_of( node ):
				node = null
	if node == null or prop == "":
		return []
	if not has_property( node, prop.get_slice( ":", 0 ) ):
		return []
	return [ node, NodePath( prop ) ]

## True when `obj` exposes a property named `prop` (engine or script).
static func has_property( obj : Object, prop : String ) -> bool:
	if obj == null or prop == "":
		return false
	return prop in obj

## Applies the prepared overrides for point `idx` to the instance rooted at `root`.
## Problems (unresolved paths, values that cannot convert) are collected in
## `problems` (path -> message) so the caller reports each one once.
static func apply_property_overrides( root : Node, prepared : Array, idx : int, problems : Dictionary, instance_scoped : bool = true ) -> void:
	for item in prepared:
		var target := resolve_property_target( root, item.path, instance_scoped )
		if target.is_empty():
			problems[ item.path ] = "Property override path '%s' does not resolve on '%s'" % [ item.path, root.name ]
			continue
		var stream : Dictionary = item.stream
		var value = stream.container[ FlowData.bcast_idx( stream.container.size(), idx ) ]
		if stream.data_type == FlowData.DataType.Bool:
			value = bool( value )
		var node : Node = target[0]
		var prop : NodePath = target[1]
		var current = node.get_indexed( prop )
		var coerced := coerce_value( value, typeof( current ), stream.data_type )
		if not coerced.ok:
			problems[ item.path ] = "Property override '%s': cannot convert %s to %s" % [ item.path, type_string( typeof( value ) ), type_string( typeof( current ) ) ]
			continue
		node.set_indexed( prop, coerced.value )

## Converts an attribute value to the Variant type of the target property.
## Returns { ok, value }. Rules: numbers convert between int/float/bool (floats
## truncate toward zero like int()); a scalar fills every component of a vector
## or a grey Color; Vector3 <-> Color (rgb, alpha 1); Vector3 -> Vector2 keeps
## (x, y); a Quaternion attribute (stored as Vector4) or a Vector3 rotation
## attribute (Euler degrees, the canonical `rotation`) converts to Quaternion and
## Basis; anything -> String/StringName/NodePath via str(). A target without a
## value (TYPE_NIL, e.g. an unset Object property) receives the value as is.
static func coerce_value( value, target_type : int, data_type : int = -1 ) -> Dictionary:
	var src_type := typeof( value )
	if target_type == TYPE_NIL or src_type == target_type:
		return { "ok": true, "value": value }
	var is_num := src_type == TYPE_INT or src_type == TYPE_FLOAT or src_type == TYPE_BOOL
	match target_type:
		TYPE_BOOL:
			if is_num:
				return { "ok": true, "value": bool( value ) }
		TYPE_INT:
			if is_num:
				return { "ok": true, "value": int( value ) }
		TYPE_FLOAT:
			if is_num:
				return { "ok": true, "value": float( value ) }
		TYPE_STRING:
			return { "ok": true, "value": str( value ) }
		TYPE_STRING_NAME:
			return { "ok": true, "value": StringName( str( value ) ) }
		TYPE_NODE_PATH:
			if src_type == TYPE_STRING or src_type == TYPE_STRING_NAME:
				return { "ok": true, "value": NodePath( String( value ) ) }
		TYPE_VECTOR2:
			if is_num:
				return { "ok": true, "value": Vector2( float( value ), float( value ) ) }
			if src_type == TYPE_VECTOR3 or src_type == TYPE_VECTOR4:
				return { "ok": true, "value": Vector2( value.x, value.y ) }
		TYPE_VECTOR2I:
			if is_num:
				return { "ok": true, "value": Vector2i( int( value ), int( value ) ) }
			if src_type == TYPE_VECTOR3 or src_type == TYPE_VECTOR2:
				return { "ok": true, "value": Vector2i( roundi( value.x ), roundi( value.y ) ) }
		TYPE_VECTOR3:
			if is_num:
				return { "ok": true, "value": Vector3.ONE * float( value ) }
			if src_type == TYPE_COLOR:
				return { "ok": true, "value": Vector3( value.r, value.g, value.b ) }
			if src_type == TYPE_VECTOR4:
				return { "ok": true, "value": Vector3( value.x, value.y, value.z ) }
			if src_type == TYPE_VECTOR2:
				return { "ok": true, "value": Vector3( value.x, value.y, 0.0 ) }
		TYPE_VECTOR3I:
			if is_num:
				return { "ok": true, "value": Vector3i.ONE * int( value ) }
			if src_type == TYPE_VECTOR3:
				return { "ok": true, "value": Vector3i( roundi( value.x ), roundi( value.y ), roundi( value.z ) ) }
		TYPE_VECTOR4:
			if src_type == TYPE_COLOR:
				return { "ok": true, "value": Vector4( value.r, value.g, value.b, value.a ) }
			if src_type == TYPE_QUATERNION:
				return { "ok": true, "value": Vector4( value.x, value.y, value.z, value.w ) }
		TYPE_COLOR:
			if is_num:
				return { "ok": true, "value": Color( float( value ), float( value ), float( value ) ) }
			if src_type == TYPE_VECTOR3:
				return { "ok": true, "value": Color( value.x, value.y, value.z ) }
			if src_type == TYPE_VECTOR4:
				return { "ok": true, "value": Color( value.x, value.y, value.z, value.w ) }
			if src_type == TYPE_STRING:
				return { "ok": true, "value": Color.from_string( value, Color.WHITE ) }
		TYPE_QUATERNION:
			if src_type == TYPE_VECTOR4:
				return { "ok": true, "value": Quaternion( value.x, value.y, value.z, value.w ).normalized() }
			if src_type == TYPE_VECTOR3:
				return { "ok": true, "value": FlowData.eulerToQuat( value ) }
		TYPE_BASIS:
			if src_type == TYPE_VECTOR4:
				return { "ok": true, "value": Basis( Quaternion( value.x, value.y, value.z, value.w ).normalized() ) }
			if src_type == TYPE_VECTOR3:
				return { "ok": true, "value": FlowData.eulerToBasis( value ) }
	if src_type == TYPE_OBJECT and target_type == TYPE_OBJECT:
		return { "ok": true, "value": value }
	return { "ok": false, "value": null }

## Reports the problems collected by apply_property_overrides through setError.
static func report_override_problems( element, problems : Dictionary ) -> void:
	if problems.is_empty():
		return
	var messages : Array = problems.values()
	var text : String = messages[0]
	if messages.size() > 1:
		text += " (and %d more)" % ( messages.size() - 1 )
	element.setError( text )

# --- Mesh spawn entries ----------------------------------------------------------

static func _pick_weighted( weights : PackedFloat32Array, total : float, rnd : float ) -> int:
	if total <= 0.0:
		return 0
	var t := rnd * total
	var accum := 0.0
	for i in range( weights.size() ):
		accum += weights[i]
		if t <= accum and weights[i] > 0.0:
			return i
	for i in range( weights.size() - 1, -1, -1 ):
		if weights[i] > 0.0:
			return i
	return weights.size() - 1

## Entry index for every point of `in_data` (-1: the point spawns nothing).
## Returns null after setError on a configuration error. Deterministic: the
## weighted mode seeds one RNG per point from FlowData.resolve_seed (the point's
## $Seed xor `node_seed`, else a hash of its position), so a point keeps its
## pick when other points are added or removed.
static func select_entries( element, in_data, entries : Array, mode : int, attr : String, node_seed : int ) -> Variant:
	var n : int = in_data.size()
	var picks := PackedInt32Array()
	picks.resize( n )
	var count := entries.size()
	if count == 0:
		picks.fill( -1 )
		return picks
	match mode:
		eEntrySelection.Cycle:
			for i in range( n ):
				picks[i] = i % count
		eEntrySelection.AttributeIndex:
			var stream = _selector_stream( element, in_data, attr, n )
			if stream == null:
				return null
			var dt : int = stream.data_type
			if dt != FlowData.DataType.Int and dt != FlowData.DataType.Float and dt != FlowData.DataType.Bool:
				element.setError( "Entry attribute '%s' must be Int or Float for Attribute Index selection" % attr )
				return null
			var c = stream.container
			for i in range( n ):
				picks[i] = clampi( int( c[ FlowData.bcast_idx( c.size(), i ) ] ), 0, count - 1 )
		eEntrySelection.AttributeName:
			var stream = _selector_stream( element, in_data, attr, n )
			if stream == null:
				return null
			var dt : int = stream.data_type
			var c = stream.container
			var unmatched := 0
			if dt == FlowData.DataType.String:
				var by_name := {}
				for e in range( count ):
					var entry = entries[e]
					if entry == null:
						continue
					var entry_key : String = entry.get_match_name()
					if entry_key != "" and not by_name.has( entry_key ):
						by_name[ entry_key ] = e
				for i in range( n ):
					var key := String( c[ FlowData.bcast_idx( c.size(), i ) ] )
					picks[i] = by_name.get( key, -1 )
					if picks[i] < 0:
						unmatched += 1
			elif dt == FlowData.DataType.Resource:
				for i in range( n ):
					var res = c[ FlowData.bcast_idx( c.size(), i ) ]
					picks[i] = -1
					for e in range( count ):
						var entry = entries[e]
						if entry != null and entry.mesh != null and ( entry.mesh == res or ( res is Resource and res.resource_path != "" and entry.mesh.resource_path == res.resource_path ) ):
							picks[i] = e
							break
					if picks[i] < 0:
						unmatched += 1
			else:
				element.setError( "Entry attribute '%s' must be String or Resource for Attribute Name selection" % attr )
				return null
			if unmatched > 0:
				element.setError( "Entry attribute '%s': %d point(s) name no entry and were skipped" % [ attr, unmatched ] )
		_:
			var weights := PackedFloat32Array()
			weights.resize( count )
			var total := 0.0
			for e in range( count ):
				var w := 0.0
				if entries[e] != null:
					w = maxf( 0.0, float( entries[e].weight ) )
				weights[e] = w
				total += w
			if total <= 0.0:
				weights.fill( 1.0 )
				total = float( count )
			var point_seeds = in_data.getContainerChecked( FlowData.AttrSeed, FlowData.DataType.Int )
			if point_seeds != null and point_seeds.size() != n and point_seeds.size() != 1:
				point_seeds = null
			var positions = in_data.getContainerChecked( FlowData.AttrPosition, FlowData.DataType.Vector )
			var rng := RandomNumberGenerator.new()
			for i in range( n ):
				rng.seed = FlowData.resolve_seed( point_seeds, positions, i, node_seed )
				picks[i] = _pick_weighted( weights, total, rng.randf() )
	return picks

static func _selector_stream( element, in_data, attr : String, n : int ):
	attr = attr.strip_edges()
	if attr == "":
		element.setError( "Entry selection by attribute needs entry_attribute" )
		return null
	var stream = in_data.findStream( attr ) if in_data.container( attr ) != null else null
	if stream == null and in_data.data_attrs.has( attr ):
		stream = in_data.findStream( FlowData.DataAttrPrefix + attr )
	if stream == null:
		element.setError( "Input does not have attribute '%s'" % attr )
		return null
	var size : int = stream.container.size()
	if size != n and size != 1:
		element.setError( "Entry attribute '%s' must have %d values or 1 value (got %d)" % [ attr, n, size ] )
		return null
	return stream

## Grouping key of an entry: points whose entries share every render, custom
## data and collision setting land in the same MultiMeshInstance3D.
static func entry_group_key( entry ) -> Array:
	return [
		entry.mesh, entry.material_override, int( entry.cast_shadow ),
		entry.visibility_range_begin, entry.visibility_range_begin_margin,
		entry.visibility_range_end, entry.visibility_range_end_margin,
		int( entry.visibility_range_fade_mode ), entry.render_layers, int( entry.gi_mode ),
		Array( entry.custom_data_attributes ),
		int( entry.collision_mode ), int( entry.collision_bodies ), entry.collision_layer, entry.collision_mask,
	]

## Pool key (a String, stored as meta) of a group key.
static func group_pool_key( group_key : Array, extra : String = "" ) -> String:
	var parts := PackedStringArray()
	for v in group_key:
		if typeof( v ) == TYPE_OBJECT or v == null:
			parts.append( FlowSpawnPool.resource_key( v ) )
		else:
			parts.append( str( v ) )
	if extra != "":
		parts.append( extra )
	return "|".join( parts )

## Copies the entry's render settings onto a GeometryInstance3D. A null
## material_override leaves the instance's current override in place.
static func apply_render_settings( gi : GeometryInstance3D, entry ) -> void:
	if entry.material_override != null:
		gi.material_override = entry.material_override
	gi.cast_shadow = entry.cast_shadow
	gi.visibility_range_begin = entry.visibility_range_begin
	gi.visibility_range_begin_margin = entry.visibility_range_begin_margin
	gi.visibility_range_end = entry.visibility_range_end
	gi.visibility_range_end_margin = entry.visibility_range_end_margin
	gi.visibility_range_fade_mode = entry.visibility_range_fade_mode
	gi.layers = entry.render_layers
	gi.gi_mode = entry.gi_mode

# --- Per-instance custom data ----------------------------------------------------

## Prepares the custom data attributes. Returns an Array of { stream, channels },
## or null after setError when an attribute is missing, mis-sized or not numeric.
static func prepare_custom_data( element, in_data, attrs : PackedStringArray ) -> Variant:
	var out : Array = []
	var n : int = in_data.size()
	var used := 0
	for raw in attrs:
		var attr := String( raw ).strip_edges()
		if attr == "":
			continue
		var stream = in_data.findStream( attr ) if in_data.container( attr ) != null else null
		if stream == null and in_data.data_attrs.has( attr ):
			stream = in_data.findStream( FlowData.DataAttrPrefix + attr )
		if stream == null:
			element.setError( "Custom data attribute '%s' not found" % attr )
			return null
		var size : int = stream.container.size()
		if size != n and size != 1:
			element.setError( "Custom data attribute '%s' must have %d values or 1 value (got %d)" % [ attr, n, size ] )
			return null
		var channels := 0
		match int( stream.data_type ):
			FlowData.DataType.Float, FlowData.DataType.Int, FlowData.DataType.Bool:
				channels = 1
			FlowData.DataType.Vector:
				channels = 3
			FlowData.DataType.Color, FlowData.DataType.Quaternion:
				channels = 4
			_:
				element.setError( "Custom data attribute '%s' must be numeric, Vector, Color or Quaternion" % attr )
				return null
		out.append( { "stream": stream, "channels": channels } )
		used += channels
	return out

## The custom data Color of point `i`: channels filled in attribute order.
static func custom_data_at( prepared : Array, i : int ) -> Color:
	var ch := PackedFloat32Array( [ 0.0, 0.0, 0.0, 0.0 ] )
	var k := 0
	for item in prepared:
		if k >= 4:
			break
		var c = item.stream.container
		var v = c[ FlowData.bcast_idx( c.size(), i ) ]
		var comps : Array = []
		match int( item.channels ):
			1:
				comps = [ float( v ) ]
			3:
				comps = [ v.x, v.y, v.z ]
			4:
				if v is Color:
					comps = [ v.r, v.g, v.b, v.a ]
				else:
					comps = [ v.x, v.y, v.z, v.w ]
		for comp in comps:
			if k >= 4:
				break
			ch[k] = float( comp )
			k += 1
	return Color( ch[0], ch[1], ch[2], ch[3] )

# --- Collision ---------------------------------------------------------------------

## Shape for `mesh` under `mode` (FlowMeshSpawnEntry.eCollisionMode) and the
## local offset of that shape: { shape, offset }. Empty when the mode is None or
## the mesh yields no shape.
static func build_collision_shape( mesh : Mesh, mode : int ) -> Dictionary:
	# A mesh without geometry yields no shape (Convex would otherwise make an
	# empty hull after engine errors, BoxFromBounds a 1 mm box at the origin).
	if mesh == null or mesh.get_surface_count() == 0:
		return {}
	match mode:
		FlowMeshSpawnEntry.eCollisionMode.BoxFromBounds:
			var aabb := mesh.get_aabb()
			var box := BoxShape3D.new()
			box.size = Vector3( maxf( aabb.size.x, 0.001 ), maxf( aabb.size.y, 0.001 ), maxf( aabb.size.z, 0.001 ) )
			return { "shape": box, "offset": Transform3D( Basis.IDENTITY, aabb.get_center() ) }
		FlowMeshSpawnEntry.eCollisionMode.Convex:
			var convex := mesh.create_convex_shape( true, false )
			if convex == null:
				return {}
			return { "shape": convex, "offset": Transform3D.IDENTITY }
		FlowMeshSpawnEntry.eCollisionMode.Trimesh:
			var tri := mesh.create_trimesh_shape()
			if tri == null:
				return {}
			return { "shape": tri, "offset": Transform3D.IDENTITY }
	return {}

## Builds collision for the instances of one group under `holder` (the
## MultiMeshInstance3D, or the MeshInstance3D of a spline segment), whose space
## the `transforms` are in. PerMultiMesh: one FlowInstancedCollision3D with one
## shape owner per instance (one node). PerInstance: one StaticBody3D with a
## CollisionShape3D child per instance (two nodes each). Returns the body nodes.
static func build_collision( element, holder : Node3D, entry, shape_info : Dictionary, transforms : Array[Transform3D], scene_owner : Node, ctx ) -> Array:
	var bodies : Array = []
	if shape_info.is_empty() or transforms.is_empty():
		return bodies
	var shape : Shape3D = shape_info.shape
	var offset : Transform3D = shape_info.offset
	if int( entry.collision_bodies ) == FlowMeshSpawnEntry.eCollisionBodies.PerInstance:
		for i in range( transforms.size() ):
			var body := StaticBody3D.new()
			body.name = "Collision_%04d" % i
			body.collision_layer = entry.collision_layer
			body.collision_mask = entry.collision_mask
			body.transform = transforms[i]
			var cs := CollisionShape3D.new()
			cs.name = "Shape"
			cs.shape = shape
			cs.transform = offset
			body.add_child( cs )
			holder.add_child( body )
			own_child( element, body, scene_owner, ctx )
			own_child( element, cs, scene_owner, ctx )
			bodies.append( body )
		return bodies
	var shared := FlowInstancedCollision3D.new()
	shared.name = "Collision"
	shared.collision_layer = entry.collision_layer
	shared.collision_mask = entry.collision_mask
	var local : Array[Transform3D] = []
	local.resize( transforms.size() )
	for i in range( transforms.size() ):
		local[i] = transforms[i] * offset
	shared.setup( shape, local )
	holder.add_child( shared )
	own_child( element, shared, scene_owner, ctx )
	bodies.append( shared )
	return bodies

## Frees the collision bodies previously generated under `holder` (pool reuse).
static func clear_collision( holder : Node ) -> void:
	var doomed : Array = []
	for child in holder.get_children():
		if child is StaticBody3D:
			doomed.append( child )
	for child in doomed:
		holder.remove_child( child )
		child.queue_free()
