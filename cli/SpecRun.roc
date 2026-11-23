import cli.Cmd
import cli.Duration
import cli.OsStr
import cli.Path
import Recorded
import Spec

## Run one spec (`Spec.roc`) against a built program: lower its steps into
## `ROC_SPEC`, run the program from the app's directory, and judge what it
## printed. `macos.roc test` runs an app's specs with it, and the
## repository's scripts their examples'.
##
## `scripts/src/SpecRun.roc` is a byte-identical copy of `cli/SpecRun.roc`,
## and `check` fails when the two differ. Change this one, then copy it.
SpecRun := [].{

	## What a spec came to: it passed, `--update` rewrote its dumps (and
	## everything else held), or why it failed, one line per problem.
	Outcome : [Passed, Updated, Failed(List(Str))]

	## How to run it: the program, the app's directory it runs from, the
	## spec's path relative to that directory, whether to rewrite its
	## dumps, and the program's arguments and extra environment.
	Run : { program : Str, dir : Str, spec : Str, update : Bool, args : List(Str), env : List((Str, Str)) }

	## Parse a spec file, for `--check`: its problem as `file:line:col: …`.
	check! : Str, Str => Try({}, Str)
	check! = |dir, spec| {
		source = Path.read_utf8!(Path.utf8("${dir}/${spec}")) ? |_| "${spec}: could not be read"
		match Spec.parse(source) {
			Ok(_) => Ok({})
			Err(problem) => Err(SpecRun.located(spec, problem))
		}
	}

	run! : Run => Try(Outcome, _)
	run! = |{ program, dir, spec, update, args, env }| {
		path = Path.utf8("${dir}/${spec}")
		source = Path.read_utf8!(path)?
		parsed = match Spec.parse(source) {
			Ok(p) => p
			Err(problem) => return Ok(Failed([SpecRun.located(spec, problem)]))
		}
		command = Cmd.new(OsStr.from_str(program))
			.args(args.map(OsStr.from_str))
			.cwd(Path.utf8(dir))
			.env("ROC_SPEC", OsStr.from_str(Spec.lower(parsed)))
			.env("TZ", "UTC")
			.envs(env.map(|(k, v)| (OsStr.from_str(k), OsStr.from_str(v))))
			.stdin(Null)
			.timeout(Duration.seconds(120))
		output = match command.run!() {
			Ok(done) => done
			Err(CmdErr(error)) => return Ok(Failed(["${spec}: the app did not finish: ${Str.inspect(error)}"]))
			Err(Interrupted) => return Ok(Failed(["${spec}: interrupted"]))
		}
		printed = Recorded.portable(Str.from_utf8_lossy(output.stdout_bytes), dir, "<app>")
		run = Spec.read_run(printed)
		(judged, wrote) = if update {
			rewritten = Spec.update(source, parsed, run)
			if rewritten != source {
				Path.write_utf8!(path, rewritten)?
			}
			match Spec.parse(rewritten) {
				Ok(again) => (again, rewritten != source)
				Err(_) => (parsed, rewritten != source)
			}
		} else {
			(parsed, Bool.False)
		}
		problems = Spec.judge(judged, run).map(|problem| SpecRun.located(spec, problem))
		stopped = match output.status {
			Exited(0) => []
			Exited(code) => ["${spec}: the app exited with code ${code.to_str()}"]
			Signaled(signal) => ["${spec}: the app stopped on signal ${signal.to_str()}"]
		}
		all = problems.concat(stopped)
		if all.is_empty() {
			Ok(if (wrote) Updated else Passed)
		} else {
			Ok(Failed(all.concat(SpecRun.tail(Str.from_utf8_lossy(output.stderr_bytes)))))
		}
	}

	## A problem as `file:line:col: message`.
	located : Str, Spec.Problem -> Str
	located = |spec, { pos, message }| "${spec}:${pos.line.to_str()}:${pos.column.to_str()}: ${message}"

	## The last lines the app wrote on standard error, to say why it stopped.
	tail : Str -> List(Str)
	tail = |stderr| {
		lines = stderr.trim().split_on("\n").keep_if(|line| !line.is_empty())
		if lines.is_empty() {
			[]
		} else {
			["  the app's standard error ended:"].concat(lines.take_last(12).map(|line| "    ${line}"))
		}
	}

	## The specs among a directory's file names, sorted.
	names : List(Str) -> List(Str)
	names = |files| files.keep_if(|name| name.ends_with(".scm")).sort_with(compare)
}

compare : Str, Str -> [Before, Same, After]
compare = |a, b| compare_bytes(a.to_utf8(), b.to_utf8())

compare_bytes : List(U8), List(U8) -> [Before, Same, After]
compare_bytes = |a, b|
	match (a, b) {
		([], []) => Same
		([], _) => Before
		(_, []) => After
		([x, .. as xs], [y, .. as ys]) => if (x < y) Before else if (x > y) After else compare_bytes(xs, ys)
	}

expect SpecRun.names(["b.scm", "a.scm", "notes.txt"]) == ["a.scm", "b.scm"]

expect SpecRun.located("specs/a.scm", { pos: { line: 3, column: 5 }, message: "expected one (button \"+\"), saw none" }) == "specs/a.scm:3:5: expected one (button \"+\"), saw none"
