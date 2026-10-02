# WP8: loop and subgraph parity

Status: implemented on the WP8 worktree branch. The golden suite and the seed-zero suite pass without regeneration. The full suite has 2231 cases, 0 failures, 2 skipped and the known 1 orphan (exit 101); the baseline was 2182. No existing test was edited.

## Summary

- **`loop` iteration modes** (`iteration_mode`). `Points` (the default) is today's behaviour, unchanged. `Entries` is Unreal's loop over a collection. `Partitions` groups points by an attribute value, sorted by key. `Chunks` takes N points per iteration.
- **Per-iteration runtime parameters.** Every iteration's graph evaluation gets `iteration_index`, `iteration_count` and `iteration_key`. In Entries and Partitions mode it also gets the per-data attributes of the iteration's data. They are ordinary `runtime_params`, so `$param` bindings and `ctx.runtime_params` can read them.
- **Key-derived seeds.** The iteration seed is `derive_seed(ctx.seed, key_seed(iteration_key))`. Adding or removing a partition does not reshuffle the others. For an int key this is exactly the old `hash([seed, index])`, and with graph seed 0 it stays 0 (legacy).
- **`output_mode`.** `Merge` (the default) concatenates the results as today. `Collection` emits one output entry (bulk) per iteration, so a downstream per-entry node runs once per iteration.
- **Dynamic subgraph.** `loop` and `subgraph` both take `graph_attribute`: a String resource path or a `FlowGraphResource` attribute that names the graph for each iteration (loop) or each input entry (subgraph). Graphs are resolved with `ResourceLoader` and run through the cached `FlowCompiledGraph`. A graph that cannot be used gives an error that names the iteration. `loop.on_graph_error` then skips that iteration or stops the loop.
- **Feedback** (`feedback_param_name`) works in every mode. The recursion guard and the error log behave as before. The error strings of the static path are unchanged.
- **`get_loop_index`** gains `source`. `Points` (the default) keeps today's per-point enumeration. `LoopIteration` returns the enclosing loop's iteration index in every mode. The new node **`get_loop_key`** returns the iteration key.
- **Editor hooks** still go through `widget_*`. `getMeta`, the title and the port rebuild follow the new settings (`onPropChanged`). Loop options that do not apply to the current mode are hidden in the inspector but still saved.

## Definitions (binding for graphs and tests)

### Entry

An **entry** is one `Data` object arriving on an input pin: one *bulk* in the executor's terms. A pin carries several entries when its source emitted several bulks. Examples are `partition`, a `loop` in Collection mode, or several links into pin 0. A node normally runs once per entry of its pin 0 (`FlowNodeBase.run`).

### Iterations per mode

| Mode | Runs | One iteration is | `iteration_key` | Order |
|---|---|---|---|---|
| `Points` (default) | once per input entry, as before | one point (`filter([i])`) | the point index `i` (int) | point order |
| `Entries` | **once for all entries of the Stream pin** (the loop overrides `run`) | one entry, unchanged | the entry index (int). With `key_attribute` set and found on the entry (element 0 of a stream, or a per-data attribute), that value instead. | entry (bulk) order |
| `Partitions` | once per input entry | the points whose `partition_attribute` value equals the key. Input order is kept inside the partition. The value is also set as a per-data attribute on the iteration's data, under the attribute name with any `@data.` prefix removed. | the attribute value (its own type) | ascending key, `LoopNode.key_less` |
| `Chunks` | once per input entry | `chunk_size` consecutive points (`chunk_size >= 1`). The last chunk may be short. | the chunk index (int) | point order |

- In Points, Partitions and Chunks mode `iteration_index` restarts for every input entry, as Points mode always did. `iteration_count` is the number of iterations of that run.
- The Stream pin's other inputs (extra graph inputs and the feedback initial value) are taken from the first entry in Entries mode.
- `partition_attribute` may name a point stream, including a broadcast stream of length 1, or a per-data attribute (`@data.x` or a plain name with no stream). A per-data attribute gives one partition. An empty `partition_attribute` is an error: "Loop Partitions mode needs a partition_attribute". An attribute that does not resolve is also an error: "Loop partition attribute not found in input: <name>". Both match the `partition` node's style.
- **Key ordering** (`key_less`): numbers (int, float, bool) compare numerically, and equal values are ordered by Variant type id (bool, int, float). Strings compare lexically. Vectors of one type (Vector2/3/4 and their int forms) compare component-wise. Any other pair, including mixed types, compares by `key_string(key)` and then by type id. `key_string` returns a String as is, a saved Resource as its path and anything else as `var_to_str`. The ordering is total and deterministic. One stream holds one type, so mixed types only arise from unusual data.

