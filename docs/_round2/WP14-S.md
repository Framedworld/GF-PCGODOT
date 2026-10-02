# WP14-S: Godot 4.7 property-list warning and compute_kernel RID cleanup

Fixes for two problems a tester found running the branch in a Godot 4.7.1 editor on a real GPU.

Base: `9aa3675` (`origin/claude/pcg-system-review-4tpca9`). There are 3 commits: one per fix, plus these notes.

| # | Commit | Area | Problem | Test |
|---|---|---|---|---|
| 1 | `cf94d8c` | `world/flow_world_3d.gd`, `flow_node.gd` | Godot 4.7 logs `"_get_property_list()" should return "Array[Dictionary]", not "Array"`. Both overrides now build and return a typed `Array[Dictionary]`. The properties, their order and their usage flags are unchanged. | `demo/tests/review_wp14/property_list_typed_test.gd` |
| 2 | `484e03a` | `nodes/compute_kernel.gd` | On a GPU, each run logged "Attempted to free invalid ID" twice. The fix frees the uniform set first, then the buffers, the pipeline and the shader, and checks validity before each free. | `demo/tests/review_wp14/compute_kernel_cleanup_test.gd` |

## 1. Typed `_get_property_list()`

I searched the whole addon (and `demo/` outside gdUnit4) for `_get_property_list` and for other engine virtuals that return typed arrays, such as `_get_import_options`. Only two overrides exist:

- `FlowWorld3D._get_property_list()` was typed `-> Array`. It exposes the tool buttons `generate_all_cells` and `cleanup_all_cells`.
- `FlowGraphNode3D._get_property_list()` had no return type. It exposes the tool button `refresh_inputs`.

Godot checks the type of the returned array at runtime, so annotating the return type alone is not enough. Each override now fills a local `var props : Array[Dictionary]` and returns it.

`FlowGraphNode3D`'s hint was `PROPERTY_HINT_TOOL_BUTTON | PROPERTY_USAGE_EDITOR`, which ORs a usage flag into the hint. Both expressions equal 39, so the hint is now plain `PROPERTY_HINT_TOOL_BUTTON`. As before, the dictionary has no `usage` key, and the engine fills in `PROPERTY_USAGE_DEFAULT` (6).

The test snapshots `get_property_list()` taken with the old code on Godot 4.6 and 4.7.1. Both versions gave identical lists, and the test compares every key. The snapshot tests passed against the old code; only the typed checks failed. I also compared the full ordered list of property names before and after the change, and they are identical. After the fix, `godot47 --import` and the full 4.7.1 suite no longer print the message.

## 2. compute_kernel RID cleanup

Cause: the node kept every RID in one array and freed them in creation order: shader, buffers, uniform set, pipeline. RenderingDevice tracks dependencies: the uniform set depends on the shader and on every bound buffer, and the compute pipeline depends on the shader. Freeing a RID also frees everything that depends on it. Freeing the shader therefore also freed the uniform set and the pipeline, so the explicit `free_rid()` calls on those two were the two invalid frees.

Fix:
- RIDs are kept by kind in a dictionary (`_new_gpu_resources()`).
- `static func _free_gpu_resources(rd, res)` frees them in this order: uniform set (only if `uniform_set_is_valid`), buffers, pipeline (only if `compute_pipeline_is_valid`), shader.
- Each slot is cleared after it is freed, so a second call is a no-op. A null device is also a no-op.
- RenderingDevice has no validity query for buffers or shaders. Nothing frees them implicitly (they are dependencies, never dependents), so a non-null RID is enough.
- The device comes from a new overridable `_create_rendering_device()`. `rd` is untyped in `_run_compute` and `_create_shader` so tests can inject a double. The one `:=` that inferred its type from `rd` is now `: int`.
- Without a GPU, `create_local_rendering_device()` still returns null and the node falls back with the same message as before. The existing `tests/nodes/compute_kernel_test.gd` passes unchanged.

Test double: `demo/tests/review_wp14/support/fake_rendering_device.gd` models RenderingDevice's dependency freeing, invalid frees and leaks (RIDs still alive when the device is freed). `support/injected_compute_kernel.gd` injects the double into the node.

- The double reproduces the bug: freeing in creation order gives exactly 2 invalid frees.
- For a successful run and for failures at the shader, output buffer, uniform set and pipeline steps, the test checks that each created RID is freed exactly once, explicitly and in dependency order. It also checks that nothing is cascade-freed, nothing leaks, and the input passes through on failure.
- Other tests cover idempotency, a uniform set the device already dropped, and the headless null-device path.
- When the old cleanup order is put back in the code temporarily, 7 of the 11 tests fail.

### What cannot be verified headless

- The fix has not been run on a real RenderingDevice. Its correctness depends on the dependency model above, which matches `RenderingDevice::uniform_set_create` / `compute_pipeline_create` (`_add_dependency`) and `_free_dependencies`, and on the two errors the tester reported. To confirm, run a Compute Kernel graph in the editor on a GPU and check that the log has no "Attempted to free invalid ID" and no leaked-RID warnings when the local device is freed.
- The double does not compile GLSL, run the shader or compute values. Its readback returns the zero-initialised output buffer. Real dispatch results, SPIR-V compilation errors and driver behaviour remain untested, as before this package.
- Some engine behaviour cannot be seen headless: whether a real driver accepts the exact free order, and any driver-level validation messages.

## Rows for shared docs

- COMING_FROM_UNREAL_PCG.md: none.
- nodes_reference.md: none. No node behaviour or settings changed.
- DEPRECATIONS.md: none. Output is unchanged.
- `docs/_roadmap_notes/gpu_compute_kernel.md`: I did not edit it. Its line "created RIDs are tracked and freed on every exit path" is still true. The coordinator may add "in dependency order (uniform set, buffers, pipeline, shader)".

## Tests

Run from `demo/` with the local Linux library line in `flow.gdextension` (not committed):

- Import check, `godot --headless --path . --import 2>&1 | grep -E "SCRIPT ERROR|Parse Error"`: prints nothing. The same check with `godot47` also prints nothing, and there is no `should return` line.
- `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -c -a res://tests`: 2674 cases, 0 errors, 0 failures, 0 skipped, 1 orphan, exit 101. The orphan is the existing one in `tests/nodes/surface_sampler_test.gd`.
- The same command with `godot47` gives the same result.
- New suites only (`-a res://tests/review_wp14 -a res://tests/nodes/compute_kernel_test.gd`): 37 cases, 0 failures on both 4.6 and 4.7.1.

I did not touch `flow_editor.gd` or `tests/golden`.
