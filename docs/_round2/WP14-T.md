# WP14-T: test-infrastructure fixes found on Windows

A tester ran the branch in a Godot 4.7.1 editor on Windows and found two test-infrastructure problems: (A) `tests/review/r1_editor_review_test.gd` failed only inside the full run, and (B) the golden and seed-zero baselines do not reproduce on Windows. Both are fixed in test code only. No node or addon code changed. No `baseline.json` or `seed_zero_baseline.json` value changed.

Base: `9aa3675`. Commits: see the table at the end.

## A. Test-order fragility (`r1_editor_review_test.gd`, 8 cases)

### Symptom

In a full run every case of `r1_editor_review_test.gd` failed with `Invalid cast: can't convert a non-object value to an object type`, raised in `GdUnitOrphanNodesMonitor._find_orphan_at_node` (vendored gdUnit4). Each case passed when the suite ran alone.

### Root cause

Two things together cause it:

1. **A leaked orphan.** `tests/nodes/surface_sampler_test.gd` (`test_node_stream_with_no_valid_mesh_instances_sets_error`) built its input as `[Node3D.new()]` and never freed the node. That is the "1 orphan, exit 101" of every full run.
2. **A dock kept alive across tests.** After every test, gdUnit's `orphan_monitor.collect()` gathers details for *every* orphan in the process, including orphans left by earlier suites. To do that it walks the nodes reachable from the current frames: the suite's members and children. `r1_editor_review_test`, `editor_widget_modes_test` and `editor_smoke_harness_test` each kept one `flow_editor.tscn` dock from `before()` to `after()`. The walk enters the dock and runs `property as Node` on every untyped member. `flow_editor.gd` has untyped members that hold non-objects (for example `var min_id = 1000`), and that cast raises the error. GdUnit's error monitor then fails the test.

Order decides whether the bug shows. gdUnit runs `res://tests` in directory-listing order. On the Linux filesystem `review/` came before `nodes/`, so no orphan existed yet. On NTFS the order is alphabetical, so `nodes/surface_sampler_test.gd` runs before `review/`, and every case of the dock suite then fails.

Reproduced on Linux by running `surface_sampler_test.gd` and then `r1_editor_review_test.gd` with two `-a` arguments: 8/8 cases failed with the same error.

### Fix

- `surface_sampler_test.gd` frees the `Node3D` it creates. The full run now reports 0 orphans and exits 0.
- The three dock suites create the dock in `before_test()` and free it in `after_test()`, before gdUnit walks the suite. A future orphan from any suite can no longer break them. With the leak deliberately still in place, `surface_sampler_test` → `r1_editor_review_test` → `editor_widget_modes_test` → `editor_smoke_harness_test` ran with all cases passing (40 cases).

The vendored gdUnit4 addon is unchanged.

## B. Golden and seed-zero baselines on Windows

### What differs and why

The Windows run reported 19 stream-hash differences, the same on 4.6.3, 4.7.1 and the pre-round commit `61b4e67`. They are the rotation and position streams of `demo_flashy_colonnade` (both components) and the `sample_spline` rotation of `demo_sample_points`. `sample_spline` turns spline tangents into Euler degrees through `Basis.get_euler()` (atan2/asin) and stores them as float32. The transform, duplicate and spawn nodes downstream carry those rotations and derive positions from them.

The golden hash rounds floats to 1/1000 and hashes the whole stream. Any value within one float32 ulp of a rounding boundary flips the hash when another libm rounds the last bit differently. Measured on Linux over the whole golden set:

- 5.8 M float values;
- 2,297 values within 1e-6 of a 1/1000 boundary, and 22,005 within 1e-5;
- `id_0002_sample.rotation` of the colonnade (1,425 values, up to 177.7 degrees) has 38 values within 1e-5 of a boundary. At that magnitude one float32 ulp is 1.5e-5.

The coordinator's tester measured the same: jitter of 1e-7 relative (about one ulp) changed that stream's hash in 200 of 200 trials. `test_ulp_noise_flips_the_exact_hash_but_not_the_tolerance_check` reproduces this. A quantized hash is not portable by construction, so regenerating it on one OS cannot fix it.

