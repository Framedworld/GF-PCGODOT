# GodotJC → PCGODOT P0 Migration Plan

Target: move **GodotJC** (`Framedworld/GodotJC`, HEAD `d38d39d`) onto the P0 runtime API
defined in [`RUNTIME_API_P0.md`](../RUNTIME_API_P0.md). The same round also delivers node
directories from `flow_nodes/node_directories`, graph format v2 with migrations,
category/colour from `meta_node` only, and the golden-output harness (`demo/tests/golden`).

How to read references:

- `path:line` without a prefix is a GodotJC file at `d38d39d`.
- `addons/flow_nodes_editor/...` lines are the addon GodotJC vendors today. Every script in it is
  byte-identical to GF-PCGODOT `demo/addons/flow_nodes_editor` at `91471c1`. `diff -rq` shows
  only the `jc_*` files, `bin/flow.gdextension` (upstream adds a `linux.x86_64` line), a stray
  `~libflow…TMP`, and `.import` files.
- `P0 §n` is a section of `RUNTIME_API_P0.md`. `Review §n` is `PCG_SYSTEM_REVIEW.md`.

Things I verified by running code rather than reading it (Godot 4.6.stable headless, on a
scratch copy of GodotJC's `scripts/`, `resources/`, `tests/` and the addon, with autoloads
removed; the GodotJC clone itself was not modified):

1. A `@data.` attribute stores **only element 0** of the container you register. Registering a
   3-point `PackedVector3Array` as `@data.route_cells` reads back as 1 point.
   This is a live GodotJC bug (see §1 row N3 and step V2).
2. The yaw round-trip GodotJC uses for endpoint facings (`jc_spawn_markers.gd:92-98` →
   `flow_dungeon.gd:234-239`) is **not bit-exact**. `(1,0,0)`, `(-1,0,0)` and `(0,0,-1)` come
   back with a ~4e-8 residue; only `(0,0,1)` survives exactly. Step C4 therefore changes
   `spawn_inward` / `elevator_inward` by that residue.
3. The golden capture script in Appendix A runs against the **current** addon. It produced
   144 cases in about 45 s, replayed with 0 diffs in a second process, and passing a plan
   changed 12 or more dressing keys. As a negative control, changing `skin.light_energy` in
   `hotel_grounded.tres` from 1.95 to 1.96 produced exactly 72 diffs: the `Lights` output and
   the `light_energy` key, for the three themes that use that graph, and nothing else.

---

## 1. Current integration map

### 1.1 Game-side call sites and glue

| # | Where | What it does | Addon behaviour it depends on |
|---|---|---|---|
| G1 | `scripts/systems/flow_dungeon.gd:45-56` `generate_floor()` | Resolves `theme.graph_path`, falls back to `DEFAULT_GRAPH_PATH` (`:22`), evaluates, and uses `_fallback` if `floor_cells` is empty | If node resolution fails, the fallback runs **silently**: `push_warning` only (`:55`), no error |
| G2 | `flow_dungeon.gd:62` | `ResourceLoader.load(graph_path, "", CACHE_MODE_IGNORE)` on every floor | Nothing. This is defensive, because graphs used to be treated as mutable |
| G3 | `flow_dungeon.gd:66-74` | Hand-builds `FlowData.EvaluationContext`, sets **`ctx.eval_id = seed_val`**, `runtime_params = {floor_index, depth_tier, theme_id, is_anomaly}` | `_build_evaluation_state` copies the parent `eval_id` into the child ctx (`addons/flow_nodes_editor/flow_nodes_io.gd:843`) and merges runtime params (`:845-848`) |
| G4 | `flow_dungeon.gd:75-93` | Copies HotelDirector plan knobs into `runtime_params` as `hb_hall_branches_delta`, `hb_target_route_m`, `hb_max_rooms_delta`, `hb_torch_prob`, `hb_light_energy_mult`, plus `room_programs` | Runtime params reach every node, including nested evaluations |
| G5 | `flow_dungeon.gd:94-107` | Creates a throwaway `FlowGraphNode3D` "JCFlowTempRoot" under the host so `ctx.owner` is non-null, then `queue_free()`s it | `FlowGraphNode3D._ready()` calls `execute()`. With no graph assigned it **push_warns "no graph resource assigned" on every floor** (`addons/flow_nodes_editor/flow_node.gd:105-116`) |
| G6 | `flow_dungeon.gd:104` | `FlowNodeIO.evaluate_graph(graph, {}, ctx, {})` | Output collection for graphs **without `out_params`**: each `output` node is keyed by `settings.name` (`flow_nodes_io.gd:995-1004`) |
| G7 | `flow_dungeon.gd:113-231` `_normalize_outputs` | Reads 16 named outputs by hand through the `POINT_OUTPUTS` / `POSED_OUTPUTS` maps (`:26-39`) plus explicit reads | `output.gd` re-registers only streams, dropping `data_attrs` and `tags` (`addons/flow_nodes_editor/nodes/output.gd` `execute`) |
| G8 | `flow_dungeon.gd:137-152` | Unpacks `prop_meshes` from a 1-element `;`-joined stream via `JCGenTypes.split_table` | Same as G7: the table cannot travel as `@data` because `output` drops it |
| G9 | `flow_dungeon.gd:154-223` | Splits the `RoomInterior` stream by `role` into walls, doorways, tiles, room lights, sockets and props | Stream round-trip through `output` |
| G10 | `flow_dungeon.gd:225-239` | `spawn_point` / `elevator_point` from `position[0]`. The facing is **decoded from yaw** (`_first_yaw_dir`) | A Vector3 cannot cross `output` as a data attribute |
| G11 | `flow_dungeon.gd:310-375` (and `:141-152`) | Six defensive `findStream` accessors (`rec["container"] if typeof(rec)==TYPE_DICTIONARY else rec.container`) | The stream record is an untyped Dictionary |
| G12 | `flow_dungeon.gd:243-281` `_fallback` | Imperative path through the same libraries | None |
| G13 | `flow_dungeon.gd:15-17` | Comment: a bare `load()` of a node script hung in-editor play, so flow classes are referenced by `class_name` | Node executors are `@tool` `GraphNode` Controls (Review §2.1) |
| G14 | `scripts/systems/floor_generator.gd:142` | `FlowDungeon.generate_floor(theme, floor_index, rng.randi(), self)`; consumes `FloorDressing` from `:143-172` | None. **This is the stability boundary**, and `FloorGenerator` should not change in any step |
| G15 | `scripts/systems/floor_dressing.gd:57-85` `ensure()` | Normalises every key to a typed Packed array | None |
| G16 | `scripts/data/floor_theme_def.gd:20-23` | `graph_path`: one theme maps to one graph | None |
| G17 | `scripts/core/floor_director.gd:261-292` | Coded fallback themes hard-wire the four graph paths (`:271/278/285/292`) | None |
| G18 | `scripts/core/game.gd:494-499`, `scripts/core/run_manager.gd:39-42, 147-173` | The seed chain: `RunManager.rng` is seeded from `run_seed`, and each floor draws `rng.randi()`. Saves hold only `run_seed` and `current_floor`; floors are regenerated on resume (`run_manager.gd:147-149`) | None |
| G19 | `scripts/systems/jc_gen_types.gd:64-81` | `join_table` / `split_table` (`;`-joined 1-element broadcast convention) | Same as G7 |
| G20 | `tests/generation_audit.gd:430-457, 459-497, 499-528, 739-777` | Calls `FlowDungeon.generate_floor(theme, f, seed, null)` in a headless SceneTree. **`:505` and `:747` carve directly with `GFDungeonCarver.generate(..., seed_val, …)` and assert the graph's output agrees at the same raw seed.** `:520-528` is the in-process determinism replay | `ctx.eval_id` equals the raw seed seen by `jc_hotel_layout` |
| G21 | `project.godot:47` | Flow Nodes Editor plugin enabled | None |
| G22 | `addons/flow_nodes_editor/bin/~libflow.windows.editor.x86_64.dll~RF44d508.TMP` (also `addons/limboai/bin/~liblimboai…TMP`) | Leftovers from copying files over a locked DLL | None |
| G23 | `README.md:62` | Documents the nodes as living in `addons/flow_nodes_editor/nodes/jc_*.gd` | None |

### 1.2 Custom nodes (all in `addons/flow_nodes_editor/nodes/`, 2,645 lines with settings)

