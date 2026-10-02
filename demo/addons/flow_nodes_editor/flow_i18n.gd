@tool
extends RefCounted
class_name FlowI18n

const BUILTIN_DOMAIN := "__flow__"
const LOCALE_DIR := "res://addons/flow_nodes_editor/locale"

static var node_translation_enabled := true
static var _external_domains: Array[String] = []
static var _locale_directories := {}
static var _message_cache := {}


static func t(message: String) -> String:
	var locale := _current_locale_key()
	var external_message = _external_message(message, locale)
	if external_message != null:
		return str(external_message)
	var builtin_messages := _messages_for_domain(BUILTIN_DOMAIN, locale)
	return str(builtin_messages.get(message, message))


static func tn(message: String) -> String:
	if node_translation_enabled:
		return t(message)
	return message


static func trf(message: String, values: Array) -> String:
	return t(message) % values


static func count(value: int, label: String) -> String:
	return t("%d %s") % [value, t(label)]


static func set_node_translation_enabled(enabled: bool) -> void:
	node_translation_enabled = enabled


static func is_node_translation_enabled() -> bool:
	return node_translation_enabled


static func register_external_locale_directory(domain: String, locale_directory: String) -> void:
	var normalized_domain := domain.strip_edges()
	if normalized_domain.is_empty():
		return
	var normalized_directory := locale_directory.strip_edges()
	if normalized_directory.is_empty():
		return
	_ensure_builtin_locale_directory()
	_locale_directories[normalized_domain] = normalized_directory
	_message_cache.erase(normalized_domain)
	if not _external_domains.has(normalized_domain):
		_external_domains.append(normalized_domain)


static func unregister_external_locale_directory(domain: String) -> void:
	var normalized_domain := domain.strip_edges()
	if normalized_domain.is_empty():
		return
	_locale_directories.erase(normalized_domain)
	_message_cache.erase(normalized_domain)
	_external_domains.erase(normalized_domain)


static func reload_locale_files() -> void:
	_message_cache.clear()


static func _external_message(message: String, locale: String) -> Variant:
	_ensure_builtin_locale_directory()
	for domain in _external_domains:
		var domain_messages := _messages_for_domain(domain, locale)
		if domain_messages.has(message):
			return domain_messages[message]
	return null


static func _messages_for_domain(domain: String, locale: String) -> Dictionary:
	_ensure_builtin_locale_directory()
	if not _locale_directories.has(domain):
		return {}
	if not _message_cache.has(domain):
		_message_cache[domain] = {}
	var domain_cache: Dictionary = _message_cache[domain]
	if domain_cache.has(locale):
		return domain_cache[locale]
	var messages := _load_locale_messages(str(_locale_directories[domain]), locale)
	domain_cache[locale] = messages
	return messages


static func _load_locale_messages(locale_directory: String, locale: String) -> Dictionary:
	var path := locale_directory.path_join(locale + ".json")
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_warning("FlowI18n locale file is not a dictionary: " + path)
		return {}
	var root: Dictionary = parsed
	if root.has("flow") and root["flow"] is Dictionary:
		return _string_dictionary(root["flow"])
	if root.has("messages") and root["messages"] is Dictionary:
		return _string_dictionary(root["messages"])
	return _string_dictionary(root)


static func _string_dictionary(messages: Dictionary) -> Dictionary:
	var result := {}
	for key in messages.keys():
		result[str(key)] = str(messages[key])
	return result


static func _current_locale_key() -> String:
	var locale := TranslationServer.get_locale()
	# Named through Engine's singleton table: exported builds lack EditorInterface
	# and would fail to parse a direct reference, even behind is_editor_hint().
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		var ei : Object = Engine.get_singleton(&"EditorInterface")
		var editor_settings : Object = ei.call("get_editor_settings")
		if editor_settings and editor_settings.has_setting("interface/editor/editor_language"):
			var editor_locale := String(editor_settings.get_setting("interface/editor/editor_language"))
			if not editor_locale.is_empty():
				locale = editor_locale
	return _normalize_locale(locale)


static func _normalize_locale(locale: String) -> String:
	var normalized := locale.strip_edges().to_lower().replace("-", "_")
	var is_chinese := (
		normalized == "zh"
		or normalized.begins_with("zh_cn")
		or normalized.begins_with("zh_hans")
		or normalized.begins_with("zh_sg")
	)
	if is_chinese:
		return "zh_CN"
	if normalized.begins_with("en"):
		return "en"
	return normalized


static func _ensure_builtin_locale_directory() -> void:
	if not _locale_directories.has(BUILTIN_DOMAIN):
		_locale_directories[BUILTIN_DOMAIN] = LOCALE_DIR
