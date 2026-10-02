# node_conformance_test.gd
# WP9 node conformance harness: every stock template, default settings plus the
# per-template overrides, on the synthetic fixtures. Checks 1 to 4 fail the
# build; the static traits scan (check 5) only reports. The per-template table
# is printed by tools/conformance_report.gd and kept in docs/_round2/WP9.md.
class_name NodeConformanceTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const Harness = preload("res://tests/executor/conformance/conformance_harness.gd")
const Report = preload("res://tests/executor/conformance/conformance_report.gd")
const Overrides = preload("res://tests/executor/conformance/conformance_overrides.gd")
const StaticScan = preload("res://tests/executor/conformance/conformance_static_scan.gd")

# The whole matrix runs once per suite (about 15 s); the tests read it.
static var _results : Array = []


func before() -> void:
	FlowOutputCache.clear()
	_results = Report.run_all()
	FlowOutputCache.clear()
	# Spawners detach and queue_free what an earlier run spawned; let those go.
	await get_tree().process_frame
	await get_tree().process_frame


func after() -> void:
	_results = []


func _failures(check : String) -> Array:
	var failures := []
	for result in _results:
		var entry : Dictionary = result.checks[check]
		if entry.status == "fail":
			failures.append("%s: %s" % [ result.template, entry.detail ])
	return failures


func _assert_no_failures(check : String) -> void:
	var failures := _failures(check)
	assert_array(failures) \
		.override_failure_message("%s check failed for %d template(s):\n%s" % [ check, failures.size(), "\n".join(PackedStringArray(failures)) ]) \
		.is_empty()


func test_every_stock_template_is_checked_or_skipped_with_a_reason() -> void:
	var templates := Harness.stock_templates()
	var seen := []
	var problems := []
	for result in _results:
		seen.append(result.template)
		if result.skip == "" and result.cases.is_empty():
			problems.append("%s: no fixture case ran" % result.template)
	for template in templates:
		if not seen.has(template):
			problems.append("%s: not checked" % template)
	assert_int(templates.size()).is_greater(100)
	assert_array(problems).override_failure_message("\n".join(PackedStringArray(problems))).is_empty()


func test_no_input_mutation() -> void:
	_assert_no_failures("mutation")


func test_determinism() -> void:
	_assert_no_failures("determinism")


func test_thread_equivalence() -> void:
	_assert_no_failures("thread")


func test_cache_equivalence() -> void:
	_assert_no_failures("cache")


# Check 4 compares a cache HIT with a fresh run, so every warm run must hit:
# a miss means the cache key is not stable for equal settings and inputs.
func test_cache_warm_runs_hit() -> void:
	var misses := []
	for result in _results:
		if result.cacheable and result.skip == "" and result.cache_hits < result.cases.size():
			misses.append("%s: %d of %d warm runs hit" % [ result.template, result.cache_hits, result.cases.size() ])
	assert_array(misses).override_failure_message("\n".join(PackedStringArray(misses))).is_empty()


# A SCRIPT ERROR inside a node is a crash the node's error handling missed.
# Known ones are listed in conformance_overrides.gd and left out of the run.
func test_no_script_errors_in_node_code() -> void:
	var errors := []
	for result in _results:
		for case in result.cases:
			for text in case.script_errors:
				errors.append("%s on %s: %s" % [ result.template, case.case, text ])
	assert_array(errors).override_failure_message("\n".join(PackedStringArray(errors))).is_empty()


# Most templates must do real work on at least one fixture, so the checks are
# not only exercising error paths.
func test_most_templates_produce_output_on_some_fixture() -> void:
	var idle := []
	for result in _results:
		if result.skip == "" and result.worked == 0:
			idle.append(result.template)
	assert_int(idle.size()).override_failure_message("templates with no successful fixture: %s" % [ idle ]).is_less_equal(10)


# Check 5 is a heuristic for human review: it lists, never fails.
func test_static_scan_lists_findings_for_review() -> void:
	var templates := []
	for result in _results:
		templates.append(result.template)
	var findings := StaticScan.scan(templates)
	var unguarded := []
	for finding in findings:
		if finding.required and finding.guard == "":
			unguarded.append("%s %s:%d %s: %s" % [ finding.template, finding.script, finding.line, finding.label, finding.code ])
	if not unguarded.is_empty():
		print("Static traits scan, unguarded findings for review (threadable templates):\n  %s" % "\n  ".join(PackedStringArray(unguarded)))
	assert_array(findings).is_not_null()


func test_override_rows_name_existing_templates() -> void:
	var templates := Harness.stock_templates()
	var stale := []
	for template in Overrides.rows():
		if not templates.has(template):
			stale.append(template)
	assert_array(stale).is_empty()


func test_known_bug_rows_name_cases_of_their_template() -> void:
	# The harness only leaves out cases it would otherwise run, so a label that
	# was not left out names no case of the template.
	var stale := []
	for result in _results:
		for label in Overrides.for_template(result.template).get("known_bugs", {}):
			var matched := false
			for text in result.excluded:
				if String(text).begins_with(label + " ("):
					matched = true
			if not matched:
				stale.append("%s: %s" % [ result.template, label ])
	assert_array(stale).is_empty()
