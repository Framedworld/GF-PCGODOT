@tool
extends NodeSettings

# Settings for the Grammar Expand node.
#
# A grammar string is parsed against a module table (symbol -> mesh/size/weight)
# and expanded per input span into a flat list of module instances that are then
# fitted (stretched or clipped) onto the span.

enum eFitMode {
	## Scale modules so the expanded sequence exactly fills each span.
	STRETCH,
	## Keep module sizes; drop modules that overrun the span.
	CLIP,
}

@export_group("Grammar Expand")

## Grammar string. Supported subset:
##   - sequence:        A B C            (whitespace or commas separate tokens)
##   - tuple:           [A,P]            (symbol with behavior; behavior is parsed but
##                                        only the symbol selects a module)
##   - repetition:      A*  or  A:3      (* repeats to fill the span; :N repeats N times)
##   - weighted choice: {A,B}  or  {[A,P]:2,[B,P]:1}
## Example: [Post,P] {[Panel,P]:2,[Gate,P]:1}* [Post,P]
@export_multiline var grammar : String = "A*"

## Module table: each entry maps a `symbol` to a `mesh`, footprint `size` and
## selection `weight`. Use GrammarModuleResourceData resources.
@export var modules : Array[ FlowUserResourceData ] = []

## Attribute name of the per-point length carried by the input spans (Float).
@export var length_attribute : String = "length"

## How the expanded modules are fitted onto each span.
@export var fit_mode : eFitMode = eFitMode.STRETCH

## Cross-section size written into size.x / size.y of each emitted module point.
@export var cross_section_size : Vector2 = Vector2.ONE

@export_group("Output Attributes")

## Output attribute name for each module's symbol (String).
@export var out_symbol_attribute : String = "symbol"

## Output attribute name for each module's index within its span (Int).
@export var out_module_index_attribute : String = "module_index"

## Output attribute name for the emitted mesh (Resource). Empty disables mesh output.
@export var out_mesh_attribute : String = "mesh"

func _init():
	super._init()
	resource_name = "Grammar Expand Settings"
