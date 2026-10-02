# Manual editor check

The test suites run headless: the dummy renderer draws nothing, `Engine.is_editor_hint()` is false, and the editor's dock, inspector and undo system are driven through their entry points rather than with a mouse. Everything below the pixels is tested numerically. This list covers what is left: what a person has to look at in the Godot editor. It is assembled from the notes of parity round 2 ([`_round2/WP1.md`](_round2/WP1.md), [`WP3.md`](_round2/WP3.md), [`WP5.md`](_round2/WP5.md), [`WP7.md`](_round2/WP7.md), [`WP8.md`](_round2/WP8.md), [`WP11.md`](_round2/WP11.md)).

It is meant to be done in one pass of about 30 minutes, in order. Tick each box; for anything that does not match the expected observation, note the step number, what you saw, the renderer (Forward+, Mobile or Compatibility) and any line of the Output panel.

Hotkeys used below: **D** toggles the debug draw of the hovered or selected node, **A** opens the Data Inspector on it, **E** disables or enables it, **Alt+D** clears every debug draw.

---

## 0. Setup (2 min)

- [ ] **0.1** Open the `demo/` folder as a project in Godot 4.6 (or 4.7) with the GDExtension binary for your platform in `addons/flow_nodes_editor/bin/`. Check that **Flow Nodes Editor** is enabled under Project Settings → Plugins.
  - Expected: the Output panel shows no `SCRIPT ERROR` or `Parse Error` after the import.
- [ ] **0.2** Project Settings → General, type `flow_nodes` in the filter, without having opened any graph.
  - Expected: `Flow Nodes → Node Directories` and `Flow Nodes → Quality Level` are listed; Quality Level is a drop-down with Low, Medium, High, Epic, Cinematic and value Low. (The plugin registers both at startup; before, Quality Level appeared only once a quality node had been created.)

## 1. Dock: mouse, selection, drawing, undo (4 min)

Open `demos/demo_sample_points.tscn` and select its `FlowGraphNode3D`; the **Data Flow** panel opens at the bottom.

- [ ] **1.1** Click a node, Shift-click a second one, drag a box around three. Drag a node by its title.
  - Expected: selection highlights follow the clicks; the dragged node moves with its wires attached.
- [ ] **1.2** After the graph has evaluated, look at the nodes' title bars.
  - Expected: nodes slower than 0.1 ms show an execution-time badge; nodes over 10 ms show it in a warning colour.
- [ ] **1.3** Double-click a wire.
  - Expected: a reroute dot is inserted on the wire, drawn as a small round port, and the data still flows (the downstream node re-evaluates without an error).
- [ ] **1.4** Click the small connector-options toggle at the bottom of a node that has settings (for example a Transform Points node).
  - Expected: the node grows parameter ports (`Cte ...`, setting names) on its left side; clicking again hides the unconnected ones.
- [ ] **1.5** In the sidebar inspector change one setting of a node, then press **Ctrl+Z**, then **Ctrl+Y**. Move a node and press **Ctrl+Z**.
  - Expected: the setting goes back and forth and the graph re-evaluates each time; the node returns to its previous position.
- [ ] **1.6** Select two connected nodes, right-click → **Collapse Selected to Subgraph**, then double-click the new Subgraph node.
  - Expected: a subgraph node replaces the selection with the same outer wires; double-clicking opens the inner graph in the dock. Select the `FlowGraphNode3D` in the Scene dock again to return. Undo the collapse.
- [ ] **1.7** Open a graph that has an `input` node with several outputs (or add one from the search popup, "Input"), and click its **+ Add Input Parameter** button; do the same on an `output` node (**+ Add Output Parameter**).
  - Expected: a new port appears on the node and a parameter in the graph's parameter list.

## 2. Types, ports and graph parameters (5 min)

In any graph:

- [ ] **2.1 Port colours.** Add an `add_attribute` node and turn on its connector-options toggle so the `Cte ...` parameter port is visible. In the sidebar set `data_type` to Vector2, then Vector4, Quaternion, Transform, Int64, Double.
  - Expected: the parameter port dot changes colour per type — pale purple (Vector2), deep purple (Vector4), pink (Quaternion), orange (Transform); Int64 and Double are grey like Int and Float (GDScript properties carry no 64-bit distinction). The title reads `name - Vector2` and so on.
