# Flow Nodes Editor — developer notes

## Project node directories

Stock nodes live in `nodes/`. Project nodes should live outside the addon so the
addon folder can be replaced on upgrade. `FlowNodeRegistry` resolves a template
`foo` to the first `<dir>/foo.gd` found in:

1. `res://addons/flow_nodes_editor/nodes` (stock; cannot be shadowed),
2. the project setting `flow_nodes/node_directories` (a `PackedStringArray` of
   `res://` directories, shown under **Project Settings → Flow Nodes**; the plugin
   registers it with its empty default when enabled, so `project.godot` only changes
   once you add a directory),
3. directories added at runtime with `FlowNodeRegistry.register_node_directory()`.

The setting is re-read whenever it changes, so the add-node menu refreshes after an
edit in Project Settings, and exported games need no startup code. Node category,
colour and search terms come only from the node's `meta_node` (`"category"`,
`"aliases"`); there are no per-project tables in the addon.

## Graph format versions and migrations

`FlowGraphResource.data` carries `"version"` (`FlowGraphMigrations.CURRENT_VERSION`,
currently `2`; data without the key counts as `1`). `FlowGraphMigrations.migrate(data)`
upgrades older data and is called in exactly these places:

| Where | What happens to the resource |
|---|---|
| `FlowNodeIO.loadFromResource` / `loadFromResourceWithProgress` (editor load) | `resource.data` is replaced by the upgraded copy and the graph is marked dirty, so the next save writes the current version |
| `FlowNodeIO._build_evaluation_state` (runtime) | nothing — the upgraded copy is used for this evaluation only |
| `FlowNodeIO.create_nodes_from_dict` (clipboard paste) | pasted JSON is upgraded before nodes are created |

`migrate()` returns the same dictionary when there is nothing to do, so current
graphs pay no copy. It also replaces templates listed in
`FlowNodeRegistry.template_aliases` (old name → new name) when the old script no
longer exists.

### How to add a migration

Do this whenever you rename or remove a settings property of a stock node, or change
what a stored value means.

1. Bump `CURRENT_VERSION` in `flow_graph_migrations.gd` (for example `2` → `3`).
2. Add an entry for the new version to `MIGRATIONS`, keyed by the node template's
   **current** name:

   ```gdscript
   static var MIGRATIONS : Dictionary = {
       2: {},
       3: {
           # rename a settings key; the value is kept
           "distance": { "in_nameA": "source_attribute" },
           # transform a value: called when the old key is present; mutate the
           # dictionary in place or return a replacement
           "grid": { "count": _split_grid_count },
           # "*" as the template applies to every node, "*" as the key always runs
           "*": { "legacy_debug": "debug_enabled" },
       },
   }

   static func _split_grid_count(settings: Dictionary) -> Dictionary:
       settings["x"] = settings["count"]
       settings["z"] = settings["count"]
       settings.erase("count")
       return settings
   ```

   A rename never overwrites a value already stored under the new key. Migrations
   run in version order, so a graph saved at version 1 receives every step.
3. If a template was renamed, keep the old graphs loading by adding
   `"old_template": "new_template"` to `FlowNodeRegistry.STOCK_TEMPLATE_ALIASES`
   (projects add their own to `FlowNodeRegistry.template_aliases`).
4. Add a test in `demo/tests/flow_nodes_editor/FlowGraphMigrationsTest.gd`: a
   dictionary at the previous version migrates and evaluates, and one at the new
   version is returned untouched.
5. List the change in `docs/DEPRECATIONS.md`.

Never edit `.tres` graphs by hand to "migrate" them; open and save them in the editor
(or run `FlowGraphMigrations.migrate` over `resource.data` in a tool script and save
with `ResourceSaver`).

## TODO

- [ ] Demos
	- [X] Wall of rocks, picking a random point on the top
	- [X] Path with random subscene, filter by attribute with rotations
	- [X] Sample surface of a mesh, create flowers or similar in the horizontal ground
	- [X] Mark an area with a spline, have a path remove all flowers
		- [X] Change density based on the distance to the spline contour
	- [X] Bridge
