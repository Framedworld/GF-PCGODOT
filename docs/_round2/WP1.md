# WP1: executor architecture

Status: implemented on the WP1 worktree branch. The golden suite and the seed-zero suite pass without regeneration. The full suite has 1790 cases, 0 failures and 2 skipped (1741 before this package). The editor smoke harness passes for every golden graph. Threaded mode and the output cache reproduce the golden baseline exactly.

## Summary

- **`FlowNodeBase` is now a `RefCounted` runtime element** (`node.gd`). The 130 stock node scripts still `extends FlowNodeBase`. An evaluation creates fresh elements and drops them afterwards. There is nothing to `free()`. Elements never touch a `Control` or the scene tree for UI.
- **`FlowNodeWidget`** (`executor/flow_node_widget.gd`, a `GraphNode`) owns one element and hosts all of the node UI. It exposes the members and methods the editor used before by delegation.
- **`FlowCompiledGraph`** (`executor/flow_compiled_graph.gd`) parses a graph once. The parsed form lives on the graph object, and the graph is recompiled when `graph.data` or the node registry changes.
- **`FlowExecutor`** (`executor/flow_executor.gd`) is the only executor. It has three modes: synchronous, time-sliced and threaded. It also has two extension points, `node_filter` and `preseeded`. `FlowNodeIO.evaluate_graph`, `begin_evaluation`/`GraphEvaluation` and `evaluate_graph_snapshot` are thin wrappers over it.
- **`FlowNodeTraits`** (`executor/flow_node_traits.gd`) records `main_thread` and `cacheable` for every stock template. The values come from a central table and from meta flags; `meta_node` can override them. Unknown templates default to main thread and not cacheable.
- **Threaded mode** is opt-in through `FlowGraphNode3D.threaded`. Its output is identical to sequential, including the order of `last_errors`.
- **`FlowOutputCache`** (`executor/flow_output_cache.gd`) is opt-in through `FlowGraphNode3D.output_cache`. It is an LRU cache with hit and miss counters. Every hit returns copies. Its output is byte-identical to running the nodes.

## Performance (`demo/tests/perf/executor_benchmark.gd`)

Test machine: the 4-core Xeon 2.8 GHz build container, Godot 4.6 headless. "Before" is base commit `17c4524`; the pre-round code was re-measured in the same session from a `git archive` export. Each "after" figure is the median of three interleaved runs. The machine was shared with other agents, so single runs vary by about 15%.

| Scenario | Before | After, sequential | After, threaded | After, output cache on |
|---|---|---|---|---|
| A. 47-node graph (50 points, trivial nodes), 200 evaluations | 32.8 ms/eval | 10.6 ms (×3.1) | 13.2 ms (×2.5) | 6.3 ms (×5.2) |
| B. same graph as subgraph ×4 in one evaluation, 50 evaluations | 137.5 ms/eval | 43.0 ms (×3.2) | 53.3 ms (×2.6) | 27.4 ms (×5.0) |
| C. 4 compute-bound branches (900 points, `relax` ×5) | — | 230.8 ms | 80.0 ms (×2.9 vs sequential) | — |

**The 5× target is met only with the output cache on.** That case is repeated evaluation with unchanged inputs, which is what the cache is for. Without the cache, repeat evaluation is about 3.1 to 3.2× faster than the pre-round code, 1.6× short of the target.

Where the remaining time goes in scenario A (per evaluation, profiled):

| Phase | Time |
|---|---|
| Building elements and settings from the compiled graph | about 1.5 ms. Element `new()` with its `meta_node` and RNG: 0.45 ms. Settings `new()` with the replayed assignments: 0.42 ms. |
| Node bodies | about 7.4 ms. `expression` 2.6 ms (11 nodes; Godot `Expression` per point). `density_filter` 2.4 ms (11 nodes). `math_op` 1.0 ms. `add_attribute` 0.8 ms. `merge` 0.3 ms. `grid` 0.2 ms. `output` 0.1 ms. |
| Finalize | about 0.7 ms. This is mostly freeing the elements and the intermediate Data. |

