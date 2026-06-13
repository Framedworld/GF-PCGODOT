@tool
extends FlowNodeBase

# Grammar Expand (UE PCG parity: grammar-driven Subdivide Spline / Subdivide
# Segment expansion).
#
# Input  : segment/span points carrying a `length` attribute (e.g. from
#          subdivide_segment), plus position/rotation/size. Each input point is
#          treated as a span oriented along its local Z axis (size.z = length).
# Settings: a grammar string + a module table (symbol -> mesh, size, weight).
# Output : one point per expanded module, fitted along the span, carrying
#          `symbol`, `module_index` and (optionally) `mesh`, ready for
#          match_and_set / spawn_meshes.
#
# Grammar subset parsed (documented UE subset):
#   sequence            A B C            (whitespace / commas separate tokens)
#   tuple               [A,P]            symbol + behavior; behavior parsed, symbol selects
#   repetition          A*  /  A:N       * fills the span, :N repeats N times
#   weighted choice     {A,B} / {[A,P]:2,[B,P]:1}
#
# The parser is self-contained and defensive: any malformed grammar calls
# setError() with a clear message and never crashes.

const GrammarExpandSettings = preload("res://addons/flow_nodes_editor/nodes/grammar_expand_settings.gd")

# ---- AST node kinds (plain dictionaries to stay allocation-light) ----
# { kind = "module", symbol = String, behavior = String }
# { kind = "seq",    items = Array }
# { kind = "repeat", child = <node>, count = int (-1 means fill) }
# { kind = "choice", options = Array[{ node, weight }] }

func _init():
	meta_node = {
		"title" : "Grammar Expand",
		"settings" : GrammarExpandSettings,
		"ins" : [{ "label" : "Spans" }],
		"outs" : [{ "label" : "Modules" }],
		"aliases" : ["Grammar", "Subdivide Spline"],
		"category" : "Sampler",
		"tooltip" : "Expands a grammar string against a module table into per-module points\nfitted onto each input span. Ready for match_and_set / spawn_meshes.",
	}

# ======================================================================
# Tokenizer
# ======================================================================
class Tok:
	var type : String   # "sym", "[", "]", "{", "}", ",", "*", ":", "num", "eof"
	var value : String
	func _init(t : String, v : String = ""):
		type = t
		value = v

func _tokenize(src : String) -> Array:
	var toks : Array = []
	var i : int = 0
	var n : int = src.length()
	while i < n:
		var c : String = src[i]
		if c == " " or c == "\t" or c == "\n" or c == "\r":
			i += 1
			continue
		if c == "[" or c == "]" or c == "{" or c == "}" or c == "," or c == "*" or c == ":":
			toks.append(Tok.new(c))
			i += 1
			continue
		if c >= "0" and c <= "9":
			var num : String = ""
			while i < n and src[i] >= "0" and src[i] <= "9":
				num += src[i]
				i += 1
			toks.append(Tok.new("num", num))
			continue
		# identifier / symbol: letters, digits, underscore (but a leading digit
		# was already handled above as a number)
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_":
			var sym : String = ""
			while i < n:
				var cc : String = src[i]
				if (cc >= "a" and cc <= "z") or (cc >= "A" and cc <= "Z") or (cc >= "0" and cc <= "9") or cc == "_":
					sym += cc
					i += 1
				else:
					break
			toks.append(Tok.new("sym", sym))
			continue
		# Unknown character
		_parse_error = "Unexpected character '%s' at position %d" % [c, i]
		return []
	toks.append(Tok.new("eof"))
	return toks

# ======================================================================
# Recursive-descent parser
# ======================================================================
var _toks : Array = []
var _pos : int = 0
var _parse_error : String = ""

func _peek() -> Tok:
	return _toks[_pos]

func _advance() -> Tok:
	var t : Tok = _toks[_pos]
	if _pos < _toks.size() - 1:
		_pos += 1
	return t

func _parse_grammar(src : String):
	_parse_error = ""
	_toks = _tokenize(src)
	if _parse_error != "":
		return null
	_pos = 0
	var seq := _parse_sequence([])
	if _parse_error != "":
		return null
	if _peek().type != "eof":
		_parse_error = "Unexpected token '%s'" % _peek().type
		return null
	return seq

