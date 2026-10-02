# WP4a: attribute types and type-dependent nodes

Notes for the coordinator: what this package changed, and the rows to merge into
`COMING_FROM_UNREAL_PCG.md`, `doc/nodes_reference.md`, `node_templates.csv` and
`DEPRECATIONS.md`. None of those shared files was edited.

## Summary

- `FlowData.DataType` has five new values, appended before `Invalid`: `Vector2 = 10`,
  `Vector4 = 11`, `Transform = 12`, `Int64 = 13`, `Double = 14`. `newContainerOfType`,
  `writeValue`, `filteredStream`, `cloneStream`, `_inferContainerType`, `_inferValueType`,
  `canonical_numeric_type`, component selectors and `containerMatchesType` (new) handle
  every value. `duplicate`, `emptyLike`, `filter`, merge-style `append_array`, per-data
  attributes (`@data.x`) and `content_hash` work without changes, and a test walks every
  `DataType` through all of them.
- `registerStream` now checks the container against the declared type. A mismatch
  where either side is an extended type is **refused** (`push_error`, error string
  returned, nothing registered). A mismatch between historical types is still
  registered but now logs a warning. Before, both cases registered silently.
- Selector aliases: `$Position`, `$Rotation`, `$Scale`, `$Density`, `$Seed`,
  `$BoundsMin`, `$BoundsMax`, `$Steepness`, `$Color` and `$Index` (case-insensitive,
  with components such as `$Position.X`) resolve in `findStream` and `registerStream`
  and in every reader built on them (`first`, `value_at`, `container`, all
  attribute selectors). `@Source` is the output selector of every new node, meaning
  "write back to the input attribute".
- 14 new nodes: `attribute_cast`, `make_transform_attribute`,
  `break_transform_attribute`, `copy_attribute`, `attribute_string_op`, `bitwise_op`,
  `compare_op`, `merge_attributes`, `gather`, `vector_op`, `transform_op`, `trig_op`,
  and two extra attribute-family nodes that were cheap: `attribute_select` and
  `attribute_remove_duplicates`. Shared code lives in
  `addons/flow_nodes_editor/attributes/flow_attribute_ops.gd` (`FlowAttributeOps`),
  outside `nodes/` so the editor does not list it as a template.
- Extended for the new types: `add_attribute`, `filter`, `compose_vector`,
  `decompose_vector`, `expression`, `attribute_set_to_point`. Checked and already
  type-agnostic: `attribute_rename`, `remove_attribute`, `merge`, `partition`,
  `point_to_attribute_set`. Details are in the audit below.
- `visualization/table_view.gd`: columns of a type the data inspector does not format
  (Color, Quaternion and all five new types) reused the previous column's formatter
  and raised script errors. TableView now resets to a generic `str()` formatter before
  the inspector's column callback runs.
- Golden and seed-zero suites pass unchanged. No baseline was regenerated.

## DataType table

| DataType | Value | Container (`newContainerOfType`) | Inferred from container | `writeValue` accepts | Component selectors |
|---|---|---|---|---|---|
| Bool | 0 | `PackedByteArray` (0/1) | yes | anything, via `bool()` | no |
| Int | 1 | `PackedInt32Array` | yes | anything, via `int()` | no |
| Float | 2 | `PackedFloat32Array` | yes | anything, via `float()` | no |
| Vector | 3 | `PackedVector3Array` | yes | `Vector3` | `.x .y .z` |
| String | 4 | `PackedStringArray` | yes | anything, via `str()` | no |
| Resource | 5 | `Array[Resource]` | no (untyped Arrays are Invalid) | `Resource` | no |
| NodeMesh | 6 | `Array[Node]` | no | `Node` | no |
| NodePath | 7 | `Array[Node]` | no | `Node` | no |
| Color | 8 | `PackedColorArray` | yes | `Color` | `.r .g .b .a` / `.x .y .z .w` |
| Quaternion | 9 | `PackedVector4Array` (x, y, z, w) | yes, `PackedVector4Array` infers Quaternion | `Quaternion` or `Vector4` | `.x .y .z .w` (new) |
| **Vector2** | 10 | `PackedVector2Array` | yes | `Vector2`, `Vector2i` | `.x .y` |
| **Vector4** | 11 | `PackedVector4Array` | **no**: register it with an explicit type, since inference keeps returning Quaternion | `Vector4`, `Vector4i`, `Quaternion`, `Color` | `.x .y .z .w` |
| **Transform** | 12 | `Array[Transform3D]` (typed) | yes, for a typed `Array[Transform3D]` | `Transform3D`, `Basis` (no translation) | no (use `break_transform_attribute`) |
| **Int64** | 13 | `PackedInt64Array` | yes | anything, via `int()` | no |
| **Double** | 14 | `PackedFloat64Array` | yes | anything, via `float()` | no |

