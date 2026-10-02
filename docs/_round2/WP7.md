# WP7: editor integration

Notes for the coordinator: what this package changed in the editor, the rows
to merge into `COMING_FROM_UNREAL_PCG.md` and `DEPRECATIONS.md`, the manual
editor checks this headless container could not do, and the list of everything
that was not verified visually. None of the shared documents was edited.

## Summary

- **Types everywhere.** Port colours, slot types, the GDScript type mappings in
  both directions, `getFlowDataTypeFromObject`, the `newStream` callable and
  fill paths, graph parameter types and the parameters editor now cover
  Vector2, Vector4, Quaternion, Transform, Int64 and Double. `_coerce_input_data`
  wraps raw Vector2, Vector2i, Vector4, Quaternion and Transform3D runtime values.
  A raw int or float feeds an Int64 or Double graph parameter with the
  parameter's type.
- **Data inspector.** Its columns, cell text, sort keys and text filter come from
  a new pure table model, `FlowDataTableModel` (`visualization/`):
  - every DataType has columns, with one column per component for vectors;
  - sorting is numeric where the value is a number;
  - the filter matches the displayed text of every column;
  - shape-only Data shows a summary table.

  The `cell_contents` assignment bug is fixed.
- **Viewport debug draw.** A new pure builder, `FlowDebugShapes`
  (`visualization/`), turns a Data into line segments. It draws splines, box and
  sphere wireframes, polygon outlines, heightfield and mesh-surface grids,
  mesh-volume edges, points-volume boxes, composites with a combining
  indicator, and per-point bounds boxes. `NodeDrawDebug` uploads them as one
  line mesh next to the point cubes. Draw cost is capped, and the caps are listed
  below.
- **Widget behaviour.** `FlowNodeWidget` rebuilds its ports when the element's
  port layout changes, whatever path changed the setting: the inspector, or any
  code that edits the settings resource and emits `changed`. A link into a port that disappears is dropped, so it
  does not land on the parameter that takes its index. Parameter links still
  follow their parameter by name.
- **Named reroutes** are `set_variable` / `get_variable`. Dictionary rows are
  below; no new node.
- **Smoke harness.** It still builds a widget for every registered template. It
  now also checks that each widget's slots match the element's ports. A new suite
  switches every bool and enum setting of every template.

Golden and seed-zero suites pass without regeneration.

## 1. Types everywhere

### Port colours and GDScript types (`node.gd`)

| DataType | Port colour | GDScript type (both ways) | Raw runtime value accepted (`valueMatchesFlowDataType`) |
|---|---|---|---|
| Bool | `ef4444` (unchanged) | TYPE_BOOL | bool |
| Int | `c8c8c8` (unchanged) | TYPE_INT | int |
| Float | `c8c8c8` (unchanged) | TYPE_FLOAT | float |
| Vector | `a855f7` (unchanged) | TYPE_VECTOR3 | Vector3 |
| String | `3b82f6` (unchanged) | TYPE_STRING | String |
| Resource | `22c55e` (unchanged) | none | Resource |
| NodeMesh | `22c55e` (unchanged) | none | none |
| NodePath | `14b8a6` (unchanged) | none | none |
| Color | `eab308` (unchanged) | TYPE_COLOR | Color |
| **Quaternion** | `f472b6` | TYPE_QUATERNION | Quaternion, Vector4 |
| **Vector2** | `d8b4fe` | TYPE_VECTOR2 | Vector2, Vector2i |
| **Vector4** | `7e22ce` | TYPE_VECTOR4 | Vector4 |
| **Transform** | `f97316` | TYPE_TRANSFORM3D | Transform3D |
| **Int64** | `94a3b8` | TYPE_INT (maps back to Int) | int |
| **Double** | `a3e635` | TYPE_FLOAT (maps back to Float) | float |
| untyped / Invalid | `22d3ee` (unchanged) | TYPE_NIL | none |

- The colours live in one table, `FlowNodeBase.FLOW_DATA_TYPE_COLORS`.
- Int64 and Double share their Variant type with Int and Float. So:
  - a node setting of type `int` or `float` exposed as a port is typed Int or
    Float;
  - a raw `int` maps to Int.

  `valueMatchesFlowDataType(value, type)` accepts an int for Int64 and a float
  for Double, and a Vector4 for Quaternion. For Bool, Int, Float, String,
  Vector, Color and Resource it is exactly the old
  `getFlowDataTypeFromObject(value) == type` test.
- `getFlowDataTypeFromObject` maps the new Variant types. Vector2i maps to
  Vector2.
