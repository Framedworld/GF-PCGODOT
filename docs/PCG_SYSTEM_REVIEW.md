# PCGODOT System Review (2026-09)

Scope: the `flow_nodes_editor` addon at upstream HEAD (`91471c1`), reviewed against
Unreal's PCG framework and against how the two production consumers actually drive it:

| Project | Vendored version | Graphs | How it calls the addon |
|---|---|---|---|
| **GodotJC** (`Framedworld/GodotJC`) | == upstream HEAD, plus 7 `jc_*` nodes | 4 theme graphs (22 nodes each, 6 `jc_*` + 16 `output`) + 1 room subgraph | `FlowNodeIO.evaluate_graph()` directly from `scripts/systems/flow_dungeon.gd` |
| **Black Lantern Tactics** | byte-identical to upstream `58a9d3c` (~2 weeks older than HEAD) plus 23 `bl_*` nodes and a 16-line dock-sizing patch | 1 master graph (5 `bl_*` + outputs), 17 style graphs (17–77 nodes, mostly stock), 3 subgraphs | `FlowNodeIO.evaluate_graph()` directly from `DungeonLevelBuilder.gd` and `BLRoomStyleRuntime.gd` |

The short version: the data model and node vocabulary are in good shape and genuinely
UE-shaped. The **runtime/integration layer is not**, and both games route around it
in the same ways. That is where the next round of work should go, ahead of more node
parity.

---

## 1. What both games actually do (the reality check)

Reading the two codebases side by side, the same seven patterns appear in both:

1. **`FlowGraphNode3D` is never used as designed.** Neither game places one in a scene
   with a graph and `args`. Both build an `EvaluationContext` by hand, call the static
   `FlowNodeIO.evaluate_graph()`, and create a throwaway `FlowGraphNode3D` purely so
   `ctx.owner` is non-null (`flow_dungeon.gd:94-107`, `DungeonLevelBuilder.gd:662-695`).
2. **The seed is smuggled through `ctx.eval_id`** and per-run parameters through
   `ctx.runtime_params`, because `execute()` hard-codes `eval_id = 0`,
   `runtime_params = {}` and returns `void` (`flow_node.gd:113-142`).
3. **Outputs are read back by hand** from the returned Dictionary: unwrapping
   `findStream(name).container[0]`, splitting `;`-joined strings, decoding a direction
   from a one-point yaw (`flow_dungeon.gd:113-239`, `BLRoomStyleRuntime.gd:126-155`).
4. **No spawner nodes are used.** Both games emit point data (or a mutated `FloorData`
   Resource) and instantiate meshes, collision, nav and lights themselves.
5. **Graphs are pipelines of monolithic project nodes.** GodotJC uses zero stock
   processing nodes: `jc_hotel_layout → jc_hotel_skin → jc_room_dressing → ...`, each
   wrapping an imperative library (`jc_room_interior.gd` is 1,103 lines). Black Lantern's
   master graph is the same shape. Only Black Lantern's *style* graphs compose stock
   primitives, and those are described in its own docs as "a second, currently-unused
   styling system".
6. **Custom nodes live inside the addon folder** (`addons/flow_nodes_editor/nodes/jc_*`,
   `bl_*`), so the addon cannot be upgraded by directory replace. Both repos carry
   stray `~libflow...dll` temp files from exactly that kind of copy.
7. **Graphs are hand- or script-authored `.tres`**, not dock round-trips: synthetic
   uids, empty `frames`, partial settings keys in GodotJC; an 819-line
   `build_supply_common_room.gd` graph generator and a Python structural validator in
   Black Lantern.

Both games also wrote a **custom per-room loop** (`jc_room_loop.gd`;
`_apply_room_style_graphs` + `bind_room_filter`) because the stock `loop` iterates
single points and cannot pass per-iteration parameters or group by an attribute.