The seed-zero suite is worse: it hashes `var_to_bytes` of the containers and of the spawned transforms with no quantization, so any last-bit difference changes it.

### Approach chosen: exact hash plus a tolerance fallback with stored side information

This is option (2) from the brief, made element-exact. Summary statistics (min, max and sum per component) could not meet the requirement that a 0.01 change fails: on a 1,425-value stream a 0.01 change moves the sum by less than the worst-case noise of the sum. A coarser quantum alone (option 1) still has boundaries. Per-platform baselines (option 3) need a Windows machine to generate them, and they verify nothing about Windows on the first run.

**The exact hash stays the strict check.** `baseline.json` is unchanged. A new sidecar `demo/tests/golden/baseline_tolerance.json` holds, for every float stream the baseline hashes (1,957 streams), a fingerprint bound to that stream's exact hash:

- `n`, `c`: element and component counts;
- `r`: a hash of every value's 0.005 bucket. The bucket boundaries are offset by 0.381966 of a bucket so values on round decimal or power-of-two grids never sit on one;
- `m`: the few values that were within the noise budget of a bucket boundary when the fingerprint was made (index and boundary; 10,074 values, 0.17%);
- `d`: the noise budget, 8 float32 ulps of the stream's largest magnitude (at least ulp(1));
- `g`: near-gimbal rotations, kept whole (1,177 elements);
- `lo`, `hi`: per-component min and max, used only in messages.

When an exact hash differs, `GoldenTolerance.compare_entry` (`demo/tests/golden/golden_tolerance.gd`) decides:

1. Only a float stream whose name, data type and element count are unchanged can be noise. Any other difference is a failure: point count, stream set, types, tags, kind, spawn count, node or script errors, and integer or string streams such as `seed`.
2. The graph is re-evaluated (same owners, inputs and order as the golden run), and the re-run must reproduce the very same exact hash. This proves that the values checked are the run's values. For the threaded and cache modes it also proves the mode equals the sequential run bit for bit.
3. Every value must match the fingerprint. An unmasked value must land in the same bucket: it was at least the budget away from a boundary, so noise within the budget cannot move it. A masked value must stay within twice the budget of its recorded boundary. A change of 0.005 or more in any component of any element therefore always fails, so a 0.01 change always fails.
4. Such a pass is accepted only on a platform other than the one that generated the baseline. The sidecar records `"platform": "Linux.x86_64"`, so on Linux the exact hashes are still required and nothing about the Linux check got weaker. `FLOW_GOLDEN_TOLERANCE=strict` refuses noise everywhere, and `FLOW_GOLDEN_TOLERANCE=noise` accepts it on Linux too (useful for simulations).
5. A pass that needed the fallback prints `WARNING: <suite>: PLATFORM_NOISE pass on <platform>: ...` followed by one `PLATFORM_NOISE graph=<key> node=<node> bulk=<b> port=<p> stream=<s>: exact hash <a> -> <b>; within noise budget <d>` line per stream, and calls `push_warning`. It never passes silently.

### Rotations: wraparound and gimbal lock

