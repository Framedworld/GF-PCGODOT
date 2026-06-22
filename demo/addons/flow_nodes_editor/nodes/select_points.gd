@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Select Points",
		"settings" : SelectPointsNodeSettings,
		"aliases" : ["Select Points"],
		"category" : "Filter",
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Filter inputs by the ratio.\nSo when ratio = 0.2, only 20% of the input points will appear in the output (picked randomly).\n" +
					"You can set an attribute name to control which points have more probability to be selected than others.\nWhen the input carries a per-point seed stream, selection is derived per point from it (deterministic, order-independent).",
	}

var _keys: PackedFloat32Array = PackedFloat32Array()
var _indices: Array = []                  # plain Array for sort_custom
var _uniform_idx: PackedInt32Array = PackedInt32Array()

func cmp_by_key(a: int, b: int) -> bool:
	# Comparator used by Array.sort_custom; uses member _keys
	return _keys[a] < _keys[b]

func uniform_sampling(n: int, k: int, rng: RandomNumberGenerator) -> PackedInt32Array:
	# Reuse buffer
	if _uniform_idx.size() != n:
		_uniform_idx.resize(n)
	for i in n:
		_uniform_idx[i] = i
	# Fisher–Yates
	for i in range(n - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := _uniform_idx[i]; _uniform_idx[i] = _uniform_idx[j]; _uniform_idx[j] = tmp
	var out := PackedInt32Array()
	out.resize(k)
	for t in k:
		out[t] = _uniform_idx[t]
	return out

# Efraimidis–Spirakis
## O(n log n) — simple & fast when k is not tiny
func weighted_sampling(weights: PackedFloat32Array, k: int, rng: RandomNumberGenerator) -> PackedInt32Array:
	var n := weights.size()
	k = clamp(k, 0, n)
	var out := PackedInt32Array()
	if n == 0 or k == 0:
		return out

	# Ensure buffers sized to n
	if _keys.size() != n:
		_keys.resize(n)
	if _indices.size() != n:
		_indices.resize(n)

	var all_zero := true
	for i : int in n:
		var w := weights[i]  # no maxf; your `if w > 0.0` handles negatives
		if w > 0.0:
			all_zero = false
			var u := rng.randf_range(1e-6, 1.0)  # avoid ln(0)
			_keys[i] = -log(u) / w                # smaller = better
		else:
			# This are 'big numbers' but we still want some noise
			_keys[i] = 1e6 + rng.randf_range(0.0, 1.0)
		_indices[i] = i

	if all_zero:
		return uniform_sampling(n, k, rng)

	# Sort indices by key (ascending)
	_indices.sort_custom(cmp_by_key)

	out.resize(k)
	for t : int in k:
		out[t] = int(_indices[t])
	return out


# Per-point seeded selection (UE parity): each point's sort key comes from a
# RNG seeded with point_seed ^ node_seed, so the result does not depend on
# point order and stays stable across upstream count changes.
func per_point_seeded_sampling(k: int, point_seeds, weights) -> PackedInt32Array:
	var n : int = point_seeds.size()
	k = clamp(k, 0, n)
	var out := PackedInt32Array()
	if n == 0 or k == 0:
		return out

	if _keys.size() != n:
		_keys.resize(n)
	if _indices.size() != n:
		_indices.resize(n)

	var prng := RandomNumberGenerator.new()
	var all_zero := weights != null
	for i : int in n:
		prng.seed = int(point_seeds[i]) ^ settings.random_seed
		var u := prng.randf_range(1e-6, 1.0)
		if weights == null:
			_keys[i] = u
		else:
			var w : float = weights[i]
			if w > 0.0:
				all_zero = false
				_keys[i] = -log(u) / w
			else:
				# This are 'big numbers' but we still want some noise
				_keys[i] = 1e6 + u
		_indices[i] = i

	if all_zero:
		return per_point_seeded_sampling(k, point_seeds, null)

	_indices.sort_custom(cmp_by_key)
	out.resize(k)
	for t : int in k:
		out[t] = int(_indices[t])
	return out

func _coerce_weights( container, attr_name : String ):
	if container is PackedFloat32Array:
		return container
	if container is PackedInt32Array or container is PackedByteArray:
		var weights := PackedFloat32Array()
		weights.resize(container.size())
		for i in container.size():
			weights[i] = float(container[i])
		return weights
	setError( "Weight attribute '%s' must be a numeric (Float/Int) stream" % attr_name )
	return null

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input( 0, ctx, "Input 'In'" )
	if in_data == null:
		return
	#in_data.dump( "Select.Input")
	var in_size := in_data.size()

	var attr_name = getSettingValue( ctx, "weight_name")
	var ratio : float = getSettingValue(ctx, "ratio")
	ratio = clamp( ratio, 0.0, 1.0 )

	var out_size : int = int(round(in_size * ratio))

	var rng := RandomNumberGenerator.new()
	rng.seed = settings.random_seed

	var weights = null
	if attr_name:
		var weight_stream = in_data.findStream( attr_name )
		if weight_stream == null:
			setError( "Input Weight Name %s not found" % [attr_name])
			return
		weights = _coerce_weights( weight_stream.container, attr_name )
		if weights == null:
			return

	var point_seeds = in_data.getContainerChecked( FlowData.AttrSeed, FlowData.DataType.Int )
	var has_point_seeds : bool = point_seeds != null and point_seeds.size() == in_size

	# No seed stream: synthesize per-point seeds from position so selection is
	# deterministic and order-independent (UE $Seed parity) rather than relying on
	# a global RNG whose result depends on point order/count.
	if not has_point_seeds:
		var positions = in_data.getVector3Container( FlowData.AttrPosition )
		if positions != null and positions.size() == in_size:
			var synth := PackedInt32Array()
			synth.resize( in_size )
			for i in in_size:
				synth[i] = FlowData.point_seed( positions[i], settings.random_seed )
			point_seeds = synth
			has_point_seeds = true

	var indices : PackedInt32Array
	if has_point_seeds:
		indices = per_point_seeded_sampling( out_size, point_seeds, weights )
	elif weights != null:
		indices = weighted_sampling( weights, out_size, rng )
	else:
		indices = uniform_sampling( in_size, out_size, rng )

	var out_data = in_data.filter( indices )
	set_output( 0, out_data )