# Parse a sequence of postfix-modified primaries until one of `stop` token types
# (or eof) is hit. Commas between items are optional separators.
func _parse_sequence(stop : Array):
	var items : Array = []
	while true:
		var t : Tok = _peek()
		if t.type == "eof" or t.type in stop:
			break
		if t.type == ",":
			_advance()
			continue
		var prim = _parse_postfix()
		if _parse_error != "":
			return null
		if prim == null:
			break
		items.append(prim)
	return { "kind": "seq", "items": items }

# primary with optional postfix repetition (* or :N)
func _parse_postfix():
	var node = _parse_primary()
	if _parse_error != "":
		return null
	if node == null:
		return null
	var t : Tok = _peek()
	if t.type == "*":
		_advance()
		return { "kind": "repeat", "child": node, "count": -1 }
	if t.type == ":":
		_advance()
		var num : Tok = _peek()
		if num.type != "num":
			_parse_error = "Expected a number after ':'"
			return null
		_advance()
		var count : int = int(num.value)
		if count < 0:
			count = 0
		return { "kind": "repeat", "child": node, "count": count }
	return node

func _parse_primary():
	var t : Tok = _peek()
	if t.type == "sym":
		_advance()
		return { "kind": "module", "symbol": t.value, "behavior": "" }
	if t.type == "[":
		return _parse_tuple()
	if t.type == "{":
		return _parse_choice()
	# Nothing primary-like here.
	return null

# [symbol] or [symbol,behavior]
func _parse_tuple():
	_advance() # consume "["
	var sym : Tok = _peek()
	if sym.type != "sym":
		_parse_error = "Expected a symbol after '['"
		return null
	_advance()
	var behavior : String = ""
	if _peek().type == ",":
		_advance()
		var beh : Tok = _peek()
		if beh.type != "sym" and beh.type != "num":
			_parse_error = "Expected a behavior after ',' in tuple"
			return null
		behavior = beh.value
		_advance()
	if _peek().type != "]":
		_parse_error = "Expected ']' to close tuple"
		return null
	_advance()
	return { "kind": "module", "symbol": sym.value, "behavior": behavior }

# { option (, option)* } where option is a sequence with an optional :N weight.
func _parse_choice():
	_advance() # consume "{"
	var options : Array = []
	while true:
		var t : Tok = _peek()
		if t.type == "}":
			break
		if t.type == "eof":
			_parse_error = "Unterminated '{' choice"
			return null
		if t.type == ",":
			_advance()
			continue
		# An option is a single primary+postfix; capture an explicit :N as weight.
		var node = _parse_primary()
		if _parse_error != "":
			return null
		if node == null:
			_parse_error = "Empty option in choice"
			return null
		var weight : float = 1.0
		if _peek().type == ":":
			_advance()
			var num : Tok = _peek()
			if num.type != "num":
				_parse_error = "Expected a weight number after ':' in choice"
				return null
			_advance()
			weight = float(num.value)
			if weight < 0.0:
				weight = 0.0
		elif _peek().type == "*":
			# A '*' inside a choice option = fill-repeat that option.
			_advance()
			node = { "kind": "repeat", "child": node, "count": -1 }
		options.append({ "node": node, "weight": weight })
	if _peek().type != "}":
		_parse_error = "Expected '}' to close choice"
		return null
	_advance()
	if options.is_empty():
		_parse_error = "Empty choice '{}'"
		return null
	return { "kind": "choice", "options": options }

# ======================================================================
# Expansion: AST -> ordered list of symbol strings fitting a span length.
# ======================================================================
# module_sizes: Dictionary symbol -> footprint size (>0). Used to decide how
# many times a fill-repeat (`*`) runs so it tiles the span.

func _module_size(symbol : String, module_sizes : Dictionary) -> float:
	var s : float = module_sizes.get(symbol, 1.0)
	if s <= 0.0:
		s = 1.0
	return s

