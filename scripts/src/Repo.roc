## The pure decisions of the check script: which files are formatted, how
## stages are chosen and how results print.
Repo := [].{

	## The check's stages, in the order a full run takes them.
	stages : List(Str)
	stages = ["pins", "engine", "fmt", "scripts", "specs", "tool", "glue", "build", "test", "examples", "bench", "matrix", "bundle"]

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

	## Where an example or a bench harness keeps its specs, relative to its
	## directory; the files they use are in `tests/fixtures/`, and the
	## starter's fuzz targets in `tests/fuzz/main.roc`.
	specs : Str
	specs = "tests/specs"

	## The examples the matrix stage builds every way, the one spec it runs
	## against each build, and whether it builds them for every Mac target or
	## only for this Mac's own: `arith`, for every target, for the library
	## calls 128-bit, `Dec` and float arithmetic lower to, which differ by
	## target; `workers`, for this Mac's alone, for the worker threads' entry
	## points and a crashed job's unwind out of a guarded call, which do not.
	## TODO(slow-lambda-sets): `workers` takes 80 to 140 s a build with
	## `--specialize=yes`; build it for every target too once that is fast.
	matrix_examples : List({ name : Str, spec : Str, every_target : Bool })
	matrix_examples = [{ name: "arith", spec: "${Repo.specs}/rows.scm", every_target: Bool.True }, { name: "workers", spec: "${Repo.specs}/crash.scm", every_target: Bool.False }]

	## One build of the matrix: a target, an `--opt` and a `--specialize`,
	## and whether this Mac runs what it builds.
	MatrixBuild : { target : Str, opt : Str, specialize : Str, run : Bool }

	## Every build of the matrix on a Mac whose own target is `native` and
	## which runs the programs of the targets `runs` names: every Mac target
	## with every `--opt` and `--specialize`, run when the Mac runs its
	## programs and linked only otherwise. `--opt=interpreter` builds only
	## for the native target, as roc allows.
	matrix : { native : Str, runs : List(Str) } -> List(MatrixBuild)
	matrix = |{ native, runs }| {
		var $builds = []
		for target in ["arm64mac", "x64mac", "x64v1mac"] {
			opts = if (target == native) ["speed", "size", "dev", "interpreter"] else ["speed", "size", "dev"]
			for opt in opts {
				for specialize in ["yes", "no"] {
					$builds = $builds.append({ target, opt, specialize, run: runs.contains(target) })
				}
			}
		}
		$builds
	}

	## The targets a Mac runs the programs of: its own, and `x64v1mac` on an
	## Intel Mac or under Rosetta. An `x64mac` program needs x86-64-v3, which
	## Rosetta does not offer (its CPU reports no AVX2 or BMI2), so it runs
	## only on an Intel Mac.
	matrix_runs : { intel : Bool, rosetta : Bool } -> { native : Str, runs : List(Str) }
	matrix_runs = |{ intel, rosetta }|
		if intel {
			{ native: "x64mac", runs: ["x64mac", "x64v1mac"] }
		} else if rosetta {
			{ native: "arm64mac", runs: ["arm64mac", "x64v1mac"] }
		} else {
			{ native: "arm64mac", runs: ["arm64mac"] }
		}

	## `roc build`'s flags for one build of the matrix.
	matrix_flags : MatrixBuild -> List(Str)
	matrix_flags = |{ target, opt, specialize, .. }| ["--target=${target}", "--opt=${opt}", "--specialize=${specialize}"]

	## The program one build of an example writes, under `build/matrix/`.
	matrix_name : Str, MatrixBuild -> Str
	matrix_name = |example, { target, opt, specialize, .. }| "${example}-${target}-${opt}-specialize-${specialize}"

	## The tool's modules the scripts use, each copied byte for byte into
	## `scripts/src/` (a script cannot import a module outside its own
	## directory): `check`'s tool stage fails when a copy differs.
	shared_modules : List(Str)
	shared_modules = ["Spec.roc", "SpecRun.roc"]

	## Every script, whose `expect`s the scripts stage runs.
	scripts : List(Str)
	scripts = ["scripts/check_all.roc", "scripts/build.roc", "scripts/link_inputs.roc", "scripts/bundle.roc", "scripts/release.roc", "scripts/record_demos.roc", "scripts/workflow.roc", "scripts/audio_fixtures.roc", "scripts/lower_spec.roc"]

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
			"PASS" | "LINK" | "passed" => "32"
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

expect Repo.matrix({ native: "arm64mac", runs: ["arm64mac"] }).len() == 20
expect Repo.matrix(Repo.matrix_runs({ intel: Bool.True, rosetta: Bool.False })).keep_if(|b| b.run).map(|b| b.target).drop_if(|t| t == "x64mac" or t == "x64v1mac") == []
expect Repo.matrix(Repo.matrix_runs({ intel: Bool.False, rosetta: Bool.True })).keep_if(|b| b.opt == "interpreter").map(|b| (b.target, b.run)) == [("arm64mac", Bool.True), ("arm64mac", Bool.True)]
expect Repo.matrix(Repo.matrix_runs({ intel: Bool.False, rosetta: Bool.True })).keep_if(|b| b.target == "x64v1mac").map(|b| (b.opt, b.specialize, b.run)) == [("speed", "yes", Bool.True), ("speed", "no", Bool.True), ("size", "yes", Bool.True), ("size", "no", Bool.True), ("dev", "yes", Bool.True), ("dev", "no", Bool.True)]
expect Repo.matrix(Repo.matrix_runs({ intel: Bool.False, rosetta: Bool.False })).keep_if(|b| b.run).len() == 8
expect Repo.matrix(Repo.matrix_runs({ intel: Bool.False, rosetta: Bool.True })).keep_if(|b| b.target == "x64mac").all(|b| !b.run)
expect Repo.matrix_flags({ target: "x64mac", opt: "dev", specialize: "no", run: Bool.False }) == ["--target=x64mac", "--opt=dev", "--specialize=no"]
expect Repo.matrix_name("arith", { target: "arm64mac", opt: "size", specialize: "yes", run: Bool.True }) == "arith-arm64mac-size-specialize-yes"
expect Repo.paint("LINK", Bool.True) == "\u(001b)[32mLINK\u(001b)[0m"

expect Repo.paint("PASS", Bool.False) == "PASS"
expect Repo.paint("PASS", Bool.True) == "\u(001b)[32mPASS\u(001b)[0m"
expect Repo.paint("failed", Bool.True) == "\u(001b)[31mfailed\u(001b)[0m"
expect Repo.paint("SKIP", Bool.True) == "\u(001b)[33mSKIP\u(001b)[0m"

expect Repo.fmt_skip("platform/Ui.roc") == Err(Checked)
expect Repo.fmt_skip("examples/todos/src/main.roc") == Err(Checked)

expect (Repo.millis(12), Repo.millis(1204), Repo.millis(10000), Repo.millis(1002003)) == ("12ms", "1_204ms", "10_000ms", "1_002_003ms")

expect Repo.progress({ index: 3, total: 20, name: "counter/increment", outcome: "PASS", ms: 1204 }) == " [ 3/20] counter/increment ..................... PASS   1_204ms"
