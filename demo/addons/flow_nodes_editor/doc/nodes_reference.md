# PCGODOT Node Library Reference

A complete reference of all available nodes in the PCGODOT framework, grouped by category. Clicking on a node name links directly to its implementation file.

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
| **Apply On Actor** | [apply_on_actor.gd](../nodes/apply_on_actor.gd) | Applies point attributes and optional transforms onto existing scene nodes. |
| **Assets** | [assets.gd](../nodes/assets.gd) | Generates a list of assets. Useful in combination with the Match And Set node, this node generates a list of meshes with some attribute/tag and weight assigned. |
| **Spawn Meshes** | [spawn_meshes.gd](../nodes/spawn_meshes.gd) | Spawns a Mesh Instance on each point, applying the translation, rotation and scale. The instanced mesh can be specified by point if a stream contains the mesh resource to be spawned. The generates meshes are MultiMeshInstance3D. |
| **Spawn Scenes** | [spawn_scenes.gd](../nodes/spawn_scenes.gd) | Similar to spawn meshes but a full scene is instantiated on each node. A set of properties can be transfered from the nodes to each instanced scene. |

## 📂 Attributes

| Node | Script File | Description |
| --- | --- | --- |
| **Add Attribute** | [add_attribute.gd](../nodes/add_attribute.gd) | Add a new constant stream to the input set If the input is not given a single entry with the constant value is created (intentional schema-row idiom: chained Add Attribute nodes build a one-row attribute set). |
| **Add Tags** | [add_tags.gd](../nodes/add_tags.gd) | Adds one or more tags to FlowData. |
| **Attribute Filter Range** | [attribute_filter_range.gd](../nodes/attribute_filter_range.gd) | Splits points by whether an attribute value falls inside a numeric range. |
| **Attribute Rename** | [attribute_rename.gd](../nodes/attribute_rename.gd) | Renames one attribute/stream while preserving its type and values. |
| **Attribute Set To Point** | [attribute_set_to_point.gd](../nodes/attribute_set_to_point.gd) | Converts attribute rows into point data by providing position/rotation/size streams. |
| **Data Table Row To Attribute Set** | [data_table_row_to_attribute_set.gd](../nodes/data_table_row_to_attribute_set.gd) | Extracts one or more table rows into an attribute-set stream. |
| **Delete Tags** | [delete_tags.gd](../nodes/delete_tags.gd) | Removes one or more tags from FlowData. |
| **Load Data Table** | [load_data_table.gd](../nodes/load_data_table.gd) | Loads CSV/TSV-style rows as attribute-set data with typed columns. |
| **Load PCG Data Asset** | [load_pcg_data_asset.gd](../nodes/load_pcg_data_asset.gd) | Loads JSON or Resource-backed PCG point/attribute data into FlowData streams. JSON numbers always parse as floats, so numeric JSON columns become Float streams. `asset_path` can be wired/bound like other settings. Parsed JSON is cached (shared by all nodes) per path + file modification time + parse settings, so re-evaluating an unchanged file skips the parse and an edited file is re-read; `clear_cache()` drops the cache. |
| **Mutate Seed** | [mutate_seed.gd](../nodes/mutate_seed.gd) | Generates deterministic per-point seed values from existing seeds, index, and optional position. |
| **Point Filter Range** | [point_filter_range.gd](../nodes/point_filter_range.gd) | Point-focused alias of Attribute Filter Range (defaults to position.X). |
| **Point To Attribute Set** | [point_to_attribute_set.gd](../nodes/point_to_attribute_set.gd) | Converts point data to attribute-set style data, optionally removing point transform streams. |
| **Remove Attributes** | [remove_attribute.gd](../nodes/remove_attribute.gd) | Remove streams from the input connection. |
| **Replace Tags** | [replace_tags.gd](../nodes/replace_tags.gd) | Replaces all FlowData tags with the provided set. |