### Runtime parameters of an iteration

`runtime_params` passed to the iteration's `evaluate_graph`. They are local to that evaluation: they never leak back to the loop's own context.

| Name | Value |
|---|---|
| `iteration_index` | 0-based index of the iteration in this run |
| `iteration_count` | number of iterations in this run, including iterations later skipped for a graph error |
| `iteration_key` | see the table above |
| per-data attributes | Entries and Partitions only: every per-data attribute of the iteration's data, by name. In Partitions mode this includes the partition value under the attribute name. The three names above win on a clash. |

They resolve as bindings (`settings.bindings = {"cte_int": "iteration_index"}`) and nested subgraphs inherit them. In a nested loop the innermost loop's values win.

### Seeds

```gdscript
LoopNode.iteration_seed(loop_graph_seed, key) =
    0                                                   if loop_graph_seed == 0
    FlowNodeBase.derive_seed(loop_graph_seed, key_seed(key))   otherwise
LoopNode.key_seed(key) = key (int) | 1/0 (bool) | int(hash(key_string(key)) & 0x7fffffff)
```

`loop_graph_seed` is the `ctx.seed` the loop node runs with: the component seed, or an enclosing loop iteration's seed. With graph seed 0 every iteration runs with seed 0, so each body node uses its own `random_seed`. That is the legacy behaviour, and the seed-zero suite is unchanged. In Points mode the key is the int index, so seeds are bit-identical to before. Partition seeds depend only on the partition value, so removing one partition leaves the others' outputs unchanged (tested). Index keys in Chunks and Entries mode shift when an earlier iteration is removed (tested). Use `key_attribute` in Entries mode for stable per-entry seeds.

### Output

- **Merge** (default): the results concatenated in iteration order, with the historical code (`LoopNode.merge_results`). A null or empty result is skipped. A stream missing from some results is padded with default values. Per-data attributes and tags of the results are not carried, as before. With feedback, port 1 holds the final feedback.
- **Collection**: one output entry per iteration that ran, holding that iteration's result Data unchanged (an empty Data when the iteration produced none). With feedback, port 1 of each entry holds the feedback value after that iteration, so the last entry carries the final value. If no iteration ran (empty input, or every graph failed), the output is one empty entry, like the empty-input path, so downstream nodes still run once. A downstream node runs once per iteration. A graph `output` node keeps only the last entry, as for any multi-entry pin.

### Dynamic subgraph (`graph_attribute`)

- **Value:** element 0 of the stream, or the per-data attribute, named `graph_attribute` on the iteration's data (loop) or on the `Graph` pin's data (subgraph).
- **Resolution:** `FlowNodeIO.resolve_graph_reference(value, default_graph, memo)`.
  - A `FlowGraphResource` is used as is.
  - A String or StringName is loaded through `ResourceLoader`. Each path is loaded and validated once per node run (`memo`), and the loaded graph is kept referenced for the whole run.
  - An empty String means the node's `graph` (the default).
  - Anything else is an error.
