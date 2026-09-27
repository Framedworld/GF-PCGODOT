# P0 Runtime API Contract

This is the binding spec for the first implementation round from
[PCG_SYSTEM_REVIEW.md](PCG_SYSTEM_REVIEW.md) §3. Every implementation agent and both
game migration plans target exactly these names and semantics. Anything not listed
here keeps its current behaviour.

Precedence for a node setting value at evaluation time, highest first:

1. a wired parameter port (`getSettingValue` reads the connected stream)
2. a per-instance override (`FlowGraphNode3D.overrides`)
3. a `$param` binding (`NodeSettings.bindings`)
4. the value saved in the graph resource

Back-compat rule: with `seed == 0`, no overrides, no bindings and no new calls, every
existing graph produces byte-identical output.

---

## 1. `FlowGraphNode3D` (`flow_node.gd`)

```gdscript
@export var graph : FlowGraphResource            # unchanged
@export var args : Dictionary = {}               # unchanged: graph input values
@export var seed : int = 0                       # graph seed; 0 = legacy (per-node seeds only)
@export var params : Dictionary = {}             # baseline runtime_params for every evaluation
@export var overrides : Dictionary = {}          # "node_name/property" -> value   (see §4)
@export var generate_on_ready : bool = true      # replaces the unconditional execute() in _ready
@export var transient_output : bool = false      # spawned nodes get owner = null (never saved into the scene)
@export var async_generation : bool = false      # unchanged
@export var frame_budget_ms : float = 4.0        # unchanged

signal generated(outputs : Dictionary)           # after every sync or async generation
signal cleaned_up

var last_outputs : Dictionary = {}               # outputs of the most recent generation

func generate(inputs : Dictionary = {}, extra_params : Dictionary = {}) -> Dictionary
func generate_async(inputs : Dictionary = {}, extra_params : Dictionary = {}) -> void
func cleanup() -> void
func regenerate(inputs : Dictionary = {}, extra_params : Dictionary = {}) -> Dictionary
func is_generating() -> bool
func execute() -> void                            # kept; identical to generate() with defaults, ignores return
```

- `generate` builds the context via `FlowNodeIO.make_context(self, seed, merged_params)`
  where `merged_params = params.merged(extra_params, true)`, feeds
  `args.merged(inputs, true)` as the input map, runs `evaluate_graph`, stores
  `last_outputs`, emits `generated`, returns the outputs. Synchronous.
- `generate_async` is the existing time-sliced path; on completion it stores
  `last_outputs` and emits `generated`.
- `cleanup` frees every descendant node whose `flow_owner` meta belongs to this
  component (see §5) and emits `cleaned_up`. Safe to call when nothing was generated.
- `regenerate` = `cleanup()` then `generate(...)`.
- `_ready` calls `generate()` only when `generate_on_ready` is true and not in the editor.

## 2. `FlowData.EvaluationContext` (`flow_data.gd`)

```gdscript
var owner : FlowGraphNode3D          # MAY BE NULL
var eval_id : int = 0                # evaluation counter again; never a seed
var seed : int = 0                   # graph seed
var component_id : int = 0           # owner.get_instance_id() or 0
var graph : FlowGraphResource
var gedit_nodes_by_name : Dictionary
var runtime_params : Dictionary = {} # always contains "seed" mirrored from ctx.seed
var variables : Dictionary = {}
var overrides : Dictionary = {}      # see §4
```

### Seed derivation (in `FlowNodeBase.preExecute`)

```gdscript
var effective_seed := settings.random_seed
if ctx.seed != 0:
    effective_seed = int(hash([ctx.seed, settings.random_seed]) & 0x7fffffff)
rng.seed = effective_seed
```

Nodes must read `rng.seed` (or a new `func effective_seed() -> int` on `FlowNodeBase`)
instead of `settings.random_seed` when they build local RNGs or call
`FlowData.point_seed(pos, node_seed)`. Migrate every stock node that currently reads
`settings.random_seed` directly.

Nested evaluations: `subgraph` passes the parent `ctx.seed` through unchanged. `loop`
gives iteration `i` a child seed of `hash([ctx.seed, i]) & 0x7fffffff` when
`ctx.seed != 0`, otherwise 0.

## 3. `FlowNodeIO` (`flow_nodes_io.gd`)

