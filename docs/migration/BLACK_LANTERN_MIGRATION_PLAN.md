# Black Lantern Tactics: migration plan to the next PCGODOT (`flow_nodes_editor`) release

Target: `/home/user/black-lantern-tactics` at `be55cb4` (called **BL** below), moving from its vendored
`addons/flow_nodes_editor` (called **vendored**) to the addon release that contains the P0 round described in
[`../PCG_SYSTEM_REVIEW.md`](../PCG_SYSTEM_REVIEW.md) §3 and [`../RUNTIME_API_P0.md`](../RUNTIME_API_P0.md)
(called **upstream**).

State of upstream when this was written (branch `claude/pcg-system-review-4tpca9`):

| P0 piece | Status | Commit |
|---|---|---|
| `$param` bindings (`NodeSettings.bindings`), per-instance overrides (`ctx.overrides`, `"[graph:]node/prop"`) | **landed** | `9417d63` |
| `flow_nodes/node_directories` project setting, category/colour from `meta_node` only, graph format v2 + `FlowGraphMigrations`, `docs/DEPRECATIONS.md` | **landed** | `10ec11b` |
| `FlowNodeIO.evaluate` / `make_context`, `ctx.seed`, `effective_seed()`, `generate()`/`cleanup()`, `Data.scalar/first/container`, tags + data_attrs through `output`, `flow_owner` dict | in flight | — |
| Golden-output harness (`demo/tests/golden`) | in flight | — |

Every step below names the P0 piece it needs. Steps 0–3 can start now. Steps 4–5 wait for the runtime API.

Line references are to BL `be55cb4` unless a path starts with `GF-PCGODOT/`. "Base" means upstream commit
`58a9d3c`. Section 1 shows that this is exactly the commit BL vendored.

**Two BL trees.** The clone analysed here is **older** than the team's live working tree
(`C:/Users/mattk/Documents/tactics`, branch `company`, unpushed commit `0cdd9492`). Citations are against the
clone. Wherever production feedback says the newer tree differs, the text is marked **[newer tree]**. None of
the newer-tree files below exist in the clone. Known differences:

1. Its `flow_nodes_io.gd` already frees node instances (`_free_node_instances`, called at the end of
   evaluation) and restores wired setting ports at runtime (~`:816`, ~`:942`). Table A covers both.
2. Upstream `980dc82` (per-point `resolve_seed` seeding) is being cherry-picked into it, because floor jitter
   repeated identically in every room.
3. Every zoned room style ends with a **dress pass** that calls four reusable kit subgraphs (subgrid, things
   on furniture tops, arrangements, walls, floor): about 130 extra nodes per room, and the same kit subgraph
   runs about 4× per room (§2.4).
4. Graph generators `tools/graph_gen/bake_surfaces.gd` and `tools/graph_gen/gen_room_families.gd`.
5. Graph-level workarounds for node defects that this round fixes upstream (Step 5b).

---

## Summary of findings

1. **Almost none of the vendored addon is a BL patch.** Apart from BL's own nodes, the vendored copy is
   byte-identical to upstream commit **`58a9d3c`** ("fix: correct graph topological sort + guard empty-set
   nodes", 2026-06-10, authored from the BL workstream). The only exceptions are `plugin.gd` (bottom-dock
   sizing, 16 lines), one unused local node (`project_points`) and junk in `bin/`. The topological-sort fix,
   the `distance` empty-B handling and the `attribute_filter_range` empty-input guard all come from that
   upstream commit, and upstream has since changed each of them again. The UI items thought to be BL
   additions (`flow_inspector.gd`, the custom grid, output point-count badges, the inline analyze panel) were
   upstream code at `58a9d3c`, and upstream later removed or rebuilt them. **[newer tree]** adds two more
   local patches to `flow_nodes_io.gd`: instance freeing and wired setting ports. Both are superseded by
   identical or equivalent upstream code and disappear on re-baseline (Table A).
2. **The real risk is upstream semantic drift since `58a9d3c`.** Three changes alter BL style-graph output:
   `select_points` and `attribute_random` per-point seeding (`980dc82`), and the `noise` ValueCubic mapping
   (`5a143f6`). Together they touch **14 of the 16 shipping style graphs**. The master dungeon graph, plus
   `primary_supply` and `objective_objective`, should come through byte-identical. Those three are the hard
   parity gates. **[newer tree]** is adopting the per-point seeding (C1/C2) on purpose via the `980dc82`
   cherry-pick. Once that lands, the only unplanned drift left is the `noise` mapping (C3), plus whatever the
   node fixes in Step 5b change.
3. **Latent ship blocker, not caused by PCGODOT.** `bl_floor_data_to_style_context.gd:15` preloads
   `res://scripts/testing/BlackLanternStyleLabFloorDataBuilder.gd`, and `export_presets.cfg:11` excludes
   `scripts/testing/*`. Every in-game style graph uses that node, so an exported build most likely fails to
   load it. Fix it in Step 1.
4. **Latent bug in the runtime restyle path.** `restyle_unrevealed_room` evaluates graphs without a `room_id`
   runtime param (`BLRoomStyleRuntime.gd:119`). `bl_floor_data_to_style_context` then falls back to room 1
   (`bl_floor_data_to_style_context.gd:52-60`), and the new props are never spawned, because only
   `source == "flow_style"` props get spawned (`DungeonLevelBuilder.gd:5731-5732`) while the interpreter writes
   `"flow_graph"`. Step 3/4 fixes the room id as a side effect. Report it separately.
5. **Style graphs ignore the style seed today.** Every random choice inside a style graph comes from stock
   nodes seeded by their own saved `random_seed`. `style_seed` only reaches the StyleContext resource, and no
   shipping node reads it for randomness. The P0 `seed` argument would make style graphs vary per room for the
   first time. That is a design decision, so it is split out as Step 4b. **[newer tree]** This is the root of
   the "floor jitter repeated identically in every room" report. `980dc82` fixes it per position, and Step 4b
   adds per-floor and per-style variation.
6. **Instancing cost is the next wall, and P0 does not fix it.** **[newer tree]** Measured headless on Godot
   4.7.1: instancing a 20–47-node subgraph costs 6–12 ms per call, and trivial nodes (filter, add_attribute,
   expression over 10–300 points) cost 0.2–0.5 ms each. The dress pass pushed per-stop style time from about
   1.0 s to 1.8–2.1 s. The leak fix frees memory but saves no time. The fix is P1's compiled-graph cache,
   shared across repeated `subgraph` calls and across rooms (Feedback F20). Step 7 gives an interim BL-side
   mitigation.

---

## 1. Vendored-vs-upstream delta

### 1.1 How this was established

```bash
# the two trees differ in 229 shared files (plus 47 upstream-only / 54 BL-only entries)
diff -rq GF-PCGODOT/demo/addons/flow_nodes_editor black-lantern-tactics/addons/flow_nodes_editor \
  | grep -v 'uid\|import\|/bin/\|/doc/'

# find the upstream commit the vendored copy was taken from: minimise the diff over upstream history
for c in $(git -C GF-PCGODOT log --format=%h); do ...diff core files vs $c...; done
#  -> 58a9d3c scores 0 changed lines on flow_nodes_io.gd, flow_data.gd, node.gd, flow_node.gd,
#     node_settings.gd, nodes/{distance,output,filter,sample_points,transform,loop}.gd

# full-tree diff against that commit
git -C GF-PCGODOT archive 58a9d3c demo/addons/flow_nodes_editor | tar -x -C /tmp/base
diff -rq /tmp/base/demo/addons/flow_nodes_editor black-lantern-tactics/addons/flow_nodes_editor \
  | grep -v '\.uid\|\.import\|/bin\|/doc'
#  -> only plugin.gd differs; only nodes/project_points{,_settings}.gd and bl_* are extra
```

`58a9d3c` is an ancestor of upstream HEAD (`git merge-base --is-ancestor 58a9d3c HEAD`). Every difference
between vendored and upstream is therefore either (a) one of the few local items in Table A or (b) an upstream
commit in `58a9d3c..HEAD`. The `.uid` files of every addon script the BL graphs reference are identical on
both sides (`flow_graph_resource.gd` = `uid://j6vjeb5cjjoy`, `graph_input_parameter.gd` = `uid://co0f3ugd2wj1y`,
`nodes/subgraph_settings.gd` = `uid://coavnert1vxj4`). The 23 graph `.tres` files keep loading after a
directory swap.

### 1.2 Table A: what BL actually carries on top of `58a9d3c`

| Item | What it is | Class | Decision |
|---|---|---|---|
| `plugin.gd` (vendored lines 19, 26-32, 39-40, 58-59, 80, 85) | Puts the Data Flow dock in the **bottom panel** (`spawnDock(..., true)`), sets `custom_minimum_size = Vector2(0, 420)` so the panel does not collapse, and defers `EditorInterface.get_selection()` to `_enter_tree` with null guards | (iii) UI | **Drop.** Upstream now ships its own bottom-panel docking through an `EditorDock` wrapper with `default_slot` bottom and `custom_minimum_size = Vector2(460, 300) * editor_scale` (`GF-PCGODOT/.../plugin.gd:9-90`), plus the same selection null-guards (`plugin.gd:31, 270-279`). Check that the panel is usable (acceptance item) |
| **[newer tree]** `flow_nodes_io.gd`: `_free_node_instances` + call at the end of evaluation | Same leak fix as upstream (`GF-PCGODOT/.../flow_nodes_io.gd:746-749, 1353`) | (i) already equal | Nothing to do. The re-baseline brings the same upstream code. **Not a re-baseline delta** for their tree (Risk R1) |
| **[newer tree]** `flow_nodes_io.gd` ~`:816`: in `_build_evaluation_state`, after `refreshFromSettings`, `instance.args_ports_by_name = n_data.get("args_port", {}).duplicate(true)`. ~`:942`: in `_execute_single_node`, `node.inputs` is sized to `max(meta ins, highest connected arg port + 1)` | Makes wires from graph inputs into node **settings** (setting ports) work at runtime, including in nested subgraphs and the time-sliced path | (i) superseded | **Drop on re-baseline** (the directory swap removes it). The upstream equivalent landed in `9417d63`: `_restore_wired_param_ports` (`GF-PCGODOT/.../flow_nodes_io.gd:1060-1072`, called at `:1149`) and the `node.inputs` growth in `_execute_single_node` (`:1273-1284`), which both the sync and the resumable path go through. Wired ports and the new `bindings` **coexist**, with precedence wired port > override > binding > saved value (`RUNTIME_API_P0.md` preamble). The clone's graphs carry no setting wires (every `args_port` key is a data port: `In`, `FloorData`, `Anchors`, …), so only the newer tree's kit subgraphs exercise this. Their golden cases are the check |
| **[newer tree]** cherry-pick of upstream `980dc82` (per-point `resolve_seed` in `transform`, `select_points`, `attribute_random`, `attribute_noise`, `mutate_seed`) | upstream commit | (i) | Makes C1/C2 part of their baseline (Table C). Take it **before** Step 0 so the baseline already contains it. `980dc82` is not self-contained against `58a9d3c`. It also needs, from `5a143f6`: `FlowData.AttrSeed` and `FlowData.point_seed`, `select_points.per_point_seeded_sampling` / `_coerce_weights`, and `FlowNodeBase.require_input` + `FlowData.bcast_idx`. The vendored copy has none of these (`grep` over `addons/flow_nodes_editor/{flow_data,node}.gd`, `nodes/select_points.gd`). If the backport differs from upstream code, C1/C2 will still diff at Step 2, and the attribution run shows where |
| `nodes/project_points.gd`, `project_points_settings.gd` | Local raycast-projection node. Used by **no** graph. Calls `EditorInterface` on its runtime path (`project_points.gd:17`) | local node | **Delete** |
| `bin/~libflow.windows.editor.x86_64.dll`, `bin/*.exp`, `bin/*.lib` | Windows temp-lock copy and MSVC link by-products (400 KB of junk) | junk | **Delete** (replaced by upstream `bin/` wholesale) |
| `bin/flow.gdextension` | Lists only `windows.x86_64.editor` and `macos.debug` | — | Replaced by upstream, which adds `linux.x86_64` (template_debug `.so`) and `windows.x86_64.template_debug/release` |
| 23 `nodes/bl_*.gd` + 23 `*_settings.gd` | BL project nodes (§2.2) | project | **Move** to `res://scripts/pcg_nodes/` (Step 2). Delete the 10 unused ones first (Step 1) |

Note: the brief counted 24 `bl_*` nodes. The tree holds **23** node scripts and 23 settings scripts.

### 1.3 Table B: the "local patches" are upstream `58a9d3c`, since superseded — class (i)

| Behaviour | In vendored (= `58a9d3c`) | Upstream now | Class | BL exposure |
|---|---|---|---|---|
| Topological order | Post-order DFS from finals (`flow_nodes_io.gd:316-344`). Finals are `output` nodes, **every `is_final` node, including every `subgraph`** (`nodes/subgraph.gd:13`), and debug/inspect nodes (`:339-341`) | `build_execution_order` (`GF-PCGODOT/.../flow_nodes_io.gd:712-739`): same post-order DFS, but a subgraph is a root **only if it has no consumers** (`_is_topo_final_root`, `:593-607`, from `b478c5e`). Disabled nodes are never roots. Then `_stabilize_variable_execution_order` and `_stabilize_consumer_input_order` (`9d7a995`) | (i), with an order change | 13 style graphs contain subgraph nodes, so the *visit order* of independent branches can change. Output should not: every `bl_points_to_floor_data_props` (the only node that mutates FloorData) sits on one serial FloorData chain (e.g. `style_room_default`: `src→lk_place→cr_place→interp_barrel→interp_crate→output`), and the only FloorData reader that looks at props, `bl_floor_data_to_points` port 3 (`bl_floor_data_to_points.gd:29, 274`), is wired in **no** graph (checked: f2p ports used = 0, 1, 2, 5). Gate G1/G2 confirms this |
| `distance` with no B | `null` B and empty B both far-fill (every distance 1.0) | `null` B (unwired) is an **error**, `"Input B not connected"`. Connected-but-empty B still far-fills (`a39ba87`, in `DEPRECATIONS.md` §2) | (i) | None expected. All 17 `distance` nodes have port 1 wired (`dwall`, `fl_dlock`, `distW`, `distD`, `t2_dist`, `ln_dw` in 10 graphs + `sg_wall_ring`), and every upstream producer emits an empty `Data`, not `null`, on empty input. Watch the log for `Input B not connected` |
| `attribute_filter_range` | Empty-input guard; a non-parseable String aborts the node | Same guard; `bcast_idx` broadcast; a non-parseable String point goes to **Outside** (`5a143f6`) | (i) | None. The 119 BL filter nodes filter numeric attributes only (`room_id`, `wall_role`, `dist_to_wall`, `dist_to_door`, `is_protected`, `row`/`col`, `openness`, `wall_yaw`) |
| Instance freeing | **None.** `evaluate_graph` never frees the node Controls it creates | `_free_node_instances` after outputs are collected (`flow_nodes_io.gd:746-749, 1353`) | (i) | Clone: memory only (Risk R1). **[newer tree]** already has it: no change |
| Node registry | Script path hard-coded to `res://addons/flow_nodes_editor/nodes/<template>.gd` (`flow_nodes_io.gd:281`) | `FlowNodeRegistry.get_node_script_path` reads `flow_nodes/node_directories` (`10ec11b`) | (i) | Enables Step 2 |

