# Runtime evaluator: hardening + resumable foundation

Scratch notes for the runtime evaluator work. Scope is limited to
`addons/flow_nodes_editor/flow_nodes_io.gd` and the `FlowGraphNode3D` runtime
host in `addons/flow_nodes_editor/flow_node.gd`. This covers two
PARITY_ROADMAP items:

- Engine-hardening: "Primitive graph-input args crash the runtime feed of
  `FlowGraphNode3D.execute()`; `Data`-typed inputs work."
- "Async / proximity runtime generation" — **stage 2 only** (time-slicing).
  Stage 3 (proximity sources) and HiGen partitioning are out of scope here.

## 1. Primitive graph-input fix

`FlowGraphNode3D.args` (and any `input_data_map` entry) may hold a raw primitive
(`int` / `float` / `bool` / `String` / `Vector3` / `Color`) instead of a
`FlowData.Data`. `_coerce_input_data(val, input_name)` wraps a supported
primitive into a single-row `Data` whose stream is named after the input param.

The bug: the wrapper resized the stream's container and then assigned the value
with `container[0] = val`. Primitive streams are backed by typed `Packed*Array`
(`PackedByteArray` for Bool, `PackedInt32Array` for Int, `PackedStringArray` for
String, `PackedVector3Array` for Vector, ...). Direct subscript assignment of a
raw `bool`/`int`/`String` into the wrong packed element type crashes or silently
coerces the value — the reported "primitive graph-input args crash the runtime
feed."

Fix: write through the typed writer instead —

    FlowData.Data.writeValue(container, 0, val, data_type)

This is exactly the path the generic-input **default-value** branch already used
(`evaluate_graph` writing `param.get_default_value()`), so the connected and the
default feeds now agree. The `Data`-typed path is untouched: `_coerce_input_data`
returns a `FlowData.Data` as-is before ever reaching the wrap branch, and falsy
primitives (`0`, `0.0`, `""`, `false`) remain valid (explicit `null`/type checks,
no truthiness test).

## 2. Resumable evaluator foundation (async stage 2)

`evaluate_graph` was one monolithic function: instance nodes → build deps →
topo-sort (with cycle detection) → build `EvaluationContext` → feed inputs →
execute ordered list → collect outputs → publish flow variables → free node
instances. It is now split into three static helpers that both the synchronous
and the resumable paths share verbatim:

- `_build_evaluation_state(graph, input_data_map, parent_ctx, runtime_params, depth) -> Dictionary`
  — phases 1 (instance/order/context/feed). Returns a state dict
  (`graph`, `parent_ctx`, `instances`, `node_list`, `ordered_nodes`, `ctx`),
  or `{}` if it bailed.
- `_execute_single_node(node, instances, graph, ctx)` — phase 2 for **one** node;
  byte-for-byte the body of the historical inner execution loop.
- `_finalize_evaluation(state) -> Dictionary` — phase 3 (collect outputs, publish
  flow variables, free node instances). Returns the outputs dict.

### API added

- `evaluate_graph(...) -> Dictionary` — **the default synchronous entry point,
  unchanged signature and behavior.** It now builds the state, loops
  `_execute_single_node` over every ordered node in one pass, and finalizes.
  Same phases, order, side effects, recursion guard (`depth > 20`), and return
  value as before. `subgraph`/`loop` nodes keep calling this; nested subgraphs
  run synchronously inside a single host step.

- `begin_evaluation(...) -> GraphEvaluation` — **opt-in resumable entry point.**
  Builds the state (phase 1) immediately and returns a `GraphEvaluation`.
  Returns `null` on the recursion-guard trip (mirrors `evaluate_graph`'s `{}`).

- `class GraphEvaluation extends RefCounted` — the resumable driver:
  - `step(budget_ms := 4.0) -> bool` — runs ordered nodes until `budget_ms` of
    wall-clock time (`Time.get_ticks_usec()`) is spent this call, then returns
    so the host can yield the frame. Resumes from where it left off next call.
    Node-level granularity: the budget is checked only **between** nodes, and at
    least one node always runs per call (a zero/tiny budget cannot deadlock; a
    single heavy node can overrun — acceptable, heavy nodes are native). When the
    last node finishes it auto-calls `_finalize_evaluation`, populates `outputs`,
    and returns `true`.
  - `is_done() -> bool`, `progress() -> int`, `node_count() -> int`,
    `outputs: Dictionary`, and `run_to_completion() -> Dictionary` (drains the
    rest synchronously, finalizing exactly once).

Because both paths call the **same** `_execute_single_node` and
`_finalize_evaluation`, topo sort, cycle detection, variable/runtime-param
publishing and node-instance freeing are guaranteed identical — there is a single
execution implementation, no sync/async drift.

## 3. Opt-in flag on `FlowGraphNode3D`

Two new exports on the runtime host:

- `@export var async_generation : bool = false`
- `@export var frame_budget_ms : float = 4.0`

`execute()`:

- `async_generation == false` (**default**): calls `evaluate_graph(...)` once,
  synchronously — byte-for-byte the historical path. Processing stays disabled.
- `async_generation == true`: flushes any in-flight evaluation, calls
  `begin_evaluation(...)`, stores the `GraphEvaluation`, and enables
  `_process`. `_process` calls `step(frame_budget_ms)` each frame and disables
  itself + clears the handle when `step` reports done. If `begin_evaluation`
  unexpectedly returns `null`, it falls back to the synchronous path so
  generation still happens.

Safety: `_ready()` calls `set_process(false)` up front (the script is `@tool`,
so `_process` would otherwise tick in the editor). `_exit_tree()` drains an
in-flight async evaluation via `run_to_completion()` so node instances are still
freed if the host leaves the tree mid-generation.

## Guarantee: default behavior is unchanged

With `async_generation = false` (the default), the runtime does exactly one
synchronous `evaluate_graph()` in `_ready()`, identical to before this change —
same ordering, same outputs, same variable publishing, same instance freeing.
The resumable machinery is reachable only behind the opt-in flag.

## Prerequisite for HiGen

This lays the prerequisite for the roadmap's "Hierarchical generation (Grid
Size)" / HiGen partitioning work: a time-sliced, resumable evaluator is what lets
per-cell evaluation be scheduled across frames instead of multiplying a one-shot
synchronous cost. Stage 3 (a `generation_source` marker + per-partition radius
regeneration) builds on this `GraphEvaluation` driver and the partition cell
iteration HiGen introduces.