Other rules:

- `writeValue` reports a value it cannot store in a Vector2, Vector4 or Transform
  container with `push_error` and leaves the element unchanged.
- `Data.scalar` / `set_data_attr` infer `Vector2`/`Vector2i` values as Vector2 and
  `Transform3D` as Transform. Before, these failed with an "unsupported value type"
  warning. `Vector4` values still infer as Quaternion.
- `canonical_numeric_type` maps Int64 and Double to the canonical numeric type, so
  `Data.scalar("density", 0.5, DataType.Double)` registers a Float `density`.
  Registering `density` itself as Double is still refused, since canonical types do
  not change.
- `filteredStream` reports an unknown `data_type` with `push_error`. Before, it
  returned null silently.

## Selector aliases

| Alias (any case) | Resolves to | Notes |
|---|---|---|
| `$Position` | `position` | |
| `$Rotation` | `rotation` | Euler degrees, as before |
| `$Scale` | `size` | UE's Scale is this addon's `size` |
| `$Density` | `density` | |
| `$Seed` | `seed` | |
| `$BoundsMin` | `bounds_min` | |
| `$BoundsMax` | `bounds_max` | |
| `$Steepness` | `steepness` | |
| `$Color` | `color` | the conventional colour stream name |
| `$Index` | `index` | virtual per-point index |
| `$Alias.c` | `<target>.c` | components work on aliases: `$Position.X`, `$Scale.y` |
| `@Source` | the node's input attribute | output selector of every WP4a node: writes back to (and, for a cast, retypes) the input attribute |

Aliases only add names. A stream literally named `$Something` still resolves to
itself, and every selector that worked before (`position`, `position.x`, `Yaw`,
`Pitch`, `Roll`, `index`, `front`/`up`/`right`, `@last`, `@data.<name>`) resolves
identically (`tests/attributes/selector_alias_test.gd`). The `expression` node also
maps these aliases when no stream matches the name exactly or case-insensitively, so
`$Scale.y + $BoundsMin.x` works there too.

## Node dictionary rows

Rows to **replace** in the Attributes / Metadata table of `COMING_FROM_UNREAL_PCG.md`:

| UE node | Here | Status | Notes |
|---|---|---|---|
| Copy Attribute / Transfer Attribute | `copy_attribute` | 1:1 | Target and Source pins. ByIndex (equal counts, or one source entry broadcast), ByMatchAttribute (first source entry with an equal key; Int and Int64 keys compare as integers), NearestPoint (by position, optional max distance; native KD-tree). Copies one attribute (`@Source` keeps its name) or all attributes (point transform streams only on request). Types are preserved; unmatched points keep their existing value or the type default; optional matched flag. |
| Merge Attributes | `merge_attributes` | 1:1 | Merges every data on the pin into one attribute set. Append: union of attributes, entries concatenated, numeric clashes promoted (Int and Float give Float, Int and Int64 give Int64, Int64 and Float give Double), other clashes fail. ByIndex: columns side by side. Tags and `@data` attributes merge. Behaviour reconstructed from UE's documentation, from memory. |
| Attribute String Op | `attribute_string_op` | 1:1 | Append, Prepend, Replace, ToUpper, ToLower, Contains, StartsWith, EndsWith (Bool), Format (`{0}` `{1}` `{2}` `{index}` `{attribute}`), Length (Int), Trim, Substring. Non-String operands convert to text. |
| Break/Make Transform Attribute | `break_transform_attribute` / `make_transform_attribute` | 1:1 | New `Transform` attribute type (`Array[Transform3D]`). Make: translation + rotation (Euler degrees, or a Quaternion / Vector4) + scale, composed as UE does (scale, rotate, translate). Break: translation, Euler rotation, optional quaternion, scale. The defaults turn the point transform into an attribute and back. |
| Bitwise Op | `bitwise_op` | 1:1 | And, Or, Xor, Not, ShiftLeft, ShiftRight on Bool/Int/Int64, computed in 64 bits; Int64 if either operand is Int64, else Int (low 32 bits). |
| Compare Op | `compare_op` | 1:1 | == != > >= < <= into a Bool attribute. Integers compare exactly (Int64 too), reals within a tolerance for ==/!=, strings lexicographically (optional case folding), vectors per component (all / any) or by length, transforms and objects for equality only. `filter` still routes points by the same comparisons. |
| Trig Op | `trig_op` | 1:1 | Sin, Cos, Tan, Asin, Acos, Atan, Atan2, DegToRad, RadToDeg (radians). Int64/Double give Double; vectors work per component. |
| Vector Op | `vector_op` | 1:1 | Dot, Cross, Normalize, Length, LengthSquared, Distance, DistanceSquared, Reflect (UE GetReflectionVector), Project, Lerp, RotateAroundAxis (degrees), Angle (degrees), ComponentMin/Max on Vector2, Vector, Vector4. Add/sub/mul/div stay on `math_op`. |
| Transform Op | `transform_op` | 1:1 | Compose (apply A then B, UE order), Invert, Lerp (slerped rotation), TransformPosition, InverseTransformPosition, TransformDirection, plus ApplyToPoints (moves every point by a transform attribute). |
| Rotator Op | `rotator_op` | 1:1 | Unchanged (Combine / Invert / Lerp / RotateAroundAxis on Euler or quaternion rotations). |
| Attribute Select | `attribute_select` | 1:1 | Min, Max or Median of an attribute; vectors by X/Y/Z/W, length or a custom axis; strings lexicographically. Out: a one-entry attribute set (value + index); Point: the selected entry. Ties keep the first entry. |
| Break Vector Attribute | `decompose_vector` | 1:1 | Now also Vector2, Vector4, Quaternion and Color inputs (fourth component into `w_attribute`). Also free via selectors: `position.x`, `uv.y`, `v4.w`. |
| Make Vector Attribute | `compose_vector` / `make_vector` | 1:1 | `compose_vector` gains `output_type` (Vector, Vector2, Vector4) and a W component; Int64/Double components accepted. |

Rows to **add** to the same table:

| UE node | Here | Status | Notes |
|---|---|---|---|
| Attribute Cast | `attribute_cast` | 1:1 | Any numeric, vector, Color, Quaternion, Transform or String attribute to another type, with explicit loss rules (table below). `@Source` output retypes in place; canonical attributes keep their types. |
| Attribute Remove Duplicates | `attribute_remove_duplicates` | 1:1 | Keeps the first entry of every distinct value combination of the listed attributes (any type, exact comparison). |

Row to **replace** in the Control Flow table:

| UE node | Here | Status | Notes |
|---|---|---|---|
| Gather | `gather` | 1:1 | Collects every data wired into In onto one pin, in wire order, without concatenating (that is `merge`). The Dependency Only pin only orders execution. |

Concept dictionary rows to **replace**:

| Unreal | Here | Notes |
|---|---|---|
| `$Position` | `position` (alias `$Position`) | Vector3 stream. `$Position` works as a selector anywhere a stream name is asked. |
| `$Position.X` | `position.x` / `$Position.X` | Component selectors work on any Vector, Vector2, Vector4, Quaternion or Color stream: `.x/.y/.z/.w` and `.r/.g/.b/.a`, case-insensitive. No swizzles. |
| `$Rotation` | `rotation` (alias `$Rotation`) | Unchanged otherwise (Euler degrees, Yaw/Pitch/Roll aliases). |
| `$Scale` | `size` (alias `$Scale`) | Unchanged caution about `size` doubling as bounds where no `bounds_min`/`bounds_max` exist. |
| `$BoundsMin` / `$BoundsMax` | `bounds_min` / `bounds_max` (aliases `$BoundsMin` / `$BoundsMax`) | Optional per-point streams; consumers fall back to `size` when absent. |
| `$Steepness` | `steepness` (alias `$Steepness`) | Optional Float stream, 1.0 when absent. |
| `$Color` | `color` (alias `$Color`) | A Color stream conventionally named `color`. |
| `@Source`, `@LastCreated` | `@Source` on the outputs of the attribute-op nodes; `@LastCreated` not supported | `@Source` (or an empty output name) writes back to the node's input attribute. Older nodes still need an explicit output name. |
| Attribute types (bool, int32, int64, float, double, vector2/3/4, quat, rotator, transform, string, soft object path) | Bool, Int, Int64, Float, Double, Vector2, Vector, Vector4, Quaternion, Transform, String, Color, Resource, NodeMesh/NodePath | Rotators are Euler-degree Vector streams. `attribute_cast` converts between types. |

