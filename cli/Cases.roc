import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stdout
import cli.System
import App
import SpecRun

## `test [--update | --check | --metrics]`: run the app's `expect` tests,
## then build the app and run its specs.
##
## `roc test` on the app's root module runs the `expect`s of every module
## the app has, its local packages' (such as `logic/`) included. Those run
## on any system; the specs need a Mac, Apple silicon or Intel.
##
## `tests/specs/<name>.scm` holds one behaviour spec (`Spec.roc`): steps
## that drive the real controls without taking focus, and expectations of
## what the app then shows. A `(demo …)` spec is a recording, with real
## effects and waits: `--check` parses it, and a run skips it. `--update`
## rewrites each spec's `expect-dump` trees with what the run showed and
## lowers its allocation bounds, and nothing else;
## `--metrics` prints what each spec measured without judging it; `--check`
## only parses every spec, on any system.
Cases := [].{

	## Where an app keeps its specs.
	specs : Str
	specs = "tests/specs"

	run! : { update : Bool, check : Bool, metrics : Bool } => Try({}, _)
	run! = |{ update, check, metrics }| {
		entry = App.entry!()?
		checked = SpecRun.names(files!(Cases.specs)).map(|name| "${Cases.specs}/${name}")
		cases = SpecRun.tests!(".", checked)
		if cases.is_empty() and !(check and !checked.is_empty()) {
			return Err(NoCases)
		}
		if check {
			var $invalid = 0.U64
			for spec in checked {
				match SpecRun.check!(".", spec) {
					Ok({}) => {}
					Err(problem) => {
						Stdout.line!(problem)?
						$invalid = $invalid + 1
					}
				}
			}
			return if ($invalid == 0) Stdout.line!("All ${checked.len().to_str()} specs parse.") else Err(SpecsInvalid({ invalid: $invalid, total: checked.len() }))
		}
		if !Cmd.check_available!("roc") {
			return Err(RocMissing)
		}
		Stdout.line!("Running the expect tests: roc test ${entry}")?
		tested = Cmd.new("roc").args(["test", entry].map(OsStr.from_str)).inherit_stdio().run!()?
		if tested.status != Exited(0) {
			return Err(ExpectsFailed(entry))
		}
		target = match App.system(System.target!()) {
			Mac(own) => own
			Other(system) => return Err(NotAMac({ command: "test", system, bundle: "" }))
		}
		# The specs run this Mac's own program: one build, not two.
		{ program, .. } = App.compile!(Native(target))?
		root = Env.cwd!()?.display()
		total = cases.len()
		Stdout.line!("Running ${total.to_str()} specs${if (update) ", rewriting their dumps and allocation bounds" else ""}...")?
		var $failed = []
		for spec in cases {
			ran = SpecRun.run!({ program: "${root}/${program}", dir: root, spec, update, metrics, args: [], env: [] })?
			match ran {
				Measured(lines) => {
					Stdout.line!("MEASURE ${spec}")?
					for line in lines {
						Stdout.line!("  ${line}")?
					}
				}
				Passed => Stdout.line!("PASS ${spec}")?
				Updated => Stdout.line!("SAVE ${spec}")?
				Failed(problems) => {
					Stdout.line!("FAIL ${spec}")?
					for problem in problems {
						Stdout.line!("  ${problem}")?
					}
					$failed = $failed.append(spec)
				}
			}
		}
		if metrics {
			Stdout.line!("Measured ${total.to_str()} specs: set a spec's bounds from what it measured, such as (expect-allocations-at-most N), and `--update` lowers them as the app improves.")?
			return Ok({})
		}
		if $failed.is_empty() {
			Stdout.line!(if (update) "Ran ${total.to_str()}, rewriting what they showed: review the change to tests/specs/ before you commit it." else "All ${total.to_str()} passed.")?
			Ok({})
		} else {
			Err(CasesFailed({ failed: $failed, total }))
		}
	}
}

## The file names in a directory, or none if it cannot be listed.
files! : Str => List(Str)
files! = |dir|
	match Path.list!(Path.utf8(dir)) {
		Ok(paths) => paths.keep_oks(|path| Path.filename(path).map_ok(Path.display))
		Err(_) => []
	}
