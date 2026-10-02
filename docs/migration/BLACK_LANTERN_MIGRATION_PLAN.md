# Black Lantern Tactics: migration plan to the next PCGODOT (`flow_nodes_editor`) release

> **Revision note (company @ f6f62ddf, retargeted to `05e473af`).** The first version of this plan was
> written against the `main` clone (`be55cb4`, 2026-06-10). The tree that matters is branch **`company`**.
> This revision was checked first against its pushed head `f6f62ddf` (2026-09-26) and then retargeted to
> `05e473af` (2026-09-27, ten commits later), which adds the kit, the dress pass on every indoor style, the
> `980dc82` patch-sync (`da590041`), `tools/graph_gen/style_snapshot.tscn`,
> `tools/graph_gen/flow_upstream_status.sh` and `docs/FLOW_UPSTREAM_SYNC.md`. What changed against the
> `main`-based version:
>
> - **Base.** The vendored addon is upstream **`cb064d0`** (2026-06-13) plus upstream-equal syncs and five
>   local patches, not `58a9d3c` verbatim (§1). The old "byte-identical to `58a9d3c`" finding, the
>   `plugin.gd` dock patch and the old Tables B/D no longer apply.
> - **Drift.** Almost all of the old Table C (`noise` mapping, `build_rotation_from_up`, `registerStream`
>   typing, `output` real type, subgraph roots, `runtime_params` publishing) is already inside `cb064d0`
>   or already synced, and `980dc82` came in through `da590041`. The output-changing upstream delta that
>   is left touches the **road** graphs, not the style graphs (§1.4).
> - **Export blocker fixed.** `bl_floor_data_to_style_context` already preloads
>   `res://scripts/flow/BlackLanternStyleLabFloorDataBuilder.gd`. Step 1 no longer has an export fix.
> - **Gates.** `tools/graph_gen/flow_upstream_status.sh` is the re-baseline gate: every local patch and
>   every awaited fix must read ABSORBED against the release. The team's
>   `tools/graph_gen/style_snapshot.tscn` is the Step-0 baseline and the placement gate for every step.
>   Appendix A's oracle is now optional and covers only what the snapshot does not (master graph, road
>   graph, restyle path).
> - **Graphs.** 125 graph resources under `graphs/`: 88 generated (manifest), 37 hand-authored. Only the 17
>   hand-authored room-filter graphs need the `$room_id` binding (Step 3).
> - **Workarounds.** Step 5b is re-derived with company `file:line` for each workaround, and says for each
>   one whether it can go on `897d7a2`.
> - **Citations.** Every `file:line` in §§2–6 was re-checked against `05e473af` (see the report).
>   Things that no longer exist are marked as such.

Target: Black Lantern branch `company` at **`05e473af`** (worktree `/home/user/black-lantern-company-05e473af`,
called **BL** below). The migration moves its vendored `addons/flow_nodes_editor` (called **vendored**) to
the addon release that contains the P0 round described in [`../PCG_SYSTEM_REVIEW.md`](../PCG_SYSTEM_REVIEW.md)
§3 and [`../RUNTIME_API_P0.md`](../RUNTIME_API_P0.md) (called **upstream**). The review branch
`claude/pcg-system-review-4tpca9` head is `897d7a2`.

State of upstream when this was written (branch `claude/pcg-system-review-4tpca9`, all landed, not yet merged
to upstream `main`; `plugin.cfg` still says `version="1.0"`):

| P0 piece | Status | Commit |
|---|---|---|
| `$param` bindings (`NodeSettings.bindings`), per-instance overrides (`ctx.overrides`, `"[graph:]node/prop"`), wired setting ports honoured at runtime | landed | `9417d63` |
| `flow_nodes/node_directories` project setting, category/colour from `meta_node` only, graph format v2 + `FlowGraphMigrations`, `docs/DEPRECATIONS.md` | landed | `10ec11b` |
| `FlowNodeIO.evaluate` / `make_context`, `ctx.seed`, `derive_seed()`, `generate()`/`cleanup()`, `Data.scalar/first/container`, tags + data_attrs through `output`, `flow_owner` dict | landed | `fbc48a5` |
| Golden-output harness (`demo/tests/golden`), evaluator/loop/subgraph/spawner suites | landed | `2bbb8eb` |
| Node fixes from BL feedback (`load_pcg_data_asset`, `sample_mesh` normals, `merge`, `copy`/`sample_points` inheritance, `expression` typing, `match_and_set` numeric keys) | landed | `ee662ff` |
| `match_and_set` position seeds, binding defaults from `in_params`, `meta_node.hue`/`color`, `FlowNodeIO.last_errors`, `ctx.preview`, canonical schema, `Data.value_at` | landed | `ddd0464` |
| `sample_mesh` non-indexed surfaces, bindings on Dictionary entries (Expression `args`), export-safe editor references, `match_and_set` empty `In`, `sample_spline` validation | landed | `897d7a2` |

`DEPRECATIONS.md` cites some of these by pre-squash commit ids (`ddd0464`, `ddd0464`, `ddd0464`, `ddd0464`
are inside `ddd0464`; `897d7a2`, `897d7a2`, `897d7a2` are inside `897d7a2`). They are not ancestors of
`897d7a2`, so this plan cites the squashed commit.

Every step below names the upstream piece it needs. All of them have landed on the review branch. Wait for
the tagged release (merge to upstream `main` plus a `plugin.cfg` version bump) and re-baseline once.

Line references are to BL `05e473af` unless a path starts with `GF-PCGODOT/` (review head `897d7a2`).
"Base" means upstream commit `cb064d0`. §1 shows how that was established.

**History caveat.** The clone's `company` history is shallow and starts at 2026-09-17, so the re-sync commit
`eb8d48b5` (2026-06-13) is not in it. The base is therefore established by **content** (§1.1). It agrees with
`SYNCED=cb064d0` in `tools/graph_gen/flow_upstream_status.sh:16` and with
`output/company_task02/REAUDIT_REPORT.md:173` ("last upstream re-sync (`eb8d48b5..HEAD`)"). `da590041` is in
the fetched history.

---

## Summary of findings

1. **The vendored addon is upstream `cb064d0`, plus two kinds of files: upstream-equal syncs, and five local
   patches that the review branch has now absorbed.** 16 framework `.gd` files differ from `cb064d0`.
   Eleven are byte-identical to later upstream code (`532f0af`, `e39e39c`, `c6b8e7b`, `bfa7e28`, and
   `980dc82` via `da590041`). Four carry only a local patch (`flow_i18n.gd`, `node_draw_debug.gd`,
   `nodes/match_and_set.gd`, `nodes/sample_spline.gd`). One carries both (`flow_nodes_io.gd`: the local
   `args_port` restore plus upstream `bfa7e28`). On top of that: `project_points`, a leftover
   `custom_grid_shader.gdshader`, and the 23 `bl_*` nodes. The team's own status script
   (`tools/graph_gen/flow_upstream_status.sh`), run against `897d7a2`, reports every local patch and every
   awaited fix as ABSORBED (§1.1). There are no BL-authored UI patches left (Table B).
2. **Upstream drift since the base is now small, and it lands on the road, not the rooms.** `noise`,
   `build_rotation_from_up`, `registerStream` typing, subgraph roots, `output` typing and `runtime_params`
   publishing are all inside `cb064d0` or already synced. Per-point seeding (`980dc82`) came in with
   `da590041`. The remaining output-changing upstream commit for production graphs is **`03c2826`**
   (`sample_spline` writes unit `size` plus bounds). It changes the six `sample_spline` nodes in four road
   subgraphs, and through them the `difference` keep-outs (Table C, C1). The other rows are either
   opt-in (`copy`/`sample_points` inheritance), conditional with no current trigger in BL graphs
   (`match_and_set` position seed and numeric keys, `expression` typing, canonical schema), or offline
   (`sample_mesh` normals in the surface bake). **No style graph is expected to change on a plain
   re-baseline.** The room-style snapshot (`style_snapshot.tscn`) should read 0 changed rooms. The road
   needs its own check, because the snapshot does not cover it.
3. **The export blocker is fixed on `company`.** `bl_floor_data_to_style_context.gd:15` (and
   `bl_style_context_source.gd:5`, `bl_style_lab_source.gd:5`) preload
   `res://scripts/flow/BlackLanternStyleLabFloorDataBuilder.gd`. Nothing under `scripts/` or
   `addons/flow_nodes_editor/nodes/` preloads `scripts/testing`, and `export_presets.cfg:11` still excludes
   `scripts/testing/*`. One note: the `McpProbe` autoload (`project.godot:67`) names 13 `scripts/testing`
   regression suites as plain path strings (`scripts/debug/McpProbe.gd:37-65`) and loads them lazily
   (`:160`). That does not fail to parse, but those suites are absent in an exported build.
4. **Latent bug in the runtime restyle path (unchanged).** `restyle_unrevealed_room` evaluates graphs
   without a `room_id` runtime param (`BLRoomStyleRuntime.gd:119`). The context builder therefore falls back
   to room 1 (`bl_floor_data_to_style_context.gd:50-60`). Its props are also never spawned, because only
   `source == "flow_style"` props are spawned (`DungeonLevelBuilder.gd:7617`) while the interpreter writes
   `"flow_graph"` (`bl_points_to_floor_data_props_settings.gd:27`). Step 3 fixes the room id as a side
   effect. Report the spawn filter separately.
5. **Style graphs ignore the style seed as a graph seed.** With `980dc82` in, stock randomness is
   per-position. The kit adds `seed = hash(position)` (`tools/graph_gen/gen_room_families.gd:2414, 2476`).
   `style_seed` still reaches only `StyleContext`, so the same room geometry dresses the same way on every
   floor. Passing `style_seed` as the P0 graph seed is a design decision, so it stays split out as Step 4b.
6. **Instancing cost is the next wall, and P0 does not fix it.** The kit's dress pass (`sg_kit_dress_room`
   in all 42 indoor styles; it calls `sg_kit_arrange`, `sg_kit_on_tops`, `sg_kit_walls` and `sg_kit_floor`, and the last two call `sg_kit_subgrid`) added 0.7–1.0 s of graph time per stop (commit
   `0cdd9492`). The fix is P1's compiled-graph cache (Feedback F20). Step 7 gives BL-side mitigations.
   `style_snapshot` records graph ms per room, which gives the tracking the old plan asked for.
7. **The master dungeon graph is off the default game path.** `use_hotel_generation = true`
   (`DungeonLevelBuilder.gd:36`) takes precedence at `:541`, and nothing in the tree sets it false. So
   `graphs/graph_black_lantern_dungeon.tres` runs only when `use_hotel_generation` is off (`:570-571`). The
   production Flow evaluations are the per-room style graphs (`:1002-1108`, reached from the hotel and stop
   paths at `:825, :848`) and the overworld road dressing (`scripts/road/OverworldRoadFlowAdapter.gd:226-287`).

---

## 1. Vendored-vs-upstream delta

### 1.1 How this was established

```bash
# upstream at the base the team names (cb064d0 exists: "Merge pull request #13", 2026-06-13)
git -C GF-PCGODOT worktree add <scratch>/upstream_cb064d0 cb064d0
diff -rq <scratch>/upstream_cb064d0/demo/addons/flow_nodes_editor black-lantern-company-05e473af/addons/flow_nodes_editor \
  | grep -v -E '\.uid|\.import|/bl_'
#  -> 16 framework .gd files differ; only in BL: custom_grid_shader.gdshader, nodes/project_points{,_settings}.gd
#     (plus 23 bl_* nodes + 23 settings). bin/ is identical to cb064d0 (incl. the .exp/.lib by-products).

# which later upstream revision each differing file equals (0 = byte-identical)
for f in <16 files>; do for r in cb064d0 980dc82 main 897d7a2; do
  git show $r:demo/addons/flow_nodes_editor/$f | diff - ours/$f | grep -c '^[<>]'; done; done

# the team's own gate, run read-only (fetch removed) against the review head
tools/graph_gen/flow_upstream_status.sh ~/GF-PCGODOT origin/claude/pcg-system-review-4tpca9
#  -> §2 local patches: 6/6 ABSORBED; §3 awaited fixes: 4/4 ABSORBED
```

Per-file result against `cb064d0` / `980dc82` / upstream `main` (`91471c1`) / review head `897d7a2`, in
changed lines (0 = byte-identical):

| File | cb064d0 | 980dc82 | main | 897d7a2 | Table |
|---|---|---|---|---|---|
| `flow_data.gd` | 31 | **0** | 18 | 231 | D (`532f0af` `emptyLike` `:673`, `980dc82` `resolve_seed` `:92`) |
| `flow_editor.gd` | 11 | 0 | **0** | 19 | D (`e39e39c` hot-reload guard `:1065-1075`) |
| `flow_i18n.gd` | 7 | 7 | 7 | 8 | **A** |
| `flow_nodes_io.gd` | 14 | 7 | 7 | 729 | **A** (`:819`, `:942-944`) + D (`bfa7e28` `:929`, `:1020`) |
| `node_draw_debug.gd` | 9 | 9 | 9 | 18 | **A** |
| `nodes/attribute_noise.gd`, `attribute_random.gd`, `mutate_seed.gd`, `select_points.gd`, `transform.gd` | 9–23 | **0** | **0** | 2–9 | D (`980dc82` via `da590041`) |
| `nodes/branch.gd`, `expression.gd`, `point_to_attribute_set.gd` | 4–47 | 0 | **0** | 0–29 | D (`532f0af`) |
| `nodes/output.gd` | 7 | 0 | **0** | 13 | D (`c6b8e7b`, `:152`) |
| `nodes/match_and_set.gd` | 9 | 9 | 9 | 93 | **A** (`:25-33`) |
| `nodes/sample_spline.gd` | 15 | 239 | 249 | 283 | **A** (`:219-233`) |

**Counts (framework files differing from `cb064d0`):** Table A, local patches: **5** `.gd` files (4 local
only, plus `flow_nodes_io.gd`, which mixes local and upstream code), **2** local node files
(`project_points{,_settings}.gd`) and **1** leftover (`custom_grid_shader.gdshader`). Table B, BL UI
additions: **0**. Table C, output-changing upstream commits not in BL: **1** that changes production
graphs (`03c2826`), **5** conditional ones with no trigger in current BL graphs, and **2** offline or
editor-only ones. Table D, upstream code already synced: **11** files, plus the `bfa7e28` hunk in
`flow_nodes_io.gd`.

Against the review head the picture is the reverse. Ignoring `bl_*`, `.uid` and `.import`, **197** files
differ from `897d7a2`. All of them are upstream moving on (the 2026-06-14..06-22 description, type-hint and
`size→bounds` commits, plus the whole P0 round). None of them is BL content.

The addon `.uid` files: 41 differ from `cb064d0`. BL keeps its own on every sync (`FLOW_UPSTREAM_SYNC.md` §1).
The three the graphs reference are the same on both sides: `flow_graph_resource.gd` = `uid://j6vjeb5cjjoy`,
`graph_input_parameter.gd` = `uid://co0f3ugd2wj1y`, `nodes/subgraph_settings.gd` = `uid://coavnert1vxj4`.
One mismatch is worth taking from upstream. BL's `flow_graph_edit.gd.uid` is `uid://brxprus0a0g4`, but
`flow_editor.tscn` references `uid://cr8w0asb2kvr8`, which is upstream's value. That mismatch is the "invalid
UID" warning on every BL boot (`output/company_task02/REAUDIT_REPORT.md:175`).

