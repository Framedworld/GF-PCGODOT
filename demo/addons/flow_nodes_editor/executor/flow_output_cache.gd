@tool
class_name FlowOutputCache
extends RefCounted

## Element output cache (Unreal's FPCGGraphCache), opt-in through
## FlowGraphNode3D.output_cache (EvaluationContext meta
## FlowExecutor.OUTPUT_CACHE_META).
##
## Only elements FlowNodeTraits marks cacheable are stored. The key is built
## from the node template, every stored settings value after overrides and
## bindings, the graph seed (with the node's random_seed it gives the
## effective seed), whether the run is an owner-less editor preview, and for
## every connected input the content of every bulk the element reads
## (FlowData.Data.content_hash plus size and stream count). Resources referenced
## by settings take part by identity: editing a resource in place (a Curve, a
## Mesh) while regenerating with the cache on needs FlowOutputCache.clear().
##
## Entries hold copies of the outputs and hits hand out copies again
## (Data.duplicate()), because downstream elements may mutate what they get.
## Errors a cached element raised are replayed through setError on a hit, so
## FlowNodeIO.last_errors is the same with and without the cache.
##
## The cache is process-wide and shared by every graph and component; it is
## bounded (max_entries, least recently used evicted first) and thread-safe.

## Maximum number of cached element runs.
static var max_entries : int = 1024
## Lookups that found an entry / did not.
static var hits : int = 0
static var misses : int = 0

## EvaluationContext meta: Data instance id -> fingerprint, so each produced
## Data is hashed once per evaluation however many consumers read it.
const FINGERPRINT_MEMO_META := &"flow_output_cache_fingerprints"
## Element meta: the settings part of the key, precomputed by FlowExecutor
## from the compiled graph when no override or binding changed the settings.
const SETTINGS_KEY_META := &"flow_output_cache_settings_key"

static var _entries : Dictionary = {}   # key Array -> { "bulks", "fingerprints", "errors" }
static var _mutex := Mutex.new()
static var _settings_props : Dictionary = {}   # settings script id -> PackedStringArray

## Empties the cache and resets the counters.
static func clear() -> void:
	_mutex.lock()
	_entries.clear()
	hits = 0
	misses = 0
	_mutex.unlock()

## Number of cached element runs.
static func size() -> int:
	_mutex.lock()
	var count := _entries.size()
	_mutex.unlock()
	return count

## Runs `node` (already preExecute'd) through the cache: on a hit its generated
## bulks become copies of the cached ones and its errors are replayed; on a miss
## it runs and the result is stored.
static func run_cached(node : FlowNodeBase, ctx : FlowData.EvaluationContext, instances : Dictionary) -> void:
	var key := key_for(node, ctx, instances)
	_mutex.lock()
	var entry = _entries.get(key, null)
	if entry != null:
		hits += 1
		# Most recently used last.
		_entries.erase(key)
		_entries[key] = entry
	else:
		misses += 1
	_mutex.unlock()

	var memo = ctx.get_meta(FINGERPRINT_MEMO_META) if ctx.has_meta(FINGERPRINT_MEMO_META) else null
	if entry != null:
		node.generated_bulks = _copy_bulks(entry.bulks)
		node.num_generated_bulks = node.generated_bulks.size()
		if memo is Dictionary:
			_remember_fingerprints(memo, node.generated_bulks, entry.fingerprints)
		for message in entry.errors:
			node.setError(message)
		return

	# Miss: run with the element's errors captured so a later hit can replay them.
	var outer_log = node._error_log
	var captured : Array = []
	node._error_log = captured
	node.run(ctx)
	node._error_log = outer_log
	var messages : Array = []
	for record in captured:
		messages.append(record.message)
	if outer_log is Array:
		FlowNodeBase._error_log_mutex.lock()
		outer_log.append_array(captured)
		FlowNodeBase._error_log_mutex.unlock()
	var fingerprints := []
	for bulk in node.generated_bulks:
		var bulk_fingerprints := []
		if bulk is Array:
			for data in bulk:
				bulk_fingerprints.append(_fingerprint(data, memo))
		fingerprints.append(bulk_fingerprints)
	var stored := { "bulks": _copy_bulks(node.generated_bulks), "fingerprints": fingerprints, "errors": messages }
	_mutex.lock()
	_entries[key] = stored
	# A negative capacity behaves like zero: without the emptiness check this
	# loop would index an empty key array and never end.
	while not _entries.is_empty() and _entries.size() > max_entries:
		_entries.erase(_entries.keys()[0])
	_mutex.unlock()

