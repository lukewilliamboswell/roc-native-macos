#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	roc: "nightly-2026-11-22-3350b1c",
}

import cli.Cmd
import cli.Duration
import cli.Env
import cli.Monotonic
import cli.OsStr
import cli.Path
import cli.Stderr
import cli.Stdout
import src/Recorded
import src/SpecRun
import src/Release
import src/Repo

## The `check` task, the pull-request gate: `blueprint run check` runs every
## stage, and `blueprint run check -- STAGE...` the named ones, in order.
##
## - `pins`: only the scripts pin a compiler, and they pin `roc-stable`
##   (`roc-policy check`, from Blueprint.roc's `repository_policy`).
## - `engine`: the engine facades in platform/ are what the roc-signals
##   engine package `platform/main.roc` names gives
##   (`scripts/build.roc -- engine --check`).
## - `fmt`: `roc fmt --check` over the platform, glue, examples and the
##   `macos.roc` tool (`cli/`), and `roc-stable fmt --check` over the scripts.
## - `scripts`: the scripts' `expect` tests.
## - `specs`: every spec under `examples/` and `bench/` parses
##   (`Spec.parse`), on any system.
## - `tool`: `cli/Bundle.roc` is what `scripts/src/Release.roc` generates for
##   a checkout (`tool --update` writes it), `scripts/src/Recorded.roc`,
##   `Spec.roc` and `SpecRun.roc` are copies of the tool's, and `roc test` on
##   the tool.
## - `glue`: the committed glue in host/ is what `glue/SwiftGlue.roc`
##   generates with the `roc` on PATH (`scripts/build.roc -- glue --check`).
## - `build`: `scripts/build.roc`, with the latest nightly as `roc`: the host
##   (reused when its fingerprint matches), the linker inputs and every
##   example.
## - `test`: `roc test` on the platform root and on every example.
## - `examples`: every example's specs (`examples/<name>/specs/*.scm`, or
##   only the examples `EXAMPLES="counter todos"` names), and
##   any legacy recorded scripted runs; `examples --update` rewrites the
##   specs' dumps (and records the cases) with what they print now. Then the
##   counter's first spec once more through Roc's run mode, `roc main.roc`,
##   which links the host with the compiler's own run shim against the
##   stubs, and must pass the same.
## - `bench`: every harness under `bench/` (`bench/<name>/run.sh --smoke`),
##   built and run at a token size, so it never goes stale, then its specs
##   (`bench/<name>/specs/*.scm`): the work a turn does, counted, at two
##   sizes. Its timings are only reported.
## - `bundle`: the platform bundle from the inputs `build` made, and an
##   author's first steps against it with the `macos.roc` tool: `init`,
##   `build` and `test` a counter (`scripts/bundle.roc --prebuilt --test`).
##
## The package compiler is the `roc` on PATH: the latest nightly in CI.
main! : List(OsStr) => Try({}, _)
main! = |raw_args| {
	args = raw_args.map(OsStr.display)
	chosen = match Repo.selection(args) {
		Ok(selection) => selection
		Err(Unknown(name)) => {
			note!("unknown stage ${name}; the stages are ${Str.join_with(Repo.stages, ", ")}")
			return Err(Exit(2))
		}
	}
	colour = { out: colour!(1), err: colour!(2) }
	var $problems = []
	for stage in chosen.stages {
		note!("== ${stage}")
		start = Monotonic.now!()
		found = run_stage!(stage, chosen.update, colour.out)?
		result = Repo.paint(if (found.is_empty()) "passed" else "failed", colour.out)
		note!("== ${stage}: ${result} in ${Repo.millis(Monotonic.elapsed!(start).to_millis())}")
		$problems = $problems.concat(found.map(|problem| "${stage}: ${problem}"))
	}
	if $problems.is_empty() {
		note!("check: ${Repo.paint("passed", colour.out)} (${Str.join_with(chosen.stages, ", ")})")
		Ok({})
	} else {
		warn!("\n${Repo.paint("Failed", colour.err)}")
		for problem in $problems {
			warn!("  ${problem}")
		}
		warn!("check: ${Repo.paint("failed", colour.err)} with ${$problems.len().to_str()} problems")
		Err(Exit(1))
	}
}

