## Behaviour specs: `specs/<name>.scm`, one `(test "name" (setup …) (steps …))`
## form each, the surface roc-signals' specs use with native locators.
##
## Everything here is pure, so a spec is parsed and checked on any system
## (`macos.roc test --check`). Running one drives AppKit and so needs a
## Mac: `lower` turns the parsed steps into the line protocol
## the host performs when `ROC_SPEC` holds it, the host prints one tagged
## observation per expectation, and `judge` compares them here, reporting
## `file:line:col: expected …, saw …`. `update` rewrites each
## `expect-dump`'s tree with what the run showed, and lowers allocation
## bounds, and nothing else.
##
## The window is an S-expression too: the host dumps its view tree as one,
## `(window :width 360 :height 237 (vstack :views 1 …))`, and `expect-dump`
## and `expect-tree` hold one, compared node by node (`tree_matches`).
##
## `scripts/src/Spec.roc` is a byte-identical copy of `cli/Spec.roc`, and
## `check` fails when they differ. Change `cli/Spec.roc`, then copy it.
Spec := [].{

	## A source position, from 1.
	Pos : { line : U64, column : U64 }

	## What is wrong, and where.
	Problem : { pos : Pos, message : Str }

	## One s-expression and where it starts.
	Sx := [Sym(Str, Pos), Text(Str, Pos), Int(I64, Pos), List(List(Sx), Pos)]

	## A locator: what to find, outermost first. `(within A B)` is A's
	## parts then B's: B is looked for inside the one thing A finds.
	Loc : List({ kind : Str, text : Str })

	## A view tree a spec expects, written back as canonical text
	## (`render`), and where it is written.
	Tree : { text : Str, pos : Pos }

	## The steps a spec can take.
	Op : [
		Click(Loc),
		Fill(Loc, Str),
		Submit(Loc),
		Toggle(Loc),
		Select(Loc),
		Hover(Loc),
		Choose(Str),
		Press({ key : Str, heard : [Any, Heard(Bool)] }),
		Files(List(Str)),
		Drop(List(Str)),
		Move(I64, I64),
		Leave,
		Sweep(List(I64)),
		Scroll(I64),
		Phase(Str),
		Stats,
		Window,
		Wait(I64),
		Reload,
		ExpectDump(Tree),
		ExpectTree(Loc, Tree),
		ExpectVisible(Loc),
		ExpectAbsent(Loc),
		ExpectText(Loc, Str),
		ExpectChecked(Loc, Bool),
		ExpectDisabled(Loc, Bool),
		ExpectWorkers(List({ field : Str, count : I64 })),
		StubHttp({ url : Str, status : I64, body : Str, headers : List((Str, Str)) }),
		FailHttp({ kind : Str, detail : Str }),
		RunEffect(I64),
		TickInterval(I64),
		FireTimer(I64),
		AdvanceTime(I64),
		AwaitWork,
		ExpectPendingEffects(I64),
		ExpectInterval(I64, I64),
		ExpectRequest(I64, List({ field : Str, value : Str })),
		ExpectCancelled(I64),
		MarkMetrics,
		ExpectMetricDelta(Str, I64),
		ExpectMetricDeltaAtMost(Str, I64, Pos),
		ExpectAllocationsAtMost(I64, Pos),
		ExpectAllocatedBytesAtMost(I64, Pos),
		ExpectNoNewLiveAllocations,
		Frame(I64),
		FrameClock(Str),
		StepSource(Str, I64),
		Repaint,
		WindowSize(I64, I64),
		ScreenSize(I64, I64),
		Renderer(Str),
		RequireMetal,
		BenchSurfaces(I64),
		ExpectProbe(Loc, I64, I64, List(Field)),
		ExpectSurfaces(List(Field)),
		Render(I64),
		Slide(Loc, I64),
		StallAnalysis(Bool),
		ExpectAudioStatus(List(Field)),
		ExpectTone(I64, Str),
		ExpectEq(List(Field)),
		ExpectSnapshot(List(Field)),
		ExpectHistory(List(Field)),
		ExpectSources(List(Field)),
		RequireAvTiming,
		MarkAvTiming,
		ExpectAvOffset(List(Field)),
		ExpectFramePacing(List(Field)),
	]

	## One `:name value` pair an expectation holds, its value as text.
	Field : { field : Str, value : Str }

	## One step and where it is written.
	Step : { pos : Pos, op : Op }

	## What a spec sets before the app mounts: the worker pool's size (0 for
	## the host's own), the virtual clock's time at mount, in milliseconds
	## since 1970, local storage's pairs, and whether effects are performed
	## for real rather than held for the steps to answer (a demo's
	## `(live-effects)`), and whether the playback session renders on a
	## manual clock, offline and never to a speaker (`(audio-clock manual)`).
	Setup : { pool : U64, time : I64, storage : List((Str, Str)), live : Bool, audio_manual : Bool }

	## A parsed spec.
	Parsed : { name : Str, setup : Setup, steps : List(Step) }

	## Parse a spec file's text.
	parse : Str -> Try(Parsed, Problem)
	parse = |text| {
		root = read_one(text)?
		(items, pos) = match root {
			List(xs, p) => (xs, p)
			other => return Err({ pos: pos_of(other), message: "a spec is one (test \"name\" (steps …)) form" })
		}
		match items {
			[Sym("test", _), Text(name, _), .. as sections] => {
				var $setup = { pool: 0, time: 0, storage: [], live: Bool.False, audio_manual: Bool.False }
				var $steps = []
				var $saw_setup = Bool.False
				var $saw_steps = Bool.False
				for section in sections {
					match section {
						List([Sym("setup", spos), .. as forms], _) => {
							if $saw_setup or $saw_steps {
								return Err({ pos: spos, message: "setup comes once, before steps" })
							}
							$saw_setup = Bool.True
							for form in forms {
								$setup = setup_form($setup, form)?
							}
						}
						List([Sym("steps", spos), .. as forms], _) => {
							if $saw_steps {
								return Err({ pos: spos, message: "steps comes once" })
							}
							if forms.is_empty() {
								return Err({ pos: spos, message: "steps holds at least one step" })
							}
							$saw_steps = Bool.True
							for form in forms {
								$steps = $steps.append(step_form(form)?)
							}
						}
						other => return Err({ pos: pos_of(other), message: "expected a (setup …) or (steps …) section" })
					}
				}
				if !$saw_steps {
					return Err({ pos, message: "the test has no (steps …) section" })
				}
				Ok({ name, setup: $setup, steps: $steps })
			}
			[Sym("test", _), other, ..] => Err({ pos: pos_of(other), message: "the test's name is a string" })
			_ => Err({ pos, message: "a spec starts with test: (test \"name\" (steps …))" })
		}
	}

	## The line protocol the host performs (`ROC_SPEC`): a version line, the
	## setup, then one line per step, `k<TAB>verb<TAB>field…` with `k` the
	## step's number from 1. A field escapes `\`, tab and line break.
	lower : Parsed -> Str
	lower = |{ setup, steps, .. }| {
		head = ["roc-spec 1", "0\ttime\t${setup.time.to_str()}"]
			.concat(if (setup.pool > 0) ["0\tpool\t${setup.pool.to_str()}"] else [])
			.concat(setup.storage.map(|(key, value)| "0\tlocal-storage\t${escape(key)}\t${escape(value)}"))
			.concat(if (setup.live) ["0\tlive"] else [])
			.concat(if (setup.audio_manual) ["0\taudio-clock\tmanual"] else [])
		var $lines = head
		var $k = 0.U64
		for step in steps {
			$k = $k + 1
			$lines = $lines.append(Str.join_with([$k.to_str()].concat(lowered(step.op).map(escape)), "\t"))
		}
		Str.join_with($lines, "\n").concat("\n")
	}

	## What the host printed, read back: the observation of each step that
	## made one, the step that failed and why, and whether it finished.
	Run : { observed : List({ step : U64, lines : List(Str) }), failed : Try({ step : U64, message : Str, lines : List(Str) }, [None]), skipped : Try(U64, [None]), done : Bool }

	## Read the host's standard output: `@k obs` or `@k fail MESSAGE`
	## starts a record, each `|LINE` adds a line to it, `@k skip WHY` says the
	## run ended at step `k` without judging the rest (`require-metal` on a
	## Mac without a Metal device), and `@done` says every step ran. Anything
	## else is the app's own output, and ignored.
	read_run : Str -> Run
	read_run = |printed| {
		var $observed = []
		var $failed = Err(None)
		var $skipped = Err(None)
		var $done = Bool.False
		var $current = Err(None)
		for line in printed.split_on("\n") {
			if line == "@done" {
				$done = Bool.True
			} else if line.starts_with("@") {
				$observed = close($observed, $current)
				$current = Err(None)
				words = line.drop_prefix("@").split_on(" ")
				match words {
					[k, "obs"] =>
						match U64.from_str(k) {
							Ok(step) => {
								$current = Ok({ step, lines: [] })
							}
							Err(_) => {}
						}
					[k, "skip", ..] =>
						match U64.from_str(k) {
							Ok(step) => {
								$skipped = Ok(step)
							}
							Err(_) => {}
						}
					[k, "fail", .. as rest] =>
						match U64.from_str(k) {
							Ok(step) => {
								$failed = Ok({ step, message: Str.join_with(rest, " "), lines: [] })
								$current = Err(Failure)
							}
							Err(_) => {}
						}
					_ => {}
				}
			} else if line.starts_with("|") {
				body = line.drop_prefix("|")
				match $current {
					Ok(open) => {
						$current = Ok({ ..open, lines: open.lines.append(body) })
					}
					Err(Failure) =>
						match $failed {
							Ok(f) => {
								$failed = Ok({ ..f, lines: f.lines.append(body) })
							}
							Err(_) => {}
						}
					Err(_) => {}
				}
			}
		}
		{ observed: close($observed, $current), failed: $failed, skipped: $skipped, done: $done }
	}

	## Every way the run differs from the spec, at the step it concerns.
	judge : Parsed, Run -> List(Problem)
	judge = |{ steps, .. }, run| {
		var $problems = []
		var $k = 0.U64
		var $mark = Err(NoMark)
		for step in steps {
			$k = $k + 1
			match run.failed {
				Ok(f) if f.step == $k => return $problems.append({ pos: step.pos, message: failure_message(f.message, f.lines) })
				_ => {}
			}
			match run.skipped {
				# The rest is not judged: this Mac cannot run it.
				Ok(at) if at == $k => return $problems
				_ => {}
			}
			seen = observation(run, $k)
			if step.op == MarkMetrics {
				$mark = seen.map_ok(counters_of).map_err(|_| NoMark)
			}
			match expectation(step.op, seen, $mark) {
				Ok({}) => {}
				Err(message) => {
					$problems = $problems.append({ pos: step.pos, message })
				}
			}
		}
		if !run.done and run.failed.is_err() {
			last = steps.last().map_ok(|s| s.pos) ?? { line: 1, column: 1 }
			$problems.append({ pos: last, message: "the app stopped before every step had run" })
		} else {
			$problems
		}
	}

	## The spec's source with each `expect-dump`'s tree replaced by the one
	## the run showed, laid out a node a line from its column, and each allocation
	## bound (`expect-allocations-at-most`, `expect-allocated-bytes-at-most`,
	## and `expect-metric-delta-at-most` of `allocations`, `reallocations` or
	## `allocated_bytes`) lowered to what the run saw when it saw less. A
	## bound is never raised: a run that saw more fails. Nothing else changes.
	update : Str, Parsed, Run -> Str
	update = |source, { steps, .. }, run| {
		bytes = source.to_utf8()
		var $edits = []
		var $k = 0.U64
		var $mark = Err(NoMark)
		for step in steps {
			$k = $k + 1
			seen = observation(run, $k)
			if step.op == MarkMetrics {
				$mark = seen.map_ok(counters_of).map_err(|_| NoMark)
			}
			match (step.op, seen) {
				(ExpectDump(tree), Ok(lines)) => {
					start = offset_of(bytes, tree.pos)
					$edits = $edits.append({ start, end: form_end(bytes, start), text: dump_literal(lines, tree.pos.column - 1) })
				}
				(op, Ok(lines)) =>
					match bound_of(op) {
						Ok({ name, most, pos }) => {
							(seen_value, _) = change(name, counters_of(lines), $mark)
							if seen_value >= 0 and seen_value < most {
								start = offset_of(bytes, pos)
								$edits = $edits.append({ start, end: number_end(bytes, start), text: seen_value.to_str() })
							}
						}
						Err(_) => {}
					}
				_ => {}
			}
		}
		var $out = []
		var $at = 0.U64
		for edit in $edits {
			$out = $out.concat(bytes.sublist({ start: $at, len: edit.start - $at })).concat(edit.text.to_utf8())
			$at = edit.end
		}
		Str.from_utf8_lossy($out.concat(bytes.drop_first($at)))
	}

	## The lowered steps with one more, a `metrics` observation after the
	## last, for `measure`.
	lower_measured : Parsed -> Str
	lower_measured = |parsed| Spec.lower(parsed).concat("${(parsed.steps.len() + 1).to_str()}\tmetrics\n")

	## What a run measured (`macos.roc test --metrics`): for each step that
	## expects a metric, every heap metric and each work metric that is not
	## zero, as changed since its mark; and, after the last step, the same
	## since the window mounted. Run it on `lower_measured`'s steps.
	measure : Parsed, Run -> List({ pos : Pos, text : Str })
	measure = |{ steps, .. }, run| {
		var $out = []
		var $k = 0.U64
		var $mark = Err(NoMark)
		shown = |lines, mark| {
			now = counters_of(lines)
			names = Spec.heap_metrics.concat(Spec.metric_names.map(|m| m.name))
			parts = names.keep_oks(
				|name| {
					(d, _) = change(name, now, mark)
					if (d != 0 or Spec.heap_metrics.contains(name)) Ok("${name} ${d.to_str()}") else Err(Zero)
				},
			)
			Str.join_with(parts, ", ")
		}
		for step in steps {
			$k = $k + 1
			seen = observation(run, $k)
			match seen {
				Ok(lines) if step.op == MarkMetrics => {
					$mark = Ok(counters_of(lines))
				}
				Ok(lines) if observes(step.op) and (bound_of(step.op).is_ok() or is_metric(step.op)) => {
					$out = $out.append({ pos: step.pos, text: shown(lines, $mark) })
				}
				_ => {}
			}
		}
		last = steps.last().map_ok(|s| s.pos) ?? { line: 1, column: 1 }
		match observation(run, $k + 1) {
			Ok(lines) => $out.append({ pos: last, text: "since the window mounted: ${shown(lines, Err(NoMark))}" })
			Err(_) => $out
		}
	}

	## How a step is written back, for messages: `(button "+")`.
	show_loc : Loc -> Str
	show_loc = |loc|
		match loc {
			[] => "nothing"
			[one] => show_part(one)
			[one, { kind: "nth#", text: k }] => "${show_part(one).drop_suffix(")")} ${k})"
			[first, .. as rest] => "(within ${show_part(first)} ${Spec.show_loc(rest)})"
		}

	## The worker-pool fields `expect-workers` may name.
	worker_fields : List(Str)
	worker_fields = ["limit", "live", "running", "queued", "started", "answered", "lost", "stopped", "timed-out", "dropped"]

	## The step names, for an unknown step's message.
	step_names : List(Str)
	step_names = ["click", "fill", "submit", "toggle", "select", "hover", "choose", "press", "files", "drop", "move", "leave", "sweep", "scroll", "phase", "stats", "window", "wait", "reload", "expect-dump", "expect-tree", "expect-visible", "expect-absent", "expect-text", "expect-checked", "expect-disabled", "expect-workers", "stub-http", "fail-http", "run-effect", "tick-interval", "fire-timer", "advance-time", "await-work", "expect-pending-effects", "expect-interval", "expect-request", "expect-cancelled", "mark-metrics", "expect-metric-delta", "expect-metric-delta-at-most", "expect-allocations-at-most", "expect-allocated-bytes-at-most", "expect-no-new-live-allocations", "frame", "frame-clock", "step-source", "repaint", "window-size", "screen-size", "renderer", "require-metal", "bench-surfaces", "expect-probe", "expect-surfaces", "render", "slide", "stall-analysis", "expect-audio-status", "expect-tone", "expect-eq", "expect-snapshot", "expect-history", "expect-sources", "require-av-timing", "mark-av-timing", "expect-av-offset", "expect-frame-pacing"]

	## The fields each report expectation may name: a drawing surface's
	## colour at a point, in percent; the surfaces shown and on the frame
	## clock, and the clock's time in milliseconds; and the playback
	## session's transport, EQ, newest measurement, kept measurements and
	## the `audio.*` sources a surface would read.
	report_fields : List({ step : Str, fields : List(Str) })
	report_fields = [
		{ step: "expect-probe", fields: ["r", "g", "b", "a", "tolerance"] },
		{ step: "expect-surfaces", fields: ["shown", "ticking", "time"] },
		{ step: "expect-audio-status", fields: ["state", "position", "duration", "track", "ended", "analysis"] },
		{ step: "expect-eq", fields: ["bypass", "preamp", "bands", "volume"] },
		{ step: "expect-snapshot", fields: ["present", "at", "rate", "rms", "peak", "finite", "loudest"] },
		{ step: "expect-history", fields: ["count", "bound", "first", "last", "current", "ordered", "waiting", "slots", "skipped"] },
		{ step: "expect-sources", fields: ["waveform", "left", "right", "bands", "level", "bass", "mids", "treble"] },
		{ step: "expect-av-offset", fields: ["mean-within", "p95-within", "max-within", "lead-at-most", "matched-at-least"] },
		{ step: "expect-frame-pacing", fields: ["dropped-at-most", "skipped-at-most", "p99-at-most", "gpu-p99-at-most", "frames-at-least"] },
	]

	## What each bound of the timing expectations reads from the host's
	## report (`av-timing`), and whether the value must be at least the
	## bound rather than at most: `mean-within` bounds the mean offset's
	## size, `p95-within` and `max-within` the offsets' sizes.
	timing_bounds : List({ field : Str, reads : Str, least : Bool, size : Bool })
	timing_bounds = [
		{ field: "mean-within", reads: "mean", least: Bool.False, size: Bool.True },
		{ field: "p95-within", reads: "p95", least: Bool.False, size: Bool.False },
		{ field: "max-within", reads: "max", least: Bool.False, size: Bool.False },
		{ field: "lead-at-most", reads: "lead", least: Bool.False, size: Bool.False },
		{ field: "matched-at-least", reads: "matched", least: Bool.True, size: Bool.False },
		{ field: "dropped-at-most", reads: "dropped", least: Bool.False, size: Bool.False },
		{ field: "skipped-at-most", reads: "skipped", least: Bool.False, size: Bool.False },
		{ field: "p99-at-most", reads: "frame-p99", least: Bool.False, size: Bool.False },
		{ field: "gpu-p99-at-most", reads: "gpu-p99", least: Bool.False, size: Bool.False },
		{ field: "frames-at-least", reads: "frames", least: Bool.True, size: Bool.False },
	]

	## The page heap's metrics, which the host counts while a spec runs:
	## calls of `roc_alloc`, `roc_realloc` and `roc_dealloc`, the net of
	## allocations over deallocations, and the bytes allocations and
	## reallocations asked for.
	heap_metrics : List(Str)
	heap_metrics = ["allocations", "reallocations", "deallocations", "live_allocations", "allocated_bytes"]

	## The metrics whose `-at-most` bounds `--update` ratchets down.
	ratcheted : List(Str)
	ratcheted = ["allocations", "reallocations", "allocated_bytes"]

	## The work metrics a spec may name, and the engine's work counters each
	## sums. Counter `k` is the `k`th of the work record the engine returns
	## with every turn (roc-signals design.md, Appendix B: `count:u32
	## (counter:u64)*`, cumulative over the window's engine): 1-18 count
	## commands by opcode, 19-31 engine work, 32-38 the effect counters, 40
	## onwards ports, properties, released registrations, transitions,
	## progress, startup and opportunities. This is roc-signals' own table
	## (`platform/Scm.roc`, `metric_names`), which its engine package does
	## not expose.
	metric_names : List({ name : Str, counters : List(U64) })
	metric_names = [
		{ name: "rows_created", counters: [1] },
		{ name: "rows_removed", counters: [22] },
		{ name: "rows_reused", counters: [23] },
		{ name: "rows_updated", counters: [24] },
		{ name: "rows_moved", counters: [4] },
		{ name: "create_element", counters: [8] },
		{ name: "set_text", counters: [2, 12] },
		{ name: "set_value", counters: [19] },
		{ name: "set_checked", counters: [20] },
		{ name: "bind_event", counters: [11] },
		{ name: "registrations_released", counters: [43] },
		{ name: "set_metadata", counters: [17] },
		{ name: "patches_emitted", counters: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 41, 42, 48] },
		{ name: "derived_calls_into_roc", counters: [21] },
		{ name: "scopes_created", counters: [25] },
		{ name: "scopes_disposed", counters: [26] },
		{ name: "dirty_source_roots", counters: [27] },
		{ name: "each_key_hashes", counters: [28] },
		{ name: "each_key_compares", counters: [29] },
		{ name: "turns", counters: [30] },
		{ name: "effects_issued", counters: [32] },
		{ name: "effects_delivered", counters: [33] },
		{ name: "effects_stale", counters: [34] },
		{ name: "effects_refused", counters: [35] },
		{ name: "effects_cancelled", counters: [36] },
		{ name: "effects_reparented", counters: [37] },
		{ name: "effects_skipped", counters: [38] },
		{ name: "effects_progress", counters: [47] },
		{ name: "view_transitions", counters: [45] },
		{ name: "startup", counters: [49] },
		{ name: "startup_ack", counters: [50] },
		{ name: "startup_complete", counters: [51] },
		{ name: "opportunity_commands", counters: [52] },
		{ name: "opportunity_requested", counters: [53] },
		{ name: "opportunity_cancelled", counters: [54] },
		{ name: "opportunity_delivered", counters: [55] },
		{ name: "opportunity_stale", counters: [56] },
	]

	## A metric's value in a work record's counters: the sum of its counters.
	metric : List(U64), Str -> Try(U64, [UnknownMetric])
	metric = |counters, name|
		match Spec.metric_names.find_first(|m| m.name == name) {
			Ok(m) => Ok(m.counters.fold(0, |sum, k| sum + (counters.get(k) ?? 0)))
			Err(_) => Err(UnknownMetric)
		}

	## A work record's counters, from its bytes: `count:u32 (counter:u64)*`,
	## little-endian, and what follows them ignored.
	work_counters : List(U8) -> List(U64)
	work_counters = |bytes| {
		count = le(bytes, 0, 4)
		var $out = []
		var $k = 0.U64
		while $k < count and 4 + 8 * ($k + 1) <= bytes.len() {
			$out = $out.append(le(bytes, 4 + 8 * $k, 8))
			$k = $k + 1
		}
		$out
	}

	## The fields `expect-request` may name.
	request_fields : List(Str)
	request_fields = ["method", "url", "body", "timeout"]

	## The locator kinds.
	locator_names : List(Str)
	locator_names = ["button", "checkbox", "text", "text-field", "text-area", "list-row", "hover-target", "slider", "surface", "within"]
}