## 📂 Generators

| Node | Script File | Description |
| --- | --- | --- |
| **Dungeon Connect Rooms** | [dungeon_connect_rooms.gd](../nodes/dungeon_connect_rooms.gd) | Generates sequential L-shaped corridor floor points between selected rooms. |
| **Dungeon Expand Rooms** | [dungeon_expand_rooms.gd](../nodes/dungeon_expand_rooms.gd) | Expands single room center points into grid floor tiles covering their width and height. |
| **Dungeon Generator** | [dungeon_generator.gd](../nodes/dungeon_generator.gd) | Generates procedural floor, wall, pillar, and torch layout points using a grid room-carving algorithm. |
| **Dungeon Room Candidates** | [dungeon_room_candidates.gd](../nodes/dungeon_room_candidates.gd) | Generates a random set of room candidates snapped to grid, with priority, ID, and bounds. |
| **Dungeon Walls and Doors** | [dungeon_walls_and_doors.gd](../nodes/dungeon_walls_and_doors.gd) | Analyzes the FloorPoints set to output walls, doors, torches, and pillars. |
| **Grid** | [grid.gd](../nodes/grid.gd) | Generates a set of points in a grid spatial distribution, where the separation is step |
| **Grid Boundary** | [grid_boundary.gd](../nodes/grid_boundary.gd) | Extracts exposed edge and corner points from filled grid cells. |
| **Grid Connect Points** | [grid_connect_points.gd](../nodes/grid_connect_points.gd) | Connects ordered points with orthogonal grid-cell paths on the XZ plane. |
| **Grid Fill Bounds** | [grid_fill_bounds.gd](../nodes/grid_fill_bounds.gd) | Creates one point per grid cell inside input bounds, or inside configured bounds when no input is connected. |
| **Noise** | [noise.gd](../nodes/noise.gd) | Outputs an attribute with Noise values |
| **Relax** | [relax.gd](../nodes/relax.gd) | Relax distance between points |
| **Self Pruning** | [self_pruning.gd](../nodes/self_pruning.gd) | Rejects points that overlap previous points, or removes duplicate grid-cell points. |
| **Volume Sampler** | [volume_sampler.gd](../nodes/volume_sampler.gd) | Samples points inside incoming point volumes (Volume Sampler alias). |

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
| **Points From Imported Scene** | [points_from_imported_scene.gd](../nodes/points_from_imported_scene.gd) | Loads imported scene/mesh resources and emits one point per mesh instance or mesh asset. |
| **Sample Mesh** | [sample_mesh.gd](../nodes/sample_mesh.gd) | No description available. |
| **Scan Meshes** | [scan_meshes.gd](../nodes/scan_meshes.gd) | No description available. |
| **Texture Sampler** | [texture_sampler.gd](../nodes/texture_sampler.gd) | Samples a texture using UV or position-derived coordinates and writes sampled attributes. |

## 📂 Spatial

| Node | Script File | Description |
| --- | --- | --- |
| **Difference** | [difference.gd](../nodes/difference.gd) | Performs set operations between two point sets based on position/size overlap. |
| **Intersection** | [intersection.gd](../nodes/intersection.gd) | Returns points in A that overlap points in B (Intersection alias). |
| **Navigation Region Sampler** | [navigation_region_sampler.gd](../nodes/navigation_region_sampler.gd) | Samples Godot NavigationRegion3D meshes into points. |
| **Physics Overlap Query** | [physics_overlap_query.gd](../nodes/physics_overlap_query.gd) | Runs shape-overlap checks per point against the 3D physics world (Godot-specific query node). |
| **Physics Shape Sweep** | [physics_shape_sweep.gd](../nodes/physics_shape_sweep.gd) | Sweeps a sphere or box from each point through the Godot physics world. |
| **Point Neighborhood** | [point_neighborhood.gd](../nodes/point_neighborhood.gd) | Computes neighborhood-derived values such as average center, average density, and distance to center. |
| **Ray Cast** | [ray_cast.gd](../nodes/ray_cast.gd) | Traces a ray in the current scene from the point position (the attribute can be redefined). |
| **Substract** | [substract.gd](../nodes/substract.gd) | Applies the boolean logic |
| **Union** | [union.gd](../nodes/union.gd) | Union alias. Merges all incoming point sets. |

