@tool
extends HBoxContainer
class_name FlowConnectorRow

# The Basic row containing a left/right connectors

var data : Dictionary = {}
signal in_popup
signal out_popup

func getInLabel() -> Label:
	return $LabelIn

func getOutLabel() -> Label:
	return $LabelOut
	
func getNode() -> FlowNodeWidget:
	return get_parent() as FlowNodeWidget

func _on_label_in_mouse_entered():	
	in_popup.emit()

func _on_label_in_mouse_exited():
	out_popup.emit()

func setData( new_data : Dictionary ):
	data = new_data

func isParameter() -> bool:
	return data && data.get( "is_parameter", false )