# ------------------------------------------------------------------ reader

R : { bytes : List(U8), at : U64, line : U64, column : U64 }

read_one : Str -> Try(Spec.Sx, Spec.Problem)
read_one = |text| {
	r0 = skip_trivia({ bytes: text.to_utf8(), at: 0, line: 1, column: 1 })
	if r0.at >= r0.bytes.len() {
		return Err({ pos: here(r0), message: "the file holds no (test …) form" })
	}
	(sx, r1) = read_expr(r0)?
	r2 = skip_trivia(r1)
	if r2.at < r2.bytes.len() {
		return Err({ pos: here(r2), message: "a spec file holds exactly one (test …) form" })
	}
	Ok(sx)
}

here : R -> Spec.Pos
here = |r| { line: r.line, column: r.column }

peek : R -> Try(U8, [End])
peek = |r| r.bytes.get(r.at).map_err(|_| End)

advance : R -> R
advance = |r|
	match r.bytes.get(r.at) {
		Ok('\n') => { ..r, at: r.at + 1, line: r.line + 1, column: 1 }
		Ok(b) if b >= 0x80 and b < 0xC0 => { ..r, at: r.at + 1 }
		_ => { ..r, at: r.at + 1, column: r.column + 1 }
	}

advance_by : R, U64 -> R
advance_by = |r, n| {
	var $r = r
	var $i = 0.U64
	while $i < n {
		$r = advance($r)
		$i = $i + 1
	}
	$r
}

