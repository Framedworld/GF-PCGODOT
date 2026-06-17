@tool
extends NodeSettings

@export_group("Mutate Seed")

enum eMode {
	## Replaces the seed with the generated hash.
	Replace,
	## Adds the generated hash to the existing seed value.
	Add,
	## Bitwise XORs the existing seed with the generated hash.
	Xor,
}

## Input attribute name this node reads for seed.
@export var in_seed_attribute : String = "seed":
	set(value):
		in_seed_attribute = value.strip_edges()
		emit_changed()

## Output attribute name that stores seed produced by this node.
@export var out_seed_attribute : String = "seed":
	set(value):
		out_seed_attribute = value.strip_edges()
		emit_changed()

## Selects which processing mode this node uses (similar to UE PCG node modes).
@export var mode : eMode = eMode.Replace:
	set(value):
		value = clampi(value, 0, eMode.size() - 1)
		mode = value
		emit_changed()

## Offset applied to seed offset before writing final output values.
@export var seed_offset : int = 1:
	set(value):
		seed_offset = value
		emit_changed()

## If enabled, mixes point position coordinates into the seed hash calculation.
@export var include_position : bool = true:
	set(value):
		include_position = value
		emit_changed()

func _init():
	super._init()
	resource_name = "Mutate Seed Settings"
