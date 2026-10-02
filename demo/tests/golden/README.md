# Golden-output harness

`golden_graphs_test.gd` is a determinism / regression test for whole graphs
(the equivalent of Unreal PCG's determinism tests). It evaluates every graph it
can find, summarises what every node produced, and compares that summary with
the checked-in `baseline.json`. A change to a node, the evaluator or a data
helper that alters any graph's output shows up as a failing test that names the
graph, the first node that drifted, the port and the stream.

## What it covers

Discovery (see `GRAPH_DIRS` / `GRAPH_FILES` at the top of the suite):

- every `FlowGraphResource` (`.tres` / `.res`) under `res://graphs` and
  `res://demos`, plus `res://graph00.tres` and `res://graph02_curves.tres`;
- every `FlowGraphNode3D` inside every `.tscn` / `.scn` under those
  directories. The scene is instanced and added to the test tree (with its
  graphs detached so nothing auto-generates), then each component's graph is
  evaluated with that component as `ctx.owner` and its `args` as graph inputs,
  so scene scanners and spawners see the scene they were authored for.

Standalone `.tres` graphs are evaluated with a fresh `FlowGraphNode3D` owner
added to the test tree, so spawners run too. Subgraph resources evaluated on
their own receive no inputs (their defaults); that is still a stable
fingerprint.

For each graph the baseline records:

| field | contents |
|---|---|
| `nodes` | `FlowNodeIO.evaluate_graph_snapshot()`: for **every** node in the graph, per bulk, per output port, a summary of the `FlowData.Data` (see below). Nodes that did not run map to `[]`. |
| `outputs` | the same summary for each named graph output `evaluate_graph()` returns |
| `spawned` | number of nodes carrying `flow_owner` meta under the owner (or the scene root) after evaluation |
| `node_errors` | sorted `FlowNodeBase.setError()` messages (`<node> : <message>`) |
| `script_errors` | sorted GDScript runtime errors raised during evaluation (these are recorded instead of failing the run; see "Known script errors" below) |

A Data summary is `size`, `kind`, sorted `tags`, `data_attrs` (type + hash)
and, per stream sorted by name, `name`, `data_type`, element `count` and a
16-hex-digit SHA-256 content hash. Integer, bool and string containers hash
their exact contents; float-based containers (Float, Vector, Color,
Quaternion) are rounded to 1/1000 first (`FlowNodeIO.SNAPSHOT_FLOAT_QUANTUM`);
Resource/Node containers hash only `resource_path` (or class) per element,
never object identity. Rounding does **not** make the hash portable: a value
within one float32 ulp of a rounding boundary flips it, see "Cross-platform
noise" below.

The suite has four tests:

- `test_golden_graphs_match_baseline`: compares against `baseline.json` and
  lists up to 12 differences per graph (also new / removed graphs), one line
  per stream: `graph=<key> node=<node> bulk=<b> port=<p> stream=<name>: exact
  hash <expected> -> <actual>; tolerance: <verdict>`;
- `test_golden_graphs_are_deterministic`: evaluates everything a second time
  in the same process (fresh owners and scene instances) and requires an
  identical result;
- `test_tolerance_sidecar_matches_baseline`: every fingerprint in
  `baseline_tolerance.json` belongs to the hash `baseline.json` holds;
- `test_baseline_records_native_library_state`: sanity check on the file.

`golden_tolerance_test.gd` tests the tolerance layer itself.

## Running it

From `demo/`:

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/golden
```

The whole `res://tests` run (and CI's `gdunit_validate` job, which runs
`paths: res://tests`) picks it up automatically.

### Regenerating the baseline

When an output change is intended (a bug fix, a new node default, a
re-baseline), regenerate and review the diff like any other code change:

```bash
FLOW_GOLDEN_UPDATE=1 godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/golden
git diff --stat tests/golden/baseline.json
```

In update mode the comparison is skipped and `baseline.json` is rewritten
(keys sorted, tab-indented, so diffs are per node), together with its
tolerance sidecar `baseline_tolerance.json`. Generate both **on Linux x86_64
with the native library loaded** (see below) so every graph is covered and the
exact hashes stay strict where CI runs; the files record
`generated_with_native_library` and `platform`.

To rebuild only the sidecar (for example after changing
`golden_tolerance.gd`), leaving `baseline.json` untouched:

```bash
FLOW_GOLDEN_UPDATE_TOLERANCE=1 godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/golden/golden_graphs_test.gd
```

It refuses to write unless the run matches `baseline.json` exactly, and binds
every fingerprint to the hash `baseline.json` already holds for that stream.

### Cross-platform noise (PLATFORM_NOISE)

Different platforms' libm (`sin`, `cos`, `atan2`) and compilers can round the
last bit of a result differently. Rounding to 1/1000 does not hide that: an
Euler angle of 100..180 degrees has a float32 ulp of about 1.5% of the
quantum, so a stream of a few hundred rotations almost always holds a value
close enough to a rounding boundary to flip the hash. The baseline is
generated on Linux; a Windows run was reported to differ in 19 stream hashes of `demo_flashy_colonnade` and
`demo_sample_points` (sampled spline rotations and the positions derived from
them), for that reason alone.