- [ ] **2.2 Graph parameters.** Click the toolbar's **Edit graph inputs** button; the sidebar shows the graph's parameters. Click **Add Parameter** and open the type drop-down.
  - Expected: thirteen types, each with its own swatch. Picking Vector4, Quaternion or Transform puts the value editor on its own row under the name; Int64 and Double show a number field. Only the value row of the picked type is shown.
- [ ] **2.3** Add an `input` node for that parameter.
  - Expected: its output port takes the type's colour.
- [ ] **2.4** Select the scene's `FlowGraphNode3D`, press **Refresh Inputs** in the Inspector.
  - Expected: the new parameter appears in `args` with its default. Edit the value, press Refresh Inputs again: the edited value survives (also for Int64 and Double).
- [ ] **2.5 Ports follow modes.** Add a `surface_sampler`. Wire a node into **In** and another into one of its parameter ports (connector-options toggle on). Tick `use_bounding_shape`.
  - Expected: a **Bounding Shape** input appears under In, and the parameter wire moves down one row with its parameter.
- [ ] **2.6** Wire something into Bounding Shape, save the scene, close it and reopen it.
  - Expected: all three wires are where they were.
- [ ] **2.7** Untick `use_bounding_shape`, then press **Ctrl+Z**.
  - Expected: on untick, the Bounding Shape wire disappears (it does not jump onto the parameter port) and the parameter wire moves back up. After the undo the input row comes back. Note whether the dropped wire comes back: it is expected **not** to (the drop happens inside the port rebuild and is not an undo action of its own); reconnecting it by hand is the workaround.
- [ ] **2.8** Repeat 2.5 with a `projection` node and `projection_mode = Surface` (input **Projection Target**).
  - Expected: same behaviour as 2.5 to 2.7.

## 3. Data Inspector (4 min)

- [ ] **3.1 All types.** Build `grid` → `add_attribute` (Vector2) → `add_attribute` (Transform) → `add_attribute` (Int64) → `add_attribute` (Double) and press **A** on the last node.
  - Expected: columns `name.X name.Y` for the Vector2; nine columns for the Transform (Pos, Rot in degrees, Scale); an integer column for Int64 and six decimals for Double; text right-aligned except String, Resource and Node columns; header widths fit the titles; no red errors in the Output panel.
- [ ] **3.2** Type a value shown in a Transform column into the filter box.
  - Expected: only the rows whose displayed text contains it remain.
- [ ] **3.3** Click each column title twice.
  - Expected: rows reorder ascending, then descending; empty cells stay at the bottom both ways.
- [ ] **3.4** Click a row.
  - Expected: that point is highlighted in the 3D viewport.
- [ ] **3.5 Shape-only data.** Add a `Path3D` with a curve to the scene, add `get_spline_data` and press **A** on it.
  - Expected: one row `FlowSplineShape | Spline | 0 | (min) | (max) | (size) | N points, length L, tube 1.000`, and the stats line ends with `shape FlowSplineShape (Spline)`.
- [ ] **3.6** Wire `get_surface_data` (A) and `get_volume_data` (B) into a `difference` and press **A** on it. Double-click one of its rows.
  - Expected: three rows (the composite, `A: ...`, `B: ...`). The double-click moves the viewport camera to that part's bounds centre.
- [ ] **3.7 Tooltip.** Hover a `get_volume_data` node after evaluation.
  - Expected: the tooltip reads `Out: 0 pts, 0 streams, shape FlowBoxVolume (Volume)` (or names the composite).

## 4. 3D viewport debug draw (6 min)

- [ ] **4.1 Point cubes.** In `demo_sample_points`, press **D** on a sampler node; change its `debug_color` and `debug_modulate_by`; press **Alt+D**.
  - Expected: instanced cubes at the points, tinted on a grey ramp by density (or the chosen attribute) or in the debug colour; Alt+D clears every node's debug draw.