The executor overhead that WP1 controls dropped from about 25 ms to about 2.5 ms. Getting past 5× without the cache would mean speeding up the node bodies: `Data.duplicate`/`filter` and per-point GDScript loops in `flow_data.gd` and the node scripts. Those files belong to other packages and to the "pure scripts need no edits" rule.

Threaded mode does not help scenarios A and B. Their elements create many small objects (Data, dictionaries, packed arrays), and that contends in the engine. Each wave also pays a pool round trip. It pays off on compute-bound branches (scenario C, ×2.9 on 4 cores). Group tasks are submitted as high priority. Low-priority tasks get only about 30% of the pool's threads, which on 4 cores is a single thread.

## How the design maps to the contract

| # | Requirement | Where |
|---|---|---|
| 1 | Element/widget split | `node.gd`, `executor/flow_node_widget.gd`, `executor/flow_reroute_widget.gd`. Delegated members: `settings`, `node_template`, `meta_node`, `deps`, `dependants`, `dirty`, `generated_bulks`, `num_generated_bulks`, `input_bulks`, `num_connected_bulks`, `inputs`, `err`, `args_ports_by_name`, `show_disconnected_inputs`, `eval_id`, `scene_fingerprint`, `has_scene_fingerprint`, `num_in_ports`, `num_out_ports`, `num_ports`, `rng`, `graph_seed`. Any other element member reads and writes through `_get`/`_set`. Delegated methods: `getMeta`, `getTitle`, `getLocalizedTitle`, `getTooltip`, `getExposedParams`, `exposedAsInputNode`, `onPropChanged`, `preExecute`, `run`, `execute`, `executedDisabled`, `setError`, `computeSceneFingerprint`, `get_bulk_output`, `get_bulk_input`, `get_input`, `get_optional_input`, `set_output`, `getSettingValue`, `effective_seed`, `get_deterministic_color`, `_get_category_hue`, `_get_meta_node_color`. |
| 2 | UI hooks | Documented at the top of `node.gd`: `widget_init`, `widget_ready`, `widget_gui_input`, `widget_exit_tree`, `widget_refresh`. Two more hooks were added: `widget_draw` (reroute draws itself) and `widget_script` (reroute needs a subclass for `_draw_port`). |
| 3 | `FlowCompiledGraph` | `FlowCompiledGraph.for_graph(graph)`. Invalidation is by `graph.data` identity plus content hash, and by `FlowNodeRegistry` version. **Deviation:** the instance is cached on the graph (`FlowGraphResource._flow_compiled`) instead of in a static dictionary. A static cache kept graph resources such as a NoiseTexture2D alive after their scene was freed, and that changed golden determinism for `demo_terrain_layers`. Run settings are rebuilt from the exact `dict_to_resource` writes recorded at compile time, not by `Resource.duplicate()`. In Godot 4.6, `duplicate()` shares arrays and dictionaries and calls every setter; replaying the writes is faster and reproduces the old path exactly. |
| 4 | `FlowExecutor` | `Mode.SYNCHRONOUS / TIME_SLICED / THREADED`, `node_filter`, `preseeded`. `begin()`, `step()`, `run()`, `finalize()`. The static phases are `build_state`, `execute_node`, `execute_element` and `finalize_state`. |
| 5 | `FlowNodeTraits` | Central table plus meta flags plus `meta_node["main_thread"]` / `["pure"]`. Table below. |
| 6 | Threaded mode | `FlowGraphNode3D.threaded`, which sets `FlowExecutor.THREADED_META` on the context. Audit below. |
| 7 | `FlowOutputCache` | `FlowGraphNode3D.output_cache`, which sets `FlowExecutor.OUTPUT_CACHE_META` on the context. |
| 8 | Editor parity and smoke harness | `demo/tests/editor/editor_smoke_harness_test.gd`. |
| 9 | Public API unchanged | `evaluate_graph`, `evaluate`, `make_context`, `begin_evaluation` (returns `GraphEvaluation` with `step`, `run_to_completion`, `is_done`, `progress`, `node_count`, `outputs`, and `_instances` / `_ordered` for existing tests), `evaluate_graph_snapshot`, `generate*` and `last_errors` keep their signatures and results. `_build_evaluation_state`, `_execute_single_node` and `_finalize_evaluation` keep working on the same state dictionary. |