Read together: the addon is being used as a **typed pipeline runner for GDScript
stages with a graph UI on top**, not as a point-composition toolkit. The
improvements below are aimed at making that use first-class rather than fighting it,
while keeping the UE-composition path viable for the day the games lean on it.

---

## 2. Architecture review against Unreal PCG

### 2.1 Execution nodes are editor widgets (the structural issue)

`FlowNodeBase extends GraphNode`, a Control. Runtime evaluation instantiates one
Control per node per evaluation, and `loop.gd` re-instantiates the entire subgraph per
element (`loop.gd:153-157` admits this). UE separates `UPCGSettings` (data),
`FPCGElement` (stateless executor), `UPCGNode` (topology) and the editor widget.

Consequences already observed in the games:

- The leak that upstream fixed with `_free_node_instances` was live in the Black
  Lantern snapshot reviewed here (June 10); the team's current working tree carries
  the same fix. Even with the fix, the cost of instantiating Controls remains: the
  Black Lantern team measured (headless, Godot 4.7.1) 6 to 12 ms to instance a
  20 to 47 node subgraph, and 0.2 to 0.5 ms per trivial node (filter, add_attribute,
  expression over 10 to 300 points). Their per-room "dress pass" calls the same kit
  subgraph about four times per room across about twenty rooms, so per-stop style
  time rose from about 1.0 s to 1.8 to 2.1 s purely from re-instancing.
- GodotJC hit an editor hang from a bare `load()` of a node script at play time and
  now preloads by path to dodge `@tool` class-web resolution (`flow_dungeon.gd:15-17`,
  `jc_hotel_layout.gd:10-11`).
- Nothing can run off the main thread; `WorkerThreadPool` is off the table while
  executors are Controls.
- Every evaluation pays `initFromScript()`-adjacent widget setup for nodes nobody will
  ever see.

### 2.2 Component lifecycle

| UE `UPCGComponent` | `FlowGraphNode3D` today |
|---|---|
| `Generate()` / `Cleanup()` / `Regenerate()` | `execute()` only; no cleanup API. GodotJC's own doc suggests `for c in pcg.get_children(): c.queue_free()`. |
| `Seed` property + `GenerationTrigger` | No seed export; seed rides `ctx.eval_id` by convention in both games. |
| `OnGenerated` delegate | No signal. The async path finishes silently. |
| Outputs available to Blueprint | `execute()` discards the outputs Dictionary that `evaluate_graph` returns. |
| Graph parameter overrides per component | `args: Dictionary` with a "Refresh Inputs" tool button; no per-node setting override. |
| Generated resources tracked, transient in editor | Spawned `MultiMeshInstance3D`s get `owner = scene_root`, so generated geometry is serialised into the `.tscn` on every save. |

### 2.3 Parameters and bindings

- `GraphInputParameter` cannot declare a Points/Any, Color, NodePath or Int64 input,
  so a graph cannot advertise "I take a point set" at the component boundary.
- There is no way to bind a **node setting** to a runtime value. Black Lantern rewrites
  `attribute_filter_range.min_value/max_value` in the serialized dict before every run
  (`bind_room_filter`), which then forces `CACHE_MODE_IGNORE` loads in four places.
  GodotJC duplicated four 8.6 KB theme graphs that differ only in knob values.
- Both games hand-synchronise knobs across nodes with "must match" comments
  (`door_fraction`, `cell_size`) because graph-scoped parameters are not reachable
  from settings.
- `getSettingValue()` only honours a wired input when the Data has exactly one stream,
  so wiring a real point set into a parameter port is silently ignored.

### 2.4 Data model (mostly good)

Strengths: column streams, `density`/`seed`/`normal` canonical attributes with real UE
semantics, position-hashed per-point seeds, `@data.` domain, `bounds_min/max`,
`steepness`, quaternion stream, `kind` marker, bulks for multi-data pins.

Gaps that the games tripped on:

- **`output.gd` drops `data_attrs` and `tags`** (it re-registers streams only). GodotJC
  therefore joins string tables into a single `;`-separated broadcast element and
  splits on the consumer (`JCGenTypes.join_table`), and yaw-encodes a direction into a
  one-point rotation to get a Vector3 across the boundary.
- No helper to wrap or unwrap a scalar/Resource/String in a `Data`; Black Lantern has
  ~10 copies of `_wrap_floor_data` / `_string_from_flow_data`, GodotJC has 22 copies
  of a defensive stream accessor. The stream record is an untyped Dictionary.
- Attribute typing is by convention: Black Lantern shipped a graph that registered
  `rotation` as Float and got five warnings and broken orientation. Canonical
  attributes deserve schema enforcement at `registerStream`.
- Rotation defaults to Euler degrees; fine for authoring, but `getTransformsStream`
  still rebuilds a Basis per point in GDScript.
- No Vector2 or Transform stream types; UE has both.

### 2.5 Caching and incremental evaluation

The editor has per-node `dirty` flags, dependant expansion and scene fingerprints.
The runtime has none: every `evaluate_graph` re-parses settings, re-instantiates every
node, re-sorts, re-runs. UE caches element outputs keyed by a CRC of settings + inputs,
which is what makes its runtime regeneration and loops affordable. `loop.gd`'s comment
names the missing piece exactly: parse once, execute many. The Black Lantern
measurements above show the cache must be shared across repeated `subgraph` calls
within one evaluation and across rooms, not only across `loop` iterations.

### 2.6 Spawners and generated content

- `spawn_meshes` exposes mesh, variants, weights, selector, colors, parent path. UE's
  Static Mesh Spawner descriptor also covers collision profile, material overrides,
  cast shadows, visibility/cull distances, layers and instance custom data. None of
  those exist here, which is one reason both games build their own MultiMeshes.
- Generated nodes are tagged with `flow_owner = <node name>`. Two graph instances that
  spawn into the same `spawn_parent_path` will delete each other's output on
  `clear_previous_instances`.
- No `cleanup()`, no transient mode, no signal.

### 2.7 Extension mechanism and upstream hygiene

- `FlowNodeRegistry.register_node_directory` exists but is static in-memory state that
  must be re-registered before every evaluation and editor load. Neither game calls
  it; both dropped nodes into the addon's own `nodes/`.
- Project-specific content has leaked into upstream shared files:
  `node.gd:218` (`bl_` hue rule), `flow_editor.gd:1472` and
  `search_add_node_popup.gd:19` (a hard-coded "Black Lantern" category listing 20
  `bl_*` templates), `flow_nodes_io.gd:829-837` (`MAPGEN_DEBUG_ORDER`,
  `assemble_map_plan`, `pcg_map_plan`). Category and colour should come from
  `meta_node`, never from editor tables.
- No deprecation path: Black Lantern's tools reference `gdr_tree_gd.gd`,
  `DataType.Vector3`, and `grid_points` / `bl_debug_points` templates that no longer
  exist.
- Semantics changed between the upstream commit a game vendored and upstream HEAD
  (`distance.gd` null-B was "empty" at `58a9d3c`, "error" now; `attribute_filter_range`
  string handling; `noise` value mapping; per-point seeding). Nothing would tell a game
  that re-baselining changed its output. Black Lantern's copy turned out not to be
  locally patched at all: it is that older upstream commit verbatim, which makes the
  point sharper, since a plain upgrade would silently change 14 of its 16 style graphs.

### 2.8 Serialization

`FlowGraphResource.data` is a `version: 1` Dictionary blob of nodes, links and
frames. There is no migration hook, so any node-setting rename is a silent data loss
on load. Diffs are noisy (positions, every settings key), which is part of why both
teams reached for scripts and text edits instead of the dock.

### 2.9 Editor