skip_trivia : R -> R
skip_trivia = |r0| {
	var $r = r0
	var $comment = Bool.False
	while $r.at < $r.bytes.len() {
		b = peek($r) ?? 0
		if $comment {
			if b == '\n' {
				$comment = Bool.False
			}
			$r = advance($r)
		} else if b == ' ' or b == '\t' or b == '\r' or b == '\n' {
			$r = advance($r)
		} else if b == ';' {
			$comment = Bool.True
			$r = advance($r)
		} else {
			return $r
		}
	}
	$r
}

read_expr : R -> Try((Spec.Sx, R), Spec.Problem)
read_expr = |r0| {
	r = skip_trivia(r0)
	match peek(r) {
		Err(End) => Err({ pos: here(r), message: "unexpected end of file" })
		Ok('(') => read_list(r)
		Ok(')') => Err({ pos: here(r), message: "unexpected closing parenthesis" })
		Ok('"') => read_text(r)
		Ok(_) => read_atom(r)
	}
}

read_list : R -> Try((Spec.Sx, R), Spec.Problem)
read_list = |r0| {
	start = here(r0)
	var $r = skip_trivia(advance(r0))
	var $items = []
	while peek($r) != Ok(')') {
		if $r.at >= $r.bytes.len() {
			return Err({ pos: start, message: "this list is never closed" })
		}
		(item, next) = read_expr($r)?
		$items = $items.append(item)
		$r = skip_trivia(next)
	}
	Ok((List($items, start), advance($r)))
}

read_text : R -> Try((Spec.Sx, R), Spec.Problem)
read_text = |r0| {
	start = here(r0)
	var $r = advance(r0)
	var $out = []
	while $r.at < $r.bytes.len() {
		b = peek($r) ?? 0
		if b == '"' {
			s = Str.from_utf8($out) ? |_| { pos: start, message: "this string is not UTF-8" }
			return Ok((Text(s, start), advance($r)))
		} else if b == '\n' or b == '\r' {
			return Err({ pos: start, message: "a string cannot hold a line break; write \\n" })
		} else if b == '\\' {
			at = here($r)
			$r = advance($r)
			decoded = match peek($r) {
				Ok('n') => '\n'
				Ok('t') => '\t'
				Ok('"') => '"'
				Ok('\\') => '\\'
				_ => return Err({ pos: at, message: "unknown escape; a string knows \\n, \\t, \\\" and \\\\" })
			}
			$out = $out.append(decoded)
			$r = advance($r)
		} else {
			$out = $out.append(b)
			$r = advance($r)
		}
	}
	Err({ pos: start, message: "this string is never closed" })
}

is_delimiter : U8 -> Bool
is_delimiter = |b| b == ' ' or b == '\t' or b == '\r' or b == '\n' or b == '(' or b == ')' or b == '"' or b == ';'

read_atom : R -> Try((Spec.Sx, R), Spec.Problem)
read_atom = |r0| {
	start = here(r0)
	var $r = r0
	while $r.at < $r.bytes.len() and !is_delimiter(peek($r) ?? ' ') {
		$r = advance($r)
	}
	text = Str.from_utf8($r.bytes.sublist({ start: r0.at, len: $r.at - r0.at })) ? |_| { pos: start, message: "this word is not UTF-8" }
	atom = match I64.from_str(text) {
		Ok(n) => Int(n, start)
		Err(_) => Sym(text, start)
	}
	Ok((atom, $r))
}

pos_of : Spec.Sx -> Spec.Pos
pos_of = |sx|
	match sx {
		Sym(_, p) => p
		Text(_, p) => p
		Int(_, p) => p
		List(_, p) => p
	}

show : Spec.Sx -> Str
show = |sx|
	match sx {
		Sym(s, _) => s
		Text(s, _) => Str.inspect(s)
		Int(n, _) => n.to_str()
		List(_, _) => "a list"
	}

# ------------------------------------------------------------------ grammar

setup_form : Spec.Setup, Spec.Sx -> Try(Spec.Setup, Spec.Problem)
setup_form = |setup, form|
	match form {
		List([Sym("worker-pool", _), Int(n, _)], _) if n >= 1 and n <= 64 => Ok({ ..setup, pool: n.to_u64_wrap() })
		List([Sym("worker-pool", p), ..], _) => Err({ pos: p, message: "(worker-pool N) takes a count from 1 to 64" })
		List([Sym("initial-time", _), Int(ms, _)], _) => Ok({ ..setup, time: ms })
		List([Sym("initial-time", p), ..], _) => Err({ pos: p, message: "(initial-time MS) takes milliseconds since 1970" })
		List([Sym("local-storage", _), Text(key, _), Text(value, _)], _) => Ok({ ..setup, storage: setup.storage.append((key, value)) })
		List([Sym("local-storage", p), ..], _) => Err({ pos: p, message: "(local-storage \"key\" \"value\") seeds one pair" })
		List([Sym("live-effects", _)], _) => Ok({ ..setup, live: Bool.True })
		List([Sym("live-effects", p), ..], _) => Err({ pos: p, message: "(live-effects) takes nothing" })
		List([Sym("audio-clock", _), Sym("manual", _)], _) => Ok({ ..setup, audio_manual: Bool.True })
		List([Sym("audio-clock", p), ..], _) => Err({ pos: p, message: "(audio-clock manual) renders the playback session offline, only when a (render MS) step says so" })
		List([head, ..], _) => Err({ pos: pos_of(head), message: "unknown setup form ${show(head)}; the setup forms are worker-pool, initial-time, local-storage, live-effects and audio-clock" })
		other => Err({ pos: pos_of(other), message: "a setup form is a list, such as (worker-pool 1)" })
	}

