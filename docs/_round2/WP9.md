# WP9: purity and thread-safety conformance harness

Status: implemented on the WP9 worktree branch. No node script and no `FlowNodeTraits` row was changed. The golden suite and the seed-zero suite are untouched.

## Summary

- **A generic node conformance harness** (`demo/tests/executor/conformance/`) drives every registered stock template (164) through `FlowExecutor.execute_node`, the evaluator's own per-node entry point. Inputs come from synthetic source elements, and the evaluation context is the one the executor builds (graph seed 1337, error log meta, cache meta).
- **Checks 1 to 4 fail the build. Every one passes for every template.** The checks are input mutation, determinism, worker-thread equivalence and cache equivalence. The run covers 2,201 fixture cases.
- **Check 5, the static traits scan, finds no required-API hit in any threadable template.** It only reports; it never fails the build. Every hit it lists is for review, and none needs a traits change.
- **No traits downgrade was needed.** One traits inconsistency could not be fixed with a row, because `meta_node` wins over the table: `bounds_from_mesh`. See "Traits inconsistencies".
- **Two genuine node bugs and one executor hazard were found**, listed under "Bugs found":
  - `dungeon_connect_rooms`: a script error;
  - `points_from_imported_scene` / `load_alembic_file`: wrong transforms;
  - threaded mode: helper errors printed from pool threads crash a non-thread-safe script `Logger`.
- The suite takes 17 to 24 s inside GdUnit on the shared 4-core container (19 to 23 s for the report tool) and is deterministic.

## How the harness works

