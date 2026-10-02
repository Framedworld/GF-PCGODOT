# Retest expectations after the real-editor round

Written for whoever re-runs the real-editor scenarios against the head that carries the `READY-FOR-RETEST` commit. Everything below was verified headless on Linux (Godot 4.6 and 4.7.1) unless stated otherwise; nothing was re-run in a real editor or on Windows by the author.

## Fixed (expect these to pass now)

| Finding | What changed | Where |
|---|---|---|
| Insert Reroute undo left 12 nodes / 13 links | `load_graph_state` writes the restored graph into the resource before rebuilding, so `repair_graph_integrity` no longer merges the old state back. A pending save is flushed before the repair runs on a click. | `flow_editor.gd`, [WP14-E](WP14-E.md) |
| Collapse to Subgraph kept the selected nodes | Same cause. A second defect (collapse mutated the undo state's frame attachment lists) is fixed too. | same |
| Pooling was a no-op in the dock | `removeGeneratedNodes` keeps pooled content of a present, enabled spawner with `reuse_instances` and `clear_previous_instances` on; everything else is freed as before. | same |
| Reload failure log for embedded graphs, `*` on a freshly opened tab, `-0.000` in the Data Inspector | Sub-resource paths are not reloaded from disk; a version-only migration no longer queues a save; the table formatter drops the sign of a zero. | same |
| `r1_editor_review_test` failed only in the full run | The dock suites create a fresh dock per test; the one leaked node in `surface_sampler_test` is freed. The suite now exits 0 with 0 orphans. | [WP14-T](WP14-T.md) |
| Golden / seed-zero baselines failed on Windows | The exact hash stays the strict check on Linux. Off Linux a differing float stream passes only as a printed `PLATFORM_NOISE` warning when it is element-exact within a few ulps; real changes still fail. `baseline.json` and `seed_zero_baseline.json` are unchanged. | [WP14-T](WP14-T.md) |
| HTerrain `get_height_at` called with two ints | Now `Vector2i`; the fake plugin has the real signature. | `terrain/flow_hterrain_adapter.gd` |
| `_get_property_list` deprecation (Godot 4.7) | Both overrides return `Array[Dictionary]`. | [WP14-S](WP14-S.md) |
| compute_kernel "Attempted to free invalid ID" | RIDs are freed dependents first and each free is guarded. Tested with a fake rendering device only. | [WP14-S](WP14-S.md) |
| Benchmark printed 8.5x | The printed "before" times are labelled reference-only; `FLOW_BENCH_BEFORE_A_MS` / `_B_MS` take your own base-commit numbers. | `tests/perf/executor_benchmark.gd` |

## Second retest round: golden tolerance budget

The first Windows retest found the noise budget (8 ulps) too small. The budget is now 64 float32 ulps of each stream's largest magnitude, capped at 0.0015 per value so that a change of 0.005 or more still always fails; rotations beyond about 45.6 degrees of pitch are compared as whole rotations. The sidecar was rebuilt on Linux against the unchanged `baseline.json`. A local simulation of the Windows pattern (rotation noise of about 38 ulps) failed with the old sidecar and passes with the new one. Expect `PLATFORM_NOISE pass on Windows.x86_64` lines and no golden or seed-zero failures. Details: [WP14-T](WP14-T.md), "Budget revision after the Windows retest". The seed-zero failure "no baseline for res://demos/subgraph_collapsed_N.tres" comes from running Collapse to Subgraph in the project, which writes that file into `demos/`; delete such files before running the suite.

## Deliberately left

- Dock pooling for a spawner nested in a subgraph or loop (see checklist 6.2).
- Compute-kernel behaviour on a real GPU beyond the one kernel already verified: the free-order fix has not been run on a device.
- Terrain3D `get_height_range()` reporting a zero Y extent before the plugin refreshes it (the surface still samples real heights).
- If float noise moves a position that is hashed into a per-point `seed`, the golden check fails and names the `seed` streams: those values really differ.
- The unfixed items listed per package in `docs/PARITY_ROADMAP.md` (Wave C hardening) and `docs/_round2/WP13-*.md`.

## Changed expectations in `docs/MANUAL_EDITOR_CHECK.md`

- Step 6.2 now states the nested-spawner limit and the `clear_previous_instances` requirement.
- The Terrain3D / HTerrain section says both were checked once against the real plugins.

## What to run

From `demo/` (use `-c`, otherwise gdUnit stops a suite at its first failure and reports fewer cases):

```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -c -a res://tests
```

Expected on Linux: 2699 cases, 0 failures, 0 skipped, 0 orphans, exit 0. On Windows: the same, with `WARNING: ... PLATFORM_NOISE pass on Windows.x86_64` lines in the golden, seed-zero, executor-modes and editor-smoke suites. `FLOW_GOLDEN_TOLERANCE=strict` shows the raw exact differences. If something fails, the failing lines name the graph, node, stream and both hashes.

## Real-editor scenarios worth repeating

Reroute insert, Ctrl+Z, Ctrl+Y, Ctrl+Z (counts return to before / after / before); Collapse to Subgraph then Ctrl+Z; three consecutive Regenerates on `demo_fallguys` with `reuse_instances` on (same `MultiMeshInstance3D` object each time); opening an embedded-graph scene (no "Resource file not found" log, no leading `*` before an edit); the earlier passing checks as regression guards.
