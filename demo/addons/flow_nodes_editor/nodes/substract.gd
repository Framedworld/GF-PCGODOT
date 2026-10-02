@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Substract",
		"category" : "Spatial",
		"settings" : SubstractSettings,
		"ins" : [{ "label": "In A" }, { "label": "In B" }], 
		"outs" : [{ "label" : "Out" }],
		"hide_inputs" : true,
		"tooltip" : "Applies the boolean logic 'substract', where the points of A that overlap points in B are removed.\nThe same node can be changed to return only the points A intersecting the points of B",
	}
	
func getTitle() -> String:
	return "Substract" if settings.operation == SubstractSettings.eOperation.A_Minus_B else "Intersection"

func execute( _ctx : FlowData.EvaluationContext ):
	var in_dataA: FlowData.Data = get_input(0)
	var in_dataB : FlowData.Data = get_input(1)
	
	if in_dataA == null:
		setError( "Input A not found")
		return
		
	if in_dataB == null:
		setError( "Input B not found")
		return

	var tA = GDRTree.new()
	var posA = in_dataA.getVector3Container( FlowData.AttrPosition )
	var szA = in_dataA.getVector3Container( FlowData.AttrSize )
	tA.add( posA, szA )
	
	var posB = in_dataB.getVector3Container( FlowData.AttrPosition )
	var szB = in_dataB.getVector3Container( FlowData.AttrSize )
	
	var inverse_result = settings.operation == SubstractSettings.eOperation.A_Intersection_B
	var result = tA.overlaps( posB, szB, inverse_result )
	
	var out_data : FlowData.Data = in_dataA.filter( result.idxs_overlapped )
		
	set_output( 0, out_data )
