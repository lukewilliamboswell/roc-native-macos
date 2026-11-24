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
## - `fmt`: `roc fmt --check` over the platform, glue, examples, the matrix
##   fixtures (`tests/matrix/`) and the `macos.roc` tool (`cli/`), and
##   `roc-stable fmt --check` over the scripts.
## - `scripts`: the scripts' `expect` tests.
## - `specs`: every spec under `examples/`, `bench/` and `tests/matrix/` parses
##   (`Spec.parse`), on any system, demos (`(demo …)`) included.
## - `tool`: `cli/Bundle.roc` is what `scripts/src/Release.roc` generates for
##   a checkout (`tool --update` writes it), `scripts/src/Spec.roc` and
##   `SpecRun.roc` are copies of the tool's, and `roc test` on the tool.
## - `glue`: the committed glue in host/ is what `glue/SwiftGlue.roc`
##   generates with the `roc` on PATH (`scripts/build.roc -- glue --check`).
## - `build`: `scripts/build.roc`, with the latest nightly as `roc`: the host
##   (reused when its fingerprint matches), the linker inputs and every
##   example.
## - `test`: `roc test` on the platform root and on every example (its
##   `src/main.roc`, which also runs its logic package's
##   `expect`s), and for an example with `tests/fuzz/main.roc`, the roc-fuzz build
##   of it and `check` on each of its targets (except on an Intel Mac, which
##   roc-fuzz has no target for).
## - `examples`: every example's specs (`examples/<name>/tests/specs/*.scm`
##   but its demos, or
##   only the examples `EXAMPLES="counter todos"` names; `METRICS=1` prints
##   what each measured instead of judging it); `examples --update`
##   rewrites their dumps and lowers their allocation bounds. Then the
##   counter's first spec once more through Roc's run mode, `roc
##   src/main.roc`, which links the host with the compiler's own run shim
##   against the stubs, and must pass the same.
## - `bench`: every harness under `bench/` (`bench/<name>/run.sh --smoke`),
##   built and run at a token size, so it never goes stale, then its specs
##   (`bench/<name>/tests/specs/*.scm`): the work a turn does, counted, at two
##   sizes. Its timings are only reported.
## - `matrix`: every build an author can ask `roc build` for. Each of
##   `Repo.matrix_apps` (the fixture `tests/matrix/arith` and the example
##   `workers`) built with every `--opt` (`speed`, `size`, `dev`,
##   `interpreter`) and `--specialize` for this Mac's own target, each
##   build running the app's specs, then `arith` with every `--opt` but
##   `interpreter` (which builds only for the native target) for the other
##   Mac targets, `x64v1mac` among them: linked, and run too where this Mac
##   runs them (`x64v1mac` under Rosetta, or on an Intel Mac). Its programs
##   go to `build/matrix/`. `matrix --update` rewrites the apps' dumps from
##   each one's first build that runs.
## - `bundle`: the platform bundle from the inputs `build` made, and an
##   author's first steps against it with the `macos.roc` tool: `init`,
##   `build`, `test` and (but on an Intel Mac) `fuzz --check` the starter app
##   (`scripts/bundle.roc --prebuilt --test`).
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
		"matrix" => matrix!(update, colour)
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
	sources = tracked!(["platform", "glue", "examples", "bench", "cli", Repo.matrix_fixtures])?.keep_if(|path| path.ends_with(".roc"))
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
	note!("${$checked.len().to_str()} of ${sources.len().to_str()} platform, glue, example, fixture and tool sources checked")
	Ok(sources_fmt.concat(scripts))
}

