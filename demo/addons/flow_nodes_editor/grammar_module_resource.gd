@tool
class_name GrammarModuleResourceData
extends FlowUserResourceData

# A grammar module: maps a grammar symbol to a mesh, a footprint size and a
# selection weight. Mirrors the weighted-table resource pattern used by the
# `assets` node (see MeshesUserResourceData). Consumed by the grammar_expand
# node's module table.

## Grammar symbol this module represents (e.g. "A", "BL", "Post").
@export var symbol : String = ""

## Mesh spawned for this module (optional — grammar_expand can also feed
## match_and_set on `symbol` instead of emitting meshes directly).
@export var mesh : Mesh

## Footprint length of this module along the span (world units). Used to fit
## modules into each segment; also written into size.z of the emitted point.
@export var size : float = 1.0

## Relative weight for weighted choice `{...}` selection. Higher = more frequent.
@export var weight : float = 1.0