| # | Node (lines) | Seed source | runtime_params read | Boundary workarounds | Other addon coupling |
|---|---|---|---|---|---|
| N1 | `jc_hotel_layout.gd` (321) + settings (135) | `:36` `ctx.eval_id if ctx.eval_id != 0 else settings.random_seed`; local RNG `:180-181` | `floor_index :35`, `hb_max_rooms_delta :42`, `hb_torch_prob :45`, `hb_hall_branches_delta :48`, `room_programs :89`, `hb_target_route_m :258` | `join_table` ×3 for `room_tags`, `room_door_states`, `room_archetypes` (`:84-85, 91-92`); `@data.spawn_plane/inward`, `elev_*`, `cell_size` (`:97-103`) | `preload` of settings by addon path `:9`; `SpatialAnalyzer` preloaded "so headless runs do not depend on the class-name cache" `:10-12`; `load()` of archetype `.tres` `:240` |
| N2 | `jc_hotel_skin.gd` (150) + settings (64) | none | `hb_light_energy_mult :53`, `depth_tier :80` | reads `@data.*_plane` `:58-61` and route `:114-118` | settings preload `:9`; inline accessors `:41-49` |
| N3 | *(bug)* `jc_hotel_layout.gd:104-115` | – | – | Writes `@data.route_cells`, `lane_route_cells` and `center_route_cells` as **multi-point** arrays. `registerStream("@data.x", …)` keeps only element 0 (`addons/flow_nodes_editor/flow_data.gd:460-471`, verified), so `jc_hotel_skin` (`:81, 114-118`) gets a 1-point "route" for `_fake_door_kind` (`scripts/systems/hotel_skin_lib.gd:295-299`), and `jc_cart_traps` bend detection (`:60-64`) never fires | – |
| N4 | `jc_spawn_markers.gd` (110) + settings (34) | `:53` eval_id-or-setting | – | reads `@data.*` `:56-64`; **yaw-encodes the inward direction** `_posed :92-98` | settings preload `:8`; accessors `:72-89` |
| N5 | `jc_cart_traps.gd` (102) + settings (36) | `:75` eval_id-or-setting | – | reads `@data.*` and route `:41-46, 51-55, 94-102` | settings preload `:9`; `fake_door_fraction` "must match" the skin (`jc_cart_traps_settings.gd:11-12`) |
| N6 | `jc_room_dressing.gd` (109) + settings (186) | `:57` eval_id-or-setting | – | `prop_meshes` as a `join_table` plain stream `:84-88`, with the comment "the output node … drops the data-attribute domain" `:85-87` | settings preload `:10`; `door_fraction` / `door_min_spacing` duplicated from the skin (`jc_room_dressing_settings.gd:62-68`, comment `jc_room_dressing.gd:37-38`) |
| N7 | `jc_room_loop.gd` (254) + settings (16) | `room_seed = eval_id*1000003 + rid*97 + 13` `:115` | copies all of them into per-room params `:99-115` | `split_table` `:200-205` | nested `FlowNodeIO.evaluate_graph(subgraph, {"RoomCells": sub}, ctx, params)` `:128`; subgraph loaded with `CACHE_MODE_IGNORE` `:37`; relies on `_publish_runtime_params` not leaking local params (`flow_nodes_io.gd:546-554`) and on the input feed copying `data_attrs` (`:885`) for `@data.cell_size` |
| N8 | `jc_room_interior.gd` (1,103) + settings (25) | `:112` `runtime_params.room_seed`, else `ctx.eval_id` | `room_tag`, `room_id`, `room_tags` `:107-109`, `room_archetype_id :171`, `theme_id :182` | – | settings preload `:13`; `load()` of archetype/style `.tres` `:1031-1045` |

Across `flow_dungeon.gd` and the `jc_*` nodes there are exactly **22** copies of the
`TYPE_DICTIONARY else rec.container` accessor idiom (`grep -c`).

None of the jc nodes uses the base-class `rng` member that `preExecute` seeds
(`addons/flow_nodes_editor/node.gd:150-151`). They either build local RNGs or pass a seed into
`GFDungeonCarver` / `HotelSkinLib`. That is why step B can be byte-identical.

### 1.3 Graphs (`resources/pcg/`)

| Graph | Content | Notes |
|---|---|---|
| `hotel_grounded.tres` | 22 nodes: `layout`, `skin`, `markers`, `carttraps`, `dressing`, `room_loop` (6 jc) and 16 `output` nodes (`:145-431`). `version: 1`, no `out_params`, no `frames` | Skin port 6 (`Sconces`) is unwired. `layout.random_seed = 12345` (`:154`); every other jc node has `random_seed: 0` |
| `hotel_basement.tres`, `hotel_ethereal.tres`, `hotel_mental.tres` | Identical topology and positions. Only knob values, `uid` and `resource_name` differ (full diff in Appendix B) | Basement also serialises `topology: "spine"`, `corridor_width`, `width_jitter`, `side_spur_chance`, `spur_width` |
| `room_interior.tres` | `input RoomCells → jc_room_interior → output Interior`, `in_params = [RoomCells]` | Evaluated once per room by N7 |

A fifth theme, `resources/floors/vertical_slice.tres`, has no `graph_path` and falls through to
`DEFAULT_GRAPH_PATH` (grounded). It is in the golden set.

Not used by GodotJC: `FlowGraphNode3D` as a component, any spawner, `apply_on_actor`,
`subgraph`, stock `loop`, any native class (see R5). The P0 items `generate()`, `cleanup()`,
`transient_output` and the `flow_owner` meta shape (P0 §1, §5) therefore need **no** GodotJC
changes. Only P0 §2, §3, §4 and §6 matter here.

---

## 2. Step-by-step migration

Order and output contract:

| Step | Brief item | Output change | Ships alone? |
|---|---|---|---|
| 0 | – | none (capture) | yes |
| A1 | (a) re-vendor | **none**, byte-identical | yes |
| A2 | (a) move nodes and project setting | **none** | yes |
| B | (b) `FlowNodeIO.evaluate` and `ctx.seed` | **none**. Nodes read `ctx.seed` raw | yes |
| C1–C3 | (c) accessors and string tables | dressing layer: **none**. Graph layer: `PropPoints` only | yes |
| C4 | (c) direction as a data attribute | dressing: `spawn_inward` / `elevator_inward` residue only | yes |
| D | (d) one graph plus overrides | **none** | yes |
| E | (e) runtime_params and bindings | **none** | yes |
| V | (b) seed derivation and the N3 route fix | **every floor changes**; do it at a release boundary | yes (optional) |
| L | (f) stock group-by loop | changes unless the addon offers keyed seeding (see Feedback) | after P1 |
| H | (g) docs | n/a | anytime; each step also edits its own docs |

The rule for every step: run `tests/generation_audit.gd` (exit 0) **and** the golden compare
(Appendix A). A step marked "none" must pass the golden with **0 diffs**. A step with an
expected change must produce a diff set that is a subset of the listed allowlist. You then
re-capture the baseline in the **same commit** with a message that names the allowlist.

### Step 0: capture the golden baseline on the current addon

Do this before any addon code changes. The P0 harness in GF-PCGODOT will call
`FlowNodeIO.evaluate`, which does not exist in GodotJC's vendored addon. A baseline must come
from the old addon, so the capture has to use the pre-P0 entry point.

1. Branch GodotJC (`pcg-p0-migration`) from `d38d39d`.
2. Add `tests/golden/pcg_golden.gd` from Appendix A. Keep it **outside `addons/`**, because
   re-vendoring replaces that folder. It evaluates two layers per case:
   - **dressing**: `FlowDungeon.generate_floor()` output, the exact dict `FloorGenerator`
     consumes. This is the contract that must survive every step.
   - **graph**: every named output of the theme graph, hashing streams, `data_attrs`, `tags`
     and `kind`. It uses `FlowNodeIO.evaluate()` when it exists and otherwise a hand-built
     context with `eval_id = seed`, which is exactly what `flow_dungeon.gd:66-74` does today.

   Cases: grounded f0 and f3, basement f5, ethereal f10, mental f15, vertical_slice f0; seeds
   {1, 2, 3, 4, 19, 123456789}; plans {none, planA}. planA sets every `gen` knob that
   `flow_dungeon.gd:81-93` forwards, plus `room_programs`. The plan is injected through a
   stub `/root/HotelDirector` with `current_plan`, which is exactly what
   `flow_dungeon.gd:286-294` reads, so no game code changes.
3. If the addon's own harness (`demo/tests/golden`) has landed **with a legacy mode** (see
   Feedback F3), also copy it to `tests/golden/addon/`. Point it at `res://resources/pcg`
   with the same seeds, a `runtime_params` fixture (`floor_index`, `depth_tier`, `theme_id`)
   per theme graph, and a `RoomCells` input fixture for `room_interior.tres`. Capture its
   baseline too. Without a legacy mode it cannot produce a pre-migration baseline, and
   Appendix A remains the reference.
4. `godot --headless --path . --import`. `.godot/` is gitignored (`.gitignore:2`), so the
   class-name cache must be rebuilt on every fresh checkout.
5. Run `godot --headless --path . --script res://tests/golden/pcg_golden.gd -- --write` to
   write `tests/golden/pcg_baseline.json` (144 cases).
6. Run the compare (no `--write`) twice. It must print `GOLDEN PASS cases=144 diffs=0`.
7. Run the audit and record the verdict and warning count: `tests/run_audit.ps1` on Windows,
   or `godot --headless --path . --script res://tests/generation_audit.gd`.