- **`scan_nodes` and `get_property_from_object_path` keep the previous mapping**
  (`getLegacyFlowDataTypeFromObject`). Those importers read every meta of every
  scanned node. With the new mapping, scenes with Vector2, Vector4, Quaternion
  or Transform3D metas or properties would gain streams. A Quaternion meta
  would likely raise a script error, because they write `container[i] = value`
  into PackedVector4Array storage.
  Their output therefore does not change. Importing the new types there is a
  follow-up (see "Not done").
- **Hand-drawn wires.** `FlowEditor.canConnect` keeps its rule that two typed
  ports must have the same type. It now compares type families
  (`FlowEditor.connection_type_family`), in which Int64 counts as Int and Double
  as Float. Node settings are GDScript `int` / `float`, so their parameter ports
  are typed Int / Float, and an Int64 or Double graph input must be able to feed
  them. Other types still match only themselves. Before, two typed ports matched
  only by equal slot types.
- `newStream` covers every type in its Callable path, through
  `FlowData.Data.writeValue`. A Quaternion or Vector2i fill value is converted
  to the stored form. The historical types keep their exact old code path.

### Graph parameters

- `GraphInputParameter` gains `cte_color`, `cte_quaternion`, `cte_vector2`,
  `cte_vector4`, `cte_transform`, `cte_int64` and `cte_double`.
  - Each is named `cte_` plus the lowercase DataType key, which is how the
    inspector plugin shows only the matching one.
  - `GraphInputParameter.value_property_name(type)` is the single mapping. The
    inspector plugin and the parameters editor use it.
  - Default values are not written to `.tres` files, so existing graphs load
    unchanged.
  - A Color or Quaternion parameter had no constant before (its default was
    `null`). It now defaults to white or identity.
- `FlowGraphParametersEditor.PARAMETER_TYPES` offers Int64, Double, Vector2,
  Vector4, Quaternion, Color and Transform after the six historical types.
  - Vector4, Quaternion and Transform get the wide value row that Vector has.
  - Each type has its own swatch colour.
- `input.gd` and `FlowGraphNode3D.refreshInputs` compare a component's `args`
  value with the parameter type through `valueMatchesFlowDataType`. An int arg
  for an Int64 parameter is used, and it is no longer reset to the default.
- `FlowExecutor._feed_graph_inputs` passes the parameter type to
  `_coerce_input_data`. A raw int fed to an Int64 parameter arrives as an Int64
  stream. A raw int fed to a Float parameter still arrives as Int (unchanged,
  and an existing test pins it).
- **Precision.** Int64 values are exact through `.tres`. Doubles are written
  with 17 significant figures. Godot's text parser can land one ulp away (seen
  on `0.1 + 1e-12`), which is far below single precision. The round-trip test
  asserts 1e-15.

## 2. Data inspector

`FlowDataTableModel` (`visualization/flow_data_table_model.gd`) is a pure model
of one Data. `data_inspector.gd` maps the TableView callbacks onto it: one cell
callback reads `model.cell_text(column, row)`. Sorting uses `model.sort_value`
and filtering uses `model.filtered_rows`.

| Stream type | Columns | Cell text | Sort key |
|---|---|---|---|
| Bool | 1 | True / False | 0 / 1 |
| Int, Int64 | 1 | integer | integer |
| Float | 1 | 3 decimals | float |
| Double | 1 | 6 decimals | float |
| Vector | `.X .Y .Z` | 3 decimals | component |
| Vector2 | `.X .Y` | 3 decimals | component |
| Vector4, Quaternion | `.X .Y .Z .W` | 3 decimals | component |
| Color | `.R .G .B .A` | 3 decimals | component |
| Transform | `.Pos.X/Y/Z .Rot.X/Y/Z .Scale.X/Y/Z` | 3 decimals; rotation in Euler degrees (the point rotation convention, from the orthonormalised basis) | component |
| String | 1, left aligned | text | text |
| Resource | 1, left aligned | resource path, `[Class]` when it has none | text |
| NodeMesh, NodePath | 1, left aligned | `$name`, blank for a freed node | text |

- Broadcast streams (one value for every row) show that value on every row.
- **Sorting.** Click a column title. Numeric columns sort numerically and text
  columns as text. Empty cells sort last in both directions. Ties keep the row
  order.
- **Filter.** A row matches when the lowercase filter text is found in its
  index or in the displayed text of any of its cells. This works for every type,
  including vector components and transforms. Before, only Bool, Int, Float,
  Vector, String, Resource and Node columns were searched. Searching the
  displayed text means a Float value of 0.1234, shown as "0.123", matches
  "0.123" but not "0.1234".