## Whether to colour what is written to file descriptor `fd` (1 or 2).
## Colour is an aid, never the only signal: the word is always printed, and
## it is left plain when `NO_COLOR` is set or nobody is watching a terminal.
colour! : U8 => Bool
colour! = |fd| {
	no_colour = match Env.var_str!(OsStr.from_str("NO_COLOR")) {
		Ok(value) => !value.is_empty()
		Err(_) => Bool.False
	}
	if no_colour {
		Bool.False
	} else {
		# `test` inherits this script's descriptors, and -t asks whether one is a terminal.
		match Cmd.new("test").args(["-t", OsStr.from_str(fd.to_str())]).inherit_stdio().run!() {
			Ok(output) => output.status == Exited(0)
			Err(_) => Bool.False
		}
	}
}

run_stage! : Str, Bool, Bool => Try(List(Str), _)
run_stage! = |stage, update, colour|
	match stage {
		"pins" => pins!()
		"engine" => run!("roc-stable", ["scripts/build.roc", "--", "engine", "--check"])
		"fmt" => fmt!(colour)
		"tool" => tool!(update)
		"scripts" => scripts!()
		"specs" => specs!()
		"glue" => run!("roc-stable", ["scripts/build.roc", "--", "glue", "--check"])
		"build" => build!()
		"test" => test!()
		"examples" => examples!(update, colour)
		"bench" => bench!(update)
		"bundle" => run!("roc-stable", ["scripts/bundle.roc", "--", "--prebuilt", "--test"])
		_ => Ok(["no such stage"])
	}

## The files git tracks or would track (untracked files .gitignore does not
## exclude), under the given paths.
tracked! : List(Str) => Try(List(Str), _)
tracked! = |paths| {
	listed = Cmd.new("git").args(["ls-files", "--cached", "--others", "--exclude-standard", "--"].concat(paths).map(OsStr.from_str)).capture!()?
	Ok(listed.split_on("\n").keep_if(|line| !line.is_empty()))
}

## The compiler pins, as `repository_policy` in Blueprint.roc states them:
## roc-policy checks every Roc header, and no file outside the scripts names
## a compiler for the whole repository.
pins! : () => Try(List(Str), _)
pins! = || {
	var $problems = run!("roc-policy", ["check", "--root", "."])?
	for path in Repo.stray_pins {
		if Path.exists!(Path.utf8(path))? {
			$problems = $problems.append("${path} pins a compiler; only the scripts under scripts/ may")
		}
	}
	Ok($problems)
}

fmt! : Bool => Try(List(Str), _)
fmt! = |colour| {
	sources = tracked!(["platform", "glue", "examples", "bench", "cli"])?.keep_if(|path| path.ends_with(".roc"))
	var $checked = []
	for path in sources {
		match Repo.fmt_skip(path) {
			Ok(reason) => note!(" ${Repo.paint("SKIP", colour)} ${path}: ${reason}")
			Err(Checked) => {
				$checked = $checked.append(path)
			}
		}
	}
	sources_fmt = run!("roc", ["fmt", "--check"].concat($checked))?
	scripts = run!("roc-stable", ["fmt", "--check"].concat(tracked!(["scripts"])?.keep_if(|path| path.ends_with(".roc"))))?
	note!("${$checked.len().to_str()} of ${sources.len().to_str()} platform, glue, example and tool sources checked")
	Ok(sources_fmt.concat(scripts))
}

## The `macos.roc` tool's package, `cli/`: its checked-in `Bundle.roc` is
## current, its recorded-case rules are the scripts' own, and its `expect`s
## pass. With `update`, write `cli/Bundle.roc` as generated.
tool! : Bool => Try(List(Str), _)
tool! = |update| {
	var $problems = []
	cases = names_in!("examples/counter/specs")
	generated = Release.development_bundle(cases)
	if update {
		Path.write_utf8!(Path.utf8("cli/Bundle.roc"), generated)?
		note!("wrote cli/Bundle.roc")
	} else if Path.read_utf8!(Path.utf8("cli/Bundle.roc"))? != generated {
		$problems = $problems.append("cli/Bundle.roc is not what scripts/src/Release.roc generates for this checkout (the counter's specs may have changed): run `blueprint run check -- tool --update` and review the diff")
	}
	for name in Repo.shared_modules {
		if Path.read_utf8!(Path.utf8("cli/${name}"))? != Path.read_utf8!(Path.utf8("scripts/src/${name}"))? {
			$problems = $problems.append("scripts/src/${name} differs from cli/${name}, which it must copy byte for byte: change cli/${name}, then copy it over")
		}
	}
	Ok($problems.concat(run!("roc", ["test", "cli/main.roc"])?))
}