step_form : Spec.Sx -> Try(Spec.Step, Spec.Problem)
step_form = |form| {
	(parts, pos) = match form {
		List(xs, p) => (xs, p)
		other => return Err({ pos: pos_of(other), message: "a step is a list, such as (click (button \"+\"))" })
	}
	(head, args) = match parts {
		[Sym(name, _), .. as rest] => (name, rest)
		[other, ..] => return Err({ pos: pos_of(other), message: "a step starts with its name" })
		[] => return Err({ pos, message: "an empty step" })
	}
	usage = |shape| Err({ pos, message: "${head} is written ${shape}" })
	op = match (head, args) {
		("click", [l]) => Click(loc(l)?)
		("click", _) => return usage("(click LOCATOR)")
		("fill", [l, Text(s, _)]) => Fill(loc(l)?, s)
		("fill", _) => return usage("(fill LOCATOR \"text\")")
		("submit", [l]) => Submit(loc(l)?)
		("submit", _) => return usage("(submit LOCATOR)")
		("toggle", [l]) => Toggle(loc(l)?)
		("toggle", _) => return usage("(toggle LOCATOR)")
		("select", [l]) => Select(loc(l)?)
		("select", _) => return usage("(select LOCATOR)")
		("hover", [l]) => Hover(loc(l)?)
		("hover", _) => return usage("(hover LOCATOR)")
		("choose", [Text(s, _)]) => Choose(s)
		("choose", _) => return usage("(choose \"choice\")")
		("press", [Text(key, _)]) => Press({ key, heard: Any })
		("press", [Text(key, _), Sym(":heard", _), Sym(b, bp)]) => Press({ key, heard: Heard(boolean(b, bp)?) })
		("press", _) => return usage("(press \"cmd+n\"), optionally with :heard true or false")
		("files", [_, ..]) => Files(texts(args, "(files \"path\" …)")?)
		("files", _) => return usage("(files \"path\" …)")
		("drop", [_, ..]) => Drop(texts(args, "(drop \"path\" …)")?)
		("drop", _) => return usage("(drop \"path\" …)")
		("move", [Int(x, _), Int(y, _)]) => Move(x, y)
		("move", _) => return usage("(move X Y), points from the window's top-left corner")
		("leave", []) => Leave
		("leave", _) => return usage("(leave)")
		("sweep", [_, _, _, _, _, _]) => Sweep(ints(args, "(sweep X0 Y0 X1 Y1 MOVES MS)")?)
		("sweep", _) => return usage("(sweep X0 Y0 X1 Y1 MOVES MS)")
		("scroll", [Int(k, _)]) if k >= 0 => Scroll(k)
		("scroll", _) => return usage("(scroll ROW), a row of the first list from 0")
		("phase", [Text(s, _)]) => Phase(s)
		("phase", _) => return usage("(phase \"name\")")
		("stats", []) => Stats
		("stats", _) => return usage("(stats)")
		("window", []) => Window
		("window", _) => return usage("(window)")
		("wait", [Int(ms, _)]) if ms >= 0 => Wait(ms)
		("wait", _) => return usage("(wait MS)")
		("reload", []) => Reload
		("reload", _) => return usage("(reload)")
		("expect-dump", [tree]) => ExpectDump(tree_of(tree, "window")?)
		("expect-dump", _) => return usage("(expect-dump (window …)), or (expect-dump _) for `test --update` to fill in")
		("expect-tree", [l, tree]) => ExpectTree(loc(l)?, tree_of(tree, "")?)
		("expect-tree", _) => return usage("(expect-tree LOCATOR (kind …))")
		("expect-visible", [l]) => ExpectVisible(loc(l)?)
		("expect-visible", _) => return usage("(expect-visible LOCATOR)")
		("expect-absent", [l]) => ExpectAbsent(loc(l)?)
		("expect-absent", _) => return usage("(expect-absent LOCATOR)")
		("expect-text", [l, Text(s, _)]) => ExpectText(loc(l)?, s)
		("expect-text", _) => return usage("(expect-text LOCATOR \"text\")")
		("expect-checked", [l, Sym(b, bp)]) => ExpectChecked(loc(l)?, boolean(b, bp)?)
		("expect-checked", _) => return usage("(expect-checked LOCATOR true)")
		("expect-disabled", [l, Sym(b, bp)]) => ExpectDisabled(loc(l)?, boolean(b, bp)?)
		("expect-disabled", _) => return usage("(expect-disabled LOCATOR true)")
		("expect-workers", [_, ..]) => ExpectWorkers(worker_counts(args)?)
		("expect-workers", _) => return usage("(expect-workers :answered 8 …)")
		("stub-http", [Text(_, _), .. as rest]) => StubHttp(stub(rest, { url: "", status: 200, body: "", headers: [] })?)
		("stub-http", _) => return usage("(stub-http \"label\" :status 200 :body \"…\"), optionally with :url \"…\" and :headers ((\"name\" \"value\") …)")
		("fail-http", [Text(_, _), Sym(":kind", _), Sym(kind, _)]) if kind == "timeout" => FailHttp({ kind, detail: "" })
		("fail-http", [Text(_, _), Sym(":kind", _), Sym(kind, _), Sym(":detail", _), Text(detail, _)]) if kind == "network" => FailHttp({ kind, detail })
		("fail-http", _) => return usage("(fail-http \"label\" :kind network :detail \"message\") or (fail-http \"label\" :kind timeout)")
		("run-effect", [Int(n, _)]) if n >= 1 => RunEffect(n)
		("run-effect", _) => return usage("(run-effect N), N counting the effects the app issued from 1")
		("tick-interval", [Int(ms, _)]) if ms >= 1 => TickInterval(ms)
		("tick-interval", _) => return usage("(tick-interval MS), an interval's period")
		("fire-timer", [Int(ms, _)]) if ms >= 0 => FireTimer(ms)
		("fire-timer", _) => return usage("(fire-timer MS), a timer's delay")
		("advance-time", [Int(ms, _)]) if ms >= 0 => AdvanceTime(ms)
		("advance-time", _) => return usage("(advance-time MS)")
		("await-work", []) => AwaitWork
		("await-work", _) => return usage("(await-work)")
		("expect-pending-effects", [Int(n, _)]) if n >= 0 => ExpectPendingEffects(n)
		("expect-pending-effects", _) => return usage("(expect-pending-effects N)")
		("expect-interval", [Int(ms, _), Int(n, _)]) if ms >= 1 and n >= 0 => ExpectInterval(ms, n)
		("expect-interval", _) => return usage("(expect-interval MS N), N live intervals of that period")
		("expect-request", [Int(n, _), .. as rest]) if n >= 1 => ExpectRequest(n, request_pairs(rest)?)
		("expect-request", _) => return usage("(expect-request N :method \"GET\" :url \"…\"), with any of :method, :url, :body and :timeout")
		("expect-cancelled", [Int(n, _)]) if n >= 1 => ExpectCancelled(n)
		("expect-cancelled", _) => return usage("(expect-cancelled N)")
		("mark-metrics", []) => MarkMetrics
		("mark-metrics", _) => return usage("(mark-metrics)")
		("expect-metric-delta", [Sym(name, np), Int(n, _)]) if n >= 0 => ExpectMetricDelta(metric_name(name, np)?, n)
		("expect-metric-delta", _) => return usage("(expect-metric-delta METRIC N)")
		("expect-metric-delta-at-most", [Sym(name, np), Int(n, bp)]) if n >= 0 => ExpectMetricDeltaAtMost(metric_name(name, np)?, n, bp)
		("expect-metric-delta-at-most", _) => return usage("(expect-metric-delta-at-most METRIC N)")
		("expect-allocations-at-most", [Int(n, bp)]) if n >= 0 => ExpectAllocationsAtMost(n, bp)
		("expect-allocations-at-most", _) => return usage("(expect-allocations-at-most N)")
		("expect-allocated-bytes-at-most", [Int(n, bp)]) if n >= 0 => ExpectAllocatedBytesAtMost(n, bp)
		("expect-allocated-bytes-at-most", _) => return usage("(expect-allocated-bytes-at-most N)")
		("expect-no-new-live-allocations", []) => ExpectNoNewLiveAllocations
		("expect-no-new-live-allocations", _) => return usage("(expect-no-new-live-allocations)")
		("frame", []) => Frame(-1)
		("frame", [Int(ms, _)]) if ms >= 0 => Frame(ms)
		("frame", _) => return usage("(frame) or (frame MS): the frame clock on by MS (a 60 Hz refresh if none), and one frame for each display-paced surface")
		("frame-clock", [Sym(c, _)]) if c == "manual" or c == "display" => FrameClock(c)
		("frame-clock", _) => return usage("(frame-clock manual) or (frame-clock display)")
		("step-source", [Text(name, _)]) => StepSource(name, 1)
		("step-source", [Text(name, _), Int(n, _)]) if n >= 1 => StepSource(name, n)
		("step-source", _) => return usage("(step-source \"synthetic.wave\") or (step-source \"synthetic.wave\" N)")
		("repaint", []) => Repaint
		("repaint", _) => return usage("(repaint)")
		("window-size", [Int(w, _), Int(h, _)]) if w >= 1 and h >= 1 => WindowSize(w, h)
		("window-size", _) => return usage("(window-size W H), the window's content size in points")
		("screen-size", [Int(w, _), Int(h, _)]) if w >= 1 and h >= 1 => ScreenSize(w, h)
		("screen-size", _) => return usage("(screen-size W H), the most content the window has room for, in points, as on a screen that size")
		("renderer", [Sym(r, _)]) if r == "metal" or r == "cg" or r == "auto" => Renderer(r)
		("renderer", _) => return usage("(renderer metal), (renderer cg) or (renderer auto)")
		("require-metal", []) => RequireMetal
		("require-metal", _) => return usage("(require-metal), which ends the spec, passing, on a Mac without a Metal device")
		("bench-surfaces", [Int(n, _)]) if n >= 1 => BenchSurfaces(n)
		("bench-surfaces", _) => return usage("(bench-surfaces N), N frames a size with each renderer, reported and never judged")
		("expect-probe", [l, Int(x, _), Int(y, _), .. as rest]) if x >= 0 and y >= 0 => {
			want = report_pairs(head, rest)?
			if want.any(|w| !(I64.from_str(w.value).map_ok(|n| n >= 0 and n <= 100) ?? Bool.False)) {
				return usage("(expect-probe (surface \"label\") X Y :r 100 :g 0 :b 0 :a 100 :tolerance 2), each value a whole percentage from 0 to 100")
			}
			ExpectProbe(loc(l)?, x, y, want)
		}
		("expect-probe", _) => return usage("(expect-probe (surface \"label\") X Y :r 100 :g 0 :b 0 :a 100), X and Y in points from its top-left corner")
		("expect-surfaces", [_, ..]) => ExpectSurfaces(report_pairs(head, args)?)
		("expect-surfaces", _) => return usage("(expect-surfaces :shown 1 :ticking 1 :time \"200.0\")")
		("render", [Int(ms, _)]) if ms >= 1 => Render(ms)
		("render", _) => return usage("(render MS), with (audio-clock manual)")
		("slide", [l, Int(v, _)]) => Slide(loc(l)?, v)
		("slide", _) => return usage("(slide (slider K) VALUE), as a drag ending there would leave it")
		("stall-analysis", [Sym(b, bp)]) => StallAnalysis(boolean(b, bp)?)
		("stall-analysis", _) => return usage("(stall-analysis true) or (stall-analysis false)")
		("expect-audio-status", [_, ..]) => ExpectAudioStatus(report_pairs(head, args)?)
		("expect-audio-status", _) => return usage("(expect-audio-status :state \"Playing\" :position 200 …)")
		("expect-tone", [Int(hz, _), Int(db, _)]) if hz >= 1 => ExpectTone(hz, db.to_str())
		("expect-tone", [Int(hz, _), Sym("silent", _)]) if hz >= 1 => ExpectTone(hz, "silent")
		("expect-tone", _) => return usage("(expect-tone HZ DBFS) or (expect-tone HZ silent), the HZ component of the last render's output")
		("expect-eq", [_, ..]) => ExpectEq(report_pairs(head, args)?)
		("expect-eq", _) => return usage("(expect-eq :bypass false :preamp 0 :bands \"0 0 0 0 0 0 0 0 0 0\" :volume 100)")
		("expect-snapshot", [_, ..]) => ExpectSnapshot(report_pairs(head, args)?)
		("expect-snapshot", _) => return usage("(expect-snapshot :at \"267.0\" :rate 44100 :rms -20 …)")
		("expect-history", [_, ..]) => ExpectHistory(report_pairs(head, args)?)
		("expect-history", _) => return usage("(expect-history :count 5 :current true …)")
		("expect-sources", [_, ..]) => ExpectSources(report_pairs(head, args)?)
		("expect-sources", _) => return usage("(expect-sources :level \"0.67\" …)")
		("require-av-timing", []) => RequireAvTiming
		("require-av-timing", _) => return usage("(require-av-timing), which ends the spec, passing, unless ROC_AV_TIMING=1 asks for real-clock timing")
		("mark-av-timing", []) => MarkAvTiming
		("mark-av-timing", _) => return usage("(mark-av-timing), which starts the timing report again from now")
		("expect-av-offset", [_, ..]) => ExpectAvOffset(report_pairs(head, args)?)
		("expect-av-offset", _) => return usage("(expect-av-offset :mean-within 30 :p95-within 45 :lead-at-most 15), in milliseconds")
		("expect-frame-pacing", [_, ..]) => ExpectFramePacing(report_pairs(head, args)?)
		("expect-frame-pacing", _) => return usage("(expect-frame-pacing :dropped-at-most 3 :p99-at-most 25)")
		_ => return Err({ pos, message: "unknown step ${head}; the steps are ${Str.join_with(Spec.step_names, ", ")}" })
	}
	Ok({ pos, op })
}

boolean : Str, Spec.Pos -> Try(Bool, Spec.Problem)
boolean = |word, pos|
	match word {
		"true" => Ok(Bool.True)
		"false" => Ok(Bool.False)
		_ => Err({ pos, message: "expected true or false, not ${word}" })
	}

texts : List(Spec.Sx), Str -> Try(List(Str), Spec.Problem)
texts = |args, shape| {
	var $out = []
	for arg in args {
		match arg {
			Text(s, _) => {
				$out = $out.append(s)
			}
			other => return Err({ pos: pos_of(other), message: "expected a string here: ${shape}" })
		}
	}
	Ok($out)
}

ints : List(Spec.Sx), Str -> Try(List(I64), Spec.Problem)
ints = |args, shape| {
	var $out = []
	for arg in args {
		match arg {
			Int(n, _) => {
				$out = $out.append(n)
			}
			other => return Err({ pos: pos_of(other), message: "expected a whole number here: ${shape}" })
		}
	}
	Ok($out)
}

worker_counts : List(Spec.Sx) -> Try(List({ field : Str, count : I64 }), Spec.Problem)
worker_counts = |args|
	match args {
		[] => Ok([])
		[Sym(key, kp), Int(n, _), .. as rest] if key.starts_with(":") => {
			field = key.drop_prefix(":")
			if !Spec.worker_fields.contains(field) {
				return Err({ pos: kp, message: "unknown worker count ${key}; they are ${Str.join_with(Spec.worker_fields.map(|f| ":${f}"), ", ")}" })
			}
			Ok([{ field, count: n }].concat(worker_counts(rest)?))
		}
		[other, ..] => Err({ pos: pos_of(other), message: "expect-workers takes :name COUNT pairs, such as :answered 8" })
	}

metric_name : Str, Spec.Pos -> Try(Str, Spec.Problem)
metric_name = |name, pos|
	if Spec.metric_names.any(|m| m.name == name) or Spec.heap_metrics.contains(name) {
		Ok(name)
	} else {
		Err({ pos, message: "unknown metric ${name}; the metrics are ${Str.join_with(Spec.heap_metrics.concat(Spec.metric_names.map(|m| m.name)), ", ")}" })
	}

## The little-endian number of `size` bytes at `at`; 0 past the end.
le : List(U8), U64, U64 -> U64
le = |bytes, at, size| bytes.drop_first(at).take_first(size).fold({ n: 0, shift: 0 }, |acc, b| { n: acc.n + b.to_u64().shl_wrap(acc.shift), shift: acc.shift + 8 }).n

## A staged HTTP answer's keywords.
stub : List(Spec.Sx), { url : Str, status : I64, body : Str, headers : List((Str, Str)) } -> Try({ url : Str, status : I64, body : Str, headers : List((Str, Str)) }, Spec.Problem)
stub = |args, acc|
	match args {
		[] => Ok(acc)
		[Sym(":url", _), Text(url, _), .. as rest] => stub(rest, { ..acc, url })
		[Sym(":status", _), Int(status, p), .. as rest] =>
			if (status >= 100 and status <= 999) stub(rest, { ..acc, status }) else Err({ pos: p, message: "a status is from 100 to 999" })
		[Sym(":body", _), Text(body, _), .. as rest] => stub(rest, { ..acc, body })
		[Sym(":headers", _), List(pairs, _), .. as rest] => {
			var $headers = []
			for pair in pairs {
				match pair {
					List([Text(name, _), Text(value, _)], _) => {
						$headers = $headers.append((name, value))
					}
					other => return Err({ pos: pos_of(other), message: "a header is (\"name\" \"value\")" })
				}
			}
			stub(rest, { ..acc, headers: $headers })
		}
		[other, ..] => Err({ pos: pos_of(other), message: "stub-http takes :url, :status, :body and :headers, each followed by its value" })
	}

request_pairs : List(Spec.Sx) -> Try(List({ field : Str, value : Str }), Spec.Problem)
request_pairs = |args|
	match args {
		[] => Ok([])
		[Sym(key, kp), value, .. as rest] if key.starts_with(":") => {
			field = key.drop_prefix(":")
			if !Spec.request_fields.contains(field) {
				return Err({ pos: kp, message: "unknown request field ${key}; they are ${Str.join_with(Spec.request_fields.map(|f| ":${f}"), ", ")}" })
			}
			text = match value {
				Text(t, _) => t
				Int(n, _) => n.to_str()
				other => return Err({ pos: pos_of(other), message: "a request field's value is a string or a number" })
			}
			Ok([{ field, value: text }].concat(request_pairs(rest)?))
		}
		[other, ..] => Err({ pos: pos_of(other), message: "expect-request takes :name value pairs, such as :method \"GET\"" })
	}

## A report expectation's `:name value` pairs, each name one its step
## knows (`Spec.report_fields`), each value text: a string as it is, a
## number in decimal, a word (`true`, `silent`) as written.
report_pairs : Str, List(Spec.Sx) -> Try(List(Spec.Field), Spec.Problem)
report_pairs = |step, args| {
	known = Spec.report_fields.find_first(|r| r.step == step).map_ok(|r| r.fields) ?? []
	match args {
		[] => Ok([])
		[Sym(key, kp), value, .. as rest] if key.starts_with(":") => {
			field = key.drop_prefix(":")
			if !known.contains(field) {
				return Err({ pos: kp, message: "${step} has no field ${key}; its fields are ${Str.join_with(known.map(|f| ":${f}"), ", ")}" })
			}
			text = match value {
				Text(t, _) => t
				Int(n, _) => n.to_str()
				Sym(word, _) if !word.starts_with(":") => word
				other => return Err({ pos: pos_of(other), message: "${key} takes a value: a string, a number or a word such as true" })
			}
			Ok([{ field, value: text }].concat(report_pairs(step, rest)?))
		}
		[other, ..] => Err({ pos: pos_of(other), message: "${step} takes :name value pairs, such as ${Str.join_with(known.take_first(1).map(|f| ":${f}"), "")} …" })
	}
}