- **Shape-only Data** is a Data with a shape and no points. It shows a summary
  table:
  - columns: Shape (class), Kind, Points, Bounds Min, Bounds Max, Size, Detail;
  - one row for the shape, plus one indented row per composite operand
    (`A: ...`, `B: ...`), depth first, at most 64 rows;
  - Detail gives the length and closed flag of a spline, the polygon vertices
    and area, the heightfield size and cell, mesh triangle counts, box half
    extents, sphere radius, the box count of a points volume, and the operation
    and density function of a composite;
  - double-clicking a summary row focuses the viewport on that part's bounds
    centre.

  When a Data has both points and a shape, the points table is unchanged and the
  stats line names the shape.
- **The `cell_contents` bug.** `onColumnBegins` assigned `tv.cell_contents =
  null` on a TableView, which has no such property (a script error). Columns
  without a formatter now call `tv.setCellCallback(Callable())`, and the table
  skips them.
- The node tooltip and status bar summary name the shape of a shape-bearing
  output, as "shape FlowSplineShape (Spline)".

## 3. Viewport debug draw

`FlowDebugShapes.build_for_data(data, options)` returns `Lines`. That is two
vertices per segment, one colour per vertex, segment counts per category, a
`truncated` flag and notes. `NodeDrawDebug` uploads the result as one
`PRIMITIVE_LINES` RenderingServer mesh with an unshaded vertex-colour material,
next to the existing point-cube MultiMesh. The mesh is freed when debug is turned
off, when the node is disabled, or on exit.

| Data | Drawn as |
|---|---|
| `FlowSplineShape` | polyline of `curve.get_baked_points()` through `shape.transform`; closed curves closed; a one-point curve as a small cross |
| `FlowBoxVolume` | the 12 edges of the oriented box |
| `FlowSphereVolume` | three great circles (XY, XZ, YZ planes), an ellipsoid when the transform scales |
| `FlowPolygonSurface` | the outline at the polygon's height |
| `FlowHeightfieldSurface` | `SURFACE_GRID + 1` lines along each local axis following the heights. The first and last of each set are the border. |
| `FlowMeshSurface` | bounds box (dimmed) plus a `SURFACE_GRID + 1` square grid of vertical hits, split where the surface is missed |
| `FlowMeshVolume` | triangle edges, or the bounds box past the cap |
| `FlowPointsVolume` | one axis-aligned box per point |
| `FlowCompositeShape` | operand A in the debug colour, operand B tinted 70% towards the operation colour (Union green, Intersection yellow, Difference red), plus the combining indicator: the composite bounds as a dashed box (8 dashes per edge) and an operation glyph on its top face (`+`, `x`, `-`) |
| other `FlowSpatial` subclasses | bounds box |
| points with `bounds_min` and `bounds_max` | one box per point from the local bounds corners, rotated by the point rotation (Euler or `rotation_quat`) and placed at its position; `size` does not scale it (the bounds are the extents, as `getEffectiveBounds` reads them) |

**Debug settings.**
- Shapes use `debug_color`.
- Bounds boxes use the same colours as the point cubes: the grey ramp of the
  modulation stream (`debug_modulate_by`, the last added stream, density...) or
  `debug_color`.
- Bounds boxes are drawn in the `EXTENDS` debug mode only. `ABSOLUTE` mode draws
  fixed-size cubes, so extents would contradict it.
- The inspected row (`debug_row`) is drawn in the selection colour (magenta),
  even past the box cap.
- Int64, Double, Vector2, Vector4 and Quaternion streams can now modulate the
  debug colours. Numbers modulate by value, vectors by length.

**Caps** (constants on `FlowDebugShapes`):

| Cap | Value | What happens past it |
|---|---|---|
| `MAX_SEGMENTS` (all lines of one node) | 65 536 | further segments dropped, `truncated` |
| `MAX_SPLINE_POINTS` (per spline) | 2 048 | baked points subsampled evenly, ends kept |
| `MAX_OUTLINE_POINTS` (polygon outline) | 2 048 | subsampled |
| `CIRCLE_SEGMENTS` (per great circle) | 48 | fixed |
| `SURFACE_GRID` (grid lines per axis) | 24 (25 lines) | fixed; sampling cost of a mesh surface is 625 vertical queries |
| `HEIGHTFIELD_LINE_POINTS` (points per heightfield line) | 256 | subsampled |
| `MAX_MESH_EDGES` (mesh volume) | 6 000 | bounds box only |
| `MAX_POINT_BOXES` (point bounds, points volume) | 4 096 | remaining boxes dropped (the selected row is still drawn) |
| `MAX_COMPOSITE_DEPTH` | 8 | deeper operands drawn as their bounds |

With `trace` on, a truncated draw prints its notes.

## 4. Widget behaviour

- `FlowNodeWidget.port_signature()` describes what the rows are built from: the
  element's flow inputs (label, data type), its outputs, its exposed parameter
  names and types, and `show_disconnected_inputs`.
