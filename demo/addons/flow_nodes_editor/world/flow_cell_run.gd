@tool
class_name FlowCellRun
extends RefCounted

## One evaluation of a FlowWorldCell on a FlowGraphNode3D (the cell
## component): a FlowExecutor with the cell's node_filter, the coarser cells'
## outputs as `preseeded` and the cell's capture list, run synchronously,
## threaded (the component's `threaded`) or time-sliced.
##
## Created by FlowGraphNode3D.begin_cell(); FlowGraphNode3D.generate_cell()
## runs it to completion at once. When the run finishes the component stores
## last_outputs / last_errors and emits `generated`, as generate() does.

var cell : FlowWorldCell
var executor : FlowExecutor
var ctx : FlowData.EvaluationContext
## Node errors of this run ([{ node, template, message }, ...]).
var errors : Array = []
## Graph outputs of this cell (output name -> FlowData.Data), once done.
var outputs : Dictionary = {}
## Captured bulks of the cell's capture_nodes (node name -> bulks), once done.
var captured : Dictionary = {}
## Graph variables after the run (the coarser cells' plus this cell's).
var variables : Dictionary = {}

var _component_ref : WeakRef
var _done : bool = false
var _cancelled : bool = false

func _init(component : Node, run_cell : FlowWorldCell, run_executor : FlowExecutor, run_ctx : FlowData.EvaluationContext, error_log : Array) -> void:
	_component_ref = weakref(component)
	cell = run_cell
	executor = run_executor
	ctx = run_ctx
	errors = error_log

## The cell component (null once freed).
func component() -> Node:
	return _component_ref.get_ref()

func is_done() -> bool:
	return _done

func was_cancelled() -> bool:
	return _cancelled

## Elements in the run and elements executed so far (time-sliced progress).
func node_count() -> int:
	return executor.node_count() if executor != null else 0

func progress() -> int:
	return executor.progress() if executor != null else 0

## Runs elements until `budget_ms` is spent (at least one; step(0) runs exactly
## one element). Returns true once the run finished.
func step(budget_ms : float = 4.0) -> bool:
	if _done:
		return true
	if executor == null or executor.step(budget_ms):
		_finish()
	return _done

## Runs every remaining element (threaded when the executor is THREADED and
## nothing ran yet) and finishes. Returns the cell outputs.
func run() -> Dictionary:
	if not _done:
		if executor != null:
			executor.run()
		_finish()
	return outputs

## Stops the run: the remaining elements are not executed; the evaluation is
## finalized (elements released) without emitting `generated`.
func cancel() -> void:
	if _done:
		return
	_cancelled = true
	if executor != null:
		executor.finalize()
	_done = true
	var comp = component()
	if comp != null and comp.has_method("_on_cell_run_finished"):
		comp._on_cell_run_finished(self, false)

func _finish() -> void:
	if _done:
		return
	if executor != null:
		executor.finalize()
		outputs = executor.outputs
		captured = executor.captured
	variables = ctx.variables.duplicate() if ctx != null else {}
	_done = true
	var comp = component()
	if comp != null and comp.has_method("_on_cell_run_finished"):
		comp._on_cell_run_finished(self, true)