loc : Spec.Sx -> Try(Spec.Loc, Spec.Problem)
loc = |sx|
	match sx {
		List([Sym("within", _), outer, inner], _) => Ok(loc(outer)?.concat(loc(inner)?))
		List([Sym("within", p), ..], _) => Err({ pos: p, message: "within is written (within LOCATOR LOCATOR)" })
		List([Sym(kind, _), Text(text, _)], _) if ["button", "checkbox", "text", "text-field", "text-area", "list-row"].contains(kind) => Ok([{ kind, text }])
		List([Sym(kind, _)], _) if ["text-field", "text-area"].contains(kind) => Ok([{ kind, text: "" }])
		List([Sym(kind, _), Int(n, p)], _) if kind == "list-row" or kind == "hover-target" or kind == "slider" =>
			if (n >= 1) Ok([{ kind: "${kind}#", text: n.to_str() }]) else Err({ pos: p, message: "rows, hover targets and sliders count from 1" })
		List([Sym(kind, _), Text(text, _), Int(n, p)], _) if ["button", "checkbox", "text"].contains(kind) =>
			if (n >= 1) Ok([{ kind, text }, { kind: "nth#", text: n.to_str() }]) else Err({ pos: p, message: "the K-th of several counts from 1" })
		List([Sym("surface", _), Text(text, _)], _) => Ok([{ kind: "surface", text }])
		List([Sym(kind, p), ..], _) if Spec.locator_names.contains(kind) => Err({ pos: p, message: "${kind} is written ${locator_shape(kind)}" })
		List([head, ..], _) => Err({ pos: pos_of(head), message: "unknown locator ${show(head)}; the locators are ${Str.join_with(Spec.locator_names, ", ")}" })
		other => Err({ pos: pos_of(other), message: "expected a locator, such as (button \"Save\"), not ${show(other)}" })
	}

locator_shape : Str -> Str
locator_shape = |kind|
	match kind {
		"text-field" => "(text-field) or (text-field \"placeholder\")"
		"text-area" => "(text-area) or (text-area \"placeholder\")"
		"list-row" => "(list-row \"text in the row\") or (list-row K)"
		"hover-target" => "(hover-target K), the K-th element that listens for hover"
		"slider" => "(slider K), the K-th slider in the window's order"
		"surface" => "(surface \"label\"), a drawing surface by its label"
		_ => "(${kind} \"text\")"
	}

show_part : { kind : Str, text : Str } -> Str
show_part = |{ kind, text }|
	if kind.ends_with("#") {
		"(${kind.drop_suffix("#")} ${text})"
	} else if text.is_empty() {
		"(${kind})"
	} else {
		"(${kind} ${Str.inspect(text)})"
	}

# ------------------------------------------------------------------ lowering

lowered : Spec.Op -> List(Str)
lowered = |op|
	match op {
		Click(l) => ["click"].concat(loc_fields(l))
		Fill(l, s) => ["fill"].concat(loc_fields(l)).append(s)
		Submit(l) => ["submit"].concat(loc_fields(l))
		Toggle(l) => ["toggle"].concat(loc_fields(l))
		Select(l) => ["select"].concat(loc_fields(l))
		Hover(l) => ["hover"].concat(loc_fields(l))
		Choose(s) => ["choose", s]
		Press({ key, heard }) => ["press", key, if (heard == Any) "" else "observe"]
		Files(paths) => ["files"].concat(paths)
		Drop(paths) => ["drop"].concat(paths)
		Move(x, y) => ["move", x.to_str(), y.to_str()]
		Leave => ["leave"]
		Sweep(values) => ["sweep"].concat(values.map(|v| v.to_str()))
		Scroll(k) => ["scroll", k.to_str()]
		Phase(s) => ["phase", s]
		Stats => ["stats"]
		Window => ["window"]
		Wait(ms) => ["wait", ms.to_str()]
		Reload => ["reload"]
		ExpectDump(_) => ["dump"]
		ExpectTree(l, _) => ["tree"].concat(loc_fields(l))
		ExpectVisible(l) => ["find"].concat(loc_fields(l))
		ExpectAbsent(l) => ["find"].concat(loc_fields(l))
		ExpectText(l, _) => ["find"].concat(loc_fields(l))
		ExpectChecked(l, _) => ["find"].concat(loc_fields(l))
		ExpectDisabled(l, _) => ["find"].concat(loc_fields(l))
		ExpectWorkers(_) => ["workers"]
		StubHttp({ url, status, body, headers }) => ["stub-http", url, status.to_str(), body, headers.len().to_str()].concat(headers.join_map(|(n, v)| [n, v]))
		FailHttp({ kind, detail }) => ["fail-http", kind, detail]
		RunEffect(n) => ["run-effect", n.to_str()]
		TickInterval(ms) => ["tick-interval", ms.to_str()]
		FireTimer(ms) => ["fire-timer", ms.to_str()]
		AdvanceTime(ms) => ["advance-time", ms.to_str()]
		AwaitWork => ["await-work"]
		ExpectPendingEffects(_) => ["effects"]
		ExpectInterval(_, _) => ["effects"]
		ExpectRequest(_, _) => ["effects"]
		ExpectCancelled(_) => ["effects"]
		MarkMetrics => ["metrics"]
		ExpectMetricDelta(_, _) => ["metrics"]
		ExpectMetricDeltaAtMost(_, _, _) => ["metrics"]
		ExpectAllocationsAtMost(_, _) => ["metrics"]
		ExpectAllocatedBytesAtMost(_, _) => ["metrics"]
		ExpectNoNewLiveAllocations => ["metrics"]
		Frame(ms) => ["frame", if (ms < 0) "" else ms.to_str()]
		FrameClock(c) => ["frame-clock", c]
		StepSource(name, n) => ["step-source", name, n.to_str()]
		Repaint => ["repaint"]
		WindowSize(w, h) => ["window-size", w.to_str(), h.to_str()]
		ScreenSize(w, h) => ["screen-size", w.to_str(), h.to_str()]
		Renderer(r) => ["renderer", r]
		RequireMetal => ["require-metal"]
		BenchSurfaces(n) => ["bench-surfaces", n.to_str()]
		ExpectProbe(l, x, y, _) => ["probe"].concat(loc_fields(l)).concat([x.to_str(), y.to_str()])
		ExpectSurfaces(_) => ["surfaces"]
		Render(ms) => ["render", ms.to_str()]
		Slide(l, v) => ["slide"].concat(loc_fields(l)).append(v.to_str())
		StallAnalysis(b) => ["stall-analysis", if (b) "true" else "false"]
		ExpectAudioStatus(_) => ["audio-status"]
		ExpectTone(hz, _) => ["tone", hz.to_str()]
		ExpectEq(_) => ["eq"]
		ExpectSnapshot(_) => ["snapshot"]
		ExpectHistory(_) => ["history"]
		ExpectSources(_) => ["sources"]
		RequireAvTiming => ["require-av-timing"]
		MarkAvTiming => ["mark-av-timing"]
		ExpectAvOffset(_) => ["av-timing"]
		ExpectFramePacing(_) => ["av-timing"]
	}

loc_fields : Spec.Loc -> List(Str)
loc_fields = |l| [l.len().to_str()].concat(l.join_map(|{ kind, text }| [kind, text]))

escape : Str -> Str
escape = |s| s.replace_each("\\", "\\\\").replace_each("\t", "\\t").replace_each("\n", "\\n")

unescape : Str -> Str
unescape = |s| {
	bytes = s.to_utf8()
	var $out = []
	var $i = 0.U64
	while $i < bytes.len() {
		b = bytes.get($i) ?? 0
		if b == '\\' {
			next = bytes.get($i + 1) ?? '\\'
			$out = $out.append(if (next == 'n') '\n' else if (next == 't') '\t' else next)
			$i = $i + 2
		} else {
			$out = $out.append(b)
			$i = $i + 1
		}
	}
	Str.from_utf8_lossy($out)
}

# ------------------------------------------------------------------ judging

close : List({ step : U64, lines : List(Str) }), Try({ step : U64, lines : List(Str) }, [None, Failure]) -> List({ step : U64, lines : List(Str) })
close = |observed, current|
	match current {
		Ok(open) => observed.append(open)
		Err(_) => observed
	}

observation : Spec.Run, U64 -> Try(List(Str), [Missing])
observation = |run, k| run.observed.find_first(|o| o.step == k).map_ok(|o| o.lines).map_err(|_| Missing)

## A found thing's properties, from `key value` lines: `count`, `text`,
## `checked`, `disabled`, and a `candidate` line per thing of the kind
## looked for when the count was not one.
Found : { count : U64, text : Str, checked : Str, disabled : Str, candidates : List(Str) }

found : List(Str) -> Found
found = |lines|
	lines.fold(
		{ count: 0, text: "", checked: "", disabled: "", candidates: [] },
		|acc, line| {
			(key, value) = match line.split_on(" ") {
				[k, .. as rest] => (k, unescape(Str.join_with(rest, " ")))
				[] => ("", "")
			}
			match key {
				"count" => { ..acc, count: U64.from_str(value) ?? 0 }
				"text" => { ..acc, text: value }
				"checked" => { ..acc, checked: value }
				"disabled" => { ..acc, disabled: value }
				"candidate" => { ..acc, candidates: acc.candidates.append(value) }
				_ => acc
			}
		},
	)

## Whether a step expects something, and so needs the host's observation.
observes : Spec.Op -> Bool
observes = |op|
	match op {
		ExpectDump(_) | ExpectTree(_, _) | ExpectVisible(_) | ExpectAbsent(_) | ExpectText(_, _) | ExpectChecked(_, _) | ExpectDisabled(_, _) | ExpectWorkers(_) => Bool.True
		ExpectPendingEffects(_) | ExpectInterval(_, _) | ExpectRequest(_, _) | ExpectCancelled(_) => Bool.True
		ExpectMetricDelta(_, _) | ExpectMetricDeltaAtMost(_, _, _) | ExpectAllocationsAtMost(_, _) | ExpectAllocatedBytesAtMost(_, _) | ExpectNoNewLiveAllocations => Bool.True
		Press({ heard: Heard(_), .. }) => Bool.True
		ExpectProbe(_, _, _, _) | ExpectSurfaces(_) | ExpectAudioStatus(_) | ExpectTone(_, _) | ExpectEq(_) | ExpectSnapshot(_) | ExpectHistory(_) | ExpectSources(_) => Bool.True
		ExpectAvOffset(_) | ExpectFramePacing(_) => Bool.True
		_ => Bool.False
	}

