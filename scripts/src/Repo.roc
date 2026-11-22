## The pure decisions of the check script: which files are formatted, how
## stages are chosen and how results print.
Repo := [].{

	## The check's stages, in the order a full run takes them.
	stages : List(Str)
	stages = ["pins", "engine", "fmt", "scripts", "tool", "build", "test", "examples", "bundle"]

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

	## The engine modules, byte-identical copies of roc-signals. They are
	## never edited or reformatted here; `tests/engine-modules.sha256` holds
	## their digests.
	engine_modules : List(Str)
	engine_modules = ["Core", "Engine", "Web", "EntryRoutes", "Url", "ReadyIndex", "Spelling", "Layout", "TableCore", "View", "Seq", "MarkupAdvice", "SignalCore"].map(|name| "platform/${name}.roc")

	## Files that would pin a compiler for the whole repository, which the
	## model forbids: only the scripts' headers name one.
	stray_pins : List(Str)
	stray_pins = [".roc-version", ".github/roc-nightly.json"]

	## The sources `roc fmt --check` does not check yet, by path prefix, with
	## the reason. Each is printed as a SKIP line on every run.
	##
	## TODO: format these, then delete this list. They were written before the
	## formatter gate, and reformatting them while the concurrent feature
	## branches that edit them are open would conflict with every one of them.
	fmt_skips : List({ prefix : Str, reason : Str })
	fmt_skips = [
		{ prefix: "platform/main.roc", reason: "not yet formatted; format after the open feature branches merge" },
		{ prefix: "glue/", reason: "not yet formatted; format after the open feature branches merge" },
		{ prefix: "examples/", reason: "not yet formatted; format after the open feature branches merge" },
	]

	## Why `roc fmt --check` skips a path, if it does.
	fmt_skip : Str -> Try(Str, [Checked])
	fmt_skip = |path|
		match Repo.fmt_skips.find_first(|skip| path.starts_with(skip.prefix)) {
			Ok(skip) => Ok(skip.reason)
			Err(_) => Err(Checked)
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

expect Repo.engine_modules.len() == 13

expect Repo.fmt_skip("platform/Core.roc") == Err(Checked)
expect Repo.fmt_skip("examples/todos/main.roc").is_ok()

expect (Repo.millis(12), Repo.millis(1204), Repo.millis(10000), Repo.millis(1002003)) == ("12ms", "1_204ms", "10_000ms", "1_002_003ms")

expect Repo.progress({ index: 3, total: 20, name: "counter/increment", outcome: "PASS", ms: 1204 }) == " [ 3/20] counter/increment ..................... PASS   1_204ms"
