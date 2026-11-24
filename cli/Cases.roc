import cli.Env
import cli.Path
import cli.Stdout
import cli.System
import App
import SpecRun

## `test [--update | --check | --metrics]`: build the app and run its specs.
##
## `specs/<name>.scm` holds one behaviour spec (`Spec.roc`): steps that drive
## the real controls without taking focus, and expectations of what the app
## then shows. `--update` rewrites each spec's `expect-dump` trees with what
## the run showed and lowers its allocation bounds, and nothing else;
## `--metrics` prints what each spec measured without judging it; `--check`
## only parses every spec, on any system.
Cases := [].{

	## Where an app keeps its specs.
	specs : Str
	specs = "specs"

	run! : { update : Bool, check : Bool, metrics : Bool } => Try({}, _)
	run! = |{ update, check, metrics }| {
		if !(Path.exists!(Path.utf8("main.roc"))?) {
			return Err(NoMainRoc)
		}
		checked = SpecRun.names(files!(Cases.specs)).map(|name| "${Cases.specs}/${name}")
		if checked.is_empty() {
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
		match App.system(System.target!()) {
			AppleSilicon => {}
			Other(system) => return Err(NotAppleSilicon({ command: "test", system, bundle: "" }))
		}
		{ program, .. } = App.compile!()?
		root = Env.cwd!()?.display()
		total = checked.len()
		Stdout.line!("Running ${total.to_str()} specs${if (update) ", rewriting their dumps and allocation bounds" else ""}...")?
		var $failed = []
		for spec in checked {
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
			Stdout.line!(if (update) "Ran ${total.to_str()}, rewriting what they showed: review the change to specs/ before you commit it." else "All ${total.to_str()} passed.")?
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