`flow_editor.gd` is ~5,000 lines. It has good bones (D/A/E/F hotkeys, exec-time badge,
alias search, Data Inspector, collapse-to-subgraph) but no graph validation
(unconnected required ports, unreachable nodes, type mismatches), no "run with these
inputs and this seed" harness, and no public API for a project dock. Black Lantern
built a separate Style Lab scene plus its own EditorPlugin and reaches into this one
by duck typing (`plugin_node.call("setResourceToEdit", ...)`).

### 2.10 Tests

1,343 GdUnit4 cases is real coverage for node semantics. The untested set is exactly
what the games depend on: `loop`, `subgraph`, `spawn_meshes`, `spawn_nodes`,
`spawn_scenes`, `apply_on_actor`, `debug`, and there is no evaluator-level test
(`evaluate_graph` ordering, diamonds, variable publishing, output collection, freeing).
The diamond-ordering fix in Black Lantern's copy is upstream commit `58a9d3c`'s
post-order sort; upstream later added `_stabilize_consumer_input_order` on top. Neither
had a test before this round.

### 2.11 Node-level defects reported from production (Black Lantern, 2026-09)

Verified against upstream HEAD unless noted. Fixes are part of the current round.

- `load_pcg_data_asset` runs Vector3 string parsing on every value of every column
  even after the column is known not to be a vector; a 333 by 16 JSON costs 15 to
  18 ms per load, nothing is cached, and `asset_path` is read directly from settings
  so it cannot be wired or bound.
- `sample_mesh` area-weighted normals use `(b-a) x (c-a)`; with Godot's clockwise
  front faces this can point into the mesh (reported: a table underside faces up).
- `merge` registers a bulk's new streams after appending that bulk's other streams,
  so the stream-length invariant warns on every merge of differing column sets.
- `match_and_set` uses the node-global RNG when no `seed` stream exists, so every
  room picks the same variants; it also compares keys as strings, so a JSON `3.0`
  never matches key `3`.
- `copy` in SourceToTargets mode emits only source streams (UE's Copy Points has
  attribute inheritance options).
- `sample_points` emits only the common streams and drops the parent point's
  attributes.
- `expression` retypes an existing stream when the result type differs.
- `point_offsets` writes three bookkeeping columns by default; `add_attribute` with
  no input yields a one-point Data (useful as a schema row, but undocumented).
- Setting-wire ports are positional, so graph generators had to instance node
  scripts to compute port indices. Name-based bindings remove that.

### 2.12 Platform

The committed `flow.gdextension` ships Windows editor/templates and macOS debug only.
No Linux binary, no macOS release. Both games note this in their docs and Black
Lantern guards every native call with `ClassDB.class_exists("GDKdTree")`. CI already
builds Linux; it just is not committed or released.

---

## 3. Recommendations, in priority order

Each item names the game code it would delete.

### P0 — Runtime API that matches how the games call it

```gdscript
# flow_node.gd
@export var seed : int = 0
@export var generate_on_ready : bool = true          # UE GenerationTrigger
@export var transient_output : bool = false           # spawned nodes never get owner
signal generated(outputs : Dictionary)
signal cleaned_up

func generate(inputs : Dictionary = {}, params : Dictionary = {}) -> Dictionary
func generate_async(inputs := {}, params := {}) -> void   # emits `generated`
func cleanup() -> void                                    # frees flow_owner children
func regenerate(...)

# flow_nodes_io.gd — owner-less evaluation is legal
static func evaluate_graph(graph, inputs, ctx, params, depth)  # ctx.owner may be null;
                                                               # spawners error clearly
```

`seed` becomes a real field on `EvaluationContext` and `eval_id` goes back to being an
evaluation counter. Deletes: both throwaway `FlowGraphNode3D` roots, both hand-built
contexts, GodotJC's `_normalize_outputs` glue for seeding, Black Lantern's seed-in-`eval_id`
convention.

### P0 — Carry the whole `Data` across graph boundaries

`output.gd` and the input feed in `_build_evaluation_state` should copy `data_attrs`,
`tags` and `kind`, not just streams. Add typed helpers:

```gdscript
static func Data.scalar(name, value, data_type) -> Data
func Data.first(name, default = null) -> Variant
func Data.container(name) -> Variant       # or null, never a Dictionary
```

Deletes: `JCGenTypes.join_table/split_table`, the yaw-encoded direction, ~30 copies of
`_wrap_*` / `_*_from_flow_data` across both games.

### P0 — Bind node settings to runtime values

Two mechanisms, both cheap given `getSettingValue` already exists:

1. **Component-level setting overrides**: `FlowGraphNode3D.overrides : Dictionary`
   keyed by `"<node_name>/<property>"`, applied in `_build_evaluation_state` after
   `dict_to_resource`. Graph resources stay immutable and cacheable.
2. **`$param` binding in the inspector**: a String setting whose value starts with `$`
   resolves against graph inputs / `runtime_params` at evaluation time (UE's
   "override by attribute" pin, without the wire).

Deletes: `bind_room_filter` and every `CACHE_MODE_IGNORE` load in Black Lantern; three
of GodotJC's four theme graphs; the "must match" knob comments once graph inputs are
reachable from settings.

### P1 — Separate executors from `GraphNode`

Introduce `FlowElement extends RefCounted` holding `execute(ctx)`, `getMeta()`,
settings, bulks and the input/output helpers. `FlowNodeBase` (the widget) owns a
`FlowElement` and delegates. The evaluator instantiates only elements. Do it
incrementally: keep `FlowNodeBase.execute` as a shim that forwards, migrate stock nodes
file by file, and let project nodes keep extending `FlowNodeBase` until they move.

