# Sample Terrain Layers — implementation notes

Implements the generic path (b) from the PARITY_ROADMAP "Landscape paint-layer sampling" section.

## Node: `sample_terrain_layers`

**Category:** Sampler  
**Aliases:** Get Landscape Data, Landscape Layers, Splat Sampler  
**Files:**
- `demo/addons/flow_nodes_editor/nodes/sample_terrain_layers.gd`
- `demo/addons/flow_nodes_editor/nodes/sample_terrain_layers_settings.gd`

### What it does

Accepts a set of user-assigned mask textures (one per "paint layer") and samples each texture at the world XZ position (or an explicit UV attribute) of every input point. For each layer it writes one `Float` stream (values in 0..1) onto the point data, named `<prefix><layer_name>` (default prefix `layer_`). Downstream the user filters with the existing `density_filter` or `attribute_filter_range` nodes — this node does no filtering itself.

### Settings

#### Layer list (`layers : Array[LayerEntry]`)

Each `LayerEntry` resource has:

| Property | Type | Description |
|---|---|---|
| `layer_name` | `String` | Short identifier; becomes the stream suffix (e.g. `grass` → stream `layer_grass`). Must be unique within the list. |
| `texture` | `Texture2D` | Mask texture. The selected channel (see `value_channel`) is sampled as the layer weight. |

#### Top-level settings

| Property | Default | Description |
|---|---|---|
| `stream_prefix` | `"layer_"` | Prepended to `layer_name` for the output stream name. |
| `use_world_xz` | `true` | When true, derives UV from `world_min`/`world_max` bounds. When false, reads an existing UV attribute. |
| `world_min` | `(-100, -100)` | World XZ corner that maps to UV (0, 0). X = world X, Y = world Z. |
| `world_max` | `(100, 100)` | World XZ corner that maps to UV (1, 1). |
| `uv_attribute_name` | `"uv"` | Attribute to read when `use_world_xz` is false. Must be `Vector` (XY used) or `Color` (RG used). |
| `value_channel` | `R` | Which channel of each mask texture encodes the layer weight: R, G, B, A, or Luminance. |
| `wrap_mode` | `Clamp` | How UVs outside [0,1] are handled: Clamp (border pixel) or Wrap (tile). |

### World-to-UV mapping

With `use_world_xz = true`:

```
U = (point.x - world_min.x) / (world_max.x - world_min.x)
V = (point.z - world_min.y) / (world_max.y - world_min.y)
```

`world_min.y` and `world_max.y` correspond to world Z (the Vector2 Y component stores the Z axis value because paint-layer bounds are 2-D).

Set `world_min`/`world_max` to match the terrain plugin's AABB footprint.  For a `Terrain3D` node this is typically readable from `Terrain3D.get_storage().get_height_range()` or the plugin's `data_directory` metadata.

### Error conditions

The node calls `setError` and stops execution for:

- Empty layer list
- Null layer entry or empty `layer_name` in any entry
- Duplicate `layer_name` values
- Missing or wrong-type position/UV stream on input
- Degenerate world bounds (zero range on either axis)
- Unassigned, unimported, or undecompressable texture on any layer

### Example usage

**Scenario:** Spawn rocks only where the Terrain3D "rock" paint layer is strong.

1. **Surface Sampler** → produces a dense point cloud over the terrain surface.
2. **Sample Terrain Layers** (this node):
   - Add one `LayerEntry`: name = `rock`, texture = your rock splat mask.
   - Set `world_min` / `world_max` to match the terrain's world AABB footprint.
   - Leave `value_channel = R` if your mask is a greyscale texture packed in the R channel.
   - Output now carries a `layer_rock` Float stream on every point.
3. **Attribute Filter Range** (or **Density Filter** after a **Remap**):
   - Filter `layer_rock` in range [0.5, 1.0] to keep only strongly-painted areas.
4. **Spawn Meshes** → place rock meshes on surviving points.

**Scenario: explicit UV (e.g. pre-baked UV from a scan_meshes):**

1. Input points already carry a `uv` Vector stream from a prior node.
2. In **Sample Terrain Layers**, disable `use_world_xz`, set `uv_attribute_name = "uv"`.
3. Assign mask textures and add layer entries as above.

### Path (a) — terrain plugin integration

Path (a) (auto-detecting Terrain3D / HTerrain plugin nodes and reading their splat maps directly) is **not implemented** yet.  To approximate it manually:

- Open the terrain plugin's storage resource, locate the control/splat texture, export it as a PNG, import it in Godot, and assign it to a layer entry here.
- `world_min` / `world_max` should match the terrain's configured data bounds.

### Future work

- Path (a): auto-detect `Terrain3D` node, read `get_storage().get_color_maps()` (or equivalent) directly without requiring a manual export step.
- Multi-channel packing: allow a single RGBA texture to drive four named layers simultaneously (one per RGBA channel), reducing texture slots and upload cost.