### Attribute Cast loss rules

| From to | Rule |
|---|---|
| Float / Double to Int / Int64 | `float_to_int`: Truncate toward zero (default, UE), Round (halves away from zero), Floor, Ceil. NaN becomes 0; values beyond the 64-bit range clamp. |
| Int64 (or a converted real) to Int | `int_overflow`: Wrap keeps the low 32 bits (default, UE static_cast) or Clamp. |
| Double to Float, Int / Int64 to Float | Rounded to 32-bit precision. |
| Int / Int64 to Double | Exact up to 2^53. |
| any number to Bool | `value != 0`. Bool to a number is 0/1. |
| number to Vector2 / Vector / Vector4 | broadcast to every component; Color gets r = g = b = value, a = 1. Number to Quaternion or Transform: refused. |
| vector to a wider vector | pads with 0 (a Color's alpha with 1) |
| vector to a narrower vector | drops trailing components |
| Vector to Quaternion / Quaternion to Vector | Euler degrees conversion (the point rotation model) |
| Vector4 or Color to Quaternion, Quaternion to Vector4 or Color | components reinterpreted (x, y, z, w), not normalised |
| vector to a number | refused by default (UE); `vector_to_scalar` = First Component or Length allows it |
| Vector to Transform / Quaternion to Transform | translation-only / rotation-only transform |
| Transform to Vector / Quaternion | translation / rotation; to anything else refused |
| anything to String | `str()`, `true`/`false`, resource path, node name |
| String to a number | parsed; an unparsable string fails the node and names the point |
| String to a vector / Transform | `"x,y,z"` component lists (one number broadcasts) or a Godot literal such as `Vector3(1, 2, 3)` |
| Resource / NodeMesh / NodePath | only to String, or between the three object types |

## nodes_reference rows

Under **Attributes**:

| Node | Script File | Description |
| --- | --- | --- |
| **Attribute Cast** | [attribute_cast.gd](../nodes/attribute_cast.gd) | Converts an attribute to another type (Bool, Int, Int64, Float, Double, Vector2, Vector, Vector4, Color, Quaternion, Transform, String) with explicit truncation, wrap and padding rules. |
| **Attribute Remove Duplicates** | [attribute_remove_duplicates.gd](../nodes/attribute_remove_duplicates.gd) | Keeps the first entry of every distinct value combination of the listed attributes. |
| **Attribute Select** | [attribute_select.gd](../nodes/attribute_select.gd) | Selects the entry with the Min, Max or Median value of an attribute (vectors by axis, length or custom axis); outputs the value as an attribute set and the selected point. |
| **Attribute String Op** | [attribute_string_op.gd](../nodes/attribute_string_op.gd) | Per-point string operations: append, prepend, replace, case, contains / starts / ends with, format, length, trim, substring. |
| **Bitwise Op** | [bitwise_op.gd](../nodes/bitwise_op.gd) | And, Or, Xor, Not and shifts on Bool/Int/Int64 attributes, computed in 64 bits. |
| **Break Transform Attribute** | [break_transform_attribute.gd](../nodes/break_transform_attribute.gd) | Splits a Transform attribute into translation, Euler rotation, quaternion and scale attributes. |
| **Compare Op** | [compare_op.gd](../nodes/compare_op.gd) | Compares two attributes or an attribute and a constant (== != > >= < <=) into a Bool attribute; numbers, strings, vectors, transforms. |
| **Copy Attribute** | [copy_attribute.gd](../nodes/copy_attribute.gd) | Copies one or all attributes from a Source input onto a Target input by index, match attribute or nearest point, keeping types. |
| **Make Transform Attribute** | [make_transform_attribute.gd](../nodes/make_transform_attribute.gd) | Builds a Transform attribute from translation, rotation and scale attributes or constants. |
| **Merge Attributes** | [merge_attributes.gd](../nodes/merge_attributes.gd) | Merges every data on its input into one attribute set, appending entries (with numeric type promotion) or joining columns by index. |
| **Transform Op** | [transform_op.gd](../nodes/transform_op.gd) | Compose, invert, lerp and apply Transform attributes, transform vectors, or move points by a transform. |
| **Trig Op** | [trig_op.gd](../nodes/trig_op.gd) | Sin, Cos, Tan, their inverses, Atan2 and degree/radian conversion on numeric or vector attributes. |
| **Vector Op** | [vector_op.gd](../nodes/vector_op.gd) | Dot, cross, normalize, length, distance, reflect, project, lerp, rotate, angle and component min/max on Vector2/Vector/Vector4 attributes. |

Under **Utility**:

| Node | Script File | Description |
| --- | --- | --- |
| **Gather** | [gather.gd](../nodes/gather.gd) | Forwards every data wired into In unchanged and in order on one pin (no concatenation); the Dependency Only pin only orders execution. |

`node_templates.csv` rows (Template, Title):

```
"attribute_cast","Attribute Cast"
"attribute_remove_duplicates","Attribute Remove Duplicates"
"attribute_select","Attribute Select"
"attribute_string_op","Attribute String Op"
"bitwise_op","Bitwise Op"
"break_transform_attribute","Break Transform Attribute"
"compare_op","Compare Op"
"copy_attribute","Copy Attribute"
"gather","Gather"
"make_transform_attribute","Make Transform Attribute"
"merge_attributes","Merge Attributes"
"transform_op","Transform Op"
"trig_op","Trig Op"
"vector_op","Vector Op"
```

## DEPRECATIONS rows (section 2, changed semantics)

| Node / API | Before | Now | Since |
|---|---|---|---|
| `Data.registerStream`, container that does not match the declared type | Registered silently, producing a mistyped stream (for example a `PackedFloat32Array` declared Int) | When either side is an extended type (Vector2, Vector4, Transform, Int64, Double, including a `PackedFloat64Array` declared Float), **refused**: `push_error`, the error string is returned, nothing is registered. Between historical types, still registered, but with a warning. A full-suite run found one such case, in a test (`surface_sampler_test` registers an `Array` as String). A later round may refuse these too. | WP4a feat(pcg): extended attribute types |
| `Data.registerStream` / `findStream` with a `$`-prefixed name | `"$Density"` was an ordinary stream name: registering it created a stream literally called `$Density`, and reading it found only that stream | `$Position`, `$Rotation`, `$Scale`, `$Density`, `$Seed`, `$BoundsMin`, `$BoundsMax`, `$Steepness`, `$Color`, `$Index` (any case) address the canonical streams, unless a stream with that literal name already exists. Writing `$Density` now writes `density`. | WP4a |
| `Data._inferContainerType`, `PackedVector2Array` / `PackedInt64Array` / `PackedFloat64Array` / `Array[Transform3D]` | Invalid: `registerStream` without a type returned "Invalid container type" | Inferred as Vector2 / Int64 / Double / Transform. `PackedVector4Array` still infers Quaternion. | WP4a |
| `Data.scalar` / `set_data_attr` with a `Vector2` or `Transform3D` value | Warned "unsupported value type" and stored nothing | Stored as Vector2 / Transform | WP4a |
| Component selectors on Vector2, Vector4 and Quaternion streams (`uv.x`, `q.w`) | `push_error` and null | Read and write the component as a Float stream. `position.w` on a Vector stream returns null without logging an error when read through `first`/`value_at`/`container`. `findStream` still logs it. | WP4a |
| `filteredStream` with an unknown `data_type` | Returned null silently | Returns null with `push_error` | WP4a |
| `filter`, two integer operands (Int / Int64 streams) | Compared as floats | Compared as integers, so Int64 values above 2^53 compare exactly. **No output change** for Int (32-bit) streams. Int64 and Double streams are now accepted as numeric. | WP4a |
| `expression`, `$Name` that matches no stream exactly or case-insensitively | Left bare, usually a parse error | Resolved through the selector aliases (`$Scale` to `size`, `$BoundsMin` to `bounds_min`, ...) when that stream is bound. Vector2, Vector4, Quaternion and Transform3D results register with their own type; they used to fail with "Failed to identify type of expression result". A numeric result written into an existing Int64/Double stream keeps that type. | WP4a |
| `decompose_vector` with a Vector2, Vector4, Quaternion or Color input | Error "is not a Vector3" | Writes per-component Float streams (x, y and also z, w for 4-component inputs) | WP4a |
| Data inspector table, columns of Color, Quaternion or the new types | Reused the previous column's formatter, which printed wrong values or raised a script error | Shown with a generic `str()` formatter | WP4a fix(editor): table view |

No output change for any stock demo graph: the golden and seed-zero baselines are unchanged.

## Audit: DataType switches in the addon

`grep -rn "DataType\." demo/addons/flow_nodes_editor --include=*.gd` finds about 620
references in about 110 files. These are the `match` / `if` chains that branch on the type:

| File | What it does with a type | New types | Action |
|---|---|---|---|
| `flow_data.gd` | containers, write, filter, clone, infer, sub-streams | handled | changed (this package) |
| `nodes/add_attribute.gd` (+settings) | constant per type | handled: `cte_vector2`, `cte_vector4`, `cte_transform`, `cte_int64`, `cte_double`, and `cte_quaternion` (Quaternion was missing too) | changed |
| `nodes/filter.gd` | numeric comparison | Int64, Double handled; exact integer comparison | changed |
| `nodes/compose_vector.gd` / `decompose_vector.gd` | Vector only | Vector2, Vector4 (+Quaternion, Color for decompose) | changed |
| `nodes/expression.gd` | result type to stream type | Vector2, Vector4, Quaternion, Transform results; Int64/Double kept | changed |
| `nodes/attribute_set_to_point.gd` | Vector position/rotation/size | new `transform_attribute_name` | changed |
| `nodes/point_to_attribute_set.gd` | `_clone_stream_container` | falls back to `container.duplicate()`, correct for every new type | none (tested) |
| `nodes/attribute_rename.gd`, `remove_attribute.gd` | type-agnostic | work | none (tested) |
| `nodes/merge.gd` | `newContainerOfType` + `append_array` | work; a type clash still drops that bulk's values with a warning (use `merge_attributes` to promote) | none (tested through the evaluator) |
| `nodes/partition.gd` | keys by `"%s" % value` | Vector2/Vector4/Transform/Int64 work; **Double keys that differ only after ~14 significant digits share a partition** (string formatting) | none, documented |
| `nodes/math_op.gd` | Float/Int/Vector/Color pairs | new types: error "incompatible/unsupported data types". Cast first, or use `vector_op` / `trig_op` | none, documented |
| `nodes/sort.gd` | Float/Int/String (native sort) | new types: error "Unsupported sort data type". Cast to Float/Int first | none, documented |
| `nodes/reduce.gd` | Float/Int/Vector | new types: error | none, documented |
| `nodes/attribute_filter_range.gd` | numeric value per type | new types are rejected by its type check (error) | none, documented |
| `nodes/attribute_noise.gd`, `mutate_seed.gd`, `point_neighborhood.gd`, `texture_sampler.gd`, `sample_terrain_layers.gd`, `compute_kernel.gd` | numeric / vector readers | new types: their "unsupported type" errors | none, documented |
| `nodes/load_data_table.gd`, `load_pcg_data_asset.gd`, `assets.gd` | produce historical types only | not affected | none |
| `nodes/partition.gd`, `output.gd`, `loop.gd`, `combine_points.gd`, `copy.gd`, `duplicate_point.gd`, `difference.gd`, `grid_fill_bounds.gd`, `point_offsets.gd`, `sample_points.gd` | `newContainerOfType` / `filteredStream` / `cloneStream` per stream | work for every type through flow_data | none |
| `visualization/table_view.gd` | cell formatting | generic fallback | changed |

Editor and evaluator files that branch on `DataType` and do **not** handle the new
types. I did not edit them (they belong to WP1):

| File | Gap | Suggested change |
|---|---|---|
| `data_inspector.gd` `onColumnBegins`, `_row_sort_value`, `update_visible_rows` | No branch for Color, Quaternion, Vector2, Vector4, Transform, Int64, Double. Display now works through the table_view fallback (str()), but Vector2/Vector4 columns are not split into components, sorting uses the string form, and the text filter never matches these columns. `tv.cell_contents = null` (lines ~101 and ~107) assigns a property TableView does not have. | Add branches: split Vector2/Vector4/Quaternion into component columns like Vector, format Int64 with `%d` and Double with more digits, and add matching filter and sort cases. Replace `tv.cell_contents = null` with `tv.setCellCallback(Callable())`. |
| `node.gd` `getColorForFlowDataType`, `getGdScriptTypeForFlowDataType`, `getFlowDataTypeFromGdScriptType`, `newStream` (callable path) | New types fall to the default colour and to `TYPE_NIL` / Invalid, so a settings property of type Vector2/Vector4/Transform3D cannot be exposed as a typed port or graph parameter. `newStream` with a Callable initialiser errors for the new types (a fill value works). | Map TYPE_VECTOR2 to Vector2, TYPE_VECTOR4 to Vector4, TYPE_TRANSFORM3D to Transform and back; give the new types colours; add the new containers to the Callable branch. |
| `node_draw_debug.gd` `_can_modulate_stream` / `_stream_to_intensities` | Debug tint ignores Int64, Double, Vector2, Vector4 | Treat Int64/Double like Int/Float and Vector2/Vector4 by length. |
| `graph_input_parameter.gd`, `flow_graph_parameters_editor.gd` | Graph parameters can't be any of the new types (no `cte_*` field or editor row) | Add `cte_vector2`, `cte_vector4`, `cte_transform`, `cte_int64`, `cte_double` and rows, if graph parameters of these types are wanted. |
| `flow_nodes_io.gd` `_coerce_input_data` | Uses `getFlowDataTypeFromObject`, so a raw `Vector2` / `Transform3D` runtime input is rejected; a `FlowData.Data` input of any type works | Follows from the `node.gd` mapping above. |

## Design notes and limits

- Operand conventions follow `boolean`: In A plus an optional In B pin. Operand B
  is read from In B when that input holds the attribute, otherwise from In A, or
  from a constant. A selector that names no attribute fails the node; it never
  silently becomes a constant.
- `compare_op` constants are text parsed as the type of operand A (`"1"`,
  `"true"`, `"1,2,3"`, `Vector3(1, 2, 3)`).
- `merge_attributes` overrides `run()` (like `merge`) to see every bulk on its pin.
  `gather` relies on the evaluator running `execute()` once per bulk of pin 0.
- `copy_attribute` NearestPoint uses `GDKdTree` when the extension is loaded,
  otherwise a brute-force scan. Ties may resolve differently between the two.
- `make_transform_attribute` / `transform_op ApplyToPoints` compose point
  transforms as `R * S` (Godot and UE TRS order). The point transform helpers
  elsewhere (`TransformsStream.atIndex`) use `Basis.scaled` (`S * R`). The two
  agree for uniform scale only.
- I left out `Make/Break Rotator Attribute` (rotators are Euler Vector streams, so
  `compose_vector` / `decompose_vector` cover them) and `Get Attribute From Point
  Index` (WP4b).
- Not done: a `$Transform` virtual selector (read the point transform as a Transform
  attribute). `make_transform_attribute` with its defaults does the same job.

## Tests

New suites in `demo/tests/attributes/` (all pass; 101 cases):

- `flow_data_types_test.gd`: every DataType through newContainerOfType, writeValue,
  registerStream, filter, broadcast filter, cloneStream, duplicate, merge-style
  append, emptyLike, `@data`, content_hash. It also checks mismatch refusal, the
  Vector4 inference rule, precision, scalar inference and component access. A
  DataType without a sample fails the walk.
- `selector_alias_test.gd`: every alias, case, components, writes, literal-name
  precedence, and the unchanged pre-existing selectors.
- `table_view_generic_cells_test.gd`: the fallback formatter.
- One suite per node family: `attribute_cast_test.gd`, `compare_op_test.gd`,
  `vector_trig_bitwise_test.gd`, `transform_nodes_test.gd`, `copy_attribute_test.gd`,
  `attribute_string_op_test.gd`, `merge_gather_test.gd` (with evaluator graphs for
  gather, merge and merge_attributes), `select_dedupe_and_registry_test.gd` (also
  resolves every new template through `FlowNodeRegistry`).
- `existing_nodes_new_types_test.gd`: the audited nodes with the new types.
