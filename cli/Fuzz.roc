import cli.Cmd
import cli.OsStr
import cli.Path
import cli.Stdout
import cli.System
import App

## `fuzz [--check] [--time SECONDS] [TARGET...]`: build the app's fuzz
## targets and run them.
##
## `fuzz/main.roc` is an app on roc-fuzz's platform
## (https://github.com/lukewilliamboswell/roc-fuzz) that imports the app's
## pure logic package and declares properties of it. `roc build --fuzz`
## builds it into one program, `.macos/fuzz`, which runs on Apple silicon
## Macs and on Linux x64, wherever roc-fuzz does. Each target either runs
## for a while, exploring inputs with coverage feedback and keeping those
## worth revisiting in `.roc-fuzz/corpus/<target>` (by default), or, with
## `--check`, checks only the examples it declares, quickly, as CI does. A
## failure prints its report, and leaves it and the failing input under
## `.roc-fuzz/`.
Fuzz := [].{

	## Where an app keeps its fuzz targets.
	source : Str
	source = "fuzz/main.roc"

	## The program `roc build --fuzz` writes, in the build directory.
	program : Str
	program = "${App.work}/fuzz"

	## Where each target keeps the inputs it found worth revisiting.
	corpus : Str
	corpus = ".roc-fuzz/corpus"

	## What the user asked for: only the declared examples (`--check`), or
	## each target explored for `seconds`; all targets, or those `names`d.
	Options : { check : Bool, seconds : U64, names : List(Str) }

	## Ten seconds a target: long enough to find a shallow mistake, short
	## enough to run after each change.
	defaults : Options
	defaults = { check: Bool.False, seconds: 10, names: [] }

	## The options on `fuzz`'s command line.
	options : List(Str), Options -> Try(Options, [UnexpectedArguments({ command : Str, extra : List(Str) })])
	options = |args, found|
		match args {
			[] => Ok(found)
			["--check", .. as rest] => Fuzz.options(rest, { ..found, check: Bool.True })
			["--time", seconds, .. as rest] =>
				match U64.from_str(seconds) {
					Ok(n) if n > 0 => Fuzz.options(rest, { ..found, seconds: n })
					_ => Err(UnexpectedArguments({ command: "fuzz", extra: args }))
				}
			[name, .. as rest] if !name.starts_with("-") => Fuzz.options(rest, { ..found, names: found.names.append(name) })
			extra => Err(UnexpectedArguments({ command: "fuzz", extra }))
		}

	## Build the targets, then run the chosen ones in turn.
	run! : Options => Try({}, _)
	run! = |chosen| {
		if !(Path.exists!(Path.utf8(Fuzz.source))?) {
			return Err(NoFuzzTargets)
		}
		match Fuzz.supported(System.target!()) {
			Ok({}) => {}
			Err(here) => return Err(FuzzNotHere(here))
		}
		if !Cmd.check_available!("roc") {
			return Err(RocMissing)
		}
		Path.create_all!(Path.utf8(App.work))?
		Stdout.line!("Building ${Fuzz.source} with roc-fuzz...")?
		built = Cmd.new("roc").args(["build", "--fuzz", Fuzz.source, "--output=${Fuzz.program}"].map(OsStr.from_str)).inherit_stdio().run!()?
		if built.status != Exited(0) {
			return Err(BuildFailed)
		}
		printed = Cmd.new(OsStr.from_str(Fuzz.program)).args(["--list-targets"]).capture!()?
		names = Fuzz.pick(Fuzz.listed(printed), chosen.names)?
		Stdout.line!(if (chosen.check) "Checking the declared examples of ${Fuzz.counted(names.len())}..." else "Fuzzing ${Fuzz.counted(names.len())} for ${chosen.seconds.to_str()} seconds each...")?
		var $failed = []
		for name in names {
			args = if (chosen.check) ["--target=${name}", "check"] else ["--target=${name}", "run", "${Fuzz.corpus}/${name}", "--time=${chosen.seconds.to_str()}"]
			ran = Cmd.new(OsStr.from_str(Fuzz.program)).args(args.map(OsStr.from_str)).inherit_stdio().run!()?
			if ran.status != Exited(0) {
				$failed = $failed.append(name)
			}
		}
		if $failed.is_empty() {
			Stdout.line!(if (names.len() == 1) "The fuzz target passed." else "All ${Fuzz.counted(names.len())} passed.")?
			Ok({})
		} else {
			Err(FuzzFailed({ failed: $failed, total: names.len() }))
		}
	}

	## A count of fuzz targets, for a sentence.
	counted : U64 -> Str
	counted = |n| if (n == 1) "1 fuzz target" else "${n.to_str()} fuzz targets"

	## The target names `--list-targets` printed, one a line.
	listed : Str -> List(Str)
	listed = |printed| printed.split_on("\n").map(Str.trim).drop_if(Str.is_empty)

	## The targets to run: every one, or those named, which must exist.
	pick : List(Str), List(Str) -> Try(List(Str), [UnknownFuzzTargets({ unknown : List(Str), known : List(Str) })])
	pick = |known, named| {
		unknown = named.drop_if(|name| known.contains(name))
		if !unknown.is_empty() {
			Err(UnknownFuzzTargets({ unknown, known }))
		} else if named.is_empty() {
			Ok(known)
		} else {
			Ok(named)
		}
	}

	## Whether roc-fuzz runs here: on an Apple silicon Mac or on Linux x64.
	## Otherwise, the system's name for a sentence.
	supported : System.Target -> Try({}, Str)
	supported = |target|
		match (target.os(), target.arch()) {
			(MacOS(_), Arm64) => Ok({})
			(Linux(_), X64) => Ok({})
			(MacOS(_), X64) => Err("an Intel Mac")
			(Linux(_), _) => Err("Linux on ARM")
			(Windows(_), _) => Err("Windows")
		}
}

expect Fuzz.options([], Fuzz.defaults) == Ok(Fuzz.defaults)
expect Fuzz.options(["--check", "money-parse", "--time", "30"], Fuzz.defaults) == Ok({ check: Bool.True, seconds: 30, names: ["money-parse"] })
expect Fuzz.options(["--time", "0"], Fuzz.defaults) == Err(UnexpectedArguments({ command: "fuzz", extra: ["--time", "0"] }))
expect Fuzz.options(["--time"], Fuzz.defaults) == Err(UnexpectedArguments({ command: "fuzz", extra: ["--time"] }))

expect Fuzz.listed("money-round-trip\nmoney-parse\n\n") == ["money-round-trip", "money-parse"]

## Naming targets runs only those; naming one that is not there runs none.
expect Fuzz.pick(["a", "b"], []) == Ok(["a", "b"]) and Fuzz.pick(["a", "b"], ["b"]) == Ok(["b"])
expect Fuzz.pick(["a", "b"], ["c", "a"]) == Err(UnknownFuzzTargets({ unknown: ["c"], known: ["a", "b"] }))