## The `macos.roc` tool's package, `cli/`: its checked-in `Bundle.roc` is
## current, its recorded-case rules are the scripts' own, and its `expect`s
## pass. With `update`, write `cli/Bundle.roc` as generated.
tool! : Bool => Try(List(Str), _)
tool! = |update| {
	var $problems = []
	files = tracked!(Release.template_dirs)?
	generated = Release.development_bundle(files)
	if update {
		Path.write_utf8!(Path.utf8("cli/Bundle.roc"), generated)?
		note!("wrote cli/Bundle.roc")
	} else if Path.read_utf8!(Path.utf8("cli/Bundle.roc"))? != generated {
		$problems = $problems.append("cli/Bundle.roc is not what scripts/src/Release.roc generates for this checkout (a file of ${Str.join_with(Release.template_dirs, " or ")} may have been added, removed or changed): run `blueprint run check -- tool --update` and review the diff")
	}
	for name in Repo.shared_modules {
		if Path.read_utf8!(Path.utf8("cli/${name}"))? != Path.read_utf8!(Path.utf8("scripts/src/${name}"))? {
			$problems = $problems.append("scripts/src/${name} differs from cli/${name}, which it must copy byte for byte: change cli/${name}, then copy it over")
		}
	}
	Ok($problems.concat(run!("roc", ["test", "cli/main.roc"])?))
}

## Every spec under `examples/`, `bench/` and `tests/matrix/` parses, with
## its problem at its file, line and column when it does not.
specs! : () => Try(List(Str), _)
specs! = || {
	found = tracked!(["examples", "bench", Repo.matrix_fixtures])?.keep_if(|path| path.ends_with(".scm"))
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
	intel = intel!()
	for example in examples_found!()? {
		dir = "examples/${example.name}"
		$problems = $problems.concat(run!("roc", ["test", "${dir}/${example.entry}"])?)
		# An example's fuzz targets: built with roc-fuzz, and each target's
		# declared examples checked, as `macos.roc fuzz --check` does.
		# roc-fuzz has no Intel Mac target, so an Intel Mac skips them.
		if Path.exists!(Path.utf8("${dir}/tests/fuzz/main.roc"))? {
			if intel {
				note!("${dir}: roc-fuzz has no Intel Mac target, so its fuzz targets are not checked here")
			} else {
				$problems = $problems.concat(fuzz_check!(dir)?)
			}
		}
	}
	Ok($problems)
}

## Build an example's `tests/fuzz/main.roc` with roc-fuzz and run `check` on
## every target it lists, from the example's directory.
fuzz_check! : Str => Try(List(Str), _)
fuzz_check! = |dir| {
	root = Env.cwd!()?.display()
	program = "${root}/build/fuzz/${dir.drop_prefix("examples/")}"
	Path.create_all!(Path.utf8("build/fuzz"))?
	built = run_with!(Cmd.new("roc").args(["build", "--fuzz", "tests/fuzz/main.roc", "--output=${program}"].map(OsStr.from_str)).cwd(Path.utf8(dir)), "roc build --fuzz ${dir}/tests/fuzz/main.roc")?
	if !built.is_empty() {
		return Ok(built)
	}
	listed = Cmd.new(OsStr.from_str(program)).args(["--list-targets"]).capture!()?
	var $problems = []
	for name in listed.split_on("\n").map(Str.trim).drop_if(Str.is_empty) {
		$problems = $problems.concat(run_with!(Cmd.new(OsStr.from_str(program)).args([OsStr.from_str("--target=${name}"), "check"]).cwd(Path.utf8(dir)), "${dir} fuzz target ${name} check")?)
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
		for spec in SpecRun.tests!(dir, SpecRun.names(names_in!("${dir}/${Repo.specs}")).map(|file| "${Repo.specs}/${file}")) {
			outcome = SpecRun.run!({ program: "${root}/${dir}/${name}", dir: "${root}/${dir}", spec, update, metrics: measuring!(), args: [], env: [] })?
			match outcome {
				Measured(lines) => note!(Str.join_with(lines.map(|line| "${dir}/${line}"), "\n"))
				Passed => note!("PASS ${dir}/${spec}")
				Updated => note!("SAVE ${dir}/${spec}")
				Failed(problems) => {
					note!("FAIL ${dir}/${spec}")
					$problems = $problems.append("${dir}/${spec}: ${Str.join_with(problems, "\n  ")}")
				}
			}
		}
	}
	Ok($problems)
}

## The examples: every directory under `examples/` with a `src/main.roc`,
## and that entry.
examples_found! : () => Try(List({ name : Str, entry : Str }), _)
examples_found! = || Ok(Release.examples(tracked!(["examples"])?))