# Recursively flatten `node` into `out` (Array of symbol strings).
# remaining_len is how much span length is still free; used to bound `*` fills.
# rng drives weighted choice. Returns the total footprint size consumed.
func _expand_node(node : Dictionary, out : Array, remaining_len : float, module_sizes : Dictionary, prng : RandomNumberGenerator) -> float:
	match node.get("kind", ""):
		"module":
			var sym : String = node.symbol
			out.append(sym)
			return _module_size(sym, module_sizes)
		"seq":
			var used : float = 0.0
			for child in node.items:
				used += _expand_node(child, out, remaining_len - used, module_sizes, prng)
			return used
		"repeat":
			var child : Dictionary = node.child
			var count : int = node.count
			var used2 : float = 0.0
			if count >= 0:
				for _rep in range(count):
					used2 += _expand_node(child, out, remaining_len - used2, module_sizes, prng)
				return used2
			# Fill (`*`): repeat until the span is consumed. Bound iterations by
			# the smallest possible module footprint to guarantee termination.
			var guard : int = 0
			var max_iter : int = _fill_iteration_bound(remaining_len, module_sizes)
			while used2 < remaining_len - 0.000001 and guard < max_iter:
				var before : int = out.size()
				used2 += _expand_node(child, out, remaining_len - used2, module_sizes, prng)
				guard += 1
				if out.size() == before:
					break # produced nothing; avoid infinite loop
			return used2
		"choice":
			var options : Array = node.options
			var total_w : float = 0.0
			for opt in options:
				total_w += maxf(0.0, opt.weight)
			var picked : Dictionary
			if total_w <= 0.0:
				picked = options[prng.randi_range(0, options.size() - 1)]
			else:
				var roll : float = prng.randf() * total_w
				var acc : float = 0.0
				picked = options[options.size() - 1]
				for opt in options:
					acc += maxf(0.0, opt.weight)
					if roll <= acc:
						picked = opt
						break
			return _expand_node(picked.node, out, remaining_len, module_sizes, prng)
	return 0.0

func _fill_iteration_bound(remaining_len : float, module_sizes : Dictionary) -> int:
	var min_size : float = 1.0
	var first : bool = true
	for v in module_sizes.values():
		var fv : float = float(v)
		if fv <= 0.0:
			continue
		if first or fv < min_size:
			min_size = fv
			first = false
	if min_size <= 0.0:
		min_size = 1.0
	return maxi(1, int(remaining_len / min_size) + 4)