- `initFromScript()` records the signature. `refresh_ui()`, which runs on every
  settings change, rebuilds the rows when the signature changed. This covers
  every node whose `getMeta()` or `exposedAsInputNode()` depends on a setting:
  - `surface_sampler.use_bounding_shape`;
  - `projection.projection_mode`;
  - `add_attribute.data_type`;
  - `sample_points.distribution`;
  - third-party nodes.

  The nodes' own `onPropChanged -> initFromScript` calls still work. A second
  rebuild is skipped because the signature then matches.
- **Links.** Parameter links are detached and reattached by parameter name, as
  before. Inputs and parameters are both tracked in `args_ports_by_name`.
  - When an input disappears (a mode setting turned off), its links are now
    dropped. Before, `initFromScript` raised a script error and left the link
    attached to whatever port took the index.
  - Links out of removed outputs, and links into flow ports past the new input
    count, are also dropped.
  - The graph is marked for saving.
- **Saved links keep their indices where the nodes promise it.** In the default
  mode (`use_bounding_shape` off, `projection_mode` Physics) the first parameter
  port is 1, exactly as before WP2. With the mode on, the new input is port 1 and
  the parameters shift by one. Save and reload restore every link at its index.

## 5. Named reroutes

No new node. Rows for the Generic / Tags / Debug table (they replace the
"Named Reroute Declaration | — | roadmap" row):

| UE node | Here | Status | Notes |
|---|---|---|---|
| Named Reroute Declaration | `set_variable` | 1:1 | Declares a named, wire-free channel: the node's `variable_name` is the reroute name; its title reads "Set: name" and its port takes a per-name colour. The data passes through, so it can sit inline like a declaration with an output. |
| Named Reroute Usage | `get_variable` | 1:1 | Reads the channel declared by the `set_variable` of the same name, anywhere in the same graph; pick the name from the node's drop-down. Evaluation follows the declaration (the executor orders usages after their declaration, also in threaded mode). Clicking either node flashes its counterparts. Unlike UE's named reroutes, a name is graph-wide, also across frames. |

## 6. Smoke harness

- `editor_smoke_harness_test.gd` already built a widget for every registered
  template (`_editor.node_types`). Every template a package adds is therefore
  covered without a list. Its widget test now also checks each widget's slots
  against the element's ports. This is the only edit to the existing harness.
- `editor_widget_modes_test.gd` uses the same headless dock. It switches every
  bool and enum setting of every registered template through all its values,
  several hundred switches in all (the test requires more than 300). After each
  switch it asserts that the ports were rebuilt and that the slot enable state
  and slot types match the metadata.
  - A plain settings edit is used, with no `onPropChanged`, so the widget's own
    rebuild is what is tested.
  - It also requires that `surface_sampler`, `projection`, `add_attribute` and
    `sample_points` were seen changing ports.
- The WP2 and WP3 nodes are listed with their mode settings: `surface_sampler`,
  `projection`, `volume_sampler`, `sample_spline`, `difference`, `intersection`,
  `union`, `create_surface_from_spline`, `create_surface_from_polygon`,
  `make_bounds`, `get_bounds`, `get_spline_data`, `get_surface_data`,
  `get_volume_data`, `to_point`, `filter_data_by_type`, `spawn_meshes`,
  `spawn_scenes`, `spawn_nodes`, `apply_on_actor`, `spawn_spline_mesh` and
  `create_target_node`.
  - The settings must exist; a rename fails the test.
  - The flow inputs must be exactly the expected ones per mode.
  - The output count must not change.
- Link behaviour is checked across a mode change for `surface_sampler` and
  `projection`, through a plain settings edit and through the inspector path.
  The checks cover the parameter link moving, the dropped link, save and reload
  at the same indices, and the default parameter port staying at 1.

## Manual editor check

Steps for someone with the Godot editor. "D" toggles debug draw on the hovered
or selected node, "A" opens the data inspector.

1. **Port colours.**
   - Open any graph and add `add_attribute`.
   - In the sidebar inspector set `data_type` to Vector2, then Vector4,
     Quaternion, Transform, Int64 and Double. Turn on "show all inputs" (the
     connector options toggle) so the `Cte ...` parameter port is visible.
   - Expected: the parameter port dot changes colour per type: pale purple
     Vector2, deep purple Vector4, pink Quaternion, orange Transform. Int64 and
     Double are grey like Int and Float, because GDScript properties carry no
     64-bit distinction.
   - The title reads `name - Vector2` and so on.