expectation : Spec.Op, Try(List(Str), [Missing]), Try(Counters, [NoMark]) -> Try({}, Str)
expectation = |op, seen, mark| {
	if !observes(op) {
		return Ok({})
	}
	lines = match seen {
		Ok(l) => l
		Err(Missing) => return Err("expected an observation of this step, saw none: the host printed nothing for it")
	}
	match op {
		ExpectDump(tree) => dump_matches(tree.text, lines)
		ExpectTree(l, tree) =>
			if lines.any(|line| line.starts_with("count ")) {
				one(l, found(lines)).map_ok(|_| {})
			} else {
				dump_matches(tree.text, lines)
			}
		ExpectVisible(l) => one(l, found(lines)).map_ok(|_| {})
		ExpectAbsent(l) => {
			f = found(lines)
			if (f.count == 0) Ok({}) else Err("expected no ${Spec.show_loc(l)}, saw ${count_text(f.count)}")
		}
		ExpectText(l, want) => {
			f = one(l, found(lines))?
			if (f.text == want) Ok({}) else Err("expected ${Spec.show_loc(l)} to show ${Str.inspect(want)}, saw ${Str.inspect(f.text)}")
		}
		ExpectChecked(l, want) => {
			f = one(l, found(lines))?
			wanted = if (want) "true" else "false"
			if f.checked.is_empty() {
				Err("expected ${Spec.show_loc(l)} to be ${if (want) "checked" else "unchecked"}, saw something that is not a checkbox")
			} else if f.checked == wanted {
				Ok({})
			} else {
				Err("expected ${Spec.show_loc(l)} to be ${if (want) "checked" else "unchecked"}, saw it ${if (want) "unchecked" else "checked"}")
			}
		}
		ExpectDisabled(l, want) => {
			f = one(l, found(lines))?
			wanted = if (want) "true" else "false"
			if f.disabled.is_empty() {
				Err("expected ${Spec.show_loc(l)} to be ${if (want) "disabled" else "enabled"}, saw something that is not a control")
			} else if f.disabled == wanted {
				Ok({})
			} else {
				Err("expected ${Spec.show_loc(l)} to be ${if (want) "disabled" else "enabled"}, saw it ${if (want) "enabled" else "disabled"}")
			}
		}
		ExpectWorkers(counts) => {
			seen_counts = lines.keep_oks(
				|line|
					match line.split_on(" ") {
						[field, n] => I64.from_str(n).map_ok(|count| { field, count }).map_err(|_| NotACount)
						_ => Err(NotACount)
					},
			)
			wrong = counts.keep_if(|want| seen_counts.find_first(|s| s.field == want.field) != Ok(want))
			if wrong.is_empty() {
				Ok({})
			} else {
				shown = |list| Str.join_with(list.map(|{ field, count }| ":${field} ${count.to_str()}"), " ")
				saw = seen_counts.keep_if(|s| wrong.any(|w| w.field == s.field))
				Err("expected the worker pool's ${shown(wrong)}, saw ${shown(saw)}")
			}
		}
		ExpectMetricDelta(name, want) => metric_delta(name, lines, mark, |d| d == want, "exactly ${want.to_str()}")
		ExpectMetricDeltaAtMost(name, most, _) => metric_delta(name, lines, mark, |d| d <= most, "at most ${most.to_str()}")
		ExpectAllocationsAtMost(most, _) => metric_delta("allocations", lines, mark, |d| d <= most, "at most ${most.to_str()}")
		ExpectAllocatedBytesAtMost(most, _) => metric_delta("allocated_bytes", lines, mark, |d| d <= most, "at most ${most.to_str()}")
		ExpectNoNewLiveAllocations => metric_delta("live_allocations", lines, mark, |d| d <= 0, "at most 0 (nothing left behind)")
		ExpectPendingEffects(want) => {
			e = effects(lines)
			pending = e.issued.keep_if(|x| x.state == "pending" and x.kind != "interval")
			count = pending.len() + e.work + e.files
			if count == want.to_u64_wrap() {
				Ok({})
			} else {
				listed = pending.map(|x| "#${x.k} ${x.kind}").concat(if (e.work > 0) ["${e.work.to_str()} worker jobs"] else []).concat(if (e.files > 0) ["${e.files.to_str()} file operations"] else [])
				Err("expected ${want.to_str()} pending effects, saw ${count.to_str()}${if (listed.is_empty()) "" else ": ${Str.join_with(listed, ", ")}"}")
			}
		}
		ExpectInterval(ms, want) => {
			live = effects(lines).issued.keep_if(|x| x.kind == "interval" and x.state == "pending" and x.ms == ms.to_str()).len()
			if (live == want.to_u64_wrap()) Ok({}) else Err("expected ${want.to_str()} live intervals of ${ms.to_str()} ms, saw ${live.to_str()}")
		}
		ExpectRequest(n, fields) => {
			e = effects(lines)
			match e.issued.find_first(|x| x.k == n.to_str()) {
				Err(_) => Err("expected effect #${n.to_str()} to be an HTTP request, saw only ${e.issued.len().to_str()} effects issued")
				Ok(x) if x.kind != "http" => Err("expected effect #${n.to_str()} to be an HTTP request, saw a ${x.kind}")
				Ok(x) => {
					wrong = fields.keep_if(|f| x.request.find_first(|r| r.field == f.field) != Ok(f))
					if wrong.is_empty() {
						Ok({})
					} else {
						shown = |list| Str.join_with(list.map(|{ field, value }| ":${field} ${Str.inspect(value)}"), " ")
						Err("expected request #${n.to_str()} to have ${shown(wrong)}, saw ${shown(x.request.keep_if(|r| wrong.any(|w| w.field == r.field)))}")
					}
				}
			}
		}
		ExpectCancelled(n) => {
			e = effects(lines)
			match e.issued.find_first(|x| x.k == n.to_str()) {
				Ok(x) if x.state == "cancelled" => Ok({})
				Ok(x) => Err("expected effect #${n.to_str()} (a ${x.kind}) to be cancelled, saw it ${x.state}")
				Err(_) => Err("expected effect #${n.to_str()} to be cancelled, saw only ${e.issued.len().to_str()} effects issued")
			}
		}
		ExpectProbe(l, x, y, want) => probe_expect("${Spec.show_loc(l)}'s colour at ${x.to_str()},${y.to_str()}", want, lines)
		ExpectSurfaces(want) => fields_expect("the surfaces'", want, lines)
		ExpectAudioStatus(want) => fields_expect("the playback session's", want, lines)
		ExpectTone(hz, want) => fields_expect("the ${hz.to_str()} Hz component's", [{ field: "level", value: want }], lines)
		ExpectEq(want) => fields_expect("the EQ's", want, lines)
		ExpectSnapshot(want) => fields_expect("the newest measurement's", want, lines)
		ExpectHistory(want) => fields_expect("the kept measurements'", want, lines)
		ExpectSources(want) => fields_expect("the audio sources'", want, lines)
		ExpectAvOffset(want) => bounds_expect("the audio/visual offsets'", want, lines)
		ExpectFramePacing(want) => bounds_expect("the frame pacing's", want, lines)
		Press({ key, heard: Heard(want) }) => {
			got = lines.contains("heard true")
			if (got == want) Ok({}) else Err("expected ${key} to be ${if (want) "heard" else "not heard"} by the app, saw it ${if (got) "heard" else "not heard"}")
		}
		_ => Ok({})
	}
}

## Whether a report's `name value` lines hold every field wanted, as text.
fields_expect : Str, List(Spec.Field), List(Str) -> Try({}, Str)
fields_expect = |what, want, lines| {
	seen = lines.keep_oks(
		|line|
			match line.split_on(" ") {
				[field, .. as rest] if !field.is_empty() => Ok({ field, value: unescape(Str.join_with(rest, " ")) })
				_ => Err(NotAField)
			},
	)
	wrong = want.keep_if(|w| seen.find_first(|s| s.field == w.field) != Ok(w))
	if wrong.is_empty() {
		Ok({})
	} else {
		shown = |list| Str.join_with(list.map(|{ field, value }| ":${field} ${Str.inspect(value)}"), " ")
		saw = wrong.map(|w| seen.find_first(|s| s.field == w.field) ?? { field: w.field, value: "nothing" })
		Err("expected ${what} ${shown(wrong)}, saw ${shown(saw)}")
	}
}

## Whether a probe's `name value` lines hold every channel wanted, each
## within the probe's `:tolerance` in percentage points (0, exactly, when
## it names none).
probe_expect : Str, List(Spec.Field), List(Str) -> Try({}, Str)
probe_expect = |what, want, lines| {
	tolerance = want.find_first(|w| w.field == "tolerance").map_ok(|w| I64.from_str(w.value) ?? 0) ?? 0
	seen = |name|
		lines.keep_oks(
			|line|
				match line.split_on(" ") {
					[field, value] if field == name => I64.from_str(value).map_err(|_| NotANumber)
					_ => Err(NotANumber)
				},
		).first()
	wrong = want.keep_if(
		|w|
			if w.field == "tolerance" {
				Bool.False
			} else {
				match (seen(w.field), I64.from_str(w.value)) {
					(Ok(got), Ok(n)) => (got - n).abs() > tolerance
					_ => Bool.True
				}
			},
	)
	if wrong.is_empty() {
		Ok({})
	} else {
		shown = |list| Str.join_with(list.map(|{ field, value }| ":${field} ${value}"), " ")
		saw = wrong.map(|w| { field: w.field, value: seen(w.field).map_ok(|n| n.to_str()) ?? "nothing" })
		within = if (tolerance > 0) " (within ${tolerance.to_str()})" else ""
		Err("expected ${what} ${shown(wrong)}${within}, saw ${shown(saw)}")
	}
}

## Whether a timing report's `name value` lines keep within every bound
## wanted (`Spec.timing_bounds`), each a number in milliseconds or a count.
bounds_expect : Str, List(Spec.Field), List(Str) -> Try({}, Str)
bounds_expect = |what, want, lines| {
	seen = |name|
		lines.keep_oks(
			|line|
				match line.split_on(" ") {
					[field, value] if field == name => F64.from_str(value).map_err(|_| NotANumber)
					_ => Err(NotANumber)
				},
		).first()
	var $wrong = []
	for w in want {
		bound = Spec.timing_bounds.find_first(|b| b.field == w.field) ?? { field: w.field, reads: w.field, least: Bool.False, size: Bool.False }
		limit = F64.from_str(w.value) ?? 0
		held = match seen(bound.reads) {
			Ok(v) => {
				got = if (bound.size and v < 0) -v else v
				if (bound.least) got >= limit else got <= limit
			}
			Err(_) => Bool.False
		}
		if !held {
			saw = lines.find_first(|l| l.starts_with("${bound.reads} ")).map_ok(|l| l.drop_prefix("${bound.reads} ")) ?? "nothing"
			$wrong = $wrong.append(":${w.field} ${w.value}, saw ${bound.reads} ${saw}")
		}
	}
	if $wrong.is_empty() {
		Ok({})
	} else {
		report = lines.find_first(|l| l.starts_with("offsets ")) ?? ""
		Err("expected ${what} ${Str.join_with($wrong, "; ")}${if (report.is_empty()) "" else " (${report})"}")
	}
}

## What a `metrics` observation holds: the work counters (`work HEX`, the
## work record's bytes) and the page heap's counts (`heap NAME N`).
Counters : { work : List(U64), heap : List({ name : Str, value : I64 }) }

counters_of : List(Str) -> Counters
counters_of = |lines| {
	work = match lines.find_first(|line| line.starts_with("work ")) {
		Ok(line) => Spec.work_counters(hex_bytes(line.drop_prefix("work ")))
		Err(_) => []
	}
	heap = lines.keep_oks(
		|line|
			match line.split_on(" ") {
				["heap", name, n] => I64.from_str(n).map_ok(|value| { name, value }).map_err(|_| NotACount)
				_ => Err(NotACount)
			},
	)
	{ work, heap }
}

## A metric's value in an observation's counters.
value_of : Counters, Str -> I64
value_of = |c, name| {
	heap = |n| c.heap.find_first(|h| h.name == n).map_ok(|h| h.value) ?? 0
	if name == "live_allocations" {
		heap("allocations") - heap("deallocations")
	} else if Spec.heap_metrics.contains(name) {
		heap(name)
	} else {
		(Spec.metric(c.work, name) ?? 0).to_i64_wrap()
	}
}

## How a metric changed from the mark (or, with none, from the window's
## mount) to these counters, and which it was measured from.
change : Str, Counters, Try(Counters, [NoMark]) -> (I64, Str)
change = |name, now, mark|
	match mark {
		Ok(before) => (value_of(now, name) - value_of(before, name), "since (mark-metrics)")
		Err(NoMark) => (value_of(now, name), "since the window mounted")
	}

hex_bytes : Str -> List(U8)
hex_bytes = |text| {
	digits = text.to_utf8().map(|c| if (c >= 'a') c - 'a' + 10 else c - '0')
	var $out = []
	var $i = 0.U64
	while $i + 1 < digits.len() {
		$out = $out.append((digits.get($i) ?? 0) * 16 + (digits.get($i + 1) ?? 0))
		$i = $i + 2
	}
	$out
}

metric_delta : Str, List(Str), Try(Counters, [NoMark]), (I64 -> Bool), Str -> Try({}, Str)
metric_delta = |name, lines, mark, holds, wanted| {
	(delta, since) = change(name, counters_of(lines), mark)
	if (holds(delta)) Ok({}) else Err("expected ${name} to change by ${wanted} ${since}, saw ${delta.to_str()}")
}

## Whether a step expects a metric.
is_metric : Spec.Op -> Bool
is_metric = |op|
	match op {
		ExpectMetricDelta(_, _) | ExpectMetricDeltaAtMost(_, _, _) | ExpectAllocationsAtMost(_, _) | ExpectAllocatedBytesAtMost(_, _) | ExpectNoNewLiveAllocations => Bool.True
		_ => Bool.False
	}