### 1.4 Table C: semantic divergences that change BL output on re-baseline — class (ii)

All are upstream commits in `58a9d3c..HEAD`. The "affected" column comes from parsing every graph
(`graphs/**/*.tres`) for the node templates involved.

| # | Change (commit) | Affected BL graphs / nodes | Chosen semantics | Detection |
|---|---|---|---|---|
| C1 | `select_points`: selection is per point, seeded from `$seed` or else `point_seed(position, random_seed)`, not from the node RNG in index order (`980dc82`, `5a143f6`; `nodes/select_points.gd` `per_point_seeded_sampling`). BL points carry **no** `seed` stream, so the position hash is used | 49 nodes in **14 graphs**: armory_weapons ×2, barracks_quarters ×2, cultist_ritual ×4, medical_station ×2, office_command ×5, storage_warehouse ×3, style_room_advanced ×3, style_room_default ×1, supply_common_room ×3, supply_kitchen ×6, supply_kitchen_island ×8, supply_locker_room ×3, supply_rec_room ×3, workshop_maintenance ×4, plus 1 in `sg_surface_item` (unused). **Not** in primary_supply, objective_objective or the templates | **Adopt upstream.** Order- and count-stable selection is what the style graphs want. **[newer tree]** is already pulling it in (`980dc82` cherry-pick) because floor jitter repeated identically in every room. Designer review re-tunes `ratio`/`random_seed` where a style regresses | Golden `lab/*`, `game/*` diffs. Attribution run (Step 2b). If the cherry-pick is in the Step-0 baseline, C1/C2 cause **no** Step-2 diff |
| C2 | `attribute_random`: per-point seed via `FlowData.resolve_seed` (seed stream → position hash → index), not `random_seed + i*256` (`980dc82`) | `sg_wall_ring` node `w_role` (`random_seed` 771122), which assigns `wall_role`. That decides lockers (≤0.5) vs crates (>0.5) in **every graph that calls `wall_ring`**: armory, barracks, cultist, medical, office, storage, style_room_default, supply_common_room, supply_kitchen, supply_kitchen_island, supply_locker_room, supply_rec_room, workshop. Also `style_room_advanced` node `w_role` | **Adopt upstream** (**[newer tree]**: via the same cherry-pick) | Same |
| C3 | `noise`: `eNoiseType.ValueCubic` (1) now maps to `TYPE_VALUE_CUBIC` (was `TYPE_VALUE`); `SimplexSmooth` to `TYPE_SIMPLEX_SMOOTH` (was `TYPE_SIMPLEX`) (`5a143f6`, `nodes/noise.gd:14-28`) | `office_command.tres` node `nz` (`"noise_type": 1`, line 544), which feeds the `openness` filter | **Keep the old look**: change `office_command.tres:544` to `"noise_type": 0` (`Value` → `TYPE_VALUE` in both versions). The designers tuned the `openness` threshold on the old field | Golden `lab/office_command*` |
| C4 | `build_rotation_from_up`: secondary axis is always `Vector3.UP`; it used to switch to `RIGHT` when the up vector was nearly vertical (`5a143f6`) | 8 nodes (barracks `bd_rot`, cultist `bn_rot`/`to_rot`, medical `ct_rot`, advanced `co_rot`/`ap_rot`, `sg_orient_and_place/rot`, workshop `wsh_rot`). All use `up_vector_attribute: wall_normal`, which is horizontal | Adopt upstream. No output change expected | Golden. A residual diff in rotation-only props points here |
| C5 | `registerStream` honours the declared `data_type`; it used to always infer from the packed container type (`cac340b`, `flow_data.gd` `_inferContainerType`) | Every `registerStream(..., type)` in BL nodes and `BLRoomStyleRuntime.gd`. Spot-checked `bl_floor_data_to_points.gd:78-189`, `bl_floor_data_contract_points.gd:111-820` and `BLRoomStyleRuntime.gd:428-503`: containers match the declared types | Adopt upstream | Golden master digest includes each stream's `data_type` |
| C6 | Evaluation order (Table B row 1) | 13 graphs with subgraphs | Adopt upstream | G1/G2 must be identical |
| C7 | `output` registers the named stream with the main stream's **real** type (`c6b8e7b`); empty input gives an empty output instead of an index error (`95dc886`) | Master graph outputs `PropPoints`, `LightPoints`, `WallCells`, `DoorCells`, `FloorCells`, `RoomBounds` (declared Vector). The game reads only `FloorData` and `ValidationReport` (`DungeonLevelBuilder.gd:680, 685`) | Adopt upstream | Golden `master/*` stream types |
| C8 | Upstream injects `runtime_params["__eval_depth"]` (`GF-PCGODOT/.../flow_nodes_io.gd:1174`) and copies child params **back into the parent ctx** (`_publish_runtime_params`, `:573-580`, `bfa7e28`). P0 adds `runtime_params["seed"]` | `bl_floor_data_to_style_context.gd:68` copies runtime params into `StyleContext.director_params` | Harmless: consumers read named keys only (`BLRoomStyleRuntime.gd:299-301`). **Rule:** never reuse one params Dictionary for two evaluations (BL already builds a fresh one per room at `DungeonLevelBuilder.gd:787`) | Code review |
| C9 | The native lib now ships for Windows export templates and Linux | `ZoneCarver.gd:251`, `RoomSubdivider.gd:1078` pick native L2 kd-tree nearest **or** a Manhattan brute-force fallback, and the two can pick different pairs | See Risk R3. Exported Windows builds switch from the fallback to native, so exported floors change and will match editor floors | Golden `meta.native` flag |

Not affecting BL (checked): `03c2826`/`e6aea74` size→bounds generators (BL uses none), `5a3f9d7` shared
resource mutation (scene/spawner nodes), `c3ab89d` attribute-op coercion (nodes BL does not use), the default
seed `randi()`→`12345` (only for nodes created fresh; saved seeds and name-hash-stabilised missing seeds are
unchanged in both, `_stabilize_missing_seed`, `flow_nodes_io.gd:73-86` base / `:83-96` HEAD), and
`expression` (`expose_arrays` is `false` in all 6 BL expression nodes).

### 1.5 Table D: UI items — class (iii)

| Item (vendored location) | Origin | Upstream today | Decision |
|---|---|---|---|
| `flow_inspector.gd` (custom settings panel, `flow_editor.gd:19, 794`) | upstream at `58a9d3c` | Removed (`050a59c`). Settings go through the Godot inspector + `flow_inspector_property_policy.gd` + `flow_editor_settings_proxy.gd` | Drop |
| `custom_grid.gd` + `custom_grid_shader.gdshader` (`flow_editor.gd:787`) | upstream at `58a9d3c` | Removed (`db68390`), replaced by the native GraphEdit grid with a toggle (`23023d3`) | Drop |
| Output point-count badges (`node.gd:442-443, 477-500`) | upstream at `58a9d3c` | Removed (`63ad631`). Only the exec-time badge remains (`GF-PCGODOT/.../node.gd:401`) | Drop. The Data Inspector (`E`) shows counts. Upstream could restore the badges as an option (Feedback F14) |
| Inline analyze panel (`flow_editor.gd:68-69, 208, 736-738`) | upstream at `58a9d3c` | Rebuilt as `%InlineAnalyzePanel` (`flow_editor.gd:27`) + `flow_editor_chrome.gd:12, 25, 122`, hotkey `A` | Drop (parity) |
| Bottom-dock sizing (`plugin.gd`, Table A) | **BL** | Upstream `EditorDock` bottom slot | Drop |
| "Black Lantern" add-node category (`search_add_node_popup.gd:249`, `flow_editor.gd:604`) and `bl_` hue (`node.gd:212`) | upstream at `58a9d3c` | Deleted in `10ec11b`. Category and colour now come from `meta_node.category` (`GF-PCGODOT/.../node.gd:186-216`) | Re-apply **in BL**: add `"category": "Black Lantern"` to each moved node's `meta_node` (Step 2). Colour falls back to a per-template hash (Feedback F8) |

### 1.6 Everything else in the 229-file diff

These files differ only because upstream kept moving. None needs a BL decision beyond the rows above: type
hints and export descriptions (`c272559`, `7b47f2d`, `a09082c`, `4d98f2d`), `aliases`/`category` meta
(`5a143f6`, `10ec11b`), `require_input` / `bcast_idx` helpers (`5a143f6`), quaternion / bounds / domains
(`fc21f73`, `dcb078a`, `cac340b`), the resumable evaluator (`d270e34`, `begin_evaluation`), variable
fast-paths (`cf01b5a`), editor chrome, i18n and docking (`55694d3`, `951a8e5`, `7ca9fec`, …), and native
wrapper portability (`5aa09b5`; the kd-tree `.cpp` differs only in whitespace).

---

## 2. Current integration map

### 2.1 Call sites and glue

| # | Where | What it does | Addon behaviour it relies on |
|---|---|---|---|
| M1 | `DungeonLevelBuilder.gd:28-29` | `use_pcg_generation = true`; `pcg_master_graph = preload("res://graphs/graph_black_lantern_dungeon.tres")` | — |
| M2 | `DungeonLevelBuilder.gd:430-460` (`build_level`, `:362`) | Flow path. If it returns null, falls back to `_generate_floor_data()` (`:449-450`, direct GDScript pipeline `:629-660`) | — |
| M3 | `DungeonLevelBuilder.gd:662-698` `_generate_flow_node_floor_data` | Throwaway `FlowGraphNode3D` added **to the tree** (`:667-670`). Because `graph == null`, its `_ready()`→`execute()` prints `"FlowGraphNode3D: no graph resource assigned"` (vendored `flow_node.gd:89-96`) once per floor. Hand-built ctx: `eval_id = _rng.seed` (**seed smuggling**), `graph`, `runtime_params = _collect_director_style_params()` (`:672-677`). `FlowNodeIO.evaluate_graph(graph, {}, ctx, ctx.runtime_params)` (`:679`). Reads `ValidationReport` (`:680-683`) and `FloorData` (`:685`), `queue_free` (`:686`), then `_apply_room_style_graphs(fd, int(ctx.eval_id))` (`:696`) | `eval_id` copied unchanged into every node (`flow_nodes_io.gd:350` base). Outputs keyed by output-node `settings.name`. Resource streams carry the FloorData **by reference** |
| M4 | `DungeonLevelBuilder.gd:722-797` `_apply_room_style_graphs` | Registry assignments (`:730`). Per styled room: `ResourceLoader.load(path, "", CACHE_MODE_IGNORE)` (`:761`), `bind_room_filter` (`:768`), `_clear_room_style_domains` (`:771`), another throwaway `FlowGraphNode3D` added to the tree (`:775-778`, prints the same warning), inline FloorData wrap (`:780-782`), ctx `eval_id = style_seed`, `runtime_params = {room_id, style_seed}` (`:784-788`), `evaluate_graph(...)` with the **result discarded** (`:790`). Stamps `style_graph_path` (`:796-797`). `:743-747` loads `BLRoomStyleRuntime` and `FlowData` by path for no reason | Outputs are ignored. The graph **mutates the passed FloorData in place** (`bl_points_to_floor_data_props`). Order of mutation = FloorData link chain |
| M5 | `DungeonLevelBuilder.gd:800-838` `_clear_room_style_domains` | Drops `tactical_decorator` props and room cover before styling | Prop provenance `source`. The interpreter's default `source_tag` is `"flow_graph"` (`bl_points_to_floor_data_props_settings.gd:27`) |
| M6 | `DungeonLevelBuilder.gd:840-870` `_collect_director_style_params` | pressure / band / awakening / scarcity / last card into **master-graph** runtime_params. No graph node reads them (`artifacts/loop1_audit_digest.md:199`), and style graphs never receive them in the game path (`:787`) | — (inert) |
| M7 | `DungeonLevelBuilder.gd:885-899` | `_floor_data_from_flow_data`, `_string_from_flow_data`: hand unwrapping of `findStream(name).container[0]` | Stream record shape `{container, data_type}` |
| M8 | `DungeonLevelBuilder.gd:1000-1015` `_scatter_cover_props` | Skips rooms with `style_graph_path` or `flow_*` props | Provenance strings |
| M9 | `DungeonLevelBuilder.gd:5351-5401` `_maybe_apply_repeat_distortion` | `CACHE_MODE_IGNORE` load (`:5399`), then `restyle_unrevealed_room` | — |
| M10 | `DungeonLevelBuilder.gd:5702-5747` `restyle_unrevealed_room` | `bind_room_filter` **mutates the passed graph** (`:5713`). Builds a snapshot FloorData (`:5715`, `:5749-5764`). Seed `int(_rng.seed) + room_idx*131` (`:5716`, a **third** seed formula). `BLRoomStyleRuntime.evaluate_style_graph_with_context(..., null)` (`:5717`), `apply_style_spec` (`:5718`), copies room keys back (`:5726-5728`), spawns only `source == "flow_style"` props (`:5731-5745`) | As M4. See Summary finding 4 |
| M11 | `GameController.gd:1288-1292, 1299-1320` | `BUILDING_RESTYLE_GRAPHS` (cultist_ritual / storage_warehouse / workshop_maintenance). `CACHE_MODE_IGNORE` load (`:1312`), then `restyle_unrevealed_room(room, graph, {"reason","stage"})` (`:1315-1318`). Triggered by `BuildingDirectorFSM` `KIND_RESTYLE_ROOM` (`BuildingDirectorFSM.gd:69, 292-298, 327-334`) via `GameController.gd:1270-1275` | — |
| M12 | `BLRoomStyleRuntime.gd:15-28` `bind_room_filter` | Rewrites `min_value`/`max_value` of every `attribute_filter_range` with `attribute_name == "room_id"` **in `graph.data`** | That the serialized `settings` dict is re-read on every evaluation (`dict_to_resource`) |
| M13 | `BLRoomStyleRuntime.gd:31-52, 54-88` | `make_context` builds `BLRoomStyleContext`. `build_input_data` wraps 18 named inputs (9 distinct `Data`) | Input feed renames the main stream to the input name (`flow_nodes_io.gd:371-387` base) |
| M14 | `BLRoomStyleRuntime.gd:105-124` `evaluate_style_graph_outputs` | Temp `FlowGraphNode3D` (not in tree), ctx `eval_id = style_seed`, `runtime_params = director_params` (**no `room_id`, no `style_seed`**) | eval_id smuggling |
| M15 | `BLRoomStyleRuntime.gd:126-155, 514-685` | `spec_from_outputs`: fuzzy output routing by `lower_name.contains("proppoints")` (`:519, 527`), `coverpoints` / `lightpoints` / `fogshroudpoints` / `revealpoints` (`:530-538`). Prop kind guessed from the output name (`:673-685`). Per-point readers with hand broadcast (`:627-671`). Cell from `round(position/2.0)` (`:623-625`) | Output names |
| M16 | `BLRoomStyleRuntime.gd:157-261` | `apply_style_spec`, `validate_style_spec` (door/threshold/overlap/path checks) | — |
| M17 | `BLRoomStyleRuntime.gd:263-340` | `decorate_floor_with_style_graphs` + `choose_style_path`. Only caller is the unused `bl_decorator_master` (`bl_decorator_master.gd:29`). **Dead** | — |
| M18 | `RoomStyleAssignment.gd:28-29` | `compute_seed = floor_seed ^ (room_id * 2654435769) ^ style_id.hash()` (64-bit, may be negative) | — |
| M19 | `RoomStyleRegistry.gd:119-151` | `build_assignments`, `style_seed = compute_seed(...)`. `resources/room_styles/registry.tres` has 33 entries over 14 graphs. `objective_objective` and `style_room_advanced` are **not** referenced | — |
| M20 | `BlackLanternStyleLab.gd:15, 551-578` | `preload(flow_node.gd)`. `_run_style_graph`: hand-built ctx, `owner = StyleGraphUnderTest` (a persistent `FlowGraphNode3D` child), `eval_id = seed`, `runtime_params = {room_id: 1, style_seed}` (`:559-564`). `_compute_style_seed` mirrors `compute_seed` for room 1 (`:567-569`) | eval_id smuggling |
| M21 | `BlackLanternStyleLab.gd:283, 360` | `CACHE_MODE_REPLACE` for the active graph. `CACHE_MODE_IGNORE` + `duplicate(true)` for the new-style template (**legitimate**, keep) | — |
| M22 | `BlackLanternStyleLab.gd:413-452`, `addons/bl_style_lab_dock/style_lab_dock.gd:157-198` | Open a graph in the Data Flow dock by **walking the editor tree** for a node with `setResourceToEdit` or `graph_dock` and calling `setResourceToEdit(graph, null)` | Private method name `setResourceToEdit` (vendored `flow_editor.gd:72`, upstream `:476`) and plugin var `graph_dock` |
| M23 | `addons/bl_style_lab_dock/plugin.gd:7-10`, `project.godot:67` | BL editor plugin (right dock). Both plugins enabled | — |
| M24 | `ZoneCarver.gd:251`, `RoomSubdivider.gd:1078`, `bl_style_context_points.gd:89` | `ClassDB.class_exists("GDKdTree")` guards with GDScript fallbacks | Native lib optional |
| M25 | `export_presets.cfg:11` | Excludes `scripts/testing/*`, `scripts/tools/*`, `artifacts/*`, `*.py`, the Style Lab and LoopVisualTest scenes | — |