## Every spec under `examples/` and `bench/` parses, with its problem at
## its file, line and column when it does not.
specs! : () => Try(List(Str), _)
specs! = || {
	found = tracked!(["examples", "bench"])?.keep_if(|path| path.ends_with(".scm"))
	var $problems = []
	for path in found {
		match SpecRun.check!(".", path) {
			Ok({}) => {}
			Err(problem) => {
				$problems = $problems.append(problem)
			}
		}
	}
	note!("${found.len().to_str()} specs parsed")
	Ok($problems)
}

build! : () => Try(List(Str), _)
build! = || run_with!(Cmd.new("roc-stable").args(["scripts/build.roc"]).env("ROC", "roc"), "scripts/build.roc")

## The `expect`s of every script, and so of every module under scripts/src.
scripts! : () => Try(List(Str), _)
scripts! = || {
	var $problems = []
	for script in Repo.scripts {
		$problems = $problems.concat(run!("roc-stable", ["test", script])?)
	}
	Ok($problems)
}

test! : () => Try(List(Str), _)
test! = || {
	var $problems = run!("roc", ["test", "platform/main.roc"])?
	for example in examples_present!()? {
		$problems = $problems.concat(run!("roc", ["test", "examples/${example}/main.roc"])?)
	}
	Ok($problems)
}

## Every harness under `bench/`: built and run at a token size with
## `run.sh --smoke`, which fails unless the run does what it measures, and
## then its specs against the program `run.sh` built, each of which counts
## the work a turn does (`expect-metric-delta-at-most`) with the same bounds
## at a small size and a large one.
bench! : Bool => Try(List(Str), _)
bench! = |update| {
	harnesses = tracked!(["bench"])?.keep_if(|path| path.ends_with("/run.sh"))
	root = Env.cwd!().map_ok(|cwd| cwd.display()) ?? "."
	var $problems = []
	for script in harnesses {
		$problems = $problems.concat(run_with!(Cmd.new("bash").args([script, "--smoke"].map(OsStr.from_str)).env("ROC", "roc"), "${script} --smoke")?)
		dir = script.drop_suffix("/run.sh")
		name = dir.drop_prefix("bench/")
		for spec in SpecRun.names(names_in!("${dir}/specs")) {
			outcome = SpecRun.run!({ program: "${root}/${dir}/${name}", dir: "${root}/${dir}", spec: "specs/${spec}", update, args: [], env: [] })?
			match outcome {
				Passed => note!("PASS ${dir}/specs/${spec}")
				Updated => note!("SAVE ${dir}/specs/${spec}")
				Failed(problems) => {
					note!("FAIL ${dir}/specs/${spec}")
					$problems = $problems.append("${dir}/specs/${spec}: ${Str.join_with(problems, "\n  ")}")
				}
			}
		}
	}
	Ok($problems)
}

## The examples: every directory under `examples/` with a `main.roc`.
examples_present! : () => Try(List(Str), _)
examples_present! = || {
	roots = tracked!(["examples"])?.keep_if(|path| path.ends_with("/main.roc"))
	Ok(roots.keep_oks(|path| path.drop_prefix("examples/").split_on("/").first()))
}