## A ratcheted bound's metric, its bound and where the bound is written.
bound_of : Spec.Op -> Try({ name : Str, most : I64, pos : Spec.Pos }, [NotABound])
bound_of = |op|
	match op {
		ExpectMetricDeltaAtMost(name, most, pos) if Spec.ratcheted.contains(name) => Ok({ name, most, pos })
		ExpectAllocationsAtMost(most, pos) => Ok({ name: "allocations", most, pos })
		ExpectAllocatedBytesAtMost(most, pos) => Ok({ name: "allocated_bytes", most, pos })
		_ => Err(NotABound)
	}

## The byte offset of a position in the source, counted as the reader counts.
offset_of : List(U8), Spec.Pos -> U64
offset_of = |bytes, pos| {
	var $r = { bytes, at: 0, line: 1, column: 1 }
	while $r.at < bytes.len() and ($r.line < pos.line or ($r.line == pos.line and $r.column < pos.column)) {
		$r = advance($r)
	}
	$r.at
}

## The end of the number that starts at `at`.
number_end : List(U8), U64 -> U64
number_end = |bytes, at| {
	var $i = at
	while $i < bytes.len() and (bytes.get($i) ?? 0) >= '0' and (bytes.get($i) ?? 0) <= '9' {
		$i = $i + 1
	}
	$i
}

## The effects the app issued in this window, from `effect K KIND STATE
## MS` lines and each request's `request K FIELD VALUE` lines, and the
## worker jobs and file operations in flight (`work N`, `files N`).
Effects : { issued : List({ k : Str, kind : Str, state : Str, ms : Str, request : List({ field : Str, value : Str }) }), work : U64, files : U64 }

effects : List(Str) -> Effects
effects = |lines|
	lines.fold(
		{ issued: [], work: 0, files: 0 },
		|acc, line|
			match line.split_on(" ") {
				["effect", k, kind, state, ms] => { ..acc, issued: acc.issued.append({ k, kind, state, ms, request: [] }) }
				["request", k, field, .. as rest] => {
					value = unescape(Str.join_with(rest, " "))
					{ ..acc, issued: acc.issued.map(|x| if (x.k == k) { ..x, request: x.request.append({ field, value }) } else x) }
				}
				["work", n] => { ..acc, work: U64.from_str(n) ?? 0 }
				["files", n] => { ..acc, files: U64.from_str(n) ?? 0 }
				_ => acc
			},
	)

## The one thing a locator found, or why there was not exactly one.
one : Spec.Loc, Found -> Try(Found, Str)
one = |l, f|
	if f.count == 1 {
		Ok(f)
	} else {
		Err("expected one ${Spec.show_loc(l)}, saw ${count_text(f.count)}${nearest_text(l, f.candidates)}")
	}

count_text : U64 -> Str
count_text = |n| if (n == 0) "none" else if (n == 1) "one" else "${n.to_str()} of them"

## Up to three candidates nearest the locator's text, for a miss.
nearest_text : Spec.Loc, List(Str) -> Str
nearest_text = |l, candidates| {
	want = (l.last() ?? { kind: "", text: "" }).text
	near = nearest(want, candidates)
	if near.is_empty() {
		""
	} else {
		"; the nearest are ${Str.join_with(near.map(Str.inspect), ", ")}"
	}
}

nearest : Str, List(Str) -> List(Str)
nearest = |want, candidates| {
	w = want.to_utf8()
	candidates
		.map(|c| { c, d: distance(w, c.to_utf8()) })
		.sort_with(|a, b| if (a.d < b.d) Before else if (a.d > b.d) After else Same)
		.take_first(3)
		.map(|x| x.c)
}

## The edit distance between two byte strings.
distance : List(U8), List(U8) -> U64
distance = |a, b| {
	var $row = List.repeat(0.U64, b.len() + 1).map_with_index(|_, i| i)
	var $i = 0.U64
	for x in a {
		$i = $i + 1
		var $prev = $row
		var $next = [$i]
		var $j = 0.U64
		for y in b {
			$j = $j + 1
			cost = if (x == y) 0 else 1
			best = min2(min2(($prev.get($j) ?? 0) + 1, ($next.get($j - 1) ?? 0) + 1), ($prev.get($j - 1) ?? 0) + cost)
			$next = $next.append(best)
		}
		$row = $next
	}
	$row.last() ?? 0
}

## Whether the tree the host showed (`lines`, one node a line) matches the
## one expected, written as `want`.
dump_matches : Str, List(Str) -> Try({}, Str)
dump_matches = |want, lines|
	match (read_one(want), read_one(Str.join_with(lines, "\n"))) {
		(Ok(w), Ok(g)) => tree_matches(w, g, [head_of(g)]).map_err(|message| "${message} (record an intended change with `test --update`)")
		(_, Err(problem)) => Err("expected a view tree, saw something unreadable (${problem.message}): ${Str.join_with(lines, " ")}")
		(Err(problem), _) => Err("the expected tree is unreadable: ${problem.message}")
	}

## How far a size may move between systems, in points: the system's fonts
## decide it.
tolerance_pt : I64
tolerance_pt = 4

## The keywords whose numbers are sizes, which match within the tolerance.
sizes : List(Str)
sizes = [":width", ":height", ":content-width", ":content-height"]

## Whether `got` matches `want`, node by node: `_` matches anything, a
## list matches a list of the same kind and as many items, each matching,
## and a size within `tolerance_pt`. A mismatch names the first differing
## node by its path, such as `window/vstack/hstack#3/button#2` (`#k` is a
## node's place among its parent's nodes, from 1).
tree_matches : Spec.Sx, Spec.Sx, List(Str) -> Try({}, Str)
tree_matches = |want, got, trail| {
	at = Str.join_with(trail, "/")
	match (want, got) {
		(Sym("_", _), _) => Ok({})
		(List(ws, _), List(gs, _)) => {
			if head_of(want) != head_of(got) {
				return Err("at ${at}: expected (${head_of(want)} …), saw ${render_short(got)}")
			}
			if ws.len() != gs.len() {
				return Err("at ${at}: expected ${render_short(want)}, saw ${render_short(got)}")
			}
			var $child = 0.U64
			var $prev = ""
			for (w, g) in List.map2(ws, gs, |a, b| (a, b)) {
				name = head_of(g)
				match (w, g) {
					(Int(a, _), Int(b, _)) if sizes.contains($prev) and (a - b).abs() <= tolerance_pt => {}
					(_, List(_, _)) => {
						$child = $child + 1
						tree_matches(w, g, trail.append("${name}#${$child.to_str()}"))?
					}
					_ =>
						if !same_atom(w, g) {
							what = if ($prev.starts_with(":")) " ${$prev}" else ""
							return Err("at ${at}${what}: expected ${render(w)}, saw ${render(g)}")
						}
				}
				$prev = match w {
					Sym(word, _) => word
					_ => ""
				}
			}
			Ok({})
		}
		_ => if (same_atom(want, got)) Ok({}) else Err("at ${at}: expected ${render(want)}, saw ${render(got)}")
	}
}

## A list's kind, its first word; empty for anything else.
head_of : Spec.Sx -> Str
head_of = |sx|
	match sx {
		List([Sym(h, _), ..], _) => h
		_ => ""
	}

same_atom : Spec.Sx, Spec.Sx -> Bool
same_atom = |a, b|
	match (a, b) {
		(Sym("_", _), _) => Bool.True
		(Sym(x, _), Sym(y, _)) => x == y
		(Text(x, _), Text(y, _)) => x == y
		(Int(x, _), Int(y, _)) => x == y
		_ => Bool.False
	}

## An s-expression as canonical text, on one line.
render : Spec.Sx -> Str
render = |sx|
	match sx {
		Sym(word, _) => word
		Text(text, _) => quote(text)
		Int(n, _) => n.to_str()
		List(items, _) => "(${Str.join_with(items.map(render), " ")})"
	}

## A node's head, without what it holds, for a message.
render_short : Spec.Sx -> Str
render_short = |sx|
	match sx {
		List(items, _) => {
			atoms = items.keep_if(
				|i| match i {
					List(_, _) => Bool.False
					_ => Bool.True
				},
			)
			held = items.len() - atoms.len()
			"(${Str.join_with(atoms.map(render), " ")}${if (held > 0) " …${held.to_str()} nodes" else ""})"
		}
		other => render(other)
	}

quote : Str -> Str
quote = |text| "\"${text.replace_each("\\", "\\\\").replace_each("\"", "\\\"").replace_each("\n", "\\n").replace_each("\t", "\\t")}\""

## A tree a spec expects, of the kind `head` (any kind, when empty), or `_`.
tree_of : Spec.Sx, Str -> Try(Spec.Tree, Spec.Problem)
tree_of = |sx, kind|
	match sx {
		Sym("_", pos) => Ok({ text: "_", pos })
		List([Sym(h, _), ..], pos) if kind.is_empty() or h == kind => Ok({ text: render(sx), pos })
		other => Err({ pos: pos_of(other), message: if (kind.is_empty()) "expected a view tree, such as (button \"+\"), or _" else "expected the window's tree, (${kind} :width W :height H …), or _" })
	}

## The end of the form that starts at `at`: past its closing parenthesis,
## its closing quote, or its last character.
form_end : List(U8), U64 -> U64
form_end = |bytes, at| {
	var $i = at
	var $depth = 0.U64
	var $in_text = Bool.False
	while $i < bytes.len() {
		b = bytes.get($i) ?? 0
		if $in_text {
			if b == '\\' {
				$i = $i + 1
			} else if b == '"' {
				$in_text = Bool.False
				if $depth == 0 {
					return $i + 1
				}
			}
		} else if $depth == 0 and $i > at and is_delimiter(b) {
			return $i
		} else if b == '"' {
			$in_text = Bool.True
		} else if b == '(' {
			$depth = $depth + 1
		} else if b == ')' {
			if $depth <= 1 {
				return $i + 1
			}
			$depth = $depth - 1
		}
		$i = $i + 1
	}
	$i
}

## The tree the host showed, a node a line, each line after the first
## indented to `column`.
dump_literal : List(Str), U64 -> Str
dump_literal = |lines, column| {
	pad = Str.join_with(List.repeat(" ", column), "")
	Str.join_with(lines.map_with_index(|line, i| if (i == 0) line else "${pad}${line}"), "\n")
}

failure_message : Str, List(Str) -> Str
failure_message = |message, lines| {
	f = found(lines)
	want = lines.find_first(|line| line.starts_with("want ")).map_ok(|line| unescape(line.drop_prefix("want "))) ?? ""
	near = nearest(want, f.candidates)
	if near.is_empty() {
		message
	} else {
		"${message}; the nearest are ${Str.join_with(near.map(Str.inspect), ", ")}"
	}
}

# ------------------------------------------------------------------ tests

counter =
	\\(test "increment"
	\\  (steps
	\\    (click (button "+"))
	\\    (expect-text (text "1") "1") ; a comment
	\\    (expect-dump (window :width 360 :height 237
	\\                   (vstack :views 1
	\\                     (button "+"))))))
	\\

expect {
	parsed = Spec.parse(counter)
	match parsed {
		Ok({ name, steps: [first, second, third], .. }) =>
			name == "increment"
				and first == { pos: { line: 3, column: 5 }, op: Click([{ kind: "button", text: "+" }]) }
				and second.op == ExpectText([{ kind: "text", text: "1" }], "1")
				and (
					match third.op {
						ExpectDump({ text, pos }) => text == "(window :width 360 :height 237 (vstack :views 1 (button \"+\")))" and pos == { line: 5, column: 18 }
						_ => Bool.False
					}
				)
		_ => Bool.False
	}
}

## Lowering writes one line per step, with the locators' parts as fields.
expect
	Spec.parse(counter).map_ok(Spec.lower)
		== Ok("roc-spec 1\n0\ttime\t0\n1\tclick\t1\tbutton\t+\n2\tfind\t1\ttext\t1\n3\tdump\n")

fetch =
	\\(test "fetch"
	\\  (setup (initial-time 1000))
	\\  (steps
	\\    (click (button "Fetch"))
	\\    (expect-request 1 :method "GET" :timeout 2000)
	\\    (stub-http "ok" :status 200 :body "hi" :headers (("content-type" "text/plain")))
	\\    (run-effect 1)
	\\    (expect-pending-effects 0)))
	\\