2. **Graph parameters.**
   - In the Data Flow panel's graph parameters section, click "Add Parameter".
     Open the type drop-down.
   - Expected: thirteen types with distinct swatches. Picking Vector4,
     Quaternion or Transform puts the value editor on its own row under the name.
     Picking Int64 or Double shows a number field.
   - Add an `input` node for the parameter. Its output port takes the type's
     colour.
   - On the `FlowGraphNode3D`, press "Refresh Inputs". The `args` entry appears
     with the default, and an edited value survives another refresh.
3. **Data inspector, all types.**
   - Build `create_points` (or `grid`) → `add_attribute` (Vector2) →
     `add_attribute` (Transform) → `add_attribute` (Int64) → `add_attribute`
     (Double). Press A on the last node.
   - Expected:
     - columns `name.X name.Y` for the Vector2;
     - nine columns for the Transform: Pos, Rot in degrees, Scale;
     - an integer column for Int64 and six decimals for Double;
     - no red errors in the Output panel;
     - text right-aligned, except String, Resource and Node columns;
     - the header widths fit the titles.
   - Type in the filter box, for example a value shown in a Transform column.
     Only matching rows remain.
   - Click column titles twice each. The rows reorder up and down, and empty
     cells stay at the bottom.
4. **Data inspector, shape-only.**
   - Wire `get_spline_data` (with a Path3D in the scene) and press A on it.
   - Expected: one row `FlowSplineShape | Spline | 0 | (min) | (max) | (size) | N
     points, length L, tube 1.000`, and the stats line ends with `shape
     FlowSplineShape (Spline)`.
   - Then `difference` of `get_surface_data` and `get_volume_data`. Expected:
     three rows (composite, `A: ...`, `B: ...`).
   - Double-click a row. The viewport camera moves to that part's bounds centre.
5. **Debug draw, splines.**
   - Press D on `get_spline_data`.
   - Expected: a line in the debug colour following the Path3D curve exactly,
     including its curvature and the node's transform. A closed curve is closed.
   - Move the Path3D and let the graph re-run. The line follows.
6. **Debug draw, volumes.**
   - Press D on `get_volume_data` with a rotated box CollisionShape3D and a
     sphere one.
   - Expected: a rotated wire box and three great circles of the sphere's radius.
7. **Debug draw, surfaces.**
   - Press D on `get_surface_data` (HeightmapImage source, or a HeightMapShape3D
     terrain).
   - Expected: a 25 x 25 line grid draped on the terrain, its outer lines along
     the border.
   - With a MeshInstance3D source, expected: a dim bounds box and a draped grid
     that stops where the mesh ends.
   - A `create_surface_from_spline` in Shape mode shows its polygon outline.
8. **Debug draw, composites.**
   - Press D on `difference` (shape with shape).
   - Expected: operand A in the debug colour, operand B reddish, and a dashed box
     around the composite bounds with a short "-" on its top.
   - Intersection shows yellow tints and an "x". Union shows green and a "+".
9. **Debug draw, point bounds.**
   - Press D on a sampler output that writes `bounds_min` / `bounds_max`
     (`surface_sampler` on surface data, `bounds_modifier`).
   - Expected: a wire box per point around its cube, rotated with the point,
     tinted like the cubes.
   - Click a row in the inspector. That point's box turns magenta.
   - Set `debug_mode` to ABSOLUTE. The wire boxes disappear and the cubes keep
     the fixed size.
   - Change `debug_color` and `debug_modulate_by`. Wire boxes and shapes follow.
10. **Debug draw, limits.**
    - Point D at a 1025 x 1025 heightfield or a huge points set.
    - Expected: the editor stays responsive. The grid stays coarse (25 lines per
      axis) and at most 4096 point boxes are drawn.
    - With the node's `trace` setting on, the console prints "Debug.Lines
      truncated: ...".
11. **Ports follow modes.**
    - Add `surface_sampler`. Wire a node into In and another into a parameter
      port (enable "show all inputs").
    - Tick `use_bounding_shape`. A "Bounding Shape" input appears under In, and
      the parameter wire moves down one row with its parameter.
    - Wire something into Bounding Shape, save, close and reopen the scene. All
      three wires are where they were.
    - Untick `use_bounding_shape`. The Bounding Shape wire disappears (it does
      not jump onto the parameter), and the parameter wire moves back up.
    - Undo (Ctrl+Z) the untick. The input and its row should come back. Note
      whether the dropped wire comes back too. It is expected not to, because
      the drop happens inside the port rebuild and is not an undo action of its
      own. Reconnecting it by hand is the workaround.
    - Repeat with `projection.projection_mode` = Surface ("Projection Target").
12. **Tooltip.** Hover a `get_volume_data` node after evaluation. The tooltip
    reads `Out: 0 pts, 0 streams, shape FlowBoxVolume (Volume)` (or the
    composite).