### 2.2 The 23 `bl_*` nodes

Seed column: how the node derives randomness today. Helpers column: hand wrap/unwrap functions to replace in Step 5.

| Node | Used by | Seed | Helpers (line) | Notes |
|---|---|---|---|---|
| `bl_building_mass` | master | `ctx.eval_id` if `use_context_seed` (true in graph) (`:17-19`) | `_floor_data_resource` `:43` | wraps `BuildingMassGenerator` |
| `bl_zone_carver` | master | `eval_id + 101` (`:21-30`) | `_floor_data_from_input` `:32`, `_floor_data_resource` `:46` | |
| `bl_room_splitter` | master | `eval_id + 211` (`:21-32`) | `:34`, `:48` | |
| `bl_tactical_decorator` | master | `eval_id + 307` (`:21-29`) | `:31`, `:45` | |
| `bl_validate_floor_data` | master | — | `:91`, `:105`, `_string_data` `:112` | emits `ValidationReport` "… status=OK" (`:70-80`) |
| `bl_floor_data_contract_points` | master | — | `:54` | 1,025 lines of point streams |
| `bl_style_lab_source` | `graph_room_points_debug.tres` (editor only) | `settings.random_seed` | — | |
| `bl_floor_data_to_points` | 18 graphs (`f2p`) | — | `:33` | ports 0/1/2/5 used. Port 3 reads props (`:274`) but is never wired |
| `bl_floor_data_to_style_context` | 18 graphs (`src`) | `rt["style_seed"]` > `eval_id` > setting (`:62-67`); `room_id` from `rt[room_id_from_runtime_key]` else setting 1 (`:52-60`) | `:77`, `_resource_data` `:86`, `_int_data` `:94` | **preloads `scripts/testing/…FloorDataBuilder.gd` (`:15`)**, which exports exclude |
| `bl_style_context_points` | 12 graphs (`scp`) | — | — | writes `room_id = style_context.room_id` (`:107, 117`) |
| `bl_points_to_floor_data_props` | 20 graphs, 87 nodes | — | `:339`, `_wrap_floor_data` `:349`, `_get_*_stream` `:369-396`, `_safe_*` `:405-417` | mutates FloorData in place. Cell = `floor(pos/tile)` (`:148-152`) |
| `bl_front_clearance` | advanced, `sg_orient_and_place` | — | — | |
| `bl_fill_corner_points` | advanced, `sg_orient_and_place` | — | — | |
| `bl_decorator_master` | **none** | `eval_id` (`:75`) | `:45`, `:78`, `:85` | uses `ctx.owner` (`:34`) |
| `bl_points_to_style_spec` | **none** | `random_seed + style_seed + room*4099` (`:50-51`) | `:131`, `:193` | |
| `bl_room_style_template` | **none** | `style_seed + random_seed + room*7919` (`:56-57`) | `:248` | |
| `bl_smart_prop_scatter` | **none** | — | `:263` | |
| `bl_style_anchor_points` | **none** | — | `:128` | |
| `bl_style_context_source` | **none** | — | `:70`, `:78`, `:84` | also preloads the excluded builder (`:5`) |
| `bl_style_metadata_spec` | **none** | — | `:95` | |
| `bl_style_spec_merge` | **none** | — | `:105` | |
| `bl_style_spec_to_points` | **none** | — | `:192` | |
| `bl_sync_grid_cell` | **none** | — | `:52` | See Step 8 |

All 23 preload their settings as `res://addons/flow_nodes_editor/nodes/bl_*_settings.gd`, and all settings
scripts carry a `class_name BL…Settings`. Thirteen nodes set `"auto_register": false`, which hides them from
the add-node menus (`search_add_node_popup.gd:64`). Three of them are among the 13 kept, and they are the
three most-used style nodes.

### 2.3 Graphs

- `graphs/graph_black_lantern_dungeon.tres`: 14 nodes, the 6 `bl_*` stages + 8 `output` nodes. No stock
  processing nodes and no stock randomness.
- `graphs/styles/*.tres`: **16 shipping style graphs** (17–77 nodes), each with exactly one
  `attribute_filter_range` named `roomflt` on `room_id`. `templates/style_template_branched.tres` also has
  one, and `style_template_basic.tres` has none.
- `graphs/styles/subgraphs/`: `sg_wall_ring` (used 13×), `sg_orient_and_place` (used 17×), `sg_surface_item`
  (unused). Every subgraph call wires all 3 ports, and `param_overrides` is empty everywhere.
- No node in any graph has `debug_enabled`, `inspect_enabled` or `disabled` set, and no `bl_*` meta sets
  `is_final`.

### 2.4 **[newer tree]** usage the clone does not show (from production feedback)

- **Dress pass.** Every zoned room style ends with calls to four reusable kit subgraphs (subgrid, things on
  furniture tops, arrangements, walls, floor). That is about 130 extra graph nodes per room, about 20 rooms per
  stop, and the same kit subgraph runs about 4× per room. Each call re-instances every node, because
  `subgraph` calls `evaluate_graph` afresh.
- **Measured cost** (headless, Godot 4.7.1): 6–12 ms to instance a 20–47-node subgraph per call, 0.2–0.5 ms
  per trivial node (filter, add_attribute, expression on 10–300 points). Per-stop style-graph time went from
  about 1.0 s to 1.8–2.1 s.
- **Setting wires.** Kit subgraphs wire graph inputs into node settings (setting ports). This relies on the
  local runtime patch in Table A.
- **Graph generators.** `tools/graph_gen/bake_surfaces.gd` bakes furniture top surfaces from meshes (and flips
  `sample_mesh` normals, Step 5b). `tools/graph_gen/gen_room_families.gd` emits room-family graphs and computes
  setting-wire port indices by **instancing the node script** at generation time (`_param_port`). Name-based
  `bindings` replace that (Step 5b). Note that `tools/` is a new top-level folder. Check that
  `export_presets.cfg` excludes it the way it excludes `scripts/tools/*`.
- **Graph-level workarounds** for node defects: listed with their replacements in Step 5b.

---

## 3. Step-by-step migration

The order is a refinement of the brief's (a)…(i): **0 = a, 1 = h, 2 = b, 3 = c, 4 = d, 5 = e, 6 = g,
7 = f, 8 = i, 9 = docs.** The dead-tool cleanup moves to the front because it is risk-free and removes scripts
that already reference symbols upstream has deleted. The game is shippable after each step. Every step ends
with the **standard verification**:

> **V-boot**: run `res://scenes/Main.tscn`. The log shows `═══ DungeonLevelBuilder — Black Lantern (seed: N) ═══`,
> `Flow Node validation: rooms=… status=OK` (`DungeonLevelBuilder.gd:683`, text from
> `bl_validate_floor_data.gd:70-80`) and `Room style graphs: K rooms will be graph-styled`
> (`DungeonLevelBuilder.gd:749`). No `Failed to resolve node script`, `Input B not connected`,
> `Stream name conflict` or script errors appear. Walk from the entry to the objective room (connected floor,
> per `docs/PCG_AUTHORING.md:73`) or run the AI harness: `ai_start_playtest(424242, 120)` (README "AI
> playtest harness").
> **V-golden**: `pcg_golden_capture.tscn -- --compare=…` (Appendix A) against the current baseline, with
> the gates listed in the step.

### Step 0 — Capture the golden baseline on the **current** addon, in the team's working tree (a)

*Needs: nothing from upstream.*

The upstream golden harness evaluates graphs through the new API, and its `demo/tests/golden` path is not in
BL. It cannot capture a "before" picture of the old addon. BL therefore gets its own **parity oracle**, a
scene plus script that call only APIs present in **both** addon versions (`FlowNodeIO.evaluate_graph`,
`FlowData.EvaluationContext`, `Data.streams`) and the game's own entry points. The same file captures before
and after, so a diff means the addon or BL changed, never the harness.

1. Add `res://scripts/tools/pcg_golden/pcg_golden_capture.gd` and `.tscn` (Appendix A). Both are under
   `scripts/tools/`, which `export_presets.cfg:11` already excludes, so nothing ships.
2. Run the capture against the team's **working tree** (`company` at `0cdd9492` or later, with the `980dc82`
   cherry-pick already in), **not** this clone. On the Windows workstation that runs the editor (native lib
   present), run:
   ```bash
   godot --headless --path . res://scripts/tools/pcg_golden/pcg_golden_capture.tscn -- --label=pre_rebaseline
   ```
   The result is written to `res://artifacts/pcg_golden/pre_rebaseline.json`. Run it a second time with
   `--compare=res://artifacts/pcg_golden/pre_rebaseline.json`; it must report 0 diffs, which proves
   determinism. Commit the JSON.
3. The capture contains:
   - `master/<seed>`: the master graph alone, for seeds `424242, 8001, 1, 77, 20260927`. 424242 is the
     acceptance-bar seed in `docs/REPORT_LOOP_8.md`. Digest covers the FloorData plus every output stream
     (name, type, size, value hash).
   - `game/<seed>` and `game/<seed>/again`: `DungeonLevelBuilder._generate_flow_node_floor_data()` on a
     detached builder. This is the real game path, master plus `_apply_room_style_graphs`. The `again` run
     checks that re-evaluating cached graphs does not drift.
   - `lab/<style_id>` for every enabled registry entry, plus `objective_objective` and
     `style_room_advanced`: the Style Lab fixture (`BlackLanternStyleLabFloorDataBuilder.build(type, ticket,
     Vector2i(9,8), "WEST", 8001)`) run the way `BlackLanternStyleLab._run_style_graph` runs it.
   - `restyle/<graph>`: the three `BUILDING_RESTYLE_GRAPHS` through `BLRoomStyleRuntime`, as
     `restyle_unrevealed_room` does, on the seed-424242 floor, for a room id ≠ 1.
   - `meta`: Godot version, OS, `native = ClassDB.class_exists("GDKdTree")`. Only compare captures whose
     `meta.native` matches (Risk R3).
   - `timing`: wall-clock ms per case (`Time.get_ticks_usec()` around each case). **Not gated.** It tracks
     the dress-pass cost (§2.4) across steps, so a re-baseline or workaround removal that makes styling slower
     is noticed.
   - The kit subgraphs need no extra cases. The `game/*` and `lab/*` cases run every registry style, and those
     call the kit subgraphs. **Add one** `kit/<name>` case per kit subgraph that feeds a **non-default** value
     into each wired setting port. If the Step-2 re-baseline silently loses the wire, the output falls back to
     the saved value and that case shows it (Risk R16).
4. Once the upstream golden harness lands, **also** vendor its runner to `res://scripts/tools/pcg_golden/`,
   point its graph list at `res://graphs/**/*.tres`, and give it the same fixtures and params. It becomes the
   long-term regression gate from Step 2 on. BL's oracle is deleted after Step 5 (or kept if the harness
   still lacks a Resource-digest hook, Feedback F10).