`rotation` (Vector3, Euler degrees, Godot's default YXZ order, pitch = x) is compared as a rotation:

- **Wraparound.** Buckets and boundaries are taken modulo 360/0.005 = 72,000, and 180 is a bucket centre, not a boundary. So +179.9999 and -179.9999 match. 179.995 against -179.995, which are 0.01 apart across the seam, fails. A non-rotation stream gets no wraparound.
- **Gimbal lock.** The first end-to-end simulation exposed this. It perturbed `basisToEuler` by one ulp locally. The colonnade's rubble element 405 at pitch -89.81 then moved 0.0013 degrees in yaw and in roll, but only 0.0004 degrees as a rotation. Yaw and roll are ill-conditioned there by 1/|cos(pitch)|. So the comparison works as follows:
  - Where |cos(pitch)| >= 0.1, components are bucketed with a budget scaled by 1/|cos(pitch)| (at most 10x).
  - Where |cos(pitch)| < 2e-5 (pitch at ±90 up to float noise), the rotation depends only on pitch and on phi = yaw - sign(pitch)·roll, because Ry(y)·Rx(∓90)·Rz(z) = Ry(y ± z)·Rx(∓90). Those two values are bucketed. The roughly 15,700 exact-gimbal elements of the sample-mesh demos, with normals straight up, cost nothing extra.
  - In between, the element is stored whole and compared by rotation distance (quaternions in double precision). The tolerance is 2·d plus the float32 representability term, capped at 0.005 degrees. A single-component change of 0.01 moves the rotation by exactly 0.01 degrees, so it fails.
  - Trading yaw against roll at exact gimbal lock is the same rotation, and it passes.

### What the tests show (`demo/tests/golden/golden_tolerance_test.gd`, 10 cases)

- 1e-7 relative jitter on the colonnade's sampled rotations flips the exact hash in more than half of 200 trials and passes the tolerance check in all 200.
- Jitter of up to ±4 float32 ulps on every float stream of the colonnade and sample_points graphs is tolerated.
- A ±0.01 change fails. This is checked on every masked value, every near-gimbal rotation component and every 37th value of five streams (rotation, random-rubble rotation, position, size and colour; about 4,000 cases).
- A changed point count fails, both in the stream and in the summary.
- A removed, added or retyped stream fails.
- Wraparound and gimbal behaviour, as described above.
- Exact grid values (k/8, k/2, 0.6k) are never masked.
- End to end: a simulated other-platform colonnade run, with all rotation streams jittered and hashes recomputed, passes as PLATFORM_NOISE with a sidecar from another platform. It fails with the local platform's sidecar. A 0.01 change on top fails, and the message names the graph, node and stream.
- A changed integer stream is never noise.

I mutation-checked the suite: disabling the hash check and the angle handling made 5 of the 9 cases that existed then fail.

### Local Windows simulation

I added `* 1.0000001` to `sample_spline`'s rotation output (local only, reverted) and ran the golden, seed-zero, executor-modes and editor-smoke suites:

- Default (Linux, strict): fails with 37 stream lines, `graph=... node=... stream=...: exact hash a -> b; within noise budget ... (PLATFORM_NOISE is not accepted on the platform that generated the baseline ...)`.
- With `FLOW_GOLDEN_TOLERANCE=noise`: all 14 cases pass, each suite printing its PLATFORM_NOISE list (37 streams; seed-zero: 10 sources).

A harsher simulation, perturbing `FlowData.basisToEuler` everywhere, also shows a limit. In `demo_sample_points`, positions that move by noise feed per-point `seed` values that are hashed from the position. Those integers, and the random rotations drawn from them in `id_0041_transform`, then legitimately differ, and the harness reports them as failures, naming the `seed` streams. The reported Windows run had no `seed` differences.

### Seed-zero (`tests/runtime/seed_zero_backcompat_test.gd`)

Its byte-exact hashes are unchanged and remain the check on Linux. Off the baseline's platform, a mismatch is accepted as PLATFORM_NOISE, with a printed warning, only if:

- (a) `FlowNodeIO.evaluate` and `FlowGraphNode3D.generate` agree bit for bit with the legacy path in the same process. That is the back-compat property the suite exists for, and it is platform independent.
- (b) The golden tolerance comparison accepts every golden graph of the same source (`res://x.tres`, or every `res://x.tscn::*` component).

A source without golden coverage cannot pass this way. Failures now print one line per key and mode, naming which hash differs (outputs, generated content or per-node bulks) with both values, followed by the golden diagnosis.

Limitation: off Linux, spawned-node transforms and MultiMesh buffers are only covered through the streams they come from (golden) and through (a). Linux keeps the byte-exact check on them.

### Other suites

`executor/executor_modes_golden_test.gd` (threaded, cache cold and warm, threaded with cache) and the runtime-vs-golden half of `editor/editor_smoke_harness_test.gd` use `GoldenTolerance.compare_entry`. Editor vs runtime stays an exact in-process comparison.

### Regenerating

- `FLOW_GOLDEN_UPDATE=1` now writes `baseline.json` and the sidecar together.
- `FLOW_GOLDEN_UPDATE_TOLERANCE=1` writes only the sidecar. It refuses unless the run matches `baseline.json` exactly and binds each fingerprint to the hash `baseline.json` already holds.

The sidecar in this branch was made the second way, on Linux, so `baseline.json` is byte-identical to `9aa3675`. `test_tolerance_sidecar_matches_baseline` keeps the two files in step.

## How the Windows tester should verify

From `demo/`, with the Windows console binary (adjust the name):

```powershell
# 1. The suites that failed, exactly as the full run orders them:
Godot_v4.7.1-stable_win64_console.exe --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -c `
  -a res://tests/nodes/surface_sampler_test.gd -a res://tests/review/r1_editor_review_test.gd `
  -a res://tests/golden -a res://tests/runtime/seed_zero_backcompat_test.gd `
  -a res://tests/executor/executor_modes_golden_test.gd -a res://tests/editor/editor_smoke_harness_test.gd

# 2. The full run: expect 0 failures, 0 orphans, exit code 0.
Godot_v4.7.1-stable_win64_console.exe --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -c -a res://tests
```

Expected on Windows: everything passes, and the golden, seed-zero, executor-modes and editor-smoke suites print `WARNING: ...: PLATFORM_NOISE pass on Windows.x86_64: ...` with the noisy streams listed. I expect the colonnade and sample_points rotation and position streams, the 19 reported, plus the same streams in the node copies they flow through.

To see the raw exact differences, as before: `$env:FLOW_GOLDEN_TOLERANCE="strict"` and then run command 1.

If anything still fails, the report needs only the failing lines. Each one names `graph=... node=... bulk=... port=... stream=...`, the exact hashes and the tolerance verdict, for example `element 405 component 2 = ... is ... from the value it had at baseline time (noise budget ...)` or `values moved by 0.005 or more somewhere in the stream ...; per-component min ... -> ..., max ... -> ...`. Running the GdUnit inspector in the editor gives the same lines.

## Files

- Changed: `demo/tests/nodes/surface_sampler_test.gd`, `demo/tests/review/r1_editor_review_test.gd`, `demo/tests/editor/editor_widget_modes_test.gd`, `demo/tests/editor/editor_smoke_harness_test.gd`, `demo/tests/golden/golden_graphs_test.gd` (evaluation helpers made static and shared, comparison through the tolerance layer, sidecar modes, one new case), `demo/tests/golden/README.md`, `demo/tests/executor/executor_modes_golden_test.gd`, `demo/tests/runtime/seed_zero_backcompat_test.gd`.
- New: `demo/tests/golden/golden_tolerance.gd`, `demo/tests/golden/golden_tolerance_test.gd`, `demo/tests/golden/baseline_tolerance.json` (490 KB).
- Not changed: any addon file, gdUnit4, `baseline.json`, `seed_zero_baseline.json`.

Dictionary, nodes_reference and DEPRECATIONS rows: none (test infrastructure only).

## Verification on Linux

- Import check (4.6 and 4.7.1): `godot --headless --path . --import 2>&1 | grep -E "SCRIPT ERROR|Parse Error"` prints nothing.
- Full suite, `-c -a res://tests`: 2670 cases, 0 errors, 0 failures, 0 skipped, **0 orphans, exit 0**, on both 4.7.1 and 4.6. Before this package it was 2659 cases with 1 orphan and exit 101. The 11 new cases are 10 in `golden_tolerance_test.gd` and `test_tolerance_sidecar_matches_baseline`.
- Order reproduction for A: `-a res://tests/nodes/surface_sampler_test.gd -a res://tests/review/r1_editor_review_test.gd` failed 8/8 before and passes now.

## Commits

| Commit | What |
|---|---|
| `df3a248` | `surface_sampler_test` frees its leaked `Node3D` (root cause of the orphan) |
| `7cdd975` | The three editor-dock suites use a dock per test |
| `768c56c` | Golden tolerance layer, sidecar, tests and README |
| `05e12c7` | Executor-modes and editor-smoke golden checks use it |
| `6b10804` | Seed-zero platform-noise fallback and per-entry report |
| (this file) | Notes |