13. **Disable or remove a node** with debug lines showing. The lines vanish,
    with no leftover lines in the viewport.

## Not verified visually

Headless runs use the dummy renderer and `Engine.is_editor_hint()` is false, so
none of the following was seen. Everything below the pixels is tested
numerically.

- What the debug lines look like:
  - colours on screen, depth testing against scene geometry, alpha blending of a
    translucent `debug_color`;
  - that `PRIMITIVE_LINES` with an unshaded vertex-colour `StandardMaterial3D`
    renders in the editor viewport on every renderer (Forward+, Mobile,
    Compatibility);
  - which scenario the line instance lands in. It uses the same scenario
    resolution as the point cubes.
- The data inspector table on screen: column widths, alignment, scrolling,
  header click targets, and the wider summary columns.
- Port dot colours and the parameter editor swatches and row layout. The
  `EditorInterface` icon calls, the native property editors and the
  `EditorInspectorButton` styles cannot be created headless, so only the pure
  helpers of `FlowGraphParametersEditor` were tested.
- The graph input parameter inspector plugin (`graph_input_parameter_inspector`)
  showing the right `cte_*` row.
- Undo and redo around a port rebuild, and the rebuild while a wire is being
  dragged.
- Hot reload of a node script whose ports depend on a setting.

## Not done

- `scan_nodes` and `get_property_from_object_path` still skip Vector2, Vector4,
  Quaternion and Transform3D metas and properties (kept for output
  compatibility). Importing them needs `writeValue`-based writes in those two
  scripts, as an opt-in.
- Exposed node settings of type `int` or `float` cannot be typed Int64 or Double
  ports: GDScript properties carry no 64-bit distinction.
- Search aliases "Named Reroute Declaration" / "Named Reroute Usage" on
  `set_variable` / `get_variable` would make the search popup find them by UE
  name. That is an edit to node scripts this package does not own.
- Choosing `Invalid` (999) as a `data_type` in an inspector enum drop-down still
  raises script errors in nodes that index `DataType.keys()` with it
  (`add_attribute.getTitle`, for instance). This is pre-existing. The widget sweep
  skips that value.

## Dictionary rows for COMING_FROM_UNREAL_PCG.md

Concept table (replace the two existing rows):

| In Unreal PCG | Here |
|---|---|
| **Attributes table (Inspect)** | The **Data Inspector** — press **A** on a node. One row per point, one column per attribute (vectors, colours, quaternions and transforms split into component columns), with filtering on the displayed text and click-to-sort columns; clicking a row highlights that point in the 3D viewport. Spatial data with no points (splines, surfaces, volumes, composites) shows a summary row per shape and per composite operand: class, kind, bounds, details. |
| **Debug cube rendering** | Press **D** on a node — points draw as instanced cubes in the viewport, tinted by density (or another attribute) on a grayscale ramp. Spatial data draws as lines: spline curves, box and sphere wireframes, polygon outlines, draped grids on heightfield and mesh surfaces, composites as their parts with an operation marker; points with `bounds_min`/`bounds_max` also get a wire box per point. |

Generic / Tags / Debug table: the two Named Reroute rows in section 5.

Attribute types concept row, add to the WP4a row's notes: "Graph parameters (the
`FlowGraphNode3D` inputs) can be any of Bool, Int, Int64, Float, Double, Vector2,
Vector, Vector4, Quaternion, Color, Transform, String and Resource; raw Godot
values of those types are accepted in `args` and `generate(inputs)`."

## nodes_reference rows

None. No node was added.

## DEPRECATIONS rows