8. Commit the script and baseline. **Record the engine build and OS** in the commit message.
   Every later compare must use the same build and OS (R11). GodotJC targets 4.7
   (`project.godot:16`); the prototype was validated on 4.6.
9. Add the golden compare to `tests/run_audit.ps1` after the audit call, reusing its
   `Start-Process -Wait -PassThru` pattern (`tests/run_audit.ps1:4-5`).

### Step A1: re-vendor the addon, jc nodes still inside it (byte-identical)

This proves the addon upgrade alone is safe before any file moves.

- **Files**: replace `addons/flow_nodes_editor/**`, then put the 14 `jc_*.gd` and 14
  `.gd.uid` files back into `addons/flow_nodes_editor/nodes/` for now. Delete both `~…TMP`
  files (G22).
  ```sh
  mkdir -p /tmp/jc && mv addons/flow_nodes_editor/nodes/jc_* /tmp/jc/
  rm -rf addons/flow_nodes_editor
  git -C ../GF-PCGODOT archive <release-sha> demo/addons/flow_nodes_editor | tar -x --strip-components=2 -C addons/
  mv /tmp/jc/* addons/flow_nodes_editor/nodes/
  ```
  Use `git archive`, not `cp -r`, so untracked build artifacts such as
  `native/src/*.os` are not vendored. Record `<release-sha>` in
  `docs/integration/gf_pcgodot.md`.
- **Addon API used**: none new. This relies on the P0 back-compat rule: *"with `seed == 0`, no
  overrides, no bindings and no new calls, every existing graph produces byte-identical
  output."* GodotJC's hand-built context has `seed == 0`. It also relies on the child context
  still inheriting the caller's `eval_id` (today `flow_nodes_io.gd:843`), which P0 does not
  list as changing (see F7).
- **Graph format v2**: GodotJC's graphs are hand-authored `version: 1` with partial settings
  keys. Load them through the migration table; **do not re-save them from the dock in this
  step** (R10).
- **Delete**: nothing yet.
- **Verify**: golden 0 diffs (both layers, 144 cases); audit PASS; open
  `hotel_grounded.tres` in the dock, confirm 22 nodes appear, and close without saving. If
  a jc template fails to resolve, the game silently falls back (G1); golden shows every
  dressing key different and the audit fails `used_flow` (`generation_audit.gd:439-441,
  487`).

### Step A2: move jc nodes to `res://scripts/pcg_nodes/` and register the directory (byte-identical)

- **Files**:
  - `git mv` all 28 files (`jc_*.gd` and `.gd.uid`) to `scripts/pcg_nodes/`. UIDs are
    preserved. The graphs reference nodes by **template name**, not path, so no `.tres`
    changes (`addons/flow_nodes_editor/flow_node_registry.gd:34-44` resolves
    `<dir>/<template>.gd`).
  - Rewrite the settings preloads to relative paths so the next move is free:
    `jc_hotel_layout.gd:9`, `jc_hotel_skin.gd:9`, `jc_room_dressing.gd:10`,
    `jc_room_loop.gd:10`, `jc_room_interior.gd:13`, `jc_spawn_markers.gd:8`,
    `jc_cart_traps.gd:9`.
    ```gdscript
    # before
    const JCHotelLayoutSettingsScript = preload("res://addons/flow_nodes_editor/nodes/jc_hotel_layout_settings.gd")
    # after
    const JCHotelLayoutSettingsScript = preload("jc_hotel_layout_settings.gd")
    ```
  - `project.godot`: add the key below. The review's name for it is
    `flow_nodes/node_directories` (Review §3 P1, "Read extra node directories from a
    ProjectSettings key").
    ```ini
    [flow_nodes]
    node_directories=PackedStringArray("res://scripts/pcg_nodes")
    ```
  - Add `"category": "Jerk Chicken"`, plus whichever colour key the addon documents (F11), to
    each `meta_node` (e.g. `jc_hotel_layout.gd:21-31`). Category and colour now come from meta
    only. Without this the nodes land in the default bucket with a hash-derived hue. There is
    no effect on output.
  - `README.md:62`: new path.
- **Delete**: every `jc_*` file under `addons/flow_nodes_editor/nodes/`. After this commit the
  addon folder is a pristine upstream copy and future upgrades are a plain directory replace.
- **Verify**: from a **fresh clone**, run `--import`, then the golden (0 diffs), then the audit.
  This proves the class cache and directory registration work headless, where editor plugins
  do not run (R7). In the editor, the add-node popup lists the JC nodes under "Jerk Chicken".
  Run an exported Windows build smoke test on floor 0: `export_presets.cfg` is gitignored
  (`.gitignore:5`), so check locally that no export filter excludes `scripts/pcg_nodes/`
  (R13).

### Step B: `FlowNodeIO.evaluate` and `ctx.seed` (byte-identical)

This must be **one atomic commit**. After it, `eval_id` is an evaluation counter
(*"`var eval_id : int = 0 # evaluation counter again; never a seed`"*, P0 §2). Any jc node
still reading it would silently get a counter as its seed.

- **Addon API used** (P0 §2, §3):
  - `static func evaluate(graph : FlowGraphResource, inputs : Dictionary = {}, seed : int = 0, params : Dictionary = {}, owner : Node3D = null) -> Dictionary`
  - `var seed : int = 0 # graph seed` on `EvaluationContext`
  - *"`evaluate_graph` must work with `parent_ctx.owner == null`"*. The jc graphs contain no
    spawner, and if a dock user wires one in it will *"call `setError(...)` and pass their
    input through"* instead of crashing.
  - *"`_build_evaluation_state` copies `seed`, `component_id` and `overrides` from the parent
    context into the child context"*. This keeps `ctx.seed` available inside
    `jc_room_loop`'s nested evaluation (N7).
- **Decision: read `ctx.seed` raw, not `effective_seed()`.** Today every jc node receives the
  floor seed unchanged through `eval_id`. `ctx.seed` carries the same integer, so outputs stay
  identical. `preExecute` also re-seeds the member `rng` with
  `hash([ctx.seed, settings.random_seed]) & 0x7fffffff` (P0 §2), but no jc node reads that
  member (§1.2). Switching to derived seeds is a separate, output-changing decision: see
  step V.
- **Files and edits**:
  - `scripts/systems/flow_dungeon.gd`: split `_evaluate_graph` (`:59-109`) into
    `static func evaluate_raw(theme, floor_index, seed_val, plan) -> Dictionary`, which
    returns the outputs dict, and `_normalize_outputs(evaluate_raw(...))`.
    `tests/golden/pcg_golden.gd::_digest_graph` then calls `FlowDungeon.evaluate_raw` so the
    graph layer always matches the production path. Run the compare after this test-only
    edit; it must still be 0 diffs.
    ```gdscript
    # before (flow_dungeon.gd:66-74, 94-107)
    var ctx := FlowData.EvaluationContext.new()
    ctx.eval_id = seed_val
    ctx.graph = graph
    ctx.runtime_params = { "floor_index": floor_index, ... }
    ...
    var flow_root: FlowGraphNode3D = null
    if host != null and host.is_inside_tree():
        flow_root = FlowGraphNode3D.new(); flow_root.name = "JCFlowTempRoot"
        host.add_child(flow_root); ctx.owner = flow_root
    var outputs: Dictionary = FlowNodeIO.evaluate_graph(graph, {}, ctx, {})
    if flow_root != null: flow_root.queue_free()

    # after
    var params := _runtime_params(theme, floor_index, plan)   # same keys as today
    return FlowNodeIO.evaluate(graph, {}, seed_val, params, null)
    ```
    Keep the now-unused `host` parameter of `generate_floor` for this step so that
    `floor_generator.gd:142` and the five audit call sites stay untouched. Mark it deprecated.
  - `scripts/pcg_nodes/jc_hotel_layout.gd:36`, `jc_spawn_markers.gd:53`,
    `jc_cart_traps.gd:75`, `jc_room_dressing.gd:57`:
    `ctx.eval_id if ctx.eval_id != 0 else settings.random_seed` →
    `ctx.seed if ctx.seed != 0 else settings.random_seed`.
  - `jc_room_loop.gd:115`: `int(ctx.eval_id) * 1000003 + …` → `int(ctx.seed) * 1000003 + …`.
  - `jc_room_interior.gd:112`: `runtime_params.get("room_seed", ctx.eval_id)` →
    `runtime_params.get("room_seed", ctx.seed)`.
  - Header comments: `flow_dungeon.gd:9-13` and `jc_hotel_layout.gd:5-7`.
- **Seed 0**: `rng.randi()` can return 0. Then `ctx.seed == 0`, which takes the legacy
  per-node path, exactly like today's `eval_id == 0` fallback.
- **`runtime_params["seed"]`**: P0 mirrors the seed into `runtime_params`. `jc_room_loop`
  copies runtime_params into each room (`:99`). No jc node reads a `"seed"` key, so this is
  harmless.
- **Delete**: the hand-built context and the throwaway `FlowGraphNode3D` (`flow_dungeon.gd:66-74`,
  `:94-107`). This also removes the per-floor "no graph resource assigned" warning (G5).
- **Verify**: golden 0 diffs; audit PASS. The audit checks at `generation_audit.gd:505` and
  `:747` are the sharpest test here, because they compare a direct carve at the raw seed with
  the graph's output. Also, `grep -rn eval_id scripts/` must return nothing.

### Step C: carry the whole `Data` across the boundary

**Addon API used** (P0 §6):

- *"`output.gd` copies `data_attrs`, `tags` and `kind` from its input onto the Data it emits"*
- `static func scalar(name, value, data_type := Invalid) -> Data`
- `func first(name, default = null)`
- `func container(name)`, which returns *"the packed container / Array, or null"*
- `set_data_attr(name, value, data_type)` and `get_data_attr(name, default)`

`first` and `container` *"accept every selector form `findStream` accepts (`@last`,
`position.x`, `@data.foo`, `Yaw`)"*.

