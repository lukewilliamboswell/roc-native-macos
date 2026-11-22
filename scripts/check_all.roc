#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	roc: "nightly-2026-11-14-a87808d",
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
import src/Release
import src/Repo

## The `check` task, the pull-request gate: `blueprint run check` runs every
## stage, and `blueprint run check -- STAGE...` the named ones, in order.
##
## - `pins`: only the scripts pin a compiler, and they pin `roc-stable`
##   (`roc-policy check`, from Blueprint.roc's `repository_policy`).
## - `engine`: the engine modules are roc-signals' (their recorded digests)
##   plus the patch series in `patches/roc-signals`, and nothing else.
## - `fmt`: `roc fmt --check` over the platform, glue, examples and the
##   `macos.roc` tool (`cli/`), and `roc-stable fmt --check` over the scripts.
## - `scripts`: the scripts' `expect` tests.
## - `tool`: `cli/Bundle.roc` is what `scripts/src/Release.roc` generates for
##   a checkout (`tool --update` writes it), `scripts/src/Recorded.roc` is a
##   copy of `cli/Recorded.roc`, and `roc test` on the tool.
## - `glue`: the committed glue in host/ is what `glue/SwiftGlue.roc`
##   generates with the `roc` on PATH (`scripts/build.roc -- glue --check`).
## - `build`: `scripts/build.roc`, with the latest nightly as `roc`: the host
##   (reused when its fingerprint matches), the linker inputs and every
##   example.
## - `test`: `roc test` on the platform root and on every example.
## - `examples`: every example's recorded scripted runs; `examples --update`
##   records what they print now.
## - `bench`: every harness under `bench/` (`bench/<name>/run.sh --smoke`),
##   built and run at a token size, so it never goes stale.
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
		"engine" => engine!()
		"fmt" => fmt!(colour)
		"tool" => tool!(update)
		"scripts" => scripts!()
		"glue" => run!("roc-stable", ["scripts/build.roc", "--", "glue", "--check"])
		"build" => build!()
		"test" => test!()
		"examples" => examples!(update, colour)
		"bench" => bench!()
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