| File | Role |
|---|---|
| `conformance_fixtures.gd` | Fixture library. Every builder is a pure function: two calls give two distinct Data objects with equal content. |
| `conformance_harness.gd` | Drives one template: builds the element, its sources and its context, runs it in each mode, fingerprints the outputs and compares them. It also captures script errors with a thread-safe `Logger`. |
| `conformance_overrides.gd` | Per-template override table: settings, fixtures, settings variants, owner mode, known bugs, skips and notes. |
| `conformance_static_scan.gd` | Check 5. A heuristic source scan with guard classification. |
| `conformance_report.gd` | Runs the matrix and renders the Markdown below. |
| `node_conformance_test.gd` | The GdUnit suite (11 cases). It runs the matrix once in `before()`. |
| `conformance_harness_test.gd` | Self-test (16 cases). Fixtures, case pairing, digests and the static scan. Every check is shown to catch a deliberately broken fake node (`fakes/conformance_fake_node.gd`, in a `.gdignore`'d folder). |
| `tools/conformance_report.gd` | A headless script, not a test, that prints this report. |
| `data/` | A CSV and a JSON file for `load_data_table` and `load_pcg_data_asset` (`.gdignore`'d, so Godot does not import the CSV as a translation). |

### Fixtures

The primary fixtures (input port 0) are:
- `points`: 12 points with every canonical stream (`position`, `rotation`, `size`, `density`, `seed`, `normal`, `bounds_min`, `bounds_max`, `steepness`) and one attribute of every `DataType`. That is Bool, Int, Float, Vector, String, Color, Quaternion, Resource (a shared `ArrayMesh`), Vector2, Vector4, Transform, Int64 and Double.
- `single`: the same schema with 1 point.
- `empty`: `Data.new()`.
- `empty_schema`: the full schema with 0 rows.
- `tagged`: points with two tags.
- `data_attrs`: points with five per-data (`@data`) attributes.
- `attr_set`: `Kind.AttrSet`, attributes only, no position.
- One Data per shape class, each with 0 points: `spline` (`FlowSplineShape`), `surface_polygon`, `surface_heightfield`, `surface_mesh`, `volume_box`, `volume_sphere`, and `composite` (box minus sphere). Together they cover the Spline, Surface and Volume kinds.

Templates with two or more inputs get a second input on every other port. `points_b` (8 points, offset) is paired with every primary fixture. Then `points` (same size), `empty`, `attr_set` and `volume_box` are each paired with `points`.

The override table adds `dungeon_rooms` and `dungeon_cells`, plus two fixtures that reference the owner scene: `scene_meshes` (what `scan_meshes` emits) and `scene_paths` (what `scan_splines` emits).

The **owner** is a `Node3D` in the running `SceneTree`. It holds a `Path3D`, a `MeshInstance3D` and a static body with a box collision shape. Spawners spawn into it, and it is freed after each template. Only `debug` runs owner-less.

### Checks

For every case the harness runs the element:
- twice on the main thread;
- for threadable templates, as a concurrent batch of 3 elements in one `WorkerThreadPool` group task. This is what a threaded-mode wave does, with the same main-thread prewarm of Curve and Gradient settings.
- for cacheable templates, cold and then warm through `FlowOutputCache`. The settings key is computed once per template, as `FlowExecutor.build_state` does.

Each run gets fresh fixtures. The checks are:

1. **Mutation.** The `content_hash()` of every input is unchanged after every run, and so is a content digest that also walks unsaved resources referenced by the input.
2. **Determinism.** Run 1 equals run 2, outputs and error messages in order.
3. **Thread.** Each of the 3 worker results equals main-thread run 1.
4. **Cache.** Cold equals uncached, and warm (a hit) equals uncached, errors included. The suite also asserts that every warm run is a hit, because a miss would mean the hit path was never compared.

Outputs are compared by `outputs_fingerprint()`. It covers every bulk and port, and every Data digested by content: streams, tags, per-data attributes, kind and shape hash. Unsaved resources are digested by their stored properties, not their identity, so a node that builds an equal resource on every run still counts as deterministic.

The suite also fails on a **SCRIPT ERROR inside node code** and on stale override rows.

### Static scan (check 5)

The scan reads every threadable template's script and the local scripts it extends, with comments and string contents removed. It flags references to:
- the required APIs: `get_tree`, `ctx.owner`, `ctx.variables`, `ctx.runtime_params`, `RenderingServer`, `PhysicsServer3D`, `ResourceLoader`, `EditorInterface` and the editor helpers, `Engine.get_main_loop`;
- extra hazards: `load()`, `static var`, the global RNG, `global_transform`, `get_viewport`, the physics space state, `FileAccess`, `DirAccess` or `ProjectSettings`, and writes into settings or into resources the settings reference.

Each hit is classified as guarded when an enclosing `if`/`elif`, or a same-line conditional, looks like a guard (an editor hint, a null or validity check, a trace flag).

### Running it

From `demo/`:

```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/executor/conformance
godot --headless --path . -s res://tests/executor/conformance/tools/conformance_report.gd [-- --only=grid,merge --out=/tmp/wp9.md --include-known-bugs]
```

To add a node: give it its traits row as usual. The harness picks it up automatically. If its defaults only reach an error path, add an override row with settings or fixtures that make it do real work.

## Per-template results

Columns:
- **Traits**: `pure` means threadable and cacheable; `threadable` means threadable and not cacheable; `main` means main thread. `(meta)` marks traits that come from `meta_node`.
- **Fixtures**: the cases run, settings variants included.
- **Worked**: cases that produced non-empty output without an error.
- **4 Cache**: shows how many warm runs hit.
- **5 Static scan**: required-API hits in threadable templates. `n/a (main)` means the template is main-thread, so it is not scanned.

The table, failures, script errors, console errors and static findings below come from `tools/conformance_report.gd` on this branch. The known-bug case is left out (`dungeon_connect_rooms` on `attr_set`, see "Bugs found").

Templates: 164. Fixture cases: 2201. Check results: 551 pass, 0 fail, 105 skip. Wall time 23.0 s.
Slowest templates: `sample_points` 1609 ms, `difference` 1574 ms, `math_op` 1023 ms, `select_multi` 431 ms, `boolean` 345 ms.

| Template | Traits | Fixtures | Worked | 1 Mutation | 2 Determinism | 3 Thread | 4 Cache | 5 Static scan | Notes |
|---|---|---|---|---|---|---|---|---|---|
| `add_attribute` | pure | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `add_tags` | pure | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `apply_on_actor` | main | 3 | 1 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `apply_scale_to_bounds` | pure (meta) | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `assets` | pure | 1 | 0 | pass | pass | pass | pass (1/1 hit) | clean | no assets configured: emits an empty Data |
| `attribute_cast` | pure | 14 | 11 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `attribute_filter_range` | pure | 14 | 7 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `attribute_noise` | pure | 42 | 36 | pass | pass | pass | pass (42/42 hit) | clean |  |
| `attribute_random` | pure | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `attribute_remove_duplicates` | pure | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `attribute_rename` | pure | 14 | 5 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `attribute_select` | pure | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `attribute_set_to_point` | pure | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `attribute_string_op` | pure | 18 | 16 | pass | pass | pass | pass (18/18 hit) | clean |  |
| `bitwise_op` | pure | 18 | 7 | pass | pass | pass | pass (18/18 hit) | clean |  |
| `boolean` | pure | 18 | 6 | pass | pass | pass | pass (18/18 hit) | clean |  |
| `bounds_from_mesh` | pure (meta) | 14 | 4 | pass | pass | pass | pass (14/14 hit) | clean | reads the per-point Mesh attribute (ArrayMesh.get_aabb) on the worker thread |
| `bounds_modifier` | pure | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `branch` | pure | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `break_transform_attribute` | pure | 14 | 7 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `build_rotation_from_up` | pure | 14 | 4 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `clip_paths` | main | 16 | 10 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `clip_points_by_polygon` | main | 18 | 9 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `combine_points` | pure | 14 | 4 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `compare_op` | pure | 18 | 10 | pass | pass | pass | pass (18/18 hit) | clean |  |
| `compose_vector` | pure | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `compute_kernel` | main | 14 | 7 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) | no RenderingDevice headless: error path only |
| `copy` | pure | 18 | 9 | pass | pass | pass | pass (18/18 hit) | clean |  |
| `copy_attribute` | pure | 18 | 8 | pass | pass | pass | pass (18/18 hit) | clean |  |
| `copy_points` | pure | 18 | 9 | pass | pass | pass | pass (18/18 hit) | clean |  |
| `create_points` | main | 1 | 1 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `create_spline` | main | 14 | 4 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `create_surface_from_polygon` | pure | 14 | 3 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `create_surface_from_spline` | main | 15 | 2 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `create_target_node` | main (meta) | 14 | 14 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `curve_remap_density` | pure | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `data_table_row_to_attribute_set` | pure | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `debug` | main | 14 | 12 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) | owner-less. owner-less: the debug draw side effect needs the editor |
| `decompose_vector` | pure | 14 | 4 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `delete_tags` | pure | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `density_filter` | pure | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `density_remap` | pure | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `difference` | pure | 90 | 72 | pass | pass | pass | pass (90/90 hit) | clean |  |
| `discard_points_on_irregular_surface` | pure (meta) | 14 | 11 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `distance` | pure | 18 | 14 | pass | pass | pass | pass (18/18 hit) | clean |  |
| `distance_to_density` | pure | 14 | 4 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `dungeon_connect_rooms` | pure | 13 | 3 | pass | pass | pass | pass (13/13 hit) | clean |  |
| `dungeon_expand_rooms` | pure | 4 | 1 | pass | pass | pass | pass (4/4 hit) | clean |  |
| `dungeon_generator` | pure | 1 | 1 | pass | pass | pass | pass (1/1 hit) | clean |  |
| `dungeon_room_candidates` | pure | 1 | 1 | pass | pass | pass | pass (1/1 hit) | clean |  |
| `dungeon_walls_and_doors` | pure | 4 | 1 | pass | pass | pass | pass (4/4 hit) | clean |  |
| `duplicate_point` | pure | 14 | 4 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `expression` | pure | 14 | 7 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `filter` | pure | 18 | 8 | pass | pass | pass | pass (18/18 hit) | clean |  |
| `filter_data_by_attribute` | pure | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `filter_data_by_index` | threadable | 14 | 12 | pass | pass | pass | skip: not cacheable | clean |  |
| `filter_data_by_tag` | pure | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `filter_data_by_type` | pure | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `find_convex_hull_2d` | pure (meta) | 14 | 11 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `gather` | pure | 18 | 16 | pass | pass | pass | pass (18/18 hit) | clean |  |
| `get_attribute_from_point_index` | pure (meta) | 14 | 5 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `get_bounds` | pure | 14 | 11 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `get_data_count` | pure | 14 | 14 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `get_entries_count` | pure | 14 | 14 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `get_loop_index` | pure | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `get_points_count` | pure | 14 | 14 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `get_property_from_object_path` | main (meta) | 1 | 1 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `get_spline_data` | main | 1 | 1 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `get_surface_data` | main | 1 | 1 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `get_variable` | main | 1 | 1 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `get_volume_data` | main | 1 | 1 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `grammar_expand` | pure | 14 | 4 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `grid` | pure | 1 | 1 | pass | pass | pass | pass (1/1 hit) | clean |  |
| `grid_boundary` | pure | 14 | 4 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `grid_connect_points` | pure | 14 | 4 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `grid_fill_bounds` | pure | 14 | 4 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `grid_size` | main | 14 | 12 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `input` | main | 1 | 0 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) | graph boundary: fed by the evaluator from the owner's args; covered by the evaluator suites |
| `intersection` | pure | 18 | 10 | pass | pass | pass | pass (18/18 hit) | clean |  |
| `load_alembic_file` | main | 1 | 1 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) | samples a stock demo asset (kaykit torch) |
| `load_data_table` | threadable | 1 | 1 | pass | pass | pass | skip: not cacheable | clean | reads tests/executor/conformance/data/conformance_table.csv |
| `load_pcg_data_asset` | threadable | 1 | 1 | pass | pass | pass | skip: not cacheable | clean | reads tests/executor/conformance/data/conformance_asset.json |
| `loop` | main | 14 | 5 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `make_bounds` | pure | 1 | 1 | pass | pass | pass | pass (1/1 hit) | clean |  |
| `make_transform_attribute` | pure | 14 | 11 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `make_vector` | pure | 1 | 1 | pass | pass | pass | pass (1/1 hit) | clean |  |
| `match_and_set` | pure | 18 | 16 | pass | pass | pass | pass (18/18 hit) | clean |  |
| `math_op` | pure | 72 | 18 | pass | pass | pass | pass (72/72 hit) | clean |  |
| `merge` | pure | 14 | 5 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `merge_attributes` | pure | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `merge_points` | pure | 14 | 5 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `mesh_sampler` | main | 3 | 1 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `mutate_seed` | pure | 14 | 11 | pass | pass | pass (13/14 batched) | pass (14/14 hit) | clean |  |
| `navigation_region_sampler` | main | 1 | 0 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) | no NavigationRegion3D in the fixture scene: empty-output path only |
| `noise` | pure | 28 | 22 | pass | pass | pass | pass (28/28 hit) | clean |  |
| `normal_to_density` | pure | 14 | 11 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `output` | threadable | 1 | 0 | pass | pass | pass | skip: not cacheable | clean | graph boundary: has no output port, it only forwards its input to the evaluator |
| `partition` | pure | 14 | 5 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `physics_overlap_query` | main | 14 | 11 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) | headless physics space is never stepped: queries see no bodies |
| `physics_shape_sweep` | main | 14 | 11 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) | headless physics space is never stepped: queries see no bodies |
| `point_filter_range` | pure | 14 | 11 | pass | pass | pass (13/14 batched) | pass (14/14 hit) | clean |  |
| `point_from_mesh` | main | 3 | 1 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `point_from_player_pawn` | main | 1 | 0 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) | no camera or player group in the fixture scene: error path only |
| `point_neighborhood` | pure | 14 | 7 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `point_offsets` | pure | 14 | 4 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `point_to_attribute_set` | pure | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `points_from_gridmap` | main | 1 | 0 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) | no GridMap in the fixture scene: empty-output path only |
| `points_from_imported_scene` | main | 1 | 1 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) | samples a stock demo asset (kaykit torch) |
| `points_from_scene` | main | 1 | 1 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `points_from_tilemap` | main | 1 | 0 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) | no TileMap in the fixture scene: empty-output path only |
| `polygon_operation` | main | 18 | 9 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `print_string` | main | 14 | 12 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `projection` | main | 14 | 11 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) | physics mode (default): headless physics space is never stepped |
| `random_color` | pure | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `ray_cast` | main | 14 | 4 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) | headless physics space is never stepped: queries see no bodies |
| `reduce` | pure | 14 | 5 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `relax` | pure | 14 | 4 | pass | pass | pass (5/14 batched) | pass (14/14 hit) | clean |  |
| `remap` | pure | 14 | 4 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `remove_attribute` | pure | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `replace_tags` | pure | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `reroute` | threadable | 14 | 12 | pass | pass | pass | skip: not cacheable | clean |  |
| `reset_point_center` | pure (meta) | 14 | 11 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `rotator_op` | pure | 14 | 4 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `runtime_quality_branch` | main (meta) | 14 | 12 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `runtime_quality_select` | main (meta) | 18 | 16 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `sample_mesh` | main | 3 | 1 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `sample_points` | pure | 56 | 16 | pass | pass | pass | pass (56/56 hit) | clean |  |
| `sample_spline` | main | 15 | 2 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `sample_terrain_layers` | main | 14 | 11 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `sanity_check` | pure | 14 | 4 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `scan_meshes` | main | 1 | 1 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `scan_nodes` | main | 1 | 1 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `scan_splines` | main | 1 | 1 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `select` | pure | 18 | 16 | pass | pass | pass | pass (18/18 hit) | clean |  |
| `select_multi` | pure | 18 | 16 | pass | pass | pass | pass (18/18 hit) | clean |  |
| `select_points` | pure | 14 | 11 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `self_pruning` | pure | 28 | 8 | pass | pass | pass | pass (28/28 hit) | clean |  |
| `sequence_sample` | pure | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `set_variable` | main | 14 | 12 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `size` | pure | 14 | 14 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `snap_to_grid` | pure | 14 | 4 | pass | pass | pass (5/14 batched) | pass (14/14 hit) | clean |  |
| `sort` | pure | 14 | 5 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `spawn_meshes` | main | 14 | 11 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) | spawns MultiMeshInstance3D under the fixture owner |
| `spawn_nodes` | main | 14 | 11 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) | spawns OmniLight3D under the fixture owner |
| `spawn_scenes` | main | 14 | 11 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) | spawns a packed Node3D under the fixture owner |
| `spawn_spline_mesh` | main (meta) | 4 | 2 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `split_points` | pure (meta) | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `split_splines` | main | 4 | 1 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `subdivide_segment` | main | 4 | 1 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `subgraph` | main | 14 | 12 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `substract` | pure | 18 | 13 | pass | pass | pass | pass (18/18 hit) | clean |  |
| `surface_sampler` | main | 28 | 14 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `switch` | pure | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `tags_mutate` | pure | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `texture_sampler` | main | 14 | 11 | pass | pass | skip: main-thread template | skip: not cacheable | n/a (main) |  |
| `to_point` | pure | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `transform` | pure | 14 | 4 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `transform_op` | pure | 18 | 7 | pass | pass | pass | pass (18/18 hit) | clean |  |
| `transform_points` | pure | 14 | 4 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `trig_op` | pure | 18 | 15 | pass | pass | pass | pass (18/18 hit) | clean |  |
| `union` | pure | 18 | 16 | pass | pass | pass | pass (18/18 hit) | clean |  |
| `vector_op` | pure | 18 | 7 | pass | pass | pass | pass (18/18 hit) | clean |  |
| `volume_sampler` | pure | 14 | 10 | pass | pass | pass | pass (14/14 hit) | clean |  |
| `weighted_point_sampler` | pure (meta) | 14 | 12 | pass | pass | pass | pass (14/14 hit) | clean |  |