**P0 constraint**: a data attribute is a **single value** (`flow_data.gd:460-471`; the
Resource container is `Array[Resource]`, `:221-222`). A `PackedStringArray` table therefore
cannot become a data attribute directly. Until F1 lands, use a one-field Resource wrapper,
which works on P0 as specified:

```gdscript
# scripts/systems/jc_string_table.gd (new)
class_name JCStringTable
extends Resource
@export var items: PackedStringArray
static func of(a: PackedStringArray) -> JCStringTable:
	var t := JCStringTable.new(); t.items = a; return t
```

If the addon ships array-valued data attributes (F1) in time, use them instead and skip the
wrapper.

**C1, accessors** (dressing output: none; graph output: none):

- Replace all 22 accessor copies with `Data.container()` or `Data.first()`. Keep the
  `is PackedFloat32Array` style type guards where the code relies on a typed empty default.
- Files: `flow_dungeon.gd:141-152, 310-375`; `jc_cart_traps.gd:34-46, 84-102`;
  `jc_hotel_skin.gd:41-49, 101-118`; `jc_room_dressing.gd:31-34, 92-109`;
  `jc_room_loop.gd:200-205, 231-241`; `jc_room_interior.gd:1018-1028`;
  `jc_spawn_markers.gd:40-45, 72-89`.
  ```gdscript
  # before (jc_spawn_markers.gd:82-89)
  var rec = data.findStream(stream_name)
  if rec == null: return fallback
  var container = rec["container"] if typeof(rec) == TYPE_DICTIONARY else rec.container
  if container is PackedFloat32Array and container.size() > 0: return container[0]
  return fallback
  # after
  cells_data.first("@data.cell_size", 4.0)
  ```

**C2, `prop_meshes`** (dressing output: none; graph output: `PropPoints` streams and attrs):

- `jc_room_dressing.gd:84-88`:
  `out.set_data_attr("prop_meshes", JCStringTable.of(meshes), FlowData.DataType.Resource)`.
  Delete the comment at `:85-87`.
- `flow_dungeon.gd:145-152`:
  `result["prop_meshes"] = (props.first("@data.prop_meshes") as JCStringTable).items`, with a
  null guard.

**C3, room tables on `Cells`** (no output change; `Cells` never reaches an output node):

- `jc_hotel_layout.gd:84-85, 91-92`: `room_tags`, `room_door_states` and `room_archetypes`
  become `JCStringTable` data attributes.
- `jc_room_loop.gd:48-50, 171-172, 200-205`: read them with
  `cells.first("@data.room_tags").items`.
- **Delete** `JCGenTypes.join_table`, `split_table` and `STREAM_TABLE_DELIMITER`
  (`jc_gen_types.gd:64-81`) and doc lines `:7-8`. `grep -rn "join_table\|split_table"` must
  return nothing.

**C4, endpoint facing** (a separate commit, with an expected change):

- `jc_spawn_markers.gd:92-98`:
  ```gdscript
  # before: one-point stream whose rotation.y encodes the inward direction
  var yaw_deg := rad_to_deg(atan2(inward.x, inward.z))
  data.registerStream(FlowData.AttrRotation, PackedVector3Array([Vector3(0, yaw_deg, 0)]), ...)
  # after
  var data := FlowData.Data.scalar(FlowData.AttrPosition, p, FlowData.DataType.Vector)
  if inward != Vector3.ZERO:
  	data.set_data_attr("inward", inward, FlowData.DataType.Vector)
  ```
- `flow_dungeon.gd:227-230`: `result["spawn_inward"] = sp.first("@data.inward", Vector3.ZERO)`
  with a null guard. **Delete** `_first_yaw_dir` (`:234-239`).
- **Expected diffs**: in the dressing layer, only `spawn_inward` and `elevator_inward`, in
  cases whose docks face ±X or −Z. The old value carried a ~4e-8 residue (verified); the new
  one is the exact dock vector. In the graph layer, `SpawnPoint` and `ElevatorPoint`.
  Consumers (`floor_generator.gd:150-158` bay guards, and the cab dock in `game.gd`) see a
  sub-micrometre shift. Re-baseline in the same commit.
- **Verify** for C overall: C1–C3 golden with 0 dressing diffs and graph diffs limited to
  `PropPoints`; C4 golden diffs within the allowlist above; audit PASS, including THEME DOORS
  (`generation_audit.gd:459-497`), which reconstructs bay planes from the inward vectors.

### Step D: collapse four theme graphs into one plus overrides (byte-identical)

- **Addon API used** (P0 §2, §4):
  - `var overrides : Dictionary = {} # see §4` on `EvaluationContext`
  - The override loop runs *"after `dict_to_resource(saved_settings, instance.settings)` and
    before `refreshFromSettings`"*.
  - *"Keys may also be prefixed with the graph's resource basename … unprefixed keys apply in
    every graph of the evaluation tree. A key that matches no node is a `push_warning` once
    per evaluation."*

  Because `evaluate()` has **no overrides parameter** (F5), GodotJC uses the lower-level
  form:
  ```gdscript
  var ctx := FlowNodeIO.make_context(null, seed_val, params)
  ctx.overrides = _overrides_for(theme, plan)
  return FlowNodeIO.evaluate_graph(graph, {}, ctx)
  ```
- **Files**:
  - `git mv resources/pcg/hotel_grounded.tres resources/pcg/hotel_floor.tres`. The base
    values are grounded's. Keep the uid and update `resource_name` to `HotelFloor`.
    **Delete** `hotel_basement.tres`, `hotel_ethereal.tres` and `hotel_mental.tres`.
  - `scripts/data/floor_theme_def.gd` (after `:23`): add
    `@export var pcg_overrides: Dictionary = {}`, a map of `"node/prop"` to value, or of a
    fan-out key to value (below).
  - `flow_dungeon.gd`:
    - Add a fan-out table so the "must match" knobs have a single source:
      ```gdscript
      const FANOUT := {
      	"door_fraction": ["skin/door_fraction", "carttraps/fake_door_fraction", "dressing/door_fraction"],
      	"door_min_spacing": ["skin/door_min_spacing", "carttraps/fake_door_min_spacing", "dressing/door_min_spacing"],
      }
      ```
    - `_overrides_for(theme, plan)` expands `theme.pcg_overrides`: keys containing `/` pass
      through, other keys go through `FANOUT`. Prefix every key with `hotel_floor:` (R8).
    - `:22` becomes `DEFAULT_GRAPH_PATH := "res://resources/pcg/hotel_floor.tres"`.
    - `:62` drops `CACHE_MODE_IGNORE`. Graphs *"stay immutable and cacheable"* (Review §3).
  - `resources/floors/{grounded,basement,ethereal,mental}.tres`: set `graph_path` to
    `hotel_floor.tres` (or clear it) and paste `pcg_overrides` from Appendix B.
    `vertical_slice.tres` needs no change.
  - `scripts/core/floor_director.gd:271, 278, 285, 292`: the coded fallback themes get the
    new `graph_path` **and the same `pcg_overrides`**. Otherwise the fallback themes silently
    lose their look (R15).
  - `jc_room_loop.gd:37`: drop `CACHE_MODE_IGNORE` for the same reason.
- **Why this is exact**: overrides are applied with `settings.set()`. `dict_to_resource`
  applies saved values the same way (`flow_nodes_io.gd:48` and following), so the setters
  clamp identically. `.tres` float literals parse to the same doubles, and colours are
  float32 either way. Keep the value **types** identical to the setting types: integers for
  `door_fraction`, `width_jitter` and `spur_width` (R9).
- **Verify**: golden 0 diffs in all 144 cases. This is the proof the collapse is exact, since
  the golden evaluates the four themes through `evaluate_raw` with each theme's overrides.
  Audit PASS; THEME DOORS evaluates all four themes. In the editor, open `hotel_floor.tres`
  and check there are no override warnings in the log for a floor, including the per-room
  nested evaluations (R8).

