# WP14-E: editor bugs from a real editor session

A tester ran the branch in a real Godot 4.7.1 editor on Windows and reported four editor bugs. This package fixes them.

Method: for each bug I wrote a headless test first and confirmed that it failed. Then I made the smallest root-cause fix in its own commit. The dock is driven headless as in the R1 review suite. Undo and redo replay the states the dock recorded for the action (see Limits).

All new tests are in `demo/tests/review/wp14e_editor_bugs_test.gd` (11 cases). Golden and seed-zero baselines did not change.

## Bugs fixed

| # | Commit | Bug | Root cause | Fix | Tests |
|---|---|---|---|---|---|
| 2 | `840cf95` | Undo of **Insert Reroute** left the reroute in place and restored the original wire, so two wires fed one input. | `load_graph_state()` is the do and undo method of every snapshot action. It rebuilds the dock through `FlowNodeIO.create_nodes_from_dict()`, which ends with `repair_graph_integrity()`. The repair adds back every node and link that `current_resource.data` holds but the dock lacks. In a real session the debounced save (0.35 s) has always run before Ctrl+Z, so the resource held the *after* state. The undo therefore produced the union of both states, and the next save wrote it. The recorded states themselves were correct. | `load_graph_state()` writes the restored graph into `current_resource.data` before it rebuilds the dock. `prepare_graph_for_interaction()` runs on every click on the graph or a node, and it also repairs against the resource. It now writes a pending debounced save first, so a click within 0.35 s of an add-node undo or a delete no longer brings the removed nodes back. | `test_insert_reroute_undo_restores_the_original_wire`, `test_add_node_wire_and_move_undo_survive_a_click_before_the_save` |
| 3 | `0b384d2` | **Collapse to Subgraph** added the subgraph node and kept the selected nodes. Undo did not restore the graph. | The collapse itself was correct: it builds an after state without the selection and with the external links rewired to the subgraph pins. It applies that state through `load_graph_state()`, so the cause was the same union as #2. One defect remained in the collapse: when it built the after state's comment frames, it wrote the reduced attachment lists into `before_state`'s frame dictionaries, and `before_state` is the undo state. After an undo, a frame around a collapsed node no longer held that node. | Fixed by #2, and the after state now uses copies of the frame dictionaries. | `test_collapse_to_subgraph_replaces_selection_in_embedded_graph`, `test_collapse_to_subgraph_replaces_selection_in_external_graph` (a scene sub-resource graph and a `.tres` graph, each with a comment frame, undo, redo and a click after each step) |
| 1 | `080bade` | **Pooling did nothing in the dock.** With `reuse_instances` on, every Regenerate created a new `MultiMeshInstance3D`, although `flow_pool_key` was identical. | `_begin_eval_graph()` calls `removeGeneratedNodes()`, which freed every generated child of the component before each dock evaluation. `FlowSpawnPool.collect()` then found nothing. `FlowGraphNode3D.generate()` does not free first, so pooling worked at runtime. | `removeGeneratedNodes()` keeps content that meets all of these conditions:<br>• it carries `flow_pool_key`;<br>• its producing spawner is in the graph and enabled;<br>• that spawner has `reuse_instances` and `clear_previous_instances` on;<br>• the spawner's own `isOwnFlowContent` matches it.<br>The spawner collects that content when it runs, as at runtime. After the evaluation, `_release_unclaimed_pooled_content()` detaches and frees kept content that was not handed out again: the spawner errored, got no input, or did not run. Everything else is freed before the evaluation, as before: content of spawners with reuse off, of deleted or disabled spawners, and content without a key. Reused content goes through the spawners' claim step, which clears the owner when `transient_output` is on. | `test_dock_evaluation_reuses_pooled_spawner_content`, `test_dock_evaluation_without_reuse_replaces_spawner_content`, `test_dock_frees_pooled_content_of_removed_disabled_or_starved_spawners` |
| 4a | `c83beec` | Opening a scene whose graph is an embedded sub-resource logged "Resource file not found: res://…tscn::Resource_…". | `_reload_resource_from_disk()` called `ResourceLoader.exists()`, which accepts a `<scene>::<id>` path while the scene is cached, and then `load()` failed. | Sub-resource paths (anything that `_is_direct_resource_save_path` rejects) are not reloaded from disk; the scene owns their state. | `test_opening_an_embedded_graph_does_not_reload_it_from_disk` |
| 4b | `c83beec` | A freshly opened graph tab showed "*" before any edit. | The demo graphs are saved at format version 1. On load, `migrate_resource_for_editor()` upgraded the version stamp in memory and called `queueSave()`, which marks the tab dirty. Version 2 changes no node data. | The tab is marked dirty only when the migration changed more than the version stamp. The stamp is written with the next real save (`nodes_as_dict` always writes the current version). A real settings migration still marks the tab dirty (`FlowGraphMigrationsTest.test_editor_load_and_save_bumps_version` is unchanged and passes). | `test_freshly_opened_embedded_graph_tab_is_not_modified`, `test_freshly_opened_external_graph_tab_is_not_modified` |
| 4c | `c83beec` | The data inspector showed "-0.000" for a zero Transform rotation. | The rotation is stored as -0.0, or as a tiny negative from the basis decomposition, and `"%1.3f"` keeps the sign. | `FlowDataTableModel.fmt_real()` drops the sign when the formatted number is zero. This changes formatting only; the data keeps its value (the test checks this). | `test_inspector_formats_negative_zero_as_zero` |

