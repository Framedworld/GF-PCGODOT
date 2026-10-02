@tool
extends FlowNodeBase

# UE PCG parity: Runtime Quality Branch. Routes the whole input to the output
# pin of the current quality level (Unreal's pcg.Quality scalability levels:
# Low 0, Medium 1, High 2, Epic 3, Cinematic 4) when that pin is enabled in the
# settings, otherwise to "Default". The other pins carry the input's schema
# with zero rows, like branch.
#
# Quality level resolution (quality_level()):
#   1. settings.quality_override when >= 0;
#   2. ctx.runtime_params["quality"] (int, float, numeric string or level name);
#   3. the project setting flow_nodes/quality_level;
#   4. 0 (Low).
# The static helpers are shared with runtime_quality_select.gd.

## Project setting holding the default quality level (int, 0..4).
const SETTING_QUALITY_LEVEL := "flow_nodes/quality_level"
## Runtime parameter that overrides the project setting for one evaluation.
const RUNTIME_PARAM_QUALITY := "quality"
const LEVEL_NAMES := [ "Low", "Medium", "High", "Epic", "Cinematic" ]
const MAX_LEVEL := 4

static var _setting_registered := false

## Registers flow_nodes/quality_level (int enum Low..Cinematic, default 0) so it
## shows in Project Settings. Safe to call repeatedly; the default value is not
## written to project.godot.
static func ensure_project_setting() -> void:
	if not ProjectSettings.has_setting( SETTING_QUALITY_LEVEL ):
		ProjectSettings.set_setting( SETTING_QUALITY_LEVEL, 0 )
	ProjectSettings.set_initial_value( SETTING_QUALITY_LEVEL, 0 )
	ProjectSettings.set_as_basic( SETTING_QUALITY_LEVEL, true )
	ProjectSettings.add_property_info( {
		"name": SETTING_QUALITY_LEVEL,
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": ",".join( LEVEL_NAMES ),
	} )
	_setting_registered = true

## Level 0..4 from an int, float, numeric string or level name
## (case-insensitive); -1 when the value is not a level.
static func parse_level( value ) -> int:
	match typeof( value ):
		TYPE_INT:
			return clampi( value, 0, MAX_LEVEL )
		TYPE_FLOAT:
			return clampi( int( round( value ) ), 0, MAX_LEVEL )
		TYPE_BOOL:
			return 0
		TYPE_STRING, TYPE_STRING_NAME:
			var text := String( value ).strip_edges()
			if text.is_valid_int():
				return clampi( int( text ), 0, MAX_LEVEL )
			for i in range( LEVEL_NAMES.size() ):
				if LEVEL_NAMES[i].to_lower() == text.to_lower():
					return i
	if value is FlowData.Data:
		return parse_level( value.first( "@last" ) if value.last_added_stream_name != "" else null )
	return -1

## Current quality level for this evaluation (see the header for the order).
static func quality_level( ctx, override_level : int = -1 ) -> int:
	if override_level >= 0:
		return clampi( override_level, 0, MAX_LEVEL )
	if ctx != null and ctx.runtime_params.has( RUNTIME_PARAM_QUALITY ):
		var from_param := parse_level( ctx.runtime_params[ RUNTIME_PARAM_QUALITY ] )
		if from_param >= 0:
			return from_param
		push_warning( "Runtime parameter 'quality' = %s is not a quality level (0..4 or Low/Medium/High/Epic/Cinematic); using the project setting" % str( ctx.runtime_params[ RUNTIME_PARAM_QUALITY ] ) )
	var from_setting := parse_level( ProjectSettings.get_setting( SETTING_QUALITY_LEVEL, 0 ) )
	return from_setting if from_setting >= 0 else 0

## Output/input pin for `level`: 1 + level when that level's pin is enabled,
## else 0 (Default).
static func pin_for_level( level : int, level_pins : Array ) -> int:
	if level >= 0 and level < level_pins.size() and level_pins[level]:
		return level + 1
	return 0

func _init():
	if not _setting_registered:
		ensure_project_setting()
	meta_node = {
		"title" : "Runtime Quality Branch",
		"settings" : RuntimeQualityBranchNodeSettings,
		"aliases" : ["Runtime Quality Branch", "Quality Branch", "Scalability Branch", "LOD Branch"],
		"category" : "ControlFlow",
		"pure" : false,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Default" }, { "label" : "Low" }, { "label" : "Medium" }, { "label" : "High" }, { "label" : "Epic" }, { "label" : "Cinematic" }],
		"tooltip" : "Routes the whole input to the pin of the current quality level (Low 0 .. Cinematic 4) when that pin is enabled\nin the settings, otherwise to Default. The other pins get the input's schema with no rows.\nLevel: quality_override, else the runtime parameter \"quality\", else the project setting flow_nodes/quality_level (default 0).",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input( 0, ctx, "Input 'In'" )
	if in_data == null:
		if num_generated_bulks > 0 and generated_bulks[num_generated_bulks - 1].size() == 1:
			for p in range( 1, 6 ):
				set_output( p, FlowData.Data.new() )
		return
	var level := quality_level( ctx, settings.quality_override )
	var target := pin_for_level( level, settings.level_pins() )
	for p in range( 6 ):
		set_output( p, in_data if p == target else in_data.emptyLike() )