Verification: V-boot unchanged (no game code touched).

### Step 1 — Pre-flight cleanup: dead tools, dead nodes, export fix (h)

*Needs: nothing from upstream. Each item is independent.*

1. **Dead tools**: delete them.
   - `scripts/tools/obb_sat_test.gd` loads `res://addons/flow_nodes_editor/gdr_tree_gd.gd` (`:8`), which
     upstream removed (`DEPRECATIONS.md` §1).
   - `scripts/tools/loop_benchmark.gd` uses `FlowData.DataType.Vector3` (`:15`, never existed) and
     `settings.execution_mode` (`:61, :66`, not a `loop_settings` property in either version).
   - `scripts/tools/generate_loop_test_scene.gd` uses the templates `grid_points` (`:34`) and
     `bl_debug_points` (`:51`), which never shipped, and `execution_mode` (`:45`).
   - `scripts/tools/loop_visual_test.gd` (`execution_mode` `:72`) + `scenes/LoopVisualTest.tscn` +
     `scripts/tools/generate_visual_test_scene.gd`. Also remove `scenes/LoopVisualTest.tscn` from
     `export_presets.cfg:11`.
   - `scripts/tools/build_supply_common_room.gd` is an 819-line one-shot generator. Re-running it would
     **overwrite** the hand-tuned `graphs/styles/supply_common_room.tres` with `"random_seed": 0` defaults
     (`:22-23`).
2. **Dead nodes** (0 graph uses in the clone, confirmed by `grep -rl '"<template>"' graphs` = 0; **re-run the
   census on the working tree first**, since its dress-pass graphs are newer): delete
   `bl_decorator_master`, `bl_points_to_style_spec`, `bl_room_style_template`, `bl_smart_prop_scatter`,
   `bl_style_anchor_points`, `bl_style_context_source`, `bl_style_metadata_spec`, `bl_style_spec_merge`,
   `bl_style_spec_to_points`, `bl_sync_grid_cell` (+ settings + `.uid`). Also delete the dead
   `BLRoomStyleRuntime.decorate_floor_with_style_graphs` / `choose_style_path` (`:263-340`, only called from
   `bl_decorator_master.gd:29`). `artifacts/loop1_audit_digest.md:217` already flagged these nodes. If the
   team wants to keep the "pressure-aware" prototypes, park them outside any node directory
   (e.g. `res://scratch/bl_nodes_parked/`), not in the addon.
3. **Local addon node**: delete `addons/flow_nodes_editor/nodes/project_points{,_settings}.gd`.
4. **Export fix (Summary finding 3)**: in `bl_floor_data_to_style_context.gd` replace
   ```gdscript
   const BuilderScript = preload("res://scripts/testing/BlackLanternStyleLabFloorDataBuilder.gd")   # :15
   ...
   floor_data = BuilderScript.build(                                                                  # :38
   ```
   with a lazy, editor-only load:
   ```gdscript
   const LAB_BUILDER_PATH := "res://scripts/testing/BlackLanternStyleLabFloorDataBuilder.gd"
   ...
   if floor_data == null:
       if not Engine.is_editor_hint():
           setError("No FloorData input (the game must feed FloorData)")
           return
       floor_data = load(LAB_BUILDER_PATH).build(
   ```
   Also delete the empty `graphs/black_lantern/{decorators,styles,toolkit}` directories
   (`artifacts/loop1_audit_digest.md:215`).
5. **[newer tree]** Add `tools/*` to the `exclude_filter` in `export_presets.cfg:11` if it is not there yet.
   The graph generators under `tools/graph_gen/` are editor-only.

Verification: V-boot. V-golden must be **identical on every case**: nothing that runs was touched, and the
cold-preview branch never runs in-game because `DungeonLevelBuilder.gd:780-782` always feeds FloorData.
Also run a **Windows export smoke test** before and after this change: export, run, and check that a
styled room has props. Before the change the styled rooms are probably empty; after it, they must have props.

### Step 2 — Re-baseline the addon and move `bl_*` out of it (b)

*Needs: upstream release containing `10ec11b`. Recommended: wait for the tagged release with the whole P0
round (plugin.cfg `version` bump) and re-baseline once. Everything below also works on `10ec11b` alone.*

**2a. One atomic commit.** It has to be atomic: the old addon can only load nodes from its own `nodes/`
directory (vendored `flow_nodes_io.gd:281`).

1. `git mv` the 13 remaining `bl_*.gd` + `_settings.gd` + `.uid` files to `res://scripts/pcg_nodes/`. Keep the
   file names, which are the template names the graphs reference; `FlowNodeRegistry` resolves
   `<dir>/<template>.gd`. Put nothing else in that directory, since the editor scans it for nodes. Shared
   helpers go to `res://scripts/flow/`.
2. Rewrite each settings preload:
   ```bash
   sed -i 's#res://addons/flow_nodes_editor/nodes/bl_#res://scripts/pcg_nodes/bl_#g' scripts/pcg_nodes/bl_*.gd
   ```
3. Add `"category": "Black Lantern",` to each node's `meta_node`. Optionally flip `"auto_register": false`
   → `true` on `bl_floor_data_to_style_context`, `bl_style_context_points` and
   `bl_points_to_floor_data_props` so designers can add them from the menu (editor-only, no runtime effect).
4. **Transitional seed read.** In each of `bl_building_mass.gd:17`, `bl_zone_carver.gd:29`,
   `bl_room_splitter.gd:31`, `bl_tactical_decorator.gd:28` and `bl_floor_data_to_style_context.gd:66-67`,
   replace the `ctx.eval_id` read with a helper that works for both the hand-built contexts (still used until
   Step 4) and the P0 `seed`:
   ```gdscript
   # res://scripts/flow/BLFlowSeed.gd
   class_name BLFlowSeed
   ## Graph seed: P0 ctx.seed when present and non-zero, else the legacy eval_id convention, else 0.
   static func graph_seed(ctx) -> int:
       if ctx == null:
           return 0
       if "seed" in ctx and int(ctx.get("seed")) != 0:
           return int(ctx.get("seed"))
       return int(ctx.eval_id)            # removed in Step 4
   ```
   `bl_zone_carver._stage_seed` becomes
   `var base := BLFlowSeed.graph_seed(ctx); return (base if base != 0 else settings.random_seed) + offset`.
   The others follow the same pattern. Do **not** use `effective_seed()` here (Step 4 explains why).
5. Replace `addons/flow_nodes_editor/` wholesale with the upstream `demo/addons/flow_nodes_editor/`,
   including `bin/`. **[newer tree]** This drops the local `flow_nodes_io.gd` patches (instance freeing;
   `args_ports_by_name` restore ~`:816`; `node.inputs` sizing ~`:942`). Do **not** re-apply them: upstream
   `_restore_wired_param_ports` + input growth (`9417d63`) cover the same cases, including nested and
   time-sliced evaluation. The stray `~libflow…dll`, `.exp` and `.lib` files, `flow_inspector.gd` and
   `custom_grid*` go away (Tables A and D).
6. Set **Project Settings → Flow Nodes → Node Directories** = `["res://scripts/pcg_nodes"]`. Per BL's
   `CLAUDE.md` ("Never edit project.godot directly"), set it in the editor or with MCP `set_project_setting`,
   not by hand.
7. The addon README says the plugin registers the setting's default when it is enabled. Open the editor once
   so the `.uid`/`.import` churn happens in this commit, not later.

**2b. Compare.** Run V-golden against `pre_rebaseline.json`. Gates:

- **G1**: every `master/*` case is **identical**. Only `bl_*` nodes and `output` run there. The oracle hands
  the seed over through both `eval_id` and, once the field exists, `ctx.seed`, and `BLFlowSeed` reads the
  same value either way. If G1 fails, stop and bisect with the attribution patch below; start with C5/C7.
- **G2**: `lab/primary_supply` and `lab/objective_objective.tres` are **identical**. They use only
  `attribute_filter_range`, `add_attribute`, `distance`, `sequence_sample` and `bl_*`. **[newer tree]** If
  the `980dc82` backport is in the baseline and matches upstream, and the C3 edit (2c.1) goes into the 2a
  commit, then **every** case except the `kit/*` wire checks should be identical. That is the strongest
  gate available.
- **G3**: every other difference is explained by C1–C3. Prove it with an **attribution run**: in a scratch
  working copy (never committed), revert only the three upstream behaviours:
  - `nodes/select_points.gd`: skip the seed-stream / position-synth block (force
    `has_point_seeds = false`), so it falls back to `uniform_sampling`/`weighted_sampling` with `rng`.
  - `nodes/attribute_random.gd`: `rng.seed = seed_val + i * 256` instead of `FlowData.resolve_seed(...)`
    (both branches).
  - `nodes/noise.gd:17, 25`: `TYPE_VALUE_CUBIC → TYPE_VALUE`, `TYPE_SIMPLEX_SMOOTH → TYPE_SIMPLEX`.

  If the `980dc82` cherry-pick is already in the Step-0 baseline (recommended), revert **only** the `noise`
  mapping. C1/C2 are then not diffs at all. If the baseline predates it, also revert `980dc82`'s changes to
  `transform`, `attribute_noise` and `mutate_seed` when the newer graphs use those nodes.

  Capture with `--label=attribution` and compare to `pre_rebaseline`. The result must be **0 diffs**. Any
  residual diff is an unclassified divergence (C4–C9 or new): investigate before continuing. Then discard the
  scratch patch.

**2c. Resolve the (ii) divergences.**

1. C3: set `graphs/styles/office_command.tres:544` `"noise_type": 1` → `0`.
2. C1/C2: designer review. **[newer tree]** If the `980dc82` cherry-pick went in before Step 0, this review
   happens with the cherry-pick and is not repeated here. Otherwise use the `docs/STYLE_LAB_AUDIT.md` method (Style Lab, seed 8001, 9×8 room,
   top-down screenshot per style). Compare against `artifacts/stylelab/final_*` and the verdict table in
   `STYLE_LAB_AUDIT.md`. For each style that regresses, change the `random_seed` of the offending
   `select_points` node, or of `sg_wall_ring/w_role`, which affects 13 graphs, so tune it once. Selection is
   now position-hashed, so a seed is a free tuning knob. Graph structure should not need changes.
3. Capture `--label=post_rebaseline`, review the diff summary, commit the JSON. **This is the new baseline.**

**2d. Graph format v2.** In a **separate** commit, bump all 23 graphs from `"version": 1` to `2`
(`sed -i 's/^"version": 1$/"version": 2/' graphs/*.tres graphs/styles/*.tres graphs/styles/*/*.tres`).
`FlowGraphMigrations.MIGRATIONS[2]` is empty, so nothing else changes, and future dock saves stop producing
version-only diffs mixed into real edits. The old addon ignores `version` (base `flow_nodes_io.gd:134` only
writes it), so a rollback stays possible.

**2e. UI.** Nothing to re-apply (Table D). Check in the editor: the Data Flow dock opens in the bottom panel
and does not collapse, `A` opens the analyze panel, the grid toggle works, and `bl_*` nodes appear under
"Black Lantern" in the add-node menu.

Verification: V-boot. The `FlowGraphNode3D: no graph resource assigned` warning is still expected here; it
goes away in Step 4. V-golden gates G1–G3. Orphan check (Risk R1).

### Step 3 — Replace `bind_room_filter` + `CACHE_MODE_IGNORE` with a `$room_id` binding (c)

*Needs: `9417d63` (landed).*

**Recommendation: use the binding, not an override.**

- A binding lives in the graph (`NodeSettings.bindings`). It is self-documenting, resolves from
  `runtime_params`, which all four callers already pass or can pass, and falls back to the saved value (1)
  in the editor and the Style Lab.
- An override would make every caller know the node name `roomflt` (true today in all 16 graphs, but only by
  convention). P0's `FlowNodeIO.evaluate` has no `overrides` argument, so callers would also have to build a
  ctx by hand (Feedback F5).

**Graph edit** (`graphs/styles/style_room_default.tres`, node `roomflt`, settings at line ~283; keys stay
alphabetical as Godot writes them):

```diff
 "name": &"roomflt",
 "position": Vector2(630, -200),
 "settings": {
 "attribute_name": "room_id",
+"bindings": {
+"max_value": "room_id",
+"min_value": "room_id"
+},
 "inclusive_max": true,
 "inclusive_min": true,
 "max_value": 1.0,
 "min_value": 1.0,
 "title": "This room only"
 },
```

The saved `1.0` stays. It is what the editor and the Style Lab preview (fixture room 1). At runtime the
binding resolves `input_data_map["room_id"]`, then `runtime_params["room_id"]`, then `variables["room_id"]`,
and coerces int→float (`flow_nodes_io.gd` `apply_setting_bindings`).

**Apply to all 16 style graphs + the branched template.** Use a text edit, not `ResourceSaver`, which would
reformat the files. Save as `artifacts/stylelab/bind_room_filters.py` next to `validate_graphs.py`
(`*.py` and `artifacts/*` are export-excluded). The script is idempotent and asserts the invariant that
`bind_room_filter` relied on:

```python
#!/usr/bin/env python3
"""Add a $room_id binding to the single room_id attribute_filter_range of each style graph."""
import pathlib, sys
root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
KEY = '"attribute_name": "room_id",\n'
BIND = KEY + '"bindings": {\n"max_value": "room_id",\n"min_value": "room_id"\n},\n'
paths = sorted(root.glob("graphs/styles/*.tres")) + sorted(root.glob("graphs/styles/templates/*.tres"))
changed = 0
for p in paths:
    text = p.read_text(encoding="utf-8")
    count = text.count(KEY)
    if count == 0:
        continue                                   # style_template_basic: no room filter
    assert count == 1, f"{p}: expected exactly one room_id filter, found {count}"
    start = text.index(KEY)
    tmpl = text.index('"template":', start)
    assert text[tmpl:text.index("\n", tmpl)].rstrip().endswith('"attribute_filter_range"'), p
    if '"bindings"' in text[start:tmpl]:
        continue                                   # already bound
    p.write_text(text.replace(KEY, BIND, 1), encoding="utf-8", newline="\n")
    changed += 1
    print("bound", p)
print(f"{changed} graph(s) updated")
```

Expected output: 17 files (the 16 listed in §2.3 + `templates/style_template_branched.tres`). Then run
`python artifacts/stylelab/validate_graphs.py <files>`. Fix its hard-coded `STYLES` Windows path (`:3`)
first, or pass paths.

**Code changes (same commit):**