- **Compiled graphs:** `FlowCompiledGraph.for_graph` caches the compiled form on the graph object. A graph used for many iterations or entries therefore compiles once (tested with `FlowCompiledGraph.compile_count`: 60 iterations over 2 path-named graphs compile at most 2 graphs, and further runs compile none while the caller keeps them loaded). A path-only graph that nothing else holds is freed after the run and compiles again on the next evaluation. No static graph cache was added: WP1 found that a static cache keeping graph resources alive changed golden determinism.
- **Loop errors:** "Loop iteration <i> (key <key>): <reason>". The reasons are "attribute '<name>' not found", "graph not found: <path>", "<path> is not a FlowGraphResource", "graph path is empty and no default graph is assigned", and the static validation messages with the graph's path appended (for example "Loop graph does not have input parameter: item (<path>)"). `on_graph_error = SkipIteration` (default) continues with the next iteration. `Stop` runs no further iterations and emits the results gathered so far.
- **Loop pins:** `graph` (optional with `graph_attribute`) still defines the loop's pins. Extra inputs and the feedback input are matched to each resolved graph's inputs by name.
- **Subgraph:** a `Graph` input pin is appended after the default graph's input pins.
  - If an entry has no data on the `Graph` pin, the first entry's data is used.
  - If the pin is not connected, the default graph runs.
  - Errors are "Subgraph entry <n>: <reason>". The entry's declared outputs are then emitted empty.
  - Inputs are fed by name from the default graph's pins and `param_overrides`. A dynamic graph's undeclared inputs take their own defaults. Outputs are matched by the default graph's output names.
  - With no default graph the node has only the `Graph` pin and no outputs, which suits side-effect-only subgraphs.
- **Editor:** with `graph_attribute` set, `computeSceneFingerprint` returns null (always re-evaluate on a scene change), because the graphs are only known at run time.

## Performance (`demo/tests/perf/loop_benchmark.gd`)

Scenario: a grid of 100 points feeds a loop (Points mode, Merge, 100 iterations) over a 20-node body (an input, 9 pairs of `add_attribute` and `math_op`, an output), which feeds an output. The graph is evaluated owner-less through `FlowNodeIO.evaluate`, 10 times after 3 warm-up runs. Godot 4.6 headless on the shared 4-core build container; single runs vary by about 10%.

| Code | ms per evaluation | ms per iteration |
|---|---|---|
| Pre-round evaluator (commit `17c4524`, parsing the body for every iteration) | 1175, 1130 (≈1150) | ≈11.5 |
| WP8 base (`45f78b3`, compiled graph from WP1) | 281, 272, 294, 292, 285 (median 285) | ≈2.85 |
| After WP8 (same scenario, Points mode) | 302, 293, 260, 287, 267 (median 287) | ≈2.87 |

- The compiled graph makes a loop iteration about 4× cheaper than before the round (1150 → 285 ms).
- WP8 adds no measurable cost. Interleaved runs of the base and WP8 checkouts were within noise of each other: 294/260, 292/287, 285/267 ms.
- In the same benchmark, Chunks (10 × 10 points) and Partitions (10 partitions) take 28 to 37 ms per evaluation. That is the same ≈2.8 to 3.7 ms per iteration: cost is per iteration, not per point.
- A Resource-attribute dynamic loop costs the same as a static one: 287 to 300 ms, with 1 compile over 13 evaluations.
- The remaining per-iteration cost is building 20 elements and running their bodies (see WP1.md, "Where the remaining time goes"). No loop-specific caching was added.

Threaded and cached equivalence: `tests/executor/loop_modes_executor_test.gd` evaluates a graph with three loops (Partitions + Collection, Chunks + Merge, Entries over `partition` entries) over a seed-dependent body that uses bindings, `get_loop_index` and `get_loop_key`. It runs sequentially, threaded, with the output cache cold and warm, and threaded with the cache, at graph seeds 0 and 1234. All runs give identical output summaries and error lists, and the warm cache has hits. This loop graph is in this test, not in the golden baseline.

## Tests

New suites (49 cases):
- `tests/nodes/loop_modes_test.gd` (28):
  - Points is the default and unchanged, runs once per entry, and passes its params.
  - Entries: every entry once; params; `key_attribute`; per-data attributes as bindable params; `execute()` without `run()`; inside a graph after `partition`.
  - Partitions: sorted by Int, String, Float and Vector keys, input order kept, data attribute stamped, per-data partition, error strings, bindable partition value.
  - Chunks: cutting with a short last chunk, `chunk_size` clamp.
  - Collection drives a downstream node once per iteration; Merge drives it once; empty Collection gives one empty entry.
  - Feedback in all four modes; running feedback per Collection entry.
  - Seed formula; partition removal leaves the others unchanged; index keys reshuffle; seed 0 equals evaluating the body directly with each node's own seed.
  - Key ordering, including mixed types.
  - `get_loop_index` and `get_loop_key` inside and outside a loop and in preview; the Points source unchanged; index and key in every mode.
