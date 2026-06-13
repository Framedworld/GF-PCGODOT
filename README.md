# PCGODOT

[![Godot Engine](https://img.shields.io/badge/Godot-4.4%2B-%23478cbf?style=flat&logo=godot-engine&logoColor=white)](https://godotengine.org)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

**Unreal PCG-style node-graph procedural content for Godot 4.** Build scatter systems, spline fences, dungeons, and full level-generation pipelines in a visual graph editor docked inside the Godot editor — with the data model, hotkeys, and node vocabulary Unreal PCG users already know.

PCGODOT is a fork and major expansion of [Godot Flow](https://github.com/yabadabu/godot_flow) by yabadabu.

![PCGODOT Flow Editor](demo/addons/flow_nodes_editor/doc/demo_flashy_colonnade_ui.png)

### 🎬 Demo Video

https://github.com/user-attachments/assets/fe29dea7-82c0-481c-a022-46050b05642d

---

## Coming from Unreal PCG?

**Read [docs/COMING_FROM_UNREAL_PCG.md](docs/COMING_FROM_UNREAL_PCG.md).** It has a 5-minute orientation, a hotkey table (D/A/E work exactly as in UE), a concept dictionary (`$Density` → `density`, `$Seed` → `seed`, `@Last` → `@last`, ...), a full UE-node → PCGODOT-node dictionary, and three classic UE tutorials (forest scatter, density-noise clumping, spline fence) translated node by node. The add-node search popup understands UE node names — type "Static Mesh Spawner" and you'll find it.

For what does **not** translate yet (HiGen, GPU nodes, per-point bounds/steepness, ...), see the honest gap list in [docs/PARITY_ROADMAP.md](docs/PARITY_ROADMAP.md).

---

## Features

* **120+ nodes** covering samplers, spatial set operations, density workflows, attribute/metadata ops, filters, spawners, control flow, and generators — see the [Node Library Reference](demo/addons/flow_nodes_editor/doc/nodes_reference.md).
* **UE PCG parity core**: per-point `density` (0..1, sampler-initialized) and `seed` (position-derived, deterministic) streams; `density_filter`, `attribute_noise`, `normal_to_density`, and `projection` nodes; UE node names as search aliases.
* **Editor-docked graph editor** ("Data Flow" bottom panel) with right-click search, drag-wire-to-empty-space node creation, reroute dots (double-click a wire), comment frames, undo/redo, and JSON clipboard copy/paste.
* **Interactive 3D debugging**: press `D` on any node to draw its points as density-tinted cubes in the viewport; press `A` for a spreadsheet Data Inspector where clicking a row highlights the point in 3D.
* **Subgraphs & loops**: nest graphs as `.tres` resources with parameter pins and per-instance overrides, collapse any selection into a subgraph, iterate data with `loop` + `get_loop_index`.
* **Attribute selector syntax**: component access (`position.x`), `@last`, virtual streams (`index`, `front`/`up`/`right`), Yaw/Pitch/Roll aliases.
* **Native acceleration**: precompiled GDExtension (Windows/macOS) wrapping C++ KdTree and RTree for distance queries, difference/intersection, and self-pruning.
* **Runtime execution**: `FlowGraphNode3D` evaluates its graph at game startup and exposes `execute()` for re-triggering from scripts.

---

## Quick Start

1. Clone the repo and open the **`demo/`** folder as a project in **Godot 4.4 or newer**.
2. Open any scene in `demo/demos/` (start with `demo_sample_points.tscn` or `demo_random_subscenes.tscn`).
3. Click the `FlowGraphNode3D` in the scene tree — the **Data Flow** panel opens at the bottom of the editor with the node graph.
4. Right-click the canvas (or `Shift+A`) to add nodes; press `D` on a node to see its points in 3D, `A` to inspect its data table, `F` to zoom-fit.

To use the addon in your own project, copy `demo/addons/flow_nodes_editor/` into your project's `addons/` folder and enable **Flow Nodes Editor** under Project Settings → Plugins.

```gdscript
# Re-run a graph at runtime:
$FlowGraphNode3D.execute()
```

External addons can provide their own Flow node directories by calling
`FlowNodeRegistry.register_node_directory("res://addons/your_addon_name/nodes")`
from an editor plugin. Use namespaced node script filenames such as
`youraddon.example_node.gd` to avoid template collisions, and set
`"category": "Your Addon/Examples"` in node metadata to control where the node
appears in the add-node menu.

---

## Demo Scenes

34 demo scenes in `demo/demos/`, each a small self-contained graph:

| Scene | Shows |
|---|---|
| `demo_ue_forest` | **Epic's PCG forest quick-start, translated** — scan terrain → surface sample → density noise → density filter → transform → spawn ([tutorial walkthrough](docs/COMING_FROM_UNREAL_PCG.md)) |
| `demo_dungeon` | Full procedural dungeon (rooms, corridors, walls, props, lighting, two levels) via nested subgraphs, built from the bundled CC0 KayKit meshes |
| `demo_flashy_colonnade` | Helical colonnade architecture + rubble scatter |
| `demo_fallguys` | Fall Guys-style colored hexagon platform grid |
| `demo_bridge` | Bridge construction along a spline |
| `demo_rock_walls` | Wall segments placed along splines (fence-style placement) |
| `demo_path_over_region` | Carving a path through a scattered region |
| `demo_random_subscenes` | Weighted random scene scatter along curves ("forests & paths") |
| `demo_ray_cast_and_spawn_scene` | Raycast projection onto physics geometry + scene spawning |
| `demo_match_and_set` | Weighted asset table → per-point mesh assignment |
| `demo_sample_spline`, `demo_spline_fill`, `demo_spline_fill_performance`, `demo_spline_create` | Spline sampling, closed-spline interior fill (+ perf stress), splines from points |
| `demo_sample_points`, `demo_sample_mesh`, `demo_non_uniform_sampling` | Point scatter, mesh-surface sampling with hard-edge rejection, density-driven sampling |
| `demo_distance` | Distance-to-spline → density gradient |
| `demo_relax` | Lloyd relaxation of scattered points |
| `demo_grid_and_copy`, `demo_filter`, `demo_expression`, `demo_partition`, `demo_intersect`, `demo_remap` | Minimal single-concept demos |
| `demo_regenerate` | Collapsed subgraphs + regeneration |
| `demo_rotator_op` | **UE PCG parity:** Combine/Invert/Lerp/RotateAroundAxis rotation ops (Euler or quaternion) |
| `demo_density_difference` | **UE PCG parity:** density-aware Difference — overlap *attenuates* density instead of hard-removing points |
| `demo_subdivide_segment` | **UE PCG parity:** slice a spline into sized, oriented sub-segment points |
| `demo_grammar` | **UE PCG parity:** shape-grammar expansion (`"Post {Panel:2,Window:1}* Post"`) into placeable modules |
| `demo_attribute_domains` | **UE PCG parity:** per-data (`@Data`) vs per-point attributes via `add_attribute` domains |
| `demo_terrain_layers` | **UE PCG parity:** paint-layer sampling — read a mask texture into a `layer_*` weight, then filter on it |
| `demo_grid_size` | **UE PCG parity (foundation):** HiGen cell-size declaration node |
| `demo_compute_kernel` | **UE PCG parity (escape hatch):** run a GLSL compute shader over point streams (graceful CPU fallback) |

> **Assets:** the repository bundles the demo-referenced subset (~6 MB) of the CC0 [KayKit Dungeon Remastered](https://kaylousberg.itch.io/kaykit-dungeon-remastered) pack, so `demo_dungeon` works out of the box on a fresh clone. All other demos are fully self-contained (primitive meshes only).

---

## Gallery

| | |
|---|---|
| **UE PCG forest quick-start** — scan terrain → sample → density noise → filter → spawn ![UE Forest Demo](demo/addons/flow_nodes_editor/doc/demo_ue_forest.webp) | **Procedural dungeon** — rooms, corridors, props, lighting via nested subgraphs (KayKit CC0 assets) ![Dungeon Demo](demo/addons/flow_nodes_editor/doc/demo_dungeon.webp) |
| **Mesh-surface sampling** with hard-edge rejection ![Sampling Mesh](demo/addons/flow_nodes_editor/doc/demo_sample_mesh.png) | **Weighted subscene scatter** along curves ![Random Subscenes](demo/addons/flow_nodes_editor/doc/demo_random_subscenes.png) |
| **Distance → density** gradients ![Distance to Density](demo/addons/flow_nodes_editor/doc/demo_distance.png) | **Collapse to subgraph** ![Subgraph Collapse](demo/addons/flow_nodes_editor/doc/demo_subgraph_popup.png) |
| **Procedural colonnade + rubble** ![Helical Colonnade](demo/addons/flow_nodes_editor/doc/demo_flashy_colonnade_v2.png) | **Per-instance colors** (Fall Guys hexagons) ![Fall Guys Hexagons](demo/addons/flow_nodes_editor/doc/demo_spawn_nodes_v2.png) |

---

## Documentation

* **[Coming From Unreal PCG](docs/COMING_FROM_UNREAL_PCG.md)** — orientation, hotkeys, concept dictionary, the full UE→PCGODOT node dictionary, translated tutorials.
* **[Parity Roadmap](docs/PARITY_ROADMAP.md)** — honest list of UE PCG features not covered yet, with planned designs.
* **[Node Library Reference](demo/addons/flow_nodes_editor/doc/nodes_reference.md)** — every node, by category, linked to source.

---

## Building the Native Extension

Precompiled GDExtension binaries (KdTree/RTree spatial acceleration) ship in `demo/addons/flow_nodes_editor/bin/` for the Windows editor and macOS (debug). To build other targets — in particular **export templates**, which are required for exported games using the native extension:

```bash
git submodule update --init   # pulls godot-cpp

# Editor build for your host platform:
scons

# Windows export-template build (MinGW):
scons platform=windows target=template_release use_mingw=yes disable_exceptions=no
```

The C++ source lives under `demo/addons/flow_nodes_editor/native/src/`. Note that several nodes (`difference`, `self_pruning`, `distance`, `relax`, `sample_spline`, `point_neighborhood`) depend on the native `GDRTree`/`GDKdTree` classes directly, so the matching GDExtension binary for your platform/target is required for those nodes to run.

---

## License & Attributions

Licensed under the **Apache License 2.0** — see [LICENSE](LICENSE).

* PCGODOT is a fork and substantial expansion of **[Godot Flow](https://github.com/yabadabu/godot_flow)** by yabadabu (Apache 2.0); original copyright and attributions are preserved.
* Demo dungeon assets are from **[KayKit Dungeon Remastered](https://kaylousberg.itch.io/kaykit-dungeon-remastered)** by Kay Lousberg, licensed **CC0 1.0** (public domain) — the demo-referenced subset is bundled; the full pack is a free download.