| File:line | Before | After |
|---|---|---|
| `DungeonLevelBuilder.gd:759-768` | `var graph = ResourceLoader.load(a.graph_path, "", ResourceLoader.CACHE_MODE_IGNORE)` … `BLRoomStyleRuntime.bind_room_filter(graph, a.room_id)` | `var graph := load(a.graph_path) as FlowGraphResource`. The binding reads `room_id` from the params already passed at `:787` |
| `DungeonLevelBuilder.gd:5394-5399` | `CACHE_MODE_IGNORE` load + comment "bind_room_filter mutates" | `load(graph_path) as FlowGraphResource` |
| `DungeonLevelBuilder.gd:5710-5713` | comment + `bind_room_filter(style_graph, room_idx)` | delete. Also delete the "callers should load an uncached copy" note |
| `GameController.gd:1311-1312` | `ResourceLoader.load(graph_path, "", ResourceLoader.CACHE_MODE_IGNORE)` | `load(graph_path)` |
| `BLRoomStyleRuntime.gd:9-28` | `bind_room_filter` | delete |
| `BLRoomStyleRuntime.gd:119-121` | `ctx.runtime_params = context.director_params.duplicate(true)` | also set `ctx.runtime_params["room_id"] = context.room_id` and `["style_seed"] = context.style_seed` (Step 4 moves this into `params`). **Fixes Summary finding 4a:** the restyle path now builds the StyleContext for the right room |
| `graphs/styles/ROOM_STYLE_AUTHORING_SPEC.md:34, 166-169` | "room_id=1" guidance; verification snippet uses `CACHE_MODE_IGNORE` | document the `$room_id` binding. Plain `load()` is fine now |

`BlackLanternStyleLab.gd:360` keeps `CACHE_MODE_IGNORE`: it duplicates a template into a new file, which is
not a binding workaround.

Verification: V-boot. V-golden against `post_rebaseline`: `game/*`, `lab/*` and `master/*` are **identical**.
`game/<seed>/again` identical to `game/<seed>` shows cached graphs are no longer mutated. `restyle/*`
**changes** (room-id fix, expected; review that props now land in the target room, then re-capture
`post_bindings`). Check that `grep -rn "CACHE_MODE_IGNORE\|bind_room_filter" scripts` finds only
`BlackLanternStyleLab.gd:360`. In-game, trigger a building restyle (GameController `restyle_room`) and check
the log line `Building restyled unrevealed room N -> …` (`GameController.gd:1320`).

Separate follow-up ticket for Summary finding 4b (restyled props are never spawned): the spawn loop at
`DungeonLevelBuilder.gd:5731-5732` accepts only `flow_style`, but graph props carry `flow_graph`, and the
snapshot keeps the original room's props, which occupy cells. Out of scope for the migration. Keep it in its
own commit so golden diffs stay attributable.

### Step 4 — `FlowNodeIO.evaluate` instead of hand-built contexts; seed moves out of `eval_id` (d)

*Needs: P0 §2–§3 (`FlowNodeIO.evaluate`, `make_context`, `ctx.seed`, owner-less evaluation). In flight.*

P0 API used, quoted from `RUNTIME_API_P0.md` §3:
`static func evaluate(graph : FlowGraphResource, inputs : Dictionary = {}, seed : int = 0, params : Dictionary = {}, owner : Node3D = null) -> Dictionary`.
"`evaluate_graph` must work with `parent_ctx.owner == null`". "`eval_id` : evaluation counter again; never a
seed". "`runtime_params` … always contains `"seed"` mirrored from `ctx.seed`".

**4a. Parity migration (no output change).**

`DungeonLevelBuilder.gd:662-698`, after:

```gdscript
func _generate_flow_node_floor_data() -> FloorData:
	if pcg_master_graph == null:
		push_warning("No Flow Node dungeon graph assigned.")
		return null
	var floor_seed := int(_rng.seed)
	var outputs := FlowNodeIO.evaluate(pcg_master_graph, {}, floor_seed, _collect_director_style_params())
	var validation_report := _string_from_flow_data(outputs.get("ValidationReport"), "ValidationReport")
	if validation_report != "":
		print("  Flow Node validation: %s" % validation_report)
	var floor_data := _floor_data_from_flow_data(outputs.get("FloorData"))
	if floor_data != null:
		_apply_room_style_graphs(floor_data, floor_seed)
	return floor_data
```

This deletes the throwaway root (`:667-670, :686`), the hand-built ctx (`:672-677`) and the
`load("…flow_data.gd")` indirection. It also removes one `no graph resource assigned` warning per floor.

`DungeonLevelBuilder.gd:774-791` inside `_apply_room_style_graphs`, after:

```gdscript
		FlowNodeIO.evaluate(graph, {"FloorData": _floor_data_input(floor_data)}, 0,
				{"room_id": a.room_id, "style_seed": a.style_seed})
```

`seed = 0` **on purpose**: see 4b. Delete `:743-747` and `:774-791`'s temp root. `_floor_data_input` is the
existing inline wrap (`:780-782`) until Step 5 replaces it with `FlowData.Data.scalar`.

`BLRoomStyleRuntime.gd:105-124`, after:

```gdscript
static func evaluate_style_graph_outputs(style_graph: FlowGraphResource, context, owner = null) -> Dictionary:
	if style_graph == null:
		return {}
	var params: Dictionary = context.director_params.duplicate(true)
	params["room_id"] = context.room_id
	params["style_seed"] = context.style_seed
	return FlowNodeIO.evaluate(style_graph, build_input_data(context), 0, params, owner)
```

Delete `const FlowGraphNode3DScript` (`:5`).

`BlackLanternStyleLab.gd:551-578`, after:

```gdscript
func _run_style_graph(floor_data: FloorData, graph: FlowGraphResource) -> void:
	if floor_data == null or graph == null:
		return
	var fd_data := FlowData.Data.new()
	var values: Array[Resource] = [floor_data]
	fd_data.registerStream("FloorData", values, FlowData.DataType.Resource)
	var seed_val := _compute_style_seed()
	FlowNodeIO.evaluate(graph, {"FloorData": fd_data}, 0, {"room_id": 1, "style_seed": seed_val})
```

Delete `_style_graph_node` (`:572-578`), `FlowGraphNode3DScript` (`:15`) and the `StyleGraphUnderTest`
child from `scenes/BlackLanternStyleLab.tscn` if it was saved there.

`bl_*` seed reads: in `BLFlowSeed.graph_seed` (Step 2a.4) drop the `eval_id` fallback, so the helper returns
`ctx.seed`. Afterwards `grep -rn "eval_id" scripts/ --exclude-dir=pcg_golden` must be empty. The oracle
keeps setting `eval_id` on purpose, so it still runs against older baselines.

**Why the master nodes read the raw `ctx.seed` and not `effective_seed()`.** P0 defines
`effective_seed = hash([ctx.seed, settings.random_seed]) & 0x7fffffff` when `ctx.seed != 0`. If
`bl_building_mass` / `bl_zone_carver` / `bl_room_splitter` / `bl_tactical_decorator` switched to it, **every
floor for every `level_seed` would change**. That breaks reproduction of the recorded acceptance and AI runs
(`artifacts/ai_playtests/black_lantern_seed_424242/`, `docs/REPORT_LOOP_8.md`). It buys nothing, because
these stages already decorrelate with fixed offsets (+101 / +211 / +307). `effective_seed()` is the right
call for any **new** BL node that wants a per-node stream, and for the parked nodes if they come back.

Verification: V-boot, plus the log no longer shows `FlowGraphNode3D: no graph resource assigned`.
V-golden: **every case identical** to the Step-3 baseline (`master/*` because `ctx.seed == eval_id` value;
style cases because `seed = 0` and `style_seed` still travels in params). Check that
`grep -rn "FlowGraphNode3D\|EvaluationContext.new" scripts/ --exclude-dir=pcg_golden` is empty.

**4b. Opt-in: give style graphs a real seed (design decision, separate PR).**

**[newer tree]** The team reports that floor jitter repeated identically in every room. That is why they are
pulling `980dc82`: its per-point seeding (seed stream → position hash → index) is the semantics they want.
Position hashing alone gives per-*position* variety, so rooms of identical shape at different places already
differ. 4b adds per-*floor* and per-*style* variety on top: the same room geometry styles differently on a
different floor seed.

Today a style graph's layout depends only on room geometry. Stock randomness is keyed on each node's saved
`random_seed` and, after Step 2, on point positions. The `style_seed` that `RoomStyleAssignment.compute_seed`
produces reaches only `StyleContext.style_seed`, and no shipping node uses it for randomness. Passing it as
the P0 graph seed:

```gdscript
FlowNodeIO.evaluate(graph, inputs, a.style_seed, {"room_id": a.room_id, "style_seed": a.style_seed})
```

gives every stock node `effective_seed = hash([style_seed, random_seed]) & 0x7fffffff`, and
`select_points`/`attribute_random` feed that into `point_seed(pos, …)`. Layouts then vary per floor seed, room
and style, and stay deterministic. Things to settle first:

- `compute_seed` is a 64-bit XOR and can be negative. That is fine for `hash()`. A result of exactly `0`
  silently means "legacy". Accept that, or map `0 → 1` in `compute_seed`.
- **Unify the three derivations** before turning this on: game `compute_seed(floor_seed, room, style_id)`
  (`RoomStyleRegistry.gd:151`), restyle `int(_rng.seed) + room_idx * 131` (`DungeonLevelBuilder.gd:5716`),
  and Style Lab `compute_seed(generation_seed, 1, style_id)` (`BlackLanternStyleLab.gd:567-569`). Recommended:
  the restyle path uses `RoomStyleAssignment.compute_seed(int(_rng.seed), room_idx, graph_path.get_file().get_basename())`.
- Rerun the designer review (Step 2c.2) at 3+ seeds per style. Re-capture goldens. The Style Lab "Next Seed"
  button starts showing real variation.

### Step 5 — Replace wrap/unwrap helpers with `Data.scalar` / `Data.first` / `Data.container` (e)

*Needs: P0 §6. In flight.*

P0 API used: `static func scalar(name : String, value, data_type : DataType = DataType.Invalid) -> Data`,
`func first(name : String, default = null)`, `func container(name : String)` (`RUNTIME_API_P0.md` §6).
The review's "~10 copies" counts only game-side glue. Counting the moved nodes, **24 sites** survive Step 1
(38 including the helpers of the 10 nodes Step 1 deletes):

| Site | Replacement |
|---|---|
| `DungeonLevelBuilder.gd:885-891` `_floor_data_from_flow_data` | `d.first("FloorData") as FloorData if d else null` (inline, delete the function) |
| `DungeonLevelBuilder.gd:893-899` `_string_from_flow_data` | `str(d.first(name, "")) if d else ""` |
| `DungeonLevelBuilder.gd:780-782`, `BlackLanternStyleLab.gd:555-557` inline wraps | `FlowData.Data.scalar("FloorData", floor_data)` |
| `BLRoomStyleRuntime.gd:396-402` `_resource_data` | `FlowData.Data.scalar(name, res, FlowData.DataType.Resource)`. **Careful:** today a `null` resource gives an **empty** stream. Keep that with `if res == null: return FlowData.Data.new()` or check what `scalar(name, null, Resource)` does |
| `BLRoomStyleRuntime.gd:404-408` `_int_data` | `FlowData.Data.scalar(name, value, FlowData.DataType.Int)` |
| `BLRoomStyleRuntime.gd:133-138` (in `spec_from_outputs`) | `var value = data.first(output_name, data.first("StyleSpec"))` |
| `scripts/pcg_nodes/*`: `_floor_data_from_input` ×8 (`bl_floor_data_contract_points:54`, `bl_floor_data_to_points:33`, `bl_floor_data_to_style_context:77`, `bl_points_to_floor_data_props:339`, `bl_room_splitter:34`, `bl_tactical_decorator:31`, `bl_validate_floor_data:91`, `bl_zone_carver:32`) | one static in `res://scripts/flow/BLFlowIO.gd`: `static func floor_data_in(node: FlowNodeBase, port := 0) -> FloorData` → `var d = node.get_input(port); return d.first("FloorData") as FloorData if d else null` (the caller keeps its own `setError`) |
| `_floor_data_resource` ×5 (`bl_building_mass:43`, `bl_room_splitter:48`, `bl_tactical_decorator:45`, `bl_validate_floor_data:105`, `bl_zone_carver:46`), `_wrap_floor_data` (`bl_points_to_floor_data_props:349`) | `FlowData.Data.scalar("FloorData", floor_data)` |
| `_resource_data`/`_int_data` in `bl_floor_data_to_style_context:86-97` | `scalar(...)` |
| `_string_data` in `bl_validate_floor_data:112` | `FlowData.Data.scalar(name, value)` |
| Per-point readers `BLRoomStyleRuntime.gd:627-671`, `bl_points_to_floor_data_props.gd:369-422` | **Not covered by P0** (per-index with broadcast). Keep, but use `data.container(name)` + `FlowData.bcast_idx(size, i)` in place of the `index if size > 1 else 0` copies (Feedback F12) |

Do not put `BLFlowIO.gd` in `scripts/pcg_nodes/`: the editor scans that directory for nodes.

Verification: V-boot. V-golden identical (pure refactor).

### Step 5b — Delete node-defect workarounds as the upstream fixes land

*Needs: the node fixes being implemented this round on the review branch (see `PCG_SYSTEM_REVIEW.md` §2.11).
Each row can go in its own patch release and BL commit.*

Procedure per row:

1. Re-vendor the addon release that contains the fix.
2. V-golden **with the workaround still in place**. For pure bug fixes the result should be identical. Any
   diff is a semantic change the fix introduced; it must be listed in `DEPRECATIONS.md` §2 (Feedback F22).
3. Delete the workaround in a **separate** commit.
4. V-golden again. "Identical" is expected for pure replacements. Designer review where the table says output
   changes.

Most workarounds live only in the **[newer tree]**. The clone uses none of `load_pcg_data_asset`,
`sample_mesh`, `merge`, `match_and_set`, `copy` or `sample_points` (template census over `graphs/**/*.tres`).