## Effect steps lower to the host's verbs; their expectations to one
## observation of every effect.
expect
	Spec.parse(fetch).map_ok(Spec.lower)
		== Ok("roc-spec 1\n0\ttime\t1000\n1\tclick\t1\tbutton\tFetch\n2\teffects\n3\tstub-http\t\t200\thi\t1\tcontent-type\ttext/plain\n4\trun-effect\t1\n5\teffects\n")

## Metrics are measured from the mark before them.
expect {
	text =
		\\(test "work"
		\\  (steps
		\\    (mark-metrics)
		\\    (click (button "+"))
		\\    (expect-metric-delta set_text 1)
		\\    (expect-metric-delta-at-most derived_calls_into_roc 2)))
	# Two counters: counter 0, and counter 1 (rows_created); set_text sums 2 and 12.
	zero = "0000000000000000"
	nine = Str.join_with(List.repeat(zero, 9), "")
	before = "work 0d000000${zero}${zero}0500000000000000${nine}0100000000000000"
	after = "work 0d000000${zero}${zero}0700000000000000${nine}0100000000000000"
	run = Spec.read_run("@1 obs\n|${before}\n@3 obs\n|${after}\n@4 obs\n|${after}\n@done\n")
	Spec.parse(text).map_ok(|p| Spec.judge(p, run).map(|x| x.message)) == Ok(["expected set_text to change by exactly 1 since (mark-metrics), saw 2"])
}

expect Spec.parse("(test \"x\" (steps (expect-metric-delta rows_painted 1)))").is_err()

alloc =
	\\(test "alloc"
	\\  (steps
	\\    (mark-metrics)
	\\    (click (button "+"))
	\\    (expect-allocations-at-most 40)
	\\    (expect-metric-delta-at-most allocated_bytes 9000)
	\\    (expect-no-new-live-allocations)))
	\\

alloc_run : Str -> Spec.Run
alloc_run = |after| Spec.read_run("@1 obs\n|heap allocations 100\n|heap deallocations 90\n|heap allocated_bytes 1000\n${after}@done\n")

## Heap metrics change from the mark; a bound shows what the run saw.
expect {
	after = "@3 obs\n|heap allocations 130\n|heap deallocations 125\n|heap allocated_bytes 3000\n@4 obs\n|heap allocations 130\n|heap deallocations 125\n|heap allocated_bytes 3000\n@5 obs\n|heap allocations 130\n|heap deallocations 115\n"
	Spec.parse(alloc).map_ok(|p| Spec.judge(p, alloc_run(after)).map(|x| x.message))
		== Ok(["expected live_allocations to change by at most 0 (nothing left behind) since (mark-metrics), saw 5"])
}

## --update lowers a bound the run beat, and never raises one.
expect {
	after = "@3 obs\n|heap allocations 130\n|heap deallocations 130\n@4 obs\n|heap allocated_bytes 99999\n@5 obs\n|heap allocations 130\n|heap deallocations 130\n"
	Spec.parse(alloc).map_ok(|p| Spec.update(alloc, p, alloc_run(after))) == Ok(alloc.replace_each("at-most 40)", "at-most 30)"))
}

## A request that differs, and effects still pending, are reported.
expect {
	run = Spec.read_run("@2 obs\n|effect 1 http pending 0\n|request 1 method POST\n|request 1 timeout 2000\n@5 obs\n|effect 1 timer pending 300\n|effect 2 interval pending 47\n|work 1\n@done\n")
	Spec.parse(fetch).map_ok(|p| Spec.judge(p, run).map(|x| x.message))
		== Ok(["expected request #1 to have :method \"GET\", saw :method \"POST\"", "expected 0 pending effects, saw 2: #1 timer, 1 worker jobs"])
}

## A run that saw what the spec expects has no problems.
expect {
	run = Spec.read_run("hello\n@2 obs\n|count 1\n|text 1\n@3 obs\n|(window :width 361 :height 237\n|  (vstack :views 1\n|    (button \"+\")))\n@done\n")
	Spec.parse(counter).map_ok(|p| Spec.judge(p, run)) == Ok([])
}

## A miss says where, what was expected and what the run saw.
expect {
	run = Spec.read_run("@2 obs\n|count 0\n|candidate 2\n|candidate Counter\n@3 obs\n|(window :width 360 :height 237 (vstack :views 1 (button \"+\")))\n@done\n")
	Spec.parse(counter).map_ok(|p| Spec.judge(p, run)) == Ok([{ pos: { line: 4, column: 5 }, message: "expected one (text \"1\"), saw none; the nearest are \"2\", \"Counter\"" }])
}

## A step the host could not take ends the judging there.
expect {
	run = Spec.read_run("@1 fail no button \"+\"\n|want +\n|candidate −\n")
	Spec.parse(counter).map_ok(|p| Spec.judge(p, run)) == Ok([{ pos: { line: 3, column: 5 }, message: "no button \"+\"; the nearest are \"−\"" }])
}

## Updating rewrites the dump's tree, a node a line from its column, and
## only it.
expect {
	run = Spec.read_run("@3 obs\n|(window :width 400 :height 237\n|  (vstack :views 2\n|    (button \"+\")\n|    (button \"-\")))\n@done\n")
	updated = Spec.parse(counter).map_ok(|p| Spec.update(counter, p, run))
	want =
		\\(test "increment"
		\\  (steps
		\\    (click (button "+"))
		\\    (expect-text (text "1") "1") ; a comment
		\\    (expect-dump (window :width 400 :height 237
		\\                   (vstack :views 2
		\\                     (button "+")
		\\                     (button "-"))))))
		\\
	updated == Ok(want)
}

## A placeholder `_` is filled in, and the form around it kept.
expect {
	source = "(test \"x\"\n  (steps\n    (expect-dump _)))\n"
	run = Spec.read_run("@1 obs\n|(window :width 1 :height 2\n|  (spacer))\n@done\n")
	Spec.parse(source).map_ok(|p| Spec.update(source, p, run)) == Ok("(test \"x\"\n  (steps\n    (expect-dump (window :width 1 :height 2\n                   (spacer)))))\n")
}

## A differing node is named by its path; `_` and sizes within the
## tolerance match.
expect {
	got = "(window :width 362 :height 237 (vstack :views 2 (text \"a\" :color red) (hstack :views 2 (button \"x\") (button \"y\" :enabled #f))))"
	check = |want| dump_matches(want, [got])
	(
		check("(window :width 360 :height 237 (vstack :views 2 (text _ :color red) _))"),
		check("(window :width 360 :height 237 (vstack :views 2 (text \"a\" :color red) (hstack :views 2 (button \"x\") (button \"z\" :enabled #f))))"),
		check("(window :width 300 :height 237 _)"),
	)
		== (
			Ok({}),
			Err("at window/vstack#1/hstack#2/button#2: expected \"z\", saw \"y\" (record an intended change with `test --update`)"),
			Err("at window :width: expected 300, saw 362 (record an intended change with `test --update`)"),
		)
}

## Mistakes are reported where they are.
expect {
	problems = ["(test \"x\" (steps (clik (button \"+\"))))", "(test \"x\" (steps (click (buton \"+\"))))", "(test \"x\" (steps (click (button \"+\")))", "(test \"x\")"].map(|text| Spec.parse(text).map_ok(|_| {}).map_err(|p| p.pos))
	problems == [Err({ line: 1, column: 18 }), Err({ line: 1, column: 26 }), Err({ line: 1, column: 1 }), Err({ line: 1, column: 1 })]
}

expect Spec.show_loc([{ kind: "list-row", text: "Ada" }, { kind: "button", text: "x" }]) == "(within (list-row \"Ada\") (button \"x\"))"

expect nearest("Sav", ["Cancel", "Save", "Saved", "Open"]) == ["Save", "Saved", "Open"]

expect unescape(escape("a\tb\\n\nc")) == "a\tb\\n\nc"

min2 : U64, U64 -> U64
min2 = |a, b| if (a < b) a else b

## The drawing and audio steps lower to the host's verbs, a surface found by
## its label and a slider by its place.
expect {
	text =
		\\(test "draw"
		\\  (setup (audio-clock manual))
		\\  (steps
		\\    (window-size 600 300)
		\\    (frame 100)
		\\    (frame)
		\\    (step-source "synthetic.wave" 2)
		\\    (expect-probe (surface "Visualizer") 30 30 :r 100 :a 50)
		\\    (render 300)
		\\    (slide (slider 6) -12)
		\\    (expect-tone 250 silent)
		\\    (click (button "Remove" 2))))
	Spec.parse(text).map_ok(Spec.lower)
		== Ok("roc-spec 1\n0\ttime\t0\n0\taudio-clock\tmanual\n1\twindow-size\t600\t300\n2\tframe\t100\n3\tframe\t\n4\tstep-source\tsynthetic.wave\t2\n5\tprobe\t1\tsurface\tVisualizer\t30\t30\n6\trender\t300\n7\tslide\t1\tslider#\t6\t-12\n8\ttone\t250\n9\tclick\t2\tbutton\tRemove\tnth#\t2\n")
}

## A report expectation holds each field it names, and says which differ.
expect {
	text =
		\\(test "status"
		\\  (steps
		\\    (expect-audio-status :state "Playing" :position 200 :analysis false)
		\\    (expect-probe (surface "Visualizer") 45 30 :r 100 :a 50)))
	run = Spec.read_run("@1 obs\n|state Playing\n|position 250\n|duration 500\n|analysis false\n@2 obs\n|r 100\n|g 0\n|b 0\n|a 50\n@done\n")
	Spec.parse(text).map_ok(|p| Spec.judge(p, run).map(|x| x.message)) == Ok(["expected the playback session's :position \"200\", saw :position \"250\""])
}

## A report names only its step's fields; a locator's K-th counts from 1.
expect Spec.parse("(test \"x\" (steps (expect-eq :loudness 3)))").is_err() and Spec.parse("(test \"x\" (steps (click (button \"Remove\" 0))))").is_err()

expect Spec.show_loc([{ kind: "button", text: "Remove" }, { kind: "nth#", text: "2" }]) == "(button \"Remove\" 2)"

## A run that skipped at a step (`require-metal` without a device) judges
## nothing from there on, and still finished.
expect {
	text = "(test \"t\" (steps (require-metal) (expect-visible (text \"x\"))))"
	run = Spec.read_run("@1 skip no Metal device\n@done\n")
	Spec.parse(text).map_ok(|p| (Spec.judge(p, run).len(), Spec.lower(p))) == Ok((0, "roc-spec 1\n0\ttime\t0\n1\trequire-metal\n2\tfind\t1\ttext\tx\n"))
}

## The timing expectations hold bounds, not values: the mean's size, the
## rest at most (or at least) what they name.
expect {
	text = "(test \"t\" (steps (require-av-timing) (expect-av-offset :mean-within 30 :p95-within 45 :lead-at-most 15) (expect-frame-pacing :dropped-at-most 2 :frames-at-least 100)))"
	run = Spec.read_run("@2 obs\n|mean -12.5\n|p95 40.0\n|lead 20.0\n|offsets -20.0 5.0\n@3 obs\n|dropped 1\n|frames 99\n@done\n")
	Spec.parse(text).map_ok(|p| (Spec.lower(p), Spec.judge(p, run).map(|x| x.message)))
		== Ok(("roc-spec 1\n0\ttime\t0\n1\trequire-av-timing\n2\tav-timing\n3\tav-timing\n", ["expected the audio/visual offsets' :lead-at-most 15, saw lead 20.0 (offsets -20.0 5.0)", "expected the frame pacing's :frames-at-least 100, saw frames 99"]))
}

## A probe matches each channel exactly unless it names a tolerance, in
## percentage points; its values are whole percentages.
expect {
	text = "(test \"p\" (steps (expect-probe (surface \"V\") 1 2 :r 30 :a 100 :tolerance 2) (expect-probe (surface \"V\") 1 2 :r 30 :b 0)))"
	run = Spec.read_run("@1 obs\n|r 32\n|g 19\n|b 40\n|a 100\n@2 obs\n|r 32\n|g 19\n|b 40\n|a 100\n@done\n")
	(
		Spec.parse(text).map_ok(|p| Spec.judge(p, run).map(|x| x.message)),
		Spec.parse("(test \"p\" (steps (expect-probe (surface \"V\") 1 2 :r 101)))").is_err(),
	)
		== (Ok(["expected (surface \"V\")'s colour at 1,2 :r 30 :b 0, saw :r 32 :b 40"]), Bool.True)
}