- [ ] **4.2 Splines.** Press **D** on `get_spline_data` (step 3.5). Move the `Path3D` and let the graph re-run.
  - Expected: a line in the debug colour following the curve exactly, including its curvature and the node's transform; a closed curve is closed; the line follows the move.
- [ ] **4.3 Volumes.** Give the scene a `CollisionShape3D` with a rotated `BoxShape3D` and one with a `SphereShape3D`; press **D** on `get_volume_data`.
  - Expected: a rotated wire box, and three great circles of the sphere's radius.
- [ ] **4.4 Surfaces.** Press **D** on `get_surface_data` with a HeightmapImage source (or a `HeightMapShape3D` terrain), then with a `MeshInstance3D` source. Also press **D** on a `create_surface_from_spline` in Shape mode.
  - Expected: a 25 × 25 line grid draped on the heightfield, its outer lines along the border; for the mesh, a dim bounds box and a draped grid that stops where the mesh ends; for the polygon surface, its outline.
- [ ] **4.5 Composites.** Press **D** on a `difference` of two shapes; switch its `operation` to Intersection and Union.
  - Expected: operand A in the debug colour, operand B reddish, a dashed box around the composite bounds with a short "-" on top; Intersection shows yellow tints and an "x", Union green and a "+".
- [ ] **4.6 Point bounds.** Press **D** on a `surface_sampler` that samples surface data (or on a `bounds_modifier`). Click a row in the Data Inspector. Set `debug_mode` to ABSOLUTE, then back to EXTENDS.
  - Expected: a wire box per point around its cube, rotated with the point and tinted like the cubes; the selected point's box turns magenta; in ABSOLUTE mode the wire boxes disappear and the cubes keep the fixed size.
- [ ] **4.7 Limits.** Press **D** on a 1025 × 1025 heightfield (`get_surface_data`, HeightmapImage with a large image) or a very large point set, with the node's `trace` setting on.
  - Expected: the editor stays responsive; the grid stays at 25 lines per axis and at most 4096 point boxes are drawn; the console prints `Debug.Lines truncated: ...`.
- [ ] **4.8 Cleanup.** With debug lines showing, press **E** on the node, then delete another node that shows lines.
  - Expected: the lines vanish each time; nothing is left behind in the viewport.
- [ ] **4.9 Renderers.** If time allows, repeat 4.2 and 4.5 after switching the renderer (Project Settings → Rendering → Renderer) to Mobile and to Compatibility.
  - Expected: the lines render in every renderer (unshaded vertex colours).

## 5. Loops and subgraphs (3 min)

- [ ] **5.1** Add a `loop` node with a body graph. In the sidebar switch `iteration_mode` through Points, Entries, Partitions, Chunks.
  - Expected: `partition_attribute` is shown only in Partitions mode, `chunk_size` only in Chunks mode, `key_attribute` only in Entries mode; the title gains a suffix such as `Loop (body) [Partitions]`; `output_mode = Collection` adds `Collection` to it.
- [ ] **5.2** Wire point data with attributes into the loop's Stream pin and open the `partition_attribute` (and `graph_attribute`) field.
  - Expected: a drop-down offers the attribute names of the incoming data.
- [ ] **5.3** Set `graph_attribute` on a `subgraph` node.
  - Expected: a **Graph** input pin is appended after its other inputs and the title reads `Subgraph (g) [@attr]`; clearing the field removes the pin.
- [ ] **5.4** Double-click a `loop` and a `subgraph` whose `graph_attribute` is set and whose `graph` is assigned.
  - Expected: the default `graph` opens in the dock.

## 6. Spawners (3 min)

- [ ] **6.1 Per-instance colours.** Open `demos/demo_fallguys.tscn`.
  - Expected: the hexagon platforms show different random colours (per-instance MultiMesh colours, which the headless renderer cannot read back).