| Node / API | Before | Now | Since |
|---|---|---|---|
| `FlowNodeIO._coerce_input_data` (graph inputs from `args`, `generate(inputs)`, subgraph or loop feeds) | Raw Vector2 / Vector4 / Quaternion / Transform3D values were rejected with a warning and the parameter default was used | Wrapped as Vector2 / Vector4 / Quaternion / Transform streams. A raw int for an Int64 parameter, a float for a Double one and a Vector4 for a Quaternion one take the parameter's type. An int for a Float parameter still arrives as Int. | WP7 |
| `FlowNodeBase.getFlowDataTypeFromObject` / `getFlowDataTypeFromGdScriptType` | Vector2, Vector4, Quaternion and Transform3D mapped to Invalid | Mapped to Vector2 (also Vector2i), Vector4, Quaternion, Transform. `scan_nodes` and `get_property_from_object_path` use the new `getLegacyFlowDataTypeFromObject`, so their output is unchanged. | WP7 |
| Exposed node settings of type Vector2 / Vector4 / Quaternion / Transform3D | Untyped parameter ports (default cyan), so any output could be wired in | Typed ports with the type's colour and slot type. A new wire drawn by hand follows the dock's existing rule (`FlowEditor.canConnect`): two typed ports must have the same type, and untyped flow outputs connect to anything. So a graph `input` of another type (say Vector) can no longer be wired into a Vector2 setting port, just as an Int input cannot be wired into a Float port today. Saved links still load (loading does not go through `canConnect`). | WP7 |
| `GraphInputParameter` of type Color or Quaternion | No constant; the default value was `null` | `cte_color` (white) / `cte_quaternion` (identity). New constants for Vector2, Vector4, Transform, Int64, Double. | WP7 |
| Component `args` for an Int64 / Double parameter | An int / float value was treated as the wrong type: ignored by the editor preview and reset to the default by "Refresh Inputs" | Accepted (`FlowNodeBase.valueMatchesFlowDataType`) | WP7 |
| Data inspector filter | Searched Bool, Int, Float, Vector, String, Resource and Node columns only, each with its own formatting | Searches the displayed text of every column (all types, components included) | WP7 |
| Data inspector sorting | Empty Resource / Node cells sorted as empty strings (first when ascending) | Empty cells sort last in both directions | WP7 |
| `FlowNodeWidget` ports | Rebuilt only when the node itself called `initFromScript` from `onPropChanged`; a link into an input that a mode setting removed raised a script error and stayed on the port index | Rebuilt whenever the element's port layout changes; links into removed inputs (and out of removed outputs) are dropped | WP7 |
| `FlowEditor.canConnect` (wires drawn by hand) | Two typed ports connected only when their slot types were equal | Int64 also connects with Int and Double with Float (`FlowEditor.connection_type_family`); everything else is unchanged | WP7 |
| `NodeDrawDebug` | Shape-only Data printed "setupDebugDraw failed - out_data" and drew nothing | Draws the shape as lines (plus per-point bounds boxes in EXTENDS mode) | WP7 |

## Tests

New suites in `demo/tests/editor/`:

| Suite | Cases | What |
|---|---|---|
| `editor_type_plumbing_test.gd` | 15 | colours for every DataType (historical unchanged, extended distinct), GDScript type round trips, runtime values, `valueMatchesFlowDataType`, legacy mapping, `newStream` callable and fill for every type, `_coerce_input_data` for raw Vector2 / Vector2i / Transform3D / Vector4 / Quaternion and the parameter-type hint, graph parameter constants for every editor type, parameters editor helpers, widget slot types and colours of `add_attribute`'s exposed constant for every type, `canConnect` type families |
| `graph_parameter_types_roundtrip_test.gd` | 4 | a parameter of each extended type (and Color) saved to `.tres` and reloaded; defaults and raw `args` fed through a `FlowGraphNode3D`; `refreshInputs` keeps raw values; the dock preview shows the same values |
| `data_inspector_types_test.gd` | 11 | model columns, cell text, sorting and filtering for a Data with one stream of every type plus a broadcast stream; shape summaries for every shape class and composites; the real inspector scene driven through `setNode`, `refresh`, the TableView column and cell callbacks, the filter edit and title clicks, on all-types, shape-only, empty and null Data |
| `debug_draw_shapes_test.gd` | 22 | every shape's lines checked numerically (baked spline points through the transform, closed splines, box corners, sphere radius and ellipsoid, polygon height, heightfield heights, mesh surface hits and misses, mesh volume edges, points volume boxes), composites (parts, tint, indicator inside the bounds), every cap, point bounds (corners, rotation, colours, selection, mode switch), grey ramp and the new modulation types, `NodeDrawDebug` end to end (line mesh created and freed, ABSOLUTE mode) |
| `editor_widget_modes_test.gd` | 7 | every template times every bool and enum setting; the WP2 and WP3 nodes' mode settings with exact inputs per mode; link behaviour and save and reload for `surface_sampler` and `projection` through two paths; exposed parameters following `add_attribute.data_type` and `sample_points.distribution` |

Shared helper: `tests/editor/support/widget_port_checks.gd`.

Existing tests edited (intended):
- `evaluator/evaluate_graph_inputs_test.gd`, `test_coerce_unsupported_type_is_null`:
  removed the Vector2 assertion, because Vector2 is now accepted (requirement 1).
- `editor/editor_smoke_harness_test.gd`, `test_every_template_builds_a_widget`:
  also checks each widget's slots against the element's ports.

### Runs (Godot 4.6, from `demo/`)

