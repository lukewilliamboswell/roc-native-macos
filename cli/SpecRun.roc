import cli.Cmd
import cli.Duration
import cli.OsStr
import cli.Path
import Spec

## Run one spec (`Spec.roc`) against a built program: lower its steps into
## `ROC_SPEC`, run the program from the app's directory, and judge what it
## printed. `macos.roc test` runs an app's specs with it, and the
## repository's scripts their examples'.
##
## `scripts/src/SpecRun.roc` is a byte-identical copy of `cli/SpecRun.roc`,
## and `check` fails when the two differ. Change this one, then copy it.
SpecRun := [].{

	## What a spec came to: it passed, `--update` rewrote its dumps or
	## lowered its allocation bounds (and everything else held), why it
	## failed, one line per problem, or with `metrics` what it measured, one
	## line per step that expects a metric and one for the whole run.
	Outcome : [Passed, Updated, Failed(List(Str)), Measured(List(Str))]

	## How to run it: the program, the app's directory it runs from, the
	## spec's path relative to that directory, whether to rewrite its dumps
	## and bounds, whether only to report what it measured, and the
	## program's arguments and extra environment.
	Run : { program : Str, dir : Str, spec : Str, update : Bool, metrics : Bool, args : List(Str), env : List((Str, Str)) }

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
	run! = |{ program, dir, spec, update, metrics, args, env }| {
		path = Path.utf8("${dir}/${spec}")
		source = Path.read_utf8!(path)?
		parsed = match Spec.parse(source) {
			Ok(p) => p
			Err(problem) => return Ok(Failed([SpecRun.located(spec, problem)]))
		}
		command = Cmd.new(OsStr.from_str(program))
			.args(args.map(OsStr.from_str))
			.cwd(Path.utf8(dir))
			.env("ROC_SPEC", OsStr.from_str(if (metrics) Spec.lower_measured(parsed) else Spec.lower(parsed)))
			.env("TZ", "UTC")
			.envs(env.map(|(k, v)| (OsStr.from_str(k), OsStr.from_str(v))))
			.stdin(Null)
			.timeout(Duration.seconds(120))
		output = match command.run!() {
			Ok(done) => done
			Err(CmdErr(error)) => return Ok(Failed(["${spec}: the app did not finish: ${Str.inspect(error)}"]))
			Err(Interrupted) => return Ok(Failed(["${spec}: interrupted"]))
		}
		printed = SpecRun.portable(Str.from_utf8_lossy(output.stdout_bytes), dir, "<app>")
		run = Spec.read_run(printed)
		if metrics {
			return Ok(Measured(Spec.measure(parsed, run).map(|{ pos, text }| SpecRun.located(spec, { pos, message: text }))))
		}
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

	## What the host printed with the absolute path `root` (where the spec
	## ran) written `placeholder`, so a dump does not depend on where it ran
	## (a file's URL, for example). Where the path showed, the window's size
	## depends on it too, so a dump's `(window :width W :height H` becomes
	## `(window :width _ :height _`, which matches any size.
	portable : Str, Str, Str -> Str
	portable = |printed, root, placeholder|
		if root.is_empty() or !printed.contains(root) {
			printed
		} else {
			lines = Str.join_with(printed.split_on(root), placeholder)
				.split_on("\n")
				.map(|line| if (line.starts_with("|(window :width ")) Str.join_with(line.split_on(" ").map_with_index(|w, i| if (i == 2 or i == 4) "_${undigit(w)}" else w), " ") else line)
			Str.join_with(lines, "\n")
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

	## Whether the spec at `path` is a demo, `(demo …)`: a recording with
	## real effects and real waits, which `test` and the check parse but never
	## run. A spec that cannot be read or parsed is not a demo, so running it
	## reports why.
	is_demo! : Str => Bool
	is_demo! = |path|
		match Path.read_utf8!(Path.utf8(path)) {
			Ok(source) => Spec.parse(source).map_ok(|parsed| parsed.demo) ?? Bool.False
			Err(_) => Bool.False
		}

	## The tests among `specs`, paths relative to `dir`, in order: every one but
	## the demos.
	tests! : Str, List(Str) => List(Str)
	tests! = |dir, specs| {
		var $kept = []
		for spec in specs {
			if !SpecRun.is_demo!("${dir}/${spec}") {
				$kept = $kept.append(spec)
			}
		}
		$kept
	}
}

## A word without its leading digits: `351)` is `)`.
undigit : Str -> Str
undigit = |word| Str.from_utf8_lossy(word.to_utf8().drop_if(|c| c >= '0' and c <= '9'))

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

## The path becomes the placeholder, and the window's size a wildcard.
expect SpecRun.portable("@2 obs\n|(window :width 570 :height 351\n|  (text \"file:///Users/me/app/a.txt\")))\n", "/Users/me/app", "<app>") == "@2 obs\n|(window :width _ :height _\n|  (text \"file://<app>/a.txt\")))\n"

## Output that never printed the path is left as it was.
expect SpecRun.portable("|(window :width 360 :height 145)\n", "/home/ci", "<app>") == "|(window :width 360 :height 145)\n"

expect SpecRun.located("tests/specs/a.scm", { pos: { line: 3, column: 5 }, message: "expected one (button \"+\"), saw none" }) == "tests/specs/a.scm:3:5: expected one (button \"+\"), saw none"
