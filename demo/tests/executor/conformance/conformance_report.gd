extends RefCounted

## Runs the node conformance harness over the stock templates and renders the
## result as Markdown (the table in docs/_round2/WP9.md is produced by this).
## Used by node_conformance_test.gd and tools/conformance_report.gd.

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const Harness = preload("res://tests/executor/conformance/conformance_harness.gd")
const StaticScan = preload("res://tests/executor/conformance/conformance_static_scan.gd")

## Result records (Harness.check_template) for every stock template, or only
## those in `only` when it is not empty.
static func run_all(only : PackedStringArray = PackedStringArray()) -> Array:
	var results := []
	for template in Harness.stock_templates():
		if not only.is_empty() and not only.has(template):
			continue
		results.append(Harness.check_template(template))
	return results

static func traits_label(result : Dictionary) -> String:
	var label := ""
	if not result.main_thread and result.cacheable:
		label = "pure"
	elif not result.main_thread:
		label = "threadable"
	elif result.cacheable:
		label = "main, cacheable"
	else:
		label = "main"
	if result.traits_source == "meta":
		label += " (meta)"
	return label

static func check_cell(result : Dictionary, check : String) -> String:
	var entry : Dictionary = result.checks[check]
	match entry.status:
		"pass":
			if check == "cache":
				return "pass (%d/%d hit)" % [ result.cache_hits, result.cases.size() ]
			if check == "thread":
				var concurrent := 0
				for case in result.cases:
					if case.concurrent:
						concurrent += 1
				if concurrent < result.cases.size():
					return "pass (%d/%d batched)" % [ concurrent, result.cases.size() ]
			return "pass"
		"fail":
			return "**FAIL**"
	if result.skip != "":
		return "skip"
	return "skip: " + String(entry.detail)

static func scan_cell(result : Dictionary, findings : Array) -> String:
	if result.main_thread:
		return "n/a (main)"
	var total := 0
	var unguarded := 0
	for finding in findings:
		if finding.template != result.template or not finding.required:
			continue
		total += 1
		if finding.guard == "":
			unguarded += 1
	if total == 0:
		return "clean"
	return "%d hit(s), %d unguarded" % [ total, unguarded ]

## Full Markdown report.
static func build(only : PackedStringArray = PackedStringArray()) -> String:
	var start_us := Time.get_ticks_usec()
	var results := run_all(only)
	var templates := []
	for result in results:
		templates.append(result.template)
	var findings := StaticScan.scan(templates)
	var total_ms := float(Time.get_ticks_usec() - start_us) / 1000.0
	return render(results, findings, total_ms)