| Defect (fixed upstream this round) | BL workaround to delete | Where | After the fix | Output effect |
|---|---|---|---|---|
| `load_pcg_data_asset`: Vector3 parse attempted on every value of every column, no cache, `asset_path` read straight from settings (not wireable or bindable). 15–18 ms per load of a 333×16 JSON | Whatever per-call loads and hard-coded `asset_path` copies the kit graphs use | **[newer tree]** only (not in clone) | Bind `asset_path` with `"bindings": {"asset_path": "<param>"}` instead of duplicating nodes or graphs per asset. Rely on the cache | None expected. `timing` should drop |
| `sample_mesh` area-weighted normals `(b-a)×(c-a)` point into the mesh with Godot's clockwise front faces (a table underside faces up) | Normal flip in `tools/graph_gen/bake_surfaces.gd` | **[newer tree]** only | Delete the flip. Re-run the bake. The baked surface data must be byte-identical to the previous bake | None if the upstream fix flips exactly the same way. Diff the baked files |
| `merge` registers a bulk's new streams after appending its other streams → stream-length warning on every merge of differing column sets | `remove_attribute` nodes that trim columns before each `merge` | **[newer tree]** only | Delete the trimming nodes unless the trimmed columns must stay absent downstream | Extra columns survive the merge. Harmless unless a later node keys on column presence. Warning spam gone |
| `match_and_set` uses the node-global RNG when no `seed` stream exists, so every room picks the same variants | A node writing `seed = hash(position)` before each pick | **[newer tree]** only | **Optional delete.** With a `seed` stream present the fixed node uses it (seed stream first), so keeping the workaround preserves output exactly. Deleting it switches to the upstream position hash, whose values differ from `hash(position)` → picks change | Only if deleted: variant picks change. Designer review |
| `match_and_set` compares keys as strings: JSON `3.0` never matches key `3` | Key normalisation before the match (expression / string cast) | **[newer tree]** only | Delete the normalisation | None expected |
| `copy` in SourceToTargets mode emits only source streams (target attributes dropped) | `copy` LinearCopies ×N + key `expression` + `match_and_set` to re-attach target attributes | **[newer tree]** only | Replace the chain with one `copy` SourceToTargets using the new attribute-inheritance option | Must be identical. If not, check stream order and inherited-name collisions |
| `sample_points` emits only the common streams and drops the parent point's attributes | Two LinearCopies + expressions that re-attach parent attributes | **[newer tree]** only | Replace with plain `sample_points` | Must be identical (golden) |
| `expression` retypes an existing stream when the result type differs | Writing to a fresh stream name (and renaming) instead of in place | **[newer tree]** only | Write in place again | None expected |
| `point_offsets` writes `parent_index` / `offset_index` (and **[newer tree]** `offset_label`) columns by default | **Clone:** all **57** `point_offsets` nodes in 14 graphs blank the columns with `"parent_index_attribute": ""` and `"offset_index_attribute": ""` (armory 3, barracks 2, cultist 3, medical 3, office 5, storage 2, advanced 3, common_room 5, kitchen 10, kitchen_island 6, locker_room 3, rec_room 6, workshop 5, `sg_surface_item` 1; e.g. `supply_kitchen_island.tres:749-751`, `sg_surface_item.tres:196-198`). In the clone's addon, `offset_label` is only written when `labels` is non-empty (`GF-PCGODOT/.../nodes/point_offsets.gd:71-110`) | If the fix makes the columns opt-in, the explicit blanks become redundant but stay correct, because saved values win over defaults. Leave them to avoid churn, or strip them in the same commit as the Step-2d version bump | None |
| Setting-wire ports are positional, so generators must know port indices | `gen_room_families.gd` `_param_port` instances each node script at generation time to compute the setting-wire port index | **[newer tree]** only | Generate name-based bindings instead: write `"bindings": {"<property>": "<param>"}` into the node's settings dict and declare the param in the graph's `in_params` (or pass it in `runtime_params`). Delete `_param_port`. This also stops the generator instancing `@tool` node scripts, which caused an editor hang in GodotJC (`PCG_SYSTEM_REVIEW.md` §2.1). Keep a wire only when the value really is a per-point stream: bindings read `Data.first` (element 0) | None: a binding resolves the same value the wire carried. Golden on the generated graphs |
| `add_attribute` with no input yields a one-point Data | If the kit graphs use it as a schema row, nothing to delete. Ask upstream to document it (Feedback F23) | **[newer tree]** only | — | — |

### Step 6 — Style Lab and dock: public API instead of duck typing (g)

*Needs: upstream `plugin.gd` `_handles`/`_edit`, which came in with `1906c2b` (part of `58a9d3c..HEAD`, so
the Step-2 re-baseline brings it).*

What exists today: upstream's plugin handles `FlowGraphResource` (`GF-PCGODOT/.../plugin.gd:281-288`
`_handles`/`_edit` → `_open_flow_graph_resource_from_filesystem`). Opening a graph is therefore Godot's
public API:

```gdscript
# BlackLanternStyleLab.gd:413-452 → replaces open_graph_in_data_flow body + deletes _find_flow_plugin
func open_graph_in_data_flow() -> void:
	if _active_graph == null:
		_load_active_style_graph()
	if _active_graph == null or not Engine.is_editor_hint():
		return
	EditorInterface.edit_resource(_active_graph)
```

Do the same in `addons/bl_style_lab_dock/style_lab_dock.gd:176-178` (`EditorInterface.edit_resource(graph)`)
and delete `_find_flow_dock` (`:181-198`).

What the lab still needs that no public API provides (gaps → Feedback F1–F3):

1. Open a graph **with fixture inputs and params** (FloorData fixture, `room_id = 1`, `style_seed`, seed), so
   the dock preview matches the lab instead of `bl_floor_data_to_style_context`'s cold-preview fixture
   (`:32-45`).
2. A signal when the dock **saves** or edits a graph, so the lab can rebuild automatically. The dock saves
   through `ResourceSaver.save` (`GF-PCGODOT/.../flow_editor.gd:1133`), so `EditorPlugin.resource_saved`
   does not fire. **Stopgap:** in the existing 1.5 s poll timer (`style_lab_dock.gd:46-50`), compare
   `FileAccess.get_modified_time(_active_graph.resource_path)` and call `reload_and_rebuild()` when it
   changes.
3. A way to run the graph from the dock with a chosen seed ("Run with…", review §3 P2).

Verification: in the editor, open `scenes/BlackLanternStyleLab.tscn`. "Open in Data Flow" opens the right
graph. Rebuild works for every registry style. Next Seed changes nothing until Step 4b, which is expected.
New Style creates, registers and opens a graph.

### Step 7 — FloorData-as-stream stays; what P1 would change (f)

**Keep** passing the `FloorData` Resource as a one-element `Resource` stream. It is typed (`DataType.Resource`
= 5, stable across versions), passes by reference at no cost, matches what every `bl_*` node expects, and P0
`Data.scalar/first` makes it one line at each end.

Be explicit about what it costs, because P1 will make these visible:

- The graph's real output is a **side effect**: in-game, the outputs Dictionary is discarded
  (`DungeonLevelBuilder.gd:790`). A P1 per-element output cache keyed on settings + input hash would treat
  `bl_points_to_floor_data_props` as cacheable and skip the mutation. BL needs a way to mark mutating nodes
  non-cacheable (Feedback F11).
- Correctness depends on the FloorData **link chain** serialising every writer. Keep that rule in
  `ROOM_STYLE_AUTHORING_SPEC.md` ("Chain FloorData through interps", `:161-163`). Never let two writers run
  in parallel branches.

What the P1 **group-by loop** would enable. Today's per-room loop is GDScript (`_apply_room_style_graphs`,
`DungeonLevelBuilder.gd:750-797`): registry pick → clear → evaluate → stamp. With `loop` + `iterate_by =
"room_id"` + per-iteration `runtime_params` (`iteration_key` → `room_id`) + compiled-subgraph reuse, a single
"style floor" graph could partition `bl_floor_data_to_points` output by room and run each room's subgraph. The
`$room_id` binding from Step 3 would resolve per iteration unchanged. Three things are missing before BL can
move the loop into the graph:

- the **subgraph must be chosen per iteration** from a partition attribute, because the registry picks a
  different graph per room (`RoomStyleRegistry.find_best_match`) (Feedback F13);
- iterations must run **serially in sorted key order**, because rooms share `FloorData.cover_cells`;
- the registry match itself (tags, `min_room_cells`, priority) would need a `bl_assign_room_styles` node
  writing `@data.style_graph`.

Until those exist, keep the GDScript loop. P1's compiled-graph cache alone would already make it cheaper,
since the same graph is re-parsed for every room.

**Performance in the meantime ([newer tree], §2.4).** P0 does not reduce instancing cost. Until P1 ships a
compiled-graph cache shared across repeated `subgraph` calls and across rooms (Feedback F20), the dress pass
costs 0.8–1.1 s per stop. BL-side options, each guarded by V-golden:

- **Run the dress pass once per stop instead of about 4× per room.** Kit output points already carry
  `room_id`, and `bl_points_to_floor_data_props` writes each prop into the room named by its per-point
  `room_id` (`bl_points_to_floor_data_props.gd:72, 137, 295`). A single floor-level dress graph fed with every
  room's anchor points could therefore replace about 80 kit calls with about 4. Preconditions: kit logic must
  be room-local by construction (filters keyed on per-point attributes, not on a room-wide scalar), and the
  per-room clear policy (`_clear_room_style_domains`) must run for all styled rooms before the pass.
- **Merge the four kit calls per room into one**, partitioning inside by a `kit` attribute. This saves the
  per-call instancing (6–12 ms × 3 per room).
- Do not trade correctness for speed. The FloorData writer chain must stay serial (above).

### Step 8 — Grid attribute: `bl_sync_grid_cell` and the hand-kept cell streams (i) — **not this round**

`bl_sync_grid_cell` is already gone in Step 1: no graph used it. BL does still maintain grid semantics by
hand in several places, and they disagree with each other:

- producers: `bl_floor_data_to_points` and `bl_style_context_points` write `grid_cell` / `cell_x` /
  `cell_y` / `room_id`. `BLRoomStyleRuntime._point_data_for_context` writes the same (`:419-503`);
- consumers: the `expression` nodes use `posmod(cell_x|cell_y, N)` (armory, office, storage, kitchen_island,
  locker_room, workshop). The interpreter derives the cell as `floor(pos / tile)` (**min-corner**,
  `bl_points_to_floor_data_props.gd:148-152`), while `BLRoomStyleRuntime._cell_from_point` uses
  `round(pos / 2.0)` (`:623-625`). The two conventions disagree. This is the "cell-min corner pushes props out
  on N/W walls" issue that `STYLE_LAB_AUDIT.md` worked around.

When the P2 grid attribute lands (canonical `cell` + `cell_size` data attr, `snap_to_grid.anchor`,
`transform`/`point_offsets`/`copy` keeping `cell` in sync):

1. Producers emit the canonical `cell` and `@data.cell_size = 2.0` instead of `grid_cell` / `cell_x` /
   `cell_y`.
2. The interpreter and `_cell_from_point` read `cell`. Pick **one** anchor and document it. Capture a golden
   first: changing the anchor moves props.
3. The expressions become `posmod(cell.x, N)` (or the P2 equivalent). Update `ROOM_STYLE_AUTHORING_SPEC.md:40-48, 76-80, 158-160`.
4. Remove the `grid_cell` / `cell_x` / `cell_y` registrations after one release with both written.

### Step 9 — Documentation refresh

| Doc | Stale statement | Fix |
|---|---|---|
| `docs/PCG_AUTHORING.md:3` | "Flow Nodes addon is re-baselined on upstream" (it was pinned at `58a9d3c`) | state the release now vendored and point at this plan |
| `docs/PCG_AUTHORING.md:9` | `DungeonLevelBuilder.gd:643` | `:662` (or the new line) |
| `docs/PCG_AUTHORING.md:19` | style graphs described as "a second, currently-unused styling system" | they run in-game for every registry-matched room (`DungeonLevelBuilder.gd:696, 722-797`) |
| `docs/PCG_AUTHORING.md:57-60` | native lib "Windows-editor only"; export needs a rebuild | upstream ships Windows template debug/release + Linux template debug; macOS release and Linux release still missing |
| `docs/PCG_AUTHORING.md` (new §) | — | node directory `res://scripts/pcg_nodes`, `category`, `$room_id` binding, the seed rules from Step 4 |
| `graphs/styles/ROOM_STYLE_AUTHORING_SPEC.md:34, 166-169` | room_id=1 guidance, `CACHE_MODE_IGNORE` snippet | binding + plain `load()` |
| `docs/STYLE_LAB_AUDIT.md` | verdict table pre-C1/C2 | append the Step 2c review results |
| `artifacts/stylelab/validate_graphs.py:3` | hard-coded `C:\Users\mattk\...` path | derive the path from `__file__` |
| `artifacts/loop1_audit_digest.md:147, 160, 167, 199, 217` | exports lose native; root `bin/` duplicates (already gone); style path "mostly-unused"; unused nodes | mark as resolved with commit refs |

---

## 4. Risk register