```gdscript
static func make_context(owner : Node3D = null, seed : int = 0, params : Dictionary = {}) -> FlowData.EvaluationContext
static func evaluate(graph : FlowGraphResource, inputs : Dictionary = {}, seed : int = 0,
                     params : Dictionary = {}, owner : Node3D = null) -> Dictionary
static func evaluate_graph(graph, input_data_map, parent_ctx, runtime_params := {}, depth := 0) -> Dictionary   # unchanged signature
```

- `evaluate_graph` must work with `parent_ctx.owner == null`. Nodes that need an owner
  (spawners, `apply_on_actor`, scene scanners) call `setError("<Node> needs an owner
  node; generate through a FlowGraphNode3D or pass owner to FlowNodeIO.evaluate")` and
  pass their input through to output 0. No crash, no push_error spam beyond that one.
- `_build_evaluation_state` copies `seed`, `component_id` and `overrides` from the
  parent context into the child context.
- The input feed (`_build_evaluation_state`, both the specific-input and multi-port
  branches) copies `tags` in addition to `data_attrs` and `kind`.

## 4. Overrides and bindings

### Per-instance overrides

`FlowGraphNode3D.overrides` (and `EvaluationContext.overrides`) map
`"<node_name>/<property>"` to a value. In `_build_evaluation_state`, after
`dict_to_resource(saved_settings, instance.settings)` and before `refreshFromSettings`:

```gdscript
for key in ctx.overrides:
    var parts = key.split("/")
    if parts.size() == 2 and parts[0] == name and (parts[1] in instance.settings):
        instance.settings.set(parts[1], ctx.overrides[key])
```

Keys may also be prefixed with the graph's resource basename
(`"style_room_default:roomflt/min_value"`) to target a node inside a specific subgraph;
unprefixed keys apply in every graph of the evaluation tree. A key that matches no node
is a `push_warning` once per evaluation.

### `$param` bindings

`NodeSettings` gains, under "Common Settings":

```gdscript
@export var bindings : Dictionary = {}    # "property_name" -> "param_name"
```

Resolved in `_build_evaluation_state` right after overrides, lowest precedence:

1. `input_data_map[param_name]` (a `Data`): use `Data.first(param_name)`
2. `ctx.runtime_params[param_name]`
3. `ctx.variables[param_name]`

If found, `instance.settings.set(property, value)` with numeric coercion (int↔float);
if the resolved type cannot be assigned, `push_warning` and keep the saved value. If
the parameter is absent, keep the saved value silently (graphs must stay usable when
run without params, e.g. in the editor).

Editor: the settings inspector shows `bindings` as a plain Dictionary for this round.
No custom UI is required.

## 5. Generated-content ownership

Spawned subtree roots carry `flow_owner` meta. New value shape:

```gdscript
{ "component": ctx.component_id, "node": name }
```

`removeInstanced*` in every spawner and `FlowGraphNode3D.cleanup()` treat a match as
`component == ctx.component_id and node == name` (spawner) or
`component == self.get_instance_id()` (cleanup). Both still accept the legacy String
form (matched by node name only) so scenes saved before this change clean up.

When `ctx.owner != null and ctx.owner.transient_output`, spawned nodes get no `owner`
so they are never serialised into the scene. The editor's `removeGeneratedNodes` keeps
working because it matches on meta presence, not owner.

## 6. Boundary data and helpers (`flow_data.gd`, `output.gd`)

`output.gd` copies `data_attrs`, `tags` and `kind` from its input onto the Data it
emits. `Data.first`, `Data.container` and the `@data.` selector all keep working across
subgraph and component boundaries as a result.

```gdscript
# FlowData.Data
static func scalar(name : String, value, data_type : DataType = DataType.Invalid) -> Data
    # one-element stream `name`; type inferred via FlowNodeBase.getFlowDataTypeFromObject when Invalid
func first(name : String, default = null)          # element 0 of stream `name` (or @data.<name>), else default
func container(name : String)                      # the packed container / Array, or null
func set_data_attr(name : String, value, data_type : DataType = DataType.Invalid) -> void
func get_data_attr(name : String, default = null)
```

`first`/`container` accept every selector form `findStream` accepts (`@last`,
`position.x`, `@data.foo`, `Yaw`).

## 7. Tests each agent must add

- Runtime API: `generate` returns outputs and emits `generated`; `cleanup` removes only
  this component's nodes; `seed` changes output and `seed = 0` reproduces legacy output
  bit for bit; `evaluate` works with `owner = null` and a spawner reports the documented
  error instead of crashing; `output` preserves tags/data_attrs/kind.
- Overrides/bindings: override beats binding beats saved value, wired port beats all;
  subgraph-prefixed override targets only that subgraph; missing param keeps saved value.
