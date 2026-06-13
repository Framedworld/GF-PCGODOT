# compute_kernel — GPU execution escape hatch

Implements the pragmatic part of the **GPU execution** roadmap item: a single
node that runs a user-supplied GLSL compute shader over the incoming point
streams via a local `RenderingDevice`. This is the equivalent of UE's *Custom
HLSL* node — an explicit escape hatch — NOT a transparent "execute the graph on
the GPU" flag. Node-graph-on-GPU is explicitly out of scope.

Files (new, auto-discovered by filename, no registry edit):
- `demo/addons/flow_nodes_editor/nodes/compute_kernel.gd`
- `demo/addons/flow_nodes_editor/nodes/compute_kernel_settings.gd`

Node meta: title "Compute Kernel", category **Advanced**,
aliases `["Compute Shader", "GPU Kernel", "Custom HLSL"]`, one input "In", one
output "Out".

## Settings

- **shader_mode** — `INLINE` or `FILE`.
- **shader_source** (INLINE) — multiline GLSL. Fed to `RDShaderSource.source_compute`,
  so it must start at `#version 450` and must NOT carry the `#[compute]` tag
  (that tag is only for the `.glsl` RDShaderFile format).
- **shader_file_path** (FILE) — path to a `.glsl` RDShaderFile resource;
  compiled SPIR-V is pulled with `get_spirv()`.
- **input_bindings** — `PackedStringArray`, each `"<stream_name>:<binding>"`
  (e.g. `"position:0"`, `"@last:0"`). The named stream is packed and bound at
  that set-0 binding.
- **output_bindings** — `PackedStringArray`, each
  `"<binding>:<stream_name>:<float|vec3>"` (e.g. `"1:result:float"`). After
  dispatch the buffer is read back and registered as that stream.
- **bind_point_count** / **point_count_binding** — when enabled, a small std430
  storage buffer holding `uint point_count` is bound so the shader can early-out
  past the last point.
- **local_size_x** — must match the shader's `layout(local_size_x = …)`. The
  node dispatches `ceil(point_count / local_size_x)` workgroups on X (1,1 on Y/Z).
- **vec3_packing** — `VEC4_PADDED` (default) or `VEC3_TIGHT`.

## Buffer / binding contract

All buffers are **std430 storage buffers** bound in **set 0** at the declared
binding indices. The node never auto-assigns bindings — you map stream↔binding
explicitly, exactly like wiring Custom HLSL.

- Inputs are packed into `PackedFloat32Array` → `to_byte_array()` →
  `storage_buffer_create`.
- Outputs are allocated zero-initialised at `point_count * floats_per_point * 4`
  bytes, then read back with `buffer_get_data()` → `to_float32_array()`.
- Int streams are promoted to float on the way in (read them as `float` in GLSL).
- One invocation is intended per point; use `gl_GlobalInvocationID.x` as the
  point index and guard `idx >= point_count` (the dispatch rounds up).

## vec3 packing convention

Vector3 streams are packed by **vec3_packing**:

- **VEC4_PADDED (default)** — 4 floats per point `(x, y, z, 0.0)`, 16-byte
  stride. Read/write as `vec4` in GLSL and use `.xyz`. This is std430-friendly
  (a std430 `vec3` already occupies 16 bytes of alignment), so it is the safe
  default for `vec3[]`/`vec4[]` arrays.
- **VEC3_TIGHT** — 3 floats per point `(x, y, z)`, 12-byte stride. Only correct
  when the shader reads a **flat `float[]`** indexed manually (`i*3+0..2`). A
  std430 `vec3[]` array is NOT laid out this way; do not use TIGHT with a
  declared `vec3[]`.

`float` streams are always 1 float per point. Output vec3 buffers are unpacked
with the same stride used for packing.

## Graceful fallback (never crash the editor)

Every step is guarded. On any failure the node calls `setError(...)` with a
clear message and emits a **duplicate of the input unchanged** on output 0
(`_fallback`), so a graph with this node still produces valid downstream data.
Failure cases handled:

- `create_local_rendering_device()` returns null (no compute-capable GPU/driver).
- Inline compilation fails (`get_stage_compile_error` non-empty) or returns null
  SPIR-V; FILE mode missing path / not an RDShaderFile / compile error in the
  baked SPIR-V.
- Malformed `input_bindings`/`output_bindings` strings.
- Input stream not found or of an unsupported type (only Float/Int/Vector3 pack).
- `storage_buffer_create`, `uniform_set_create`, `compute_pipeline_create`, or
  `registerStream` failing.

Empty input (`point_count == 0`) short-circuits to a clean passthrough. All
created RIDs are tracked and freed on every exit path, and the local
`RenderingDevice` is `free()`d after each run.
