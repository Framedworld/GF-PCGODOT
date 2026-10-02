@tool
class_name FlowMeshSpawnEntry
extends Resource

## One mesh choice for the Spawn Meshes node (Unreal's Static Mesh Spawner
## descriptor). Spawn Meshes groups the points that pick entries with the same
## render settings into one MultiMeshInstance3D (see FlowSpawnUtil.entry_group_key).
##
## Saved as an embedded sub-resource of the graph's node settings, so a graph
## .tres keeps every field.

enum eCollisionMode {
	## No collision is generated.
	None,
	## A BoxShape3D sized to the mesh AABB (offset to its centre).
	BoxFromBounds,
	## A ConvexPolygonShape3D built from the mesh (Mesh.create_convex_shape).
	Convex,
	## A ConcavePolygonShape3D with every triangle (Mesh.create_trimesh_shape). Static only.
	Trimesh,
}

enum eCollisionBodies {
	## One FlowInstancedCollision3D (a StaticBody3D) per MultiMesh, with one shape
	## owner per instance that shares a single Shape3D. One node, whatever the count.
	PerMultiMesh,
	## One StaticBody3D + CollisionShape3D per instance (two nodes per instance).
	## Use when gameplay needs a distinct collider object per instance.
	PerInstance,
}

## Mesh drawn for the points that select this entry.
@export var mesh : Mesh
## Name matched by the "Attribute Name" selection (a String attribute). Empty:
## the mesh's resource_name, then its file basename.
@export var entry_name : String = ""
## Relative weight for the "Weighted" selection. 0 never picks the entry.
@export_range(0.0, 1000.0, 0.01, "or_greater") var weight : float = 1.0

@export_group("Rendering")
## Material applied to the whole MultiMeshInstance3D (material_override).
@export var material_override : Material
## GeometryInstance3D.cast_shadow of the generated MultiMeshInstance3D.
@export var cast_shadow : GeometryInstance3D.ShadowCastingSetting = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
## Visibility range start (0 = always visible up close).
@export var visibility_range_begin : float = 0.0
## Fade/hysteresis margin at the start of the visibility range.
@export var visibility_range_begin_margin : float = 0.0
## Visibility range end (0 = no limit).
@export var visibility_range_end : float = 0.0
## Fade/hysteresis margin at the end of the visibility range.
@export var visibility_range_end_margin : float = 0.0
## How the instance fades at the visibility range limits.
@export var visibility_range_fade_mode : GeometryInstance3D.VisibilityRangeFadeMode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
## VisualInstance3D render layers.
@export_flags_3d_render var render_layers : int = 1
## Global illumination mode.
@export var gi_mode : GeometryInstance3D.GIMode = GeometryInstance3D.GI_MODE_STATIC

@export_group("Custom Data")
## Point attributes packed into MultiMesh per-instance custom data (INSTANCE_CUSTOM
## in shaders), in order: Float/Int/Bool fill one channel, Vector three,
## Color/Quaternion four. Channels beyond the fourth are dropped; unused ones are 0.
@export var custom_data_attributes : PackedStringArray = PackedStringArray()

@export_group("Collision")
## Collision generated for each instance.
@export var collision_mode : eCollisionMode = eCollisionMode.None
## Body layout: one shared body per MultiMesh (default) or one body per instance.
@export var collision_bodies : eCollisionBodies = eCollisionBodies.PerMultiMesh
## Physics layers of the generated bodies.
@export_flags_3d_physics var collision_layer : int = 1
## Physics mask of the generated bodies.
@export_flags_3d_physics var collision_mask : int = 1

func _init():
	resource_name = "Mesh Spawn Entry"

## The name the "Attribute Name" selection matches against.
func get_match_name() -> String:
	if entry_name.strip_edges() != "":
		return entry_name.strip_edges()
	if mesh == null:
		return ""
	if mesh.resource_name != "":
		return mesh.resource_name
	if mesh.resource_path != "" and not mesh.resource_path.contains("::"):
		return mesh.resource_path.get_file().get_basename()
	return ""

func has_collision() -> bool:
	return collision_mode != eCollisionMode.None