## Why the bug 2 and 3 fix writes the resource eagerly

The coordinator asked whether the fix should change `repair_graph_integrity()` for this call path or write the data eagerly. I chose the eager write, for these reasons:

- **The repair is valid only while the resource is current.** It restores nodes and links from the resource to recover from a dock that is missing them, for example after a partial load. That only works while the resource is at least as new as the dock.
- **Skipping the repair inside `load_graph_state()` would not be enough.** The resource would stay stale until the debounced save, and any click in that window runs the repair again through `prepare_graph_for_interaction()`. That would bring the union back. The test checks this path: it undoes, then clicks, then compares.
- **Writing the restored state makes the resource current.** That is what the debounced save would do 0.35 s later anyway, so the repair stays correct everywhere.

Side effects I checked:

- **Deferred save.** `load_graph_state()` still ends with `queueSave()`. The debounced save then replaces the data with the canonical `nodes_as_dict` output.
- **Modified flag.** Unchanged. `load_graph_state()` always marked the tab dirty through `queueSave()`. The eager write does not touch the flag.
- **Keys.** `FlowGraphResource.data` only ever holds `type`, `version`, `min_pos`, `nodes`, `links` and `frames`, because `saveToResource` replaces the whole dictionary with `nodes_as_dict`. The eager write keeps exactly these keys. Zoom, offset and the name counter are separate resource properties, and `load_graph_state` already handles them.
- **Undo snapshots.** The written data is a deep copy (`duplicate(true)`), so later in-place edits of the resource data cannot alter a recorded undo state. Objects in settings, such as a subgraph's graph resource, are shared, as before.
- **External `.tres` and embedded graphs.** Both are covered by the collapse tests. The write is in memory only. Disk and scene saves happen as before.
- **The click flush.** It writes the dock into the resource, which the debounced save does 0.35 s later anyway. It is skipped while a graph reload is in progress.

Other undo paths were checked and still pass: add node (`_restore_added_node` / `_remove_added_node`), wire removal (`apply_connections_change`) and node move (`set_nodes_positions`). None of them goes through `load_graph_state()`. Before the click flush, a click within the debounce window after an add-node undo brought the node back; the test failed without the flush.

## Test seams added

- `FlowEditor.last_recorded_undo_action` holds `{name, before, after}` of the last snapshot action. `record_undo_action()` now builds it even without an undo manager. `EditorUndoRedoManager` cannot be instantiated outside the editor, so the tests replay exactly the states the real undo manager would store.
- `_inspect_in_native()` returns early outside the editor. `EditorInterface.get_inspector()` does not exist in a headless run, and selecting a node raised a script error there.

## Limits