The exact hash stays the check. When it differs, `golden_tolerance.gd`
decides whether the difference is platform noise, using the fingerprints in
`baseline_tolerance.json` (per float stream: element count, a hash of 0.005
buckets, the few values that sat within the noise budget of a bucket boundary,
near-gimbal rotations kept whole, per-component min/max for messages):

- only float streams whose name, type and element count are unchanged can be
  noise; any other difference (point count, stream set, types, tags, kind,
  spawn count, errors, integer or string streams such as `seed`) fails;
- the graph is re-evaluated, the re-run must reproduce the very same exact
  hash, and every value must match the fingerprint within the stream's noise
  budget (64 float32 ulps of its largest magnitude, at most 0.0015 per value;
  the Windows retest measured up to 39 ulps on sampled spline rotations);
- rotation streams are compared as rotations: modulo 360 (so +179.9999 and
  -179.9999 match), at gimbal lock through pitch and yaw -+ roll, near gimbal
  lock by rotation distance;
- a change of 0.005 or more in any component of any element always fails.

A pass that needed this prints `WARNING: <suite>: PLATFORM_NOISE pass on
<platform>` and one `PLATFORM_NOISE graph=... node=... stream=...` line per
stream. It is accepted only on a platform other than the one that generated
the baseline (`platform` in the sidecar, e.g. `Linux.x86_64`); there the
exact hashes are still required. Override with `FLOW_GOLDEN_TOLERANCE=strict`
(never accept noise) or `FLOW_GOLDEN_TOLERANCE=noise` (accept it on the
baseline's platform too). The executor-modes, editor-smoke and seed-zero
suites use the same comparison.

### Native library

`difference`, `self_pruning`, `distance`, `relax`, `sample_spline`,
`point_neighborhood`, `sort` and `substract` need the libflow GDExtension
(`GDKdTree`, `GDRTree`, `GDStreamUtils`). Without it, graphs using those nodes
(directly or through nested subgraph/loop graphs) are **skipped, not failed**:
the run prints `golden: SKIPPED <graph>: native library ... needed by: ...`
and still compares every other graph. A graph that uses a template no
registered node directory provides is skipped the same way. The baseline's
`skipped` map lists what was skipped when it was generated, and why.

On Linux the library is not committed; build it (`scons`) or copy a build into
`demo/addons/flow_nodes_editor/bin/` and add, without committing it,

```
linux.x86_64 = "res://addons/flow_nodes_editor/bin/libflow.linux.template_debug.x86_64.so"
```

under `[libraries]` in `bin/flow.gdextension` (CI does the same).

## Using it from a game project

The harness only depends on the addon (`FlowNodeIO.evaluate_graph_snapshot`),
so a game can vendor `golden_graphs_test.gd` and point it at its own graphs:

- edit `GRAPH_DIRS` / `GRAPH_FILES` / `BASELINE_PATH` at the top of the copy, or
- leave the file untouched and set environment variables:
  - `FLOW_GOLDEN_GRAPH_DIRS` — comma or semicolon separated list of `res://`
    directories (scanned recursively; folders with `.gdignore` are skipped)
    and/or individual graph or scene files. It replaces the defaults.
  - `FLOW_GOLDEN_BASELINE` — baseline file to read/write (a `res://` path or
    an absolute path).

```bash
FLOW_GOLDEN_GRAPH_DIRS="res://pcg/graphs,res://levels/hotel_floor.tscn" \
FLOW_GOLDEN_BASELINE="res://tests/pcg_baseline.json" \
FLOW_GOLDEN_UPDATE=1 godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/golden
```

Typical re-baseline workflow when updating a vendored addon: generate the
baseline on the old addon, update the addon, run the comparison, and read the
node-level diff to decide whether each change is intended.

If the game registers extra node directories
(`FlowNodeRegistry.register_node_directory`), do it before the suite runs (for
example from a GdUnit `before()` in a small wrapper suite), otherwise those
graphs are reported as skipped with "unknown node templates".

## Known script errors in the current baseline

Some demo graphs raise GDScript runtime errors today; they are recorded under
`script_errors` so a fix shows up as an (intended) baseline change:

- `Invalid assignment of index 'N' (on base: 'Array') ...` — a wired
  *parameter* pin (e.g. a stream connected to a node's exposed setting) makes
  `FlowNodeIO._execute_single_node` index past the node's flow inputs; the
  node then never runs at runtime. See
  `tests/evaluator/evaluate_graph_known_issues_test.gd`.
- `Invalid call. Nonexistent function 'cleanup_multimesh_direct' in base 'Nil'.`
  — any node saved with `disabled = true` (`FlowNodeBase.refreshFromSettings`
  on an evaluator-built node without `draw_debug`).

Environment-dependent node errors are also recorded as-is (for example
`compute_kernel` reports that no compute-capable RenderingDevice exists in a
headless run). Always run the harness headless, as CI does.