### 1.2 Table A: what BL actually carries on top of `cb064d0`

| Item | What it is | Upstream on `897d7a2` | Decision |
|---|---|---|---|
| `flow_nodes_io.gd:819` (restore `args_ports_by_name` after `refreshFromSettings`) and `:942-944` (grow `node.inputs` to the highest connected arg port) | Wires from graph inputs into node **settings** work at runtime, nested and time-sliced | Superseded by `9417d63`: `_restore_wired_param_ports` (`GF-PCGODOT/.../flow_nodes_io.gd:1140-1153`, called at `:1229`) and input growth (`:1370-1387`). Precedence: wired port > override > binding > saved | **Drop on re-baseline.** Exercised today by 6 road wires (`sample_spline.uniform_interval` in `sg_road_clearings`, `sg_road_guardrails` ×3, `sg_road_placement`, `sg_road_poles`) and 12 kit wires (`select_points.ratio` ×4, `copy.num_copies` ×2, Expression `args.theme` ×4 / `args.n` ×2). After the generator re-run, the kit's `ratio` and `num_copies` become bindings (Step 5b) |
| `flow_i18n.gd:120-124`, `node_draw_debug.gd:80-84` | `EditorInterface` through `Engine.get_singleton` (the Task 01 1B export fix) | Same approach in `897d7a2` (`flow_i18n.gd:122`, `node_draw_debug.gd:82`), plus 15 more sites and a static-scan test (`RuntimeEditorClassReferencesTest.gd`) | **Drop** |
| `nodes/match_and_set.gd:25-33` | Empty `In` keeps the Attributes table's schema | Superseded by `897d7a2` (DEPRECATIONS `897d7a2`, `GF-PCGODOT/.../nodes/match_and_set.gd:75-80`). Same output: `In` plus a typed zero-length stream per Attributes column | **Drop** |
| `nodes/sample_spline.gd:219-233` | A typed empty `node` stream is valid (a road with no bridges); split error texts; any invalid entry is an **error** | Superseded by `897d7a2` (DEPRECATIONS `897d7a2`, `GF-PCGODOT/.../nodes/sample_spline.gd:213-235`), with **different semantics**. Invalid entries are skipped with one warning (BL: the node errors), the error texts differ, and an empty typed stream emits an empty Data with the common, `density` and `seed` streams | **Drop.** Check that `OverworldRoadRegression` still passes for bridge-less edges, and update any test that matches the old error text |
| `nodes/project_points.gd` + `_settings.gd` | Local raycast-projection node. Used by **no** graph (template census over `graphs/**/*.tres`: 0). `project_points.gd:17` names `EditorInterface` directly | Not upstream | **Disagreement with `FLOW_UPSTREAM_SYNC.md` §1**, which says keep it because deleting it crashes the editor's hot-reload watcher. BL already has upstream's watcher guard (`e39e39c`, `flow_editor.gd:1065-1075`). Recommendation: move it with the `bl_*` nodes to `res://scripts/pcg_nodes/` (Step 2), and route `:17` through `FlowNodeBase.editor_edited_scene_root()` (`897d7a2`) so an export never parses a bare `EditorInterface`. Delete it once a watcher test confirms the crash is gone |
| `custom_grid_shader.gdshader` (+ `.uid`) | Leftover of the custom grid that upstream removed in `db68390` (before `cb064d0`). Nothing references it | Absent | **Delete.** See Step 2a: "copy upstream over ours" alone would leave it behind |
| `bin/libflow.windows.editor.x86_64.{exp,lib}` | MSVC link by-products. They were in upstream `bin/` at `cb064d0`; `897d7a2` no longer has them | Absent | **Delete** with the swap |
| `bin/flow.gdextension` + DLLs | Identical to `cb064d0`: Windows editor + template_debug/release, macOS debug | Adds `linux.x86_64` template_debug `.so`; Windows DLLs rebuilt | Replaced wholesale (Table C, C8) |
| 23 `nodes/bl_*.gd` + 23 `*_settings.gd` | BL project nodes (§2.2) | Not upstream | **Move** to `res://scripts/pcg_nodes/` (Step 2). Delete the 10 unused ones first (Step 1) |

### 1.3 Table B: UI additions — class (iii)

No BL-authored UI patch is left. `plugin.gd` equals `cb064d0` (upstream's own bottom-panel `EditorDock`,
`plugin.gd:10, 44`), and `flow_inspector.gd`, `custom_grid.gd` and the output point-count badges were already
gone at `cb064d0`. What remains is upstream editor code that names BL:

| Item (vendored location) | Origin | Upstream `897d7a2` | Decision |
|---|---|---|---|
| Hot-reload watcher guard (`flow_editor.gd:1065-1075`) | upstream `e39e39c` (synced) | Present | Nothing to do |
| "Black Lantern" add-node category (`search_add_node_popup.gd:19`, `flow_editor.gd:1472`) and `bl_` hue (`node.gd:218`) | upstream at `cb064d0` | Deleted in `10ec11b`. Category and colour come from `meta_node.category`, and `meta_node.hue`/`color` now override the colour (`ddd0464`, `GF-PCGODOT/.../node.gd:383-395`) | Re-apply **in BL**: add `"category": "Black Lantern"` and a `"hue"` to each moved node's `meta_node` (Step 2) |
| `node_draw_debug.gd` debug-label list naming BL streams (`center_bias`, `distance_to_door`, `is_protected`, `grid_cell`, `cell_x`, `cell_y`, `room_id`, `door_id`) | upstream at `cb064d0` | Removed | Editor-only. Nothing to re-apply |

### 1.4 Table C: upstream changes since `cb064d0` that can change BL output on re-baseline — class (ii)

Source: `docs/DEPRECATIONS.md` §2, plus `git log cb064d0..897d7a2 -- demo/addons/flow_nodes_editor/nodes`
with each diff read for the templates BL uses. "Affected" comes from a template census over all 125
`graphs/**/*.tres` on `05e473af` (both the `&"…"` and plain-string template forms).

| # | Change (commit) | Affected BL graphs / nodes | Chosen semantics | Detection |
|---|---|---|---|---|
| C1 | `sample_spline` records the sample extent as `bounds_min/max` and writes **unit** `size` (`03c2826`); `legacy_scale_from_extent` restores the old output (`e6aea74`) | 6 `sample_spline` nodes in 4 road subgraphs: `sg_road_clearings` (`clearing_samples`), `sg_road_guardrails` (`rail_*_modules` ×3), `sg_road_placement` (`forest_samples`), `sg_road_poles` (`pole_samples`). `size` flows into the `difference` keep-outs (`sg_road_clearance` `socket_keepout`, `sg_road_poles` `pole_socket_keepout`), which test box overlap from `size` (`GF-PCGODOT/.../nodes/difference.gd:28-61`). Evaluated in production by `OverworldRoadNetwork.gd:177, 746` | **Keep the current look first**: set `"legacy_scale_from_extent": true` on the 6 nodes in the re-baseline commit. Then decide separately whether to adopt the new semantics (road designer review) | Not covered by `style_snapshot` (rooms only). Use `OverworldRoadRegression` plus a road-dressing digest (Appendix A, optional `road/*` case) |
| C2 | `match_and_set`: points **without** a `seed` stream draw from `resolve_seed(null, positions, i, effective_seed())` instead of the node RNG (`ddd0464`, DEPRECATIONS `ddd0464`); `legacy_global_rng` restores the old order | 16 nodes in 8 graphs. **No current trigger**: the kit picks run after `pk_seed`/`*sd` (`seed = hash(position)`, `gen_room_families.gd:2414, 2476`), so they take the seed stream. `on_match` (`:2514`) and `sg_kit_dress_room` `st_role` match unique keys with no weight. The road `seed_broadcast`/`clearing_seed_broadcast` pick from a 1-row table, and `kind_pick` runs after `mutate_seed` | Adopt upstream | `style_snapshot` must show 0 changed rooms. A change here means a table with duplicate keys, or a pick without a seed stream |
| C3 | `match_and_set` numeric-aware key match after the exact string match fails (`ee662ff`) | Same 16 nodes. Keys are non-numeric strings (`slot` = `<theme>.<use>`, `skey` = `<prefab>:<n>`, `piece`, `band`) | Adopt | Snapshot |
| C4 | `expression`: a numeric result written into an existing Bool/Int/Float stream keeps that stream's type (`ee662ff`) | 938 expression nodes in 61 graphs. Static census: no out-name collision between numeric types. The kit's `rank` was made Float for this reason (`0cdd9492`), `is_protected` is overwritten with `false` (Bool over Bool), `seed` with `hash(position)` (Int over Int) | Adopt | Snapshot |
| C5 | `registerStream` refuses a canonical attribute of the wrong type (`ddd0464`, DEPRECATIONS `ddd0464`) | None found. Every BL write of `position`/`rotation` is a Vector, `seed` is Int (`hash()`, `mutate_seed`), `density` is Float (`sg_road_placement` `density_margin`). No `bl_*` node registers a canonical name with another type | Adopt | Boot log: no `push_error` from `registerStream` |
| C6 | Bindings fall back to the graph's declared `in_params` default (`ddd0464`); bindings reach Dictionary entries, and an Expression's bare `args` key binds (`897d7a2`, DEPRECATIONS `897d7a2`) | None today: no BL graph carries `bindings`, because `_has_bindings` is false on the old addon (`gen_room_families.gd:73`). This becomes live when the generator is re-run (Step 5b) | Adopt | Snapshot after the generator re-run |
| C7 | `sample_mesh` normals point outward (`ee662ff`); non-indexed surfaces no longer crash (`897d7a2`) | No graph uses `sample_mesh`. Only the offline bake (`tools/graph_gen/bake_surfaces.gd:192-215`) does, and it measures the direction itself (`:110-121`) | Adopt. Re-bake: `graphs/styles/kit/surface_points.json` must come out byte-identical, and the log must read `normals as sampled` (`:187`) | `git diff` on the JSON |
| C8 | Native lib: Linux `template_debug` `.so` added, Windows DLLs rebuilt (`9f82bdf`) | `ZoneCarver.gd:251`, `RoomSubdivider.gd:1078`, `bl_style_context_points.gd:163` pick native L2 nearest or a GDScript fallback | Adopt. Windows exports already had native (the BL `bin/` equals `cb064d0`) | Export smoke test |

Checked and **not** a re-baseline delta for BL:
- Already in `cb064d0`: `noise` ValueCubic/SimplexSmooth mapping and `build_rotation_from_up` axis
  (`5a143f6`), `registerStream` declared type (`cac340b`), subgraph roots (`b478c5e`), consumer-order
  stabilisation (`9d7a995`), `distance` unwired B (`a39ba87`), default seed `12345`, instance freeing
  (`_free_node_instances`, BL `flow_nodes_io.gd:719`, called `:1024`).
- Already synced: `output` real type (`c6b8e7b`), `runtime_params` publish-back (`bfa7e28`), per-point
  seeding (`980dc82`).
- No output change by design: graph seed with `seed == 0` (`fbc48a5`), v2 migration in memory (`10ec11b`),
  `merge` stream order (`ee662ff`), `copy`/`sample_points` inheritance defaults (`SourceOnly`/`false`,
  `ee662ff`), `load_pcg_data_asset` cache (`ee662ff`), the preview flag (`ddd0464`; every BL evaluation has an
  owner), and the `is_ownerless_preview` rewrites in `distance`, `difference`, `transform`, `math_op`,
  `point_offsets` and `build_rotation_from_up` (`ddd0464`).
- Nodes BL does not use: `5a3f9d7` (`sample_terrain_layers`, `split_splines`, `texture_sampler`, `union`),
  `c3ab89d` (`decompose_vector`, `filter`), `0bcf286` (`physics_*`), `2bbb8eb` (`scan_nodes`).
- Execution order: `build_execution_order`, `_is_topo_final_root` and `_stabilize_consumer_input_order`
  have not changed since `cb064d0`. That matters now, because `bl_floor_data_to_points` port 3
  (PropPoints, which reads props) is wired in 23 graphs: the 22 zoned families and `sg_kit_dress_room`.

### 1.5 Table D: upstream code already synced past `cb064d0` — class (i), not a delta