## The engine modules are the roc-signals copies plus the patch series in
## `patches/roc-signals`, and nothing else: reverse-applying the series,
## last patch first, to copies of them under `build/engine-check` gives
## back the pristine digests `tests/engine-modules.sha256` records.
engine! : () => Try(List(Str), _)
engine! = || {
	recorded = Path.read_utf8!(Path.utf8("tests/engine-modules.sha256"))?
	missing = Repo.engine_modules.keep_if(|path| !recorded.contains("  ${path}\n")).map(|path| "tests/engine-modules.sha256 records no digest for ${path}")
	dir = Repo.engine_patches
	present = Path.list!(Path.utf8(dir))?.keep_oks(|path| Path.filename(path).map_ok(Path.display)).keep_if(|name| name.ends_with(".patch")).sort_with(compare_str)
	series = Repo.series_problems(present, Repo.listed_patches(Path.read_utf8!(Path.utf8("${dir}/README.adoc"))?))
	if !(missing.is_empty() and series.is_empty()) {
		return Ok(missing.concat(series))
	}
	stage = "build/engine-check"
	if Path.exists!(Path.utf8(stage))? {
		Path.delete_all!(Path.utf8(stage))?
	}
	Path.create_all!(Path.utf8("${stage}/platform"))?
	for path in Repo.engine_modules {
		Path.copy!(Path.utf8(path), Path.utf8("${stage}/${path}"))?
	}
	for name in present.sort_with_reversed(compare_str) {
		# `-d` first: `patch` reads the file relative to the stage.
		reversed = run!("patch", ["-s", "-t", "-R", "-p1", "-d", stage, "-i", "../../${dir}/${name}"])?
		if !reversed.is_empty() {
			return Ok(["${dir}/${name} does not reverse-apply to the engine modules: they differ from roc-signals' files plus the series (${dir}/README.adoc)"])
		}
	}
	computed = Cmd.new("shasum").args(["-a", "256"].concat(Repo.engine_modules.map(|path| "${stage}/${path}")).map(OsStr.from_str)).capture!()?
	note!("${present.len().to_str()} engine patches reverse-apply to roc-signals' files")
	Ok(Repo.digest_problems(recorded, computed, "${stage}/"))
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
	cases = Path.list!(Path.utf8("tests/examples/counter"))?.keep_oks(|path| Path.filename(path).map_ok(Path.display))
	generated = Release.development_bundle(cases)
	if update {
		Path.write_utf8!(Path.utf8("cli/Bundle.roc"), generated)?
		note!("wrote cli/Bundle.roc")
	} else if Path.read_utf8!(Path.utf8("cli/Bundle.roc"))? != generated {
		$problems = $problems.append("cli/Bundle.roc is not what scripts/src/Release.roc generates for this checkout (the counter's recorded cases may have changed): run `blueprint run check -- tool --update` and review the diff")
	}
	if Path.read_utf8!(Path.utf8("cli/Recorded.roc"))? != Path.read_utf8!(Path.utf8("scripts/src/Recorded.roc"))? {
		$problems = $problems.append("scripts/src/Recorded.roc differs from cli/Recorded.roc, which it must copy byte for byte: change cli/Recorded.roc, then copy it over")
	}
	Ok($problems.concat(run!("roc", ["test", "cli/main.roc"])?))
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
## `run.sh --smoke`, which fails unless the run does what it measures.
bench! : () => Try(List(Str), _)
bench! = || {
	harnesses = tracked!(["bench"])?.keep_if(|path| path.ends_with("/run.sh"))
	var $problems = []
	for script in harnesses {
		$problems = $problems.concat(run_with!(Cmd.new("bash").args([script, "--smoke"].map(OsStr.from_str)).env("ROC", "roc"), "${script} --smoke")?)
	}
	Ok($problems)
}

## The examples: every directory under `examples/` with a `main.roc`.
examples_present! : () => Try(List(Str), _)
examples_present! = || {
	roots = tracked!(["examples"])?.keep_if(|path| path.ends_with("/main.roc"))
	Ok(roots.keep_oks(|path| path.drop_prefix("examples/").split_on("/").first()))
}

## Every recorded case of every example: the built app, run with the case's
## `ROC_SCRIPT` steps, must exit 0 having printed exactly the recorded output.
examples! : Bool, Bool => Try(List(Str), _)
examples! = |update, colour| {
	var $cases = []
	var $problems = []
	for example in examples_present!()? {
		dir = "tests/examples/${example}"
		files = if Path.is_dir!(Path.utf8(dir)) ?? Bool.False {
			Path.list!(Path.utf8(dir))?.keep_oks(|path| Path.filename(path).map_ok(Path.display))
		} else {
			[]
		}
		names = files.keep_oks(Recorded.case_name).sort_with(compare_str)
		if names.is_empty() {
			$problems = $problems.append("examples/${example} has no recorded case: add ${dir}/<case>.script, then run `blueprint run examples -- --update`")
		}
		for name in names {
			$cases = $cases.append({ example, name, base: "${dir}/${name}" })
		}
	}
	note!("Running ${$cases.len().to_str()} cases${if (update) ", recording their output" else ""}")
	start = Monotonic.now!()
	var $index = 0
	var $passed = 0
	for case in $cases {
		$index = $index + 1
		case_start = Monotonic.now!()
		outcome = run_case!(case, update)?
		ms = Monotonic.elapsed!(case_start).to_millis()
		label = match outcome {
			Ok(Passed) => "PASS"
			Ok(Recorded) => "SAVE"
			Err(_) => "FAIL"
		}
		note!(Repo.progress({ index: $index, total: $cases.len(), name: "${case.example}/${case.name}", outcome: Repo.paint(label, colour), ms }))
		match outcome {
			Ok(_) => {
				$passed = $passed + 1
			}
			Err(problem) => {
				$problems = $problems.append("${case.example}/${case.name}: ${problem}")
			}
		}
	}
	note!("Summary: ${$passed.to_str()} passed, ${($cases.len() - $passed).to_str()} failed in ${Repo.millis(Monotonic.elapsed!(start).to_millis())}")
	Ok($problems)
}

run_case! : { example : Str, name : Str, base : Str }, Bool => Try(Try([Passed, Recorded], Str), _)
run_case! = |{ example, base, .. }, update| {
	exe = "examples/${example}/${example}"
	if !(Path.exists!(Path.utf8(exe))?) {
		return Ok(Err("${exe} is not built: run `blueprint run build` first"))
	}
	steps = Path.read_utf8!(Path.utf8("${base}.script"))?.trim()
	result = Cmd.new(OsStr.from_str(exe))
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
	root = Env.cwd!().map_ok(|cwd| cwd.display()) ?? ""
	printed = Recorded.portable(Str.from_utf8_lossy(output.stdout_bytes), root, "<repo>")
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