# ======================================================================
# Execute
# ======================================================================
func execute(ctx : FlowData.EvaluationContext):
	var in_data : FlowData.Data = require_input(0, ctx, "Input 'Spans'")
	if in_data == null:
		return

	if not (in_data.hasStream(FlowData.AttrPosition) and in_data.hasStream(FlowData.AttrRotation) and in_data.hasStream(FlowData.AttrSize)):
		setError("Input must be point data (position/rotation/size streams required)")
		return

	# Build the module table: symbol -> { size, weight, mesh }.
	var module_table : Dictionary = {}
	var module_sizes : Dictionary = {}
	for m in settings.modules:
		if m == null:
			continue
		var sym = m.get("symbol")
		if sym == null or str(sym) == "":
			continue
		var sym_str : String = str(sym)
		var sz = m.get("size")
		var size_val : float = float(sz) if sz != null else 1.0
		if size_val <= 0.0:
			size_val = 1.0
		var w = m.get("weight")
		var weight_val : float = float(w) if w != null else 1.0
		var mesh_val = m.get("mesh")
		module_table[sym_str] = { "size": size_val, "weight": weight_val, "mesh": mesh_val }
		module_sizes[sym_str] = size_val

	if module_table.is_empty():
		setError("Module table is empty — add GrammarModuleResourceData entries with a symbol")
		return

	# Parse the grammar once (the symbol sequence per span depends only on the
	# span length, but choices use a per-span seed for determinism).
	var grammar_src : String = str(settings.grammar).strip_edges()
	if grammar_src == "":
		setError("Grammar string is empty")
		return
	var ast = _parse_grammar(grammar_src)
	if _parse_error != "" or ast == null:
		setError("Grammar parse error: %s" % (_parse_error if _parse_error != "" else "invalid grammar"))
		return

	# Read input span streams.
	var spos := in_data.getVector3Container(FlowData.AttrPosition)
	var srot := in_data.getVector3Container(FlowData.AttrRotation)
	var ssize := in_data.getVector3Container(FlowData.AttrSize)
	var length_stream = in_data.findStream(settings.length_attribute)
	var seed_stream = in_data.findStream(FlowData.AttrSeed)
	var node_seed : int = settings.random_seed

	var num_spans : int = spos.size()

	var out_pos := PackedVector3Array()
	var out_rot := PackedVector3Array()
	var out_size := PackedVector3Array()
	var out_symbols := PackedStringArray()
	var out_module_idx := PackedInt32Array()
	var out_meshes : Array = FlowData.Data.newContainerOfType(FlowData.DataType.Resource)

	var stretch : bool = settings.fit_mode == GrammarExpandSettings.eFitMode.STRETCH

	for span_idx in range(num_spans):
		# Span length: prefer the length attribute, else fall back to size.z.
		var span_len : float = 0.0
		if length_stream != null and span_idx < length_stream.container.size():
			span_len = float(length_stream.container[span_idx])
		if span_len <= 0.0:
			span_len = ssize[span_idx].z
		if span_len <= 0.0:
			continue

		var center : Vector3 = spos[span_idx]
		var basis : Basis = FlowData.eulerToBasis(srot[span_idx])
		var axis : Vector3 = -basis.z # local forward (looking_at convention)
		var span_start : Vector3 = center - axis * (span_len * 0.5)

		# Per-span deterministic rng for choices.
		var span_rng := RandomNumberGenerator.new()
		if seed_stream != null and span_idx < seed_stream.container.size():
			span_rng.seed = (int(seed_stream.container[span_idx]) ^ node_seed) & 0x7fffffff
		else:
			span_rng.seed = (FlowData.point_seed(center, node_seed)) & 0x7fffffff

		# Expand the grammar into an ordered symbol list for this span.
		var symbols : Array = []
		_expand_node(ast, symbols, span_len, module_sizes, span_rng)
		if symbols.is_empty():
			continue

		# Compute footprint sizes and the fit scaling.
		var raw_total : float = 0.0
		var sizes_list : Array = []
		for sym in symbols:
			var msz : float = _module_size(sym, module_sizes)
			sizes_list.append(msz)
			raw_total += msz
		if raw_total <= 0.0:
			continue

		var scale : float = 1.0
		if stretch:
			scale = span_len / raw_total
		# CLIP: keep raw sizes; we drop modules overrunning the span below.

		var cursor : float = 0.0
		var module_idx : int = 0
		for i in range(symbols.size()):
			var sym : String = symbols[i]
			var fitted_len : float = sizes_list[i] * scale
			if not stretch:
				# CLIP: stop once a module would overrun the span.
				if cursor + fitted_len > span_len + 0.000001:
					break
			var module_center : Vector3 = span_start + axis * (cursor + fitted_len * 0.5)
			out_pos.append(module_center)
			out_rot.append(srot[span_idx])
			out_size.append(Vector3(settings.cross_section_size.x, settings.cross_section_size.y, fitted_len))
			out_symbols.append(sym)
			out_module_idx.append(module_idx)
			# Symbols absent from the module table contribute a null mesh (their
			# footprint already defaulted to 1.0 in _module_size).
			var entry = module_table.get(sym, null)
			out_meshes.append(entry.mesh if entry != null else null)
			cursor += fitted_len
			module_idx += 1

	# Assemble output.
	var num_points : int = out_pos.size()
	var out := FlowData.Data.new()
	out.addCommonStreams(num_points)
	var op := out.getVector3Container(FlowData.AttrPosition)
	var orot := out.getVector3Container(FlowData.AttrRotation)
	var osize := out.getVector3Container(FlowData.AttrSize)
	for i in range(num_points):
		op[i] = out_pos[i]
		orot[i] = out_rot[i]
		osize[i] = out_size[i]

	if settings.out_symbol_attribute.strip_edges() != "":
		out.registerStream(settings.out_symbol_attribute, out_symbols, FlowData.DataType.String)
	if settings.out_module_index_attribute.strip_edges() != "":
		out.registerStream(settings.out_module_index_attribute, out_module_idx, FlowData.DataType.Int)
	if settings.out_mesh_attribute.strip_edges() != "":
		# Only emit a mesh stream when at least one module supplied a mesh; an
		# all-null Resource stream is still valid and lets spawn_meshes fall back
		# to its default mesh, so we always register it for consistency.
		out.registerStream(settings.out_mesh_attribute, out_meshes, FlowData.DataType.Resource)

	# Density + per-point seed (UE parity).
	var sdensity := PackedFloat32Array()
	sdensity.resize(num_points)
	sdensity.fill(1.0)
	out.registerStream(FlowData.AttrDensity, sdensity, FlowData.DataType.Float)
	var sseed := PackedInt32Array()
	sseed.resize(num_points)
	for i in range(num_points):
		sseed[i] = FlowData.point_seed(op[i], node_seed)
	out.registerStream(FlowData.AttrSeed, sseed, FlowData.DataType.Int)

	set_output(0, out)
