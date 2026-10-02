@tool
extends RefCounted
class_name FlowGraphMigrations

## Upgrades serialized graph data (FlowGraphResource.data, clipboard JSON) from older
## format versions to CURRENT_VERSION.
##
## Called in three places only:
##   * FlowNodeIO.loadFromResource / loadFromResourceWithProgress (editor load; the
##     upgraded data replaces resource.data and the graph is marked dirty so the next
##     save writes CURRENT_VERSION),
##   * FlowNodeIO._build_evaluation_state (runtime; the resource is never written),
##   * FlowNodeIO.create_nodes_from_dict (clipboard paste).
##
## Data with no "version" key predates versioning and is treated as version 1.
## See "How to add a migration" in the addon README.

## Format version written by FlowNodeIO.nodes_as_dict.
const CURRENT_VERSION := 2

## Version assumed for data that carries no "version" key.
const UNVERSIONED := 1

## Per-version settings migrations. MIGRATIONS[v] upgrades data from version v - 1 to v
## and is applied to every graph whose version is lower than v, in ascending order.
##
##   MIGRATIONS[v] = {
##       "<node template>": {
##           "old_key": "new_key",        # rename a settings key (value kept)
##           "old_key": func(settings: Dictionary) -> Variant: ...,
##                                         # called when old_key is present; mutate
##                                         # `settings` in place or return a new
##                                         # Dictionary to replace it
##           "*": func(settings) -> Variant: ...,   # called for every node of the template
##       },
##       "*": { ... },                     # applies to every template
##   }
##
## A rename never overwrites a value already stored under new_key; the old key is
## dropped either way. A static var (not a const) so a Callable can be stored and so
## tests can install temporary entries.
static var MIGRATIONS : Dictionary = {
	# Version 2 introduces the migration mechanism itself; no settings changed.
	2: {},
}

static var _warned_future_version := false

## Returns the format version stored in `data` (UNVERSIONED when absent).
static func get_version(data: Dictionary) -> int:
	var raw = data.get("version", UNVERSIONED)
	if raw is int or raw is float or raw is String:
		var version := int(raw)
		return version if version > 0 else UNVERSIONED
	return UNVERSIONED

## True when migrate(data) would change anything (old version or aliased template).
static func needs_migration(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	var version := get_version(data)
	if version > CURRENT_VERSION:
		return false
	if version < CURRENT_VERSION:
		return true
	return _has_aliased_template(data)

## Upgrades `data` to CURRENT_VERSION. Returns `data` itself (same instance) when there
## is nothing to do, otherwise a deep copy with settings keys migrated, deprecated
## template names replaced through FlowNodeRegistry.template_aliases and
## `"version" = CURRENT_VERSION`. The input dictionary is never modified.
static func migrate(data: Dictionary) -> Dictionary:
	if data.is_empty():
		return data
	var version := get_version(data)
	if version > CURRENT_VERSION:
		if not _warned_future_version:
			_warned_future_version = true
			push_warning("Flow graph data has format version %d, newer than this addon (%d). Loading it as-is; update the addon." % [version, CURRENT_VERSION])
		return data
	if version == CURRENT_VERSION and not _has_aliased_template(data):
		return data

	var out: Dictionary = data.duplicate(true)
	var nodes = out.get("nodes", [])
	if nodes is Array:
		for target_version in range(version + 1, CURRENT_VERSION + 1):
			var table = MIGRATIONS.get(target_version, {})
			if table is Dictionary and not table.is_empty():
				for node_data in nodes:
					if node_data is Dictionary:
						_migrate_node_settings(node_data, table)
		for node_data in nodes:
			if node_data is Dictionary:
				_apply_template_alias(node_data)
	out["version"] = CURRENT_VERSION
	return out

static func _migrate_node_settings(node_data: Dictionary, table: Dictionary) -> void:
	var template := str(node_data.get("template", ""))
	var settings = node_data.get("settings", null)
	if not (settings is Dictionary):
		return
	var rule_sets: Array = []
	if table.has("*"):
		rule_sets.append(table["*"])
	if table.has(template):
		rule_sets.append(table[template])
	# Tables are keyed by the template's current name; also match graphs that still
	# store a deprecated name.
	var aliased := FlowNodeRegistry.resolve_template_alias(template)
	if aliased != template and table.has(aliased):
		rule_sets.append(table[aliased])
	for rules in rule_sets:
		if rules is Dictionary:
			settings = _apply_rules(settings, rules)
	node_data["settings"] = settings

static func _apply_rules(settings: Dictionary, rules: Dictionary) -> Dictionary:
	for old_key in rules.keys():
		var rule = rules[old_key]
		if old_key == "*":
			if rule is Callable:
				settings = _call_rule(rule, settings)
			continue
		if not settings.has(old_key):
			continue
		if rule is Callable:
			settings = _call_rule(rule, settings)
		elif rule is String or rule is StringName:
			var new_key := String(rule)
			if new_key.is_empty() or new_key == String(old_key):
				continue
			if not settings.has(new_key):
				settings[new_key] = settings[old_key]
			settings.erase(old_key)
	return settings

static func _call_rule(rule: Callable, settings: Dictionary) -> Dictionary:
	var result = rule.call(settings)
	if result is Dictionary:
		return result
	return settings

static func _apply_template_alias(node_data: Dictionary) -> void:
	var template := str(node_data.get("template", ""))
	var target := FlowNodeRegistry.alias_for_missing_template(template)
	if not target.is_empty():
		node_data["template"] = target

static func _has_aliased_template(data: Dictionary) -> bool:
	if not FlowNodeRegistry.has_template_aliases():
		return false
	var nodes = data.get("nodes", [])
	if not (nodes is Array):
		return false
	for node_data in nodes:
		if node_data is Dictionary:
			if not FlowNodeRegistry.alias_for_missing_template(str(node_data.get("template", ""))).is_empty():
				return true
	return false