| Files (BL) | Upstream commit | How it got in |
|---|---|---|
| `flow_data.gd` (`resolve_seed` `:92`, `emptyLike` `:673`), `nodes/{attribute_noise,attribute_random,mutate_seed,select_points,transform}.gd` | `980dc82` (+ `532f0af`) | `da590041` ("SYNC(flow_nodes): upstream GF-PCGODOT 980dc82"). All six files are byte-identical to `980dc82` |
| `nodes/{branch,expression,point_to_attribute_set}.gd` | `532f0af` | Partial sync (the team's "Data.emptyLike"). Byte-identical to upstream `main` |
| `nodes/output.gd:152` | `c6b8e7b` | Partial sync ("output.gd type fix"). Byte-identical to `main` |
| `flow_editor.gd:1065-1075` | `e39e39c` | Partial sync. Byte-identical to `main` |
| `flow_nodes_io.gd:929, 976, 1020` (`local_params`) | `bfa7e28` | Partial sync ("local_params") |

**Reconciliation with `docs/FLOW_UPSTREAM_SYNC.md`.** Its §2 lists the same four local-patch rows as Table A,
but it reads them against `ddd0464`, so three show "local — reported". On `897d7a2` all of them are absorbed.
Disagreements and gaps:
1. §1 keeps `project_points` (see Table A).
2. §2 does not list `custom_grid_shader.gdshader` or the `bin/*.exp`/`*.lib` by-products. §4 step 3 ("copy
   upstream over ours excluding `*.uid`") would leave them, and any other file upstream deletes, in
   place. Delete-then-copy instead (Step 2a).
3. §1 excludes every `*.uid`. That keeps the `flow_graph_edit.gd.uid` mismatch (§1.1). Take upstream's
   `.uid` for addon-internal scripts that no BL resource references.
4. §2 does not mention that the `sample_spline` fix upstream has different semantics from BL's patch
   (Table A).
5. The status script's first branch defaults to `origin/main` (`flow_upstream_status.sh:11, 25`), where the
   P0 round has not landed yet. Name the review branch (or the release tag) first, or §2/§3 read LOCAL.

### 1.6 Everything else in the 197-file diff to `897d7a2`

These files differ only because upstream kept moving. None needs a BL decision beyond the rows above:
- type hints and export descriptions (`7b47f2d`, `c272559`, `a09082c`, `e636c2d`);
- `size→bounds` on generators BL does not use (`03c2826`, `e6aea74`), which adds `setSymmetricBounds` to
  `flow_data.gd`;
- the P0 round: `9417d63` bindings/overrides; `10ec11b` registry, migrations and categories; `fbc48a5`
  runtime API; `2bbb8eb` tests; `ee662ff`, `ddd0464` and `897d7a2` node fixes and editor-reference guards;
- native rebuilds (`9f82bdf`).

---

## 2. Current integration map

### 2.1 Call sites and glue

| # | Where | What it does | Addon behaviour it relies on |
|---|---|---|---|
| M1 | `DungeonLevelBuilder.gd:36, 39-40` | `use_hotel_generation = true` (default game path), `use_pcg_generation = true`, `pcg_master_graph = preload("res://graphs/graph_black_lantern_dungeon.tres")` | — |
| M2 | `DungeonLevelBuilder.gd:473` (`build_level`), `:541-545` (hotel/stop path, taken by default), `:570-571` (master-graph path, only when `use_hotel_generation` is off), `:589-591` (fallback `_generate_floor_data`, `:776-807`) | Chooses the floor source | — |
| M3 | `DungeonLevelBuilder.gd:930-966` `_generate_flow_node_floor_data` | Throwaway `FlowGraphNode3D` added **to the tree** (`:935-938`). Hand-built ctx: `eval_id = _rng.seed` (**seed smuggling**, `:943`), `runtime_params = _collect_director_style_params()` (`:940-945`). `FlowNodeIO.evaluate_graph` (`:947`). Reads `ValidationReport` (`:948-951`) and `FloorData` (`:953`), `queue_free` (`:954`), then `_apply_room_style_graphs(fd, int(ctx.eval_id))` (`:964`). **Off the default path** (Summary 7) | `eval_id` copied unchanged into every node. Outputs keyed by output-node `settings.name`. Resource streams carry the FloorData **by reference** |
| M3b | `DungeonLevelBuilder.gd:814-855` `_generate_hotel_floor_data` | Default path: a `MissionFloorStack` floor (a stop site is built by `StopFloorDataBuilder`, `MissionFloorStack.gd:169, 226`) is styled once via `_apply_room_style_graphs(staged, int(staged.rng_seed))` (`:825`, guarded by meta `bl_styles_applied`). Otherwise a JC hotel floor is styled at `:848` | — |
| M4 | `DungeonLevelBuilder.gd:1002-1108` `_apply_room_style_graphs` | Registry assignments (`:1010`). Per styled room: `ResourceLoader.load(path, "", CACHE_MODE_IGNORE)` (`:1043`), `bind_room_filter` (`:1050`), `_clear_room_style_domains` (`:1053`), a throwaway `FlowGraphNode3D` added to the tree (`:1056-1060`), inline FloorData wrap (`:1062-1064`), ctx `eval_id = style_seed`, `runtime_params = {room_id, style_seed}` (`:1066-1070`), `evaluate_graph` (`:1081`). The graph's writes are counted by `source == "flow_graph"`; a room that gets 0 props gets a warning with the interpreter's report (`:1078-1096`). Stamps `style_graph_path` (`:1101-1102`), then `_stamp_room_records` (`:1107`). `:1024-1029` loads `BLRoomStyleRuntime` and `FlowData` by path for no reason | Outputs are ignored apart from `is_empty()`. The graph **mutates the passed FloorData in place** (`bl_points_to_floor_data_props`). Order of mutation = FloorData link chain |
| M5 | `DungeonLevelBuilder.gd:1248-1286` `_clear_room_style_domains` | Drops decorator props and room cover before styling. Keeps `flow_graph` props (`:1271`) | Prop provenance `source`. The interpreter's default `source_tag` is `"flow_graph"` (`bl_points_to_floor_data_props_settings.gd:27`) |
| M6 | `DungeonLevelBuilder.gd:1288-1318` `_collect_director_style_params` | pressure / band / awakening / scarcity / last card into **master-graph** runtime_params. No graph node reads them (`artifacts/loop1_audit_digest.md:199`), and style graphs never receive them in the game path (`:1069`) | — (inert) |
| M7 | `DungeonLevelBuilder.gd:1333-1347` | `_floor_data_from_flow_data`, `_string_from_flow_data`: hand unwrapping of `findStream(name).container[0]` | Stream record shape `{container, data_type}` |
| M8 | `DungeonLevelBuilder.gd:1644-1662` `_scatter_cover_props` | Skips rooms with `style_graph_path` or `flow_*` props | Provenance strings |
| M9 | `DungeonLevelBuilder.gd:7080-7155` `_maybe_apply_repeat_distortion` | `CACHE_MODE_IGNORE` load (`:7128`, comment `:7125`), then `restyle_unrevealed_room` | — |
| M10 | `DungeonLevelBuilder.gd:7587-7632` `restyle_unrevealed_room` | `bind_room_filter` **mutates the passed graph** (`:7598`). Builds a snapshot FloorData (`:7600`, `:7634-7649`). Seed `int(_rng.seed) + room_idx*131` (`:7601`, a **third** seed formula). `BLRoomStyleRuntime.evaluate_style_graph_with_context(..., null)` (`:7602`), `apply_style_spec` (`:7603`), copies room keys back (`:7611-7613`), spawns only `source == "flow_style"` props (`:7616-7631`) | As M4. See Summary finding 4 |
| M11 | `GameController.gd:1728-1763, 1776-1810` | `_on_building_reaction` routes `restyle_room`/`restyle_room_reactive` to `_execute_building_restyle` (`:1758-1763`). `BUILDING_RESTYLE_GRAPHS` (cultist_ritual / storage_warehouse / workshop_maintenance, `:1776-1780`). `CACHE_MODE_IGNORE` load (`:1799-1800`), then `restyle_unrevealed_room(room, graph, {"reason","stage"})` (`:1803-1806`), log `:1808`. Triggered by `BuildingDirectorFSM` `KIND_RESTYLE_ROOM` (`BuildingDirectorFSM.gd:69, 373, 403-410, 506-508`) | — |
| M12 | `BLRoomStyleRuntime.gd:9-28` `bind_room_filter` | Rewrites `min_value`/`max_value` of every **top-level** `attribute_filter_range` with `attribute_name == "room_id"` **in `graph.data`** | That the serialized `settings` dict is re-read on every evaluation (`dict_to_resource`) |
| M13 | `BLRoomStyleRuntime.gd:31-52, 54-88` | `make_context` builds `BLRoomStyleContext`. `build_input_data` wraps 18 named inputs (9 distinct `Data`) | Input feed renames the main stream to the input name |
| M14 | `BLRoomStyleRuntime.gd:105-124` `evaluate_style_graph_outputs` | Temp `FlowGraphNode3D` (not in tree), ctx `eval_id = style_seed`, `runtime_params = director_params` (**no `room_id`, no `style_seed`**) | eval_id smuggling |
| M15 | `BLRoomStyleRuntime.gd:126-155, 514-685` | `spec_from_outputs`: fuzzy output routing by `lower_name.contains("proppoints")` (`:519, 527`), `coverpoints` / `lightpoints` / `fogshroudpoints` / `revealpoints` (`:530-538`). Prop kind guessed from the output name (`:673-685`). Per-point readers with hand broadcast (`:627-671`). Cell from `round(position/2.0)` (`:623-625`) | Output names |
| M16 | `BLRoomStyleRuntime.gd:157-261` | `apply_style_spec`, `validate_style_spec` (door/threshold/overlap/path checks) | — |
| M17 | `BLRoomStyleRuntime.gd:263-332` | `decorate_floor_with_style_graphs` + `choose_style_path`. Only caller is the unused `bl_decorator_master` (`bl_decorator_master.gd:29`). **Dead** | — |
| M18 | `RoomStyleAssignment.gd:37-38` | `compute_seed = floor_seed ^ (room_id * 2654435769) ^ style_id.hash()` (64-bit, may be negative) | — |
| M19 | `RoomStyleRegistry.gd:293-330` | `build_assignments` / `_assign_room`, `style_seed = compute_seed(...)` (`:330`; archetype path `:280`). `resources/room_styles/registry.tres` has **85 entries over 64 graphs** (14 legacy styles + 50 `stop_*`). `objective_objective` and `style_room_advanced` are **not** referenced | — |
| M20 | `scripts/testing/BlackLanternStyleLab.gd:15, 1198-1225` | `preload(flow_node.gd)`. `_run_style_graph`: hand-built ctx, `owner = StyleGraphUnderTest` (a persistent `FlowGraphNode3D` child, `:1219-1225`), `eval_id = seed`, `runtime_params = {room_id: 1, style_seed}` (`:1205-1211`). `_compute_style_seed` mirrors `compute_seed` for room 1 (`:1214-1216`) | eval_id smuggling |
| M20b | `BlackLanternStyleLab.gd:716-752` `_run_site_style_graphs` and `:870-893` zone overlay | Site mode runs every room's style the way M4 does: `CACHE_MODE_IGNORE` + `bind_room_filter` (`:731-732`), `eval_id = style_seed` (`:738`). The zone overlay evaluates a probe built from the family graph with `eval_id = room id` (`:891`) | As M4 |
| M21 | `BlackLanternStyleLab.gd:389, 466, 954, 967` | `CACHE_MODE_REPLACE` for the active graph (`:389`). `CACHE_MODE_IGNORE` + `duplicate(true)` for the new-style template (`:466`), and for reading the wrapper and family graphs that build the zone probe (`:954, :967`). All three IGNORE loads are **legitimate** (keep) | — |
| M22 | `BlackLanternStyleLab.gd:519-558`, `addons/bl_style_lab_dock/style_lab_dock.gd:157-198` | Open a graph in the Data Flow dock by **walking the editor tree** for a node with `setResourceToEdit` or `graph_dock` and calling `setResourceToEdit(graph, null)`. The site-mode "open" already uses `EditorInterface.edit_resource` (`:1082`) | Private method name `setResourceToEdit` (vendored `flow_editor.gd:476`, upstream `:484`) and plugin var `graph_dock` |
| M23 | `addons/bl_style_lab_dock/plugin.gd:7-10`, `project.godot:83` | BL editor plugin (right dock). Both plugins enabled | — |
| M24 | `ZoneCarver.gd:251`, `RoomSubdivider.gd:1078`, `bl_style_context_points.gd:163` | `ClassDB.class_exists("GDKdTree")` guards with GDScript fallbacks | Native lib optional |
| M25 | `export_presets.cfg:11` | Excludes `scripts/testing/*`, `scripts/tools/*`, `artifacts/*`, `*.py`, `*.md`, the Style Lab and LoopVisualTest scenes. **Not** excluded: top-level `tools/*` (graph generators, `style_snapshot`) and `output/*` | — |
| M26 | `scripts/road/OverworldRoadFlowAdapter.gd:226-287` `evaluate_dressing` (callers `OverworldRoadNetwork.gd:177, 746`; `assemble_road_scene` `:747-774`) | Evaluates `graphs/road/graph_overworld_road_assembly.tres` per road edge. Temp `FlowGraphNode3D` owner (`:258`), `runtime_params = {dressing_density, dressing_seed}` (`:262-265`), `eval_id = dressing_seed` (`:268`), raw scalars `IN_DENSITY`/`IN_SEED` in the input map (`:283-284`), `evaluate_graph` (`:287`) | eval_id smuggling; the graph's declared `in_params`; setting wires (`uniform_interval`) |
| M27 | `tools/graph_gen/style_snapshot.gd:47-100` | The team's gate: `StopFloorDataBuilder.build` → `TacticalDecorator` → registry → per room `CACHE_MODE_IGNORE` + `bind_room_filter` (`:68-69`), hand ctx `eval_id = style_seed` (`:77-79`), `evaluate_graph` (`:81`), then an md5 over sorted per-prop lines (kind, scene, cell, yaw to 5°) (`:86-98`) | Mirrors M4. It must change in lockstep with Steps 3–4 |
| M28 | `tools/graph_gen/bake_surfaces.gd:192-222` | Offline: builds a `scan_meshes → sample_mesh → output` graph in code and evaluates it with an owner node (`:208-215`) | `sample_mesh` normals and index handling (Step 5b) |
| M29 | `tools/graph_gen/gen_room_families.gd:2303-2345` | `_param_port` instances node scripts to find setting-port indices; `_bind` writes `bindings` when `NodeSettings` has them (`:73`, `:2321-2329`) and wires otherwise | Setting ports, `bindings` |

### 2.2 The 23 `bl_*` nodes

Seed column: how the node derives randomness today. Helpers column: hand wrap/unwrap functions to replace in Step 5.
Use counts are node/graph counts over `graphs/**/*.tres` on `05e473af`.

| Node | Used by | Seed | Helpers (line) | Notes |
|---|---|---|---|---|
| `bl_building_mass` | master | `ctx.eval_id` if `use_context_seed` (true in graph) (`:17`) | `_floor_data_resource` `:43` | wraps `BuildingMassGenerator` |
| `bl_zone_carver` | master | `eval_id + 101` (`:21-30`) | `_floor_data_from_input` `:32`, `_floor_data_resource` `:46` | |
| `bl_room_splitter` | master | `eval_id + 211` (`:21-32`) | `:34`, `:48` | |
| `bl_tactical_decorator` | master | `eval_id + 307` (`:21-29`) | `:31`, `:45` | |
| `bl_validate_floor_data` | master | — | `:91`, `:105`, `_string_data` `:112` | emits `ValidationReport` "… status=OK" (`:70-80`) |
| `bl_floor_data_contract_points` | master | — | `:54` | 1,025 lines of point streams |
| `bl_style_lab_source` | `graph_room_points_debug.tres` (editor only) | `settings.random_seed` | — | preloads the builder from `scripts/flow` (`:5`) |
| `bl_floor_data_to_points` | 41 nodes / 41 graphs (`f2p`, families, `sg_kit_dress_room`) | — | `:33` | Ports 0/2/5 in the legacy styles. **Port 3 (PropPoints, `_prop_points` `:271`) is wired in 23 graphs** (22 zoned families + `sg_kit_dress_room`), and it now carries `scene_override`, `world_position`, `visual_offset`, `yaw` (`da590041`..`de39f12a`) |
| `bl_floor_data_to_style_context` | 68 / 68 (`src`) | `rt["style_seed"]` > `eval_id` > setting (`:62-67`); `room_id` from `rt[room_id_from_runtime_key]` else setting 1 (`:50-60`) | `:77`, `_resource_data` `:86`, `_int_data` `:94` | preloads `scripts/flow/BlackLanternStyleLabFloorDataBuilder.gd` (`:15`), export-safe |
| `bl_style_context_points` | 60 / 60 (`scp`) | — | — | writes `room_id = style_context.room_id` (`:183`, registered `:261`) |
| `bl_points_to_floor_data_props` | 379 / 73 | — | `:349`, `_wrap_floor_data` `:359`, `_get_*_stream` `:390-424`, `_safe_*` `:426-448` | mutates FloorData in place. Cell = `floor(pos/tile)` (`:156-157`), except `free_place` points (`:82-85, 154-159`, `0cdd9492`) |
| `bl_front_clearance` | 3 / 2 (advanced, `sg_orient_and_place`) | — | — | |
| `bl_fill_corner_points` | 2 / 2 (advanced, `sg_orient_and_place`) | — | — | |
| `bl_decorator_master` | **none** | `eval_id` (`:75`) | `:45`, `:78`, `:85` | uses `ctx.owner` (`:34`) |
| `bl_points_to_style_spec` | **none** | `random_seed + style_seed + room*4099` (`:50-51`) | `:131`, `:193` | |
| `bl_room_style_template` | **none** | `style_seed + random_seed + room*7919` (`:56-57`) | `:248` | |
| `bl_smart_prop_scatter` | **none** | — | `:263` | |
| `bl_style_anchor_points` | **none** | — | `:128` | |
| `bl_style_context_source` | **none** | — | `:70`, `:78`, `:84` | preloads the builder from `scripts/flow` (`:5`) |
| `bl_style_metadata_spec` | **none** | — | `:95` | |
| `bl_style_spec_merge` | **none** | — | `:105` | |
| `bl_style_spec_to_points` | **none** | — | `:192` | |
| `bl_sync_grid_cell` | **none** | — | `:52` | See Step 8 |

All 23 preload their settings as `res://addons/flow_nodes_editor/nodes/bl_*_settings.gd`, and all settings
scripts carry a `class_name BL…Settings`. The ten **none** rows are still referenced only by upstream's old
editor tables (`search_add_node_popup.gd:19`, `flow_editor.gd:1472`), which the swap removes.

### 2.3 Graphs

125 graph resources under `graphs/` on `05e473af` (282 `.tres` in the whole tree). **Generated** means listed
in `tools/graph_gen/generated_manifest.json` and md5-equal to what `gen_room_families.gd` last wrote. All 88
listed graphs match, so none is hand-edited. **Hand-authored** means not in the manifest.

| Group | Generated | Hand-authored |
|---|---|---|
| Room styles `graphs/styles/*.tres` (66) | 49 `stop_*`: 42 indoor wrappers (family + extras + `sg_kit_dress_room`) and 7 lots (`stop_ambulance_bay`, `_building_street`, `_churchyard`, `_court_motel`, `_diner_lot`, `_lot_gas`, `_schoolyard`) | 17: the 16 legacy styles (`armory_weapons` … `workshop_maintenance`, incl. `objective_objective`, `primary_supply`, `style_room_advanced`, `style_room_default`) and `stop_stair_hall` |
| Style subgraphs `graphs/styles/subgraphs/` (40) | 33 `sg_family_*` (zoned families) | 7: `sg_car_cover`, `sg_orient_and_place`, `sg_practical_light`, `sg_shelf_aisle`, `sg_stop_interior`, `sg_surface_item`, `sg_wall_ring` |
| Kit `graphs/styles/kit/` (6) | `sg_kit_dress_room`, `sg_kit_arrange`, `sg_kit_on_tops`, `sg_kit_walls`, `sg_kit_floor`, `sg_kit_subgrid` (+ `arrangements.json`; `surface_points.json` is baked by `bake_surfaces.tscn`) | — |
| Templates (2) | — | `style_template_basic`, `style_template_branched` |
| Master + debug (2) | — | `graph_black_lantern_dungeon` (14 nodes: 6 `bl_*` + 8 `output`), `graph_room_points_debug` |
| Road (9) | — | `graph_overworld_road_assembly` + 8 `sg_road_*` |

- **Room filters.** Exactly 17 graphs carry one `attribute_filter_range` on `room_id`: the 16 legacy styles
  and `templates/style_template_branched`. Generated styles scope the room through
  `bl_floor_data_to_style_context` with `room_id_from_runtime_key: "room_id"`
  (`gen_room_families.gd:2779, 3148`) and `bl_style_context_points`. So `bind_room_filter` is a no-op for them.
- **Setting wires** (`args_port` on a settings property): 6 road (`sample_spline.uniform_interval`), 12 kit
  (`select_points.ratio` ×4, `copy.num_copies` ×2, Expression `args.theme` ×4, `args.n` ×2). Legacy style
  graphs carry none.
- No node in any graph is `disabled`. `sg_surface_item` declares four inputs and wires none
  (`output/company_task03/flow_all_graphs/agent_support/REPORT.md:25`).

### 2.4 The kit and the dress pass (company `0cdd9492`, `de39f12a`)

- **Dress pass.** Every indoor style ends with one `sg_kit_dress_room` node (42 graphs). It reads what stands
  in the room (`bl_floor_data_to_points` port 3), looks each piece up in `data/deco_pieces.json`, then calls
  `sg_kit_arrange`, `sg_kit_on_tops`, `sg_kit_walls` and `sg_kit_floor`. The last two call `sg_kit_subgrid`.
  Every choice is a table: `data/deco_palette_{arrange,tops,walls,floor}.json`,
  `graphs/styles/kit/arrangements.json`, `surface_points.json`.
- **Nodes the kit relies on:** `match_and_set` 13, `copy` 8, `load_pcg_data_asset` 7, `select_points` 4,
  `attribute_random` 4, `self_pruning` 3, `merge` 2, `transform` 1 (in `sg_kit_floor`).
- **Measured cost** (commit `0cdd9492`): +0.7–1.0 s graph time per stop. `style_snapshot` records ms per room.
- **Graph generator.** `tools/graph_gen/gen_room_families.gd` (3,324 lines) writes families, wrappers, lots and
  the kit. It respects hand edits through the manifest (`954166a2`). It switches to `bindings` by itself
  when the addon has them (`_has_bindings`, `:73`).

---

## 3. Step-by-step migration

The order refines the brief's (a)…(i): **0 = a, 1 = h, 2 = b, 3 = c, 4 = d, 5 = e, 6 = g, 7 = f, 8 = i,
9 = docs.** The dead-tool cleanup comes first because it carries no risk and removes scripts that reference
symbols upstream has deleted. The game is shippable after each step. The re-baseline procedure is the team's
own, `docs/FLOW_UPSTREAM_SYNC.md` §4, with the corrections from §1.5. Every step ends with the **standard
verification**:

> **V-boot**: run `res://scenes/Main.tscn` on at least two stops. The log shows
> `═══ DungeonLevelBuilder — Black Lantern (seed: N) ═══` (`DungeonLevelBuilder.gd:496`), a `Hotel floor …`
> line (`:828` or `:850`), `Room style graphs: K rooms will be graph-styled` (`:1031`) and one
> `graph wrote N props into room …` line per styled room (`:1096`). No `Room style graph placed NOTHING`
> (`:1090`), `Failed to resolve node script`, `Input B not connected`, `Stream name conflict`, a
> `registerStream` refusal or any `SCRIPT ERROR` appears. Suites: `StopSiteRegression` (1145/0 at
> `de39f12a`) and `OverworldRoadRegression` (197/200: three failures are known and stale).
> **V-snapshot**: `<godot> --headless --path . tools/graph_gen/style_snapshot.tscn -- --out=res://output/style_snapshot_<label>.json --compare=res://output/style_snapshot_<baseline>.json`.
> The gate is the last line, `COMPARE N rooms unchanged, 0 changed` (`style_snapshot.gd:131`), plus the
> per-stop `graphs A -> B ms` lines (`:119`) for timing. The tool does not set an exit code, so grep for that line.
> **V-road**: the road is not in the snapshot. Run `OverworldRoadRegression` and, when a step touches road
> nodes, the optional `road/*` digest (Appendix A).

### Step 0 — Baseline with the team's snapshot on the **current** addon (a)

*Needs: nothing from upstream.*

`tools/graph_gen/style_snapshot.tscn` is BL's golden gate. It already exists, runs through the production
style path (`StopFloorDataBuilder` → `TacticalDecorator` → registry → one graph per room, the way
`_apply_room_style_graphs` runs them) for 7 stops × seeds 11 and 21 (`style_snapshot.gd:14-15`), and hashes each
room's placement (`kind|prefab|cell|yaw to 5°`, `:86-98`) with graph time per room. The team reports it as
deterministic (177/177 rooms) with a pre-sync baseline saved. That baseline JSON is **not** in the pushed tree
(`output/` has no `style_snapshot*.json` at `05e473af`), so commit it or record where it lives.

1. `tools/graph_gen/flow_upstream_status.sh <GF-PCGODOT checkout> <release branch or tag>` (release first,
   §1.5 item 5). Expect §2 and §3 to read ABSORBED throughout.
2. **Snapshot before**, twice:
   `… style_snapshot.tscn -- --out=res://output/style_snapshot_before.json`, then
   `… -- --out=res://output/style_snapshot_before2.json --compare=res://output/style_snapshot_before.json`.
   The second run must print `0 changed` (determinism). Commit `style_snapshot_before.json`.
3. **Attribution run, as before.** If a later step's snapshot diff is unexpected, revert only the suspect
   upstream behaviours in a scratch copy of the upgraded addon, re-run the snapshot, and require 0 changed
   rooms. The candidates are the Table C rows: `legacy_global_rng = true` on every `match_and_set` (C2);
   restore exact-string-only key matching (C3); `expression` retyping (C4); `registerStream` accepting any
   type (C5); `legacy_scale_from_extent` (C1, road only). Any residual diff is an unclassified divergence.
   Investigate it before continuing. Discard the scratch patch afterwards.
4. **Road baseline**: `OverworldRoadRegression` (197/200). Optionally the Appendix A `road/*` digest, which is
   the only record of road dressing output.
5. **Optional, secondary**: Appendix A's oracle for what the snapshot does not reach: `master/*` (the master
   graph, off the default path), `restyle/*` (M10) and `road/*`. It is no longer the primary gate.

Verification: V-boot unchanged (no game code touched).

### Step 1 — Pre-flight cleanup: dead tools, dead nodes, export excludes (h)

*Needs: nothing from upstream. Each item is independent.*

1. **Dead tools**: delete them (all unchanged since `be55cb4`).
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
     (`:22-23`). That graph is hand-authored, so the manifest does not protect it.
2. **Dead nodes** (0 graph uses on `05e473af`: template census over `graphs/**/*.tres`, both template forms,
   and no script reference outside the addon's own old editor tables): delete `bl_decorator_master`,
   `bl_points_to_style_spec`, `bl_room_style_template`, `bl_smart_prop_scatter`, `bl_style_anchor_points`,
   `bl_style_context_source`, `bl_style_metadata_spec`, `bl_style_spec_merge`, `bl_style_spec_to_points`,
   `bl_sync_grid_cell` (+ settings + `.uid`). Also delete the dead
   `BLRoomStyleRuntime.decorate_floor_with_style_graphs` / `choose_style_path` (`:263-332`, only called from
   `bl_decorator_master.gd:29`). `artifacts/loop1_audit_digest.md:217` already flagged these nodes.
3. **Local addon node**: `nodes/project_points{,_settings}.gd`. Keep it (team rule), but move it with the
   `bl_*` nodes in Step 2 and fix `project_points.gd:17` (Table A).
4. **Export fix: already done on `company`.** `bl_floor_data_to_style_context.gd:15`,
   `bl_style_context_source.gd:5` and `bl_style_lab_source.gd:5` preload
   `res://scripts/flow/BlackLanternStyleLabFloorDataBuilder.gd`. Keep a check in the acceptance list:
   `grep -rn "scripts/testing" scripts addons/flow_nodes_editor/nodes` must return only comments and
   `scripts/debug/McpProbe.gd:38-64`. McpProbe names the regression suites as lazily loaded strings (`:160`),
   which is not a parse failure, but those suites are absent in exports. The empty
   `graphs/black_lantern/{decorators,styles,toolkit}` directories (`artifacts/loop1_audit_digest.md:215`)
   no longer exist.
5. **Export excludes**: add `tools/*` and `output/*` to `exclude_filter` in `export_presets.cfg:11`. The graph
   generators, the snapshot, the bake and `output/company_task03/**/*.gd` are editor-only. None of them is
   excluded today.

Verification: V-boot. V-snapshot must be **identical** (0 changed): nothing that runs was touched. Also run a
**Windows export smoke test**: export, run a stop, and check that a styled room has props.

### Step 2 — Re-baseline the addon and move `bl_*` out of it (b)

*Needs: the upstream release containing the P0 round (`9417d63` … `897d7a2`). Re-baseline once.*

**2a. One atomic commit.** It has to be atomic, because the old addon can only load nodes from its own
`nodes/` directory.

1. `git mv` the 13 remaining `bl_*.gd` + `_settings.gd` + `.uid` files and `project_points{,_settings}.gd`
   to `res://scripts/pcg_nodes/`. Keep the file names, which are the template names the graphs reference;
   `FlowNodeRegistry` resolves `<dir>/<template>.gd`. Put nothing else in that directory, since the editor
   scans it for nodes. Shared helpers go to `res://scripts/flow/`.
2. Rewrite each settings preload:
   ```bash
   sed -i 's#res://addons/flow_nodes_editor/nodes/\(bl_\|project_points\)#res://scripts/pcg_nodes/\1#g' scripts/pcg_nodes/*.gd
   ```
   Then fix `project_points.gd:17` to use `FlowNodeBase.editor_edited_scene_root()`
   (`GF-PCGODOT/.../node.gd:176`).
3. Add `"category": "Black Lantern",` and a `"hue"` to each node's `meta_node` (`ddd0464`;
   `GF-PCGODOT/.../node.gd:383-395`). Optionally flip `"auto_register": false` → `true` on
   `bl_floor_data_to_style_context`, `bl_style_context_points` and `bl_points_to_floor_data_props`.
4. **Transitional seed read.** In each of `bl_building_mass.gd:17`, `bl_zone_carver.gd:29`,
   `bl_room_splitter.gd:31`, `bl_tactical_decorator.gd:28` and `bl_floor_data_to_style_context.gd:66-67`,
   replace the `ctx.eval_id` read with a helper that works both for the hand-built contexts (still used until
   Step 4) and for the P0 `seed`:
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
5. **Swap the addon: delete, then copy.** Remove `addons/flow_nodes_editor/` except the BL `.uid` files of
   scripts that BL resources reference (§1.1; keep them all if in doubt, as `FLOW_UPSTREAM_SYNC.md` §1 says).
   Copy upstream `demo/addons/flow_nodes_editor/` in, including `bin/`. This drops `custom_grid_shader.gdshader`
   and the `bin/*.exp`/`*.lib` files, which a plain copy-over would leave behind. Take upstream's
   `flow_graph_edit.gd.uid` (`uid://cr8w0asb2kvr8`). That ends the "invalid UID" boot warning. **Do not
   re-apply any Table A patch.** `flow_upstream_status.sh` shows all six absorbed.
6. **Keep the road's current look (Table C, C1):** add `"legacy_scale_from_extent": true` to the settings of
   the 6 `sample_spline` nodes (`sg_road_clearings.tres` `clearing_samples`, `sg_road_guardrails.tres`
   `rail_right_bends_modules`/`rail_left_bends_modules`/`rail_bridges_modules`, `sg_road_placement.tres`
   `forest_samples`, `sg_road_poles.tres` `pole_samples`). These are hand-authored road graphs, so the
   manifest is not involved.
7. Set **Project Settings → Flow Nodes → Node Directories** = `["res://scripts/pcg_nodes"]`, in the editor or
   with MCP `set_project_setting` (BL's `CLAUDE.md`: never edit `project.godot` directly).
8. Open the editor once so the `.uid`/`.import` churn lands in this commit. **Do not save any generated graph
   from the dock.** A save migrates it to version 2, the md5 changes, and the generator from then on treats
   the graph as hand-edited (`gen_room_families.gd:167-168`).
9. Do **not** re-run `gen_room_families.tscn` or `bake_surfaces.tscn` in this commit. Both switch behaviour on
   the new addon (Step 5b) and belong in their own commits.

**2b. Compare.** Gates:

- **G1**: V-snapshot against `style_snapshot_before.json` shows **0 changed rooms** on every stop × seed. Every
  style graph, every family and the whole kit run here. Table C predicts no room change: C2–C5 have no
  trigger in BL graphs, and C1 is road-only. If G1 fails, use the attribution run (Step 0.3).
- **G2**: road. `OverworldRoadRegression` unchanged (197/200). With the C1 legacy flag in, the optional
  `road/*` digest must be identical.
- **G3** (optional oracle): `master/*` identical. Only `bl_*` nodes and `output` run there.
- Timing: compare the per-stop `graphs A -> B ms` lines. Flag a regression of more than 10%.

**2c. Resolve the (ii) divergences.**

1. C1, road: decide whether to keep `legacy_scale_from_extent`. If the road designer wants upstream's unit
   scale plus bounds, remove the flag in a separate commit, review the keep-outs (`socket_keepout`,
   `pole_socket_keepout`) and the guardrail module spacing, and accept the new road digest.
2. The old plan's `noise` edit (`office_command.tres`, `"noise_type": 1`, now line 642) is **not needed**. BL
   has rendered `TYPE_VALUE_CUBIC` since the June sync, because `5a143f6` is inside `cb064d0`. Leave it.
3. The old plan's C1/C2 designer review (`select_points`/`attribute_random` per-point seeding) already
   happened with `da590041` ("Random picks change in every graph using these nodes … still deterministic").
   Nothing to repeat.
4. Snapshot `--out=res://output/style_snapshot_post_rebaseline.json` and commit it. **This is the new
   baseline.**

**2d. Graph format v2.** In a **separate** commit:
- The 37 hand-authored graphs: `sed -i 's/^"version": 1$/"version": 2/'` over the files listed in §2.3.
- The 88 generated graphs: change the literal `"version": 1` in `gen_room_families.gd:2374, 2818, 3133, 3179`
  (and `bake_surfaces.gd:208`) to `2`, then re-run the generator so the manifest records the new md5s. A
  `sed` over generated files would make the generator treat all 88 as hand-edited.

`FlowGraphMigrations.MIGRATIONS[2]` is empty, so nothing else changes. The old addon ignores `version`, so a
rollback stays possible.

**2e. UI.** Nothing BL-authored to re-apply (Table B). In the editor, check that the Data Flow dock opens in the
bottom panel, `A` opens the analyze panel, the grid toggle works, the boot shows no "invalid UID" warning, and
`bl_*` nodes appear under "Black Lantern" in the add-node menu with their hue.

Verification: V-boot. V-snapshot G1, V-road G2. Orphan check (R1) is now a regression check only: BL already
frees instances (`flow_nodes_io.gd:719, 1024`).

### Step 3 — Replace `bind_room_filter` + `CACHE_MODE_IGNORE` with a `$room_id` binding (c)

*Needs: `9417d63` (in the release).*

**Recommendation: use the binding, not an override.** `FLOW_UPSTREAM_SYNC.md` §3 suggests that "overrides can
replace the room-filter binding". The binding is still the better fit:

- A binding lives in the graph (`NodeSettings.bindings`). It documents itself, resolves from
  `runtime_params` (which every caller already passes or can pass), and falls back to the saved value (1) in
  the editor and the Style Lab. It also resolves inside subgraphs, because children inherit
  `runtime_params`. That lifts the "never move a `room_id` filter into a subgraph" rule
  (`ROOM_STYLE_AUTHORING_SPEC.md:209-212`), which exists only because `bind_room_filter` walks the top level.
- An override would make every caller know the node name `roomflt` (true in all 17 graphs, but only by
  convention). `evaluate(..., overrides)` now exists (`RUNTIME_API_P0.md`, "Implemented: deviations"), so
  that option is open, but it spreads a graph detail into five callers.

**Which graphs.** Only the **17 hand-authored** graphs with a `room_id` filter (§2.3). Generated graphs have
no room filter: they scope the room via `room_id_from_runtime_key` (`gen_room_families.gd:2779, 3148`). So
**no generator change is needed** for the binding. If a future family ever emits a `room_id`
`attribute_filter_range`, `gen_room_families.gd` should write `"bindings": {"min_value": "room_id",
"max_value": "room_id"}` into that node's settings through `_bind` (`:2319-2335`), which already emits
`bindings` when the addon has them. It should not be a per-file script.

**Graph edit** (`graphs/styles/style_room_default.tres`, node `roomflt`; keys stay alphabetical as Godot writes
them):

```diff
 "name": &"roomflt",
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
then the graph's declared `in_params` default (`ddd0464`). Int is coerced to float (`flow_nodes_io.gd`
`apply_setting_bindings`, `GF-PCGODOT/.../flow_nodes_io.gd:827`).

**Apply to the 16 legacy styles + the branched template.** Use a text edit, not `ResourceSaver`, which would
reformat the files. Save the script as `artifacts/stylelab/bind_room_filters.py` next to `validate_graphs.py`
(`*.py` and `artifacts/*` are export-excluded). The script is idempotent, skips graphs with no room filter
(all generated `stop_*` graphs), and asserts the invariant that `bind_room_filter` relied on:

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

Expected output: `17 graph(s) updated`. None of these files is in `generated_manifest.json`, so the generator
leaves them alone. Then run `python artifacts/stylelab/validate_graphs.py <files>`. Fix its hard-coded
`STYLES` Windows path (`:3`) first, or pass paths.

**Code changes (same commit):**

| File:line | Before | After |
|---|---|---|
| `DungeonLevelBuilder.gd:1041-1050` | comment + `var graph = ResourceLoader.load(a.graph_path, "", ResourceLoader.CACHE_MODE_IGNORE)` … comment + `BLRoomStyleRuntime.bind_room_filter(graph, a.room_id)` | `var graph := load(a.graph_path) as FlowGraphResource`. The binding reads `room_id` from the params already passed at `:1069` |
| `DungeonLevelBuilder.gd:7125-7128` | comment "Uncached load: bind_room_filter mutates" + `CACHE_MODE_IGNORE` load | `load(graph_path) as FlowGraphResource` |
| `DungeonLevelBuilder.gd:7595-7598` | comment + `bind_room_filter(style_graph, room_idx)` | delete, including the "callers should load an uncached copy" note |
| `GameController.gd:1799-1800` | comment + `ResourceLoader.load(graph_path, "", ResourceLoader.CACHE_MODE_IGNORE)` | `load(graph_path)` |
| `BlackLanternStyleLab.gd:731-732` (site mode) | `CACHE_MODE_IGNORE` + `runtime.bind_room_filter` | `load(path)`, no bind |
| `tools/graph_gen/style_snapshot.gd:68-69` | `CACHE_MODE_IGNORE` + `BLRuntime.bind_room_filter` | `load(...)`, and call `bind_room_filter` only `if BLRuntime.has_method("bind_room_filter")`, so the same tool still runs against the pre-Step-3 baseline |
| `BLRoomStyleRuntime.gd:9-28` | `bind_room_filter` | delete |
| `BLRoomStyleRuntime.gd:119-121` | `ctx.runtime_params = context.director_params.duplicate(true)` | also set `ctx.runtime_params["room_id"] = context.room_id` and `["style_seed"] = context.style_seed` (Step 4 moves this into `params`). **Fixes Summary finding 4:** the restyle path now builds the StyleContext for the right room |
| `graphs/styles/ROOM_STYLE_AUTHORING_SPEC.md:34, 166-167, 209-212` | room_id=1 guidance; `CACHE_MODE_IGNORE` verification snippet; "only walks the TOP-LEVEL graph" | document the `$room_id` binding. Plain `load()` is fine now, and a bound filter works inside a subgraph |
| `docs/PCG_AUTHORING.md:19` | "bound to the room with `BLRoomStyleRuntime.bind_room_filter`", "~line 914" | binding; `_apply_room_style_graphs` is at `DungeonLevelBuilder.gd:1002` |

These keep `CACHE_MODE_IGNORE`, because they read or duplicate a file rather than working around bindings:
`BlackLanternStyleLab.gd:466` (template duplicated into a new file) and `:954, :967` (the zone probe reads the
wrapper and family from disk).

Verification: V-boot. V-snapshot against `post_rebaseline`: **0 changed**. A cached graph shared across rooms
must place exactly what the per-room uncached copies placed. Run the snapshot twice in one process if you
want to prove reuse. The optional `restyle/*` oracle case **changes** (room-id fix, expected). Check that
`grep -rn "CACHE_MODE_IGNORE\|bind_room_filter" scripts tools` finds only
`BlackLanternStyleLab.gd:466, 954, 967` and the guarded `style_snapshot.gd` call. In-game, trigger a building
restyle and check the log line `Building restyled unrevealed room N -> …` (`GameController.gd:1808`).

Separate follow-up ticket for Summary finding 4 (restyled props are never spawned): the spawn loop at
`DungeonLevelBuilder.gd:7616-7617` accepts only `flow_style`, but graph props carry `flow_graph`, and the
snapshot keeps the original room's props, which occupy cells. Out of scope for the migration. Keep it in its
own commit so snapshot diffs stay attributable.

### Step 4 — `FlowNodeIO.evaluate` instead of hand-built contexts; seed moves out of `eval_id` (d)

*Needs: P0 §2–§3 (`FlowNodeIO.evaluate`, `make_context`, `ctx.seed`, owner-less evaluation), landed in `fbc48a5`.*

P0 API used, quoted from `RUNTIME_API_P0.md` §3:
`static func evaluate(graph : FlowGraphResource, inputs : Dictionary = {}, seed : int = 0, params : Dictionary = {}, owner : Node3D = null) -> Dictionary`
(as implemented it also takes a trailing `overrides` Dictionary; see "Implemented: deviations").
"`evaluate_graph` must work with `parent_ctx.owner == null`". "`eval_id` : evaluation counter again; never a
seed". "`runtime_params` … always contains `"seed"` mirrored from `ctx.seed`".

**4a. Parity migration (no output change).**

`DungeonLevelBuilder.gd:930-966` (master path, off by default), after:

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

This deletes the throwaway root (`:935-938, :954`), the hand-built ctx (`:940-945`) and the
`load("…flow_data.gd")` indirection. It also removes one `no graph resource assigned` warning per floor.

`DungeonLevelBuilder.gd:1055-1082` inside `_apply_room_style_graphs`, after:

```gdscript
		FlowNodeIO.evaluate(graph, {"FloorData": _floor_data_input(floor_data)}, 0,
				{"room_id": a.room_id, "style_seed": a.style_seed})
```

`seed = 0` **on purpose**: see 4b. Delete `:1024-1029` and the temp root (`:1056-1060`, `:1082`). Keep the
props-written count and its warning (`:1078-1096`). `_floor_data_input` is the existing inline wrap
(`:1062-1064`) until Step 5 replaces it with `FlowData.Data.scalar`. The outputs Dictionary is still only
checked with `is_empty()` (`:1092`). Read `FlowNodeIO.last_errors` there as well, so a failing node names
itself in the warning (Feedback F17, now landed).

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

`BlackLanternStyleLab.gd:1198-1225`, after:

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

Delete `_style_graph_node` (`:1219-1225`), `FlowGraphNode3DScript` (`:15`) and the `StyleGraphUnderTest`
child from `scenes/BlackLanternStyleLab.tscn` if it was saved there. The Style Lab's other two evaluations
get the same one-line change: site mode (`:733-741`, with `a.room_id`/`a.style_seed`) and the zone overlay
(`:886-893`, params `{room_id: rid, style_seed: rid}`, seed 0).

`OverworldRoadFlowAdapter.gd:256-287` (road, M26): replace the temp owner and hand ctx with
`FlowNodeIO.evaluate(graph_res, inputs, 0, {"dressing_density": density, "dressing_seed": dressing_seed})`.
Use seed 0: the road graph seeds itself from its `DressingSeed` input through `mutate_seed`, so a graph seed
would change every roadside pick. `tools/graph_gen/style_snapshot.gd:70-81` and
`tools/graph_gen/bake_surfaces.gd:209-215` follow the same pattern. The snapshot must mirror the game
exactly, so change it in the same commit as `_apply_room_style_graphs`. The bake keeps an owner, because
`scan_meshes` needs one: pass it as `owner`.

`bl_*` seed reads: in `BLFlowSeed.graph_seed` (Step 2a.4) drop the `eval_id` fallback, so the helper returns
`ctx.seed`. Afterwards `grep -rn "eval_id" scripts/ tools/ --exclude-dir=pcg_golden` must be empty. The oracle
keeps setting `eval_id` on purpose, so it still runs against older baselines.

**Why the master nodes read the raw `ctx.seed` and not `effective_seed()`.** P0 defines
`effective_seed = hash([ctx.seed, settings.random_seed]) & 0x7fffffff` when `ctx.seed != 0`. If
`bl_building_mass` / `bl_zone_carver` / `bl_room_splitter` / `bl_tactical_decorator` switched to it, **every
floor for every `level_seed` would change**. That breaks reproduction of the recorded acceptance and AI runs
(`artifacts/ai_playtests/black_lantern_seed_424242/`, `docs/REPORT_LOOP_8.md`). It buys nothing, because
these stages already decorrelate with fixed offsets (+101 / +211 / +307). `effective_seed()` is the right
call for any **new** BL node that wants a per-node stream, and for the parked nodes if they come back.

Verification: V-boot, plus the log no longer shows `FlowGraphNode3D: no graph resource assigned` (M3 and
M4 temp roots). V-snapshot: **0 changed** against the Step-3 baseline (style cases, because `seed = 0` and
`style_seed` still travels in params). V-road: identical. Optional oracle `master/*` identical, because
`ctx.seed == eval_id`. Check that
`grep -rn "FlowGraphNode3D\|EvaluationContext.new" scripts/ tools/ --exclude-dir=pcg_golden` is empty,
apart from the bake's owner node.

**4b. Opt-in: give style graphs a real seed (design decision, separate PR).**

BL took `980dc82` in `da590041` because floor jitter repeated identically in every room. Its per-point seeding
(seed stream → position hash → index), plus the kit's `seed = hash(position)`, gives per-*position* variety,
so rooms of identical shape at different places already differ. 4b adds per-*floor* and per-*style*
variety on top: the same room geometry styles differently on a different floor seed. Note that the kit's
picks read the `seed` **stream** first. A graph seed changes them only through `effective_seed()` on the
nodes (`select_points`, `match_and_set`, `attribute_random` XOR the node seed into the stream value).

Today a style graph's layout depends only on room geometry. Stock randomness is keyed on each node's saved
`random_seed` and on point positions. The `style_seed` that `RoomStyleAssignment.compute_seed`
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
  (`RoomStyleRegistry.gd:330`), restyle `int(_rng.seed) + room_idx * 131` (`DungeonLevelBuilder.gd:7601`),
  and Style Lab `compute_seed(generation_seed, 1, style_id)` (`BlackLanternStyleLab.gd:1214-1216`). Recommended:
  the restyle path uses `RoomStyleAssignment.compute_seed(int(_rng.seed), room_idx, graph_path.get_file().get_basename())`.
- Run a designer review at 3+ seeds per style. Re-capture the snapshot. The Style Lab "Next Seed"
  button starts showing real variation.

### Step 5 — Replace wrap/unwrap helpers with `Data.scalar` / `Data.first` / `Data.container` / `Data.value_at` (e)

*Needs: P0 §6 (`fbc48a5`) and `Data.value_at` (`ddd0464`).*

P0 API used: `static func scalar(name : String, value, data_type : DataType = DataType.Invalid) -> Data`,
`func first(name : String, default = null)`, `func container(name : String)` (`RUNTIME_API_P0.md` §6), and
`Data.value_at(name, i, default)` (per-point read that honours broadcast). The sites that survive Step 1:

| Site | Replacement |
|---|---|
| `DungeonLevelBuilder.gd:1333-1339` `_floor_data_from_flow_data` | `d.first("FloorData") as FloorData if d else null` (inline, delete the function) |
| `DungeonLevelBuilder.gd:1341-1347` `_string_from_flow_data` | `str(d.first(name, "")) if d else ""` |
| Inline FloorData wraps: `DungeonLevelBuilder.gd:1062-1064`, `BlackLanternStyleLab.gd:733-735, 886-888, 1202-1204`, `tools/graph_gen/style_snapshot.gd:72-74` | `FlowData.Data.scalar("FloorData", floor_data)` |
| `BLRoomStyleRuntime.gd:396-402` `_resource_data` | `FlowData.Data.scalar(name, res, FlowData.DataType.Resource)`. **Careful:** today a `null` resource gives an **empty** stream. Keep that with `if res == null: return FlowData.Data.new()` |
| `BLRoomStyleRuntime.gd:404-408` `_int_data` | `FlowData.Data.scalar(name, value, FlowData.DataType.Int)` |
| `BLRoomStyleRuntime.gd:133-138` (in `spec_from_outputs`) | `var value = data.first(output_name, data.first("StyleSpec"))` |
| `scripts/pcg_nodes/*`: `_floor_data_from_input` ×8 (`bl_floor_data_contract_points:54`, `bl_floor_data_to_points:33`, `bl_floor_data_to_style_context:77`, `bl_points_to_floor_data_props:349`, `bl_room_splitter:34`, `bl_tactical_decorator:31`, `bl_validate_floor_data:91`, `bl_zone_carver:32`) | one static in `res://scripts/flow/BLFlowIO.gd`: `static func floor_data_in(node: FlowNodeBase, port := 0) -> FloorData` → `var d = node.get_input(port); return d.first("FloorData") as FloorData if d else null` (the caller keeps its own `setError`) |
| `_floor_data_resource` ×5 (`bl_building_mass:43`, `bl_room_splitter:48`, `bl_tactical_decorator:45`, `bl_validate_floor_data:105`, `bl_zone_carver:46`), `_wrap_floor_data` (`bl_points_to_floor_data_props:359`) | `FlowData.Data.scalar("FloorData", floor_data)` |
| `_resource_data`/`_int_data` in `bl_floor_data_to_style_context:86-97` | `scalar(...)` |
| `_string_data` in `bl_validate_floor_data:112` | `FlowData.Data.scalar(name, value)` |
| Per-point readers `BLRoomStyleRuntime.gd:627-671`, `bl_points_to_floor_data_props.gd:390-448` | `data.value_at(name, i, default)` (`ddd0464`). This retires the `index if size > 1 else 0` copies (Feedback F12, landed) |
| Road input builders `OverworldRoadFlowAdapter.gd` (`make_spline_data`, `make_socket_data`, `make_ribbon_data`) and the raw scalars `IN_DENSITY`/`IN_SEED` (`:283-284`) | keep the multi-stream builders; wrap the two scalars with `Data.scalar` so the input feed never has to guess a type |

Do not put `BLFlowIO.gd` in `scripts/pcg_nodes/`: the editor scans that directory for nodes.

Verification: V-boot. V-snapshot 0 changed, V-road identical (pure refactor).

### Step 5b — Delete node-defect workarounds now that the upstream fixes have landed

*Needs: the release (`ee662ff`, `ddd0464`, `897d7a2`). Order: sync (Step 2) → re-bake → re-run the generator
→ delete. One BL commit per row.*

Procedure per row (`FLOW_UPSTREAM_SYNC.md` §4 steps 4–5):
1. **Re-bake** `tools/graph_gen/bake_surfaces.tscn`. `graphs/styles/kit/surface_points.json` must be
   byte-identical, and the log must read `normals as sampled` (`bake_surfaces.gd:187`).
2. **Re-run the generator** `tools/graph_gen/gen_room_families.tscn`. `_has_bindings` turns true
   (`gen_room_families.gd:73`), so the kit's `select_points.ratio` and `copy.num_copies` wires become
   `bindings`. The manifest records the new md5s. It must name **no** hand-edited graph (§2.3: none today).
   V-snapshot: **0 changed** (a binding resolves the value the wire carried).
3. Delete the workaround in a **separate** commit, then V-snapshot again. "0 changed" is expected unless the
   row says otherwise.

| Workaround (company `file:line`) | Upstream fix on `897d7a2` | Deletable on `897d7a2`? | Output effect of deleting |
|---|---|---|---|
| `sample_mesh` normal direction: `bake_surfaces.gd:110-121` measures whether sampled normals point in or out and flips (`flip`, `:120`); log `:187` | Outward normals (`ee662ff`) | **Keep** (team rule). It measures instead of assuming, so it is right on both addons. Optionally hard-code `flip = 1.0` once a re-bake logs `normals as sampled` for all 45 pieces | None: the bake output must be byte-identical |
| `remove_attribute` keep-only before `merge` | `merge` registers new streams first (`ee662ff`) | **Already gone**: 0 `remove_attribute` nodes in `graphs/**` on `05e473af` (`FLOW_UPSTREAM_SYNC.md:30`, "none left since `sg_kit_dress_room`") | — |
| `seed = hash(position)` before every pick: `gen_room_families.gd:2414` (`_kit_pick` `pk_seed`), `:2476` (`_kit_clusters` `*sd`); 10 `expression` nodes in `sg_kit_arrange`/`on_tops`/`walls`/`floor` | `match_and_set` seeds by position without a seed stream (`ddd0464`) | **Yes, optional. Recommendation: keep.** It also feeds `select_points` (`pk_fill`) and `attribute_random` (`pk_r`), which read the stream first | If deleted: every kit pick, fill and turn changes (upstream's position hash ≠ `hash(position)`). Designer review + new snapshot baseline |
| LinearCopies ×N + key expression + `match_and_set` to carry a piece's places onto points: `gen_room_families.gd:2504-2531` (`_kit_items`: `on_copy` `:2510`, `on_key` `:2512`, `on_tbl`/`on_match` `:2513-2515`), in `sg_kit_arrange` and `sg_kit_on_tops` | `copy` `attribute_inheritance` (`ee662ff`) | **Optional rebuild, not a drop-in.** It needs a per-prefab target table for `copy` SourceToTargets/TargetFirst. Rebuild only if it reads simpler (`FLOW_UPSTREAM_SYNC.md:32`) | Must be snapshot-identical. If not, check stream order and inherited-name collisions |
| Two LinearCopies + two expressions to subdivide a cell: `gen_room_families.gd:2381-2395` (`sg_kit_subgrid`: `sg_i` `:2385`, `sg_j` `:2386`, `sg_u`/`sg_v` `:2387-2388`) | `sample_points` `inherit_attributes` (`ee662ff`) | **Optional.** A uniform-grid `sample_points` must put the n×n places exactly at `(i+0.5)/n·2−1` in the wall frame. Otherwise positions move | Must be snapshot-identical; any diff means the grid is not the same |
| `point_offsets` column blanking: 64 nodes in 19 graphs set `"parent_index_attribute": ""` and `"offset_index_attribute": ""` (e.g. `sg_kit_on_tops.tres:963`, `supply_kitchen_island.tres:821`); generator `gen_room_families.gd:2471, 3192` | None: upstream still writes the columns by default (`ee662ff` documents it) | **Keep.** Not a defect workaround | Deleting would add columns |
| Non-indexed meshes indexed in memory: `bake_surfaces.gd:103` (call), `:230-250` (`_ensure_indexed`, `SurfaceTool.create_from` + `index()`) | `sample_mesh` reads a null `ARRAY_INDEX` untyped (`897d7a2`, `GF-PCGODOT/.../nodes/sample_mesh.gd:16-20`) | **Yes, delete.** `flow_upstream_status.sh` §3 reports it absorbed | Expected none: re-bake and diff `surface_points.json`. If it differs, `index()` reordered triangles; keep the helper and report it |
| Wires for Expression `args`: `pk_slot` `args.theme` ×4 (`gen_room_families.gd:2417`), `sg_u`/`sg_v` `args.n` ×2 (`:2394-2395`). `_bind` keeps a wire when `_is_setting_property` is false (`:2319-2345`, comment `:2324-2325`) | Bindings reach Dictionary entries; on an Expression a bare `args` key binds (`897d7a2`, DEPRECATIONS `897d7a2`; `GF-PCGODOT/.../flow_nodes_io.gd:819-820, 934`) | **Yes, after a generator change.** In `_bind`, when the template is `expression` and `setting` is a key of `settings["args"]`, write `bindings[setting] = <param>` like a property. Gate it on the release version, not on `_has_bindings` (`9417d63` had bindings but not args) | None: the binding resolves the value the wire carried. V-snapshot 0 changed |
| `_param_port` instances node scripts to compute setting-port numbers: `gen_room_families.gd:2303-2316`, used by `_bind`'s wire branch `:2330-2334` | `NodeSettings.bindings` (`9417d63`) | **Yes, once the Expression-args row lands.** After the sync, `_bind` already emits bindings for real properties (`:2321-2329`), so only the args wires still reach `_param_port`. Then delete it. `_is_setting_property` (`:2339-2345`) still instances a node to read its settings class (Feedback F21) | None |
| Four palette files, one per kit, and constant columns kept out of them (`PALETTE_FILE` `gen_room_families.gd:1944`; `pk_kind`/`pk_vo` `:2427-2428`) | `load_pcg_data_asset`: bindable `asset_path`, parse cache (`ee662ff`) | **Optional.** The cache alone removes the per-load parse (the team measured about 21 ms a room) | None |
| Kit ranks written as Float to avoid a retype (`gen_room_families.gd:366, 553, 600`, commit `0cdd9492`) | `expression` keeps an existing numeric stream's type (`ee662ff`) | **Keep.** Correct on both addons | — |
| `match_and_set` string-key normalisation | Numeric-aware keys (`ee662ff`) | **None in tree.** Keys are built as strings (`on_key` `:2512`, `pk_slot` `:2415`) | — |
| Seed in `ctx.eval_id`, `bind_room_filter` + `CACHE_MODE_IGNORE` (M3, M4, M9–M11, M20, M20b, M26, M27) | `ctx.seed`, `evaluate`, bindings (`fbc48a5`, `9417d63`) | **Yes**: Steps 3–4 | Step 3: none; Step 4b only if a graph seed is set |

### Step 6 — Style Lab and dock: public API instead of duck typing (g)

*Needs: nothing new. BL's addon already has upstream's `_handles`/`_edit` (`addons/flow_nodes_editor/plugin.gd:276-279`,
from `1906c2b`, inside `cb064d0`). This step can start now.*

Opening a graph is Godot's public API. The Style Lab's site mode already uses it
(`BlackLanternStyleLab.gd:1082`):

```gdscript
# BlackLanternStyleLab.gd:519-540 → replaces open_graph_in_data_flow body; delete _find_flow_plugin (:543-558)
func open_graph_in_data_flow() -> void:
	if _active_graph == null:
		_load_active_style_graph()
	if _active_graph == null or not Engine.is_editor_hint():
		return
	EditorInterface.edit_resource(_active_graph)
```

Do the same in `addons/bl_style_lab_dock/style_lab_dock.gd:176-178` (`EditorInterface.edit_resource(graph)`)
and delete `_find_flow_dock` (`:181-198`). `EditorInterface` is fine here: both files are editor-only (the dock
is an EditorPlugin; the lab scene is export-excluded).

What the lab still needs that no public API provides (gaps → Feedback F1–F3):

1. Open a graph **with fixture inputs and params** (FloorData fixture, `room_id = 1`, `style_seed`, seed), so
   the dock preview matches the lab instead of `bl_floor_data_to_style_context`'s cold-preview fixture
   (`:32-45`). A declared `in_params` default now feeds bindings in the dock (`ddd0464`). That covers
   scalar knobs, but not a FloorData fixture.
2. A signal when the dock **saves** or edits a graph. The dock saves through `ResourceSaver.save`
   (`GF-PCGODOT/.../flow_editor.gd:1141`), so `EditorPlugin.resource_saved` does not fire. **Stopgap:** in the
   existing 1.5 s poll timer (`style_lab_dock.gd:46-50`), compare
   `FileAccess.get_modified_time(_active_graph.resource_path)`. A dock save of a **generated** graph also
   makes it hand-edited for the generator (manifest md5), which is the intended behaviour (`954166a2`).
3. A way to run the graph from the dock with a chosen seed ("Run with…", review §3 P2).

Verification: in the editor, open `scenes/BlackLanternStyleLab.tscn`. "Open in Data Flow" opens the right
graph. Rebuild works for every registry style. Next Seed changes nothing until Step 4b, which is expected.
New Style creates, registers and opens a graph.

### Step 7 — FloorData-as-stream stays; what P1 would change (f)

**Keep** passing the `FloorData` Resource as a one-element `Resource` stream. It is typed (`DataType.Resource`
= 5, stable across versions), passes by reference at no cost, matches what every `bl_*` node expects, and
`Data.scalar/first` makes it one line at each end.

Be explicit about what it costs, because P1 will make these visible:

- The graph's real output is a **side effect**. In-game the outputs Dictionary is only checked with
  `is_empty()` (`DungeonLevelBuilder.gd:1081, 1092`). A P1 per-element output cache keyed on settings and
  input hash would treat `bl_points_to_floor_data_props` as cacheable and skip the mutation. BL needs a way
  to mark mutating nodes non-cacheable (Feedback F11).
- Correctness depends on the FloorData **link chain** serialising every writer **and every reader**: the
  dress pass reads props (`bl_floor_data_to_points` port 3) that the family just wrote. Keep that rule in
  `ROOM_STYLE_AUTHORING_SPEC.md` ("Chain FloorData through interps", `:164-165`). Never let two writers, or a
  writer and a props reader, run in parallel branches.

What the P1 **group-by loop** would enable. Today's per-room loop is GDScript (`_apply_room_style_graphs`,
`DungeonLevelBuilder.gd:1032-1102`): registry pick → clear → evaluate → stamp. With `loop` + `iterate_by =
"room_id"` + per-iteration `runtime_params` + compiled-subgraph reuse, a single "style floor" graph could
partition the floor's points by room and run each room's subgraph. The `$room_id` binding from Step 3 would
resolve per iteration unchanged. Three things are missing before BL can move the loop into the graph:

- the **subgraph must be chosen per iteration** from a partition attribute, because the registry picks a
  different graph per room (`RoomStyleRegistry.find_best_match`, `:54`) (Feedback F13);
- iterations must run **serially in sorted key order**, because rooms share `FloorData.cover_cells`;
- the registry match itself (tags, `min_room_cells`, priority, archetypes) would need a `bl_assign_room_styles`
  node writing `@data.style_graph`.

Until those exist, keep the GDScript loop.

**Performance in the meantime.** P0 does not reduce instancing cost. The dress pass is one
`sg_kit_dress_room` node per indoor room, but inside it runs four kit subgraphs plus `sg_kit_subgrid` twice,
all re-instanced per call. BL-side options, each guarded by V-snapshot (placement **and** ms):

- **Run the dress pass once per stop instead of once per room.** Kit output points carry `room_id`, and
  `bl_points_to_floor_data_props` writes each prop into the room named by its per-point `room_id`
  (`bl_points_to_floor_data_props.gd:72, 142, 305`). Preconditions: kit logic is room-local by construction
  (filters keyed on per-point attributes), every room's family has run before the pass (it reads their
  props), and the per-room clear policy (`_clear_room_style_domains`) runs for all styled rooms first.
- **Cache the tables.** `load_pcg_data_asset` now caches parsed JSON by path + mtime (`ee662ff`). Nothing to
  do beyond the sync.
- Do not trade correctness for speed. The FloorData chain must stay serial (above).

### Step 8 — Grid attribute: `bl_sync_grid_cell` and the hand-kept cell streams (i) — **not this round**

`bl_sync_grid_cell` is already gone in Step 1: no graph used it. BL still maintains grid semantics by hand in
several places, and they disagree with each other:

- producers: `bl_floor_data_to_points` and `bl_style_context_points` write `grid_cell` / `cell_x` /
  `cell_y` / `room_id`. `BLRoomStyleRuntime._point_data_for_context` writes the same (`:419-503`);
- consumers: the `expression` nodes use `posmod(cell_x|cell_y, N)` (legacy styles). The interpreter derives the
  cell as `floor(pos / tile)` (**min-corner**, `bl_points_to_floor_data_props.gd:156-157`), except for
  `free_place` points, which keep their own cell (`:154-159`). `BLRoomStyleRuntime._cell_from_point` uses
  `round(pos / 2.0)` (`:623-625`). The two conventions disagree. This is the "cell-min corner pushes props out
  on N/W walls" issue that `STYLE_LAB_AUDIT.md` worked around. The zoned families use the entry frame
  (`entry_depth`, `across_ratio`) instead of raw cells, so they depend less on it.

When the P2 grid attribute lands (canonical `cell` + `cell_size` data attr, `snap_to_grid.anchor`,
`transform`/`point_offsets`/`copy` keeping `cell` in sync):

1. Producers emit the canonical `cell` and `@data.cell_size = 2.0` instead of `grid_cell` / `cell_x` /
   `cell_y`.
2. The interpreter and `_cell_from_point` read `cell`. Pick **one** anchor and document it. Snapshot first:
   changing the anchor moves props.
3. The expressions become `posmod(cell.x, N)` (or the P2 equivalent). Update
   `ROOM_STYLE_AUTHORING_SPEC.md:40-48, 76-80, 158-160`.
4. Remove the `grid_cell` / `cell_x` / `cell_y` registrations after one release with both written.

### Step 9 — Documentation refresh

| Doc | Stale statement | Fix |
|---|---|---|
| `docs/PCG_AUTHORING.md:3` | "Flow Nodes addon is re-baselined on upstream" | state the release now vendored and point at this plan |
| `docs/PCG_AUTHORING.md:9` | `DungeonLevelBuilder.gd:643`; the master graph described as "the active floor" | `:930`, and say it runs only with `use_hotel_generation` off (`:36, :541, :570`) |
| `docs/PCG_AUTHORING.md:19` | Already corrected on `company` ("the old note … is stale"), but cites `_apply_room_style_graphs()` "~line 914" and `bind_room_filter` | `:1002`; `$room_id` binding (Step 3) |
| `docs/PCG_AUTHORING.md:101-103` | native lib "Windows-editor only"; an export needs a rebuild | Windows template debug/release already ship (vendored `bin/` = `cb064d0`); the release adds Linux template debug; macOS release and Linux release are still missing |
| `docs/PCG_AUTHORING.md` (new §) | — | node directory `res://scripts/pcg_nodes`, `category`/`hue`, `$room_id` binding, the seed rules from Step 4 |
| `graphs/styles/ROOM_STYLE_AUTHORING_SPEC.md:34, 166-167, 209-212` | room_id=1 guidance, `CACHE_MODE_IGNORE` snippet, "`bind_room_filter` only walks the TOP-LEVEL graph" | binding, plain `load()`, bound filters work in subgraphs |
| `docs/FLOW_UPSTREAM_SYNC.md` §1, §2, §4.3 | statuses read against `ddd0464`; "copy upstream over ours"; keep every `*.uid` | all absorbed on `897d7a2`; delete-then-copy; take upstream's `flow_graph_edit.gd.uid`; note the `sample_spline` semantic difference; `project_points` moved to `scripts/pcg_nodes` |
| `tools/graph_gen/flow_upstream_status.sh:10-11, 16, 25` | default branch order checks `origin/main`; `SYNCED=cb064d0`; the addon path | after the sync: `SYNCED=<release>`; the review/release branch first; `bl_*`/`project_points` checks point at `scripts/pcg_nodes` |
| `artifacts/stylelab/validate_graphs.py:3` | hard-coded `C:\Users\mattk\...` path | derive the path from `__file__` |
| `artifacts/loop1_audit_digest.md:147, 160, 167, 199, 217` | exports lose native; root `bin/` duplicates; style path "mostly-unused"; director params inert; unused nodes | mark as resolved with commit refs (147 was resolved by the June sync) |

---

## 4. Risk register

| ID | Risk | Likelihood / impact | Mitigation / detection |
|---|---|---|---|
| R1 | **Leak fix.** BL already frees node instances (`flow_nodes_io.gd:719`, called `:1024`, upstream code at `cb064d0`). Not a re-baseline delta | None | Keep the orphan-count check as a regression check: `Performance.OBJECT_ORPHAN_NODE_COUNT` flat across two consecutive stop builds |
| R2 | **Execution order.** Unchanged since `cb064d0` (§1.4). It matters more now that 23 graphs read props (`bl_floor_data_to_points` port 3) that an earlier writer placed | Low / high | Chain rule (Step 7). V-snapshot catches a reordering as changed placement |
| R3 | **Native lib on export platforms.** Keep every `ClassDB.class_exists` guard (`ZoneCarver.gd:251`, `RoomSubdivider.gd:1078`, `bl_style_context_points.gd:163`). Windows exports already load native (vendored `bin/` = `cb064d0`). The release adds a Linux template_debug `.so`, and macOS release / Linux release are still missing. Native L2 and the GDScript fallback can pick different pairs | Low / medium | Export smoke test on each shipped platform |
| R4 | **Determinism across the seed change.** `eval_id` stops being a seed (`DEPRECATIONS.md` §2). Hand-built contexts (M3, M4, M20, M20b, M26, M27) would silently lose the seed if any `bl_*` node still read `eval_id` after Step 4 | Medium if steps are skipped / high (floors change) | `BLFlowSeed` transitional helper (Step 2a.4). Raw `ctx.seed` for master stages, not `effective_seed()`. `grep eval_id scripts/ tools/` empty after Step 4. Step 4b handled as a design change |
| R5 | ~~Export exclusion breaks style nodes~~: **fixed on `company`** (Summary 3). Residual: `tools/*` and `output/*` are not export-excluded (M25), so generator and probe scripts ship; `McpProbe` names absent test suites | Low / low | Step 1.5. Acceptance grep for `scripts/testing` |
| R6 | **Registry script lookup in exported builds.** Upstream resolves `res://scripts/pcg_nodes/<template>.gd` with `ResourceLoader.exists(path, "Script")` (`flow_node_registry.gd` `_find_template_script`, `:144`). Exported scripts are remapped | Low / high | Export smoke test after Step 2. If it fails, report upstream (Feedback F15) |
| R7 | **Cached graphs shared across rooms** once `CACHE_MODE_IGNORE` goes. A node that writes into an Array/Dictionary setting it got by reference from `graph.data` would leak state between rooms. The kit reuses the same subgraph resource many times per stop | Low / medium | V-snapshot after Step 3 (0 changed). P0 promises graph resources stay immutable |
| R8 | **Restyle behaviour changes when the room-id bug is fixed** (Step 3) | Certain / low (restyle is currently inert) | Separate commit, optional `restyle/*` oracle case, follow-up ticket for spawning |
| R9 | **Owner-less `@tool` evaluation** now reports errors (`ctx.preview` is set only by the dock, `ddd0464`). Every BL evaluation passes an owner today. The owner-less road/lab calls after Step 4 run outside the editor or in the lab | Low / low | `FlowNodeIO.last_errors` in the style-loop warning (Step 4a) |
| R10 | **Release not yet cut.** The P0 round is on the review branch, not upstream `main`, and `plugin.cfg` is still `1.0` | Medium / low | Re-baseline on the tag. Re-run `flow_upstream_status.sh` against it |
| R11 | **Road drift from `size→bounds`** (Table C, C1). The snapshot does not cover the road | Certain without the legacy flag / medium | `legacy_scale_from_extent` in the re-baseline commit (Step 2a.6). Road review before removing it |
| R12 | **Stale game docs** mislead the next agent or designer (Step 9 table) | High / medium | Step 9 in the same release |
| R13 | **Editor churn and the manifest.** The first editor load rewrites `.uid`/`.import` files. **Saving any generated graph from the dock** (a v2 migration makes it dirty) changes its md5, and the generator then skips it as hand-edited (`gen_room_families.gd:167-168`) | Likely / medium | Commit the churn in 2a without saving generated graphs. Do the v2 bump through the generator (Step 2d). After each generator run, check the list of skipped graphs it prints at the end |
| R14 | **Colour for `bl_*` nodes** | Resolved upstream: `meta_node.hue`/`color` (`ddd0464`) | Step 2a.3 |
| R15 | **Instancing cost** (§2.4): +0.7–1.0 s per stop from the kit. Neither P0 nor the leak fix helps; re-baselining may add cost (binding resolution, `last_errors`) | Certain / medium (load-time hitch per stop) | Compare `style_snapshot` ms per stop at every step; fail review above +10%. Step 7 mitigations. Feedback F20 |
| R16 | **Setting wires lost on re-baseline**: the local `args_port` patch is dropped for `_restore_wired_param_ports` | Low / high (kit fill ratios, subgrid n and road spacing silently revert to saved values) | G1 (12 kit wires in every indoor room) and G2 (6 road wires). After the generator re-run the kit wires become bindings; the Expression `args` wires remain until Step 5b |
| R17 | **Snapshot blind spots.** `style_snapshot` covers 7 stops × 2 seeds through `StopFloorDataBuilder` only. Not covered: hotel floors (JC packer), the master graph, the road, the restyle path, and non-hashed prop fields (cover type, light state, reveal). It mirrors the production loop rather than calling it (`style_snapshot.gd:58-81` vs `DungeonLevelBuilder.gd:1032-1102`). It sets no exit code | Medium / medium | V-road + suites. Optional Appendix A cases for master/restyle/road. Update the snapshot in lockstep with Steps 3–4 (M27). Grep its final `COMPARE` line |
| R18 | **Sync procedure leaves stale files.** "Copy upstream over ours" keeps files upstream deleted (`custom_grid_shader.gdshader`, `bin/*.exp`/`*.lib`) and the mismatched `flow_graph_edit.gd.uid` | Certain / low | Delete-then-copy (Step 2a.5). Acceptance diff against the release is empty apart from `.uid` |

---

## 5. Effort and parallelism

| Step | Effort | Can start | Blocks |
|---|---|---|---|
| 0 Snapshot baseline (+ optional oracle cases) | 0.25 d (1 d with the oracle) | now | 2 |
| 1 Cleanup + export excludes + export smoke test | 0.5 d | now (after 0) | — |
| 2a Swap + move + setting + seed helper + road legacy flag | 0.5 d | release tag | 2b |
| 2b Compare (snapshot, road) + attribution if needed | 0.25–0.5 d | 2a | 2c |
| 2c Road decision (C1) | 0.25 d + road designer review | 2b | — |
| 2d/2e v2 bump through the generator + UI check | 0.25 d | 2c | — |
| 3 Bindings (17 hand graphs) + snapshot lockstep | 0.5 d | 2 | 4 |
| 4a Evaluate / seed parity (DLB, runtime, lab ×3, road, snapshot, bake) | 1 d | 3 | 4b, 5 |
| 4b Style seeds (optional) | 0.5 d + designer review 0.5–1 d | 4a | — |
| 5 Helpers + `value_at` | 1 d | 4a | — |
| 5b Re-bake, regenerate, workaround removal | 1–1.5 d (generator args-binding change 0.25 d) | 2 | — |
| 6 Style Lab | 0.5 d | now | — |
| 7 Perf mitigation (optional) | 1–2 d (single dress pass per stop) | 2 | — |
| 8 Grid attribute | 1–1.5 d | upstream P2 | — |
| 9 Docs (incl. `FLOW_UPSTREAM_SYNC.md`, status script) | 0.5 d | alongside each step | — |

**Total for this round (0–6 + 9, without 4b and 7): about 6–7 developer-days.** There is no designer review of
style layouts: the per-point seeding review already happened with `da590041`. The only review is the road
decision (C1).

Parallel streams, split by file ownership so they do not conflict:

- **Stream A (runtime glue):** Steps 3, 4 and the game-side part of 5. Owns `DungeonLevelBuilder.gd`,
  `BLRoomStyleRuntime.gd`, `GameController.gd`, `OverworldRoadFlowAdapter.gd`, the Style Lab's evaluation
  functions, and `tools/graph_gen/style_snapshot.gd` (it must move with the game path). Strictly sequential:
  3 → 4a → 5.
- **Stream B (nodes):** Step 1.2, the node part of Step 2a, and the node part of Step 5. Owns
  `scripts/pcg_nodes/*` and `scripts/flow/BLFlow*.gd`.
- **Stream C (editor):** Step 6. Owns the Style Lab open-graph code and `addons/bl_style_lab_dock/*`. Can run now.
- **Stream D (content and generators):** Step 2a.6, Step 2d, the binding script run, Step 5b. Owns
  `graphs/**`, `tools/graph_gen/gen_room_families.gd`, `bake_surfaces.gd`, `generated_manifest.json`.
- **Stream E (docs):** Step 9.

Step 0 must finish before Step 2a starts. The Step 2a swap is one commit touching A/B/D files, so it has one
owner.

---

## 6. Acceptance checklist

- [ ] `output/style_snapshot_before.json` committed (or its location recorded), captured on the current addon
      and reproducible (self-compare = `0 changed`).
- [ ] `flow_upstream_status.sh <checkout> <release>`: §2 and §3 all ABSORBED before the swap; after the swap, §4
      lists no framework file.
- [ ] After Step 2: **G1** snapshot `0 changed` on all 7 stops × 2 seeds; **G2** `OverworldRoadRegression`
      unchanged and the road digest identical with `legacy_scale_from_extent`. `style_snapshot_post_rebaseline.json`
      committed.
- [ ] After Steps 3, 4a, 5 and each 5b row: snapshot `0 changed` (except rows that say otherwise, with review
      notes). Optional `restyle/*` changes in Step 3 only (room-id fix, reviewed).
- [ ] After the generator re-run: no graph reported as hand-edited; the kit carries `bindings` for `ratio`,
      `num_copies` and (after the generator change) Expression `args`. No setting-wire `args_port` entries are left
      in generated graphs, and `_param_port` is deleted.
- [ ] Re-bake: `graphs/styles/kit/surface_points.json` byte-identical, log `normals as sampled`,
      `_ensure_indexed` deleted.
- [ ] V-boot on at least two stops: styled-room count printed, `graph wrote N props` per styled room, no
      `placed NOTHING`, `Failed to resolve node script`, `Input B not connected`, `Stream name conflict`, `registerStream`
      refusal, or `FlowGraphNode3D: no graph resource assigned`. `StopSiteRegression` 1145/0.
- [ ] `diff -rq <release>/demo/addons/flow_nodes_editor addons/flow_nodes_editor` lists only `.uid` files (and
      `.import`). No `bl_*`, `project_points*`, `custom_grid_shader*` or `bin/*.exp|*.lib` under `addons/`.
- [ ] `ProjectSettings` `flow_nodes/node_directories == ["res://scripts/pcg_nodes"]`. Each of the 13 `bl_*`
      nodes shows under "Black Lantern" in the add-node menu with its hue. No "invalid UID" boot warning.
- [ ] `grep -rn "CACHE_MODE_IGNORE" scripts tools` → only `BlackLanternStyleLab.gd:466, 954, 967`.
      `grep -rn --exclude-dir=pcg_golden "bind_room_filter\|EvaluationContext.new\|eval_id\|setResourceToEdit\|_find_flow_plugin\|_find_flow_dock" scripts tools addons/bl_style_lab_dock` → empty
      (the snapshot's guarded call goes once the pre-Step-3 baseline is retired).
      `grep -rn "res://addons/flow_nodes_editor/nodes/\|res://scripts/testing/" scripts/pcg_nodes scripts/flow` → empty.
- [ ] All 17 room-filter graphs carry `"bindings": {"max_value": "room_id", "min_value": "room_id"}`.
      `validate_graphs.py` is clean. All 125 graphs are `"version": 2`, and the generator writes 2.
- [ ] `export_presets.cfg:11` excludes `tools/*` and `output/*`. Windows export smoke test: a styled room has
      props, and the overworld road has dressing (R3, R5, R6).
- [ ] Data Flow dock usable in the bottom panel; `A` analyze, grid toggle and `E` data inspector work.
- [ ] Style Lab: Open in Data Flow uses `EditorInterface.edit_resource`. Rebuild works for all 85 registry
      entries. Site mode and the zone overlay run. New Style works.
- [ ] A runtime building restyle styles the **target** room (log `Building restyled unrevealed room N`), and
      the follow-up ticket for spawning is filed.
- [ ] Snapshot timing: per-stop graph ms no slower than the Step-0 capture (+10% tolerance). Record the
      numbers in the PR.
- [ ] Step 9 doc table done, including `FLOW_UPSTREAM_SYNC.md` and `flow_upstream_status.sh`.
      `BLACK_LANTERN_MIGRATION_PLAN.md` is referenced from `docs/PCG_AUTHORING.md`.

---

## 7. Feedback to the addon

Each item is a Black Lantern need, with the BL evidence. **Status on `897d7a2`:** resolved: F5 (`evaluate(..., overrides)`),
F6 (`owner : Node3D`), F7 in part (`registerStream` refuses wrongly typed canonical attributes, `ddd0464`;
a project schema such as `declare_attribute` is still open), F8 (`meta_node.hue`/`color`), F9 (DEPRECATIONS §2 rows),
F12 (`Data.value_at`), F16 (`ctx.preview`), F17 (`FlowNodeIO.last_errors`), F22 (DEPRECATIONS rows; legacy flags
exist for `match_and_set` and the size→bounds generators), F23 (tooltip, `ee662ff`). Partial: F21 (bindings, and
Expression `args` bindings in `897d7a2`; no static `param_port_index`). Open: F1–F4, F10, F11, F13–F15, F18–F20.

| # | Gap | BL evidence | Suggested shape |
|---|---|---|---|
| F1 | **Public editor API to open a graph with fixture inputs / params / seed.** `EditorInterface.edit_resource` opens by path only, and preview runs with no inputs | `BlackLanternStyleLab.gd:519-558`, `style_lab_dock.gd:157-198` duck-type `setResourceToEdit`. `bl_floor_data_to_style_context.gd:32-45` fabricates a fixture FloorData in cold preview because the dock cannot be given one | `FlowEditorPlugin.get_singleton().open_graph(res, owner := null, inputs := {}, params := {}, seed := 0)`, and/or per-graph `FlowGraphResource.preview_params` + `preview_inputs` (fixture resource paths) used by the dock |
| F2 | **Graph saved / edited signal** | The dock saves via `ResourceSaver.save` (`GF-PCGODOT/.../flow_editor.gd:1141`), so `EditorPlugin.resource_saved` does not fire and the lab needs a manual "Reload & Rebuild" | `signal graph_saved(resource)` / `graph_edited(resource)` on the plugin singleton, or `emit_changed()` after save |
| F3 | **"Run with…" in the dock** (seed, params, fixture) | Style Lab exists largely to do this (`docs/STYLE_LAB_AUDIT.md` method) | review §3 P2 panel |
| F4 | **Output discovery by role, not by name** | `BLRoomStyleRuntime.gd:514-538` routes outputs with `lower_name.contains("proppoints")`, and `:673-685` guesses prop kind from the output name | output node setting `tags : PackedStringArray` stamped on the emitted Data (P0 already carries tags through), plus `FlowNodeIO.outputs_with_tag(outputs, tag)`; or expose `graph.out_params` with declared types and a `role` field |
| F5 | **`FlowNodeIO.evaluate` has no `overrides` argument** | Overrides are only reachable through `FlowGraphNode3D` or a hand-built ctx, which P0 otherwise removes | `evaluate(graph, inputs, seed, params, owner, overrides := {})` |
| F6 | **`owner` type mismatch**: `make_context(owner : Node3D)` / `evaluate(owner : Node3D)` vs `EvaluationContext.owner : FlowGraphNode3D` | Style Lab (a `Node3D`) would pass itself | Type `owner` as `Node3D` everywhere, or document FlowGraphNode3D-only |
| F7 | **Schema enforcement for canonical attributes** | `medical_station.tres` registered `rotation` as Float `180.0`: 5 "Stream name conflict" warnings and broken orientation (`docs/STYLE_LAB_AUDIT.md:11`). `registerStream` only warns (`flow_data.gd` conflict warning) | `registerStream` / `add_attribute` refuse (setError) a wrong type for `position`/`rotation`/`size`/`seed`/`density`/`normal`/`bounds_*`. Plus a project schema: `FlowData.declare_attribute("room_id", DataType.Int)` checked in debug builds |
| F8 | **Colour for project categories** | "Black Lantern" is not in `CATEGORY_HUES` (vendored `node.gd:218`; upstream `CATEGORY_HUES`, `GF-PCGODOT/.../node.gd:353`), so 13 nodes get unrelated hash hues | `meta_node.hue` (or `color`) override, or a `flow_nodes/category_hues` project setting |
| F9 | **DEPRECATIONS §2 is missing semantic changes BL hit** | Table C: `noise` ValueCubic/SimplexSmooth mapping (`5a143f6`), `registerStream` honouring declared type (`cac340b`), `build_rotation_from_up` secondary axis (`5a143f6`), non-terminal subgraphs no longer roots (`b478c5e`), `output` real type (`c6b8e7b`), `__eval_depth` + child→parent `runtime_params` publishing (`bfa7e28`) | Add rows. Offer `legacy_value_noise` on `noise` like `legacy_scale_from_extent` |
| F10 | **Golden harness usable by games before they upgrade** | BL had to write its own oracle (Appendix A) because the harness needs the new API, and a `Resource` stream digest is meaningless without a project hook | Keep the harness core on `evaluate_graph` + `Data.streams` only; add `resource_digesters: {class_name: Callable}`, per-case fixtures/params/seeds, optional per-node intermediate digests for attribution, and a `meta` block (native lib present, OS) |
| F11 | **Declare side-effecting nodes** before P1 caching/threading | `bl_points_to_floor_data_props`, `bl_zone_carver`, `bl_room_splitter`, `bl_tactical_decorator` mutate the input `FloorData` in place | `meta_node.pure = false` (default true): never cached, never parallelised, always executed in link order |
| F12 | **Per-point typed accessor with broadcast** | 8 copies: `BLRoomStyleRuntime.gd:627-671`, `bl_points_to_floor_data_props.gd:390-448` | `Data.value_at(name, i, default)` and typed variants using `bcast_idx` |
| F13 | **P1 loop: per-iteration subgraph selection and ordering guarantees** | The registry picks a different graph per room (`DungeonLevelBuilder.gd:1002-1108`). Rooms share `cover_cells` | `loop.subgraph_attribute` (graph path from the partition's `@data`); documented serial, sorted-key iteration when any element is impure (F11) |
| F14 | **Optional output point-count badges** | Removed upstream (`63ad631`). Designers used them in the `58a9d3c`-era BL copy; gone from BL since the June sync | Editor setting "Show output counts" |
| F15 | **Registry lookup in exported builds** | BL will resolve 13 templates from `res://scripts/pcg_nodes` at runtime | A test that exports the demo and evaluates a graph using a project-directory node |
| F16 | **Preview mode should be explicit, not `owner == null`** | P0 makes owner-less runtime evaluation legal, but `require_input` and several nodes still treat `owner == null and Engine.is_editor_hint()` as "editor preview" (`GF-PCGODOT/.../node.gd:1032`), hiding errors in `@tool` callers like the Style Lab | `ctx.preview : bool`, set only by the editor |
| F17 | **Report node errors to runtime callers** | A failing style graph shows up in-game only as an empty room. `setError` is visible only in the editor | `FlowNodeIO.evaluate` returns or stores `last_errors : Array[{node, template, message}]` |
| F18 | **Release binaries**: macOS release, Linux release/editor | `PCG_AUTHORING.md:101-103`, Risk R3 | Commit the CI builds |
| F19 | **Prefixed override keys depend on `resource_path`** (`graph_basename`), which may be empty for `CACHE_MODE_IGNORE` loads | BL used IGNORE loads in 3 places until Step 3 | Document it, or key on the resource uid |
| F20 | **Compiled-graph cache shared across repeated `subgraph` calls within one evaluation and across rooms**, not only across `loop` iterations | Team measurements: 6–12 ms per 20–47-node subgraph instance, 0.2–0.5 ms per trivial node. `sg_kit_dress_room` runs four kit subgraphs (+ `sg_kit_subgrid` ×2) per indoor room; the kit added 0.7–1.0 s per stop (`0cdd9492`). `style_snapshot` records ms per room | P1 `FlowCompiledGraph` keyed by graph resource (+ version), reused by every `subgraph` node and every top-level `evaluate` in the process. Invalidate on graph save (F2) |
| F21 | **Name-based setting wires for script-authored graphs** | `gen_room_families.gd:2303-2316` `_param_port` instances node scripts to find port indices; `_is_setting_property` (`:2339-2345`) instances them again to tell a property from an Expression `args` key | `bindings` covers scalar knobs (landed in `9417d63`). Document it as the generator-facing API, and add `FlowNodeIO.param_port_index(template, property)` (static, no instancing) for the per-point case |
| F22 | **Every output-changing node fix must be in `DEPRECATIONS.md` §2**, with a legacy flag where cheap | The Step 5b fixes change output when a graph relies on the old behaviour (`match_and_set` RNG, `copy`/`sample_points` inheritance, `merge` column order, `point_offsets` defaults, `expression` typing) | One row per fix, with the commit. Legacy flags like `legacy_scale_from_extent` |
| F23 | **Document `add_attribute` with no input** yielding a one-point Data (schema row) | Kit graphs | README + node tooltip |

---

## Appendix A — Golden oracle (`res://scripts/tools/pcg_golden/`) — optional, secondary

**Superseded as the primary gate by `tools/graph_gen/style_snapshot.tscn`** (Step 0). Keep this oracle only for
what the snapshot does not reach: `master/*` (the master graph, off the default game path, Summary 7),
`restyle/*` (M10, where the Step-3 room-id fix shows up), and a `road/*` case for the overworld dressing (Table
C, C1). The `game/*` and `lab/*` cases below overlap with the snapshot. Drop them if the snapshot is enough.
`_game_case` goes through `_generate_flow_node_floor_data()`, i.e. the master path, not the hotel/stop path the
snapshot covers.

A `road/*` case is not written out here. It should call
`OverworldRoadFlowAdapter.evaluate_dressing(pts, pts, sockets, density, seed)` on the fixture that
`scripts/road/OverworldSliceRunner.gd:188-218` already builds, and digest `result["points"]` and
`result["furniture"]` with `canon()`.

`pcg_golden_capture.tscn`: a single `Node` with the script below. Run it as a **game** (not an EditorScript)
so autoloads exist and `DungeonLevelBuilder` (not `@tool`) executes.

```gdscript
# res://scripts/tools/pcg_golden/pcg_golden_capture.gd
extends Node
## PCG parity oracle for the PCGODOT migration. Only uses APIs that exist in BOTH the
## vendored addon (cb064d0-based) and the upgraded one, so the same file captures before and after.
## godot --headless --path . res://scripts/tools/pcg_golden/pcg_golden_capture.tscn -- --label=X [--compare=res://…json]

const SEEDS := [424242, 8001, 1, 77, 20260927]
const LAB_SEED := 8001
const LAB_SIZE := Vector2i(9, 8)
const REGISTRY_PATH := "res://resources/room_styles/registry.tres"
const EXTRA_GRAPHS := ["res://graphs/styles/objective_objective.tres", "res://graphs/styles/style_room_advanced.tres"]
const RESTYLE_GRAPHS := ["res://graphs/styles/cultist_ritual.tres", "res://graphs/styles/storage_warehouse.tres", "res://graphs/styles/workshop_maintenance.tres"]
const LabBuilder := preload("res://scripts/flow/BlackLanternStyleLabFloorDataBuilder.gd")
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
	# optional: run.call("road/<edge>", ...) cases through OverworldRoadFlowAdapter.evaluate_dressing (see above)
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
	fd.rooms[1]["props"] = []                       # mirror BlackLanternStyleLab.gd:592-597
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

Notes: `_compare` ignores `timing`; compare it by hand or with `jq`. `_game_case` uses a detached builder.
`_collect_director_style_params` then gets `get_tree() == null` and returns its defaults
(`DungeonLevelBuilder.gd:1298-1299`), and the temp roots it creates are freed with `dlb`. Refine `_compare`
into per-room diffs as needed. The JSON is readable enough to diff with `git diff` or `jq`.