## Every spec of every example, and any legacy recorded case: the built
## app, run from its directory, must pass the spec, or exit 0 having printed
## exactly the recorded output.
examples! : Bool, Bool => Try(List(Str), _)
examples! = |update, colour| {
	var $cases = []
	var $problems = []
	# `EXAMPLES="counter todos"` runs only those examples' specs.
	only = (Env.var_str!(OsStr.from_str("EXAMPLES")) ?? "").split_on(" ").keep_if(|name| !name.is_empty())
	for example in examples_present!()?.keep_if(|name| only.is_empty() or only.contains(name)) {
		specs = SpecRun.names(names_in!("examples/${example}/specs")).map(|name| Spec({ example, name: "specs/${name}" }))
		legacy = names_in!("examples/${example}/tests").keep_oks(Recorded.case_name).sort_with(compare_str).map(|name| Legacy({ example, name, base: "examples/${example}/tests/${name}" }))
		if specs.is_empty() and legacy.is_empty() {
			$problems = $problems.append("examples/${example} has no spec: add examples/${example}/specs/<name>.scm, then run `blueprint run examples -- --update`")
		}
		$cases = $cases.concat(specs).concat(legacy)
	}
	note!("Running ${$cases.len().to_str()} specs and cases${if (update) ", recording their output" else ""}")
	start = Monotonic.now!()
	var $index = 0
	var $passed = 0
	for case in $cases {
		$index = $index + 1
		case_start = Monotonic.now!()
		(shown, outcome) = match case {
			Spec(spec) => ("${spec.example}/${spec.name}", run_spec!(spec, if (update) Update else Built)?)
			Legacy(legacy) => ("${legacy.example}/tests/${legacy.name}", run_case!(legacy, if (update) Update else Built)?)
		}
		ms = Monotonic.elapsed!(case_start).to_millis()
		label = match outcome {
			Ok(Passed) => "PASS"
			Ok(Recorded) => "SAVE"
			Err(_) => "FAIL"
		}
		note!(Repo.progress({ index: $index, total: $cases.len(), name: shown, outcome: Repo.paint(label, colour), ms }))
		match outcome {
			Ok(_) => {
				$passed = $passed + 1
			}
			Err(problem) => {
				$problems = $problems.append("${shown}: ${problem}")
			}
		}
	}
	note!("Summary: ${$passed.to_str()} passed, ${($cases.len() - $passed).to_str()} failed in ${Repo.millis(Monotonic.elapsed!(start).to_millis())}")
	# Roc's run mode, which `roc build` never exercises: a run shim import
	# the stubs lack fails this link.
	if !update {
		first = $cases.keep_oks(
			|case|
				match case {
					Spec(spec) if spec.example == "counter" => Ok(spec)
					_ => Err(NotCounter)
				},
		)
		match first.first() {
			Ok(spec) => {
				run_start = Monotonic.now!()
				outcome = run_spec!(spec, RunMode)?
				label = if (outcome.is_ok()) "PASS" else "FAIL"
				note!(Repo.progress({ index: 1, total: 1, name: "counter/${spec.name} via roc main.roc", outcome: Repo.paint(label, colour), ms: Monotonic.elapsed!(run_start).to_millis() }))
				match outcome {
					Ok(_) => {}
					Err(problem) => {
						$problems = $problems.append("counter/${spec.name} via `roc main.roc`: ${problem}")
					}
				}
			}
			Err(_) => {
				$problems = $problems.append("the counter has no spec to run through `roc main.roc`")
			}
		}
	}
	Ok($problems)
}

## The file names in a directory, or none when there is no such directory.
names_in! : Str => List(Str)
names_in! = |dir|
	if Path.is_dir!(Path.utf8(dir)) ?? Bool.False {
		(Path.list!(Path.utf8(dir)) ?? []).keep_oks(|path| Path.filename(path).map_ok(Path.display))
	} else {
		[]
	}

## One spec: the built app (`Built`), rewriting its dumps when `Update`, or
## `roc main.roc` in the example's directory (`RunMode`).
run_spec! : { example : Str, name : Str }, [Built, Update, RunMode] => Try(Try([Passed, Recorded], Str), _)
run_spec! = |{ example, name }, how| {
	root = Env.cwd!().map_ok(|cwd| cwd.display()) ?? "."
	dir = "${root}/examples/${example}"
	exe = "${dir}/${example}"
	if how != RunMode and !(Path.exists!(Path.utf8(exe))?) {
		return Ok(Err("examples/${example}/${example} is not built: run `blueprint run build` first"))
	}
	(program, args) = if (how == RunMode) ("roc", ["main.roc"]) else (exe, [])
	outcome = SpecRun.run!({ program, dir, spec: name, update: how == Update, args, env: [] })?
	Ok(
		match outcome {
			Passed => Ok(Passed)
			Updated => Ok(Recorded)
			Failed(problems) => Err(Str.join_with(problems, "\n  "))
		},
	)
}

