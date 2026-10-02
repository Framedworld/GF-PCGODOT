extends RefCounted

## Shared checks for editor widget tests (editor_widget_modes_test.gd and the
## editor smoke harness): do a FlowNodeWidget's slots match its element?

## Empty when the widget's slots match its element's metadata.
static func port_mismatches(widget: FlowNodeWidget) -> Array:
	var problems := []
	var meta := widget.getMeta()
	var ins : Array = meta.get("ins", [])
	var outs : Array = meta.get("outs", [])
	if widget.port_signature() != widget._built_port_signature:
		problems.append("ports not rebuilt after the metadata changed")
	if widget.num_in_ports < ins.size():
		problems.append("%d input rows for %d flow inputs" % [widget.num_in_ports, ins.size()])
	for i in range(ins.size()):
		if not widget.is_slot_enabled_left(i):
			problems.append("flow input %d disabled" % i)
			continue
		var t : int = ins[i].get("data_type", FlowData.DataType.Invalid)
		if t != FlowData.DataType.Invalid and widget.get_slot_type_left(i) != t:
			problems.append("flow input %d has slot type %d, expected %d" % [i, widget.get_slot_type_left(i), t])
	for i in range(outs.size()):
		if widget.is_slot_enabled_right(i) != (outs[i] != null):
			problems.append("output %d enabled=%s" % [i, widget.is_slot_enabled_right(i)])
		elif outs[i] != null:
			var t : int = outs[i].get("data_type", FlowData.DataType.Invalid)
			if t != FlowData.DataType.Invalid and widget.get_slot_type_right(i) != t:
				problems.append("output %d has slot type %d, expected %d" % [i, widget.get_slot_type_right(i), t])
	if widget.num_ports > outs.size() and widget.is_slot_enabled_right(outs.size()):
		problems.append("output %d enabled past the outputs" % outs.size())
	return problems