### Failures

None.

### Skipped templates

None.

### Script errors raised inside node code (bugs)

None.

### Cases left out as known bugs

- `dungeon_connect_rooms`: attr_set (known bug: dungeon_connect_rooms.gd:51 indexes the position stream of an input with 2+ rows and no position stream (SCRIPT ERROR))

### Errors printed outside setError (missing from FlowNodeIO.last_errors)

- `load_alembic_file` (none): nodes/points_from_imported_scene.gd:19: Condition "!is_inside_tree()" is true. Returning: Transform3D()
- `point_filter_range` (attr_set): flow_data.gd:871: Failed to find stream root position
- `points_from_imported_scene` (none): nodes/points_from_imported_scene.gd:19: Condition "!is_inside_tree()" is true. Returning: Transform3D()
- `relax` (empty, attr_set, spline, surface_polygon, surface_heightfield, surface_mesh, volume_box, volume_sphere, composite): flow_data.gd:995: cloneStream: Data does not have a stream named position
- `snap_to_grid` (empty, attr_set, spline, surface_polygon, surface_heightfield, surface_mesh, volume_box, volume_sphere, composite): flow_data.gd:995: cloneStream: Data does not have a stream named position

### Templates that never produced output without an error

- `assets`: empty output
- `input`: empty output
- `navigation_region_sampler`: empty output
- `output`: empty output
- `point_from_player_pawn`: No player/source Node3D found
- `points_from_gridmap`: empty output
- `points_from_tilemap`: empty output