## Cache key of `node` in this evaluation (see the class description).
static func key_for(node : FlowNodeBase, ctx : FlowData.EvaluationContext, instances : Dictionary) -> Array:
	var memo = ctx.get_meta(FINGERPRINT_MEMO_META) if ctx.has_meta(FINGERPRINT_MEMO_META) else null
	var inputs_signature := []
	for conn in node.deps:
		if conn.get("virtual_variable", false):
			inputs_signature.append([ -1, str(conn.from_node) ])
			continue
		var src = instances.get(conn.from_node)
		var bulks_signature := []
		if src != null:
			for bulk in src.generated_bulks:
				var data = bulk[conn.from_port] if conn.from_port < bulk.size() else null
				bulks_signature.append(_fingerprint(data, memo))
		inputs_signature.append([ int(conn.to_port), int(conn.from_port), bulks_signature ])
	var settings_key = node.get_meta(SETTINGS_KEY_META) if node.has_meta(SETTINGS_KEY_META) else settings_values(node.settings)
	return [
		node.node_template,
		settings_key,
		ctx.seed,
		FlowNodeBase.is_ownerless_preview(ctx),
		inputs_signature,
	]

## Content fingerprint of one input Data (or null).
static func data_fingerprint(data) -> Array:
	if not (data is FlowData.Data):
		return [ typeof(data) ]
	return [ data.content_hash(), data.size(), data.streams.size(), data.data_attrs.size() ]

# data_fingerprint, memoized per evaluation by Data instance.
static func _fingerprint(data, memo) -> Array:
	if not (memo is Dictionary) or not (data is FlowData.Data):
		return data_fingerprint(data)
	var id : int = data.get_instance_id()
	_mutex.lock()
	var known = memo.get(id, null)
	_mutex.unlock()
	if known != null:
		return known
	var fingerprint := data_fingerprint(data)
	_mutex.lock()
	memo[id] = fingerprint
	_mutex.unlock()
	return fingerprint

static func _remember_fingerprints(memo : Dictionary, bulks : Array, fingerprints : Array) -> void:
	_mutex.lock()
	for b in range(mini(bulks.size(), fingerprints.size())):
		var bulk = bulks[b]
		for p in range(mini(bulk.size(), fingerprints[b].size())):
			if bulk[p] is FlowData.Data:
				memo[bulk[p].get_instance_id()] = fingerprints[b][p]
	_mutex.unlock()

## Every stored settings value, in property order (deep copies, so later edits
## of a settings container never change a stored key).
static func settings_values(settings : Resource) -> Array:
	if settings == null:
		return []
	var script = settings.get_script()
	var script_id : int = script.get_instance_id() if script != null else 0
	_mutex.lock()
	var props = _settings_props.get(script_id, null)
	_mutex.unlock()
	if props == null:
		props = PackedStringArray()
		for prop in settings.get_property_list():
			if (prop.usage & PROPERTY_USAGE_STORAGE) == 0:
				continue
			if FlowNodeAssets.discarded_props.has(prop.name):
				continue
			props.append(prop.name)
		_mutex.lock()
		_settings_props[script_id] = props
		_mutex.unlock()
	var values := []
	for prop_name in props:
		var value = settings.get(prop_name)
		if value is Array or value is Dictionary:
			value = value.duplicate(true)
		values.append(value)
	return values

static func _copy_bulks(bulks : Array) -> Array:
	var copies := []
	for bulk in bulks:
		var bulk_copy := []
		if bulk is Array:
			for data in bulk:
				bulk_copy.append(data.duplicate() if data is FlowData.Data else data)
		copies.append(bulk_copy)
	return copies
