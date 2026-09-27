# Black Lantern Tactics: compatibility run of the PCGODOT addon at `897d7a2`

**Question.** Does the `flow_nodes_editor` addon on GF-PCGODOT branch `claude/pcg-system-review-4tpca9` (head
`897d7a2`) change what Black Lantern Tactics generates, compared with the copy the game vendors today?

**Answer.**

- **Rooms: no change.** Every stop and seed, every room and every prop comes out byte-identical. That covers
  the seven stops, the hotel stack, the `pcg_master_graph` floor and the regenerated kit graphs. The game's
  `seed = hash(position)` workaround hides upstream's one change to room randomness (`match_and_set` seeding,
  `c981656`). A bisection shows the change is live and that `legacy_global_rng` restores the old picks
  exactly (§4.3).
- **Overworld road: changed.** Upstream places slightly fewer road props: 3 to 12 fewer poles per edge and 1 to
  10 fewer trees, bushes or rocks per edge (1–3 of any one kind). Six of the seven road pieces measured differ. The cause is `03c2826`:
  `sample_spline` now writes `bounds_min`/`bounds_max`. `legacy_scale_from_extent` does **not** restore the old
  output, which contradicts both `DEPRECATIONS.md` and
  [BLACK_LANTERN_MIGRATION_PLAN.md](BLACK_LANTERN_MIGRATION_PLAN.md) §1.4 C1. Stripping the new bounds on two
  samplers (`pole_samples`, `forest_samples`) restores the road exactly (§4.2).
- **Errors.** The swap adds no parse or runtime errors. The full `HeadlessSuite` battery (which boots a real
  mission), `StopSiteRegression` and `OverworldRoadRegression` give identical results on both copies. No
  upstream-only `FlowNodeIO.last_errors` or `push_error` appeared (§3, §5).
- **Speed.** Upstream dresses rooms about 8–9 % faster. The `load_pcg_data_asset` parse cache accounts for all
  of that gain (≈ 25 ms per room). Without the cache, upstream would be about 3 % slower than the vendored
  copy (§6).

Run on 2026-09-27. Nothing was committed to either repository. All work was done in scratch worktrees.

---

## 1. Setup

| | |
|---|---|
| Game commit | Black Lantern Tactics `company` **`05e473af`** ("CHORE(tools): the snapshot tool's uid"). This run was first started on `f6f62ddf`; the base was moved to `05e473af` on request, and nothing from the `f6f62ddf` run is reported here. |
| Upstream addon | GF-PCGODOT `claude/pcg-system-review-4tpca9` @ **`897d7a2`**, `demo/addons/flow_nodes_editor` (working tree clean, equal to the commit) |
| Scratch copies | `git -C /home/user/black-lantern-tactics worktree add --detach <scratch>/bl_vendored 05e473af` and the same for `<scratch>/bl_upstream`. `<scratch>` = `/tmp/claude-0/-home-user-GF-PCGODOT/db793662-7f0b-5476-94ed-de027c967608/scratchpad` |
| Godot | **4.7.1.stable.official.a13da4feb** (`/usr/local/bin/godot47`) for every run. The project declares feature `4.7`. Godot 4.6 was not used. |
| Native library | The same `libflow.linux.template_debug.x86_64.so` (sha256 `bc847658fa66a757…`, built from GF-PCGODOT `native/src`) was copied into both copies, and `linux.x86_64 = "res://addons/flow_nodes_editor/bin/libflow.linux.template_debug.x86_64.so"` was added to `bin/flow.gdextension`. `addons/flow_nodes_editor/native/src` is **identical** in the vendored copy and upstream, so no separate vendored build was needed. Both runs report `ClassDB.class_exists("GDKdTree") == true` and `GDRTree == true`: native availability is the same on both sides. |
| Plugin version | `plugin.cfg` reads `version="1.0"` in both copies. Upstream's deprecation policy counts a release as a bump of this field, but none has been made. |

### 1.1 How the upstream copy was made

The copy followed the game's own `docs/FLOW_UPSTREAM_SYNC.md` §4. The tool scripts and paths are the game's own:

1. Ran `tools/graph_gen/flow_upstream_status.sh /home/user/GF-PCGODOT claude/pcg-system-review-4tpca9`. The full
   output is in Appendix A. All four §2 local patches and all four awaited §3 fixes read **ABSORBED**, so no
   local patch needed re-applying.
2. Copied upstream over the vendored addon, **excluding `*.uid`** and the `*.os` build objects:
   `(cd $UP && tar cf - --exclude='*.uid' --exclude='*.os' .) | (cd bl_upstream/addons/flow_nodes_editor && tar xf -)`.
   This kept §1 as the sync document requires: all 23 `nodes/bl_*.gd` + `_settings`, `nodes/project_points*`, every
   game `.uid`, and the game-only `custom_grid_shader.gdshader`. `plugin.gd` is upstream's; the game's differs from it
   only by upstream's added `ensure_project_setting()` calls. `flow_inspector.gd` and `custom_grid.gd` do not exist on
   this commit.
3. `godot47 --headless --path . --import` on both copies.
4. Regenerated the surface table and the kit graphs: `tools/graph_gen/bake_surfaces.tscn`, then
   `tools/graph_gen/gen_room_families.tscn`. For control, the same regeneration was run on the vendored copy.
5. Took snapshots and ran the suites (§§3–6).

**Where the sync document and the upstream addon disagree** (reported as the coordinator asked):

| # | `FLOW_UPSTREAM_SYNC.md` says | What happened / upstream says |
|---|---|---|
| S1 | §4.3: copy upstream "excluding `*.uid`" | This drops the `.uid` of files that are **new** upstream (`flow_graph_migrations.gd.uid`). Godot re-creates it, with `WARNING: Missing .uid file for path "res://addons/flow_nodes_editor/flow_graph_migrations.gd". The file was re-created from cache.` This is harmless. The rule should be "exclude `*.uid` for files we already have". |
| S2 | §1: keep `nodes/bl_*.gd` inside the addon | Upstream `DEPRECATIONS.md` §1 says `bl_*` templates are "not part of the addon" and should move to a project directory listed in `flow_nodes/node_directories`, each with a `meta_node.category`. Keeping them in `nodes/` still works, because `FlowNodeRegistry` scans the addon's `nodes/` first. However, 23 of the 23 `bl_*` nodes and `project_points` have no `category`, so the editor now gives them hash colours. The effect is cosmetic. |
| S3 | §3: `seed = hash(position)` before every pick is "Harmless if left; delete for fewer nodes" | Leaving it in is harmless. **Deleting it is not.** It re-rolls 155 of 177 rooms on the upstream addon and 155 of 177 on the vendored one (§4.3, E1). No flag makes the deletion output-neutral: after deletion, `legacy_global_rng` reproduces the *vendored addon without the workaround*, not today's rooms. Keep the workaround unless re-rolled picks are acceptable. |
| S4 | §3: Sample Mesh normals: "after a sync its log should say `normals as sampled`" | Confirmed. The vendored bake logs `normals flipped` 45/45 and the upstream bake logs `normals as sampled` 45/45. `graphs/styles/kit/surface_points.json` and `data/deco_surfaces.json` come out **byte-identical** from both. |
| S5 | §3: "Delete `_ensure_indexed` once fixed" | Confirmed fixed by `897d7a2`. With `_ensure_indexed` disabled, the upstream bake is byte-identical. The control on the vendored addon hits 3× `SCRIPT ERROR ... sample_mesh.gd:37` and loses 864 lines of `surface_points.json` (E3). It can go. |
| S6 | §3: bindings: "Automatic: the generator detects `bindings`" | Confirmed. `gen_room_families` rewrote 5 kit subgraphs, wires to `bindings` (29 lines added, 77 removed), and reported "MANIFEST 94 graphs, none edited by hand". Output is unchanged: 177/177 rooms identical. |
| S7 | §3: Load PCG Data Asset: "the cache alone removes about 21 ms a room" | Measured about **25 ms per room** (§6). |
| S8 | §4.6: the suites to run | `OverworldRoadRegression` gives 197/200 on both copies (the 3 known stale failures), and `HeadlessSuite` gives `SUITE_TOTAL real_failures=4` on both. **Neither catches the road change in §4.2**, because no suite pins dressing counts. |
| S9 | `flow_upstream_status.sh` says "Read-only … Changes nothing" | It runs `git fetch origin` in the upstream checkout, which updates remote-tracking refs. This is minor. |

---

## 2. What was compared, and how

The comparison uses two digests, both headless and without rendering or scene spawning of props, on the same Godot
binary with the same native library.

1. **The team's `tools/graph_gen/style_snapshot.tscn`** (on this commit). It covers every stop × seeds 11 and 21,
   runs StopFloorDataBuilder → TacticalDecorator → registry → one graph per room, and hashes each room as
   kind|prefab|cell|yaw. This is the primary room gate.
2. **`tools/bl_snapshot.tscn`** (this run, Appendix B), which covers what the team's tool does not:
   - It drives **the builder itself**: `MissionFloorStack.build_for_mission` (including `reserve_fear_rooms` with
     the company roster) → `DungeonLevelBuilder._apply_room_style_graphs(fd, fd.rng_seed)`. This includes
     `_clear_room_style_domains` and `_stamp_room_records`, exactly as `_generate_hotel_floor_data` runs a staged
     stop.
   - It covers the seven stops, the **hotel** stack (two pinned floors), the **`pcg_master_graph`** branch
     (`_generate_flow_node_floor_data`) and the **overworld road**. The road path is
     `ProceduralRoadGenerator.generate_road` → `OverworldRoadNetwork.setup` → `commit_edge` on every root branch,
     then the dressing is re-evaluated with the exact arguments `_dress_edge`/`_dress_approach` pass, footprint-cleared.
   - Per room it records a SHA-256 of the whole canonicalised room dictionary, plus separate hashes of the props
     (sorted), the cover cells, the doors, the ticket and `style_graph_path`. Per floor it records totals and hashes
     of `floor_cells`, `room_records`, `corridor_props` and `fear_rooms`.
   - It captures every error and warning with an `OS` `Logger`, so capture is identical on both addons. It also
     records `FlowNodeIO.last_errors` when the addon has it, and wall time per stage and per styled room.
   - It is hermetic: `RunPersistence.disk_writes_enabled = false`, and in-memory state is set to
     `{selected_mission_id, roster = company_seed_profiles()}`. It never reads or writes `user://run_state.json`.

