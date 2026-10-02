@tool
class_name FlowWorldGrid
extends RefCounted

## Cell math for hierarchical generation (Unreal's HiGen grid). Pure static
## helpers, no state; safe on any thread.
##
## A level is identified by its grid size in world units (a power of two, an
## int). Level 0 (UNBOUNDED) is the Unbounded level: executed once for the
## whole world. A cell is (level, coord : Vector2i) on the XZ plane:
##
##   cell box    AABB(Vector3(cx * size, world_min_y, cz * size),
##                    Vector3(size, world_height, size))
##   ownership   half-open on X and Z: min <= p < max, so a point on the edge
##               shared by two cells belongs to exactly one of them (the one on
##               the max side of the edge). Y is closed: min <= p.y <= max
##               (cells never touch vertically).
##   coord_of(p) Vector2i(floor(p.x / size), floor(p.z / size)); for a power of
##               two size the division is exact, so coord_of(p) == c exactly
##               when p is owned by the box of c.
##
## Execution bounds of a cell are its box intersected with the world bounds on
## XZ (Unreal intersects a partition actor's bounds with the original
## component's bounds); on the Unbounded level they are the world bounds.

const UNBOUNDED := 0
## Largest grid size (2^30). Level ids are stored in PackedInt32Array, so a
## larger power of two would wrap; larger (or infinite) sizes are clamped.
const MAX_GRID_SIZE := 1 << 30

## Nearest power of two >= 1 (same rounding as GridSizeNodeSettings: ties go
## up), at most MAX_GRID_SIZE.
static func snap_grid_size(value : float) -> int:
	if value <= 1.0:
		return 1
	if not (value < float(MAX_GRID_SIZE)):
		return MAX_GRID_SIZE
	var exp_floor := int(floor(log(value) / log(2.0)))
	var lower := pow(2.0, exp_floor)
	var upper := pow(2.0, exp_floor + 1)
	if (value - lower) < (upper - value):
		return int(lower)
	return int(upper)

## True when `a` is a coarser level than `b` (Unbounded is the coarsest).
static func is_coarser(a : int, b : int) -> bool:
	if a == b:
		return false
	if a == UNBOUNDED:
		return true
	if b == UNBOUNDED:
		return false
	return a > b

## Integer floor division (rounds toward negative infinity).
static func floor_div(a : int, b : int) -> int:
	var q := a / b
	if (a % b != 0) and ((a < 0) != (b < 0)):
		q -= 1
	return q

## Cell coordinate of a world position on level `size`.
static func coord_of(world_pos : Vector3, size : int) -> Vector2i:
	if size <= 0:
		return Vector2i.ZERO
	return Vector2i(int(floor(world_pos.x / size)), int(floor(world_pos.z / size)))

## Coordinate on the coarser level `parent_size` of the cell that contains
## cell `coord` of level `size`. Unbounded parents are always (0, 0).
static func parent_coord(coord : Vector2i, size : int, parent_size : int) -> Vector2i:
	if parent_size <= 0 or size <= 0:
		return Vector2i.ZERO
	return Vector2i(floor_div(coord.x * size, parent_size), floor_div(coord.y * size, parent_size))

## The full box of a cell (not clipped to the world bounds).
static func cell_aabb(coord : Vector2i, size : int, world_bounds : AABB) -> AABB:
	if size <= 0:
		return world_bounds
	return AABB(Vector3(coord.x * size, world_bounds.position.y, coord.y * size),
		Vector3(size, world_bounds.size.y, size))

## Execution bounds of a cell: its box intersected with `world_bounds` on XZ.
## The Unbounded level (size 0) returns the world bounds. A cell outside the
## world gives a box of zero size at the clamped corner.
static func execution_bounds(coord : Vector2i, size : int, world_bounds : AABB) -> AABB:
	if size <= 0:
		return world_bounds
	var box := cell_aabb(coord, size, world_bounds)
	var mn := Vector3(maxf(box.position.x, world_bounds.position.x), world_bounds.position.y, maxf(box.position.z, world_bounds.position.z))
	var mx := Vector3(minf(box.end.x, world_bounds.end.x), world_bounds.end.y, minf(box.end.z, world_bounds.end.z))
	mx.x = maxf(mx.x, mn.x)
	mx.z = maxf(mx.z, mn.z)
	return AABB(mn, mx - mn)

## Half-open ownership test of a world position against execution bounds
## (X and Z: min <= p < max; Y: min <= p <= max).
static func owns(bounds : AABB, p : Vector3) -> bool:
	return p.x >= bounds.position.x and p.x < bounds.end.x \
		and p.z >= bounds.position.z and p.z < bounds.end.z \
		and p.y >= bounds.position.y and p.y <= bounds.end.y

## True when the box [box_min, box_max] overlaps execution bounds with the
## same half-open convention (a box that only touches the max side does not
## overlap).
static func overlaps(bounds : AABB, box_min : Vector3, box_max : Vector3) -> bool:
	return box_max.x >= bounds.position.x and box_min.x < bounds.end.x \
		and box_max.z >= bounds.position.z and box_min.z < bounds.end.z \
		and box_max.y >= bounds.position.y and box_min.y <= bounds.end.y

## Bounds grown by `margin` on every side (a negative margin shrinks them).
static func grow(bounds : AABB, margin : float) -> AABB:
	if margin == 0.0:
		return bounds
	var grown := AABB(bounds.position - Vector3.ONE * margin, bounds.size + Vector3.ONE * (2.0 * margin))
	grown.size = grown.size.max(Vector3.ZERO)
	return grown

## Every cell of level `size` whose box overlaps `area` clipped to
## `world_bounds` with positive area (a max edge exactly on a cell boundary does
## not reach the next cell), in row-major order (z, then x). The Unbounded
## level returns [(0, 0)].
static func cells_in(area : AABB, size : int, world_bounds : AABB) -> Array[Vector2i]:
	var result : Array[Vector2i] = []
	if size <= 0:
		result.append(Vector2i.ZERO)
		return result
	var mn_x := maxf(area.position.x, world_bounds.position.x)
	var mn_z := maxf(area.position.z, world_bounds.position.z)
	var mx_x := minf(area.end.x, world_bounds.end.x)
	var mx_z := minf(area.end.z, world_bounds.end.z)
	if mx_x <= mn_x or mx_z <= mn_z:
		return result
	var x0 := int(floor(mn_x / size))
	var z0 := int(floor(mn_z / size))
	var x1 := int(ceil(mx_x / size)) - 1
	var z1 := int(ceil(mx_z / size)) - 1
	for cz in range(z0, z1 + 1):
		for cx in range(x0, x1 + 1):
			result.append(Vector2i(cx, cz))
	return result

## Distance from `p` to the box (0 inside).
static func distance_to_aabb(p : Vector3, box : AABB) -> float:
	var q := p.clamp(box.position, box.end)
	return p.distance_to(q)

## Distance from `p` to the box footprint on the XZ plane (0 inside).
static func distance_to_footprint(p : Vector3, box : AABB) -> float:
	var qx := clampf(p.x, box.position.x, box.end.x)
	var qz := clampf(p.z, box.position.z, box.end.z)
	return Vector2(p.x - qx, p.z - qz).length()

## Container name of a cell component: FlowCell_L<level>_<x>_<z>
## (level 0 is the Unbounded run, FlowCell_L0_0_0).
static func cell_name(level : int, coord : Vector2i) -> String:
	return "FlowCell_L%d_%d_%d" % [level, coord.x, coord.y]
