@tool
class_name FlowSpawnPool
extends RefCounted

## Instance pooling for spawners (`reuse_instances` setting, off by default).
##
## The pool keeps no state between evaluations: the scene tree IS the pool.
## Elements are created fresh for every run, so a spawner that wants to reuse
## its previous output collects it from the spawn parents at the start of the
## run, hands out matching nodes while it spawns, and frees whatever was not
## taken at the end. Content is matched exactly like the regular clear step
## (docs/RUNTIME_API_P0.md §5): `flow_owner` meta naming this node and this
## component, legacy String metas and stale component ids included. A reused
## node gets a fresh `flow_owner` meta, so stale ids are refreshed.
##
## Each pooled node carries its pool key in the `flow_pool_key` meta (set by
## `tag`). Nodes without one (spawned with pooling off) never match a key and
## are freed by `release_unused`, so turning pooling on is always safe.
##
## `FlowGraphNode3D.cleanup()` and `regenerate()` free every generated node, so
## there is nothing to reuse after them; pooling pays off when `generate()` (or
## an editor re-evaluation) runs again over existing content.

const KEY_META := &"flow_pool_key"

## parent instance id -> key -> Array[Node] (in child order)
var _buckets : Dictionary = {}
## every collected node, for release_unused
var _all : Array[Node] = []
var _taken : Dictionary = {}

## Collects the content `element` spawned under each of `parents` for the
## evaluation's component, optionally narrowed by `filter(child) -> bool`.
## Collected nodes are renamed to temporary unique names so the run can hand
## out the canonical names (Scene_0000, ...) without clashes.
static func collect( element, parents : Array, ctx, filter : Callable = Callable() ) -> FlowSpawnPool:
	var pool := FlowSpawnPool.new()
	for parent in parents:
		if parent == null or not is_instance_valid( parent ):
			continue
		var by_key : Dictionary = pool._buckets.get( parent.get_instance_id(), {} )
		for child in parent.get_children():
			if not child.has_meta( "flow_owner" ):
				continue
			if child.is_queued_for_deletion():
				continue
			# Spawned earlier in this evaluation (another bulk or loop
			# iteration): not previous output, keep it.
			if element.isSpawnedThisSession( child, ctx ):
				continue
			if not element.isOwnFlowContent( child.get_meta( "flow_owner" ), ctx, child ):
				continue
			if filter.is_valid() and not filter.call( child ):
				continue
			if pool._all.has( child ):
				continue
			pool._all.append( child )
			var key := String( child.get_meta( KEY_META, "" ) )
			if key != "":
				if not by_key.has( key ):
					by_key[ key ] = []
				by_key[ key ].append( child )
		pool._buckets[ parent.get_instance_id() ] = by_key
	for node in pool._all:
		node.name = "__flow_pool_%d" % node.get_instance_id()
	return pool

## Number of nodes collected.
func size() -> int:
	return _all.size()

## A collected node with `key` under `parent`, or null. Each node is handed out once.
func take( key : String, parent : Node ) -> Node:
	if parent == null:
		return null
	var by_key : Dictionary = _buckets.get( parent.get_instance_id(), {} )
	var bucket : Array = by_key.get( key, [] )
	while not bucket.is_empty():
		var node : Node = bucket.pop_front()
		if is_instance_valid( node ) and not node.is_queued_for_deletion() and node.get_parent() == parent:
			_taken[ node ] = true
			return node
	return null

## Detach and free every collected node that was not taken. Returns how many.
func release_unused() -> int:
	var released := 0
	for node in _all:
		if _taken.has( node ) or not is_instance_valid( node ):
			continue
		var parent := node.get_parent()
		if parent:
			parent.remove_child( node )
		node.queue_free()
		released += 1
	_all.clear()
	_buckets.clear()
	return released

## Stamp `node` with its pool key.
static func tag( node : Node, key : String ) -> void:
	node.set_meta( KEY_META, key )

## Stable string id of a resource for pool keys: its path when saved to its own
## file, else its instance id (unsaved and built-in resources only match within
## the session, which is the case pooling targets).
static func resource_key( res ) -> String:
	if res == null:
		return "-"
	if res is Resource and res.resource_path != "" and not res.resource_path.contains( "::" ):
		return res.resource_path
	return "#%d" % res.get_instance_id()