- [ ] **6.2 Instance pooling.** In `demos/demo_sample_points.tscn` (or any demo with `spawn_meshes`), tick `reuse_instances` on the spawner. Select its generated `MultiMeshInstance3D` in the Scene dock, then change an upstream setting so the graph re-runs with the same mesh (for example a Transform Points scale). Repeat with `reuse_instances` off.
  - Expected: with pooling on, the same node stays selected in the Scene dock and Inspector after the re-run (it was reused); with pooling off, the selection is lost because the node is freed and recreated.
- [ ] **6.3 Collision.** On a `spawn_meshes` node, add one element to `mesh_entries` (a new `FlowMeshSpawnEntry` with a `BoxMesh` and `collision_mode = BoxFromBounds`). Add a `RigidBody3D` with a sphere `CollisionShape3D` a few metres above one instance and run the scene (F6). Then set the entry's `collision_bodies = PerInstance`, turn on Debug → Visible Collision Shapes and run again.
  - Expected: with the default `PerMultiMesh`, the spawned `MultiMeshInstance3D` has a single `StaticBody3D` child (one shape owner per instance, no `CollisionShape3D` nodes) and the sphere lands on the instance. With `PerInstance`, one `Collision_NNNN` body per instance, and the debug shapes outline every instance.

## 7. Hierarchical and runtime generation (4 min)

Open `demos/demo_hierarchical.tscn`.

- [ ] **7.1** Select the `FlowWorld3D` node and click **Generate All** in the Inspector. Note how long it takes.
  - Expected: trees (64 m cells) and rocks (16 m cells) appear over the 256 × 256 ground, rocks kept clear of the trees; no errors in the Output panel. The cells (`FlowCell_L0_0_0`, `FlowCell_L64_*`, `FlowCell_L16_*`, 273 in all) have no owner, so they are not listed in the Scene dock and are never saved.
- [ ] **7.2** Save the scene, then click **Cleanup All**.
  - Expected: saving writes no generated content (the `.tscn` does not change because of 7.1); Cleanup All removes everything that 7.1 created.
- [ ] **7.3** Run the scene (F6).
  - Expected: the bare ground first; after about half a second content streams in around the orbiting marker, ahead of it, and is removed behind it. Frame rate stays smooth (Debugger → Monitors → FPS).
- [ ] **7.4** While it runs, open the Scene dock's **Remote** tab and expand `FlowWorld3D`.
  - Expected: `FlowCell_*` children come and go as the marker moves; their number stays roughly constant (a headless run measured 43 to 47 generated cells after 1500 frames).

## 8. Hot reload (1 min)

- [ ] **8.1** With a graph containing a `surface_sampler` open, open `addons/flow_nodes_editor/nodes/surface_sampler.gd` in the Script editor, add a blank line at the end and save.
  - Expected: no errors; the node keeps its wires and settings, and ticking `use_bounding_shape` still rebuilds its ports (2.5).

---

## Optional: terrain plugins (outside the 30 minutes)

The Terrain3D and HTerrain adapters were tested only against fake classes. Do this only in a project that has the plugin installed.

- [ ] **T.1 Terrain3D.** Add a Terrain3D node with at least one region and two painted textures. Add a `FlowGraphNode3D` with `get_surface_data` (`source = Terrain`, no path) → `surface_sampler` → (D and A on the sampler).
  - Expected: points lie on the terrain surface (also across region borders), and the Data Inspector has `layer_<name>` columns whose values follow the painted textures. `get_surface_data`'s `@data` shows `terrain_type = Terrain3D`.
- [ ] **T.2 HTerrain.** The same with an HTerrain node with a splat map.
  - Expected: points on the surface where the terrain is (check a centred and an uncentred terrain, and a scaled `map_scale`); `layer_texture_<n>` columns follow the splat map.
- [ ] **T.3 Both plugins in one project.** With a Terrain3D and an HTerrain node in the same scene and no `terrain_node_path`.
  - Expected: the error starts with `ambiguous terrain: 2 terrain nodes found` and names both paths; setting `terrain_node_path` to either one works.

## Not covered by this list

- A port rebuild while a wire is being dragged.
- Profiling heavy graphs under the runtime scheduler (whether a 4 ms frame budget holds with large spawners).
- Cameras and players as generation sources in a real game loop.
