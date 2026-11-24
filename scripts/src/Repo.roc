## The pure decisions of the check script: which files are formatted, how
## stages are chosen and how results print.
Repo := [].{

	## The check's stages, in the order a full run takes them.
	stages : List(Str)
	stages = ["pins", "engine", "fmt", "scripts", "tool", "glue", "build", "test", "examples", "bench", "bundle"]

	## The stages named on the command line, or every stage when none is.
	## `--update` is an option of the tool and examples stages, not a stage.
	selection : List(Str) -> Try({ stages : List(Str), update : Bool }, [Unknown(Str)])
	selection = |args| {
		update = args.contains("--update")
		named = args.drop_if(|arg| arg == "--" or arg == "--update")
		match named.find_first(|arg| !Repo.stages.contains(arg)) {
			Ok(unknown) => Err(Unknown(unknown))
			Err(_) =>
				if named.is_empty() {
					Ok({ stages: Repo.stages, update })
				} else {
					Ok({ stages: Repo.stages.keep_if(|stage| named.contains(stage)), update })
				}
		}
	}

	## Every script, whose `expect`s the scripts stage runs.
	scripts : List(Str)
	scripts = ["scripts/check_all.roc", "scripts/build.roc", "scripts/link_inputs.roc", "scripts/bundle.roc", "scripts/release.roc", "scripts/record_demos.roc", "scripts/workflow.roc", "scripts/audio_fixtures.roc"]

	## Files that would pin a compiler for the whole repository, which the
	## model forbids: only the scripts' headers name one.
	stray_pins : List(Str)
	stray_pins = [".roc-version", ".github/roc-nightly.json"]

	## The sources `roc fmt --check` skips, by path prefix, each printed as a
	## SKIP line on every run. Empty: every source is formatted. A skip is
	## temporary, and its reason names the issue that tracks it.
	fmt_skips : List({ prefix : Str, reason : Str })
	fmt_skips = []

	## Why `roc fmt --check` skips a path, if it does.
	fmt_skip : Str -> Try(Str, [Checked])
	fmt_skip = |path|
		match Repo.fmt_skips.find_first(|skip| path.starts_with(skip.prefix)) {
			Ok(skip) => Ok(skip.reason)
			Err(_) => Err(Checked)
		}

	## A result word, in its colour when `colour` is set: green for a pass,
	## red for a failure, yellow for a skip or a recording. The word itself
	## is always printed.
	paint : Str, Bool -> Str
	paint = |word, colour| {
		code = match word {
			"PASS" | "passed" => "32"
			"FAIL" | "failed" | "Failed" => "31"
			_ => "33"
		}
		if (colour) "\u(001b)[${code}m${word}\u(001b)[0m" else word
	}

	## A duration as whole milliseconds with digit separators: `1_204ms`.
	millis : U64 -> Str
	millis = |ms| "${Repo.separated(ms)}ms"

	separated : U64 -> Str
	separated = |n|
		if n < 1000 {
			n.to_str()
		} else {
			rest = n % 1000
			pad = if (rest < 10) "00" else if (rest < 100) "0" else ""
			"${Repo.separated(n // 1000)}_${pad}${rest.to_str()}"
		}

	## One line of a run's progress: its position, its name, its result and
	## its time, right-aligned.
	progress : { index : U64, total : U64, name : Str, outcome : Str, ms : U64 } -> Str
	progress = |{ index, total, name, outcome, ms }| {
		width = total.to_str().count_utf8_bytes()
		position = Repo.left_pad(index.to_str(), width)
		dots = Str.repeat(".", if (name.count_utf8_bytes() < 36) (38 - name.count_utf8_bytes()) else 2)
		" [${position}/${total.to_str()}] ${name} ${dots} ${outcome}${Repo.left_pad(Repo.millis(ms), 10)}"
	}

	left_pad : Str, U64 -> Str
	left_pad = |text, width| {
		len = text.count_utf8_bytes()
		if (len >= width) text else "${Str.repeat(" ", width - len)}${text}"
	}
}

expect Repo.selection([]) == Ok({ stages: Repo.stages, update: Bool.False })
expect Repo.selection(["--", "examples", "--update"]) == Ok({ stages: ["examples"], update: Bool.True })
expect Repo.selection(["test", "build"]) == Ok({ stages: ["build", "test"], update: Bool.False })
expect Repo.selection(["bogus"]) == Err(Unknown("bogus"))

expect Repo.paint("PASS", Bool.False) == "PASS"
expect Repo.paint("PASS", Bool.True) == "\u(001b)[32mPASS\u(001b)[0m"
expect Repo.paint("failed", Bool.True) == "\u(001b)[31mfailed\u(001b)[0m"
expect Repo.paint("SKIP", Bool.True) == "\u(001b)[33mSKIP\u(001b)[0m"

expect Repo.fmt_skip("platform/Ui.roc") == Err(Checked)
expect Repo.fmt_skip("examples/todos/src/main.roc") == Err(Checked)

expect (Repo.millis(12), Repo.millis(1204), Repo.millis(10000), Repo.millis(1002003)) == ("12ms", "1_204ms", "10_000ms", "1_002_003ms")

expect Repo.progress({ index: 3, total: 20, name: "counter/increment", outcome: "PASS", ms: 1204 }) == " [ 3/20] counter/increment ..................... PASS   1_204ms"
