@tool
class_name ComputeKernelNodeSettings
extends NodeSettings

# Settings for the `compute_kernel` node: a pragmatic GPU escape hatch that runs
# a user-supplied GLSL compute shader over the incoming point streams via
# RenderingDevice. See docs/_roadmap_notes/gpu_compute_kernel.md for the full
# buffer/binding contract and the vec3 packing convention.

## How the GLSL compute source is supplied.
##  - INLINE: type/paste the shader body into `shader_source` below.
##  - FILE:   point `shader_file_path` at a .glsl RDShaderFile resource.
enum eShaderMode {
	## Specifies that the GLSL shader code is provided inline within the inspector.
	INLINE,
	## Specifies that the GLSL shader code is loaded from an external `.glsl` file.
	FILE,
}

## Float streams are packed 1 float per point. Vector3 streams are packed as
## documented by this enum so the GLSL side knows the stride to expect.
##  - VEC4_PADDED: each point is 4 floats (x, y, z, 0.0). 16-byte stride,
##                 std430-friendly, read as `vec4` (use .xyz). DEFAULT.
##  - VEC3_TIGHT:  each point is 3 floats (x, y, z). 12-byte stride. Matches a
##                 GLSL `float[]` flat buffer indexed manually (i*3+0..2).
##                 std430 `vec3[]` arrays are NOT this layout; only pick this if
##                 your shader reads a flat float array.
enum eVec3Packing {
	## Pads 3D vectors to 4 floats (aligns with standard std430 vec4 layouts).
	VEC4_PADDED,
	## Packs 3D vectors tightly as 3 consecutive floats (aligns with tightly packed vec3 arrays).
	VEC3_TIGHT,
}

@export_group("Compute Kernel")

## Selects where the compute shader GLSL code is loaded from.
@export var shader_mode : eShaderMode = eShaderMode.INLINE:
	set(value):
		if shader_mode != value:
			shader_mode = value
			notify_property_list_changed()

## The inline GLSL compute shader source code.[br]
## - Must begin with a `#version` directive (e.g. `#version 450`).[br]
## - Do not include the `#[compute]` tag as it is sent directly to the Godot RenderingDevice compilation API.
@export_multiline var shader_source : String = """#version 450

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

// Example: read input float stream at binding 0, write it doubled to binding 1.
layout(set = 0, binding = 0, std430) restrict readonly buffer InBuf {
	float data[];
} in_buf;

layout(set = 0, binding = 1, std430) restrict writeonly buffer OutBuf {
	float data[];
} out_buf;

// Binding reserved for the params UBO/SSBO is optional; point_count is passed
// as the first output-independent uniform when `bind_point_count` is enabled.
layout(set = 0, binding = 7, std430) restrict readonly buffer Params {
	uint point_count;
} params;

void main() {
	uint idx = gl_GlobalInvocationID.x;
	if (idx >= params.point_count) {
		return;
	}
	out_buf.data[idx] = in_buf.data[idx] * 2.0;
}
"""

## The file path to the external `.glsl` RDShaderFile resource to run.
@export_file("*.glsl") var shader_file_path : String = ""

@export_group("Bindings")

## The GPU input buffer bindings mapping point streams to buffer binding indices.[br]
## - Format: 'stream_name:binding_index' (e.g. 'position:0' or '@last:0').[br]
## - Supports Float and Vector3/vec3 streams.
@export var input_bindings : PackedStringArray = PackedStringArray(["@last:0"])

## The GPU output buffer bindings mapping buffer binding indices back to named point streams.[br]
## - Format: 'binding_index:stream_name:type' (e.g. '1:result:float' or '2:normal:vec3').
@export var output_bindings : PackedStringArray = PackedStringArray(["1:result:float"])

## When true, a small std430 storage buffer holding `uint point_count` is bound at `point_count_binding` so the shader can early-out past the last point.
@export var bind_point_count : bool = true

## Binding index for the point_count params buffer (only used when bind_point_count is true). Keep it clear of your input/output bindings.
@export var point_count_binding : int = 7

@export_group("Dispatch")

## Local workgroup size on X. Must match the `layout(local_size_x = ...)` in the shader. The node dispatches ceil(point_count / local_size_x) workgroups on X.
@export var local_size_x : int = 64

## How Vector3 streams are packed into / out of the GPU buffers.
@export var vec3_packing : eVec3Packing = eVec3Packing.VEC4_PADDED

func _init():
	super._init()
	resource_name = "Compute Kernel"

func exposeParam( name : String ) -> bool:
	if name == "shader_source":
		return shader_mode == eShaderMode.INLINE
	if name == "shader_file_path":
		return shader_mode == eShaderMode.FILE
	if name == "point_count_binding":
		return bind_point_count
	return true