- [X] Match & Set is not taking into account the weight attr
- [ ] Integrate with HTerrain plugin
- [ ] Subgraphs / Loops?
- [X] Sample spline along N random positions
- [X] Discard points too close to hard edges of a mesh
- [X] Add noise to position <-- Improve noise
- [X] Spline sampling interior in non grid pattern
- [X] Allow to filter rows in the inspector
- [X] Support for virtual streams like front, up, right from rotation.
- [X] Support for Vector4/Color/PackedVector4Array -> Read SubAttributes / MathNode / SetAttribute / Use in Debug if exists
- [X] undo/redo
- [X] Test random colors for each node -> Graph Editor Settings
- [X] add_attribute, if output is single stream with a type, set the color. Maybe make it generic
- [X] Allow the popup menu to have sections. Custom SubGraphs/Resources/Folders maybe
- [X] Transform. Allow rotation to be in local space
- [X] The inspected flag is saved, but it's now never restored
- [X] Support for multiple data in stream evaluation?
	- [X] Debug
	- [X] Generic Loop
	- [X] Node to group <-- Merge
	- [X] Node to split by condition/field <-- Partition
- [X] Allow meta to define input requirements. Single vs Multiple/Accepted Types/Required
- [X] Hightlight the node being evaluated rather than the connections
- [X] Do not update what it's not dirty
- [X] Introduce the mesh/spline data type
	- [X] Nodes of type Curve/Mesh
	- [X] Node to gather
	- [X] Node to create
	- [X] Node to sample (the current one)
- [X] Allow to bypass a node
- [X] There is bug where transforms seems to be updating the input
- [X] Math Node. Should hide inputs when not needed. Like Abs
- [X] Volume Sample in 3D
- [X] Remap node
- [X] Add expressions node
- [X] weighted sampling
- [X] support for @last?
- [X] Get N property as a independent value. Get first, get last, etc.
- [X] Sampling mesh
- [X] Allow the grid to have an offset/rotation or it's useless
- [X] scan nodes, filter by class_name
- [X] scan nodes, option to resize to node limits
- [X] Support for copy/paste/clone
- [X] Resource properties are correctly imported as Resources in the scan node
- [X] Promote input pin to graph input
- [X] Custom inputs values in the pcg node 3d, not in the resource
- [X] Generate reduction of metrics. Avg, Min, Max, etc of a numeric stream
- [X] Copy with offset N times. Export attribute
- [X] Show performance numbers somewhere
- [X] Merge node
- [X] if condition is null/emtpy
- [X] drop some streams
- [X] Ctrl+C will not add a comment. Only if pressing C alone
- [X] E will toggle the data inspector but also make data_visualization visible in the editor
- [X] Distance to curve
- [X] Sort a stream by some condition
	- [X] Floats
	- [X] Ints
	- [X] Strings
	- [X] How does it behave with multiple streams
- [X] add_attribute, input is optional
- [X] Math Node. Should be easier to add a constant +float/+int/-vector at least. Use make_vector for vector
- [X] Improve self prunning so more objects are kept
- [X] No need to regenerate the menu every time
- [X] Hightlight the selector row from the inspector in the 3D
- [X] Make vector from float's, maybe autopromote float -> vector3 
- [X] Allow the inspector to show all outputs/inputs
- [X] nodes to filter A/B
- [X] Math Node. Accept a stream feeding a single size element -> Promote it
- [X] Confirm if we are using PackedStringArray for streams of type Strings
- [X] Confirm I can set values of the generated instances
- [X] spatial operations
	- [X] A minus B
	- [X] A intersection B
- [X] Remove self intersections
- [X] When changing scene, the registered nodes should be removed
- [X] Confirm I can use Index as part of the streams
- [X] Spline region - Spline path
- [X] Node to scan nodes 
- [X] Read meta into the attributes
- [X] Read properties from list
- [X] store sizes
- [X] display density/color in debug
- [X] input nodes are not restored correctly
- [X] support for bools
- [X] Move isFinal to getMeta
- [X] Spawn PackedScene
- [X] store rotations
- [x] read-write sub-streams
	- [x] vector3 -> .x, .y, .z
	- [x] basis   -> yaw, pitch, roll
- [x] Choose mesh to spawn
- [x] Stream to ref mesh instance
- [x] Multic Constant as Arg vs Attribute input
	- [x] Conditional UI
- [X] Aggregate MultiInstanceMesh per mesh in spawn meshes
- [x] dispay substreams
- [x] node transform with ranges in local space
- [x] save graph into scene node 
- [x] dependencies/dirty chains
- [X] node add density
- [X] update data_view on each refresh
- [X] node operate
- [X] create custom stream
- [x] spline sampling
- [x] support for prev
- [X] Dynamic title
- [X] update while changing the scene
- [X] Block auto-update
