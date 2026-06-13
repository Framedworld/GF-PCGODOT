# Attribute domains, `kind` marker, and stream-length validation

Implementation notes for three PARITY_ROADMAP items, all landed in
`demo/addons/flow_nodes_editor/flow_data.gd` plus a few nodes. Every change is
designed to be a no-op for existing `.tres` data and graphs.

## 1. Attribute domains (`@Data` / `@Points`)

UE 5.6 lets the same data carry per-point and per-data attributes, addressed via
`@Data.` / `@Points.` selector prefixes. We add a true per-data domain.

### New field
- `FlowData.Data.data_attrs : Dictionary` — maps `attr_name -> { value, data_type }`.
  Sits alongside the existing `tags`. Absent/empty means historical behavior.

### Selector syntax
- Prefix constant: `FlowData.DataAttrPrefix = "@data."`.
- `findStream("@data.<name>")` returns a synthetic **length-1 broadcast** stream
  built from `data_attrs[<name>]`. Under the existing broadcast convention
  (`bcast_idx`), that value reads as a constant for every point. Returns `null`
  when the attribute is absent.
- `registerStream("@data.<name>", container, type)` writes into `data_attrs`
  instead of creating a per-point stream. Element 0 of the container (or `null`
  if empty) becomes the stored value. Both selector branches run *before* the
  `name.split(".")` sub-stream logic, so the dot in `@data.foo` is never treated
  as a `Vector.X` style sub-component.

### Carry-through
- `duplicate()` and `filter()` copy `data_attrs` (deep) verbatim. Per-data attrs
  are domain-level metadata, so filtering the point set does not change them.

### Node changes
- `add_attribute.gd` / `add_attribute_settings.gd`: new `domain` toggle
  (`eDomain { PerPoint, PerData }`, default `PerPoint`). `PerPoint` is the exact
  historical path (broadcast-filled per-point stream). `PerData` writes a single
  value to `@data.<name>`.
- `partition.gd`: each output `Data` now gets the partition's representative
  value stamped as a per-data attribute under `@data.<attribute_name>` (in
  addition to the still-optional `out_partition_attribute` per-point int stream).
  Every point in a partition shares that value, so the data domain is its natural
  home.

## 2. Spatial data type lattice — `kind` marker

### New enum + field
- `FlowData.Kind { Points, Spline, Surface, Volume, AttrSet }`.
- `FlowData.Data.kind : Kind = Kind.Points` (default). Carried through
  `duplicate()` and `filter()`.

### Consumer
- `filter_data_by_type.gd` now **prefers** `kind` when it is non-default
  (anything other than `Points`): it classifies directly from the marker. When
  `kind == Points` (unset/default) it falls back to today's stream-shape
  heuristic (`position`/`rotation`/`size` => points; NodePath `node` => spline;
  otherwise attribute set). Source nodes setting `kind` is out of scope here, so
  with no producers stamping it the node behaves exactly as before.
- Note: the node's target enum only exposes PointData / SplineData /
  AttributeSet. Data explicitly marked `Surface`/`Volume` matches none of those
  targets and is routed to the "Outside" pin.

## 3. Stream-length invariants (engine-hardening)

`registerStream` now emits a clear `push_warning` (not a hard error) when a Data
already holds points and a per-point stream is registered whose length is
neither the point count nor 1 (broadcast). Empty containers (the
register-empty-then-fill idiom used by `addStream`/`addCommonStreams`) and
length-1 broadcasts remain exempt. The point count is recomputed from the
*other* streams so overwriting the first stream cannot false-positive against
itself. Warn-only preserves legitimate mid-construction build-up idioms (e.g.
merge's offset padding) while surfacing genuine corruption.

A small refactor extracted the packed-array `=> DataType` inference into the
static helper `FlowData.Data._inferContainerType()`, now shared by the per-data
selector path and the normal per-point path.

## Backward-compatibility guarantees
- New fields default to empty/`Points`; absent in old data == identical behavior.
- `duplicate()`/`filter()` only *add* copies of the new fields.
- The `@data.` selector paths trigger only on that exact prefix; all other names
  flow through the unchanged code.
- `add_attribute` defaults to `PerPoint` (historical path).
- `filter_data_by_type` uses the heuristic whenever `kind` is default.
- Stream-length validation is warn-only and never changes valid paths.
