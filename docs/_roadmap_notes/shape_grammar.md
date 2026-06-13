# Shape Grammar nodes — implementation notes

Implements two PARITY_ROADMAP items: **Subdivide Segment** and **Shape grammar
nodes**. Both are new, self-contained nodes auto-discovered by filename; no core
files were edited.

New files:

- `demo/addons/flow_nodes_editor/nodes/subdivide_segment.gd` (+ `_settings.gd`)
- `demo/addons/flow_nodes_editor/nodes/grammar_expand.gd` (+ `_settings.gd`)
- `demo/addons/flow_nodes_editor/grammar_module_resource.gd`
  (`GrammarModuleResourceData`, the module-table resource — lives at the addon
  root, **not** under `nodes/`, so the node scanner does not register it as a node)

---

## Subdivide Segment

`category: "Sampler"`, aliases `["Subdivide Segment", "Subdivide Spline"]`.

Slices each input span into sized sub-segments and emits one oriented point per
sub-segment at its center (long axis = local Z = `size.z`).

**Input** — one input port:
- `SPLINES` mode: a Path3D `NodePath` stream (default attribute `node`). Each
  spline is baked at `bake_interval`; with `whole_spline_as_span` on (default)
  the whole spline is one span, otherwise each baked segment is its own span.
- `SEGMENTS` mode: two `Vector` streams `segment_start` / `segment_end` carried
  on the input points (e.g. from `split_splines`).

**Settings**:
- `input_mode` — SPLINES | SEGMENTS
- `bake_interval`, `whole_spline_as_span` (SPLINES)
- `segment_start_attribute`, `segment_end_attribute` (SEGMENTS)
- `subdivide_mode` — MODULE_LENGTHS (cycle a length list) | TARGET_COUNT (N equal pieces)
- `module_lengths` (PackedFloat32Array), `target_count` (int)
- `fit_mode` — STRETCH (scale modules to fill the span exactly) | CLIP (drop the
  final overrun) | PAD_ENDS (keep a shorter final piece carrying its real length)
- `cross_section_size` (Vector2 → size.x / size.y)
- output attribute names: `out_length_attribute` (`length`),
  `out_segment_index_attribute` (`segment_index`), `out_t_start_attribute`
  (`t_start`), `out_t_end_attribute` (`t_end`) — all configurable, blank to skip.

**Output** — point data: position (segment center), rotation (Euler, oriented
along the span), size (`x`,`y` = cross-section, `z` = sub-segment length), plus
`length` / `segment_index` / `t_start` / `t_end`, and the sampler-convention
`density = 1.0` and per-point `seed` streams.

---

## Grammar Expand

`category: "Generator"`, aliases `["Grammar", "Subdivide Spline"]`.

Parses a grammar string against a module table and expands it per input span
into a flat list of fitted module points.

**Input** — one port: span/segment points carrying a `length` attribute (default
from Subdivide Segment) plus position/rotation/size. Each input point is treated
as a span oriented along its local Z (length from the `length` attribute, else
`size.z`). Modules are laid head-to-tail and centered on the span.

**Settings**:
- `grammar` (multiline string)
- `modules` — `Array[FlowUserResourceData]`; use `GrammarModuleResourceData`
  entries: `symbol` (String), `mesh` (Mesh, optional), `size` (float footprint),
  `weight` (float, for weighted choice). Same weighted-table pattern as `assets`.
- `length_attribute` (default `length`)
- `fit_mode` — STRETCH (scale the expanded sequence to fill the span exactly) |
  CLIP (keep module sizes, drop modules that overrun)
- `cross_section_size` (Vector2 → size.x / size.y)
- output attribute names: `out_symbol_attribute` (`symbol`),
  `out_module_index_attribute` (`module_index`), `out_mesh_attribute` (`mesh`,
  blank to skip mesh output).

**Output** — point data: position (module center), rotation (inherited from the
span), size (`x`,`y` = cross-section, `z` = fitted module length), plus `symbol`
(String), `module_index` (Int), an optional `mesh` (Resource) stream, and
`density` / per-point `seed`. Feed `symbol` into `match_and_set` (matching on
`symbol`) or feed `mesh` straight into `spawn_meshes`.

### Grammar syntax supported (UE subset)

| Form | Meaning |
| --- | --- |
| `A B C` | sequence (whitespace or commas separate tokens) |
| `[A]`, `[A,P]` | tuple: `A` is the symbol; the behavior (`P`) is parsed but only the symbol selects a module |
| `A*` | fill-repeat: repeat `A` until the span length is consumed |
| `A:N` | repeat `A` exactly `N` times |
| `{A,B}` | uniform weighted choice |
| `{[A,P]:2,[B,P]:1}` | weighted choice with explicit `:weight` per option |
| `{A,B}*` | a choice may be postfixed with `*` to fill the span |

Repetition counts for `*` are bounded by the span length divided by the smallest
module footprint, so a `*` always terminates. Symbols not present in the module
table default to footprint size `1.0` and a null mesh.

**Defensiveness:** the parser is a self-contained recursive-descent tokenizer +
parser. Any malformed grammar (unexpected character, unbalanced `[]`/`{}`,
missing number after `:`, empty `{}`, etc.) calls `setError(...)` with a clear
message and produces no output — it never crashes. An empty grammar or an empty
module table is also reported via `setError`.

---

## Example usage

Epic-style fence / modular wall:

```
Path3D spline
  -> Subdivide Segment           (SPLINES, whole_spline_as_span = true,
                                   subdivide_mode = TARGET_COUNT or MODULE_LENGTHS)
  -> Grammar Expand              grammar:  [Post,P] {[Panel,P]:2,[Gate,P]:1}* [Post,P]
                                 modules:  Post(mesh=post, size=0.5, weight=1)
                                           Panel(mesh=panel, size=2.0, weight=2)
                                           Gate(mesh=gate, size=2.0, weight=1)
                                 fit_mode: STRETCH
  -> Spawn Meshes                (mesh_attribute = "mesh")
```

Or route `symbol` through `Match And Set` (match_attr = `symbol`) against an
`Assets` table to attach meshes/colors, then `Spawn Meshes`.

Per-floor building loop: `Subdivide Segment` along a vertical span (or
`Duplicate Point` with a Y offset ≈ UE Duplicate Cross-Section) to stack floors,
then `Grammar Expand` per floor for the window/wall rhythm.