## 📂 Splines

| Node | Script File | Description |
| --- | --- | --- |
| **Clip Paths** | [clip_paths.gd](../nodes/clip_paths.gd) | UE naming alias for clipping point sets by Path3D polygons. |
| **Clip Points By Polygon** | [clip_points_by_polygon.gd](../nodes/clip_points_by_polygon.gd) | Filters points against one or more Path3D or point-list polygons. |
| **Create Spline** | [create_spline.gd](../nodes/create_spline.gd) | Generates a spline from all the input points. |
| **Create Surface From Polygon** | [create_surface_from_polygon.gd](../nodes/create_surface_from_polygon.gd) | Creates bounds-style surface points from ordered polygon point streams. |
| **Create Surface From Spline** | [create_surface_from_spline.gd](../nodes/create_surface_from_spline.gd) | Creates one bounds-style surface point from each Path3D polygon/spline. |
| **Distance** | [distance.gd](../nodes/distance.gd) | Creates a new attribute where the value is the minimum distance from each point to any of the points in the second set. The value can be normalized to an optional Max Distance |
| **Polygon Operation** | [polygon_operation.gd](../nodes/polygon_operation.gd) | UE naming alias for polygon clipping/filter operations. |
| **Sample Spline** | [sample_spline.gd](../nodes/sample_spline.gd) | No description available. |
| **Scan Splines** | [scan_splines.gd](../nodes/scan_splines.gd) | No description available. |
| **Split Splines** | [split_splines.gd](../nodes/split_splines.gd) | Converts Path3D splines into segment-center points with start/end metadata. |

## 📂 Utility