## Element and widget: what changed for node authors

- Elements are `RefCounted`. **Calling `free()` on one is now an error.** Drop the reference instead.
- `name` is a plain `StringName` member. The widget keeps it equal to the `GraphNode` name.
- Elements talk to their widget through signals: `error_changed(message)`, `redraw_requested`, `refresh_requested` and `settings_replaced(old, new)`. The widget connects to them. The widget also watches the settings resource's `changed` signal. The element no longer does, so runtime elements never connect to anything.
- Compatibility shims stay on the element and forward to a bound widget. At runtime they do nothing. They are `getEditor()`, `initFromScript()`, `setupDrawDebug()`, `redrawUI()`, `refreshDebugMark()`, `refreshInspectMark()`, `setActivity()`, `setExecTime()`, and the empty `_ready()`, `_exit_tree()` and `_gui_input()` (kept so that `super._ready()` still parses).
- **`GraphNode`/`Control` API is gone from the element.** Examples are `title`, `size`, `set_slot_*`, `add_child`, `tooltip_text`, `modulate` and `queue_redraw`. A third-party node that used these must move that code into the `widget_*` hooks, where `widget` is the `GraphNode`. All stock nodes that did this were migrated: `input`, `output`, `reroute`, `loop`, `subgraph`, `get_variable`, `set_variable` and `grid_size`, plus `expression`, which set `size` inside `getTitle()`.
- `refreshFromSettings()` on the element now only asks a bound widget to refresh. Overrides that call `super.refreshFromSettings()` still work.

### UI hooks (documented at the top of `node.gd`)

| Hook | Called from | Used by |
|---|---|---|
| `widget_init(widget)` | end of `FlowNodeWidget.initFromScript()`, after the port rows are built | `input` and `output` (the "+ Add parameter" button), `reroute` (compact rows), `get_variable` (variable picker) |
| `widget_ready(widget)` | `FlowNodeWidget._ready()` | `input` and `output` (watch `in_params_changed`), `reroute` (size, mouse and selection flags) |
| `widget_gui_input(widget, event) -> bool` | start of `FlowNodeWidget._gui_input()`; returning `true` consumes the event | `loop`, `subgraph` (double-click opens the nested graph) |
| `widget_exit_tree(widget)` | `FlowNodeWidget._exit_tree()` | `input`, `output`, `loop`, `subgraph` |
| `widget_refresh(widget)` | end of every `FlowNodeWidget.refresh_ui()`, which is what `refreshFromSettings()` runs | `input` and `output` (slot colour), `set_variable` and `get_variable` (title, slot colour, picker), `grid_size` (title), `reroute`, `loop` and `subgraph` (watch the nested graph, rebuild ports), `expression` (shrink to fit) |
| `widget_draw(widget) -> bool` | the widget's `draw` callback; `true` replaces the default drawing | `reroute` |
| `widget_script() -> Script` | `FlowEditor.addNodeFromTemplate` | `reroute` (`FlowRerouteWidget` overrides `_draw_port`) |

### Editor changes, for review

