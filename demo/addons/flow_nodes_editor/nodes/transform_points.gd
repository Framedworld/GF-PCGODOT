@tool
extends "res://addons/flow_nodes_editor/nodes/transform.gd"

func _init():
	meta_node = {
		"title" : "Transform Points",
		"category" : "Spatial",
		"settings" : TransformNodeSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Godot-facing alias of Transform for point data.",
	}
