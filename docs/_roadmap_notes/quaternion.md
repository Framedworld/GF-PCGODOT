# Quaternion rotation model — implementation note

Implements the "Quaternion rotation model" roadmap item. Euler degrees remain
the default authoring representation; quaternions are an additive, opt-in path.

## What was added

### 1. New `DataType.Quaternion`
- Added `Quaternion` to the `FlowData.DataType` enum (before `Invalid`).
- Storage container is `PackedVector4Array` — each rotation is a `Vector4(x,y,z,w)`
  holding a unit quaternion. `PackedVector4Array` was chosen because
  `registerStream` auto-detects container types via `is`, so the new type slots
  into the existing detection chain cleanly.
- Plumbed through every container-handling method in `flow_data.gd`:
  - `Data.newContainerOfType` → returns `PackedVector4Array`
  - `Data.writeValue` → accepts a `Quaternion` (converted to Vector4) or a Vector4
  - `Data.registerStream` auto-detect → `PackedVector4Array` ⇒ `DataType.Quaternion`
  - `Data.cloneStream` → duplicates as `PackedVector4Array`
  - `Data.filteredStream` → index-filters the Vector4 container (so `filter()` works)
  - `duplicate()` already type-agnostic (uses `.duplicate()` per container) — no change needed.

### 2. New canonical stream `AttrRotationQuat` = `&"rotation_quat"`
- Optional. When **present**, it WINS over the Euler `rotation` stream when
  `getTransformsStream()` builds point bases. When **absent**, the Euler path is
  byte-for-byte the historical behavior.
- `TransformsStream` gained `quats : PackedVector4Array` and `use_quats : bool`,
  plus a `basisAt(id)` helper used by `atIndex`/`atIndexAbsScale`. When
  `use_quats` is true the basis comes from the quaternion; otherwise from the
  Euler value (unchanged code path).
- When the quaternion path is active, `TransformsStream.eulers` is still
  populated (derived from the quats) so any consumer that reads `.eulers`
  directly (e.g. `point_offsets.gd`) keeps working with consistent values.

### 3. New node `nodes/rotator_op.gd` (+ `rotator_op_settings.gd`)
- Category: `"Point Ops"`. Aliases: `Rotator Op`, `Quaternion Op`, `Rotation Op`.
- Operations: `Combine`, `Invert`, `Lerp`, `RotateAroundAxis` — all converted
  through `Quaternion` internally.
  - Combine: `current * operand` (operand applied in local space).
  - Invert: `current.inverse()`.
  - Lerp: `current.slerp(operand, alpha)`.
  - RotateAroundAxis: `Quaternion(axis, angle) * current` (world-space pre-rotation).
- Reads rotation from `rotation_quat` if present, else from Euler `rotation`.
- Writes back in the user-selected representation (`Euler` default, or
  `Quaternion`). To avoid the two representations disagreeing downstream, writing
  Euler drops any `rotation_quat` stream and vice-versa.
- Helper conversions added to `flow_data.gd`: `vec4ToQuat`, `quatToVec4`,
  `quatToBasis`, `basisToQuat`, `eulerToQuat`, `quatToEuler`.
- Auto-discovered by filename (no registry edit); `.gd.uid` files generated to
  match repo convention.

## Backward-compatibility guarantees
- The Euler `eulerToBasis` / `basisToEuler` paths are untouched; Euler stays the
  authoring default.
- `getTransformsStream()` only diverges when a `rotation_quat` stream exists.
  Every existing graph (no `rotation_quat`) takes the identical Euler path,
  including the same position/rotation/size presence + length validation.
- The new `DataType.Quaternion` is purely additive — no existing enum values
  shifted (`Quaternion` inserted before `Invalid = 999`, which keeps its value).

## Non-goals / assumptions
- No full `Transform`-typed attribute (per roadmap; compose/decompose cover the rest).
- The data inspector / debug-draw UI were intentionally not modified (out of the
  allowed edit scope); a Quaternion stream displays via the generic value path.
- `rotation_quat` values are assumed to be unit quaternions; node outputs are
  normalized after each operation.
