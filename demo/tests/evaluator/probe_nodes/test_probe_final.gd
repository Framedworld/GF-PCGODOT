@tool
extends "res://tests/evaluator/probe_nodes/test_probe.gd"

## Same as test_probe but flagged is_final, so the evaluator treats it as an
## execution root (like a spawner) without needing an output node.

func _init():
	super._init()
	meta_node["title"] = "Test Probe (Final)"
	meta_node["is_final"] = true