### Step E: runtime_params and `$param` bindings (byte-identical)

- **Addon API** (P0 §4): `@export var bindings : Dictionary = {} # "property_name" -> "param_name"`,
  resolved from *"`input_data_map[param_name]` … `ctx.runtime_params[param_name]` …
  `ctx.variables[param_name]`"* at the **lowest** precedence (*"wired port > override >
  binding > saved"*).
- **Finding**: no stock node in GodotJC's graphs could consume a knob. The graph is 6 jc nodes
  plus 16 outputs (`hotel_grounded.tres:145-431`). Under the brief's rule, every key stays in
  `runtime_params`. Disposition:

| Key | Set at | Read at | Semantics | Decision |
|---|---|---|---|---|
| `floor_index` | `flow_dungeon.gd:70` | `jc_hotel_layout.gd:35` | Input to depth scaling in node code | keep |
| `depth_tier` | `:71` | `jc_hotel_skin.gd:80` | Library option | keep |
| `theme_id` | `:72` | `jc_room_interior.gd:182` (nested per-room graph) | Selects grounded plans | keep |
| `is_anomaly` | `:73` | **nobody** | – | delete |
| `hb_hall_branches_delta` | `:81-82` | `jc_hotel_layout.gd:48` | Delta. The sum is unclamped above, while the setting clamps to 10 (`jc_hotel_layout_settings.gd:48-51`) | keep. A binding would change semantics |
| `hb_max_rooms_delta` | `:85-86` | `jc_hotel_layout.gd:42-44` | Delta after depth scaling, `maxi(2, …)` | keep |
| `hb_torch_prob` | `:87-88` | `jc_hotel_layout.gd:45` | **Absolute**, and the director should beat the theme | fold into the override `hotel_floor:layout/torch_probability`, composed **after** the theme overrides in `_overrides_for`. Delete the read at `:45`. A binding cannot beat a theme override (precedence), so compose in the caller. The setter clamps to [0,1], matching `FloorIntentDef.torch_probability`'s `@export_range(0.0, 1.0)` (`scripts/data/floor_intent_def.gd:23`); no intent sets it today |
| `hb_light_energy_mult` | `:89-90` | `jc_hotel_skin.gd:53` | Multiplier on the (now overridden) setting | keep |
| `hb_target_route_m` | `:83-84` | `jc_hotel_layout.gd:258` | Diagnostic warning only | keep |
| `room_programs` | `:91-93` | `jc_hotel_layout.gd:89` | Array | keep |
| `room_id`, `room_tag`, `room_tags`, `room_archetype_id`, `room_seed` | `jc_room_loop.gd:99-115` | `jc_room_interior.gd:107-112, 171` | Per-iteration | keep until step L |
| `door_state` | `jc_room_loop.gd:109` | **nobody** (used locally in the loop at `:116`) | – | delete the param key |

- **Bindings adopted this round**: none. Revisit once F9 lands. Binding
  `skin.door_fraction`, `carttraps.fake_door_fraction` and `dressing.door_fraction` to one
  graph input would single-source the knob inside the graph for dock previews too. Today
  that only works when the caller passes the parameter.
- **Verify**: golden 0 diffs (planA exercises every hb key); audit PASS; the HOTEL DIRECTOR
  check (`generation_audit.gd:1055-1110`) still builds 48 plans.

### Step V: optional, output-changing, at a release boundary

Bundle V1 and V2 into one release so players and tests absorb a single break.

**V1, per-node seed decorrelation** with `effective_seed()`:

- P0 §2: *"`effective_seed = int(hash([ctx.seed, settings.random_seed]) & 0x7fffffff)`"* and
  *"Nodes must read `rng.seed` (or a new `func effective_seed() -> int` …) instead of
  `settings.random_seed`"*. Replace the four `ctx.seed if …` expressions from step B with
  `effective_seed()`.
- **Effect**: every floor changes. The layout seeds from `hash([S, 12345])`
  (`hotel_floor.tres` `layout.random_seed`); the other nodes seed from `hash([S, 0])`.
- **Audit breaks**: `generation_audit.gd:505` and `:747` carve with the raw `seed_val`. Change
  them to `FlowDungeon.layout_seed(seed_val)`, a new helper wrapping the addon formula (see
  F12). This avoids duplicating the hash.
- **Saved games**: the save holds only `run_seed` and `current_floor`, and "the floor itself
  is regenerated from run_seed + current_floor on resume" (`run_manager.gd:147-149`). A
  resumed floor **already differs** from the pre-save floor, because `restore_run` re-seeds
  `RunManager.rng` from `run_seed` (`run_manager.gd:171-173`) and the floor seed is the next
  `rng.randi()` (`floor_generator.gd:142`). There is no seed-entry or replay feature;
  `meta_progression.gd:466` stores `run_seed` for display only. Therefore:
  - add **no legacy flag**, and accept the break at the release boundary;
  - add `"gen_version": 2` to `RunManager.to_dict()` (`run_manager.gd:150-161`) for bug
    reports;
  - re-baseline the golden.

  If a legacy mode is ever needed, the step B form (`ctx.seed` raw) **is** the legacy mode.
  Keep it behind a const rather than a per-save flag.
- **Recommendation**: adopt V1 only if a correlation problem is observed. Each jc node passes
  the seed into a library that derives its own streams (e.g. `hotel_skin_lib.gd:853`,
  `:1345-1346`), and nothing today shows cross-node correlation.

**V2, fix the truncated route (N3)**. This is a real bug; fix it even without V1:

- Add a third output pin, `Route`, to `jc_hotel_layout` (`meta_node.outs`, `:25-28`), carrying
  a Data whose `position` stream is `SpatialAnalyzer.center_route_points(analysis)`, or
  `route_points` when that is empty. Add an input pin to `jc_hotel_skin` and `jc_cart_traps`,
  and wire it in `hotel_floor.tres`; after step D there is only one graph to edit. Replace
  `_route_vec3s` (`jc_hotel_skin.gd:114-118`, `jc_cart_traps.gd:94-102`) with
  `get_input(1).container("position")`. Delete the `@data.*route_cells` writes
  (`jc_hotel_layout.gd:104-115`).
- **Effect**: `fake_door_kind` zones (`hotel_skin_lib.gd:295-299`) and cart-trap bend
  weighting (`hotel_skin_lib.gd:1372`) start working as documented, so door kinds and trap
  picks change.
- **Verify**: audit THEME DOORS (2–4 traps per floor, bay clearance,
  `generation_audit.gd:487-490`), a playtest of the four themes, and a re-baseline.

### Step L: replace `jc_room_loop` with the stock group-by loop (P1, not this round)

- **Target shape** (Review §3 P1, "Group-by loop"):
  ```
  layout.Cells → jc_room_openings → filter(room >= 0) → loop(iterate_by="room",
                 subgraph=room_interior.tres) → out RoomInterior
  ```
  - `iterate_by`, and *"per-iteration `runtime_params` injection: `iteration_index`,
    `iteration_key`, and the partition's `@data.*` attributes"*.
  - `jc_room_interior` takes `room_id` from `iteration_key`. It reads tag, door state and
    archetype by indexing the `@data` tables from C3, which the loop injects.
- **What jc_room_loop does that a plain group-by does not**, and where each piece goes:
  1. Loose `T_OPENING` points with `room < 0` are attached to every adjacent room
     (`_append_nearby_openings`, `jc_room_loop.gd:175-197`). One point can belong to several
     partitions. Move this to a pre-pass node, `jc_room_openings`, that duplicates such points
     per adjacent room with `room` rewritten. This can be done now, byte-identical, if the
     duplicated points keep today's order.
  2. The ambient audio anchor (`:116-127`) and the fallback ceiling light (`:150-159`) move
     into `jc_room_interior`: emit the anchor first and the fallback light last, to preserve
     per-room order. This can be done now, byte-identical.
  3. The `room` and `archetype` output streams (`:161-167`) are emitted by `jc_room_interior`.
  4. Rooms are iterated in ascending id order (`:73-74`). The stock loop must guarantee
     ascending partition order (F10).
  5. `room_seed = seed*1000003 + rid*97 + 13` (`:115`) is keyed by **room id**. P0's loop seeds
     by **iteration index** (*"iteration `i` … `hash([ctx.seed, i])`"*), so outputs change at
     the swap unless the addon provides keyed seeding or exposes the parent seed (F10).
- **Keep until then**: `jc_room_loop.gd` as is, apart from the step B/C edits. Do items 1–3
  early to shrink the swap.
- **Delete at the swap**: `jc_room_loop.gd` and its settings (270 lines).

### Step H: documentation drift (can run in parallel with anything)

Each step updates the docs it invalidates. In addition, the following is **already stale at
`d38d39d`** and should be fixed in the first docs commit.

`docs/FLOOR_GENERATION.md`:

- `:52` lists `hb_hall_branches`; the real key is `hb_hall_branches_delta`
  (`flow_dungeon.gd:81-82`). It also omits `hb_target_route_m` (`:83-84`).
- `:422` says the delta is "an absolute replacement … yields *one* branch". The code applies
  it as a delta (`jc_hotel_layout.gd:46-48`, whose comment says "it used to REPLACE it").
- `:66-69` shows skin with "10 outputs" including `Sconces`. The graph has no Sconces output
  node (skin port 6 is unwired), which `:319` of the same doc also says.
- `:78` and `:289` say `door_fraction` ramps "50 → 62 → 68 → 80". The graphs set
  **28 / 24 / 32 / 38** (grounded / basement / ethereal / mental, Appendix B).
- `:30` and `:60` claim the graph and fallback "cannot drift apart". The fallback's
  parameters already differ: `dim = 16 + 2f`, `rooms = 5 + f/2` (`flow_dungeon.gd:244-246`)
  versus the graph's `32 + 2f` and `9 + 0.5f` (`hotel_grounded.tres:150-166`). Reword this
  to "same libraries, different parameters".
- Rewrite after the migration: `:51` (seed in `eval_id`), `:53` (temporary root), `:54` and
  `:275` (`;`-joined tables), `:347` (`room_seed = eval_id …`), `:408` (yaw encoding),
  `:473` ("per theme graph"). `:56`, the load-hang gotcha, **stays**; see R6.

`docs/integration/gf_pcgodot.md`:

- `:3-7`: add the vendored SHA and the re-vendor procedure from A1.
- `:43-55`: `execute()`-only `FlowGraphNode3D`. Replace with the P0 API and a note that
  GodotJC uses `FlowNodeIO.evaluate`.
- `:57-97` and `:144-235`: the `dungeon_generator` contract and the "Style A/B" recipe,
  including `for c in pcg.get_children(): c.queue_free()` at `:188` and the reachability
  claim at `:157-163`, were never implemented. GodotJC uses `jc_hotel_layout` →
  `GFDungeonCarver`. Delete them and point to `FLOOR_GENERATION.md` §2.
- `:136-137`: `register_node_directory` "not needed". Replace with the
  `flow_nodes/node_directories` setting.
- `:139-140` and `:248`: "`project.godot` was intentionally NOT modified". The plugin is
  enabled at `project.godot:47`.
- `:111-126` and `:243-244`: native status. Add "GodotJC uses no native classes" (R5) and
  update Linux per release.

`docs/integration/ue_pcg_alignment.md`:

- `:77` and `:128`: seed via `ctx.eval_id` / runtime_params becomes `ctx.seed`.
- `:85` and `:132`: `door_fraction` "default 0 … mental keeps 80" and "(62)". The actual
  values are 28/24/32/38.
- `:88`: `has_ceiling` "default OFF". `floor_theme_def.gd:71` defaults to `true`.
- `:139`: `bath_chance (0.85)`. The graphs set `0.0` (`hotel_grounded.tres:368`) because the
  room subgraph owns baths.

---

## 3. Risk register

| # | Risk | Likelihood / impact | Mitigation |
|---|---|---|---|
| R1 | **Seed derivation change** (P0 §2 `hash([seed, node_seed])`) silently changes every floor and breaks the raw-seed cross-checks at `generation_audit.gd:505, 747` | Certain if adopted / high | Step B reads `ctx.seed` raw, so it is byte-identical. Derived seeds are isolated in V1 with an audit helper and a re-baseline |
| R2 | The new addon stops propagating the caller's `eval_id` into child contexts (today `flow_nodes_io.gd:843`). A1 would then change every floor while GodotJC still hand-builds the context | Low / high | A1 golden catches it (every dressing key diffs). F7 asks the addon to pin this |
| R3 | The yaw round-trip is not bit-exact (verified), so C4 cannot be 0-diff | Certain / negligible | Allowlist of `spawn_inward` and `elevator_inward` only; re-baseline in the same commit |
| R4 | **Latent bug N3**: routes truncated to 1 point by `@data.` | Present today / medium (design intent not realised) | Fix in V2. F1 asks the addon to warn |
| R5 | **Native library**: GodotJC calls no native class. `grep GDKdTree\|GDRTree\|GDStreamUtils` finds nothing in `scripts/` or the jc nodes, the graphs use only jc, `input` and `output` nodes, and the review's native-only node list (`distance`, `difference`, …) is unused. The engine still loads `bin/flow.gdextension` at startup, and upstream's copy lists a `linux.x86_64` `.so` that is not committed, which means an error line on Linux | Certain on Linux / cosmetic | Vendor `bin/` as released; ignore the log line or wait for F13. Windows binaries are present |
| R6 | **load() hang** (`flow_dungeon.gd:15-17`). P0 **does not remove the cause**: `evaluate_graph` still `load()`s each node script (`flow_nodes_io.gd:785`) and instantiates `@tool` `GraphNode` Controls. The fix is the P1 `FlowElement` split (Review §3: "no more `@tool` class-web hangs at runtime") | Medium / high (editor hang) | Keep the `class_name` references (`FlowNodeIO`, `FlowData`, `FlowGraphResource`) in FlowDungeon and the path preloads in nodes (`jc_hotel_layout.gd:10-12`). Never add a game-side `load("res://scripts/pcg_nodes/…")`; after A2 the addon resolves node scripts. The nodes' own `load()` calls on archetype `.tres` data (`jc_hotel_layout.gd:240`, `jc_room_interior.gd:1031-1045`) are data, not the hang. Re-test in-editor play after A2 |
| R7 | **class_name resolution in headless runs**: `.godot/` is gitignored, so a fresh clone has no class cache. The moved settings declare `class_name` (e.g. `JCHotelLayoutSettings`), so a stale cache points at old paths. `--script` mode does not run editor plugins, so node directories must be read by `evaluate_graph` itself | Medium / medium. A failure shows as the **silent fallback** (G1) | CI order: `--import`, then audit, then golden. A2 verification from a fresh clone. The golden `used_flow` key and the audit `used_flow` checks catch the fallback |
| R8 | **Override warning spam**: `jc_room_loop` evaluates `room_interior.tres` once per room with the parent ctx (`jc_room_loop.gd:128`), so unprefixed `layout/…` keys match nothing there | Medium / low (log noise, hidden real warnings) | Prefix keys with `hotel_floor:`; F4 asks for tree-scoped warnings |
| R9 | **Override value types**: an int setting given a float from a `.tres` Dictionary (`24.0`) may fail `set()`. P0 specifies numeric coercion for bindings only | Medium / medium (silently keeps the saved value) | Author ints as ints. The D golden catches it. F4 asks for the same coercion as bindings |
| R10 | **Graph format v2**: re-saving hand-authored v1 graphs from the dock rewrites every key, adds noise, and could drop unknown keys | Medium / medium | Do not re-save during A. Re-save `hotel_floor.tres` deliberately after D and run the golden |
| R11 | **Cross-platform float determinism**: `sin`, `cos` and libm can differ between MSVC (Windows dev) and glibc (Linux CI) | Medium / low | Capture and compare on the same OS and engine build; keep per-platform baselines if CI runs Linux |
| R12 | **Engine version**: GodotJC targets 4.7 (`project.godot:16`); the prototype ran on 4.6 | Low | Capture on the team's 4.7 binary |
| R13 | **Export filters**: nodes outside the addon folder must be exported, and `export_presets.cfg` is gitignored | Low / high | Exported smoke test in A2 |
| R14 | Nested evaluations must receive `seed` and `overrides` | Low | P0 §3 copies them; the golden covers `RoomInterior` |
| R15 | Coded fallback themes (`floor_director.gd:261-292`) lose their look after D | Medium / low | Give them the same `pcg_overrides` in D |
| R16 | Between A1 and B the throwaway `FlowGraphNode3D` still exists. The new `_ready()` calls `generate()` when `generate_on_ready` is true, with a null graph | Low / cosmetic | Short window; B deletes it. F8 asks for a silent no-op |

---

## 4. Effort and parallelism

| Step | Effort | Depends on | Can run in parallel with |
|---|---|---|---|
| 0 Baseline | 0.25 d | – | H (docs) |
| A1 Re-vendor | 0.5 d | 0, addon release | H |
| A2 Move nodes | 0.5 d | A1 | H |
| B evaluate and seed | 0.5 d | A2 | H |
| C1–C3 Data helpers and tables | 1 d | B | D (D touches `.tres`, `floor_theme_def.gd`, `floor_director.gd` and `flow_dungeon._overrides_for`; C touches jc nodes and `_normalize_outputs`. Coordinate the edits to `flow_dungeon.gd`) |
| C4 Direction | 0.25 d | C1 | D, E |
| D One graph and overrides | 1 d | B | C, E |
| E runtime_params cleanup | 0.25 d | D (the torch fold uses `_overrides_for`) | C |
| V1 / V2 | 1 d and a playtest | D (edit one graph), C1 | – (release boundary) |
| L Loop pre-work (items 1–3) | 0.5–1 d | C3 | anything after C3 |
| L Swap to stock loop | 1–1.5 d | addon P1 loop, F10 | – |
| H Docs | 0.5 d | – | everything |

