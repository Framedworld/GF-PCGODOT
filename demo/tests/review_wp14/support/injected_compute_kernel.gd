# injected_compute_kernel.gd
# compute_kernel with its rendering device replaced by a test double.
extends "res://addons/flow_nodes_editor/nodes/compute_kernel.gd"

var fake_rd = null

func _create_rendering_device():
	return fake_rd
