# PCGODOT Node Library Reference

A complete reference of all 167 node templates in the PCGODOT framework (every script in `nodes/` except the `*_settings.gd` files), grouped by category. Clicking on a node name links directly to its implementation file.

## 📌 Table of Contents
- [Assets](#-assets)
- [Attributes](#-attributes)
- [Generators](#-generators)
- [Math](#-math)
- [Meshes](#-meshes)
- [Spatial](#-spatial)
- [Splines](#-splines)
- [Utility](#-utility)

---

## 📂 Assets

| Node | Script File | Description |
| --- | --- | --- |
| **Apply On Actor** | [apply_on_actor.gd](../nodes/apply_on_actor.gd) | Applies point attributes and optional transforms onto existing scene nodes. `property_overrides` maps point attributes to (nested) property paths of each target. |
| **Assets** | [assets.gd](../nodes/assets.gd) | Generates a list of assets. Useful in combination with the Match And Set node, this node generates a list of meshes with some attribute/tag and weight assigned. |
| **Create Target Node** | [create_target_node.gd](../nodes/create_target_node.gd) | Creates (or reuses) a named Node3D container with groups and an owner policy and outputs a reference to it (`@data.target` by default). Spawners parent their content under it through `spawn_parent_attribute`. Unreal's Create Target Actor. |
| **Spawn Meshes** | [spawn_meshes.gd](../nodes/spawn_meshes.gd) | Spawns a Mesh Instance on each point, applying the translation, rotation and scale. The instanced mesh can be specified by point if a stream contains the mesh resource to be spawned. The generates meshes are MultiMeshInstance3D. `mesh_entries` (FlowMeshSpawnEntry descriptors) add per-entry weight, material override, shadows, visibility range, render layers, GI mode, per-instance custom data and collision, picked by weight, attribute index, attribute name or cycling. Optional `spawn_parent_attribute` and instance pooling (`reuse_instances`). |
| **Spawn Scenes** | [spawn_scenes.gd](../nodes/spawn_scenes.gd) | Similar to spawn meshes but a full scene is instantiated on each node. A set of properties can be transfered from the nodes to each instanced scene. `property_overrides` maps point attributes to (nested) property paths of the instance (`light_energy`, `position:x`, `Child/Light:light_energy`, `%Unique:prop`), with type coercion. Optional `spawn_parent_attribute` and instance pooling (`reuse_instances`). |
| **Spawn Spline Mesh** | [spawn_spline_mesh.gd](../nodes/spawn_spline_mesh.gd) | Deforms a mesh along each segment of the input splines (Path3D nodes or spline data). One MeshInstance3D per segment, with a bent ArrayMesh cached per mesh and segment. Forward axis, tangent and up handling, scale along/across, per-segment mesh entries. Accepts composite spline data (Get Spline Data, Merged): every spline part is spawned whole, in merge order. |

## 📂 Attributes

| Node | Script File | Description |
| --- | --- | --- |
| **Add Attribute** | [add_attribute.gd](../nodes/add_attribute.gd) | Add a new constant stream to the input set If the input is not given a single entry with the constant value is created (intentional schema-row idiom: chained Add Attribute nodes build a one-row attribute set). |
| **Add Tags** | [add_tags.gd](../nodes/add_tags.gd) | Adds one or more tags to FlowData. |
| **Attribute Cast** | [attribute_cast.gd](../nodes/attribute_cast.gd) | Converts an attribute to another type (Bool, Int, Int64, Float, Double, Vector2, Vector, Vector4, Color, Quaternion, Transform, String) with explicit truncation, wrap and padding rules. |
| **Attribute Filter Range** | [attribute_filter_range.gd](../nodes/attribute_filter_range.gd) | Splits points by whether an attribute value falls inside a numeric range. |
| **Attribute Noise** | [attribute_noise.gd](../nodes/attribute_noise.gd) | Combines a random value in [noise_min, noise_max] with the target attribute per point (Set / Minimum / Maximum / Add / Multiply). Targets `density` by default (Density Noise). |
| **Attribute Remove Duplicates** | [attribute_remove_duplicates.gd](../nodes/attribute_remove_duplicates.gd) | Keeps the first entry of every distinct value combination of the listed attributes. |
| **Attribute Rename** | [attribute_rename.gd](../nodes/attribute_rename.gd) | Renames one attribute/stream while preserving its type and values. |
| **Attribute Select** | [attribute_select.gd](../nodes/attribute_select.gd) | Selects the entry with the Min, Max or Median value of an attribute (vectors by axis, length or custom axis); outputs the value as an attribute set and the selected point. |
| **Attribute Set To Point** | [attribute_set_to_point.gd](../nodes/attribute_set_to_point.gd) | Converts attribute rows into point data by providing position/rotation/size streams. |
| **Attribute String Op** | [attribute_string_op.gd](../nodes/attribute_string_op.gd) | Per-point string operations: append, prepend, replace, case, contains / starts / ends with, format, length, trim, substring. |
| **Bitwise Op** | [bitwise_op.gd](../nodes/bitwise_op.gd) | And, Or, Xor, Not and shifts on Bool/Int/Int64 attributes, computed in 64 bits. |
| **Break Transform Attribute** | [break_transform_attribute.gd](../nodes/break_transform_attribute.gd) | Splits a Transform attribute into translation, Euler rotation, quaternion and scale attributes. |
| **Compare Op** | [compare_op.gd](../nodes/compare_op.gd) | Compares two attributes or an attribute and a constant (== != > >= < <=) into a Bool attribute; numbers, strings, vectors, transforms. |
| **Copy Attribute** | [copy_attribute.gd](../nodes/copy_attribute.gd) | Copies one or all attributes from a Source input onto a Target input by index, match attribute or nearest point, keeping types. |
| **Data Table Row To Attribute Set** | [data_table_row_to_attribute_set.gd](../nodes/data_table_row_to_attribute_set.gd) | Extracts one or more table rows into an attribute-set stream. |
| **Delete Tags** | [delete_tags.gd](../nodes/delete_tags.gd) | Removes one or more tags from FlowData. |
| **Get Attribute From Point Index** | [get_attribute_from_point_index.gd](../nodes/get_attribute_from_point_index.gd) | Reads one point's attribute (negative index counts from the end) into a one-row attribute set, the single point, and a per-data attribute on the input. |
| **Get Property From Object Path** | [get_property_from_object_path.gd](../nodes/get_property_from_object_path.gd) | Reads properties of named scene nodes or resources (Scan Nodes property syntax) into an attribute set, one row per object. |
| **Load Data Table** | [load_data_table.gd](../nodes/load_data_table.gd) | Loads CSV/TSV-style rows as attribute-set data with typed columns. |
| **Load PCG Data Asset** | [load_pcg_data_asset.gd](../nodes/load_pcg_data_asset.gd) | Loads JSON or Resource-backed PCG point/attribute data into FlowData streams. JSON numbers always parse as floats, so numeric JSON columns become Float streams. `asset_path` can be wired/bound like other settings. Parsed JSON is cached (shared by all nodes) per path + file modification time + parse settings, so re-evaluating an unchanged file skips the parse and an edited file is re-read; `clear_cache()` drops the cache. |
| **Make Transform Attribute** | [make_transform_attribute.gd](../nodes/make_transform_attribute.gd) | Builds a Transform attribute from translation, rotation and scale attributes or constants. |
| **Merge Attributes** | [merge_attributes.gd](../nodes/merge_attributes.gd) | Merges every data on its input into one attribute set, appending entries (with numeric type promotion) or joining columns by index. |
| **Mutate Seed** | [mutate_seed.gd](../nodes/mutate_seed.gd) | Generates deterministic per-point seed values from existing seeds, index, and optional position. |
| **Point Filter Range** | [point_filter_range.gd](../nodes/point_filter_range.gd) | Point-focused alias of Attribute Filter Range (defaults to position.X). |
| **Point To Attribute Set** | [point_to_attribute_set.gd](../nodes/point_to_attribute_set.gd) | Converts point data to attribute-set style data, optionally removing point transform streams. |
| **Remove Attributes** | [remove_attribute.gd](../nodes/remove_attribute.gd) | Remove streams from the input connection. |
| **Replace Tags** | [replace_tags.gd](../nodes/replace_tags.gd) | Replaces all FlowData tags with the provided set. |
| **Transform Op** | [transform_op.gd](../nodes/transform_op.gd) | Compose, invert, lerp and apply Transform attributes, transform vectors, or move points by a transform. |
| **Trig Op** | [trig_op.gd](../nodes/trig_op.gd) | Sin, Cos, Tan, their inverses, Atan2 and degree/radian conversion on numeric or vector attributes. |
| **Vector Op** | [vector_op.gd](../nodes/vector_op.gd) | Dot, cross, normalize, length, distance, reflect, project, lerp, rotate, angle and component min/max on Vector2/Vector/Vector4 attributes. |

## 📂 Generators

| Node | Script File | Description |
| --- | --- | --- |
| **Create Points** | [create_points.gd](../nodes/create_points.gd) | Creates an explicit list of points (transform, bounds, density, steepness, seed, extra attributes) in world or owner-local space. |
| **Dungeon Connect Rooms** | [dungeon_connect_rooms.gd](../nodes/dungeon_connect_rooms.gd) | Generates sequential L-shaped corridor floor points between selected rooms. |
| **Dungeon Expand Rooms** | [dungeon_expand_rooms.gd](../nodes/dungeon_expand_rooms.gd) | Expands single room center points into grid floor tiles covering their width and height. |
| **Dungeon Generator** | [dungeon_generator.gd](../nodes/dungeon_generator.gd) | Generates procedural floor, wall, pillar, and torch layout points using a grid room-carving algorithm. |
| **Dungeon Room Candidates** | [dungeon_room_candidates.gd](../nodes/dungeon_room_candidates.gd) | Generates a random set of room candidates snapped to grid, with priority, ID, and bounds. |
| **Dungeon Walls and Doors** | [dungeon_walls_and_doors.gd](../nodes/dungeon_walls_and_doors.gd) | Analyzes the FloorPoints set to output walls, doors, torches, and pillars. |
| **Grammar Expand** | [grammar_expand.gd](../nodes/grammar_expand.gd) | Expands a grammar string against a module table into per-module points fitted onto each input span, ready for Match And Set or Spawn Meshes. |
| **Grid** | [grid.gd](../nodes/grid.gd) | Generates a set of points in a grid spatial distribution, where the separation is step |
| **Grid Boundary** | [grid_boundary.gd](../nodes/grid_boundary.gd) | Extracts exposed edge and corner points from filled grid cells. |
| **Grid Connect Points** | [grid_connect_points.gd](../nodes/grid_connect_points.gd) | Connects ordered points with orthogonal grid-cell paths on the XZ plane. |
| **Grid Fill Bounds** | [grid_fill_bounds.gd](../nodes/grid_fill_bounds.gd) | Creates one point per grid cell inside input bounds, or inside configured bounds when no input is connected. World Anchored places the cells on world multiples of cell_size instead of centring them on each box (partition-invariant). |
| **Noise** | [noise.gd](../nodes/noise.gd) | Outputs an attribute with Noise values |
| **Relax** | [relax.gd](../nodes/relax.gd) | Relax distance between points |
| **Self Pruning** | [self_pruning.gd](../nodes/self_pruning.gd) | Rejects points that overlap previous points, or removes duplicate grid-cell points. |
| **Volume Sampler** | [volume_sampler.gd](../nodes/volume_sampler.gd) | Samples points inside incoming point volumes (Volume Sampler alias), or on a voxel grid of `voxel_size` inside volume data (Get Volume Data, composites, splines). |

## 📂 Math

| Node | Script File | Description |
| --- | --- | --- |
| **Boolean** | [boolean.gd](../nodes/boolean.gd) | Applies boolean logic between streams and writes the result as a bool stream. |
| **Expression** | [expression.gd](../nodes/expression.gd) | Evaluates an expression and stores the result in the output stream |
| **Math** | [math_op.gd](../nodes/math_op.gd) | Applies a math operation between two streams, storing the result in a new stream or overriding another. You can read and write substreams like position.X |
| **Reduce** | [reduce.gd](../nodes/reduce.gd) | Computes the min/max/avg values of the specified stream Limited to streams of type float, vector3 or ints. |
| **Remap** | [remap.gd](../nodes/remap.gd) | Remaps the input values using a curve |

## 📂 Meshes

| Node | Script File | Description |
| --- | --- | --- |
| **Load Alembic File** | [load_alembic_file.gd](../nodes/load_alembic_file.gd) | UE naming alias for loading Alembic/imported scene resources as mesh points. |
| **Point From Mesh** | [point_from_mesh.gd](../nodes/point_from_mesh.gd) | Creates one point per mesh node, using mesh bounds for size and node transform for position/rotation. |
| **Points From Imported Scene** | [points_from_imported_scene.gd](../nodes/points_from_imported_scene.gd) | Loads imported scene/mesh resources and emits one point per mesh instance or mesh asset, placed by each mesh's transform accumulated from the scene root. |
| **Sample Mesh** | [sample_mesh.gd](../nodes/sample_mesh.gd) | Samples points on mesh surfaces: random area-weighted, one per vertex, or one per triangle center. Writes density, seed and normal streams. |
| **Sample Terrain Layers** | [sample_terrain_layers.gd](../nodes/sample_terrain_layers.gd) | Writes one weight stream per paint layer (0..1) at each point: from user-assigned mask textures (world-XZ or UV, the default) or from a terrain adapter (Terrain3D control map, HTerrain splat maps, splat images). |
| **Scan Meshes** | [scan_meshes.gd](../nodes/scan_meshes.gd) | Collects MeshInstance3D nodes from the scene and outputs a `node` stream plus a `mesh` Resource stream. Filter by group and/or a boolean metadata flag. |
| **Texture Sampler** | [texture_sampler.gd](../nodes/texture_sampler.gd) | Samples a texture using UV or position-derived coordinates and writes sampled attributes. |

## 📂 Spatial

| Node | Script File | Description |
| --- | --- | --- |
| **Apply Scale To Bounds** | [apply_scale_to_bounds.gd](../nodes/apply_scale_to_bounds.gd) | Multiplies each point's bounds by its scale and resets the scale to one. |
| **Bounds From Mesh** | [bounds_from_mesh.gd](../nodes/bounds_from_mesh.gd) | Sets point bounds from a mesh's local AABB (settings mesh or per-point Mesh attribute). Runs on the main thread and is not cached. |
| **Difference** | [difference.gd](../nodes/difference.gd) | Set operations between point sets (position/size overlap) or spatial shapes: shape with shape gives a composite that is sampled later; points with a shape are filtered (Binary) or density-attenuated (Minimum / Multiply / Subtract) by the shape's density over each point's bounds box (`overlap_mode = BoundsBox`, the default) or at its centre (`PointCenter`). |
| **Find Convex Hull 2D** | [find_convex_hull_2d.gd](../nodes/find_convex_hull_2d.gd) | Keeps the points on the X/Z convex hull of each input, in counter-clockwise order, with a hull index attribute. |
| **Get Bounds** | [get_bounds.gd](../nodes/get_bounds.gd) | World bounds of a spatial shape or of a point set, as one bounds point or a box volume shape. |
| **Get Execution Bounds** | [get_execution_bounds.gd](../nodes/get_execution_bounds.gd) | Bounds of the current FlowWorld3D cell (the world bounds on the Unbounded level, `fallback_bounds` outside world generation) as a box volume or a bounds point, with cell `@data` attributes. The optional Dependency pin only orders execution: `grid_size → get_execution_bounds` runs per cell. |
| **Get Surface Data** | [get_surface_data.gd](../nodes/get_surface_data.gd) | Surface data from MeshInstance3D nodes, HeightMapShape3D collision shapes, a heightmap image, or a terrain (Terrain3D / HTerrain auto-detected by their methods, or by path) with its paint-layer weights (Get Landscape Data). The plugin adapters were tested against fakes only. |
| **Get Volume Data** | [get_volume_data.gd](../nodes/get_volume_data.gd) | Volume data from collision shapes (also inside Area3D / bodies), CSG roots or mesh bounds. |
| **Intersection** | [intersection.gd](../nodes/intersection.gd) | Returns points in A that overlap points in B (Intersection alias). With spatial data, shape with shape gives an intersection composite and points with a shape keep the points whose bounds box (or centre, `overlap_mode`) overlaps it. |
| **Navigation Region Sampler** | [navigation_region_sampler.gd](../nodes/navigation_region_sampler.gd) | Samples Godot NavigationRegion3D meshes into points. |
| **Physics Overlap Query** | [physics_overlap_query.gd](../nodes/physics_overlap_query.gd) | Runs shape-overlap checks per point against the 3D physics world (Godot-specific query node). |
| **Physics Shape Sweep** | [physics_shape_sweep.gd](../nodes/physics_shape_sweep.gd) | Sweeps a sphere or box from each point through the Godot physics world. |
| **Point Neighborhood** | [point_neighborhood.gd](../nodes/point_neighborhood.gd) | Computes neighborhood-derived values such as average center, average density, and distance to center. |
| **Projection** | [projection.gd](../nodes/projection.gd) | Projects points onto physics colliders along a direction (default) or onto surface data (Surface mode), writing the normal and optionally the rotation and density. |
| **Ray Cast** | [ray_cast.gd](../nodes/ray_cast.gd) | Traces a ray in the current scene from the point position (the attribute can be redefined). |
| **Reset Point Center** | [reset_point_center.gd](../nodes/reset_point_center.gd) | Moves each point's pivot to a normalized location inside its bounds without moving the bounds box. |
| **Rotator Op** | [rotator_op.gd](../nodes/rotator_op.gd) | Combine, Invert, Lerp or RotateAroundAxis on the Euler `rotation` or the `rotation_quat` stream. |
| **Split Points** | [split_points.gd](../nodes/split_points.gd) | Splits every point in two along a bounds axis at a ratio (Before Split / After Split), keeping the transform or recentering each half. |
| **Substract** | [substract.gd](../nodes/substract.gd) | Applies the boolean logic |
| **To Point** | [to_point.gd](../nodes/to_point.gd) | Converts spatial data (spline, surface, volume, composite) to points with its default sampling; point data passes through. |
| **Union** | [union.gd](../nodes/union.gd) | Union alias. Merges all incoming point sets. With spatial data, shape with shape gives a union composite, and points with a shape fold the density (same `overlap_mode` as Difference). |

## 📂 Splines

| Node | Script File | Description |
| --- | --- | --- |
| **Clip Paths** | [clip_paths.gd](../nodes/clip_paths.gd) | UE naming alias for clipping point sets by Path3D polygons. |
| **Clip Points By Polygon** | [clip_points_by_polygon.gd](../nodes/clip_points_by_polygon.gd) | Filters points against one or more Path3D or point-list polygons. |
| **Create Spline** | [create_spline.gd](../nodes/create_spline.gd) | Generates a spline from all the input points. |
| **Create Surface From Polygon** | [create_surface_from_polygon.gd](../nodes/create_surface_from_polygon.gd) | Creates bounds-style surface points from ordered polygon point streams, or (Shape mode) polygon surface shapes. |
| **Create Surface From Spline** | [create_surface_from_spline.gd](../nodes/create_surface_from_spline.gd) | Creates one bounds-style surface point from each Path3D polygon/spline (or spline data), or (Shape mode) a polygon surface shape per spline. |
| **Distance** | [distance.gd](../nodes/distance.gd) | Creates a new attribute where the value is the minimum distance from each point to any of the points in the second set. The value can be normalized to an optional Max Distance |
| **Get Spline Data** | [get_spline_data.gd](../nodes/get_spline_data.gd) | Collects Path3D nodes as spline data (a copied curve and transform per Data, or one merged union). |
| **Polygon Operation** | [polygon_operation.gd](../nodes/polygon_operation.gd) | UE naming alias for polygon clipping/filter operations. |
| **Sample Spline** | [sample_spline.gd](../nodes/sample_spline.gd) | Samples points along Path3D curves or spline data (uniform, random, segment centres), or fills the closed XZ polygon of the curve (grid, random, Poisson). |
| **Scan Splines** | [scan_splines.gd](../nodes/scan_splines.gd) | Collects Path3D nodes from the scene and outputs a `node` stream plus a `curve` Resource stream. Filter by group and/or a boolean metadata flag. |
| **Split Splines** | [split_splines.gd](../nodes/split_splines.gd) | Converts Path3D splines into segment-center points with start/end metadata. |
| **Subdivide Segment** | [subdivide_segment.gd](../nodes/subdivide_segment.gd) | Slices spline or two-point spans into sized sub-segments, one oriented point per sub-segment with length, segment_index, t_start and t_end. |

## 📂 Utility

| Node | Script File | Description |
| --- | --- | --- |
| **Attribute Random** | [attribute_random.gd](../nodes/attribute_random.gd) | Sets an attribute on points to random values or sequential indices. |
| **Bounds Modifier** | [bounds_modifier.gd](../nodes/bounds_modifier.gd) | Sets, adds or multiplies a box into the points' bounds: Per Point Bounds (default) writes `bounds_min`/`bounds_max`, keeping an off-centre box's centre as in UE; Symmetric Size (legacy) writes the extent to `size`. |
| **Branch** | [branch.gd](../nodes/branch.gd) | Selects one of two outputs based on a Boolean attribute or value. |
| **Build Rotation From Up Vector** | [build_rotation_from_up.gd](../nodes/build_rotation_from_up.gd) | Computes rotation from an up vector stream or constant and applies it to the points. |
| **Combine Points** | [combine_points.gd](../nodes/combine_points.gd) | For each input Point Data, outputs a new Point Data containing a single point that encompasses all points in its respective Point Data. |
| **Compose Vector** | [compose_vector.gd](../nodes/compose_vector.gd) | Composes a Vector3 attribute from float attributes or default values. `output_type` also builds Vector2 or Vector4 attributes (with a W component). |
| **Compute Kernel** | [compute_kernel.gd](../nodes/compute_kernel.gd) | Runs a user-supplied GLSL compute shader over point streams through RenderingDevice, with declared stream bindings; the input passes through unchanged when the GPU or shader is unavailable. |
| **Copy** | [copy.gd](../nodes/copy.gd) | Copies points using linear repeat offsets or source-to-target placement mode. In SourceToTargets mode `attribute_inheritance` (UE Copy Points parity) picks which input's attributes the copies carry: `SourceOnly` (default; the historical output), `SourceFirst` (source attributes plus target attributes the source lacks), `TargetFirst` (target wins name collisions) or `TargetOnly`. Transform/extent streams (position, rotation, rotation_quat, size, bounds_min/max) are always composed from source and target and are not inherited. |
| **Copy Points** | [copy_points.gd](../nodes/copy_points.gd) | Godot-facing alias of Copy for point data. |
| **Cull Points Outside Bounds** | [cull_points_outside_bounds.gd](../nodes/cull_points_outside_bounds.gd) | Keeps the points inside the current FlowWorld3D cell (half-open on X and Z, optional point-bounds overlap and margin); pass-through outside world generation (Cull Points Outside Actor Bounds). |
| **Curve Remap Density** | [curve_remap_density.gd](../nodes/curve_remap_density.gd) | Remaps the density of each point in the point data to another density value according to the provided curve. |
| **Debug** | [debug.gd](../nodes/debug.gd) | Forces the visualization of the debug node. Used when some specific values are required in the debug options. |
| **Decompose Vector** | [decompose_vector.gd](../nodes/decompose_vector.gd) | Decomposes a Vector3 attribute into three float attributes. Vector2, Vector4, Quaternion and Color inputs also work (the fourth component goes to `w_attribute`). |
| **Density Filter** | [density_filter.gd](../nodes/density_filter.gd) | Keeps points whose density is inside [lower_bound, upper_bound] on In Filter and the rest on Outside Filter. A missing density counts as 1.0. |
| **Density Remap** | [density_remap.gd](../nodes/density_remap.gd) | Applies a linear transform to the point densities. |
| **Discard Points On Irregular Surface** | [discard_points_on_irregular_surface.gd](../nodes/discard_points_on_irregular_surface.gd) | Splits points into Kept and Discarded by the height irregularity and normal spread of the input points inside their bounds footprint. |
| **Distance to Density** | [distance_to_density.gd](../nodes/distance_to_density.gd) | Sets the point density according to the distance of each point from a reference point. |
| **Duplicate Point** | [duplicate_point.gd](../nodes/duplicate_point.gd) | For each point, duplicate the point and move it along an axis defined by the Direction/Offset, and apply a transform on the new point. |
| **Filter** | [filter.gd](../nodes/filter.gd) | Filter inputs based on some condition. This node returns splits the input stream in two substreams. |
| **Filter Data By Attribute** | [filter_data_by_attribute.gd](../nodes/filter_data_by_attribute.gd) | Separates data based on whether they have a specified metadata attribute. |
| **Filter Data By Index** | [filter_data_by_index.gd](../nodes/filter_data_by_index.gd) | Routes whole data entries, or the points of each entry, by index lists and ranges (In Filter / Outside Filter). |
| **Filter Data By Tag** | [filter_data_by_tag.gd](../nodes/filter_data_by_tag.gd) | Separates data according to their tags. You can specify a comma-separated list of Tags to filter by. |
| **Filter Data By Type** | [filter_data_by_type.gd](../nodes/filter_data_by_type.gd) | Separates data by type: point data, spline, surface, volume, any spatial data, or attribute set. Data carrying a spatial shape is classified by that shape. |
| **Gather** | [gather.gd](../nodes/gather.gd) | Forwards every data wired into In unchanged and in order on one pin (no concatenation); the Dependency Only pin only orders execution. |
| **Get Data Count** | [get_data_count.gd](../nodes/get_data_count.gd) | Returns the number of entries in the input data. |
| **Get Entries Count** | [get_entries_count.gd](../nodes/get_entries_count.gd) | Returns the number of entries in the input data. |
| **Get Loop Index** | [get_loop_index.gd](../nodes/get_loop_index.gd) | Source Points (default): a sequential index per incoming point. Source Loop Iteration: the enclosing Loop's iteration index, in every iteration mode. |
| **Get Loop Key** | [get_loop_key.gd](../nodes/get_loop_key.gd) | Writes the enclosing Loop iteration's key (point, entry or chunk index, the entry's key attribute, or the partition value) to every incoming point, or as a one-value Data. |
| **Get Points Count** | [get_points_count.gd](../nodes/get_points_count.gd) | UE naming alias of Size. Outputs total points as a single integer stream. |
| **Get Variable** | [get_variable.gd](../nodes/get_variable.gd) | Reads data from a named graph variable declared by a Set Variable node. |
| **Grid Size** | [grid_size.gd](../nodes/grid_size.gd) | Hierarchical generation marker: the nodes downstream run once per cell of this power-of-two size when a FlowWorld3D generates the graph (the smallest size wins under several markers). Data passes through unchanged; outside FlowWorld3D it has no effect. |
| **Input** | [input.gd](../nodes/input.gd) | Exposes an input of the Flow Graph Node into the Graph |
| **Loop** | [loop.gd](../nodes/loop.gd) | Runs a graph once per iteration of Stream: per point (default), per data entry, per attribute partition or per chunk of points; merged or one output entry per iteration, with an optional feedback parameter and a graph chosen per iteration (`graph_attribute`). |
| **Make Bounds** | [make_bounds.gd](../nodes/make_bounds.gd) | Generates a single bounding point at center with size, or (Shape mode) a box volume shape. |
| **Make Vector** | [make_vector.gd](../nodes/make_vector.gd) | Creates a single Vector value from 3 inmediate float values |
| **Match And Set** | [match_and_set.gd](../nodes/match_and_set.gd) | Copies attributes into input data set based on a match_attr. **Numeric keys:** values are matched by their string form first; when a value has no exact match and both it and a key are numeric (int/float, or a string that parses as one), they are compared as floats with `is_equal_approx`, so a JSON-loaded `3.0` matches key `"3"` and an int `3` matches `"3.0"`. |
| **Merge** | [merge.gd](../nodes/merge.gd) | Merges and combines all streams of all input connections in a single output If input A provides streams s1 and s2, and input B streams s1 and s3 the output will have streams s1,s2 and s3 and the default values will be used where the input does not define a value. |
| **Merge Points** | [merge_points.gd](../nodes/merge_points.gd) | Godot-facing alias of Merge for point data. |
| **Mesh Sampler** | [mesh_sampler.gd](../nodes/mesh_sampler.gd) | Samples points on a mesh surface. Alias of Sample Mesh. |
| **Normal To Density** | [normal_to_density.gd](../nodes/normal_to_density.gd) | density = clamp(dot(normal, normal_to_compare) + offset, 0, 1) ^ strength, combined with the existing density. Uses the `normal` stream, else the rotation's up vector. |
| **Output** | [output.gd](../nodes/output.gd) | Exposes an output parameter of the Subgraph |
| **Partition** | [partition.gd](../nodes/partition.gd) | Partition data based on the different values an attribute. |
| **Point From Player** | [point_from_player_pawn.gd](../nodes/point_from_player_pawn.gd) | Emits one point from a Godot player/source Node3D. Resolves by explicit path, group, class/name, then optional camera fallback. |
| **Point Offsets** | [point_offsets.gd](../nodes/point_offsets.gd) | Creates child points around each input point using local or world offsets. Useful for sockets, tabletop dressing, seating layouts, and repeated prop clusters. Writes `parent_index`, `offset_index` and `offset_label` columns by default; clear an attribute name to skip that column. |
| **Points From GridMap** | [points_from_gridmap.gd](../nodes/points_from_gridmap.gd) | Generates one point per used GridMap cell (Godot-specific 3D tile extraction). |
| **Points From Scene** | [points_from_scene.gd](../nodes/points_from_scene.gd) | Generates one point per scene node and optionally imports metadata and selected properties. |
| **Points From TileMap** | [points_from_tilemap.gd](../nodes/points_from_tilemap.gd) | Generates one point per used TileMapLayer cell (Godot-specific world extraction). |
| **Print String** | [print_string.gd](../nodes/print_string.gd) | Prints a message that outputs a prefixed message optionally to the log. |
| **Random Color** | [random_color.gd](../nodes/random_color.gd) | Generates random colors for each point. |
| **Reroute** | [reroute.gd](../nodes/reroute.gd) | Reroute dot (double-click a wire): passes data through unchanged. |
| **Runtime Quality Branch** | [runtime_quality_branch.gd](../nodes/runtime_quality_branch.gd) | Routes the input to the pin of the current quality level (runtime parameter `quality`, else the `flow_nodes/quality_level` project setting) or to Default. |
| **Runtime Quality Select** | [runtime_quality_select.gd](../nodes/runtime_quality_select.gd) | Forwards the input of the current quality level, or the Default input. |
| **Sample Points** | [sample_points.gd](../nodes/sample_points.gd) | Subdivides each input point into a subgrid of regular points with the specified sampling distance. Enable `inherit_attributes` (default off) to copy every other attribute of each input point onto the samples generated from it (broadcast streams stay broadcast; generated streams such as position, rotation, size, bounds, density and seed are never overridden). |
| **Sanity Check Point Data** | [sanity_check.gd](../nodes/sanity_check.gd) | Validates that the input data point(s) have a value in the given range. |
| **Scan Nodes** | [scan_nodes.gd](../nodes/scan_nodes.gd) | Generate points from existing non-flowgraph nodes in the scene Can filter by class name, group. Metadata values can optionally be imported You can also import properties of the nodes, even with a subpath property like mesh:text if the nodes are a MeshInstance3D with meshes of type TextMesh. |
| **Select** | [select.gd](../nodes/select.gd) | Selects one of two inputs to be forwarded to a single output based on a Boolean attribute or value. |
| **Select (Multi)** | [select_multi.gd](../nodes/select_multi.gd) | Selects one of multiple inputs to be forwarded to a single output based on an index attribute or value. |
| **Select Points** | [select_points.gd](../nodes/select_points.gd) | Filter inputs by the ratio. So when ratio = 0.2, only 20% of the input points will appear in the output (picked randomly). |
| **Sequence Sample** | [sequence_sample.gd](../nodes/sequence_sample.gd) | Samples |
| **Set Variable** | [set_variable.gd](../nodes/set_variable.gd) | Stores the input data in a named graph variable and passes it through unchanged. |
| **Size** | [size.gd](../nodes/size.gd) | Returns the current size of the input sequence |
| **Snap to Grid** | [snap_to_grid.gd](../nodes/snap_to_grid.gd) | Snaps point positions, rotations, or scale sizes to grid values. |
| **Sort** | [sort.gd](../nodes/sort.gd) | Reorders the points based on the values of stream |
| **Spawn Nodes** | [spawn_nodes.gd](../nodes/spawn_nodes.gd) | Dynamically instantiates a raw Godot class or custom script node on each point. Properties can be transferred from point attributes to node properties. `property_overrides` maps point attributes to (nested) property paths of the node. Optional `spawn_parent_attribute` and instance pooling (`reuse_instances`). |
| **Subgraph** | [subgraph.gd](../nodes/subgraph.gd) | Evaluates a nested graph inside this node; with `graph_attribute`, the graph named by an attribute of its extra Graph pin, per input entry. |
| **Surface Sampler** | [surface_sampler.gd](../nodes/surface_sampler.gd) | Samples points randomly inside the bounds of the input points, or on surface data (Get Surface Data, composites) with points per square meter, looseness, point extents, density and an optional Bounding Shape input; on terrain surfaces it writes one `layer_<name>` weight per paint layer. |
| **Switch** | [switch.gd](../nodes/switch.gd) | Routes the input to one of multiple outputs based on an index attribute or value. |
| **Tags** | [tags_mutate.gd](../nodes/tags_mutate.gd) | Adds, removes, or replaces FlowData tags. |
| **Transform** | [transform.gd](../nodes/transform.gd) | Applies the random translation/rotation/scale to each point |
| **Transform Points** | [transform_points.gd](../nodes/transform_points.gd) | Godot-facing alias of Transform for point data. |
| **Weighted Point Sampler** | [weighted_point_sampler.gd](../nodes/weighted_point_sampler.gd) | Picks N points proportionally to a weight attribute, with or without replacement, per-point seeded. |