Critical path: 0 → A1 → A2 → B → {C, D} → E, about **4 developer-days** for the byte-identical
part. V is a release decision, and L waits for the addon's P1.

---

## 5. Acceptance criteria

- [ ] `tests/golden/pcg_golden.gd` and `pcg_baseline.json` are committed, captured on the
      pre-migration addon. The commit message names the engine build and OS.
- [ ] `tests/run_audit.ps1` runs the audit, then the golden compare, and fails on either.
- [ ] A1, A2, B, C1–C3 (dressing layer), D and E each pass the golden with **0 diffs**. C4
      diffs only `spawn_inward` / `elevator_inward` (dressing) and
      `SpawnPoint` / `ElevatorPoint` (graph).
- [ ] `generation_audit.gd` exits 0 after every step, with no new warnings beyond the baseline
      count.
- [ ] `addons/flow_nodes_editor/` equals an upstream release tree (`diff -r` against
      `git archive`) with no `jc_*` and no `~*.TMP` files. The vendored SHA is recorded in
      `docs/integration/gf_pcgodot.md`.
- [ ] `project.godot` has `flow_nodes/node_directories = ["res://scripts/pcg_nodes"]`. A fresh
      clone passes `--import`, then audit, then golden headless. In-editor play generates a
      floor without a hang.
- [ ] `grep -rn "eval_id" scripts/` returns nothing.
      `grep -rn "FlowGraphNode3D\|EvaluationContext.new" scripts/` returns nothing.
- [ ] `grep -rn "join_table\|split_table\|_first_yaw_dir\|TYPE_DICTIONARY else" scripts/`
      returns nothing.
- [ ] `resources/pcg/` contains exactly `hotel_floor.tres` and `room_interior.tres`. The four
      `FloorThemeDef`s and the four coded fallback themes carry `pcg_overrides`. No override
      warnings appear during a floor generation.
- [ ] `FloorGenerator` (`scripts/systems/floor_generator.gd`) has no diff across the whole
      migration.
- [ ] The listed doc drift in `FLOOR_GENERATION.md`, `gf_pcgodot.md` and `ue_pcg_alignment.md`
      is fixed, and `README.md:62` points at `scripts/pcg_nodes/`.
- [ ] (If V ships) `RunManager.to_dict` carries `gen_version`, the audit derives layout seeds
      through the helper, and the N3 route reaches `jc_hotel_skin` and `jc_cart_traps` with
      more than one point.

---

## Feedback to the addon

These are gaps in the P0 contract as it applies to GodotJC, to fold into the current round
where cheap.

1. **F1 – `@data.` silently truncates.** `registerStream("@data.x", container)` with
   `size() > 1` keeps element 0 (`flow_data.gd:460-471`). GodotJC shipped a bug from this
   (N3). At minimum, `push_warning` when `size() > 1`. Better, define array-valued data
   attributes: `set_data_attr(name, PackedStringArray / PackedVector3Array)`, with
   `first` / `get_data_attr` returning the array. That would remove the `JCStringTable`
   wrapper in step C.
2. **F2 – Resource-valued data attributes need content hashing** in the golden harness. The
   `DataType.Resource` wrapper is the only P0-legal way to carry a table, and hashing it by
   instance id is unstable across processes. A `Data.content_hash()` shared by harness and
   games would settle this.
3. **F3 – The golden harness must run on the pre-P0 addon.** Feature-detect
   `FlowNodeIO.evaluate`, and fall back to a hand-built context with `eval_id = seed`.
   Otherwise no project can capture a pre-migration baseline. It also needs per-graph fixtures
   for seeds, `runtime_params` and input Data (`room_interior.tres` needs `RoomCells`). It
   needs a project-local output path, a non-zero exit code on diff, and a documented rule that
   baseline and compare must share an engine build and OS.
4. **F4 – Overrides:**
   - (a) apply the same numeric coercion as bindings;
   - (b) scope the "matches no node" warning to the **whole evaluation tree**, not each nested
     `evaluate_graph`, because custom loop nodes re-evaluate subgraphs with the parent context;
   - (c) confirm that a basename prefix also targets the **root** graph, not only subgraphs.
5. **F5 – `FlowNodeIO.evaluate()` has no `overrides` argument.** Add
   `overrides : Dictionary = {}`, or let `make_context` take it, so owner-less callers do not
   need the two-step `make_context` + `evaluate_graph` form.
6. **F6 – `make_context(owner : Node3D)` vs `EvaluationContext.owner : FlowGraphNode3D`.** A
   caller passing its own `Node3D` host would hit a type error. Pick one type.
7. **F7 – Pin `eval_id` inheritance.** State that `_build_evaluation_state` keeps copying the
   parent's `eval_id` verbatim (today `flow_nodes_io.gd:843`), and that only
   `make_context` / `generate` assign the counter. Legacy callers that hand-build contexts stay
   byte-identical until they migrate. Add this to the evaluator tests.
8. **F8 – A graph-less `FlowGraphNode3D` should be silent.** With `generate_on_ready` and a
   null graph, `generate()` should return `{}` without warning. Today every GodotJC floor logs
   "no graph resource assigned" (`flow_node.gd:113-116`).
9. **F9 – Bindings should fall back to the graph's `in_params` default** when the parameter is
   absent from `input_data_map`. Then one declared graph input can single-source a knob
   (GodotJC's three `door_fraction` copies) in dock previews as well as at runtime.
10. **F10 – For the P1 loop:**
    - (a) define partition order as ascending key;
    - (b) offer seeding by `iteration_key`, not only by index, or expose the parent seed in
      the iteration context. Keyed seeding survives adding or removing a partition and matches
      GodotJC's rid-keyed `room_seed`;
    - (c) inject `@data.*` table attributes (F1) as per-iteration params.
11. **F11 – Document the exact `meta_node` keys** for category and colour (and aliases) now
    that editor tables are gone. The jc nodes carry none today.
12. **F12 – Expose the seed formula** as a static, e.g. `FlowNodeBase.derive_seed(graph_seed,
    node_seed)`. Tests and games that cross-check (GodotJC's audit) should not copy
    `hash([a, b]) & 0x7fffffff`.
13. **F13 – `flow.gdextension` must not list binaries that are not committed or released.**
    Upstream lists `libflow.linux.template_debug.x86_64.so`, which is untracked.
14. **F14 – Output collection without `out_params`** (`flow_nodes_io.gd:995-1004`) is what
    GodotJC's 16 named outputs rely on. Keep it, cover it in the evaluator tests, and make sure
    graph-format v2 migrations do not require `out_params` or rewrite hand-authored `version: 1`
    graphs in a way that changes evaluation.
15. **F15 – The registry must read `flow_nodes/node_directories` inside `evaluate_graph`**, not
    only at plugin load. Headless `--script` runs and exported games never load the editor
    plugin, and a resolution failure makes games fall back silently.

---

## Appendix A: `tests/golden/pcg_golden.gd`

Validated on a scratch copy against the current addon. It produced 144 cases, replayed with
0 diffs, and the negative control behaved as expected. After step B, replace the body of
`_digest_graph`'s evaluation with `FlowDungeon.evaluate_raw(theme, floor_index, seed_val,
plan)` so overrides from step D are included.

```gdscript
extends SceneTree
## PCG golden baseline for GodotJC (pre-migration capture + per-step compare).
##   capture: godot --headless --path . --script res://tests/golden/pcg_golden.gd -- --write
##   compare: godot --headless --path . --script res://tests/golden/pcg_golden.gd
## Two layers, both keyed "<layer>|<theme>|f<floor>|s<seed>|<plan>":
##   dressing  FlowDungeon.generate_floor() after FloorDressing.ensure(): what the game consumes.
##   graph     every named output of the theme graph, streams + data_attrs + tags + kind.
## Only public, pre-P0 API is used (FlowNodeIO.evaluate_graph + hand-built context), and
## FlowNodeIO.evaluate() is feature-detected so the SAME file keeps working after step B.

const BASELINE := "res://tests/golden/pcg_baseline.json"
const CASES := [
	{"theme": "res://resources/floors/grounded.tres", "floor": 0},
	{"theme": "res://resources/floors/grounded.tres", "floor": 3},
	{"theme": "res://resources/floors/basement.tres", "floor": 5},
	{"theme": "res://resources/floors/ethereal.tres", "floor": 10},
	{"theme": "res://resources/floors/mental.tres", "floor": 15},
	{"theme": "res://resources/floors/vertical_slice.tres", "floor": 0},  # no graph_path: default graph
]
const SEEDS := [1, 2, 3, 4, 19, 123456789]
## Plans stand in for HotelDirector.current_plan (read by FlowDungeon._director_plan).
const PLANS := {
	"noplan": {},
	"planA": {
		"gen": {"hall_branches_delta": 2, "max_rooms_delta": 1, "light_energy_mult": 0.78,
			"target_route_m": Vector2(100, 240)},
		"room_programs": [
			{"door_state": "special", "archetype_id": "", "program_id": "golden_special_000"},
			{"door_state": "ambient", "archetype_id": "", "program_id": "golden_ambient_001"},
			{"door_state": "playable", "archetype_id": "", "program_id": "golden_playable_002"},
		],
	},
}

var _director: Node


func _initialize() -> void:
	var write := OS.get_cmdline_user_args().has("--write")
	_install_director_stub()
	var got := {}
	for c in CASES:
		var theme: Resource = load(c["theme"])
		var tid := str(theme.get("id"))
		for plan_id in PLANS:
			_director.set("current_plan", PLANS[plan_id])
			for s in SEEDS:
				var tag := "%s|f%d|s%d|%s" % [tid, c["floor"], s, plan_id]
				got["dressing|" + tag] = _digest_dict(FlowDungeon.generate_floor(theme, c["floor"], s, null))
				got["graph|" + tag] = _digest_graph(theme, c["floor"], s, PLANS[plan_id])
	if write:
		var f := FileAccess.open(BASELINE, FileAccess.WRITE)
		f.store_string(JSON.stringify(got, "\t", true))
		f.close()
		print("GOLDEN WRITE %d cases -> %s" % [got.size(), BASELINE])
		quit(0)
		return
	var want: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASELINE))
	var bad := 0
	for k in want:
		if not got.has(k):
			bad += 1
			print("GOLDEN MISSING ", k)
			continue
		for field in want[k]:
			if str(got[k].get(field, "<absent>")) != str(want[k][field]):
				bad += 1
				print("GOLDEN DIFF %s :: %s" % [k, field])
	print("GOLDEN %s  cases=%d diffs=%d" % ["PASS" if bad == 0 else "FAIL", want.size(), bad])
	quit(0 if bad == 0 else 1)