## The examples' names.
examples_present! : () => Try(List(Str), _)
examples_present! = || Ok(examples_found!()?.map(|example| example.name))

## Every spec of every example: the built app, run from its directory, must
## pass it.
examples! : Bool, Bool => Try(List(Str), _)
examples! = |update, colour| {
	var $cases = []
	var $problems = []
	# `EXAMPLES="counter todos"` runs only those examples' specs.
	only = (Env.var_str!(OsStr.from_str("EXAMPLES")) ?? "").split_on(" ").keep_if(|name| !name.is_empty())
	for example in examples_present!()?.keep_if(|name| only.is_empty() or only.contains(name)) {
		dir = "examples/${example}"
		specs = SpecRun.tests!(dir, SpecRun.names(names_in!("${dir}/${Repo.specs}")).map(|file| "${Repo.specs}/${file}")).map(|name| { example, name })
		if specs.is_empty() {
			$problems = $problems.append("examples/${example} has no spec: add examples/${example}/${Repo.specs}/<name>.scm, then run `blueprint run examples -- --update`")
		}
		$cases = $cases.concat(specs)
	}
	note!("Running ${$cases.len().to_str()} specs${if (update) ", rewriting their dumps and allocation bounds" else ""}")
	start = Monotonic.now!()
	var $index = 0
	var $passed = 0
	for case in $cases {
		$index = $index + 1
		case_start = Monotonic.now!()
		shown = "${case.example}/${case.name}"
		outcome = run_spec!(case, if (update) Update else Built)?
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
		match $cases.find_first(|case| case.example == "counter") {
			Ok(spec) => {
				run_start = Monotonic.now!()
				outcome = run_spec!(spec, RunMode)?
				label = if (outcome.is_ok()) "PASS" else "FAIL"
				note!(Repo.progress({ index: 1, total: 1, name: "counter/${spec.name} via roc src/main.roc", outcome: Repo.paint(label, colour), ms: Monotonic.elapsed!(run_start).to_millis() }))
				match outcome {
					Ok(_) => {}
					Err(problem) => {
						$problems = $problems.append("counter/${spec.name} via `roc src/main.roc`: ${problem}")
					}
				}
			}
			Err(_) => {
				$problems = $problems.append("the counter has no spec to run through `roc src/main.roc`")
			}
		}
	}
	Ok($problems)
}

