import Recorded

## Behaviour specs: `specs/<name>.scm`, one `(test "name" (setup …) (steps …))`
## form each, the surface roc-signals' specs use with native locators.
##
## Everything here is pure, so a spec is parsed and checked on any system
## (`macos.roc test --check`). Running one drives AppKit and so needs an
## Apple silicon Mac: `lower` turns the parsed steps into the line protocol
## the host performs when `ROC_SPEC` holds it, the host prints one tagged
## observation per expectation, and `judge` compares them here, reporting
## `file:line:col: expected …, saw …`. `update` rewrites the bodies of
## `expect-dump` steps with what the run printed, and nothing else.
##
## `scripts/src/Spec.roc` is a byte-identical copy of `cli/Spec.roc`, as
## `scripts/src/Recorded.roc` is of `cli/Recorded.roc`, and `check` fails
## when they differ. Change `cli/Spec.roc`, then copy it.
Spec := [].{

	## A source position, from 1.
	Pos : { line : U64, column : U64 }

	## What is wrong, and where.
	Problem : { pos : Pos, message : Str }

	## One s-expression and where it starts. A `Dump` is a `"""` block:
	## its text, and the byte range of the whole literal in the source.
	Sx := [Sym(Str, Pos), Text(Str, Pos), Int(I64, Pos), Dump({ text : Str, pos : Pos, start : U64, end : U64, indent : Str }), List(List(Sx), Pos)]

	## A locator: what to find, outermost first. `(within A B)` is A's
	## parts then B's: B is looked for inside the one thing A finds.
	Loc : List({ kind : Str, text : Str })

	## A dump expected by `expect-dump`, and where its literal is.
	DumpBody : { text : Str, start : U64, end : U64, indent : Str }

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
		ExpectDump(DumpBody),
		ExpectVisible(Loc),
		ExpectAbsent(Loc),
		ExpectText(Loc, Str),
		ExpectChecked(Loc, Bool),
		ExpectDisabled(Loc, Bool),
		ExpectWorkers(List({ field : Str, count : I64 })),
	]

	## One step and where it is written.
	Step : { pos : Pos, op : Op }

	## What a spec sets before the app mounts.
	Setup : { pool : U64 }

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
				var $setup = { pool: 0 }
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
		head = ["roc-spec 1"].concat(if (setup.pool > 0) ["0\tpool\t${setup.pool.to_str()}"] else [])
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
	Run : { observed : List({ step : U64, lines : List(Str) }), failed : Try({ step : U64, message : Str, lines : List(Str) }, [None]), done : Bool }

	## Read the host's standard output: `@k obs` or `@k fail MESSAGE`
	## starts a record, each `|LINE` adds a line to it, and `@done` says
	## every step ran. Anything else is the app's own output, and ignored.
	read_run : Str -> Run
	read_run = |printed| {
		var $observed = []
		var $failed = Err(None)
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
		{ observed: close($observed, $current), failed: $failed, done: $done }
	}

	## Every way the run differs from the spec, at the step it concerns.
	judge : Parsed, Run -> List(Problem)
	judge = |{ steps, .. }, run| {
		var $problems = []
		var $k = 0.U64
		for step in steps {
			$k = $k + 1
			match run.failed {
				Ok(f) if f.step == $k => return $problems.append({ pos: step.pos, message: failure_message(f.message, f.lines) })
				_ => {}
			}
			match expectation(step.op, observation(run, $k)) {
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

	## The spec's source with each `expect-dump` body replaced by the dump
	## the run printed for it, keeping its indentation. Only dumps change.
	update : Str, Parsed, Run -> Str
	update = |source, { steps, .. }, run| {
		var $edits = []
		var $k = 0.U64
		for step in steps {
			$k = $k + 1
			match (step.op, observation(run, $k)) {
				(ExpectDump(body), Ok(lines)) => {
					$edits = $edits.append({ start: body.start, end: body.end, text: dump_literal(lines, body.indent) })
				}
				_ => {}
			}
		}
		bytes = source.to_utf8()
		var $out = []
		var $at = 0.U64
		for edit in $edits {
			$out = $out.concat(bytes.sublist({ start: $at, len: edit.start - $at })).concat(edit.text.to_utf8())
			$at = edit.end
		}
		Str.from_utf8_lossy($out.concat(bytes.drop_first($at)))
	}

	## How a step is written back, for messages: `(button "+")`.
	show_loc : Loc -> Str
	show_loc = |loc|
		match loc {
			[] => "nothing"
			[one] => show_part(one)
			[first, .. as rest] => "(within ${show_part(first)} ${Spec.show_loc(rest)})"
		}

	## The worker-pool fields `expect-workers` may name.
	worker_fields : List(Str)
	worker_fields = ["limit", "live", "running", "queued", "started", "answered", "lost", "stopped", "timed-out", "dropped"]

	## The step names, for an unknown step's message.
	step_names : List(Str)
	step_names = ["click", "fill", "submit", "toggle", "select", "hover", "choose", "press", "files", "drop", "move", "leave", "sweep", "scroll", "phase", "stats", "window", "wait", "reload", "expect-dump", "expect-visible", "expect-absent", "expect-text", "expect-checked", "expect-disabled", "expect-workers"]

	## The locator kinds.
	locator_names : List(Str)
	locator_names = ["button", "checkbox", "text", "text-field", "text-area", "list-row", "hover-target", "within"]
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
		Ok('"') => if (starts_triple(r)) read_dump(r) else read_text(r)
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
			return Err({ pos: start, message: "a string cannot hold a line break; write \\n, or use a \"\"\" block for a dump" })
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

starts_triple : R -> Bool
starts_triple = |r| r.bytes.sublist({ start: r.at, len: 3 }) == ['"', '"', '"']

## A `"""` block: the opening quotes end their line, the closing quotes
## start one, and whatever indents the closing quotes is taken from every
## line between, which holds the text verbatim, with no escapes.
read_dump : R -> Try((Spec.Sx, R), Spec.Problem)
read_dump = |r0| {
	start = here(r0)
	open = advance_by(r0, 3)
	if peek(open) != Ok('\n') {
		return Err({ pos: start, message: "a \"\"\" block starts its text on the next line" })
	}
	body_at = open.at + 1
	var $r = advance(open)
	while $r.at < $r.bytes.len() and !starts_triple($r) {
		$r = advance($r)
	}
	if $r.at >= $r.bytes.len() {
		return Err({ pos: start, message: "this \"\"\" block is never closed" })
	}
	raw = $r.bytes.sublist({ start: body_at, len: $r.at - body_at })
	lines = Str.from_utf8(raw).map_err(|_| { pos: start, message: "this block is not UTF-8" })?.split_on("\n")
	indent = lines.last() ?? ""
	if !indent.to_utf8().all(|b| b == ' ' or b == '\t') {
		return Err({ pos: start, message: "the closing \"\"\" starts its own line" })
	}
	var $kept = []
	for line in lines.drop_last(1) {
		if line.starts_with(indent) {
			$kept = $kept.append(line.drop_prefix(indent))
		} else if line.trim().is_empty() {
			$kept = $kept.append("")
		} else {
			return Err({ pos: start, message: "every line of a \"\"\" block is indented at least as far as its closing \"\"\"" })
		}
	}
	text = Str.join_with($kept.map(|line| line.concat("\n")), "")
	after = advance_by($r, 3)
	Ok((Dump({ text, pos: start, start: r0.at, end: after.at, indent }), after))
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
		Dump({ pos, .. }) => pos
		List(_, p) => p
	}

show : Spec.Sx -> Str
show = |sx|
	match sx {
		Sym(s, _) => s
		Text(s, _) => Str.inspect(s)
		Int(n, _) => n.to_str()
		Dump(_) => "a \"\"\" block"
		List(_, _) => "a list"
	}

# ------------------------------------------------------------------ grammar

setup_form : Spec.Setup, Spec.Sx -> Try(Spec.Setup, Spec.Problem)
setup_form = |setup, form|
	match form {
		List([Sym("worker-pool", _), Int(n, _)], _) if n >= 1 and n <= 64 => Ok({ ..setup, pool: n.to_u64_wrap() })
		List([Sym("worker-pool", p), ..], _) => Err({ pos: p, message: "(worker-pool N) takes a count from 1 to 64" })
		List([head, ..], _) => Err({ pos: pos_of(head), message: "unknown setup form ${show(head)}; the setup forms are worker-pool" })
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
		("expect-dump", [Dump({ text, start, end, indent, .. })]) => ExpectDump({ text, start, end, indent })
		("expect-dump", _) => return usage("(expect-dump \"\"\" …dump… \"\"\")")
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

loc : Spec.Sx -> Try(Spec.Loc, Spec.Problem)
loc = |sx|
	match sx {
		List([Sym("within", _), outer, inner], _) => Ok(loc(outer)?.concat(loc(inner)?))
		List([Sym("within", p), ..], _) => Err({ pos: p, message: "within is written (within LOCATOR LOCATOR)" })
		List([Sym(kind, _), Text(text, _)], _) if ["button", "checkbox", "text", "text-field", "text-area", "list-row"].contains(kind) => Ok([{ kind, text }])
		List([Sym(kind, _)], _) if ["text-field", "text-area"].contains(kind) => Ok([{ kind, text: "" }])
		List([Sym(kind, _), Int(n, p)], _) if kind == "list-row" or kind == "hover-target" =>
			if (n >= 1) Ok([{ kind: "${kind}#", text: n.to_str() }]) else Err({ pos: p, message: "rows and hover targets count from 1" })
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
		ExpectVisible(l) => ["find"].concat(loc_fields(l))
		ExpectAbsent(l) => ["find"].concat(loc_fields(l))
		ExpectText(l, _) => ["find"].concat(loc_fields(l))
		ExpectChecked(l, _) => ["find"].concat(loc_fields(l))
		ExpectDisabled(l, _) => ["find"].concat(loc_fields(l))
		ExpectWorkers(_) => ["workers"]
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

expectation : Spec.Op, Try(List(Str), [Missing]) -> Try({}, Str)
expectation = |op, seen| {
	lines = match (op, seen) {
		(ExpectDump(_), Ok(l)) => l
		(ExpectVisible(_), Ok(l)) => l
		(ExpectAbsent(_), Ok(l)) => l
		(ExpectText(_, _), Ok(l)) => l
		(ExpectChecked(_, _), Ok(l)) => l
		(ExpectDisabled(_, _), Ok(l)) => l
		(ExpectWorkers(_), Ok(l)) => l
		(Press({ heard: Heard(_), .. }), Ok(l)) => l
		(Press({ heard: Heard(_), .. }), Err(Missing)) => return Err("expected the host to report the key press, saw nothing")
		(Press(_), _) => return Ok({})
		(ExpectDump(_), Err(Missing)) => return Err("expected a dump, saw none: the host printed no observation for this step")
		(ExpectVisible(_), Err(Missing)) => return Err("expected an observation, saw none")
		(ExpectAbsent(_), Err(Missing)) => return Err("expected an observation, saw none")
		(ExpectText(_, _), Err(Missing)) => return Err("expected an observation, saw none")
		(ExpectChecked(_, _), Err(Missing)) => return Err("expected an observation, saw none")
		(ExpectDisabled(_, _), Err(Missing)) => return Err("expected an observation, saw none")
		(ExpectWorkers(_), Err(Missing)) => return Err("expected the pool's counts, saw none")
		_ => return Ok({})
	}
	match op {
		ExpectDump(body) => dump_matches(body.text, lines)
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
		Press({ key, heard: Heard(want) }) => {
			got = lines.contains("heard true")
			if (got == want) Ok({}) else Err("expected ${key} to be ${if (want) "heard" else "not heard"} by the app, saw it ${if (got) "heard" else "not heard"}")
		}
		_ => Ok({})
	}
}

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

dump_matches : Str, List(Str) -> Try({}, Str)
dump_matches = |want, lines| {
	got = Str.join_with(lines.map(|line| line.concat("\n")), "")
	if Recorded.matches(want, got) {
		Ok({})
	} else {
		w = want.split_on("\n")
		g = got.split_on("\n")
		var $k = 0.U64
		while $k < w.len() and $k < g.len() and (w.get($k) ?? "") == (g.get($k) ?? "") {
			$k = $k + 1
		}
		first = "line ${($k + 1).to_str()}: expected ${Str.inspect(w.get($k) ?? "")}, saw ${Str.inspect(g.get($k) ?? "")}"
		Err("the dump differs at ${first} (record an intended change with `test --update`); it printed:\n${got}")
	}
}

## A `"""` literal holding `lines`, each indented by `indent`.
dump_literal : List(Str), Str -> Str
dump_literal = |lines, indent| {
	body = Str.join_with(lines.map(|line| if (line.is_empty()) "\n" else "${indent}${line}\n"), "")
	"\"\"\"\n${body}${indent}\"\"\""
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
	\\    (expect-dump """
	\\      --- 360x237
	\\      ui-vstack [1 views]
	\\      """)))
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
						ExpectDump({ text, indent, .. }) => text == "--- 360x237\nui-vstack [1 views]\n" and indent == "      "
						_ => Bool.False
					}
				)
		_ => Bool.False
	}
}