func _install_director_stub() -> void:
	_director = get_root().get_node_or_null("HotelDirector")
	if _director == null:
		var s := GDScript.new()
		s.source_code = "extends Node\nvar current_plan: Dictionary = {}\n"
		s.reload()
		_director = s.new()
		_director.name = "HotelDirector"
		get_root().add_child(_director)


## Byte-level digest: sha256 over var_to_bytes, so a single float ULP shows up.
## Objects (e.g. a Resource-valued @data attr after step C) are hashed by content,
## never by instance id, so digests are stable across processes.
static func _h(v: Variant) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes(_canon(v)))
	return ctx.finish().hex_encode().substr(0, 16)


static func _canon(v: Variant) -> Variant:
	if v is Object:
		var props := {}
		for p in (v as Object).get_property_list():
			if int(p["usage"]) & PROPERTY_USAGE_STORAGE and str(p["name"]) != "script":
				props[str(p["name"])] = _canon((v as Object).get(p["name"]))
		return props
	if v is Array:
		var a := []
		for e in v:
			a.append(_canon(e))
		return a
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _canon(v[k])
		return d
	return v


static func _digest_dict(d: Dictionary) -> Dictionary:
	var out := {}
	var keys := d.keys()
	keys.sort()
	for k in keys:
		var v: Variant = d[k]
		out[str(k)] = "%s#%d" % [_h(v), v.size() if v is PackedVector3Array or v is PackedFloat32Array or v is PackedInt32Array or v is PackedStringArray else -1]
	return out


## Graph layer: same inputs FlowDungeon uses today (seed via ctx.eval_id pre-P0,
## via FlowNodeIO.evaluate() once it exists). After step B: call FlowDungeon.evaluate_raw().
static func _digest_graph(theme: Resource, floor_index: int, seed_val: int, plan: Dictionary) -> Dictionary:
	var gp := str(theme.get("graph_path"))
	if gp == "" or not ResourceLoader.exists(gp):
		gp = FlowDungeon.DEFAULT_GRAPH_PATH  # same resolution as flow_dungeon.gd:46-50
	var graph: FlowGraphResource = ResourceLoader.load(gp, "", ResourceLoader.CACHE_MODE_IGNORE)
	var params := {"floor_index": floor_index, "depth_tier": FlowDungeon._depth_tier(floor_index),
		"theme_id": str(theme.get("id")), "is_anomaly": false}
	var gen: Dictionary = plan.get("gen", {})
	for k in gen:
		params["hb_" + str(k)] = gen[k]
	if plan.has("room_programs"):
		params["room_programs"] = plan["room_programs"]
	var outputs: Dictionary
	var io: Script = load("res://addons/flow_nodes_editor/flow_nodes_io.gd")
	var has_evaluate := io.get_script_method_list().any(func(m): return m["name"] == "evaluate")
	if has_evaluate:
		outputs = io.call("evaluate", graph, {}, seed_val, params, null)
	else:
		var ctx := FlowData.EvaluationContext.new()
		ctx.eval_id = seed_val
		ctx.graph = graph
		ctx.runtime_params = params
		outputs = FlowNodeIO.evaluate_graph(graph, {}, ctx, {})
	var out := {}
	var names := outputs.keys()
	names.sort()
	for n in names:
		var d = outputs[n]
		var sn: Array = d.streams.keys()
		sn.sort()
		var parts := []
		for s in sn:
			parts.append([s, int(d.streams[s].data_type), d.streams[s].container])
		var an: Array = d.data_attrs.keys()
		an.sort()
		var attrs := []
		for a in an:
			attrs.append([a, d.data_attrs[a]])
		out[str(n)] = "streams=%s attrs=%s tags=%s kind=%d" % [_h(parts), _h(attrs), _h(d.tags), int(d.kind)]
	return out
```

Notes:

- `vertical_slice` has no `graph_path`, so the graph layer resolves `DEFAULT_GRAPH_PATH` the way
  `flow_dungeon.gd:46-50` does. In the prototype baseline its 16 graph outputs matched grounded
  f0 except `RoomInterior`. That is expected: `theme_id` gates the grounded room plans
  (`jc_room_interior.gd:182`), and it confirms the fixture reaches the nested per-room graph.
- The script only writes `tests/golden/pcg_baseline.json`. It never writes into `addons/` or
  modifies other project resources.

## Appendix B: per-theme `pcg_overrides` (base = grounded values in `hotel_floor.tres`)

Derived from `diff` of the four `resources/pcg/hotel_*.tres`. `door_fraction` is a fan-out
key: `skin/door_fraction`, `carttraps/fake_door_fraction` and `dressing/door_fraction` are
equal in every theme today. Prefix every `node/prop` key with `hotel_floor:` when building the
context.

| Key | grounded (base) | basement | ethereal | mental |
|---|---|---|---|---|
| `layout/torch_probability` | 0.22 | 0.1 | 0.3 | 0.16 |
| `layout/topology` | *(default "hotel")* | "spine" | – | – |
| `layout/corridor_width` | *(default 3)* | 3 | – | – |
| `layout/width_jitter` | *(default 0)* | 1 | – | – |
| `layout/side_spur_chance` | *(default 0.25)* | 0.35 | – | – |
| `layout/spur_width` | *(default 1)* | 1 | – | – |
| `skin/carpet_color` | Color(0.46, 0.08, 0.11, 1) | Color(0.1, 0.12, 0.1, 1) | Color(0.25, 0.35, 0.6, 1) | Color(0.28, 0.05, 0.3, 1) |
| `skin/light_color` | Color(1, 0.9, 0.7, 1) | Color(0.55, 0.65, 0.45, 1) | Color(0.6, 0.75, 1, 1) | Color(1, 0.3, 0.5, 1) |
| `skin/light_energy` | 1.95 | 1.05 | 2.3 | 1.6 |
| `door_fraction` (fan-out) | 28 | 24 | 32 | 38 |
| `dressing/corridor_clutter_chance` | 0.12 | 0.14 | 0.10 | 0.18 |
| `dressing/art_chance` | 0.35 | 0.25 | 0.45 | 0.50 |
| `dressing/vent_chance` | 0.45 | 0.55 | 0.40 | – |
| `dressing/socket_chance` | 0.55 | 0.45 | 0.50 | 0.65 |
| `dressing/hallway_seating_chance` | 0.14 | 0.10 | 0.16 | 0.18 |
| `dressing/hallway_plant_chance` | 0.08 | 0.04 | 0.09 | 0.10 |
| `dressing/hallway_table_chance` | 0.05 | 0.035 | – | 0.06 |

"–" means the value equals the base, so no override is needed. Grounded needs `{}`.
`vertical_slice` needs `{}` and keeps `theme_id = "vertical_slice"`, so as today it does not
use the grounded room plans (`jc_room_interior.gd:182`). Everything else in the four graphs,
including `layout.random_seed = 12345` and all positions, is identical.