### Traits declared in meta_node that disagree with the table

- `bounds_from_mesh`: table [main_thread=true, cacheable=false], effective [main_thread=false, cacheable=true] (meta_node wins)

### Static scan findings (threadable templates)

| Template | Location | Pattern | Guard | Code |
|---|---|---|---|---|
| `load_data_table` | `load_data_table.gd:171` | file or project setting (extra) | none | `if not FileAccess.file_exists(path):` |
| `load_data_table` | `load_data_table.gd:174` | file or project setting (extra) | none | `var text := FileAccess.get_file_as_string(path)` |
| `load_pcg_data_asset` | `load_pcg_data_asset.gd:22` | static var (extra) | none | `static var _cache : Dictionary = {}` |
| `load_pcg_data_asset` | `load_pcg_data_asset.gd:24` | static var (extra) | none | `static var parse_count : int = 0` |
| `load_pcg_data_asset` | `load_pcg_data_asset.gd:26` | static var (extra) | none | `static var cache_hits : int = 0` |
| `load_pcg_data_asset` | `load_pcg_data_asset.gd:29` | static var (extra) | none | `static var _cache_mutex := Mutex.new()` |
| `load_pcg_data_asset` | `load_pcg_data_asset.gd:172` | file or project setting (extra) | none | `var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))` |
| `load_pcg_data_asset` | `load_pcg_data_asset.gd:190` | load() (extra) | none | `var res = load(path)` |
| `load_pcg_data_asset` | `load_pcg_data_asset.gd:211` | file or project setting (extra) | none | `var f := FileAccess.open(path, FileAccess.READ)` |
| `load_pcg_data_asset` | `load_pcg_data_asset.gd:215` | file or project setting (extra) | none | `return "%s\|%d\|%d" % [path, FileAccess.get_modified_time(path), length]` |
| `load_pcg_data_asset` | `load_pcg_data_asset.gd:255` | file or project setting (extra) | none | `if not FileAccess.file_exists(path):` |
| `reroute` | `reroute.gd:33` | load() (extra) | none | `return load("res://addons/flow_nodes_editor/executor/flow_reroute_widget.gd")` |
| `sample_points` | `sample_points.gd:11` | static var (extra) | none | `static var blue_noise_samples : Array[BNSample] = []` |
| `sample_points` | `sample_points.gd:15` | static var (extra) | none | `static var _blue_noise_mutex := Mutex.new()` |
| `volume_sampler` | `sample_points.gd:11` | static var (extra) | none | `static var blue_noise_samples : Array[BNSample] = []` |
| `volume_sampler` | `sample_points.gd:15` | static var (extra) | none | `static var _blue_noise_mutex := Mutex.new()` |