| ID | Risk | Likelihood / impact | Mitigation / detection |
|---|---|---|---|
| R1 | **Leak fix changes memory, not output.** Base `evaluate_graph` never frees its GraphNode Controls. Upstream frees them after collecting outputs (`flow_nodes_io.gd:746-749, 1353`). BL nodes keep no references to themselves past `execute`, and outputs are RefCounted `Data` / `FloorData`. **[newer tree]** already carries the same fix, so for the live tree this is **not** a re-baseline delta. The orphan check stays as a regression check | Clone: certain / positive. Newer tree: none | Before and after Step 2, log `Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)` after two consecutive floor builds. Before: grows by roughly the evaluated node count (14 + Σ style-graph nodes incl. subgraph internals, up to ~120 per styled room). After: flat. **[newer tree]** flat both times. Golden is unaffected |
| R2 | **Topological order parity.** Base roots include every subgraph (`subgraph.gd:13`, `is_final`). Upstream roots only terminal subgraphs and adds consumer/variable stabilisation (Table B) | Low / medium | Only FloorData writers matter, and they are serialised by links. The only props-reading output (`f2p` port 3) is unwired in all graphs. Gates G1/G2 plus the attribution run in Step 2 prove it |
| R3 | **Native lib on export platforms.** Keep every `ClassDB.class_exists` guard (`ZoneCarver.gd:251`, `RoomSubdivider.gd:1078`, `bl_style_context_points.gd:89`). New: exported Windows builds gain `template_debug/release` DLLs, so they switch from the Manhattan brute-force fallback to native L2 nearest. The two can choose different hallway pairs, so **exported floors differ from editor floors today and will match them after the upgrade**. Linux now loads a template_debug `.so` everywhere (`flow.gdextension` `linux.x86_64`). macOS release / Linux release are still missing | Medium / medium | Goldens record `meta.native`. Capture and compare on the same machine class. Export smoke test (acceptance). Optional: decide whether the fallback should become L2 so every platform agrees |
| R4 | **Determinism across the seed change.** `eval_id` stops being a seed (`DEPRECATIONS.md` §2). Hand-built contexts would silently lose the seed if any `bl_*` node still read `eval_id` after Step 4 | Medium if steps are skipped / high (floors change) | `BLFlowSeed` transitional helper (Step 2a.4). Raw `ctx.seed` for master stages, not `effective_seed()` (Step 4). Gate G1 on seeds 424242/8001/1/77/20260927. `grep eval_id scripts/` empty after Step 4. Step 4b handled as a design change |
| R5 | **Export exclusion breaks style nodes** (`bl_floor_data_to_style_context.gd:15`, `export_presets.cfg:11`) | High (probable) / high (no styled rooms in shipped builds) | Step 1.4 + export smoke test |
| R6 | **Registry script lookup in exported builds.** Upstream resolves `res://scripts/pcg_nodes/<template>.gd` with `ResourceLoader.exists(path, "Script")` (`flow_node_registry.gd` `_find_template_script`). Exported scripts are remapped | Low / high | Export smoke test after Step 2. If it fails, report upstream (Feedback F15) and register the directory explicitly as a fallback |
| R7 | **Cached graphs shared across rooms** once `CACHE_MODE_IGNORE` goes. Any node that writes into an Array/Dictionary setting it got by reference from `graph.data` (`dict_to_resource` assigns containers as-is) would leak state between rooms | Low / medium | `game/<seed>/again` golden case. P0 promises graph resources stay immutable |
| R8 | **Restyle behaviour changes when the room-id bug is fixed** (Step 3) | Certain / low (restyle is currently inert) | Separate commit, re-captured `restyle/*` baseline, follow-up ticket for spawning (Step 3) |
| R9 | **Owner-less evaluation in `@tool` contexts** (Style Lab in the editor) takes the "editor preview" branch of `require_input` (`GF-PCGODOT/.../node.gd:1028-1036`): an unwired port yields an empty output instead of an error | Medium / low (diagnostics only) | Authoring errors still show in the Data Flow dock. Feedback F16 |
| R10 | **P0 is in flight.** Names in Steps 4–5 follow `RUNTIME_API_P0.md` and may shift | Medium / low | Re-read the contract at adoption time. Steps 2–3 depend only on landed commits |
| R11 | **Designer-visible layout drift from C1/C2** in 14 styles | Certain / medium | Step 2c.2 review; seeds are free tuning knobs. Do it in the same PR as the re-baseline so nothing ships half-reviewed |
| R12 | **Stale game docs** mislead the next agent or designer (§3 Step 9 table), e.g. `PCG_AUTHORING.md:19` says the style graphs are unused | High / medium | Step 9 in the same release |
| R13 | **Editor churn**: first editor load after the swap rewrites `.uid`/`.import` files and version-1 graphs get marked dirty | Certain / low | Commit the churn in 2a. Explicit v2 bump in 2d |
| R14 | **Colour loss for `bl_*` nodes**: "Black Lantern" is not in `CATEGORY_HUES`, so each node gets a per-template hash hue | Certain / cosmetic | Feedback F8 |
| R15 | **Instancing cost** (§2.4): 6–12 ms per kit-subgraph call, per-stop styling 1.8–2.1 s. Neither P0 nor the leak fix helps; re-baselining could even add cost (`has_setting_bindings` checks, variable fast paths) | Certain / medium (load-time hitch per stop) | Track the golden `timing` block per step and fail review if it regresses by more than 10%. Step 7 BL-side mitigations. Feedback F20 |
| R16 | **Local wired-port patch dropped on re-baseline** ([newer tree] `flow_nodes_io.gd` ~`:816`, ~`:942`) in favour of upstream `_restore_wired_param_ports` | Low / high (kit settings silently revert to saved values) | Golden `game/*` + `lab/*` over the kit subgraphs. Add one lab case that runs a kit subgraph with a non-default wired value, so a silent fallback to the saved value shows up |
| R17 | **Upstream work in flight changes the baseline**: the `980dc82` cherry-pick, and each node fix in Step 5b (e.g. `match_and_set` seeding, `copy` inheritance, `sample_points` attribute passthrough, `merge` stream order) | Certain / medium | Take the cherry-pick before Step 0. One BL commit per fix, golden before and after. Ask upstream to list every output-changing fix in `DEPRECATIONS.md` §2 with an opt-in legacy flag where cheap (Feedback F22) |

---

## 5. Effort and parallelism

| Step | Effort | Can start | Blocks |
|---|---|---|---|
| 0 Golden oracle + baseline | 1 d | now | 2 |
| 1 Cleanup + export fix + export smoke test | 0.5 d | now (parallel with 0; capture 0 first) | — |
| 2a Swap + move + setting + seed helper | 0.5 d | upstream release | 2b |
| 2b Compare + attribution run | 0.5 d | 2a | 2c |
| 2c Divergences + designer review (14 styles) | 1–1.5 d (designer) | 2b | 3 |
| 2d/2e v2 bump + UI check | 0.25 d | 2c | — |
| 3 Bindings | 0.5 d | 2 | 4 |
| 4a Evaluate / seed parity | 0.5–1 d | P0 runtime API + 3 | 4b, 5 |
| 4b Style seeds (optional) | 0.5 d + designer review 0.5–1 d | 4a | — |
| 5 Helpers | 1 d | P0 `Data` helpers + 4a | — |
| 5b Workaround removal ([newer tree]) | 1.5–3 d depending on site count, + 0.5 d for `gen_room_families.gd` bindings | per upstream fix | — |
| 6 Style Lab | 0.5 d now; more when F1–F3 land | 2 | — |
| 7 FloorData / P1 note | 0 (docs only) | — | — |
| 7 Perf mitigation (optional, [newer tree]) | 1–2 d (single dress pass per stop) | 2 | — |
| 8 Grid attribute | 1–1.5 d | upstream P2 | — |
| 9 Docs | 0.5 d | alongside each step | — |

**Total for this round (0–6 + 9, without 4b, 5b and 7): about 7–8 developer-days plus 1–1.5
designer-days.** Step 5b adds 2–3.5 days, spread over the patch releases that carry the node fixes.

Parallel streams, split by file ownership so they do not conflict:

- **Stream A (runtime glue):** Steps 3, 4 and the game-side part of 5. Owns `DungeonLevelBuilder.gd`,
  `BLRoomStyleRuntime.gd`, `GameController.gd`, `BlackLanternStyleLab._run_style_graph`. Strictly
  sequential: 3 → 4a → 5.
- **Stream B (nodes):** Step 1.2/1.4, the node part of Step 2a, and the node part of Step 5. Owns
  `scripts/pcg_nodes/*` and `scripts/flow/BLFlow*.gd`.
- **Stream C (editor):** Step 6. Owns the Style Lab open-graph code and `addons/bl_style_lab_dock/*`. Can run
  as soon as Step 2 lands.
- **Stream D (content):** Step 2c designer review, the `office_command` edit, the binding script run, and
  Step 5b graph edits. Owns `graphs/**` and `tools/graph_gen/*`.
- **Stream E (docs):** Step 9.

Step 0 must finish before Step 2a starts. The Step 2a swap is one commit touching A/B/D files, so it has one
owner.

---

## 6. Acceptance checklist

- [ ] `artifacts/pcg_golden/pre_rebaseline.json` committed, captured on the current addon in the team's
      working tree (with the `980dc82` backport) and reproducible (self-compare = 0 diffs).
- [ ] After Step 2: **G1** `master/*` identical, **G2** `lab/primary_supply` + `lab/objective_objective.tres`
      identical, **G3** attribution run = 0 diffs. `post_rebaseline.json` committed with the designer review
      notes.
- [ ] After Steps 3, 4a and 5: golden identical to the previous baseline, except `restyle/*` in Step 3
      (room-id fix, reviewed).
- [ ] V-boot on seeds 424242 and one random seed: `status=OK`, styled-room count printed, no
      `Failed to resolve node script` / `Input B not connected` / `Stream name conflict` /
      `FlowGraphNode3D: no graph resource assigned`, and a connected floor (entry → objective walkable).
      `ai_start_playtest(424242, 120)` runs to completion.
- [ ] `diff -rq <upstream tag>/demo/addons/flow_nodes_editor addons/flow_nodes_editor` is empty (ignoring
      `.import`). No `bl_*` or `project_points*` files under `addons/`.
- [ ] `ProjectSettings` `flow_nodes/node_directories == ["res://scripts/pcg_nodes"]`. Each of the 13 nodes
      shows under "Black Lantern" in the add-node menu.
- [ ] `grep -rn "CACHE_MODE_IGNORE" scripts` → only `BlackLanternStyleLab.gd:360`.
      `grep -rn --exclude-dir=pcg_golden "bind_room_filter\|FlowGraphNode3D\|EvaluationContext.new\|eval_id\|setResourceToEdit\|_find_flow_plugin\|_find_flow_dock" scripts addons/bl_style_lab_dock` → empty.
      `grep -rn "res://addons/flow_nodes_editor/nodes/bl_\|res://scripts/testing/" scripts/pcg_nodes` → empty.
- [ ] All 17 room-filter graphs carry `"bindings": {"max_value": "room_id", "min_value": "room_id"}`.
      `validate_graphs.py` is clean. All graphs are `"version": 2`.
- [ ] Orphan-node count stays flat across two consecutive floor builds (R1).
- [ ] Windows export smoke test: a styled room has props in the exported build (R3, R5, R6).
- [ ] Data Flow dock usable in the bottom panel; `A` analyze, grid toggle and `E` data inspector work.
- [ ] Style Lab: Open in Data Flow uses `EditorInterface.edit_resource`. Rebuild works for all 33 registry
      entries. New Style works.
- [ ] A runtime building restyle styles the **target** room (log `Building restyled unrevealed room N`), and
      the follow-up ticket for spawning is filed.
- [ ] **[newer tree]** Local `flow_nodes_io.gd` patches (instance freeing, `args_ports_by_name` restore,
      `node.inputs` sizing) are gone. Kit subgraphs with setting wires produce identical golden output under
      upstream `_restore_wired_param_ports`.
- [ ] **[newer tree]** Every Step 5b workaround whose upstream fix has shipped is deleted (or kept on
      purpose, like the `match_and_set` seed writer, with a comment). `gen_room_families.gd` emits `bindings`
      and has no `_param_port`.
- [ ] Golden `timing`: per-stop styling no slower than the Step-0 capture (+10% tolerance). Record the
      numbers in the PR.
- [ ] Step 9 doc table done. `BLACK_LANTERN_MIGRATION_PLAN.md` referenced from `docs/PCG_AUTHORING.md`.

---

## 7. Feedback to the addon

Each item is a Black Lantern need the P0 contract (or the landed `9417d63`/`10ec11b`) does not cover, with the
BL evidence.