| Command (`-a` target) | Result |
|---|---|
| `godot --headless --path . --import` | no SCRIPT ERROR / Parse Error |
| `res://tests/editor` | 64 cases, 0 failures |
| `res://tests/golden` + `res://tests/runtime/seed_zero_backcompat_test.gd` | 5 cases, 0 failures, no baseline regenerated |
| `res://tests/golden` + `tests/evaluator` + `tests/runtime/seed_zero_backcompat_test.gd` | 76 cases, 0 failures, 2 skipped |
| `res://tests` (full) | 2240 cases, 0 errors, **1 failure**, 2 skipped, 1 orphan (exit 100). The failure is `golden_graphs_test.test_golden_graphs_are_deterministic`, explained below. The same command on the base commit gives 2182 cases, 0 failures. |

### Known issue: golden determinism in the full run

**Observation.**
- In the full run, `test_golden_graphs_are_deterministic` reports
  `res://demos/demo_dungeon.tscn::FlowGraphNode3D: spawned children 1897 ->
  1724`. The count varied between runs: 1887 and 1724 were seen.
- `test_golden_graphs_match_baseline` passes in the same run. Every node's
  output snapshot matches; only the count of spawned children differs.
- The failure needs the six editor suites, then the evaluator and runtime
  suites, before golden. Each of these passes:
  - golden alone;
  - the editor suites plus golden;
  - any single WP7 suite plus evaluator, runtime and golden;
  - leaving out any one of five of the six editor suites;
  - the WP7 code with only the smoke harness plus the attributes, spatial,
    evaluator and runtime suites before golden (350 cases).

  Creating and freeing a million nodes beforehand does not reproduce it.

**Cause.** This was found by tracking the spawned nodes in a failing run.
1. `demos/demo_dungeon.tscn` contains 1873 saved generated children. 1227 of them
   carry engine auto-generated names, `@Node3D@21588` to `@Node3D@23099`.
2. `spawn_scenes` names its instances `Scene_%04d`. Those names collide with the
   saved `Scene_*` siblings, so Godot renames each new node to `@Node3D@<n>`,
   where `<n>` is a process-wide counter.
3. When that counter lands inside the saved range, the new name equals a saved
   sibling's name. The parent's child index then loses entries.
4. In the failing run, the 80 torches and 98 wall decorations of the
   `subgraph_dungeon_lighting` and `subgraph_dungeon_wall_decor` spawners were
   alive and parented to the `FlowGraphNode3D`. They were named
   `@Node3D@22088...`. Yet `get_child_count()` returned 1721 while they sat at
   indices up to 1897, and `find_children` did not return them. The spawners of
   later subgraphs also found fewer saved nodes to clear.
5. In passing runs the counter is past 23099 (for example `@Node3D@25870`).

**Why it is not caused by WP7.** The WP7 test suites create many auto-named
nodes (docks, widgets, connector rows), so they move the counter into the
dangerous range at the moment golden evaluates the dungeon the second time. The
same failure will appear for any package whose new tests shift the counter by a
similar amount. WP7 code is not on the spawn path: runtime elements have no
widget or debug draw, and the type mapping changes are value-identical for the
historical types.

**Suggested fix (not mine to make).** Any one of these removes the dependency on
the process history:
- strip the stale generated children from `demo_dungeon.tscn`. They carry
  `flow_owner` metas and are regenerated anyway;
- have the spawners add children with `add_child(node, true)` (readable unique
  names, which Godot checks against siblings). This changes spawned node names,
  so the seed-zero and golden outputs need checking;
- or have the golden harness count spawned content without relying on the
  parent's child index.

## Files touched outside WP7 ownership

| File | Change | Why |
|---|---|---|
| `flow_nodes_io.gd` (WP1) | `_coerce_input_data` gains an optional `param_type` argument and accepts the new raw values | Requirement 1 names it |
| `executor/flow_executor.gd` (WP1) | `_feed_graph_inputs` passes the parameter type; new static `_in_param_type` | So an int feeds an Int64 parameter as Int64 |
| `nodes/input.gd` (WP1 widget parts) | two comparisons use `valueMatchesFlowDataType` | Editor preview of Int64 / Double `args` |
| `flow_node.gd` (WP5) | one line in `refreshInputs` uses `valueMatchesFlowDataType` | "Refresh Inputs" no longer resets Int64 / Double args |
| `nodes/scan_nodes.gd`, `nodes/get_property_from_object_path.gd` | `getFlowDataTypeFromObject` to `getLegacyFlowDataTypeFromObject` | Keep their output unchanged |
| `graph_input_parameter_inspector.gd` | uses `GraphInputParameter.value_property_name` | Same mapping as the parameters editor (it is a `graph_input_parameter*.gd` file, so owned) |
| `flow_editor.gd` (owned "where needed") | `canConnect` compares `connection_type_family` | Int64 / Double graph inputs into int / float setting ports |
