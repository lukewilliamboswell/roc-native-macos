import cli.Cmd
import cli.Duration
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stdout
import cli.System
import App
import Recorded

## `test [--update]`: run the app's `expect` tests, then build the app and
## run its recorded cases.
##
## `roc test` on the app's root module runs the `expect`s of every module
## the app has, its local packages' (such as `logic/`) included. Those run
## on any system; the recorded cases need an Apple silicon Mac.
##
## `tests/<case>.script` holds the steps of a run (`click:+;dump;quit`),
## which the platform's host performs when `ROC_SCRIPT` names them, driving
## the real controls without taking focus. `tests/<case>.expected` holds
## what the run prints. A case passes when the app exits normally having
## printed that, under `Recorded.matches`' rules, with the app's directory
## written `<app>`. `--update` records what each case prints now.
Cases := [].{

	## Where an app keeps its recorded cases.
	dir : Str
	dir = "tests"

	## What one case came to.
	Outcome : [Passed, Recorded, Failed(Str)]

	run! : Bool => Try({}, _)
	run! = |update| {
		entry = App.entry!()?
		if !Cmd.check_available!("roc") {
			return Err(RocMissing)
		}
		Stdout.line!("Running the expect tests: roc test ${entry}")?
		tested = Cmd.new("roc").args(["test", entry].map(OsStr.from_str)).inherit_stdio().run!()?
		if tested.status != Exited(0) {
			return Err(ExpectsFailed(entry))
		}
		match App.system(System.target!()) {
			AppleSilicon => {}
			Other(system) => return Err(NotAppleSilicon({ command: "test", system, bundle: "" }))
		}
		found = Cases.names(files!(Cases.dir))
		if found.is_empty() {
			return Err(NoCases)
		}
		{ program, .. } = App.compile!()?
		root = Env.cwd!()?.display()
		Stdout.line!("Running ${found.len().to_str()} recorded cases${if (update) ", recording what they print" else ""}...")?
		var $failed = []
		for name in found {
			result = case!(root, "${root}/${program}", name, update)?
			match result {
				Passed => Stdout.line!("PASS ${name}")?
				Recorded => Stdout.line!("SAVE ${name}")?
				Failed(why) => {
					Stdout.line!("FAIL ${name}: ${why}")?
					$failed = $failed.append(name)
				}
			}
		}
		if $failed.is_empty() {
			Stdout.line!(if (update) "Recorded ${found.len().to_str()} cases: review the change to tests/ before you commit it." else "All ${found.len().to_str()} recorded cases passed.")?
			Ok({})
		} else {
			Err(CasesFailed({ failed: $failed, total: found.len() }))
		}
	}

	## The cases among a directory's file names, sorted.
	names : List(Str) -> List(Str)
	names = |files| files.keep_oks(Recorded.case_name).sort_with(compare)

	## What a case came to, from what the run printed and how it ended.
	outcome : { expected : Try(Str, [Missing]), printed : Str, status : [Exited(I32), Signaled(I32)], update : Bool } -> Outcome
	outcome = |{ expected, printed, status, update }|
		match status {
			Exited(0) =>
				match expected {
					_ if update => Recorded
					Ok(text) if Recorded.matches(text, printed) => Passed
					Ok(text) => Failed("it printed something other than the recorded output:\n--- expected\n${text}--- printed\n${printed}")
					Err(Missing) => Failed("it has no recorded output yet; record it with `roc macos.roc test --update`.")
				}
			Exited(code) => Failed("it exited with code ${code.to_str()}; it printed:\n${printed}")
			Signaled(signal) => Failed("it stopped on signal ${signal.to_str()}; it printed:\n${printed}")
		}
}

## Run one case from the app's directory, with a 60-second deadline.
case! : Str, Str, Str, Bool => Try(Cases.Outcome, _)
case! = |root, program, name, update| {
	base = "${Cases.dir}/${name}"
	steps = Path.read_utf8!(Path.utf8("${base}.script"))?.trim()
	ran = Cmd.new(OsStr.from_str(program))
		.env("ROC_SCRIPT", OsStr.from_str(steps))
		.stdin(Null)
		.stderr(MergeWithStdout)
		.timeout(Duration.seconds(60))
		.run!()
	output = match ran {
		Ok(done) => done
		Err(CmdErr(error)) => return Ok(Failed("it did not finish: ${Str.inspect(error)}"))
		Err(Interrupted) => return Ok(Failed("interrupted"))
	}
	printed = Recorded.portable(Str.from_utf8_lossy(output.stdout_bytes), root, "<app>")
	expected_path = Path.utf8("${base}.expected")
	expected = if (Path.exists!(expected_path)?) Ok(Path.read_utf8!(expected_path)?) else Err(Missing)
	outcome = Cases.outcome({ expected, printed, status: output.status, update })
	if outcome == Recorded {
		Path.write_utf8!(expected_path, printed)?
	}
	Ok(outcome)
}

## The file names in a directory, or none if it cannot be listed.
files! : Str => List(Str)
files! = |dir|
	match Path.list!(Path.utf8(dir)) {
		Ok(paths) => paths.keep_oks(|path| Path.filename(path).map_ok(Path.display))
		Err(_) => []
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

expect Cases.names(["reset.expected", "reset.script", "increment.script", "notes.txt"]) == ["increment", "reset"]

## A run that printed what was recorded passes, within the tolerance.
expect Cases.outcome({ expected: Ok("--- 360x237\n"), printed: "--- 361x237\n", status: Exited(0), update: Bool.False }) == Passed

## `--update` records any run that ended normally, and never a crash.
expect Cases.outcome({ expected: Err(Missing), printed: "x\n", status: Exited(0), update: Bool.True }) == Recorded
expect Cases.outcome({ expected: Ok("x\n"), printed: "", status: Signaled(6), update: Bool.True }) != Recorded

## A case without a recording, or printing something else, fails.
expect Cases.outcome({ expected: Err(Missing), printed: "x\n", status: Exited(0), update: Bool.False }) != Passed
expect Cases.outcome({ expected: Ok("1\n"), printed: "2\n", status: Exited(0), update: Bool.False }) != Passed