## One legacy recorded case: the built app (`Built`), recording its output
## when `Update`.
run_case! : { example : Str, name : Str, base : Str }, [Built, Update] => Try(Try([Passed, Recorded], Str), _)
run_case! = |{ example, base, .. }, how| {
	exe = "examples/${example}/${example}"
	update = how == Update
	if !(Path.exists!(Path.utf8(exe))?) {
		return Ok(Err("${exe} is not built: run `blueprint run build` first"))
	}
	steps = Path.read_utf8!(Path.utf8("${base}.script"))?.trim()
	# A case runs from its example's directory, as `macos.roc test` runs an
	# app's, so its steps name files relative to the app and its output
	# writes the app's directory `<app>`.
	root = Env.cwd!().map_ok(|cwd| cwd.display()) ?? "."
	app_dir = "${root}/examples/${example}"
	result = Cmd.new(OsStr.from_str("${app_dir}/${example}"))
		.cwd(Path.utf8(app_dir))
		.env("ROC_SCRIPT", OsStr.from_str(steps))
		.stdin(Null)
		.stderr(MergeWithStdout)
		.timeout(Duration.seconds(60))
		.run!()
	output = match result {
		Ok(done) => done
		Err(CmdErr(error)) => return Ok(Err("${exe} did not finish: ${Str.inspect(error)}"))
		Err(Interrupted) => return Ok(Err("interrupted"))
	}
	printed = Recorded.portable(Str.from_utf8_lossy(output.stdout_bytes), app_dir, "<app>")
	expected_path = Path.utf8("${base}.expected")
	match output.status {
		Exited(0) => {}
		Exited(code) => return Ok(Err("exited with ${code.to_str()}, not 0; it printed:\n${printed}"))
		Signaled(signal) => return Ok(Err("ended by signal ${signal.to_str()}; it printed:\n${printed}"))
	}
	if update {
		Path.write_utf8!(expected_path, printed)?
		return Ok(Ok(Recorded))
	}
	expected = if (Path.exists!(expected_path)?) Path.read_utf8!(expected_path)? else ""
	if Recorded.matches(expected, printed) {
		Ok(Ok(Passed))
	} else {
		Ok(Err("printed something other than ${base}.expected (run `blueprint run examples -- --update` to record an intended change):\n--- expected\n${expected}--- printed\n${printed}"))
	}
}

## Run a program with the terminal inherited; a non-zero exit is a problem.
run! : Str, List(Str) => Try(List(Str), _)
run! = |program, args| run_with!(Cmd.new(OsStr.from_str(program)).args(args.map(OsStr.from_str)), Str.join_with([program].concat(args.take_first(4)), " "))

run_with! : Cmd.Command, Str => Try(List(Str), _)
run_with! = |command, shown| {
	note!("RUN ${shown}")
	output = command.inherit_stdio().run!()?
	match output.status {
		Exited(0) => Ok([])
		Exited(code) => Ok(["${shown} exited with ${code.to_str()}"])
		Signaled(signal) => Ok(["${shown} ended by signal ${signal.to_str()}"])
	}
}

compare_str : Str, Str -> [Before, Same, After]
compare_str = |a, b| compare_bytes(a.to_utf8(), b.to_utf8())

compare_bytes : List(U8), List(U8) -> [Before, Same, After]
compare_bytes = |a, b|
	match (a, b) {
		([], []) => Same
		([], _) => Before
		(_, []) => After
		([x, .. as xs], [y, .. as ys]) => if (x < y) Before else if (x > y) After else compare_bytes(xs, ys)
	}

note! : Str => {}
note! = |line| Stdout.line!(line) ?? {}

warn! : Str => {}
warn! = |line| Stderr.line!(line) ?? {}