This unlocks: a compiled-graph cache (`FlowCompiledGraph` = elements + order, reused
across `loop` iterations and across rooms), per-element output caching keyed by
settings hash + input hash (UE's model), `WorkerThreadPool` for pure elements, and no
more `@tool` class-web hangs at runtime.

### P1 — Group-by loop with per-iteration parameters

Both games wrote this. Add to `loop`:

- `iterate_by : String` attribute name; each iteration receives the partition
  (`in_data.filter(indices)`) instead of a single point.
- per-iteration `runtime_params` injection: `iteration_index`, `iteration_key`, and the
  partition's `@data.*` attributes.
- reuse the compiled subgraph across iterations (needs P1 above, but even a cached
  instance list with a per-pass reset is a large win).

Deletes: `jc_room_loop.gd` (254 lines), Black Lantern's `_apply_room_style_graphs`
loop and per-room graph reload.

### P1 — Make extension a supported path

- Read extra node directories from a ProjectSettings key
  (`flow_nodes/node_directories`) at plugin load and in `evaluate_graph`, so a project
  never has to call `register_node_directory` by hand or ship nodes inside the addon.
- Category, colour hue and search aliases come only from `meta_node`. Remove the
  `bl_` and "Black Lantern" tables and the `MAPGEN_DEBUG_ORDER` block from upstream.
- Add `version` to graph data and a `FlowGraphMigrations` table keyed by node template,
  so setting renames do not silently drop values.
- Publish a deprecation list per release (removed scripts, renamed enums, changed
  semantics such as `distance` null-B).

### P1 — Tests where the games live

- Evaluator tests: linear, diamond, multi-final, `set_variable`/`get_variable` order,
  subgraph output collection, nested depth, instance freeing (assert no orphan
  Controls after `evaluate_graph`).
- `loop`, `subgraph`, `spawn_*` node tests.
- A **golden-output harness**: evaluate every `demo/graphs/*.tres` with a fixed seed and
  compare stream hashes to a checked-in file. Games can vendor the harness and run it
  against their own graphs before and after a re-baseline. This is the UE
  "determinism test" equivalent and would have caught both semantic drifts.

### P2 — Generated-content management

- `transient_output` (owner stays null) and `cleanup()` as in P0.
- `flow_owner` meta becomes `{component_id, node_name}` so two components sharing a
  parent do not delete each other's output.
- Extend `SpawnMeshesNodeSettings` toward UE's descriptor: `material_override`,
  `cast_shadow`, `visibility_range_begin/end`, `layers`, `collision_shape` (none / box
  from bounds / trimesh) with a generated `StaticBody3D`, `custom_data_attribute`.
  This is what would let a game keep spawning inside the graph instead of rebuilding
  MultiMeshes by hand.

### P2 — Grid semantics as a first-class attribute

Both games are tile-based (hotel floors, tactics grid). Both maintain
`cell_x`/`cell_y`/`grid_cell`/`room_id` integer streams by hand, Black Lantern wrote
`bl_sync_grid_cell` because stock transforms drop them, and hit the "point at cell-min
corner pushes props out of the room on N/W walls" bug. UE has nothing here; your
projects do need it:

- canonical `cell` (Vector3i-as-Vector or two Int streams) plus a `cell_size` data attr.
- `snap_to_grid` gains `anchor : Center | Min` and writes `cell`.
- `transform` / `point_offsets` / `copy` keep `cell` in sync when it exists.
- `points_from_gridmap` and the dungeon family emit it.

### P2 — Editor validation and a run harness

- A Validate action listing: required in-ports unconnected, unreachable nodes, output
  name collisions, stream-type conflicts on well-known attributes, missing subgraph
  resources.
- A "Run with…" panel: choose seed, set graph inputs from a fixture `.tres`, set
  `runtime_params`. Public plugin API: `FlowEditorPlugin.open_graph(res, owner,
  inputs, params)` so project docks stop duck-typing.

### P3 — Native and performance

- Commit/release the Linux library that CI already builds; add macOS release.
- Move the per-point hot loops that every graph touches into `GDStreamUtils`:
  Euler→Basis for `getTransformsStream`, `transform`, `filteredStream` gather,
  `merge` append, `attribute_filter_range`. These dominate wall time in the game
  graphs far more than the spatial queries that are already native.
- Per-element output cache keyed by settings hash + input Data hash once P1 lands.

### P3 — Remaining UE parity items worth doing (after the above)

HiGen per-cell execution and proximity runtime generation both depend on the
compiled-graph and cache work in P1, so they stay behind it. Spline mesh spawning
(Godot has no SplineMesh; a `Path3D` + deformed `ArrayMesh` node is the analogue) and
`Get Actor Property` style scene reads are the next node-level gaps a UE user will
hit.

---

## 4. What is already good and should not be touched

- Density and seed semantics, position-hashed per-point seeds, and the "stable seed
  12345 by default" policy. This is closer to UE than most Godot scatter tools.
- The `@data.` domain, `bounds_min/max`, `steepness`, quaternion stream and `kind`
  marker: all optional, all back-compatible, all shipped without breaking `.tres`.
- Bulks as multi-data pins; `partition` stamping `@data` keys; `merge` tolerating
  stream-type mismatch instead of aborting.
- Editor ergonomics: D/A hotkeys, exec-time badges, alias search that accepts UE
  names, collapse-to-subgraph, scene fingerprints for regen.
- Documentation: `COMING_FROM_UNREAL_PCG.md` and the honest `PARITY_ROADMAP.md`.
- CI matrix (Godot 4.6 + 4.7, GdUnit4, headless import gate).

---

## 5. Suggested sequencing

1. P0 runtime API + boundary data (small, contained, immediate payoff in both games).
2. P0 setting bindings/overrides.
3. Evaluator + loop + spawner tests and the golden-output harness, so the next step is
   safe.
4. P1 executor split, then compiled-graph cache, then the group-by loop on top.
5. Extension hygiene and migrations (can run in parallel with 4).
6. Spawner descriptor, grid attribute, editor validation.
7. Native hot loops, Linux/macOS release binaries.

Rough size: items 1–3 are days; item 4 is the one multi-week piece and the only
refactor with blast radius, which is why the tests come first.