## Discovered violations

**Checks 1 to 4: none.** No template mutated an input. No template was nondeterministic, including in its error messages. No threadable template gave a different result on a worker thread, including in a concurrent batch of 3. No cacheable template gave a different result on a cache hit. Every warm run was a cache hit, so every cacheable template's key is stable for equal settings and inputs.

This matches the WP1 audit for the 85 pre-round pure scripts. It also extends the result to the 34 nodes added after that audit, which no earlier test covered this way:
- **Main thread (10):** `create_points`, `create_target_node`, `get_property_from_object_path`, `get_spline_data`, `get_surface_data`, `get_volume_data`, `spawn_spline_mesh`, `bounds_from_mesh` (the table row; effective traits are pure, see below), `runtime_quality_branch`, `runtime_quality_select`.
- **Threadable, not cacheable (1):** `filter_data_by_index`.
- **Pure (23):** `apply_scale_to_bounds`, `attribute_cast`, `attribute_remove_duplicates`, `attribute_select`, `attribute_string_op`, `bitwise_op`, `break_transform_attribute`, `compare_op`, `copy_attribute`, `discard_points_on_irregular_surface`, `find_convex_hull_2d`, `gather`, `get_attribute_from_point_index`, `get_bounds`, `make_transform_attribute`, `merge_attributes`, `reset_point_center`, `split_points`, `to_point`, `transform_op`, `trig_op`, `vector_op`, `weighted_point_sampler`.