static func render(results : Array, findings : Array, total_ms : float) -> String:
	var out := PackedStringArray()
	var counts := { "pass": 0, "fail": 0, "skip": 0 }
	var case_count := 0
	for result in results:
		case_count += result.cases.size()
		for check in Harness.CHECKS:
			counts[result.checks[check].status] += 1
	out.append("Templates: %d. Fixture cases: %d. Check results: %d pass, %d fail, %d skip. Wall time %.1f s." % [
		results.size(), case_count, counts.pass, counts.fail, counts.skip, total_ms / 1000.0 ])
	var by_time := results.duplicate()
	by_time.sort_custom(func(a, b): return a.ms > b.ms)
	var slowest := []
	for i in range(mini(5, by_time.size())):
		slowest.append("`%s` %.0f ms" % [ by_time[i].template, by_time[i].ms ])
	out.append("Slowest templates: %s." % ", ".join(PackedStringArray(slowest)))
	out.append("")
	out.append("| Template | Traits | Fixtures | Worked | 1 Mutation | 2 Determinism | 3 Thread | 4 Cache | 5 Static scan | Notes |")
	out.append("|---|---|---|---|---|---|---|---|---|---|")
	for result in results:
		var note : String = result.note
		if result.skip != "":
			note = "skipped: " + result.skip
		elif result.owner_mode == "none":
			note = ("owner-less. " + note).strip_edges()
		out.append("| `%s` | %s | %d | %d | %s | %s | %s | %s | %s | %s |" % [
			result.template, traits_label(result), result.cases.size(), result.worked,
			check_cell(result, "mutation"), check_cell(result, "determinism"),
			check_cell(result, "thread"), check_cell(result, "cache"),
			scan_cell(result, findings), note.replace("|", "\\|") ])
	out.append("")
	out.append("### Failures")
	out.append("")
	var any_failure := false
	for result in results:
		for check in Harness.CHECKS:
			if result.checks[check].status == "fail":
				any_failure = true
				out.append("- `%s` %s: %s" % [ result.template, check, String(result.checks[check].detail).replace("\n", " ") ])
	if not any_failure:
		out.append("None.")
	out.append("")
	out.append("### Skipped templates")
	out.append("")
	var any_skip := false
	for result in results:
		if result.skip != "":
			any_skip = true
			out.append("- `%s`: %s" % [ result.template, result.skip ])
	if not any_skip:
		out.append("None.")
	out.append("")
	out.append("### Script errors raised inside node code (bugs)")
	out.append("")
	var script_errors := []
	for result in results:
		for case in result.cases:
			for text in case.get("script_errors", []):
				script_errors.append("- `%s` on `%s`: %s" % [ result.template, case.case, text ])
	out.append_array(PackedStringArray(script_errors) if not script_errors.is_empty() else PackedStringArray([ "None." ]))
	out.append("")
	out.append("### Cases left out as known bugs")
	out.append("")
	var excluded := []
	for result in results:
		for text in result.excluded:
			excluded.append("- `%s`: %s" % [ result.template, text ])
	out.append_array(PackedStringArray(excluded) if not excluded.is_empty() else PackedStringArray([ "None." ]))
	out.append("")
	out.append("### Errors printed outside setError (missing from FlowNodeIO.last_errors)")
	out.append("")
	var console := []
	for result in results:
		var seen := {}
		for case in result.cases:
			for text in case.get("console_errors", []):
				if not seen.has(text):
					seen[text] = []
				seen[text].append(case.case)
		for text in seen:
			console.append("- `%s` (%s): %s" % [ result.template, ", ".join(PackedStringArray(seen[text])), text ])
	out.append_array(PackedStringArray(console) if not console.is_empty() else PackedStringArray([ "None." ]))
	out.append("")
	out.append("### Templates that never produced output without an error")
	out.append("")
	var dead := []
	for result in results:
		if result.skip == "" and result.worked == 0:
			var first_error := ""
			for case in result.cases:
				if not case.errors.is_empty():
					first_error = String(case.errors[0])
					break
			dead.append("- `%s`: %s" % [ result.template, first_error if first_error != "" else "empty output" ])
	out.append_array(PackedStringArray(dead) if not dead.is_empty() else PackedStringArray([ "None." ]))
	out.append("")
	out.append("### Traits declared in meta_node that disagree with the table")
	out.append("")
	var disagreements := []
	for result in results:
		var row = result.table_row
		if row == null:
			continue
		if bool(row[0]) != result.main_thread or bool(row[1]) != result.cacheable:
			disagreements.append("- `%s`: table [main_thread=%s, cacheable=%s], effective [main_thread=%s, cacheable=%s] (meta_node wins)" % [
				result.template, bool(row[0]), bool(row[1]), result.main_thread, result.cacheable ])
	out.append_array(PackedStringArray(disagreements) if not disagreements.is_empty() else PackedStringArray([ "None." ]))
	out.append("")
	out.append("### Static scan findings (threadable templates)")
	out.append("")
	if findings.is_empty():
		out.append("None.")
	else:
		out.append("| Template | Location | Pattern | Guard | Code |")
		out.append("|---|---|---|---|---|")
		for finding in findings:
			out.append("| `%s` | `%s:%d` | %s%s | %s | `%s` |" % [
				finding.template, finding.script, finding.line, finding.label,
				"" if finding.required else " (extra)",
				("`%s`" % finding.guard.replace("|", "\\|")) if finding.guard != "" else "none",
				finding.code.replace("|", "\\|").replace("`", "'") ])
	return "\n".join(out)