Seeds: **11 and 21** for the stops, hotel, `pcg_master` and road (the team's pair), plus 4242 in `StopSiteRegression`.
The two random seeds that `HeadlessSuite` happened to boot with were also replayed (§5).

### 2.1 Determinism (checked before any cross-addon comparison)

| Check | Result |
|---|---|
| `style_snapshot`, vendored, two processes | **177/177 rooms identical** |
| `style_snapshot`, upstream, two processes | 177/177 identical |
| `bl_snapshot`, vendored, two processes × `--repeat=2` in-process (stops + hotel + pcg_master) | 506/506 room digests identical run to run (253 per rep) |
| `bl_snapshot`, upstream, same | 506/506 identical |
| `bl_snapshot` road, vendored / upstream, `--repeat=2` | 7/7 road pieces identical rep to rep on each side |

---

## 3. Deliverable 1: parse and runtime errors on the swapped copy

The swap causes no new `SCRIPT ERROR` or `Parse Error` in the game's code paths. Every run, with its result:

| Run | Vendored | Upstream | Caused by the upstream change? |
|---|---|---|---|
| `godot47 --headless --import` | 1 `SCRIPT ERROR` (`addons/phantom_camera/.../update_button.gd:62`, the updater's HTTP reply) | the same 1 | **No.** A third-party addon. |
| — import warnings | `flow_editor.tscn:4 - ext_resource, invalid UID: uid://cr8w0asb2kvr8 - using text path instead` | the same | **No.** Pre-existing uid drift in the game (`flow_graph_edit.gd.uid` is `uid://brxprus0a0g4` in the game). It falls back to the path. |
| — import warnings | — | `Missing .uid file for path ".../flow_graph_migrations.gd". The file was re-created from cache.` | **Yes, but by the sync rule**, not the addon (S1). Harmless. |
| Compile every `.gd` (`tools/parse_all.gd`, 1013 / 1015 scripts) | 10 `PARSE_FAIL` | **the same 10** | **No.** All are game-side: 5 backups under `output/company_task01/` that redeclare `TacticalCamera` / `GameController` / `SurvivorBarkBrain`; 4 `script_templates/Query*` whose base classes are absent; `scripts/tools/build_supply_common_room.gd:819` (`_mcp_print()` not found). |
| — | — | `ERROR: res://addons/flow_nodes_editor/connectors_row.tscn:7 - Parse Error: [ext_resource] referenced non-existent resource at: .../connectors_row.gd` (once) | **Yes, as a load-order artefact only.** It happens only when `connectors_row.gd` is the first addon script compiled cold. Upstream `flow_data.gd` now references `FlowNodeBase`/`FlowNodeIO` (the vendored copy's `flow_data.gd` references neither). That exposes the existing cycle `node.gd` → `preload(connectors_row.tscn)` → `connectors_row.gd` → `FlowNodeBase`. It was not seen in the import, a mission boot, the suites or the snapshots, so it is not a runtime problem. The cycle is worth breaking upstream, for example by typing `getNode()` loosely in `connectors_row.gd`. |
| `HeadlessSuite` (boots `scenes/Main.tscn` on a real mission and runs the 19-suite battery) | `SUITE_TOTAL real_failures=4`, 1 `SCRIPT ERROR` | **identical** SUITE lines, the same 1 `SCRIPT ERROR` | **No.** The error is the game test `CompanyRoadRegression.gd:4427` calling a missing `_stand_down`. The 4 failures (`company_road` gas-station card, `procedural_road` D21, 2 × `field ai`) are identical on both. |
| `StopSiteRegression` (runner `tools/stop_suite_runner.tscn`) | ok, 1145 checks, 0 failures | ok, 1145, 0. `STOP_GRAPH_OUTPUT` per-room counts identical. | — |
| `OverworldRoadRegression` (`--script`) | 200 checks, 3 failures, 357 `SCRIPT ERROR` (`OverworldRoadScene.gd:736 vehicle_hands` ×318, …) | **identical** PASS/FAIL list and errors | **No.** These are the 3 known stale failures and pre-existing game errors. |
| `bake_surfaces` / `gen_room_families` | 0 errors | 0 errors | — |
| Snapshots (every config, both digests) | 0 `push_error`; 28 warnings per run | 0 `push_error`; the same 28 warnings | **No.** All 28 are `Room style graph placed NOTHING` for service closets on the `pcg_master` path, the same on both. |

No error of the kinds the brief anticipated appeared anywhere: a removed symbol, an `EditorInterface` guard, a
canonical-schema refusal (`registerStream`), "binds unknown setting", "matched no node setting" or a deprecated
template alias. A grep of every upstream log for `canonical|Stream name conflict|deprecated|binds unknown|matched no
node setting` returns 0 hits.

---

## 4. Deliverable 2: every difference, with its cause

### 4.1 The table

| Where | Seed | What differs (vendored → upstream) | Upstream change responsible | Legacy flag restores it? | Is the new behaviour correct? |
|---|---|---|---|---|---|
| All 7 stops (177 rooms), hotel (2 floors), `pcg_master` floor | 11, 21 | **Nothing.** Room hash, props, cover, doors, tickets, `style_graph_path`, `room_records`, `fear_rooms` and floor cells are all identical, with and without the kit regeneration. | — (the `c981656` seeding change is live but hidden, see §4.3) | — | — |
| road, approach | 11 | identical (858) | — | — | — |
| road, `supply_food->escape_run@root` | 11 | 13725 → 13716: **pole 54→51**, bush_06 280→279, pine_a 4033→4030, pine_b 4125→4124, rock 809→808 (removals only) | `03c2826` `sample_spline` records extent as `bounds_min/max` | **No** (`legacy_scale_from_extent` tried: no effect) | Poles: **no**. Trees: debatable. See §4.2. |
| road, `supply_food->info_records@root` | 11 | 13531 → 13521: **pole 55→48**, bush_06 260→258, pine_c 2985→2984 | same | No | same |
| road, approach | 21 | 818 → 817: pine_b 265→264 | same | No | same |
| road, `supply_food->escape_run@root` | 21 | 13469 → 13461: **pole 53→50**, pine_a −1, pine_b −2, pine_c −1, rock −1 | same | No | same |
| road, `supply_food->info_records@root` | 21 | 27941 → 27919: **pole 113→101**, bush_06 −1, bush_07 −1, pine_a −2, pine_b −1, pine_c −2, rock −3 | same | No | same |
| road, `supply_food->sabotage_altar@root` | 21 | 13865 → 13853: **pole 53→49**, bush_06 −2, bush_07 −2, pine_a −1, pine_b −1, pine_c −2 | same | No | same |

Road timing is unchanged (§6). Every road difference is a pure removal: nothing is added or moved.

### 4.2 Road: the bisection

Every run used seed 11 unless noted, with `bl_snapshot --configs=road` against the vendored baseline.

| Experiment in `bl_upstream` | Road pieces identical to vendored |
|---|---|
| Upstream as is | 1/3 |
| R1: `"legacy_scale_from_extent": true` on all 6 road `sample_spline` nodes (`set_flag.py`) | **1/3, no change** |
| R3: `nodes/sample_spline.gd` + `_settings.gd` reverted to the vendored files | **3/3** |
| R4a: upstream `sample_spline.gd`, with only the line `output.setSymmetricBounds( ssize )` disabled (unit `size` kept) | **3/3**, and **7/7 on seeds 11+21** |
| R4b: bounds skipped only on `pole_samples` | poles restored; the trees still differ |
| R4c: bounds skipped on `pole_samples` and `forest_samples` | **3/3** |

**Mechanism.** Since `03c2826`, `sample_spline` writes the sampling extent (`Vector3.ONE * uniform_interval`) as
symmetric `bounds_min/bounds_max`. It does this **whether or not `legacy_scale_from_extent` is set**; the flag only
decides whether `size` is also reset to one.

- **Poles.** In `sg_road_poles`, `pole_samples` (40 m interval) → `pole_offset` (`point_offsets`,
  `inherit_anchor_size = false`) → … → `pole_socket_keepout` (`difference`, A = poles, B = sockets).
  `point_offsets._copy_streams` copies every anchor stream to the children, **including the new bounds**, while
  resetting `size`. Each pole therefore carries a ±20 m box. `difference` prefers `bounds_min/max` over `size`
  (`_broadphase_params`, `BoundsOverlapUtil.world_aabbs`), so any pole whose 40 m cube touches a socket is removed.
  Before the change, the keep-out used the pole's size-derived box, about 1 m.
- **Trees and rocks.** `forest_samples` (3 m interval) in `sg_road_placement` now gives each forest point a 3 m
  bounds cube. The same bounds-preferring overlap test in the clearance step removes 1–10 more trees, bushes and rocks per edge.
  `clearing_samples` and the guardrail samplers also get bounds, but disabling bounds on the two nodes above was
  enough to restore every piece measured.

**Correct?** For the poles, no. At node level the new bounds follow UE (a spline sample's bounds are its step). The
effect in this graph, though, is a 40 m keep-out per pole, which the graph was never authored for. The cause is
`point_offsets` resetting `size` but not the anchor's bounds when `inherit_anchor_size` is false. That behaviour is
inconsistent and is worth an upstream fix. For the trees, the new cube is a defensible footprint, but it is not what
the graph was tuned against. Neither case is a game bug that the old behaviour was hiding.

**What this means for the migration plan.** [BLACK_LANTERN_MIGRATION_PLAN.md](BLACK_LANTERN_MIGRATION_PLAN.md) §1.4
C1 says "set `legacy_scale_from_extent: true` on the 6 nodes … to keep the current look". **R1 shows this does not
keep it.** Two fixes keep the look, and either is enough:

- **(a) Game side.** Add a `remove_attribute` for `bounds_min,bounds_max` right after `pole_samples` and
  `forest_samples` (or after all six samplers). This is equivalent to R4a/R4c, which restore the output exactly.
- **(b) Upstream.** Make `legacy_scale_from_extent` also skip `setSymmetricBounds`, since the flag's documented
  promise is the old output, and correct the `DEPRECATIONS.md` row. Separately, `point_offsets` should not copy
  anchor bounds unchanged when `inherit_anchor_size` is false.

### 4.3 Rooms: why nothing changed, and proof that the check would have seen it (bisection-lite)

Of the output-changing rows in `DEPRECATIONS.md` §2, these reach the room graphs:

| Upstream change | Where BL uses it | Why the output does not change |
|---|---|---|
| `c981656` `match_and_set` seeds by position when there is no `seed` stream (`legacy_global_rng`) | 13 `match_and_set` nodes in the kit subgraphs | Every pick runs after the game's `pk_seed` / `*sd` Expression (`seed = hash(position)`, `gen_room_families.gd:2414, 2476`), so the points always carry a `seed` stream, and that path is unchanged. **Proven by E1 below.** |
| `ee662ff` `sample_mesh` outward normals | only in `bake_surfaces` (offline) | The bake measures the normal direction (`flip`), so the baked table is byte-identical (S4). |
| `ee662ff` `match_and_set` numeric key matching | kit `on_match` and `st_role` | The keys are strings that match exactly, so the numeric fallback never runs. |
| `ee662ff` `expression` keeps an existing numeric stream's type | 373 Expression nodes | No BL expression writes a bool into a Float stream or similar (the output is identical). |
| `ee662ff` `merge` registers streams first | 2 merges | Upstream documents this as "no output change". Confirmed. |
| `fbc48a5` / `9417d63` graph seed and `effective_seed()` (`select_points`, `transform`, `mutate_seed`, `attribute_random` …) | throughout | The game never sets `ctx.seed`, and with seed 0, `effective_seed()` equals `random_seed` (the seed-zero back-compatibility guarantee). |
| `7cb0cf0` bindings fall back to the graph's declared input default; `8005e4c` Dictionary-entry bindings | the regenerated kit graphs (S6) | The bindings resolve to the same values the wires carried. |
| `15b26d5` explicit `preview` flag instead of `owner == null` in the editor | all nodes | Every BL evaluation has an owner (`FlowGraphNode3D` temp roots). |

**E1: the seed workaround is what hides `c981656`.** `toggle_graphs.py` was used on the scratch copies only.
Each result below is a `style_snapshot` over 177 rooms.

| Comparison | Rooms changed |
|---|---|
| vendored, graphs as committed → vendored with the workaround dropped (`pk_seed`/`*sd` write `seed_ws` instead of `seed`) | **155/177** |
| upstream, graphs as committed → upstream with the workaround dropped | **155/177** |
| vendored, workaround dropped → **upstream, workaround dropped** | **151/177**: this is `c981656` itself |
| vendored, workaround dropped → **upstream, workaround dropped + `legacy_global_rng = true`** on the 13 kit `match_and_set` nodes | **0/177 (identical)** |

Prop and "thing" counts per stop move by a few percent when the workaround is dropped. For example, `supply_food@11`
gives 370 → 364 on vendored and 370 → 350 on upstream. So the snapshot does detect the change, the flag restores it
exactly, and the game's workaround is the reason the synced game is unchanged. The workaround and the upstream
behaviour **are not doubled**, because with a `seed` stream present, upstream uses `(point seed ^ node seed)` exactly
as the vendored copy does.

**E3: `_ensure_indexed` can be deleted on `897d7a2`.** See S5.

**E2 (Sample Mesh normals).** See S4. The workaround adapts by itself, and the baked output is identical.

---

## 5. Deliverable 3: errors that appear only on upstream, and `FlowNodeIO.last_errors`

- **No upstream-only runtime errors.** All snapshot configurations × seeds × repeats were captured with an `OS`
  `Logger`. Both sides show 0 `push_error` and 0 `Node.Err` (upstream's `setError` still calls `push_error`), and
  the warning sets are identical.
- **`FlowNodeIO.last_errors` is never filled on the game's path.** The game calls `FlowNodeIO.evaluate_graph(graph,
  inputs, ctx, params)` directly, in `DungeonLevelBuilder._apply_room_style_graphs`,
  `_generate_flow_node_floor_data` and `OverworldRoadFlowAdapter.evaluate_dressing`. That call attaches no error
  log: `last_errors` is filled only by `FlowNodeIO.evaluate()`, `evaluate_collecting_errors()`,
  `FlowGraphNode3D.generate()`, or after `FlowNodeIO.start_error_log(ctx)`. In the digest, `last_errors` is `[]` on
  every run.
- **With a log attached it is still empty.** `tools/last_errors_probe.tscn` (upstream only, Appendix C) runs the
  style path for every stop × seeds 11/21 with `FlowNodeIO.start_error_log(ctx)` before each `evaluate_graph`. The
  result was `LAST_ERRORS_PROBE rooms=177 errors=0`.
- **To use `last_errors` in the game,** call `FlowNodeIO.start_error_log(ctx)` before `evaluate_graph` (or switch to
  `evaluate_collecting_errors`) in the three call sites above, then read `FlowNodeIO.last_errors` next to the
  existing "placed NOTHING" report.
- **The two extra "placed NOTHING" warnings in the upstream `HeadlessSuite` log are not an upstream effect.**
  `HeadlessSuite` boots with a random mission seed, which was −7623379510307596271 on the vendored run and
  7991024038712904717 on the upstream run. Replaying both seeds on both addons with `bl_snapshot
  --configs=supply_medicine` gives 28/28 identical rooms and the same two warnings (supply_medicine RESTROOM /
  SUPPLY at seed 7991024038712904717) on both.

---

## 6. Deliverable 4: timing per stage

All timings are single-threaded wall time on the same 4-core container. Vendored and upstream runs were never run at
the same time.

### 6.1 Room dressing (`style_snapshot` graph time), mean of two processes each

| Stop@seed | Rooms | Vendored ms | Upstream ms | Upstream + regenerated kit (bindings) ms | Δ upstream |
|---|---|---|---|---|---|
| escape_run@11 | 4 | 813 | 786 | 876 | −3.3 % |
| escape_run@21 | 4 | 846 | 877 | 838 | +3.6 % |
| holdout_run@11 | 20 | 4191 | 3926 | 4198 | −6.3 % |
| holdout_run@21 | 20 | 4708 | 3952 | 4395 | −16.1 % |
| info_records@11 | 15 | 3017 | 3024 | 3279 | +0.2 % |
| info_records@21 | 17 | 3477 | 3203 | 3262 | −7.9 % |
| long_way_round@11 | 15 | 3206 | 2994 | 3088 | −6.6 % |
| long_way_round@21 | 15 | 3223 | 2879 | 3074 | −10.7 % |
| sabotage_altar@11 | 7 | 1482 | 1271 | 1505 | −14.2 % |
| sabotage_altar@21 | 11 | 2367 | 2202 | 2430 | −6.9 % |
| supply_food@11 | 7 | 1554 | 1518 | 1527 | −2.3 % |
| supply_food@21 | 7 | 1504 | 1389 | 1508 | −7.7 % |
| supply_medicine@11 | 14 | 3327 | 3050 | 3509 | −8.3 % |
| supply_medicine@21 | 21 | 4720 | 4013 | 4417 | −15.0 % |
| **Total** | **177** | **38437** (217 ms/room) | **35085** (198 ms/room) | 37906 (one run) | **−8.7 %** |

The per-room change has a median of −17.6 ms (range −118 to +57 ms).

**The `load_pcg_data_asset` cache.** Upstream `nodes/load_pcg_data_asset.gd`/`_settings.gd` were reverted to the
vendored files in `bl_upstream`, and the output stayed identical (177/177). Graph time over two processes was 39252 ms
and 39770 ms, against 35614 / 34555 ms with the cache. **The cache saves about 4.4 s over 177 rooms, about 25 ms per
room.** That is the whole upstream gain. The rest of the upstream framework (binding and override resolution,
error-log plumbing, v1→v2 graph migration in memory) costs about +3 % against the vendored copy (39.5 s vs 38.4 s
without the cache).

The regenerated kit (`bindings` instead of setting wires) timed 37.9 s in one `style_snapshot` run and 79.2 s against
76.1 s in the builder-path digest below. That is about 4 % slower than wires on the same addon, which is near the
process-to-process noise (about 2–3 %) but consistent in sign. It is still faster than the vendored copy.

### 6.2 Builder path, per stage (`bl_snapshot`, mean over 2 seeds × 2 reps × 2 processes)

| Config | Floor build (StopFloorDataBuilder / packer + fear rooms + TacticalDecorator), ms | `_apply_room_style_graphs`, ms |
|---|---|---|
| escape_run | 56 → 53 | 1029 → 1019 (−1.0 %) |
| holdout_run | 219 → 242 | 4494 → 4386 (−2.4 %) |
| info_records | 194 → 196 | 3487 → 3125 (−10.4 %) |
| long_way_round | 187 → 197 | 3259 → 2959 (−9.2 %) |
| sabotage_altar | 121 → 113 | 2005 → 1868 (−6.8 %) |
| supply_food (diner) | 89 → 83 | 1587 → 1472 (−7.3 %) |
| supply_medicine | 203 → 211 | 3887 → 3669 (−5.6 %) |
| hotel (2 floors) | 38 → 34 | 543 → 529 (−2.7 %) |
| `pcg_master` (whole `_generate_flow_node_floor_data`) | — | 732 → 729 (−0.4 %) |
| **Sum of style graphs, 36 runs** | | **81.2 s → 76.1 s (−6.3 %)** |

Floor build does not use the addon, so its differences are noise. The first styled room of a process includes cold
loads, for example 630 ms for the diner counter against about 200 ms warm.

### 6.3 Road (`bl_snapshot --configs=road`, mean over seeds 11 and 21, 2 reps)

| Stage | Vendored ms | Upstream ms |
|---|---|---|
| `ProceduralRoadGenerator.generate_road` | 14 | 13 |
| `OverworldRoadNetwork.setup` (approach + root junction, dressing included) | 490 | 522 |
| `commit_edge` × root branches (realisation, re-dressing, mesh building) | 80 685 | 82 166 |
| Dressing graph evaluations alone (the re-evaluated pieces) | 1 995 | 2 042 |

Road time is dominated by realisation in game code, not by the graph. The dressing graph does not use
`load_pcg_data_asset`, so it gets no benefit from the cache.

---

## 7. What this run does not cover

- **Visual placement after FloorData.** `_place_props`, lights and fog in `DungeonLevelBuilder` are game code and are
  not digested. They read the FloorData, which is identical, so they cannot differ because of the addon. A full
  mission boot did run in `HeadlessSuite` on both copies.
- **The Style Lab, the restyle path (Distorted Spaces "repeat" rooms) and `BLRoomStyleRuntime.evaluate_style_graph_outputs`
  (M14 in the migration plan)** were not digested. They use the same graphs and the same `evaluate_graph` call.
- **Road coverage is partial:** only the root junction's branches, one level deep, at density 0.5. Further junctions
  realise the same subgraphs.
- **Story graphs (`StoryGraphs`, `BLGraphApi`)** are not Flow Nodes graphs and are out of scope.
- **The team's unpushed tree** is not covered. Everything above is at `05e473af`. Appendix D gives the commands to
  rerun it there.
- **Graph seed.** The game does not set `ctx.seed`. Setting it (`FLOW_UPSTREAM_SYNC.md` §3, "Seed in ctx.eval_id")
  **will** change output through `derive_seed`, and was not measured here.

---

## 8. Recommendations

**For the Black Lantern re-baseline commit:**

1. Take the addon. Room output is byte-identical, and the kit regeneration (bindings, the `normals as sampled` bake)
   is output-neutral.
2. **For the road, do not rely on `legacy_scale_from_extent`.** To keep today's road, strip
   `bounds_min,bounds_max` after `pole_samples` (`sg_road_poles`) and `forest_samples` (`sg_road_placement`), or
   after all six samplers. Then rerun the road digest and expect 7/7 identical. Otherwise, accept 3–12 fewer poles
   and up to 10 fewer trees, bushes and rocks per edge. The 12-pole drop on `info_records@21` is the most visible.
3. Keep the `seed = hash(position)` Expression nodes (S3). Delete `bake_surfaces.gd` `_ensure_indexed` (S5).
4. Attach an error log (`FlowNodeIO.start_error_log(ctx)`) in the three `evaluate_graph` call sites if you want
   `last_errors`.
5. Add a road-dressing count or digest to `OverworldRoadRegression` or `HeadlessSuite`. Today no suite would notice §4.2.

**For GF-PCGODOT (this branch):**

1. Make `legacy_scale_from_extent` also skip `setSymmetricBounds` in `sample_spline` and the other size→bounds
   generators, or document that it does not restore bounds consumers (`difference`, `self_pruning`, overlap
   queries). The `DEPRECATIONS.md` row currently promises "the old look".
2. `point_offsets` with `inherit_anchor_size = false` should not copy the anchor's `bounds_min/max` unchanged, since
   it already resets `size`.
3. Break the `node.gd` ↔ `connectors_row.tscn` ↔ `connectors_row.gd` preload cycle (§3).
4. Bump `plugin.cfg` `version` for the release, as the deprecation policy expects.

---

## Appendix A: `flow_upstream_status.sh` output (full)

`bash <bl>/tools/graph_gen/flow_upstream_status.sh /home/user/GF-PCGODOT claude/pcg-system-review-4tpca9`

```text
== 1. upstream commits touching the addon since the last full sync (cb064d0)
-- claude/pcg-system-review-4tpca9
   897d7a2 2026-09-27 fix(pcg): Black Lantern follow-ups — non-indexed meshes, bindings on Dictionary settings, export-safe editor references, empty-input schemas
   ddd0464 2026-09-27 feat(pcg): planner follow-ups — position-seeded match_and_set, binding defaults, project colours, runtime error log, preview flag, canonical schema
   ee662ff 2026-09-27 fix(pcg): node fixes from production feedback (Black Lantern)
   fbc48a5 2026-09-27 feat(pcg): runtime API — graph seed, generate/cleanup/regenerate, owner-less evaluation, boundary data helpers
   2bbb8eb 2026-09-27 test(pcg): evaluator, loop, subgraph, spawner suites and a golden-output harness; scan_nodes skips generated content
   10ec11b 2026-09-27 chore(pcg): project-setting node directories, metadata-only categories, graph format v2 with migrations, deprecation policy
   9417d63 2026-09-27 feat(pcg): per-instance setting overrides and $param bindings; honour wired parameter ports at runtime
   e6aea74 2026-06-22 feat(pcg): opt-in legacy_scale_from_extent bridge on size→bounds generators
   c3ab89d 2026-06-21 fix(pcg): broadcast + numeric-coercion correctness in attribute ops
   03c2826 2026-06-21 fix(pcg): generators record extent as bounds, not scale (no mesh stretching)
   5a3f9d7 2026-06-21 fix(pcg): stop nodes from mutating shared scene/source resources
   980dc82 2026-06-21 fix(pcg): derive per-point randomness from seed/position, not node-global RNG
   9f82bdf 2026-06-21 ci: test on Godot 4.6 + 4.7; rebuild stale Windows GDExtension binaries
   0bcf286 2026-06-21 test: fix all GdUnit4 test failures — 1343 cases, 0 failures
   bba3bf1 2026-06-19 Merge pull request #18 from Flynsarmy/better_descriptions
   48108dc 2026-06-19 Merge pull request #20 from Flynsarmy/node_settings_descs
   6064b7c 2026-06-17 Show export descriptions for FlowGraphNode3D in the inspector
   b31fcdc 2026-06-17 Add debug export descriptions
   a09082c 2026-06-17 Better descriptions, add ENUM descriptions
   c272559 2026-06-17 Add type hints, better export descriptions
   7b47f2d 2026-06-14 Grammar: Add types where possible
   e39e39c 2026-06-13 fix: guard hot-reload watcher against non-instantiable node scripts
   c6b8e7b 2026-06-13 fix: Output node exposes named stream with its real type, not the declared port type
   532f0af 2026-06-14 fix: resolve all FlowCommonNodeRegressionTest failures under Godot 4.6
   bfa7e28 2026-06-14 fix: restore subgraph runtime_param propagation (was a no-op)

== 2. our local patches — absorbed in claude/pcg-system-review-4tpca9 yet?
   ABSORBED  flow_nodes_io.gd — runtime setting wires: restore args_port after refreshFromSettings
   ABSORBED  flow_nodes_io.gd — runtime setting wires: size inputs to the highest connected arg port
   ABSORBED  flow_i18n.gd — exported builds: EditorInterface through the singleton
   ABSORBED  node_draw_debug.gd — exported builds: EditorInterface through the singleton
   ABSORBED  nodes/match_and_set.gd — empty input keeps the table's schema
   ABSORBED  nodes/sample_spline.gd — an empty spline stream is valid (a road with no bridges)
   OURS      nodes/project_points.gd (+ _settings) — our node, keep on every sync
   OURS      nodes/bl_*.gd — our nodes, keep on every sync

== 3. upstream fixes our workarounds wait for (see docs/FLOW_UPSTREAM_SYNC.md §3)
   ABSORBED  nodes/match_and_set.gd — Match And Set seeds per point (then the kits' seed = hash(position) can go)
   ABSORBED  nodes/sample_mesh.gd — Sample Mesh: non-indexed surfaces (bake_surfaces.gd _ensure_indexed can go)
   ABSORBED  node_settings.gd — P0 bindings (gen_room_families.gd _bind switches itself over on the next run)
   ABSORBED  flow_data.gd — P0 seed on EvaluationContext (then set ctx.seed = style_seed in the builder)
   (Sample Mesh's inward normals: bake_surfaces.gd detects the direction itself — nothing to undo)

== 4. framework files that differ from claude/pcg-system-review-4tpca9 (ours on the left)
   729 lines  flow_nodes_io.gd
   283 lines  nodes/sample_spline.gd
   275 lines  node.gd
   235 lines  flow_node.gd
   231 lines  flow_data.gd
   137 lines  flow_node_registry.gd
   93 lines  nodes/sample_points.gd
   93 lines  nodes/match_and_set.gd
   76 lines  nodes/load_pcg_data_asset.gd
   68 lines  nodes/grammar_expand.gd
   54 lines  nodes/subdivide_segment_settings.gd
   53 lines  nodes/copy.gd
   52 lines  nodes/physics_shape_sweep_settings.gd
   46 lines  nodes/sample_points_settings.gd
   44 lines  nodes/noise_settings.gd
   43 lines  nodes/compute_kernel_settings.gd
   40 lines  nodes/sample_spline_settings.gd
   39 lines  nodes/sample_terrain_layers_settings.gd
   38 lines  nodes/texture_sampler_settings.gd
   38 lines  nodes/ray_cast_settings.gd
   36 lines  nodes/copy_settings.gd
   34 lines  nodes/physics_overlap_query_settings.gd
   31 lines  nodes/math_op_settings.gd
   30 lines  node_settings.gd
   29 lines  nodes/points_from_tilemap_settings.gd
```

## Appendix B: the digest script, `tools/bl_snapshot.gd` + `.tscn`

Copy both files into `res://tools/` of any Black Lantern checkout. They depend only on game classes that exist at `05e473af` (`MissionFloorStack`, `DungeonLevelBuilder`, `StopFloorDataBuilder`, `ProceduralRoadGenerator`, `OverworldRoadNetwork`, `OverworldRoadFlowAdapter`) and on the Godot 4.5+ `Logger` API.

```gdscript
## bl_snapshot.gd — headless digest of Black Lantern's generated FloorData.
##
## Runs the game's PRODUCTION generation path for every stop (the seven
## resources/missions/*.tres rows), a two-floor hotel stack and the
## pcg_master_graph path, for a fixed list of seeds, WITHOUT building geometry:
##
##   stop:   RunPersistence selects the mission -> MissionFloorStack.build_for_mission
##           (StopFloorDataBuilder.build -> reserve_fear_rooms -> TacticalDecorator)
##           -> DungeonLevelBuilder._apply_room_style_graphs(fd, fd.rng_seed)
##           (exactly what DungeonLevelBuilder._generate_hotel_floor_data does with a stack)
##   hotel:  MissionFloorStack._generate_pinned_floor (HotelMassGenerator -> HotelRoomPacker
##           -> reserve_fear_rooms -> TacticalDecorator), two floors, pinned stairs
##           -> DungeonLevelBuilder._apply_room_style_graphs
##   pcg_master: DungeonLevelBuilder._generate_flow_node_floor_data (graph_black_lantern_dungeon
##           .tres, then _apply_room_style_graphs) — the use_hotel_generation=false branch
##
## It writes a JSON digest: per room a stable hash of the room dict and of its props
## (sorted by kind+position), cover cells, doors, tickets and style_graph_path; per floor
## totals; every error/warning the run logged (captured with an OS Logger, so the same on
## both addon versions); FlowNodeIO.last_errors when the addon exposes it; wall time per
## stage and per styled room.
##
## Hermetic: RunPersistence.disk_writes_enabled = false and its in-memory state is replaced
## with {selected_mission_id, roster = company_seed_profiles()} — the save on disk is never
## read or written, and every run gets the same deployed fear line.
##
## Run (from the project root):
##   godot --headless --path . res://tools/bl_snapshot.tscn -- --out=/abs/digest.json \
##       [--seeds=4242,1337] [--configs=supply_food,hotel] [--repeat=2]
extends Node

const MISSIONS_DIR := "res://resources/missions"
const DEFAULT_SEEDS := [11, 21]
const FLOAT_DP := 4

var _out_path := ""
var _seeds: Array = []
var _only_configs: Array = []
var _repeat := 1
var _log_sink: Array = []
var _logger: Object = null
var _current_label := ""


class CaptureLogger extends Logger:
	var sink: Array
	var owner_node: Object
	func _init(p_sink: Array, p_owner: Object) -> void:
		sink = p_sink
		owner_node = p_owner
	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			editor_notify: bool, error_type: int, script_backtrace: Array[ScriptBacktrace]) -> void:
		var kind := "ERROR"
		if error_type == Logger.ERROR_TYPE_WARNING:
			kind = "WARNING"
		elif error_type == Logger.ERROR_TYPE_SCRIPT:
			kind = "SCRIPT_ERROR"
		elif error_type == Logger.ERROR_TYPE_SHADER:
			kind = "SHADER_ERROR"
		var text := rationale if not rationale.is_empty() else code
		sink.append({"t": Time.get_ticks_usec(), "kind": kind, "label": str(owner_node.get("_current_label")),
			"text": text, "where": "%s:%d %s" % [file.get_file(), line, function]})
	func _log_message(message: String, error: bool) -> void:
		sink.append({"t": Time.get_ticks_usec(), "kind": "MSG_ERR" if error else "MSG",
			"label": str(owner_node.get("_current_label")), "text": message})


func _ready() -> void:
	_parse_args()
	_logger = CaptureLogger.new(_log_sink, self)
	OS.add_logger(_logger)
	# Let every autoload finish _ready before we touch them.
	await get_tree().process_frame
	await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	var result := _run_all()
	result["total_wall_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	OS.remove_logger(_logger)
	var f := FileAccess.open(_out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result, " ", true))
	f.close()
	print("BL_SNAPSHOT wrote %s" % _out_path)
	get_tree().quit(0)


func _parse_args() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_path = a.substr(6)
		elif a.begins_with("--seeds="):
			for s in a.substr(8).split(",", false):
				_seeds.append(int(s))
		elif a.begins_with("--configs="):
			for c in a.substr(10).split(",", false):
				_only_configs.append(c)
		elif a.begins_with("--repeat="):
			_repeat = maxi(1, int(a.substr(9)))
	if _seeds.is_empty():
		_seeds = DEFAULT_SEEDS.duplicate()
	if _out_path.is_empty():
		_out_path = ProjectSettings.globalize_path("res://bl_snapshot_digest.json")


func _addon_info() -> Dictionary:
	var io_script: Script = load("res://addons/flow_nodes_editor/flow_nodes_io.gd")
	var has_last_errors := io_script.source_code.contains("static var last_errors")
	var cfg := ConfigFile.new()
	cfg.load("res://addons/flow_nodes_editor/plugin.cfg")
	return {
		"plugin_version": str(cfg.get_value("plugin", "version", "?")),
		"has_flow_graph_migrations": ResourceLoader.exists("res://addons/flow_nodes_editor/flow_graph_migrations.gd"),
		"has_last_errors": has_last_errors,
		"native_GDKdTree": ClassDB.class_exists("GDKdTree"),
		"native_GDRTree": ClassDB.class_exists("GDRTree"),
		"godot": Engine.get_version_info().string,
	}


func _config_list() -> Array:
	var out: Array = []
	var dir := DirAccess.open(MISSIONS_DIR)
	var files: Array = []
	for fn in dir.get_files():
		var clean := fn.trim_suffix(".remap")
		if clean.ends_with(".tres"):
			files.append(clean)
	files.sort()
	for fn in files:
		var def: MissionDef = load("%s/%s" % [MISSIONS_DIR, fn]) as MissionDef
		if def != null and StopFloorDataBuilder.handles(def):
			out.append({"name": def.id, "kind": "stop", "mission_id": def.id})
	out.append({"name": "hotel", "kind": "hotel", "floors": 2})
	out.append({"name": "pcg_master", "kind": "pcg_master"})
	out.append({"name": "road", "kind": "road"})
	if not _only_configs.is_empty():
		out = out.filter(func(c): return _only_configs.has(c.name))
	return out


func _run_all() -> Dictionary:
	var result := {"addon": _addon_info(), "seeds": _seeds, "repeat": _repeat, "runs": []}
	for cfg: Dictionary in _config_list():
		for s in _seeds:
			for rep in range(_repeat):
				_current_label = "%s/seed=%d/rep=%d" % [cfg.name, s, rep]
				var log_start := _log_sink.size()
				print("BL_SNAPSHOT begin %s" % _current_label)
				var run := _run_config(cfg, int(s))
				run["config"] = cfg.name
				run["seed"] = s
				run["rep"] = rep
				run["log"] = _summarize_log(_log_sink.slice(log_start))
				result.runs.append(run)
	return result


func _prepare_persistence(mission_id: String) -> void:
	var rp: Node = get_node("/root/RunPersistence")
	rp.set("disk_writes_enabled", false)
	var roster: Array = rp.call("company_seed_profiles")
	rp.set("_state", {"selected_mission_id": mission_id, "roster": roster})


func _new_builder() -> Node:
	var b: Node = DungeonLevelBuilder.new()
	b.name = "SnapshotBuilder"
	add_child(b)
	return b


func _run_config(cfg: Dictionary, seed: int) -> Dictionary:
	var stack: Node = get_node("/root/MissionFloorStack")
	stack.call("reset")
	var floors: Array = []
	var timings := {}
	var t := Time.get_ticks_usec()
	var io_script: Script = load("res://addons/flow_nodes_editor/flow_nodes_io.gd")
	match str(cfg.kind):
		"stop":
			_prepare_persistence(str(cfg.mission_id))
			stack.set("_seed", 0)
			stack.call("build_for_mission", seed)
			timings["floor_build_ms"] = (Time.get_ticks_usec() - t) / 1000.0
			var fallbacks: Array = stack.get("stop_build_fallbacks")
			for i in range(int(stack.call("floor_count"))):
				floors.append(stack.call("floor_data", i))
			timings["stop_build_fallbacks"] = fallbacks.size()
		"hotel":
			_prepare_persistence("")
			stack.set("_is_stop_site", false)
			stack.set("_floor_size", Vector2i(26, 20))  # MissionFloorStack.DEFAULT_FLOOR_SIZE
			stack.set("_fear_line", stack.call("_deployed_fear_line"))
			var prev_down := Vector2i(-1, -1)
			for i in range(int(cfg.floors)):
				var floor_seed: int = (seed + i * 7919) & 0x7FFFFFFF
				var fd: FloorData = stack.call("_generate_pinned_floor", floor_seed, i, prev_down)
				floors.append(fd)
				prev_down = fd.stairwell_down_pos
			timings["floor_build_ms"] = (Time.get_ticks_usec() - t) / 1000.0
		"road":
			_prepare_persistence("")
			return _run_road(seed, io_script)
		"pcg_master":
			_prepare_persistence("")
			var b := _new_builder()
			b.get("_rng").seed = seed
			var style_mark := _log_sink.size()
			var fd: FloorData = b.call("_generate_flow_node_floor_data")
			timings["pcg_master_total_ms"] = (Time.get_ticks_usec() - t) / 1000.0
			timings["room_style_ms"] = _room_times(_log_sink.slice(style_mark))
			b.queue_free()
			var floor_digest := _digest_floor(fd) if fd != null else {"null": true}
			return {"floors": [floor_digest], "timings": timings,
				"last_errors": _last_errors(io_script)}
	var digests: Array = []
	var style_total := 0.0
	var room_times: Array = []
	for fd: FloorData in floors:
		var b := _new_builder()
		var ts := Time.get_ticks_usec()
		var mark := _log_sink.size()
		b.call("_apply_room_style_graphs", fd, int(fd.rng_seed))
		style_total += (Time.get_ticks_usec() - ts) / 1000.0
		room_times.append(_room_times(_log_sink.slice(mark)))
		b.queue_free()
		digests.append(_digest_floor(fd))
	timings["style_graphs_ms"] = style_total
	timings["room_style_ms"] = room_times
	return {"floors": digests, "timings": timings, "last_errors": _last_errors(io_script)}


## The overworld road: ProceduralRoadGenerator.generate_road(seed) -> OverworldRoadNetwork.setup
## (as OverworldRoadScene._generate_and_realize does; density 0.5 = the scene default) ->
## commit every branch out of the root junction (as the truck driving each one would). Then,
## for the approach and every realized full edge, the dressing is re-evaluated with exactly the
## arguments OverworldRoadNetwork._dress_edge / _dress_approach pass, footprint-cleared the same
## way, and digested (kind | position to 3 dp | yaw | scale).
func _run_road(seed: int, io_script: Script) -> Dictionary:
	var timings := {}
	var RoadGen: Script = load("res://scripts/road/ProceduralRoadGenerator.gd")
	var NetScript: Script = load("res://scripts/road/OverworldRoadNetwork.gd")
	var Adapter: Script = load("res://scripts/road/OverworldRoadFlowAdapter.gd")
	var t := Time.get_ticks_usec()
	var gen: Dictionary = RoadGen.call("generate_road", seed)
	timings["road_generate_ms"] = (Time.get_ticks_usec() - t) / 1000.0
	var net: Node = NetScript.new()
	net.name = "SnapshotRoad"
	add_child(net)
	t = Time.get_ticks_usec()
	net.call("setup", gen, seed, 0.5)
	timings["network_setup_ms"] = (Time.get_ticks_usec() - t) / 1000.0
	var keys: Array = (net.get("edges") as Dictionary).keys()
	keys.sort()
	t = Time.get_ticks_usec()
	for k in keys:
		net.call("commit_edge", k)
	timings["commit_edges_ms"] = (Time.get_ticks_usec() - t) / 1000.0
	timings["graph_evaluations"] = int(net.get("graph_evaluations"))
	var pieces: Array = []
	var approach: Dictionary = net.get("approach")
	if not approach.is_empty():
		var pts: PackedVector3Array = approach["centerline"]
		var kinds := PackedInt32Array()
		kinds.resize(pts.size())
		var straight: int = int((load("res://scripts/road/RoadSegmentDef.gd") as Script).get_script_constant_map()["SegmentKind"]["STRAIGHT"])
		kinds.fill(straight)
		pieces.append({"key": "approach", "args": [pts, net.call("ribbon_points"), net.call("all_sockets"), float(net.get("dressing_density")), int(net.call("dressing_seed")), net.get("dressing_graph"), null, kinds, []]})
	var edges: Dictionary = net.get("edges")
	var ekeys: Array = edges.keys()
	ekeys.sort()
	for k in ekeys:
		var e: Dictionary = edges[k]
		if not bool(e.get("full", false)):
			continue
		var socks: Array = (e.get("sockets", []) as Array).filter(func(sk: Dictionary) -> bool: return str(sk.get("socket_type", "")) != "wreck")
		pieces.append({"key": str(k), "args": [e["centerline"], net.call("ribbon_points"), net.call("all_sockets"), float(net.get("dressing_density")), int(net.call("dressing_seed")), net.get("dressing_graph"), null, e.get("centerline_kinds", PackedInt32Array()), socks]})
	var rooms: Array = []
	var eval_ms := 0.0
	for pc: Dictionary in pieces:
		var te := Time.get_ticks_usec()
		var ev: Dictionary = Adapter.callv("evaluate_dressing", pc.args)
		var ms := (Time.get_ticks_usec() - te) / 1000.0
		eval_ms += ms
		var pts_out: Array = net.call("_clear_road_footprints", ev.get("points", []), false) if bool(ev.get("ok", false)) else []
		var furn_out: Array = net.call("_clear_road_footprints", ev.get("furniture", []), true) if bool(ev.get("ok", false)) else []
		var lines: Array = []
		for p: Dictionary in pts_out:
			lines.append("D|%s|%s|%s|%s" % [str(p.get("kind", "")), _road_v(p.get("position", Vector3.ZERO)), String.num(float(p.get("yaw", 0.0)), 2), String.num(float(p.get("scale", 1.0)), 3)])
		for p: Dictionary in furn_out:
			lines.append("F|%s|%s|%s|%s" % [str(p.get("kind", "")), _road_v(p.get("position", Vector3.ZERO)), String.num(float(p.get("yaw", 0.0)), 2), String.num(float(p.get("scale", 1.0)), 3)])
		lines.sort()
		var kind_counts := {}
		for l: String in lines:
			var kk: String = l.get_slice("|", 0) + ":" + l.get_slice("|", 1)
			kind_counts[kk] = int(kind_counts.get(kk, 0)) + 1
		rooms.append({"id": rooms.size(), "name": str(pc.key), "template": "", "style_id": "road", "style_graph_path": "",
			"n_props": lines.size(), "n_flow_props": lines.size(), "n_cover": 0, "n_doors": 0,
			"h_room": _h("\n".join(lines) + str(ev.get("error", ""))), "h_props": _h("\n".join(lines)), "h_cover": "", "h_doors": "", "h_ticket": "",
			"error": str(ev.get("error", "")), "ms": ms, "kind_counts": kind_counts, "props": lines})
	timings["dressing_eval_ms"] = eval_ms
	net.queue_free()
	var total := 0
	for r in rooms:
		total += int(r.n_props)
	return {"floors": [{"rng_seed": seed, "grid_size": "", "n_rooms": rooms.size(), "n_floor_cells": 0, "n_door_cells": 0,
		"n_cover_cells": 0, "n_props": total, "n_flow_props": total, "h_floor_cells": _h(_json(_canon(gen.get("edges", {}).keys()))),
		"h_room_records": "", "h_corridor_props": "", "h_fear_rooms": "", "rooms": rooms}],
		"timings": timings, "last_errors": _last_errors(io_script)}


func _road_v(v: Vector3) -> String:
	return "%s,%s,%s" % [String.num(snappedf(v.x, 0.001), 3), String.num(snappedf(v.y, 0.001), 3), String.num(snappedf(v.z, 0.001), 3)]


func _last_errors(io_script: Script) -> Variant:
	if io_script.source_code.contains("static var last_errors"):
		return _canon(io_script.get("last_errors"))
	return null


## Per-room style-graph wall time from the builder's own log lines: each styled room
## prints "    <debug_string>  seed=N" before its graph runs and "graph wrote"/"placed
## NOTHING" after.
func _room_times(lines: Array) -> Array:
	var out: Array = []
	var start_t := -1
	var start_text := ""
	for e: Dictionary in lines:
		var text: String = str(e.text)
		if e.kind == "MSG" and text.begins_with("    ") and text.contains("  seed="):
			start_t = int(e.t)
			start_text = text.strip_edges()
		elif start_t >= 0 and (text.contains("graph wrote") or text.contains("placed NOTHING")):
			out.append({"room": start_text.substr(0, 80), "ms": (int(e.t) - start_t) / 1000.0})
			start_t = -1
	return out


func _summarize_log(lines: Array) -> Dictionary:
	var errors: Array = []
	var warnings: Array = []
	var node_errs: Array = []
	for e: Dictionary in lines:
		var text: String = str(e.text)
		match str(e.kind):
			"ERROR", "SCRIPT_ERROR", "SHADER_ERROR":
				errors.append("%s: %s @ %s" % [e.kind, text, str(e.get("where", ""))])
				if text.begins_with("Node.Err"):
					node_errs.append(text)
			"WARNING":
				warnings.append("%s @ %s" % [text, str(e.get("where", ""))])
	return {"errors": errors, "warnings": warnings, "node_errors": node_errs}


## ─── Digest ──────────────────────────────────────────────────────────────────

func _digest_floor(fd: FloorData) -> Dictionary:
	var rooms: Array = []
	var total_props := 0
	var total_flow := 0
	var cover_by_room := {}
	for cell in fd.cover_cells:
		var rid := int(fd.floor_cells.get(cell, -2))
		if not cover_by_room.has(rid):
			cover_by_room[rid] = []
		cover_by_room[rid].append("%s=%s" % [_vs(cell), str(fd.cover_cells[cell])])
	var doors_by_room := {}
	for cell in fd.door_cells:
		var d: Dictionary = fd.door_cells[cell] if fd.door_cells[cell] is Dictionary else {}
		var rid := int(d.get("room_id", -2))
		if not doors_by_room.has(rid):
			doors_by_room[rid] = []
		doors_by_room[rid].append(_vs(cell) + ":" + _json(_canon(d)))
	for i in range(fd.rooms.size()):
		var room: Dictionary = fd.rooms[i]
		var props: Array = []
		var n_flow := 0
		for p in room.get("props", []):
			props.append(_json(_canon(p)))
			if p is Dictionary and str(p.get("source", "")) == "flow_graph":
				n_flow += 1
		props.sort()
		var cover: Array = cover_by_room.get(i, [])
		cover.sort()
		var doors: Array = doors_by_room.get(i, [])
		doors.sort()
		var ticket := _json(_canon(fd.room_tickets.get(i, room.get("room_ticket", ""))))
		var summary: Array = []
		for p in room.get("props", []):
			if p is Dictionary:
				# style_snapshot.gd's placement line (kind|prefab|cell|yaw to 5 deg) + source
				var r: Rect2i = p.get("rect", Rect2i()) as Rect2i
				var yaw: float = float(p.get("yaw_deg", int(p.get("rotation_steps", 0)) * 90))
				summary.append("%s|%s|%d,%d|%d|%s" % [str(p.get("kind", "")), str(p.get("scene_override", "")).get_file(),
					r.position.x, r.position.y, int(round(yaw / 5.0)) * 5, str(p.get("source", ""))])
		summary.sort()
		total_props += props.size()
		total_flow += n_flow
		rooms.append({
			"id": i,
			"name": str(room.get("name", "")),
			"template": str(room.get("template", "")),
			"style_id": str(room.get("style_id", "")),
			"style_graph_path": str(room.get("style_graph_path", "")),
			"n_props": props.size(),
			"n_flow_props": n_flow,
			"n_cover": cover.size(),
			"n_doors": doors.size(),
			"h_room": _h(_json(_canon(room))),
			"h_props": _h("\n".join(props)),
			"h_cover": _h("\n".join(cover)),
			"h_doors": _h("\n".join(doors)),
			"h_ticket": _h(ticket),
			"props": summary,
		})
	return {
		"rng_seed": fd.rng_seed,
		"grid_size": _vs(fd.grid_size),
		"n_rooms": fd.rooms.size(),
		"n_floor_cells": fd.floor_cells.size(),
		"n_door_cells": fd.door_cells.size(),
		"n_cover_cells": fd.cover_cells.size(),
		"n_props": total_props,
		"n_flow_props": total_flow,
		"h_floor_cells": _h(_json(_canon(fd.floor_cells))),
		"h_room_records": _h(_json(_canon(fd.room_records))),
		"h_corridor_props": _h(_json(_canon(fd.get_meta("corridor_props", [])))),
		"h_fear_rooms": _h(_json(_canon(fd.fear_rooms))),
		"rooms": rooms,
	}


func _prop_pos(p: Dictionary) -> String:
	for k in ["cell", "position", "pos", "rect", "world_position"]:
		if p.has(k):
			return _json(_canon(p[k]))
	return "?"


func _h(s: String) -> String:
	return s.sha256_text().substr(0, 16)


func _json(v: Variant) -> String:
	return JSON.stringify(v, "", true)


func _vs(v: Variant) -> String:
	return _json(_canon(v))


func _f(x: float) -> String:
	if is_nan(x):
		return "nan"
	var r := snappedf(x, pow(10.0, -FLOAT_DP))
	if r == 0.0:
		r = 0.0  # fold -0.0
	return String.num(r, FLOAT_DP)


## Canonical, JSON-able form: dict keys stringified + sorted (by stringify sort_keys),
## floats fixed to FLOAT_DP decimals, vectors as arrays, objects by class/path.
func _canon(v: Variant) -> Variant:
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return v
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(v)
		TYPE_FLOAT:
			return _f(v)
		TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I:
			var a: Array = []
			for i in range(4 if typeof(v) == TYPE_VECTOR4I else (3 if typeof(v) == TYPE_VECTOR3I else 2)):
				a.append(v[i])
			return a
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_QUATERNION, TYPE_COLOR:
			var n: int = {TYPE_VECTOR2: 2, TYPE_VECTOR3: 3, TYPE_VECTOR4: 4, TYPE_QUATERNION: 4, TYPE_COLOR: 4}[typeof(v)]
			var a: Array = []
			for i in range(n):
				a.append(_f(v[i]))
			return a
		TYPE_RECT2I:
			return [v.position.x, v.position.y, v.size.x, v.size.y]
		TYPE_RECT2:
			return [_f(v.position.x), _f(v.position.y), _f(v.size.x), _f(v.size.y)]
		TYPE_TRANSFORM3D, TYPE_BASIS, TYPE_AABB, TYPE_TRANSFORM2D, TYPE_PLANE:
			return str(v)
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				var ks: String = str(k) if typeof(k) == TYPE_STRING or typeof(k) == TYPE_STRING_NAME else _json(_canon(k))
				d[ks] = _canon(v[k])
			return d
		TYPE_OBJECT:
			if v == null:
				return null
			if v is Resource and not (v as Resource).resource_path.is_empty():
				return "<%s:%s>" % [(v as Object).get_class(), (v as Resource).resource_path]
			return "<%s>" % (v as Object).get_class()
		_:
			if typeof(v) >= TYPE_ARRAY:
				var a: Array = []
				for x in v:
					a.append(_canon(x))
				return a
			return str(v)
```

```text
# tools/bl_snapshot.tscn
[gd_scene format=3]

[ext_resource type="Script" path="res://tools/bl_snapshot.gd" id="1"]

[node name="BLSnapshot" type="Node"]
script = ExtResource("1")
```

## Appendix C: the other runners

### `tools/last_errors_probe.gd` (+ a .tscn like the one above; upstream addon only)

```gdscript
extends Node
## Upstream-only: every stop x seeds 11/21 through the style path of style_snapshot.gd, but
## each room's evaluation gets FlowNodeIO.start_error_log(ctx) first, so node errors land in
## FlowNodeIO.last_errors (the game's own evaluate_graph call never attaches a log).
const STOPS := ["supply_medicine", "holdout_run", "info_records", "long_way_round", "escape_run", "sabotage_altar", "supply_food"]
const SEEDS := [11, 21]

func _ready() -> void:
	get_node("/root/RunPersistence").set("disk_writes_enabled", false)
	var io: Script = load("res://addons/flow_nodes_editor/flow_nodes_io.gd")
	var total := 0
	var rooms := 0
	for stop: String in STOPS:
		for seed_v: int in SEEDS:
			var fd: FloorData = StopFloorDataBuilder.build(MissionDef.load_def(stop), seed_v)
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_v
			TacticalDecorator.new().decorate(fd, rng)
			var registry = load("res://resources/room_styles/registry.tres")
			for a in registry.build_assignments(fd, seed_v):
				if not a.has_style():
					continue
				var graph = ResourceLoader.load(a.graph_path, "", ResourceLoader.CACHE_MODE_IGNORE)
				BLRoomStyleRuntime.bind_room_filter(graph, a.room_id)
				var root = load("res://addons/flow_nodes_editor/flow_node.gd").new()
				add_child(root)
				var fdd := FlowData.Data.new()
				var rva: Array[Resource] = [fd]
				fdd.registerStream("FloorData", rva, FlowData.DataType.Resource)
				var ctx := FlowData.EvaluationContext.new()
				ctx.owner = root
				ctx.eval_id = a.style_seed
				ctx.graph = graph
				ctx.runtime_params = {"room_id": a.room_id, "style_seed": a.style_seed}
				io.call("start_error_log", ctx)
				io.call("evaluate_graph", graph, {"FloorData": fdd}, ctx, ctx.runtime_params)
				var errs: Array = io.get("last_errors")
				rooms += 1
				total += errs.size()
				for e in errs:
					print("LAST_ERROR %s@%d room %d %s: %s" % [stop, seed_v, a.room_id, str(a.graph_path).get_file(), str(e)])
				root.queue_free()
	print("LAST_ERRORS_PROBE rooms=%d errors=%d" % [rooms, total])
	get_tree().quit()
```

### `tools/stop_suite_runner.gd` (+ .tscn) — StopSiteRegression headless

```gdscript
extends Node
## Runs scripts/testing/StopSiteRegression.gd headless and prints its result.
func _ready() -> void:
	get_node("/root/RunPersistence").set("disk_writes_enabled", false)
	await get_tree().process_frame
	var suite: Node = load("res://scripts/testing/StopSiteRegression.gd").new()
	add_child(suite)
	var r: Dictionary = suite.run()
	print("STOP_SUITE ok=%s count=%s failures=%d" % [str(r.get("ok")), str(r.get("count")), (r.get("failures", []) as Array).size()])
	for f in r.get("failures", []):
		print("STOP_SUITE_FAIL %s" % str(f))
	get_tree().quit()
```

### `tools/parse_all.gd` — compile every script (`--script`, set `PARSE_ALL_TRACE=1` to print each file)

```gdscript
## Loads (compiles) every .gd under res:// except .godot/ — parse errors are printed by the
## engine as "SCRIPT ERROR: Parse Error" / "Failed to load script". Prints PARSE_ALL <n> at the end.
extends SceneTree

func _initialize() -> void:
	var files: Array = []
	_walk("res://", files)
	files.sort()
	var failed := 0
	for f: String in files:
		if OS.get_environment("PARSE_ALL_TRACE") == "1":
			print("LOADING %s" % f)
		var s = ResourceLoader.load(f, "", ResourceLoader.CACHE_MODE_REUSE)
		if s == null or (s is GDScript and not (s as GDScript).can_instantiate() and not (s as GDScript).is_abstract()):
			failed += 1
			print("PARSE_FAIL %s" % f)
	print("PARSE_ALL %d scripts, %d failed" % [files.size(), failed])
	quit(0)

func _walk(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for sub in d.get_directories():
		if sub.begins_with("."):
			continue
		_walk(dir_path.path_join(sub), out)
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
```

### Bisection helpers (Python 3, run against a SCRATCH copy only)

```python
# set_flag.py
#!/usr/bin/env python3
"""set_flag.py <project> <graph glob relative to project> <template> <setting> <gdscript literal>
Adds "<setting>": <literal> to the settings dict of every node of <template> in the matched
.tres graphs (a scratch-copy bisection helper; never run it on a real checkout)."""
import sys, glob, re
proj, pattern, template, setting, lit = sys.argv[1:6]
total = 0
for p in sorted(glob.glob(proj + "/" + pattern, recursive=True)):
    lines = open(p).read().split("\n")
    pat = re.compile(r'^"template": &?"%s"$' % re.escape(template))
    idxs = [i for i, l in enumerate(lines) if pat.match(l.strip())]
    for i in reversed(idxs):
        j = i
        while j >= 0 and lines[j] != '"settings": {':
            j -= 1
        assert j >= 0, p
        lines.insert(j + 1, '"%s": %s,' % (setting, lit))
    if idxs:
        open(p, "w").write("\n".join(lines))
        print("  %s: %d node(s)" % (p.split(proj + "/")[1], len(idxs)))
        total += len(idxs)
print("set %s=%s on %d %s node(s)" % (setting, lit, total, template))
```

```python
# toggle_graphs.py
#!/usr/bin/env python3
"""Rewrite Black Lantern kit graphs in a scratch copy for the bisection experiments.
usage: toggle_graphs.py <project> drop_seed_workaround|legacy_global_rng
  drop_seed_workaround: the kit's `seed = hash(position)` Expression nodes write `seed_ws`
      instead of `seed`, so Match And Set sees no seed stream (what deleting the game's
      workaround would do).
  legacy_global_rng: every match_and_set node in graphs/styles/kit gets
      "legacy_global_rng": true in its settings dict (upstream's opt-out of c981656)."""
import sys, glob, re
proj, mode = sys.argv[1], sys.argv[2]
n = 0
for p in sorted(glob.glob(proj + "/graphs/styles/kit/*.tres")):
    s = open(p).read()
    o = s
    if mode == "drop_seed_workaround":
        s, k = re.subn(r'("expression": "hash\(position\)",\n"out_name": )"seed",', r'\1"seed_ws",', s)
        n += k
    elif mode == "legacy_global_rng":
        lines = s.split("\n")
        idxs = [i for i, l in enumerate(lines) if l.strip() == '"template": &"match_and_set"']
        for i in reversed(idxs):
            j = i
            while j >= 0 and lines[j] != '"settings": {':
                j -= 1
            assert j >= 0
            lines.insert(j + 1, '"legacy_global_rng": true,')
            n += 1
        s = "\n".join(lines)
    if s != o:
        open(p, "w").write(s)
        print("rewrote", p.split("/")[-1])
print(mode, "edits:", n)
```

```python
# cmp_snap.py — compare two style_snapshot JSONs (room hash by room)
import json,sys
a=json.load(open(sys.argv[1]))["stops"]; b=json.load(open(sys.argv[2]))["stops"]
same=chg=0; rows=[]
for k in b:
    ra=a.get(k,{}).get("rooms",{}); rb=b[k]["rooms"]
    for r in rb:
        if r not in ra: rows.append((k,r,"NEW",rb[r]["style"],None,rb[r]["props"],None,rb[r]["things"])); chg+=1
        elif ra[r]["hash"]!=rb[r]["hash"]: rows.append((k,r,"CHG",rb[r]["style"],ra[r]["props"],rb[r]["props"],ra[r]["things"],rb[r]["things"])); chg+=1
        else: same+=1
    for r in ra:
        if r not in rb: rows.append((k,r,"GONE",ra[r]["style"],ra[r]["props"],None,ra[r]["things"],None)); chg+=1
for r in rows: print(*r, sep=" | ")
print(f"unchanged {same}, changed {chg}")
```

```python
# cmp_dig.py — compare two bl_snapshot digests (A B [rep])
import json,sys
from collections import defaultdict
def load(p):
    d=json.load(open(p)); out={}
    for r in d["runs"]:
        out[(r["config"],r["seed"],r["rep"])]=r
    return d,out
HK=["h_room","h_props","h_cover","h_doors","h_ticket","style_graph_path","n_props"]
FK=["h_floor_cells","h_room_records","h_corridor_props","h_fear_rooms","n_rooms","n_props","n_cover_cells","n_door_cells"]
def cmp_runs(ra,rb,tag):
    diffs=[]; same=0
    for fi,(fa,fb) in enumerate(zip(ra["floors"],rb["floors"])):
        for k in FK:
            if fa.get(k)!=fb.get(k): diffs.append((tag,fi,"FLOOR",k,fa.get(k),fb.get(k)))
        for rma,rmb in zip(fa.get("rooms",[]),fb.get("rooms",[])):
            dk=[k for k in HK if rma.get(k)!=rmb.get(k)]
            if dk:
                pa=set(rma["props"]); pb=set(rmb["props"])
                diffs.append((tag,fi,rma["id"],rma["name"],dk,rma["n_props"],rmb["n_props"],sorted(pa-pb)[:6],sorted(pb-pa)[:6]))
            else: same+=1
    if len(ra["floors"])!=len(rb["floors"]): diffs.append((tag,"floorcount",len(ra["floors"]),len(rb["floors"])))
    return same,diffs
a_meta,A=load(sys.argv[1]); b_meta,B=load(sys.argv[2])
print("A addon",a_meta["addon"]); print("B addon",b_meta["addon"])
mode=sys.argv[3] if len(sys.argv)>3 else "cross"
tot_same=0; tot_d=[]
for key in sorted(A):
    cfg,seed,rep=key
    if mode=="rep":  # within-file rep0 vs rep1
        if rep!=0: continue
        s,d=cmp_runs(A[key],A[(cfg,seed,1)],f"{cfg}@{seed} rep0/rep1")
    else:
        if key not in B: continue
        s,d=cmp_runs(A[key],B[key],f"{cfg}@{seed} r{rep}")
    tot_same+=s; tot_d+=d
for d in tot_d: print(d)
print(f"rooms identical {tot_same}, differing entries {len(tot_d)}")
# errors
for nm,M in (("A",A),("B",B)):
    ec=sum(len(r["log"]["errors"]) for r in M.values()); wc=sum(len(r["log"]["warnings"]) for r in M.values())
    le=[r["last_errors"] for r in M.values() if r["last_errors"]]
    print(nm,"errors",ec,"warnings",wc,"nonempty last_errors",len(le))
wa=defaultdict(int); wb=defaultdict(int)
for r in A.values():
    for w in r["log"]["warnings"]+r["log"]["errors"]: wa[w.split(" @ ")[0][:160]]+=1
for r in B.values():
    for w in r["log"]["warnings"]+r["log"]["errors"]: wb[w.split(" @ ")[0][:160]]+=1
for w in sorted(set(wa)|set(wb)):
    if wa[w]!=wb[w]: print("LOGDIFF A=%d B=%d %s"%(wa[w],wb[w],w))
```

```python
# road_cmp.py — road pieces, per kind counts (A B [v])
import json,sys
def L(p): return {(r["config"],r["seed"]):r for r in json.load(open(p))["runs"] if r["rep"]==0}
A=L(sys.argv[1]); B=L(sys.argv[2]); verbose=len(sys.argv)>3
tot_same=tot=0
for k in sorted(A):
    fa=A[k]["floors"][0]; fb=B[k]["floors"][0]
    for ra,rb in zip(fa["rooms"],fb["rooms"]):
        tot+=1
        if ra["h_props"]==rb["h_props"]: tot_same+=1; continue
        pa=set(ra["props"]); pb=set(rb["props"])
        kc=set(ra["kind_counts"])|set(rb["kind_counts"])
        d={c:(ra["kind_counts"].get(c,0),rb["kind_counts"].get(c,0)) for c in sorted(kc) if ra["kind_counts"].get(c,0)!=rb["kind_counts"].get(c,0)}
        print(k[1], ra["name"], ra["n_props"],"->",rb["n_props"], d, "onlyA",len(pa-pb),"onlyB",len(pb-pa))
        if verbose:
            for x in sorted(pa-pb)[:15]: print("    -",x)
            for x in sorted(pb-pa)[:15]: print("    +",x)
print("edges identical %d/%d" % (tot_same,tot))
```

## Appendix D: exact commands (to rerun on another tree, e.g. the unpushed one)

```bash
BL=/home/user/black-lantern-tactics         # any clone that has the commit to test
REV=05e473af                                # or your unpushed HEAD
UP=/home/user/GF-PCGODOT/demo/addons/flow_nodes_editor
S=/path/to/scratch
G=godot47                                   # Godot 4.7.1; use the same binary for both copies

# 1. two copies of the game
git -C $BL worktree add --detach $S/bl_vendored $REV
git -C $BL worktree add --detach $S/bl_upstream $REV

# 2. the same native library in both (the sources in native/src are identical)
for d in bl_vendored bl_upstream; do
  cp $UP/bin/libflow.linux.template_debug.x86_64.so $S/$d/addons/flow_nodes_editor/bin/
done
sed -i 's|^\[libraries\]$|[libraries]\nlinux.x86_64 = "res://addons/flow_nodes_editor/bin/libflow.linux.template_debug.x86_64.so"|' \
  $S/bl_vendored/addons/flow_nodes_editor/bin/flow.gdextension

# 3. the sync (docs/FLOW_UPSTREAM_SYNC.md §4): status, then copy upstream over ours without *.uid
bash $S/bl_vendored/tools/graph_gen/flow_upstream_status.sh /home/user/GF-PCGODOT claude/pcg-system-review-4tpca9
(cd $UP && tar cf - --exclude='*.uid' --exclude='*.os' .) | (cd $S/bl_upstream/addons/flow_nodes_editor && tar xf -)

# 4. tools of this run
for d in bl_vendored bl_upstream; do cp bl_snapshot.gd bl_snapshot.tscn stop_suite_runner.* parse_all.gd $S/$d/tools/; done
cp last_errors_probe.* $S/bl_upstream/tools/

# 5. import + errors (deliverable 1)
for d in bl_vendored bl_upstream; do
  (cd $S/$d && $G --headless --path . --import > $S/imp_$d.log 2>&1)
  grep -aE "SCRIPT ERROR|Parse Error" $S/imp_$d.log
  (cd $S/$d && $G --headless --path . -s res://tools/parse_all.gd > $S/parse_$d.log 2>&1); grep -a "PARSE_" $S/parse_$d.log
done

# 6. determinism, then the cross-addon diff (deliverable 2)
cd $S/bl_vendored
$G --headless --path . tools/graph_gen/style_snapshot.tscn -- --out=res://output/v1.json
$G --headless --path . tools/graph_gen/style_snapshot.tscn -- --out=res://output/v2.json
python3 cmp_snap.py output/v1.json output/v2.json                    # expect 177 unchanged
$G --headless --path . res://tools/bl_snapshot.tscn -- --out=$S/dig_v.json --repeat=2
python3 cmp_dig.py $S/dig_v.json $S/dig_v.json rep                   # rep0 == rep1
cd $S/bl_upstream
$G --headless --path . tools/graph_gen/style_snapshot.tscn -- --out=res://output/u1.json
$G --headless --path . res://tools/bl_snapshot.tscn -- --out=$S/dig_u.json --repeat=2
python3 cmp_snap.py $S/bl_vendored/output/v1.json output/u1.json
python3 cmp_dig.py $S/dig_v.json $S/dig_u.json
python3 road_cmp.py $S/dig_v.json $S/dig_u.json v                    # road pieces, kinds, only-in-A/B

# 7. regenerate the kit (FLOW_UPSTREAM_SYNC.md §4.4), then snapshot again
$G --headless --path . tools/graph_gen/bake_surfaces.tscn     # expect "normals as sampled" x45
$G --headless --path . tools/graph_gen/gen_room_families.tscn
git status --short graphs data tools/graph_gen                # surface_points.json must be unchanged
$G --headless --path . tools/graph_gen/style_snapshot.tscn -- --out=res://output/u_regen.json --compare=res://output/u1.json

# 8. bisection (scratch copies only; restore with git checkout -- graphs / the backed-up node file)
python3 set_flag.py $S/bl_upstream "graphs/road/**/*.tres" sample_spline legacy_scale_from_extent true
python3 toggle_graphs.py $S/bl_upstream drop_seed_workaround
python3 toggle_graphs.py $S/bl_upstream legacy_global_rng
$G --headless --path . res://tools/bl_snapshot.tscn -- --out=$S/road_x.json --configs=road --seeds=11

# 9. suites, and last_errors (deliverable 3)
$G --headless --path . res://tools/stop_suite_runner.tscn | grep STOP_SUITE
$G --headless --path . --script res://scripts/testing/OverworldRoadRegression.gd | grep OVERWORLD_ROAD_RESULT
$G --headless --path . --script res://scripts/testing/HeadlessSuite.gd | grep -E "^SUITE"
$G --headless --path . res://tools/last_errors_probe.tscn | grep LAST_ERROR     # upstream copy only
```

`bl_snapshot` options: `--out=<abs path>`, `--seeds=11,21`, `--configs=<mission ids>,hotel,pcg_master,road`,
`--repeat=N`. A run of every configuration at two seeds and two repeats takes about 95 s without the road and about
6 minutes for the road at seeds 11 and 21. `style_snapshot` takes about 50 s.

**Artefacts from this run** are in the scratch directory: `dig_{vendored,upstream}_{a,b}.json`,
`dig_upstream_regen.json`, `dig_{vendored,upstream}_road.json`, `road_*.json` (bisection),
`bl_*/output/snap_*.json`, `upstream_regen.patch` (what `gen_room_families` changed), and every `*.log` quoted above.