**Check 5 (static scan): no required-API hit in any threadable template.** The extra-hazard hits are all reviewed and harmless:
- `load_pcg_data_asset`: `static var` cache and counters behind the WP1 `Mutex`; `load(path)` of a `.tres`/`.res` data asset from a worker (Godot's loader is thread-safe); `FileAccess`. The node is already not cacheable.
- `load_data_table`: `FileAccess`. Already not cacheable.
- `sample_points` and `volume_sampler` (which extends it): the blue-noise `static var` table, built under the WP1 `Mutex`. The `blue_noise` settings variant ran it in concurrent worker batches without divergence.
- `reroute`: `load()` inside `widget_script()`, which is editor-only.

**Cases run on one worker instead of a batch.** Some cases print an error or warning outside `setError`:
- `relax` and `snap_to_grid` on input without `position`;
- `point_filter_range` on an attribute set;
- `mutate_seed` on input without `seed` (a warning).

The harness runs these cases on a single worker instead of a concurrent batch. The table shows this as "k/n batched", and the reason is under bug 3.

## Traits downgrades made

**None.** No template violated a check, so no row became more conservative. `executor/flow_node_traits.gd` is unchanged.

## Traits inconsistencies (for the coordinator)

- **`bounds_from_mesh`**: the table row says `[main_thread = true, cacheable = false]` ("Mesh AABB (RenderingServer)"). The node's `meta_node` declares `"pure": true, "main_thread": false`, and `meta_node` wins (`FlowNodeTraits.resolve`). The row is therefore dead, and the node runs on the pool and is cached.
  - It passed every check with an `ArrayMesh`, and with a `Mesh` attribute read per point on the worker.
  - The residual risk is `PrimitiveMesh.get_aabb()` (`BoxMesh` and friends). It runs the lazy `_update()` when an update is pending, which writes the mesh's own state and calls `RenderingServer`. Two pool elements sharing a freshly edited primitive mesh in one wave would race. That is unlikely, because the deferred update normally runs before generation, but it is not impossible.
  - A row cannot express a downgrade over `meta_node`. Fixing it needs one of:
    - the WP4b owner dropping `"pure"` from the meta (a node script edit, which WP9 may not make);
    - `FlowNodeTraits.resolve` letting a table row's conservative bits win over `meta_node` for stock templates;
    - `FlowExecutor._prewarm_shared_resources` calling `get_aabb()` on Mesh settings and Mesh attributes before a batch (WP1 code).
  - Recommendation: the second option, because it keeps the central table authoritative for stock nodes, or align the table row with the meta.

## Skipped templates

**No template is skipped wholesale.** Every one of the 164 ran at least one fixture case.

The suite leaves out **one case** as a known bug: `dungeon_connect_rooms` on `attr_set`. It raises a SCRIPT ERROR, which GdUnit reports as a failure (bug 1 below). `--include-known-bugs` runs it.

Partial coverage. These templates reached only an empty-output or error path, because a generic run cannot reach their real path:

| Template | Why |
|---|---|
| `input` | Graph boundary. It is fed by the evaluator from the owner's `args` and graph parameters, and is covered by the evaluator suites. |
| `output` | Graph boundary. It has no output port and only forwards its input to the evaluator. |
| `assets` | No assets configured. An asset list needs a project-specific `FlowUserResourceData` subclass. |
| `navigation_region_sampler` | Needs a baked `NavigationRegion3D`. There is none in the fixture scene. |
| `points_from_gridmap` | Needs a `GridMap` with a `MeshLibrary`. There is none in the fixture scene. |
| `points_from_tilemap` | Needs a `TileMap` or `TileMapLayer` with a `TileSet`. There is none in the fixture scene. |
| `point_from_player_pawn` | Needs a current camera or a player group. There is none in the fixture scene. |

The headless physics space is never stepped, so `physics_overlap_query`, `physics_shape_sweep`, `ray_cast` and `projection` (physics mode) run but see no bodies. `compute_kernel` has no RenderingDevice headless and only reaches its error path. Main-thread templates only run checks 1 and 2, by design.

## Bugs found

1. **`dungeon_connect_rooms.gd:51`: SCRIPT ERROR on input without a position stream.**
   - The node checks `in_data.size() < 2`, but `size()` is the length of the first stream. Input with two or more rows and no `position` stream passes the check, `getVector3Container("position")` returns an empty array, and `in_pos[i-1]` crashes.
   - The function aborts with no output and no `setError`, so `last_errors` does not report it.
   - Minimal repro:
     ```gdscript
     var d := FlowData.Data.new()
     d.registerStream("weight", PackedFloat32Array([1.0, 2.0]), FlowData.DataType.Float)
     var n = load("res://addons/flow_nodes_editor/nodes/dungeon_connect_rooms.gd").new()
     n.settings = n.meta_node.settings.new(); n.inputs = [d]
     var ctx := FlowData.EvaluationContext.new(); n.preExecute(ctx); n.execute(ctx)
     # SCRIPT ERROR: Invalid access of index '0' on a base object of type: 'PackedVector3Array'.
     # generated_bulks is empty, err is ""
     ```
   - Fix: check `in_pos.size()` (or `in_data.hasStream("position")`) and `setError` on a missing position. Then remove the `known_bugs` row in `conformance_overrides.gd`.

2. **`points_from_imported_scene.gd:19` (and `load_alembic_file`, which extends it): mesh transforms are ignored.**
   - `_append_mesh_point` reads `mi.global_transform` on nodes of an instantiated scene that never enters the tree (`execute` instantiates, walks and frees it).
   - Godot prints `Condition "!is_inside_tree()" is true` and returns an identity transform. Every point's position, rotation and scale therefore ignore the MeshInstance3D's own transform and its parents'.
   - Minimal repro: pack a scene with a `MeshInstance3D` (`BoxMesh`) at `position = Vector3(5, 0, 0)`, save it, and set `asset_path` to it. The output `position` is `(0, 0, 0)`; the expected value is `(5, 0, 0)`. The engine error is printed and `err` stays empty. Verified on this branch.
   - Fix: accumulate the local transforms while walking (`parent_xform * mi.transform`), or add the instance under a temporary parent inside the tree.
   - The golden suite does not cover this node with an offset mesh. Fixing it changes output for imported scenes whose meshes are not at the origin, so it needs a DEPRECATIONS row.

3. **Threaded mode and non-thread-safe script Loggers (executor, WP1 code, not a node).**
   - `FlowExecutor` defers the `push_error` of `setError` from pool elements to the main thread. It cannot defer errors a node raises another way: a `FlowData` helper's `push_error` (`cloneStream`, `findStream`, `translateStreamName`), `push_warning`, or engine errors. Godot calls every script `Logger` on the raising thread.
   - GdUnit's `GdUnitGodotErrorAssertImpl` creates a `GdUnitLogger` (with push errors on) that is never removed. That logger appends to an Array without a lock.
   - Evidence: the first version of this harness ran 3 `relax` elements concurrently on input without `position`, and the full suite aborted with `double free or corruption (!prev)` (exit 134). Running only the conformance directory passed. The same exposure exists in a threaded-mode wave whenever two pool elements print such an error at once.
   - The harness now avoids it (the single-worker cases above).
   - For the executor, the options are: document that script Loggers must be thread-safe when `threaded` is on; or have elements report through `setError` instead of relying on helper `push_error`s; or capture helper errors per thread.

Console noise, not bugs: some nodes print an error from a `FlowData` helper before reporting the same problem through `setError`, so the message appears twice in the console but once in `last_errors`:
- `relax` and `snap_to_grid` on input without `position`: `cloneStream` (`flow_data.gd:995`);
- `point_filter_range` on an attribute set: `findStream` (`flow_data.gd:871`).

With default settings (`@last`) on Data without streams, `boolean`, `filter` and `partition` print `@last is not valid` from `translateStreamName` (`flow_data.gd:724`). This was seen in a defaults-only run; the override table now gives them attribute names.

## Limits (honest scope)

- **Concurrency coverage.** A worker batch is 3 copies of the same element. It catches races on a node script's own shared state (static caches, shared settings resources). It does not explore every interleaving, and it does not pair different templates that share a resource. A pass is evidence, not proof.
- **Lazy engine resources** (`PrimitiveMesh` AABB, textures, `Curve3D` re-bake) are only exercised in the state the fixtures put them in. The executor prewarms Curve, Curve2D, Curve3D and Gradient, but not Mesh (see `bounds_from_mesh`).
- **Settings coverage.** Defaults plus override settings plus a handful of variants: `sample_points` distributions, `self_pruning` grid mode, `difference` operations and density function, `surface_sampler` count mode, `noise` add mode, `attribute_noise` modes, `math_op` operations. Other modes are reached only by the per-node suites.
- **The static scan** is a regular-expression heuristic over the node script and its local base scripts. It does not follow calls into helper classes (`FlowData`, `FlowSpatial`, `FlowSpawnUtil`).
- **Main-thread templates** run checks 1 and 2 only. Their scene reads are checked against the fixture scene, not against live editor scenes.

## Dictionary rows (for COMING_FROM_UNREAL_PCG.md)

| In Unreal PCG | Here |
|---|---|
| **`IPCGElement::IsCacheable` / `CanExecuteOnlyOnMainThread` contract tests** | **Node conformance harness** (`demo/tests/executor/conformance/`): every template is checked for input mutation, determinism, worker-thread equivalence and cache-hit equivalence; new nodes are covered automatically. |

## nodes_reference rows

None. No node was added.

## DEPRECATIONS rows

None. No output changed. Fixing bug 2 will need one.

## Files

All new, under `demo/tests/executor/conformance/`:
- `conformance_fixtures.gd`, `conformance_harness.gd`, `conformance_overrides.gd`, `conformance_static_scan.gd`, `conformance_report.gd` (with `.uid` files);
- `node_conformance_test.gd`, `conformance_harness_test.gd` (with `.uid` files);
- `fakes/conformance_fake_node.gd`, `tools/conformance_report.gd`, `data/conformance_table.csv`, `data/conformance_asset.json`, and the `.gdignore` files.

No existing file was edited. `executor/flow_node_traits.gd` is unchanged.

## Test results

From `demo/`:
- `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/executor/conformance`: 27 cases (11 + 16), 0 failures, 0 orphans.
- `... -a res://tests/executor`: 71 cases, 0 failures.
- `... -a res://tests` (full suite): 2209 cases, 0 errors, 0 failures, 2 skipped, 1 orphan, exit 101. That is the baseline 2182 plus the 27 new cases, with the same skipped and orphan counts. The golden and seed-zero suites are included and unchanged.
- `godot --headless --path . --import 2>&1 | grep -E "SCRIPT ERROR|Parse Error"`: prints nothing.
