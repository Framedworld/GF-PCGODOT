# PCGODOT (Flow Graph)

[![Godot Engine](https://img.shields.io/badge/Godot-%23FFFFFF.svg?style=flat&logo=godot-engine&logoColor=cyan)](https://godotengine.org)
[![Version](https://img.shields.io/badge/Version-1.1.0--aligned-blue.svg)](#)

**PCGODOT** is a highly powerful, node-based Procedural Content Generation (PCG) framework for Godot 4.6, heavily inspired by **Unreal Engine 5's PCG**. It enables developers to construct intricate point-set distributions, manipulate spatial attributes, and spawn meshes or scenes procedurally using a visual flow graph.

This version has been upgraded to align **1:1 with Unreal Engine's PCG Node Reference**, featuring improved control flow, advanced filtering, and a polished dark HSL theme.

---

## 🎨 Gallery & Showcases

### 1. Sampling Meshes (Discarding Hard Edges)
Distribute points across the faces of a 3D Mesh (e.g. the letter "B") while optionally pruning points near hard edges.
![Sampling Mesh](demo/addons/flow_nodes_editor/doc/demo_sample_mesh.png)

### 2. Random Subscenes Distribution (Forests & Paths)
Distribute different subscenes randomly along curves and paths using attributes, custom rotation-alignment filters, and scene scanners.
![Random Subscenes](demo/addons/flow_nodes_editor/doc/demo_random_subscenes.png)

### 3. Unified Filters & Category Popup
Browse nodes structured into standardized categories matching Unreal PCG. Select filters such as `Filter Data by Attribute`, `Filter Data by Tag`, and `Filter Data by Type`.
![Filters](demo/addons/flow_nodes_editor/doc/demo_filter.png)

### 4. Proximity Sampling & Distance to Density
Sample points and scale their density values smoothly based on their distance/proximity to curves or splines.
![Distance to Density](demo/addons/flow_nodes_editor/doc/demo_distance.png)

### 5. Nested Subgraphs & Selection Collapse
Create nested graphs and easily collapse selected nodes into a reusable Subgraph.
![Subgraph Collapse](demo/addons/flow_nodes_editor/doc/demo_subgraph_popup.png)

### 6. Procedural Helical Colonnade & Rubble Scatter
Generate complex procedural architecture such as helical towers. Combines curve sampling with coordinate transforms, relative lintel placement, and duplicate scatter operations to create debris and rubble.
![Helical Colonnade](demo/addons/flow_nodes_editor/doc/demo_flashy_colonnade.png)

---

## 🚀 Key Features

* **Unreal Engine PCG Alignment (1:1)**: Unified categories, names, and logic schemas conforming to the Unreal PCG specifications.
* **+50 Nodes**: A robust suite of nodes covering:
  * Spline & Mesh sampling (surface, volume, interior).
  * Math operations, custom expressions, and reductions.
  * Tagging, attribute manipulation, and boolean data filters.
  * Raycasting, collision setup, and spatial queries.
* **Advanced Subgraphs & Loops**: Seamlessly nest graphs inside other graphs with local parameters, custom outputs, and array loops.
* **Core Tagging Support**: A dedicated `tags` property (`PackedStringArray`) inside data elements for advanced tag-based filtering.
* **Live 3D Debug Overlay**: Direct 3D viewport visualizations showing point positions, density gradients, scale, and rotations.
* **Grid Data Inspector**: Step-by-step table viewing of attributes at any node in the graph, with active highlighting in the 3D viewport.
* **Copy/Paste**: Import/export graph components instantly as JSON.

---

## 📂 Node Library Categories

PCGODOT organizes nodes according to the official Unreal Engine PCG structure:

### 🧩 Subgraphs & Control Flow
* **Subgraph**: Runs another PCG graph resource inline.
* **Loop**: Evaluates a subgraph repeatedly over elements.
* **Output**: Exposes custom output ports for subgraphs.
* **Branch**: Directs point-sets down different paths based on conditions.
* **Select**: Routes a single dataset dynamically.
* **Select Multi**: Merges and routes multiple datasets.
* **Switch**: Evaluates multiple pathways using integer keys.

### 📊 Filtering & Sampling
* **Filter Data by Tag**: Isolates points based on their string tags.
* **Filter Data by Attribute**: Evaluates comparisons (e.g. `density > 0.5`) to isolate points.
* **Filter Data by Type**: Filters data points by spatial class type.
* **Select Points**: Samples points based on ratios or thresholds.
* **Sample Mesh**: Distributes points across a 3D Mesh's faces.
* **Sample Spline**: Follows or fills 3D curves.

### 📐 Point Ops & Densities
* **Bounds Modifier**: Shrinks, expands, or aligns point bounds.
* **Build Rotation from Up**: Generates correct rotations matching custom surface normals.
* **Combine Points**: Combines spatial properties of multiple points.
* **Duplicate Point**: Multiplies points with custom offsets.
* **Density Remap**: Modulates point density values using curve remapping.
* **Distance to Density**: Scales point density based on proximity to other objects.

---

## 🛠️ Installation & Setup

1. Copy the following folders from this repository into your Godot project's root:
   * `demo/addons/flow_nodes_editor`
   * `demo/bin`
2. Open your project in Godot: **Project** → **Project Settings** → **Plugins**.
3. Locate **Flow Nodes Editor** and toggle the status to **Enabled**.

---

## 🎮 Quickstart Guide

In a 3D Scene:
1. Create a `FlowGraphNode3D` node.
2. In the right-hand panel, select the **Data Flow** dock (appears when the node is selected).
3. Press **Shift+A** (or **Right-click**) inside the graph to open the **Add Node** panel.
4. Add a generator like **Grid**, then connect it to **Spawn Scenes** or **Spawn Meshes**.
5. Press **D** on a selected node to toggle its 3D debug visualizer.
6. Press **E** to toggle the bottom **Data Inspector** and view the raw attributes of each point.

---

## 🏗️ Building from Sources

If you want to compile the KdTree and RTree C++ wrappers yourself:

```bash
git submodule update --init
scons
```
Precompiled binaries for Windows and macOS are included under `demo/bin/` by default.

---

## 📄 License
This project is licensed under the MIT License. Feel free to adapt and expand it!