## Every build an app author can ask `roc build` for: each of
## `Repo.matrix_apps` built with every `--opt` and `--specialize` for every
## Mac target, or for this Mac's own (`Repo.matrix`), into `build/matrix/`.
## A build for a target this Mac runs (natively, or `x64v1mac` under
## Rosetta) also runs the app's specs; the others are linked only. A link
## is where a library call the catalog does not own fails. With `update`,
## an app's first build that runs rewrites its specs' dumps, and every
## later build is judged against them.
matrix! : Bool, Bool => Try(List(Str), _)
matrix! = |update, colour| {
	root = Env.cwd!()?.display()
	intel = intel!()
	# Rosetta runs x86-64 programs on Apple silicon when it is installed.
	rosetta = !intel and match Cmd.new("arch").args(["-x86_64", "/usr/bin/true"]).stdin(Null).run!() {
		Ok(output) => output.status == Exited(0)
		Err(_) => Bool.False
	}
	machine = Repo.matrix_runs({ intel, rosetta })
	builds = Repo.matrix(machine)
	native = machine.native
	Path.create_all!(Path.utf8("build/matrix"))?
	planned = Repo.matrix_apps.map(|subject| (subject, if (subject.every_target) builds else builds.keep_if(|build| build.target == native)))
	total = planned.fold(0, |sum, (_, each)| sum + each.len())
	note!("Building ${Repo.matrix_apps.len().to_str()} apps ${total.to_str()} ways")
	start = Monotonic.now!()
	var $index = 0
	var $problems = []
	for (subject, each) in planned {
		dir = "${root}/${subject.dir}"
		var $recording = update
		for build in each {
			$index = $index + 1
			flags = Repo.matrix_flags(build)
			program = "${root}/build/matrix/${Repo.matrix_name(subject.name, build)}"
			shown = "${subject.name} ${Str.join_with(flags, " ")}"
			build_start = Monotonic.now!()
			built = Cmd.new("roc").args(["build", "src/main.roc", "--output=${program}"].concat(flags).map(OsStr.from_str)).cwd(Path.utf8(dir)).stdin(Null).run!()?
			outcome = if built.status != Exited(0) {
				Err("roc build ${Str.join_with(flags, " ")} failed (${Str.inspect(built.status)}):\n${Str.from_utf8_lossy(built.stdout_bytes)}${Str.from_utf8_lossy(built.stderr_bytes)}")
			} else if build.run {
				var $failed = []
				var $recorded = Bool.False
				for spec in subject.specs {
					match SpecRun.run!({ program, dir, spec, update: $recording, metrics: Bool.False, args: [], env: [] })? {
						Failed(problems) => {
							$failed = $failed.append("${spec}: ${Str.join_with(problems, "\n  ")}")
						}
						Updated => {
							$recorded = Bool.True
						}
						_ => {}
					}
				}
				$recording = Bool.False
				if ($failed.is_empty()) Ok(if ($recorded) "SAVE" else "PASS") else Err(Str.join_with($failed, "\n  "))
			} else {
				Ok("LINK")
			}
			label = match outcome {
				Ok(word) => word
				Err(_) => "FAIL"
			}
			note!(Repo.progress({ index: $index, total, name: shown, outcome: Repo.paint(label, colour), ms: Monotonic.elapsed!(build_start).to_millis() }))
			match outcome {
				Ok(_) => {}
				Err(problem) => {
					$problems = $problems.append("${shown}: ${problem}")
				}
			}
		}
	}
	note!("Summary: ${(total - $problems.len()).to_str()} of ${total.to_str()} builds passed in ${Repo.millis(Monotonic.elapsed!(start).to_millis())}")
	Ok($problems)
}

## Whether this is an Intel Mac.
intel! : () => Bool
intel! = || (Cmd.new("uname").args(["-m"]).capture!() ?? "").trim() == "x86_64"

## Whether `METRICS=1` asks the examples and bench stages to print what each
## spec measured, without judging it (`macos.roc test --metrics`).
measuring! : () => Bool
measuring! = || (Env.var_str!(OsStr.from_str("METRICS")) ?? "") == "1"

## The file names in a directory, or none when there is no such directory.
names_in! : Str => List(Str)
names_in! = |dir|
	if Path.is_dir!(Path.utf8(dir)) ?? Bool.False {
		(Path.list!(Path.utf8(dir)) ?? []).keep_oks(|path| Path.filename(path).map_ok(Path.display))
	} else {
		[]
	}

## One spec: the built app (`Built`), rewriting its dumps when `Update`, or
## `roc src/main.roc` in the example's directory (`RunMode`).
run_spec! : { example : Str, name : Str }, [Built, Update, RunMode] => Try(Try([Passed, Recorded], Str), _)
run_spec! = |{ example, name }, how| {
	root = Env.cwd!().map_ok(|cwd| cwd.display()) ?? "."
	dir = "${root}/examples/${example}"
	exe = "${dir}/${example}"
	if how != RunMode and !(Path.exists!(Path.utf8(exe))?) {
		return Ok(Err("examples/${example}/${example} is not built: run `blueprint run build` first"))
	}
	(program, args) = if (how == RunMode) ("roc", ["src/main.roc"]) else (exe, [])
	outcome = SpecRun.run!({ program, dir, spec: name, update: how == Update, metrics: how != RunMode and measuring!(), args, env: [] })?
	Ok(
		match outcome {
			Measured(lines) => {
				note!(Str.join_with(lines.map(|line| "examples/${example}/${line}"), "\n"))
				Ok(Passed)
			}
			Passed => Ok(Passed)
			Updated => Ok(Recorded)
			Failed(problems) => Err(Str.join_with(problems, "\n  "))
		},
	)
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