| Node | Script File | Description |
| --- | --- | --- |
| **Attribute Random** | [attribute_random.gd](../nodes/attribute_random.gd) | Sets an attribute on points to random values or sequential indices. |
| **Bounds Modifier** | [bounds_modifier.gd](../nodes/bounds_modifier.gd) | Modifies the size/bounds property on points in the provided point data. |
| **Branch** | [branch.gd](../nodes/branch.gd) | Selects one of two outputs based on a Boolean attribute or value. |
| **Build Rotation From Up Vector** | [build_rotation_from_up.gd](../nodes/build_rotation_from_up.gd) | Computes rotation from an up vector stream or constant and applies it to the points. |
| **Combine Points** | [combine_points.gd](../nodes/combine_points.gd) | For each input Point Data, outputs a new Point Data containing a single point that encompasses all points in its respective Point Data. |
| **Compose Vector** | [compose_vector.gd](../nodes/compose_vector.gd) | Composes a Vector3 attribute from float attributes or default values. |
| **Copy** | [copy.gd](../nodes/copy.gd) | Copies points using linear repeat offsets or source-to-target placement mode. In SourceToTargets mode `attribute_inheritance` (UE Copy Points parity) picks which input's attributes the copies carry: `SourceOnly` (default; the historical output), `SourceFirst` (source attributes plus target attributes the source lacks), `TargetFirst` (target wins name collisions) or `TargetOnly`. Transform/extent streams (position, rotation, rotation_quat, size, bounds_min/max) are always composed from source and target and are not inherited. |
| **Copy Points** | [copy_points.gd](../nodes/copy_points.gd) | Godot-facing alias of Copy for point data. |
| **Curve Remap Density** | [curve_remap_density.gd](../nodes/curve_remap_density.gd) | Remaps the density of each point in the point data to another density value according to the provided curve. |
| **Debug** | [debug.gd](../nodes/debug.gd) | Forces the visualization of the debug node. Used when some specific values are required in the debug options. |
| **Decompose Vector** | [decompose_vector.gd](../nodes/decompose_vector.gd) | Decomposes a Vector3 attribute into three float attributes. |
| **Density Remap** | [density_remap.gd](../nodes/density_remap.gd) | Applies a linear transform to the point densities. |
| **Distance to Density** | [distance_to_density.gd](../nodes/distance_to_density.gd) | Sets the point density according to the distance of each point from a reference point. |
| **Duplicate Point** | [duplicate_point.gd](../nodes/duplicate_point.gd) | For each point, duplicate the point and move it along an axis defined by the Direction/Offset, and apply a transform on the new point. |
| **Filter** | [filter.gd](../nodes/filter.gd) | Filter inputs based on some condition. This node returns splits the input stream in two substreams. |
| **Filter Data By Attribute** | [filter_data_by_attribute.gd](../nodes/filter_data_by_attribute.gd) | Separates data based on whether they have a specified metadata attribute. |
| **Filter Data By Tag** | [filter_data_by_tag.gd](../nodes/filter_data_by_tag.gd) | Separates data according to their tags. You can specify a comma-separated list of Tags to filter by. |
| **Filter Data By Type** | [filter_data_by_type.gd](../nodes/filter_data_by_type.gd) | Separates data based on their type, as dictated by the Target Type. |
| **Get Data Count** | [get_data_count.gd](../nodes/get_data_count.gd) | Returns the number of entries in the input data. |
| **Get Entries Count** | [get_entries_count.gd](../nodes/get_entries_count.gd) | Returns the number of entries in the input data. |
| **Get Loop Index** | [get_loop_index.gd](../nodes/get_loop_index.gd) | Writes a sequential loop/index attribute for each incoming point. |
| **Get Points Count** | [get_points_count.gd](../nodes/get_points_count.gd) | UE naming alias of Size. Outputs total points as a single integer stream. |
| **Input** | [input.gd](../nodes/input.gd) | Exposes an input of the Flow Graph Node into the Graph |
| **Loop** | [loop.gd](../nodes/loop.gd) | Loops over each element in Stream and runs a graph for each |
| **Make Bounds** | [make_bounds.gd](../nodes/make_bounds.gd) | Generates a single bounding point at center with size. |
| **Make Vector** | [make_vector.gd](../nodes/make_vector.gd) | Creates a single Vector value from 3 inmediate float values |
| **Match And Set** | [match_and_set.gd](../nodes/match_and_set.gd) | Copies attributes into input data set based on a match_attr. **Numeric keys:** values are matched by their string form first; when a value has no exact match and both it and a key are numeric (int/float, or a string that parses as one), they are compared as floats with `is_equal_approx`, so a JSON-loaded `3.0` matches key `"3"` and an int `3` matches `"3.0"`. |
| **Merge** | [merge.gd](../nodes/merge.gd) | Merges and combines all streams of all input connections in a single output If input A provides streams s1 and s2, and input B streams s1 and s3 the output will have streams s1,s2 and s3 and the default values will be used where the input does not define a value. |
| **Merge Points** | [merge_points.gd](../nodes/merge_points.gd) | Godot-facing alias of Merge for point data. |
| **Mesh Sampler** | [mesh_sampler.gd](../nodes/mesh_sampler.gd) | Samples points on a mesh surface. Alias of Sample Mesh. |
| **Output** | [output.gd](../nodes/output.gd) | Exposes an output parameter of the Subgraph |
| **Partition** | [partition.gd](../nodes/partition.gd) | Partition data based on the different values an attribute. |
| **Point From Player** | [point_from_player_pawn.gd](../nodes/point_from_player_pawn.gd) | Emits one point from a Godot player/source Node3D. Resolves by explicit path, group, class/name, then optional camera fallback. |
| **Point Offsets** | [point_offsets.gd](../nodes/point_offsets.gd) | Creates child points around each input point using local or world offsets. Useful for sockets, tabletop dressing, seating layouts, and repeated prop clusters. Writes `parent_index`, `offset_index` and `offset_label` columns by default; clear an attribute name to skip that column. |
| **Points From GridMap** | [points_from_gridmap.gd](../nodes/points_from_gridmap.gd) | Generates one point per used GridMap cell (Godot-specific 3D tile extraction). |
| **Points From Scene** | [points_from_scene.gd](../nodes/points_from_scene.gd) | Generates one point per scene node and optionally imports metadata and selected properties. |
| **Points From TileMap** | [points_from_tilemap.gd](../nodes/points_from_tilemap.gd) | Generates one point per used TileMapLayer cell (Godot-specific world extraction). |
| **Print String** | [print_string.gd](../nodes/print_string.gd) | Prints a message that outputs a prefixed message optionally to the log. |
| **Random Color** | [random_color.gd](../nodes/random_color.gd) | Generates random colors for each point. |
| **Sample Points** | [sample_points.gd](../nodes/sample_points.gd) | Subdivides each input point into a subgrid of regular points with the specified sampling distance. Enable `inherit_attributes` (default off) to copy every other attribute of each input point onto the samples generated from it (broadcast streams stay broadcast; generated streams such as position, rotation, size, bounds, density and seed are never overridden). |
| **Sanity Check Point Data** | [sanity_check.gd](../nodes/sanity_check.gd) | Validates that the input data point(s) have a value in the given range. |
| **Scan Nodes** | [scan_nodes.gd](../nodes/scan_nodes.gd) | Generate points from existing non-flowgraph nodes in the scene Can filter by class name, group. Metadata values can optionally be imported You can also import properties of the nodes, even with a subpath property like mesh:text if the nodes are a MeshInstance3D with meshes of type TextMesh. |
| **Select** | [select.gd](../nodes/select.gd) | Selects one of two inputs to be forwarded to a single output based on a Boolean attribute or value. |
| **Select (Multi)** | [select_multi.gd](../nodes/select_multi.gd) | Selects one of multiple inputs to be forwarded to a single output based on an index attribute or value. |
| **Select Points** | [select_points.gd](../nodes/select_points.gd) | Filter inputs by the ratio. So when ratio = 0.2, only 20% of the input points will appear in the output (picked randomly). |
| **Sequence Sample** | [sequence_sample.gd](../nodes/sequence_sample.gd) | Samples |
| **Size** | [size.gd](../nodes/size.gd) | Returns the current size of the input sequence |
| **Snap to Grid** | [snap_to_grid.gd](../nodes/snap_to_grid.gd) | Snaps point positions, rotations, or scale sizes to grid values. |
| **Sort** | [sort.gd](../nodes/sort.gd) | Reorders the points based on the values of stream |
| **Spawn Nodes** | [spawn_nodes.gd](../nodes/spawn_nodes.gd) | Dynamically instantiates a raw Godot class or custom script node on each point. Properties can be transferred from point attributes to node properties. |
| **Subgraph** | [subgraph.gd](../nodes/subgraph.gd) | Evaluates a nested graph inside this node |
| **Surface Sampler** | [surface_sampler.gd](../nodes/surface_sampler.gd) | Samples points randomly inside the bounds of the input points. |
| **Switch** | [switch.gd](../nodes/switch.gd) | Routes the input to one of multiple outputs based on an index attribute or value. |
| **Tags** | [tags_mutate.gd](../nodes/tags_mutate.gd) | Adds, removes, or replaces FlowData tags. |
| **Transform** | [transform.gd](../nodes/transform.gd) | Applies the random translation/rotation/scale to each point |
| **Transform Points** | [transform_points.gd](../nodes/transform_points.gd) | Godot-facing alias of Transform for point data. |

