# Deprecations and breaking changes

This page lists what was removed, renamed or changed in meaning in the
`flow_nodes_editor` addon, so projects that vendor it (GodotJC, Black Lantern Tactics
and others) know what to check when they update. Newest entries first. The policy
for future changes is at the end.

When you update a vendored copy, work through every row dated after your last sync.

---

## 1. Removed or renamed symbols

| Symbol | Status | Replacement | Since |
|---|---|---|---|
| `GDRTreeGD` (`addons/flow_nodes_editor/gdr_tree_gd.gd`), the GDScript AABB-overlap fallback | **Removed** as dead code | The native `GDRTree` class (`native/src/gd_rtree.*`); `GDKdTree` for nearest-neighbour queries. Both need the GDExtension binary for your platform. Guard with `ClassDB.class_exists("GDRTree")` if you have to run without it. | `8e53dcb` (2026-06-03) |
| `FlowData.DataType.Vector3` | **Never existed.** Code that references it fails to parse. | `FlowData.DataType.Vector` (always a 3-component vector; the packed container is `PackedVector3Array`). | — |
| Templates `grid_points`, `bl_debug_points` | **Never shipped upstream.** They came from downstream copies. A graph that uses them fails with "Failed to resolve node script for template". | For `grid_points`, the stock `grid` or `grid_fill_bounds` template. For project templates like these, keep the script in a project node directory (see below) or map the old name to a stock template with `FlowNodeRegistry.template_aliases`. | — |
| Templates `bl_*`, `jc_*` in the addon's `nodes/` | **Not part of the addon.** The upstream copy used to contain editor tables naming ~20 `bl_*` templates (colours, a "Black Lantern" add-node category). These tables are now removed. | Move project nodes to a project directory listed in `flow_nodes/node_directories`, and give each node a `"category"` in its `meta_node`. | this release |
| `MAPGEN_DEBUG_ORDER` env var (evaluation-order print for `assemble_map_plan` / `pcg_map_plan`) | **Removed** from `FlowNodeIO._build_evaluation_state` | None. Log from your own node if you need the order. | this release |
| Category and colour tables keyed by template name (`node.gd` `_get_category_hue`, `flow_editor.gd` `cat_map`, `search_add_node_popup.gd` `_CATEGORY_MAP`) | **Changed.** Colour now comes only from `meta_node.category`. Unknown or missing categories get a hash colour. The template tables stay only as a fallback for the add-node menu. | Set `"category"` in `meta_node`. Stock nodes now all declare one. | this release |

## 2. Changed semantics

These changes do not break parsing, but a graph that ran before can now produce
different output.

| Node / API | Before | Now | Since |
|---|---|---|---|
| `distance`, **unwired** Input B (`get_input(1) == null`) | Some downstream copies treated it as an empty target set and passed the points through with every distance at 1.0 ("infinitely far"). | **Error**: `"Input B not connected"`. In the editor preview with no owner, the output is empty. A connected but **empty** B still takes the far-fill path (every distance 1.0). | `a39ba87` (2026-06-10) |
| `attribute_filter_range`, numeric mode, String attribute with a value that does not parse as a float | The node aborted with an error, and neither output was produced. | That point goes to **Outside**. The other points are still filtered. Non-numeric stream types (Resource, NodePath, ...) still error. | `5a143f6` (2026-06-10) |
| Default node seed | `randi()` per node | Fixed `12345`. Graphs are deterministic by default, as in UE. | `5a143f6` |
| Per-point randomness (`transform`, `attribute_noise`, `attribute_random`, `select_points`, `mutate_seed`) | Came from one node-global RNG in point-index order | Uses a per-point seed from `$Seed`, then the position hash, then the index. Results no longer shift when point order or count changes, but they differ from the old output. | `980dc82` (2026-06-21) |
| Size→bounds generators (`sample_spline`, `sample_points`, `split_splines`, `subdivide_segment`, `create_surface_from_*`) | Wrote the sampling extent into `size`, which spawners apply as scale | Write **unit scale** and put the extent in `bounds_min`/`bounds_max`. Set `legacy_scale_from_extent = true` on the generator to get the old look (see [demo_visual_parity.md](demo_visual_parity.md)). | `03c2826`, `e6aea74` (2026-06-21/22) |
| Spawned-node `flow_owner` meta (`spawn_meshes`, `spawn_nodes`, `spawn_scenes`, `create_spline`, ...) | A `String`: the spawning node's name | A `Dictionary` `{ "component": <FlowGraphNode3D instance id>, "node": <node name> }`, so two components that use the same graph do not clean up each other's output. Cleanup still accepts the legacy String form, so scenes saved before this change clean up. Code that **reads** the meta and compares it to a String has to handle both shapes. | this release ([RUNTIME_API_P0.md](RUNTIME_API_P0.md) §5) |
| `EvaluationContext.eval_id` | Some projects used it to pass a seed into nodes | An evaluation counter only, never a seed. Pass the seed as `FlowGraphNode3D.seed` or `FlowNodeIO.evaluate(..., seed)`. With `seed == 0`, output is identical to before. | this release ([RUNTIME_API_P0.md](RUNTIME_API_P0.md) §2) |

## 3. Graph format

| Change | Effect | Since |
|---|---|---|
| `FlowGraphResource.data["version"]` is now `2` (was `1`; data without the key counts as `1`) | `FlowGraphMigrations.migrate` upgrades old data when the editor loads it, at runtime (in memory only) and on paste. Loading a version-1 graph in the editor marks it dirty, and the next save writes version 2. An older addon ignores the version and still loads version-2 data, because version 2 changed no settings keys. | this release |
| Project node directories come from the project setting `flow_nodes/node_directories` | `FlowNodeRegistry.register_node_directory` still works. The setting removes the need to call it before every evaluation and editor load. | this release |

---

## 4. Policy from here on

1. **One release of soft deprecation, then removal.** A release is a bump of
   `version` in `plugin.cfg`. Whatever is renamed or removed keeps working for one
   release through a shim that calls `push_warning` once per process and names the
   replacement. The following release removes the shim. Every deprecation is listed
   on this page when it lands, with the release that will remove it.
2. **Renamed templates** get an entry in `FlowNodeRegistry.STOCK_TEMPLATE_ALIASES`
   (`"old_template": "new_template"`). `FlowNodeRegistry.get_node_script_path` and
   `FlowGraphMigrations.migrate` resolve the alias when the old script no longer
   exists, and warn once per old name. Re-saving the graph writes the new name.
   Projects can add their own aliases at startup:

   ```gdscript
   FlowNodeRegistry.template_aliases["bl_debug_points"] = "grid"
   ```

   An alias never replaces a template that still has a script, so a project that
   keeps its own copy of an old node keeps using it.
3. **Renamed or reinterpreted node settings** get a `FlowGraphMigrations` entry and a
   `CURRENT_VERSION` bump. Graphs are upgraded on load, so no setting value is
   silently dropped. See "How to add a migration" in the
   [addon README](../demo/addons/flow_nodes_editor/README.md).
4. **Semantic changes** (same inputs, different output) are listed in section 2 with
   the old and new behaviour. Where it is cheap, they ship with an opt-in setting
   that restores the old behaviour (as `legacy_scale_from_extent` does).
5. **Project-specific code never goes into shared addon files.** Category, colour and
   search terms come from `meta_node`. Project nodes live in project directories.