- `tests/nodes/dynamic_subgraph_test.gd` (14):
  - Loop: Resource attribute per point; path per partition; empty path falls back to the default; missing graph names the iteration and is skipped; Stop policy; non-graph, invalid-body and absent-attribute errors; static errors unchanged; compile once.
  - A dynamic loop with feedback.
  - Subgraph: the Graph pin appears and disappears; runs a Resource-named graph; runs a path-named graph and falls back to the default; missing graph names the entry; static error unchanged.
- `tests/executor/loop_modes_executor_test.gd` (7):
  - Threaded and cache equivalence (above); iteration streams in the outputs.
  - Widgets: loop title and ports per mode and feedback through `FlowNodeWidget.onPropChanged`; the subgraph Graph pin rebuild; hidden-but-saved mode options; `get_loop_*` widgets build.
  - Traits rows.

Not verified headless (needs a manual editor check):
- inspector hiding of `partition_attribute`, `chunk_size` and `key_attribute` per mode (the property list is tested, not the inspector UI);
- the attribute dropdowns for those settings (`_get_attribute_selector_props`);
- double-clicking a dynamic loop or subgraph opens the default `graph`.

## Dictionary rows (for COMING_FROM_UNREAL_PCG.md, Control Flow table)

| UE node | Here | Status | Notes |
|---|---|---|---|
| Loop | `loop` | 1:1 | `iteration_mode`: `Points` (per point, default), `Entries` (per data entry on the pin; Unreal's loop over a collection), `Partitions` (per distinct attribute value, sorted), `Chunks` (N points). Iterations get `iteration_index`, `iteration_count`, `iteration_key` (and per-data attributes) as runtime params, usable from bindings. Iteration seed derives from the graph seed and the key. `output_mode`: `Merge` or `Collection` (one output entry per iteration). |
| Loop (feedback pins) | `loop.feedback_param_name` | 1:1 | One feedback parameter, threaded through iterations in every mode. In Collection mode each output entry carries the feedback after its iteration. |
| Get Loop Index | `get_loop_index` with `source = LoopIteration` | 1:1 | The default `source = Points` is the historical per-point enumeration (closer to `$Index`). |
| (no direct UE node) | `get_loop_key` | new | The current iteration's key: the point, entry or chunk index, or the partition value. |
| Subgraph (dynamic graph override) | `subgraph.graph_attribute`, `loop.graph_attribute` | 1:1 | A String path or Graph attribute picks the graph per entry (subgraph) or per iteration (loop). `graph` is the default and defines the pins. Resolved graphs use the compiled-graph cache. |
| Partition then Loop | `loop` in `Partitions` mode, or `partition` → `loop` in `Entries` mode | 1:1 | |

Concept rows (top dictionary table):

| In Unreal PCG | Here |
|---|---|
| **Loop over a collection of data** | **`loop` with `iteration_mode = Entries`**: one iteration per data entry (bulk) on the Stream pin. |
| **Loop index / loop data attributes** | **runtime params `iteration_index`, `iteration_count`, `iteration_key`** plus the iteration data's per-data attributes. Read them with `$param` bindings, `get_loop_index` (`source = LoopIteration`) or `get_loop_key`. |

Corrections to existing rows:
- "Multi-data on a pin" (concept table): replace "and `loop` iterates them" with "and `loop` iterates them in `Entries` mode (other modes run per entry)".
- Seed row (`FlowGraphNode3D` table): replace "loop iteration *i* gets `derive_seed(seed, i)`" with "a loop iteration gets `derive_seed(seed, key_seed(iteration_key))`, the same value as before for point and chunk indices, and stable per partition value".
- The current "Loop" row says "Runs a subgraph per data/entry". That was not true before WP8 (it ran per point). Replace it with the row above.

## nodes_reference rows

| Node | Source | Description |
|---|---|---|
| **Get Loop Key** | [get_loop_key.gd](../nodes/get_loop_key.gd) | Writes the enclosing Loop iteration's key (point, entry or chunk index, or partition value) |

Updated rows:

| Node | Source | Description |
|---|---|---|
| **Get Loop Index** | [get_loop_index.gd](../nodes/get_loop_index.gd) | Source Points (default): a sequential index per incoming point. Source Loop Iteration: the enclosing Loop's iteration index |
| **Loop** | [loop.gd](../nodes/loop.gd) | Runs a graph once per iteration of Stream: per point, per data entry, per attribute partition or per chunk of points; merged or one output entry per iteration |
| **Subgraph** | [subgraph.gd](../nodes/subgraph.gd) | Evaluates a nested graph inside this node; optionally the graph named by an attribute (`graph_attribute`) per entry |

## DEPRECATIONS rows (section 2, changed semantics)

| Node / API | Before | Now | Since |
|---|---|---|---|
| `loop` body evaluations | Ran with no loop runtime params | Every iteration, Points mode included, gets runtime params `iteration_index`, `iteration_count` and `iteration_key`. A binding or node in a loop body that reads a runtime param of one of those names now sees the iteration value instead of falling back to the saved value or the graph-input default. Graphs that do not use those names produce identical output. | WP8 |
| `get_loop_index` execution traits | Pure (threadable, cacheable) | Main thread, not cacheable: the new `LoopIteration` source reads `ctx.runtime_params`, which the output-cache key does not include. Output is unchanged; it is only no longer cached or run on a worker thread. | WP8 |
| `LoopNode.iteration_seed(seed, index : int)` | Index only | `iteration_seed(seed, key)` takes any iteration key. The value for an int index is unchanged. | WP8 |
| `loop` / `subgraph` titles | Graph name only | A non-default mode adds a suffix (`Loop (body) [Partitions, Collection]`, `Subgraph (g) [@attr]`). Default settings keep the old title, including in error messages. | WP8 |
| `subgraph` pins with `graph_attribute` set | — | An extra `Graph` input pin is appended after the graph's input pins. Existing pin indices are unchanged. | WP8 |

Graph format (section 3): loop, subgraph and get_loop_index settings saved from the editor now include the new keys (`iteration_mode`, `partition_attribute`, `chunk_size`, `key_attribute`, `output_mode`, `graph_attribute`, `on_graph_error`; `graph_attribute`; `source`). Missing keys load as the defaults, which are today's behaviour. New settings were appended after the existing ones, so exposed-parameter port indices of saved graphs do not move.

## Deviations from PARITY_ROUND2.md

1. **`get_loop_index` "returns the index in every mode"** is opt-in through `source = LoopIteration`. The default must keep the per-point enumeration that existing graphs and tests rely on.
2. **Points, Partitions and Chunks iterate per input entry.** This keeps the historical per-entry execution: several entries on the Stream pin give several runs, each with its own `iteration_index` from 0. Only Entries mode spans all entries of the pin.
3. **Iteration seeds derive from `ctx.seed`** (the graph seed in effect for the loop), not from the loop node's own `random_seed`. This keeps Points mode bit-identical. Two loops in one graph with equal keys therefore share iteration seeds. Their body nodes still differ through their own `random_seed`.
4. **Per-data attributes become runtime params only in Entries and Partitions mode.** In Points and Chunks mode the iteration data's per-data attributes are those of the whole input, and exposing them would change bindings in existing Points-mode graphs.
5. **`subgraph` has no skip/stop setting.** It runs once per entry, so an unusable graph fails that entry (error and empty outputs) and the other entries still run.
6. **No cross-evaluation graph cache for path-named graphs**, as described under Dynamic subgraph.

## Files touched

All files are in WP8 ownership except as noted:
- `nodes/loop.gd`, `loop_settings.gd`, `subgraph.gd`, `subgraph_settings.gd`, `get_loop_index.gd`, `get_loop_index_settings.gd`.
- New `nodes/get_loop_key.gd` and `get_loop_key_settings.gd`.
- `flow_nodes_io.gd`: one additive static helper, `resolve_graph_reference`.
- `executor/flow_node_traits.gd`: own rows only (`get_loop_index` moved from pure to main thread; `get_loop_key` added).
- New tests and `tests/perf/loop_benchmark.gd`.