## Lowering writes one line per step, with the locators' parts as fields.
expect
	Spec.parse(counter).map_ok(Spec.lower)
		== Ok("roc-spec 1\n1\tclick\t1\tbutton\t+\n2\tfind\t1\ttext\t1\n3\tdump\n")

## A run that saw what the spec expects has no problems.
expect {
	run = Spec.read_run("hello\n@2 obs\n|count 1\n|text 1\n@3 obs\n|--- 361x237\n|ui-vstack [1 views]\n@done\n")
	Spec.parse(counter).map_ok(|p| Spec.judge(p, run)) == Ok([])
}

## A miss says where, what was expected and what the run saw.
expect {
	run = Spec.read_run("@2 obs\n|count 0\n|candidate 2\n|candidate Counter\n@3 obs\n|--- 360x237\n|ui-vstack [1 views]\n@done\n")
	Spec.parse(counter).map_ok(|p| Spec.judge(p, run)) == Ok([{ pos: { line: 4, column: 5 }, message: "expected one (text \"1\"), saw none; the nearest are \"2\", \"Counter\"" }])
}

## A step the host could not take ends the judging there.
expect {
	run = Spec.read_run("@1 fail no button \"+\"\n|want +\n|candidate −\n")
	Spec.parse(counter).map_ok(|p| Spec.judge(p, run)) == Ok([{ pos: { line: 3, column: 5 }, message: "no button \"+\"; the nearest are \"−\"" }])
}

## Updating rewrites the dump's body, and only it.
expect {
	run = Spec.read_run("@3 obs\n|--- 400x237\n|ui-vstack [2 views]\n@done\n")
	updated = Spec.parse(counter).map_ok(|p| Spec.update(counter, p, run))
	updated == Ok(counter.replace_each("360x237", "400x237").replace_each("[1 views]", "[2 views]"))
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