- **Headless only.** The tests do not exercise the real `EditorUndoRedoManager`, the Ctrl+Z / Ctrl+Y key handling, GraphEdit's double-click on a wire (`insertRerouteOnConnection` is called directly), the tab bar UI, or the Windows build. The tester independently found the same cause in the real editor. With an equivalent eager write, they reported these node/link counts: Insert Reroute → Ctrl+Z → Ctrl+Y → Ctrl+Z gives 12/12 → 11/11 → 12/12 → 11/11, and a collapse on an external graph goes 17/21 → 16/20, back to 17/21 on undo. I have not re-run this exact commit in a real editor.
- **4b.** The only cause I found headless is the version-only migration, covering both the open path (`setResourceToEdit` → `_switch_to_tab` → `loadFromResource`) and the first dock evaluation. A dirty mark from code that runs only inside the real editor would not show up in these tests, for example plugin selection handlers or the async regen in `_process`.
- **4a.** Reproduced with a scene loaded with `CACHE_MODE_REPLACE` under `user://`. With `CACHE_MODE_IGNORE`, `ResourceLoader.exists()` rejects the sub-resource path and nothing is logged. That is why the error only appears for scenes the editor has open.
- **Pooling.**
  - Spawners nested inside a subgraph or loop still lose their content directly under the component before each dock evaluation, so pooling stays a no-op for them in the dock. Their `flow_owner` names the inner node, which the dock cannot resolve to a settings resource.
  - Content under other parents (`spawn_parent_path`, `create_target_node` containers) was never removed by the dock, and it pooled already.
  - If an async dock evaluation is cancelled midway, kept content stays in the tree until the next evaluation. That evaluation classifies it again and frees it if its spawner no longer pools.
- **Collapsed subgraphs add streams.** The output of a collapsed subgraph carries the parameter streams of its boundary input and output nodes, for example `in_attr_In` and `out_noise_Out`, as any subgraph with named parameters does. The original streams keep their values (tested). The input parameter type comes from the target port's metadata (`Int` for `add_attribute`'s input). That is existing collapse behaviour and I did not change it.
- **Docs that are now true.** `docs/MANUAL_EDITOR_CHECK.md` step 6.2 and `docs/_round2/WP3.md` ("pooling applies … across editor re-evaluations") describe the behaviour this package restores. They need no change.

## Dictionary rows (for COMING_FROM_UNREAL_PCG.md)

None.

## nodes_reference rows

None.

## DEPRECATIONS rows

| Node / API | Before | Now | Since |
|---|---|---|---|
| Dock evaluation with `reuse_instances` on a spawner | Every dock evaluation freed the spawner's content first, so it was recreated | Content directly under the component is reused across dock evaluations, as at runtime. Content that the evaluation does not reuse is freed at its end. | `080bade` |
| `FlowEditor.load_graph_state()` (undo/redo of snapshot actions, Collapse to Subgraph) | Merged the restored state with the resource's last saved state | Writes the restored state to `current_resource.data` first; the result is exactly the restored state | `840cf95` |
| Click on the graph or a node in the dock | Repaired the dock against a resource that could be up to 0.35 s stale | Writes a pending debounced save to the resource first | `840cf95` |
| Opening a graph saved at an older format version whose migration changes only the version stamp | Tab marked modified ("*"), `save_pending` set | Not marked modified. The stamp is written with the next real save. Migrations that change node settings still mark the tab modified. | `c83beec` |
| Data inspector number cells | `-0.000` for negative zero and small negatives | `0.000` (display only) | `c83beec` |

## Test results

- Import check from `demo/`: `godot --headless --path . --import 2>&1 | grep -E "SCRIPT ERROR|Parse Error"` prints nothing.
- New suite: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -c -a res://tests/review/wp14e_editor_bugs_test.gd` gives 11 cases, 0 failures.
- Full suite, from `demo/`: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -c -a res://tests`
  - 2670 cases in 259 suites: 0 errors, 0 failures, 0 skipped.
  - 1 orphan, the existing one in `tests/nodes/surface_sampler_test.gd`. Exit code 101, as in the baseline.
- Golden and seed-zero suites pass unchanged.

## Files touched

- Editor code:
  - `flow_editor.gd`;
  - `flow_nodes_io.gd` (`migrate_resource_for_editor` only, an editor-only function);
  - `visualization/flow_data_table_model.gd` (`fmt_real`).
- New test suite: `demo/tests/review/wp14e_editor_bugs_test.gd`.
- No runtime, node or spawner script changed.