| # | Gap | BL evidence | Suggested shape |
|---|---|---|---|
| F1 | **Public editor API to open a graph with fixture inputs / params / seed.** `EditorInterface.edit_resource` opens by path only, and preview runs with no inputs | `BlackLanternStyleLab.gd:413-452`, `style_lab_dock.gd:157-198` duck-type `setResourceToEdit`. `bl_floor_data_to_style_context.gd:32-45` fabricates a fixture FloorData in cold preview because the dock cannot be given one | `FlowEditorPlugin.get_singleton().open_graph(res, owner := null, inputs := {}, params := {}, seed := 0)`, and/or per-graph `FlowGraphResource.preview_params` + `preview_inputs` (fixture resource paths) used by the dock |
| F2 | **Graph saved / edited signal** | The dock saves via `ResourceSaver.save` (`flow_editor.gd:1133`), so `EditorPlugin.resource_saved` does not fire and the lab needs a manual "Reload & Rebuild" | `signal graph_saved(resource)` / `graph_edited(resource)` on the plugin singleton, or `emit_changed()` after save |
| F3 | **"Run with…" in the dock** (seed, params, fixture) | Style Lab exists largely to do this (`docs/STYLE_LAB_AUDIT.md` method) | review §3 P2 panel |
| F4 | **Output discovery by role, not by name** | `BLRoomStyleRuntime.gd:514-538` routes outputs with `lower_name.contains("proppoints")`, and `:673-685` guesses prop kind from the output name | output node setting `tags : PackedStringArray` stamped on the emitted Data (P0 already carries tags through), plus `FlowNodeIO.outputs_with_tag(outputs, tag)`; or expose `graph.out_params` with declared types and a `role` field |
| F5 | **`FlowNodeIO.evaluate` has no `overrides` argument** | Overrides are only reachable through `FlowGraphNode3D` or a hand-built ctx, which P0 otherwise removes | `evaluate(graph, inputs, seed, params, owner, overrides := {})` |
| F6 | **`owner` type mismatch**: `make_context(owner : Node3D)` / `evaluate(owner : Node3D)` vs `EvaluationContext.owner : FlowGraphNode3D` | Style Lab (a `Node3D`) would pass itself | Type `owner` as `Node3D` everywhere, or document FlowGraphNode3D-only |
| F7 | **Schema enforcement for canonical attributes** | `medical_station.tres` registered `rotation` as Float `180.0`: 5 "Stream name conflict" warnings and broken orientation (`docs/STYLE_LAB_AUDIT.md:11`). `registerStream` only warns (`flow_data.gd` conflict warning) | `registerStream` / `add_attribute` refuse (setError) a wrong type for `position`/`rotation`/`size`/`seed`/`density`/`normal`/`bounds_*`. Plus a project schema: `FlowData.declare_attribute("room_id", DataType.Int)` checked in debug builds |
| F8 | **Colour for project categories** | "Black Lantern" is not in `CATEGORY_HUES` (`node.gd:190-201`), so 13 nodes get unrelated hash hues | `meta_node.hue` (or `color`) override, or a `flow_nodes/category_hues` project setting |
| F9 | **DEPRECATIONS §2 is missing semantic changes BL hit** | Table C: `noise` ValueCubic/SimplexSmooth mapping (`5a143f6`), `registerStream` honouring declared type (`cac340b`), `build_rotation_from_up` secondary axis (`5a143f6`), non-terminal subgraphs no longer roots (`b478c5e`), `output` real type (`c6b8e7b`), `__eval_depth` + child→parent `runtime_params` publishing (`bfa7e28`) | Add rows. Offer `legacy_value_noise` on `noise` like `legacy_scale_from_extent` |
| F10 | **Golden harness usable by games before they upgrade** | BL had to write its own oracle (Appendix A) because the harness needs the new API, and a `Resource` stream digest is meaningless without a project hook | Keep the harness core on `evaluate_graph` + `Data.streams` only; add `resource_digesters: {class_name: Callable}`, per-case fixtures/params/seeds, optional per-node intermediate digests for attribution, and a `meta` block (native lib present, OS) |
| F11 | **Declare side-effecting nodes** before P1 caching/threading | `bl_points_to_floor_data_props`, `bl_zone_carver`, `bl_room_splitter`, `bl_tactical_decorator` mutate the input `FloorData` in place | `meta_node.pure = false` (default true): never cached, never parallelised, always executed in link order |
| F12 | **Per-point typed accessor with broadcast** | 8 copies: `BLRoomStyleRuntime.gd:627-671`, `bl_points_to_floor_data_props.gd:369-422` | `Data.value_at(name, i, default)` and typed variants using `bcast_idx` |
| F13 | **P1 loop: per-iteration subgraph selection and ordering guarantees** | The registry picks a different graph per room (`DungeonLevelBuilder.gd:730-797`). Rooms share `cover_cells` | `loop.subgraph_attribute` (graph path from the partition's `@data`); documented serial, sorted-key iteration when any element is impure (F11) |
| F14 | **Optional output point-count badges** | Removed upstream (`63ad631`). Designers used them in the BL copy (`node.gd:442-500` vendored) | Editor setting "Show output counts" |
| F15 | **Registry lookup in exported builds** | BL will resolve 13 templates from `res://scripts/pcg_nodes` at runtime | A test that exports the demo and evaluates a graph using a project-directory node |
| F16 | **Preview mode should be explicit, not `owner == null`** | P0 makes owner-less runtime evaluation legal, but `require_input` and several nodes still treat `owner == null and Engine.is_editor_hint()` as "editor preview" (`GF-PCGODOT/.../node.gd:1032`), hiding errors in `@tool` callers like the Style Lab | `ctx.preview : bool`, set only by the editor |
| F17 | **Report node errors to runtime callers** | A failing style graph shows up in-game only as an empty room. `setError` is visible only in the editor | `FlowNodeIO.evaluate` returns or stores `last_errors : Array[{node, template, message}]` |
| F18 | **Release binaries**: macOS release, Linux release/editor | `PCG_AUTHORING.md:57-60`, Risk R3 | Commit the CI builds |
| F19 | **Prefixed override keys depend on `resource_path`** (`graph_basename`), which may be empty for `CACHE_MODE_IGNORE` loads | BL used IGNORE loads in 3 places until Step 3 | Document it, or key on the resource uid |
| F20 | **Compiled-graph cache shared across repeated `subgraph` calls within one evaluation and across rooms**, not only across `loop` iterations | [newer tree] measurements: 6–12 ms per 20–47-node subgraph instance, 0.2–0.5 ms per trivial node. The kit subgraph runs about 4× per room × 20 rooms. Per-stop styling went from about 1.0 s to 1.8–2.1 s | P1 `FlowCompiledGraph` keyed by graph resource (+ version), reused by every `subgraph` node and every top-level `evaluate` in the process. Invalidate on graph save (F2) |
| F21 | **Name-based setting wires for script-authored graphs** | `gen_room_families.gd` `_param_port` instances node scripts to find port indices | `bindings` covers scalar knobs (landed in `9417d63`). Document it as the generator-facing API, and add `FlowNodeIO.param_port_index(template, property)` (static, no instancing) for the per-point case |
| F22 | **Every output-changing node fix must be in `DEPRECATIONS.md` §2**, with a legacy flag where cheap | The Step 5b fixes change output when a graph relies on the old behaviour (`match_and_set` RNG, `copy`/`sample_points` inheritance, `merge` column order, `point_offsets` defaults, `expression` typing) | One row per fix, with the commit. Legacy flags like `legacy_scale_from_extent` |
| F23 | **Document `add_attribute` with no input** yielding a one-point Data (schema row) | [newer tree] kit graphs | README + node tooltip |

---

## Appendix A — Golden oracle (`res://scripts/tools/pcg_golden/`)

`pcg_golden_capture.tscn`: a single `Node` with the script below. Run it as a **game** (not an EditorScript)
so autoloads exist and `DungeonLevelBuilder` (not `@tool`) executes.

```gdscript
# res://scripts/tools/pcg_golden/pcg_golden_capture.gd
extends Node
## PCG parity oracle for the PCGODOT migration. Only uses APIs that exist in BOTH the
## vendored addon (58a9d3c) and the upgraded one, so the same file captures before and after.
## godot --headless --path . res://scripts/tools/pcg_golden/pcg_golden_capture.tscn -- --label=X [--compare=res://…json]

const SEEDS := [424242, 8001, 1, 77, 20260927]
const LAB_SEED := 8001
const LAB_SIZE := Vector2i(9, 8)
const REGISTRY_PATH := "res://resources/room_styles/registry.tres"
const EXTRA_GRAPHS := ["res://graphs/styles/objective_objective.tres", "res://graphs/styles/style_room_advanced.tres"]
const RESTYLE_GRAPHS := ["res://graphs/styles/cultist_ritual.tres", "res://graphs/styles/storage_warehouse.tres", "res://graphs/styles/workshop_maintenance.tres"]
const LabBuilder := preload("res://scripts/testing/BlackLanternStyleLabFloorDataBuilder.gd")
const DLB := preload("res://scripts/level/DungeonLevelBuilder.gd")
const MASTER := preload("res://graphs/graph_black_lantern_dungeon.tres")

func _ready() -> void:
	var label := "capture"
	var compare := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--label="): label = a.get_slice("=", 1)
		elif a.begins_with("--compare="): compare = a.get_slice("=", 1)
	var cases := {}
	var timing := {}                                # not gated; tracks instancing cost per step
	var run := func(key: String, fn: Callable) -> void:
		var t0 := Time.get_ticks_usec()
		cases[key] = fn.call()
		timing[key] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	for s in SEEDS:
		run.call("master/%d" % s, _master_case.bind(s))
		run.call("game/%d" % s, _game_case.bind(s))
		run.call("game/%d/again" % s, _game_case.bind(s))
	var registry = load(REGISTRY_PATH)
	for e in registry.entries:
		if e and e.enabled and e.graph_path != "":
			run.call("lab/" + e.style_id, _lab_case.bind(e.graph_path, e))
	for p in EXTRA_GRAPHS:
		run.call("lab/" + p.get_file(), _lab_case.bind(p, null))
	for p in RESTYLE_GRAPHS:
		run.call("restyle/" + p.get_file(), _restyle_case.bind(p, SEEDS[0]))
	# [newer tree]: add run.call("kit/<name>", ...) cases that feed non-default values into wired settings
	var out := {"meta": {"label": label, "native": ClassDB.class_exists("GDKdTree"),
		"godot": Engine.get_version_info().string, "os": OS.get_name()}, "cases": cases, "timing": timing}
	DirAccess.make_dir_recursive_absolute("res://artifacts/pcg_golden")
	var f := FileAccess.open("res://artifacts/pcg_golden/%s.json" % label, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  ", true))
	f.close()
	var code := 0
	if compare != "":
		code = _compare(JSON.parse_string(FileAccess.get_file_as_string(compare)), out)
	get_tree().quit(code)

# ── cases ────────────────────────────────────────────────────────────────────
func _ctx(seed_value: int, params: Dictionary) -> FlowData.EvaluationContext:
	var ctx := FlowData.EvaluationContext.new()
	ctx.eval_id = seed_value                        # legacy convention (pre Step 4)
	if "seed" in ctx:
		ctx.set("seed", seed_value)                 # P0 field (post Step 4)
	ctx.runtime_params = params
	return ctx

func _master_case(s: int) -> Dictionary:
	var params := {"pressure": 0.0, "pressure_band": "", "awakening_stage": 0, "scarcity_bias": 0.0,
		"last_card_id": "", "last_card_effect": ""}   # = _collect_director_style_params() defaults
	var outs: Dictionary = FlowNodeIO.evaluate_graph(MASTER, {}, _ctx(s, params), params)
	var d := {}
	for k in outs.keys():
		d[str(k)] = data_digest(outs[k])
	return d

func _game_case(s: int) -> Dictionary:
	var dlb = DLB.new()                             # detached: _ready/build_level never run
	dlb._rng.seed = s
	var fd: FloorData = dlb._generate_flow_node_floor_data()   # master + _apply_room_style_graphs
	var d := floor_digest(fd)
	dlb.free()
	return d

func _lab_case(path: String, entry) -> Dictionary:
	var type_name := "PRIMARY"
	var ticket := "QUIET"
	var style_id := path.get_file().get_basename()
	if entry:
		ticket = entry.room_ticket if entry.room_ticket != "" else "QUIET"
		if entry.room_type != 0:
			type_name = str(FloorData.RoomType.find_key(entry.room_type))
		style_id = entry.style_id
	var fd: FloorData = LabBuilder.build(type_name, ticket, LAB_SIZE, "WEST", LAB_SEED, false)
	fd.rooms[1]["style_id"] = style_id
	fd.rooms[1]["style_tags"] = entry.required_room_tags if entry else PackedStringArray()
	fd.rooms[1]["props"] = []                       # mirror BlackLanternStyleLab.gd:485-488
	var seed_val: int = LAB_SEED ^ (1 * 2654435769) ^ style_id.hash()   # = _compute_style_seed
	var fdd := FlowData.Data.new()
	var vals: Array[Resource] = [fd]
	fdd.registerStream("FloorData", vals, FlowData.DataType.Resource)
	var params := {"room_id": 1, "style_seed": seed_val}
	var ctx := FlowData.EvaluationContext.new()     # Style Lab passes the seed only via params/eval_id
	ctx.eval_id = seed_val
	ctx.runtime_params = params
	FlowNodeIO.evaluate_graph(load(path), {"FloorData": fdd}, ctx, params)
	return floor_digest(fd)

func _restyle_case(path: String, s: int) -> Dictionary:
	var dlb = DLB.new()
	dlb._rng.seed = s
	var fd: FloorData = dlb._generate_flow_node_floor_data()
	dlb.free()
	var room := -1
	for i in range(2, fd.rooms.size()):              # a real room id != 1 so room-binding bugs show
		if not (fd.rooms[i].get("cells", []) as Array).is_empty():
			room = i
			break
	var graph = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var rt: Script = load("res://scripts/flow/BLRoomStyleRuntime.gd")
	if rt.get_script_method_list().any(func(m): return m.name == "bind_room_filter"):
		rt.call("bind_room_filter", graph, room)    # pre Step 3 only
	var ctx = BLRoomStyleRuntime.make_context(fd, room, s + room * 131, {"reason": "golden", "stage": 0})
	var spec = BLRoomStyleRuntime.evaluate_style_graph_with_context(graph, ctx, null)
	var report: Dictionary = BLRoomStyleRuntime.apply_style_spec(fd, ctx, spec, true)
	return {"room": room, "style_id": spec.style_id, "props": spec.prop_specs.size(),
		"warnings": Array(report.get("warnings", PackedStringArray())), "floor": floor_digest(fd)}

# ── digests ──────────────────────────────────────────────────────────────────
static func canon(v) -> String:
	match typeof(v):
		TYPE_FLOAT:
			return "%.4f" % v
		TYPE_VECTOR3:
			return "(%.4f,%.4f,%.4f)" % [v.x, v.y, v.z]
		TYPE_DICTIONARY:
			var parts := PackedStringArray()
			for k in v.keys():
				parts.append("%s=%s" % [canon(k), canon(v[k])])
			parts.sort()
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, \
		TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			var parts := PackedStringArray()
			for e in v:
				parts.append(canon(e))
			return "[" + ",".join(parts) + "]"
		TYPE_OBJECT:
			return "<%s>" % (v.get_class() if v else "null")
	return str(v)

static func floor_digest(fd: FloorData) -> Dictionary:
	if fd == null:
		return {"null": true}
	var rooms := []
	for i in fd.rooms.size():
		var r: Dictionary = fd.rooms[i]
		var props := PackedStringArray()
		for p in r.get("props", []):
			props.append(canon(p))
		var ordered := ",".join(props).sha256_text()
		props.sort()                                # gate on content; order reported separately
		var rest := r.duplicate()
		rest.erase("props")
		rooms.append({"id": i, "room": canon(rest).sha256_text(), "props": Array(props), "props_order": ordered})
	return {"rooms": rooms,
		"cover_cells": canon(fd.cover_cells).sha256_text(), "floor_cells": canon(fd.floor_cells).sha256_text(),
		"wall_cells": canon(fd.wall_cells).sha256_text(), "door_cells": canon(fd.door_cells).sha256_text(),
		"room_tickets": canon(fd.room_tickets).sha256_text(), "reveal": canon(fd.room_reveal_data).sha256_text(),
		"story_path": canon(fd.story_path).sha256_text()}

static func data_digest(d) -> Dictionary:
	if d == null:
		return {"null": true}
	var out := {}
	for name in d.streams.keys():
		var s: Dictionary = d.streams[name]
		if s.data_type == FlowData.DataType.Resource and not s.container.is_empty() and s.container[0] is FloorData:
			out[str(name)] = floor_digest(s.container[0])
		else:
			out[str(name)] = "%d:%d:%s" % [s.data_type, s.container.size(), canon(s.container).sha256_text()]
	return out

func _compare(base: Dictionary, cur: Dictionary) -> int:
	if base.meta.native != cur.meta.native:
		push_warning("native lib presence differs (%s vs %s): results not comparable" % [base.meta.native, cur.meta.native])
	var diffs := 0
	var master_diffs := 0
	for k in base.cases.keys():
		var a = JSON.stringify(base.cases[k])
		var b = JSON.stringify(cur.cases.get(k, null))
		if a != b:
			diffs += 1
			if k.begins_with("master/"):
				master_diffs += 1
			print("DIFF ", k)
	for k in cur.cases.keys():
		if not base.cases.has(k):
			print("NEW  ", k)
	print("golden: %d case(s) differ (%d master)" % [diffs, master_diffs])
	return 2 if master_diffs > 0 else (1 if diffs > 0 else 0)
```

Notes: `_compare` ignores `timing`; compare it by hand or with `jq`. `_game_case` uses a detached builder. `_collect_director_style_params` then gets `get_tree() == null`
and returns its defaults (`DungeonLevelBuilder.gd:849-851`), and the temp roots it creates are freed with
`dlb`. Refine `_compare` into per-room diffs as needed. The JSON is readable enough to diff with `git diff`
or `jq`.