`flow_editor.gd`:
- Every `FlowNodeBase` type annotation became `FlowNodeWidget`. Static helpers are still called as `FlowNodeBase.<name>`.
- `addNodeFromTemplate` creates the element from the registered script. It picks the widget class (`NODE_WIDGET_SCRIPT`, or the element's `widget_script()`) and binds the element before configuring the node. It no longer instances `node.tscn`. `node.tscn` now points at the widget script.
- `registerNodeType` and the filesystem hot reload no longer `free()` probe instances, because they are RefCounted. The hot swap uses `FlowNodeWidget.rebind_script(script)`, which creates a fresh element and keeps settings, name, template and ports. It then clears the `FlowNodeTraits` cache.
- `getEvalOrder` orders the elements with `FlowNodeIO.build_execution_order` and maps the result back to widgets. The new `get_element_map()` builds the evaluation context's `gedit_nodes_by_name`. That map now holds elements, because element code reads its sources from it. Every place that assigned the widget map to `ctx.gedit_nodes_by_name` now assigns `get_element_map()`, and `_begin_eval_graph` refreshes it.
- `_evaluate_graph_node` runs the node through `FlowExecutor.execute_element`, the same core as the runtime. Per-node dirty tracking, scratch bindings, inspector refresh, scene fingerprints and the exec-time badge are unchanged.
- `refreshVariableNodes` and `_is_multi_port_flow_node` call element-only methods through `node.element`.

`flow_nodes_io.gd` (editor parts):
- When loading or pasting, `create_nodes_from_dict*` now applies `_stabilize_missing_seed`, as the runtime always did. Before this, a node saved without `random_seed` previewed with the class default seed in the dock but generated with a stabilized seed at runtime. The smoke harness found this for `subgraph_dungeon_upper_level` (`grid_fill_bounds`). Saving such a graph from the dock now writes the stabilized seed. Runtime output does not change.

Other files:
- `data_inspector.gd`, `node_draw_debug.gd`, `connectors_row.gd` and `flow_graph_edit.gd` were retyped to `FlowNodeWidget`.
- `flow_variable_eval.gd`: `should_refresh_debug_draw` and `variable_name_from_node` accept an element or a widget.
- The dock's other behaviour is unchanged: dirty tracking, dependant expansion, scene fingerprints, debug draw, the inspector, exec-time badges, D/A hotkeys and collapse-to-subgraph.

**Not verified headless.** In a test run the dock's `_ready()` returns early, because `Engine.is_editor_hint()` is false. The harness therefore calls the same entry points directly (`loadFromResource`, `evalGraph`, `markAllNodesAsDirty`, settings edits and `onEditorSceneChanged`), and it builds a widget for every registered template. The following were not exercised and need a manual check in the editor:
- mouse interaction (`widget_gui_input`, selection, double-click into subgraphs),
- the drawing (`_on_draw`, `FlowRerouteWidget._draw_port`, exec-time badge),
- the EditorInterface inspector wiring and undo/redo,
- filesystem hot reload,
- the debug-draw MultiMesh in the 3D viewport,
- the data-inspector table UI,
- the connectors-options toggle,
- the `+ Add Input/Output Parameter` buttons.

## FlowCompiledGraph

- Each descriptor holds the name, template, node script, saved settings and saved `args_port`. After the first run it also holds a settings prototype, the recorded settings writes, the stabilized seed, traits, connection lists (virtual variable dependencies included) and an order signature.
- The first run fills the element-dependent parts from its own elements: settings class, traits, connections and execution order. Compiling therefore creates no extra element instances; the evaluator tests count probe instances.
- If a run's overrides or bindings change a setting the order depends on (`disabled`, `inspect_enabled`, `debug_enabled`, `variable_name`), that run orders itself on its own elements, as before.
- Compile errors (unknown template, unloadable script) are reported on every run, as before.

## FlowExecutor

- **Synchronous.** The ordered elements run in one call.
- **Time-sliced.** `step(budget_ms)` runs at least one element per call and finalizes after the last one. In this mode the top-level graph never runs threaded; nested subgraph and loop evaluations follow the context's `threaded` flag.
- **Threaded.** Each wave works in two phases:
  1. Main-thread elements whose dependencies are done run on the main thread, strictly in their sequential order relative to each other.
  2. All ready pure elements then run as one WorkerThreadPool group task, and the main thread waits. Pool tasks and main-thread elements never overlap.

  Every element's errors go to a private buffer, and the buffers are appended to the context log in sequential order at the end. Pool elements queue their `push_error` text, and the main thread prints it after the batch, because Godot calls every `Logger` on the thread that raised the error. Before a batch, Curve, Curve2D, Curve3D and Gradient resources in settings are baked or sorted on the main thread, because their lazy caches are not thread-safe. If an unresolvable dependency is left (a cycle that the sequential order tolerated), the remaining elements run sequentially.
- **`node_filter : Callable(element) -> bool`.** An element for which it returns false does not run and produces nothing.
- **`preseeded : Dictionary`** maps a node name to bulks (Array of Array of Data). The element does not run, and its `generated_bulks` become copies of those bulk arrays; the Data objects themselves are shared.
- **Statistics:** `FlowExecutor.pooled_element_count`, `FlowCompiledGraph.compile_count`, `FlowOutputCache.hits` and `FlowOutputCache.misses`.

## FlowNodeTraits table

| Traits | Templates |
|---|---|
| **main thread, not cacheable** (41) | `apply_on_actor`, `clip_paths`, `clip_points_by_polygon`, `compute_kernel`, `create_spline`, `create_surface_from_spline`, `debug`, `load_alembic_file`, `mesh_sampler`, `navigation_region_sampler`, `physics_overlap_query`, `physics_shape_sweep`, `point_from_mesh`, `point_from_player_pawn`, `points_from_gridmap`, `points_from_imported_scene`, `points_from_scene`, `points_from_tilemap`, `polygon_operation`, `projection`, `ray_cast`, `sample_mesh`, `sample_spline`, `sample_terrain_layers`, `scan_meshes`, `scan_nodes`, `scan_splines`, `spawn_meshes`, `spawn_nodes`, `spawn_scenes`, `split_splines`, `subdivide_segment`, `surface_sampler`, `texture_sampler`, `get_variable`, `set_variable`, `grid_size`, `input`, `loop`, `subgraph`, `print_string` |
| **threadable, not cacheable** (4) | `load_data_table`, `load_pcg_data_asset` (file content can change), `output`, `reroute` |
| **pure: threadable and cacheable** (85) | `add_attribute`, `add_tags`, `assets`, `attribute_filter_range`, `attribute_noise`, `attribute_random`, `attribute_rename`, `attribute_set_to_point`, `boolean`, `bounds_modifier`, `branch`, `build_rotation_from_up`, `combine_points`, `compose_vector`, `copy`, `copy_points`, `create_surface_from_polygon`, `curve_remap_density`, `data_table_row_to_attribute_set`, `decompose_vector`, `delete_tags`, `density_filter`, `density_remap`, `difference`, `distance`, `distance_to_density`, `dungeon_connect_rooms`, `dungeon_expand_rooms`, `dungeon_generator`, `dungeon_room_candidates`, `dungeon_walls_and_doors`, `duplicate_point`, `expression`, `filter`, `filter_data_by_attribute`, `filter_data_by_tag`, `filter_data_by_type`, `get_data_count`, `get_entries_count`, `get_loop_index`, `get_points_count`, `grammar_expand`, `grid`, `grid_boundary`, `grid_connect_points`, `grid_fill_bounds`, `intersection`, `make_bounds`, `make_vector`, `match_and_set`, `math_op`, `merge`, `merge_points`, `mutate_seed`, `noise`, `normal_to_density`, `partition`, `point_filter_range`, `point_neighborhood`, `point_offsets`, `point_to_attribute_set`, `random_color`, `reduce`, `relax`, `remap`, `remove_attribute`, `replace_tags`, `rotator_op`, `sample_points`, `sanity_check`, `select`, `select_multi`, `select_points`, `self_pruning`, `sequence_sample`, `size`, `snap_to_grid`, `sort`, `substract`, `switch`, `tags_mutate`, `transform`, `transform_points`, `union`, `volume_sampler` |
| **anything else** | Main thread, not cacheable. If `meta_node` has `scans_scene`, `queries_physics` or `is_final`: main thread, not cacheable. `meta_node["pure"] = true` makes a node cacheable and threadable; `meta_node["main_thread"]` pins it either way. |

`flow_node_traits_test.gd` fails if a stock template has no row, or if a row names a template that does not exist. **Packages that add nodes (WP2, WP3, WP4a, WP4b) must add their rows.** Until they do, new nodes stay main-thread and uncached, which is safe but slower.

The classification rules:
- **Main thread:** anything that reads live scene nodes (`Path3D`, `MeshInstance3D`, collision, GridMap), Mesh surface arrays or textures (RenderingServer); spawns; touches `ctx.variables` or `runtime_params`; runs a nested graph; or prints.
- **Not cacheable:** additionally, anything whose output depends on files or the scene.

## Thread-safety audit

Shared or static mutable state found in the runtime scripts, and how it is guarded:

| State | Risk in threaded mode | Guard |
|---|---|---|
| `load_pcg_data_asset._cache`, `parse_count`, `cache_hits` (static) | concurrent insert, erase and count | New static `Mutex` around every access; parsing happens outside the lock (small edit to a node script) |
| `sample_points.blue_noise_samples` (static, lazily built) | two threads building at once, or readers seeing a half-filled array | `Mutex` around the one-time build; the table is built into a local array and published whole (small edit) |
| `FlowNodeBase` error log (one Array shared by an evaluation tree) | concurrent `append` | Static `Mutex`; threaded mode also uses per-element buffers flushed in order |
| Node errors printed through `push_error` | Godot calls script `Logger`s (GdUnit's, test harness capture loggers) on the raising thread. One harness logger crashed ("double free or corruption") when node errors arrived from pool threads. | Pool elements queue their `Node.Err` text, and the main thread prints it after the batch |
| `FlowNodeTraits._cache`, `FlowOutputCache` entries, counters and per-script property lists, `FlowExecutor.pooled_element_count`, `FlowCompiledGraph` (stored on the graph) | concurrent lookup and insert | `Mutex` in each |
| `EvaluationContext` (`variables`, `runtime_params`, meta, `seed`, which `loop` changes around its nested call) | written by main-thread nodes | Pool tasks only read the context, and only while no main-thread element runs. Nodes that read `owner`, `variables` or `runtime_params` are main-thread in the table. |
| Curve, Curve2D, Curve3D and Gradient referenced from settings (lazy baked or sorted caches) | concurrent bake on first `sample` | Baked or sorted on the main thread before each pool batch (`_prewarm_shared_resources`) |
| Scene nodes inside Data streams (`node` NodePath streams, `MeshInstance3D`) | Node thread guards (`global_transform`) and live scene state | Every node that dereferences them is main-thread |
| Input Data shared between consumers | a consumer that mutates its input | A heuristic audit of the 85 pure scripts found no in-place writes to input Data. They duplicate, or read packed containers, which are copy-on-write. Writing into an input is now a documented contract violation. |
| `FlowNodeRegistry`, `FlowGraphMigrations`, `FlowI18n` statics | written at compile or editor time | Only touched on the main thread (compiling and the editor UI) |
| Native `GDKdTree`, `GDRTree`, `GDStreamUtils` | — | No static state in `native/src` |

## FlowOutputCache

- **Key:** the node template; every stored settings value after overrides and bindings (precomputed from the compiled graph when nothing was bound); the graph seed, which with `random_seed` gives the effective seed; the owner-less preview flag; and, for every connection, the per-bulk input fingerprint (`Data.content_hash()`, size, stream count, attribute count). Fingerprints are memoised per evaluation, so each Data is hashed once.
- **Entries** hold copies of the bulks, their fingerprints and the element's error messages. Hits hand out copies (`Data.duplicate()`) and replay the errors through `setError`.
- **Bounds and controls:** `FlowOutputCache.max_entries` (default 1024), least recently used first; `FlowOutputCache.clear()`; `hits` and `misses`; `size()`.
- **Limitation:** Resources referenced from settings are keyed by identity. If you edit one in place (a Curve, a Mesh) and regenerate with the cache on, call `FlowOutputCache.clear()`. Data hashes are 32-bit, with size and stream count added, so a collision is possible in principle. No collision was observed over the golden set.

## Tests

New suites:
- `tests/editor/editor_smoke_harness_test.gd` (5 cases). The dock instantiates headless. Every golden graph: the editor's evaluation equals `evaluate_graph_snapshot` per node, and the runtime equals the golden baseline. Per-node dirty tracking re-runs only the edited branch, and the dock then equals the runtime of the saved edited graph. An unrelated scene change keeps scene-independent nodes clean. Every registered template builds a widget.
- `tests/executor/flow_executor_test.gd` (13). Element contract; release of elements; compiled-graph caching, invalidation (in-place edit, new dictionary, registry change) and lifetime; fresh elements and settings per run; overrides not leaking; bindings that change the order; sync, time-sliced and threaded give identical outputs; threaded error order and variables; `FlowGraphNode3D.threaded`; `node_filter`; `preseeded` (also in threaded mode); recursion guard.
- `tests/executor/flow_node_traits_test.gd` (9). Table coverage both ways, classes, dynamic input and output templates, unknown default, meta flags, meta overrides.
- `tests/executor/flow_output_cache_test.gd` (8). Hits and equality; `FlowGraphNode3D.output_cache`; the key follows settings, upstream changes, graph seed and overrides; hits are copies; errors are replayed; non-cacheable nodes are not stored; LRU bound and `clear()`; loop body evaluation.
- `tests/executor/flow_node_widget_test.gd` (8). Delegation, renaming, settings watching and replacement, error signal, rebinding, the `widget_refresh` hook, the reroute subclass and draw hook, hot-reload rebinding.
- `tests/executor/executor_modes_golden_test.gd` (3). The whole golden set in threaded mode, with the cache cold and then warm, and threaded with cache. Every entry must equal `baseline.json`.

Existing tests edited. These are intended, because elements are RefCounted:
- **135 files under `tests/`, almost all in `tests/nodes/`:** removed 1529 `free()` calls on node elements. `_run(s).free()` became `_run(s)`. A lone call in a block became `pass`.
- **7 `_make()` helpers** in `spawn_nodes`, `loop`, `spawn_scenes`, `subgraph`, `debug`, `spawn_meshes` and `apply_on_actor`: retyped from `-> Node` to `-> FlowNodeBase`.
- **`FlowNodeExtensionTest._styled_titlebar`:** wraps the element in a `FlowNodeWidget` to test styling.
- **`setting_overrides_bindings_test` (editor scratch test):** the settings watcher is now the widget's `_on_settings_changed`.
- **`evaluate_graph_lifecycle_test.test_stock_node_instances_are_freed_after_finalize`:** watches release through weak references, then drops the `GraphEvaluation`.

## Dictionary rows (for COMING_FROM_UNREAL_PCG.md)

| In Unreal PCG | Here |
|---|---|
| **`UPCGNode` / node widget** | **`FlowNodeWidget`** (a `GraphNode`) shows one node in the editor. Node scripts implement optional `widget_*` hooks for custom UI (see the top of `node.gd`). |
| **`IPCGElement`** (stateless executor) | **`FlowNodeBase`**, a `RefCounted` element. Node scripts `extends FlowNodeBase`; the evaluator creates fresh elements per run. |
| **`FPCGGraphCompiler`** | **`FlowCompiledGraph.for_graph(graph)`**: parsed once, cached on the graph, rebuilt when `graph.data` changes. |
| **`FPCGGraphExecutor`** | **`FlowExecutor`**: synchronous, time-sliced (`begin_evaluation`, `FlowGraphNode3D.async_generation`) and threaded (`FlowGraphNode3D.threaded`). |
| **`IPCGElement::CanExecuteOnlyOnMainThread` / `IsCacheable`** | **`FlowNodeTraits`** (`main_thread`, `cacheable`), from a central table or `meta_node["main_thread"]` / `meta_node["pure"]`. |
| **`FPCGGraphCache`** | **`FlowOutputCache`**, opt-in with `FlowGraphNode3D.output_cache`. Keyed by settings, seed and input content; returns copies; LRU; `FlowOutputCache.clear()`. |

## nodes_reference rows

None. No node was added or removed.

## DEPRECATIONS rows

| Node / API | Before | Now | Since |
|---|---|---|---|
| `FlowNodeBase` base class | `extends GraphNode` (a Control); instances had to be `free()`d | `extends RefCounted`. Calling `free()` on an element is an error; drop the reference. Code that created node scripts by hand and freed them (tests, tools) must stop calling `free()`. | WP1 |
| `GraphNode`/`Control` API on node scripts (`title`, `size`, `set_slot_*`, `add_child`, `tooltip_text`, `modulate`, `queue_redraw`, `_draw_port`, `_gui_input`, ...) | Available, because the node was the widget | Not available on the element. Move the code into `widget_init`, `widget_ready`, `widget_gui_input`, `widget_exit_tree`, `widget_refresh` or `widget_draw`, all of which receive the `FlowNodeWidget`. `getEditor()`, `initFromScript()`, `setupDrawDebug()`, `setActivity()` and `setExecTime()` still work and forward to the widget. | WP1 |
| Editor `ctx.gedit_nodes_by_name` | name to the editor's `GraphNode` | name to the runtime element (`FlowEditor.get_element_map()`). `FlowEditor.gedit_nodes_by_name` still maps to widgets. | WP1 |
| Editor preview of a node saved without `random_seed` | Previewed with the settings class default seed | Previews with the same stabilized seed the runtime uses (`FlowNodeIO._stabilize_missing_seed`); saving from the dock writes it into the graph. Runtime output is unchanged. | WP1 |
| Runtime debug draw of evaluator-built nodes | A runtime evaluation created a `NodeDrawDebug` per node and leaked MultiMesh RIDs ("setupDebugDraw failed - no 3D scene scenario") | Runtime elements have no widget, so there is no debug draw and no RID leak. The editor's debug draw is unchanged. A graph saved with `disabled = true` no longer raises the `draw_debug` script error at runtime. The two evaluator tests skipped for that bug (`test_disabled_saved_in_graph_passes_input_through`, `test_disabled_output_is_not_an_execution_root`) pass when unskipped (checked locally, then left skipped because it is an existing test file). | WP1 |
| `FlowGraphResource` | — | Gains a runtime-only member `_flow_compiled` (not exported, never saved) | WP1 |

## Files touched outside WP1 ownership

- `flow_graph_resource.gd`: one non-exported member that holds the compiled graph.
- `node.tscn`: now points at the widget script.
- `nodes/expression.gd`: `getTitle()` no longer sets the GraphNode `size`; a `widget_refresh` hook does it instead. This is the only pure node script that needed an edit.
- `nodes/load_pcg_data_asset.gd`: a Mutex around the static cache.
- `nodes/sample_points.gd`: a Mutex around the static blue-noise table build. WP1 owns this file's UI parts only.
- Existing tests, as listed above.
