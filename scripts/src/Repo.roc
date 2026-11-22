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

	## The engine modules, copies of roc-signals. They change here only
	## through the patch series in `Repo.engine_patches`, and are never
	## reformatted; `tests/engine-modules.sha256` holds their pristine
	## digests.
	engine_modules : List(Str)
	engine_modules = ["Core", "Engine", "Web", "EntryRoutes", "Url", "ReadyIndex", "Spelling", "Layout", "TableCore", "View", "Seq", "MarkupAdvice", "SignalCore"].map(|name| "platform/${name}.roc")

	## The directory of the engine's patch series, and the README that
	## lists it in order.
	engine_patches : Str
	engine_patches = "patches/roc-signals"

	## The patches a series README lists, in order: the first backquoted
	## `*.patch` name on each line that starts an ordered-list item (`. `).
	listed_patches : Str -> List(Str)
	listed_patches = |readme|
		readme.split_on("\n").keep_oks(
			|line|
				if line.starts_with(". `") {
					match line.split_on("`") {
						[_, name, ..] if name.ends_with(".patch") => Ok(name)
						_ => Err(NotAPatch)
					}
				} else {
					Err(NotAPatch)
				},
		)

	## What is wrong with the series: `present` are the `*.patch` files in
	## the directory, in name order, and `listed` what the README lists.
	## Each patch is named `NNNN-name.patch`, numbered from 0001 with no
	## gap, and the README lists exactly those, in that order.
	series_problems : List(Str), List(Str) -> List(Str)
	series_problems = |present, listed| {
		dir = Repo.engine_patches
		unlisted = present.keep_if(|name| !listed.contains(name)).map(|name| "${dir}/${name} is not in ${dir}/README.adoc's list: add it, with its upstream status")
		absent = listed.keep_if(|name| !present.contains(name)).map(|name| "${dir}/README.adoc lists ${name}, which is not in ${dir}")
		misnumbered = present.map_with_index(|name, index| (name, index)).keep_oks(
			|(name, index)| {
				expected = Repo.left_pad((index + 1).to_str(), 4).replace_each(" ", "0")
				if (name.starts_with("${expected}-")) Err(Fine) else Ok("${dir}/${name} is patch ${(index + 1).to_str()} of the series: name it ${expected}-<name>.patch")
			},
		)
		order = if (unlisted.is_empty() and absent.is_empty() and listed != present) ["${dir}/README.adoc lists the patches out of order: list them in name order"] else []
		unlisted.concat(absent).concat(misnumbered).concat(order)
	}

	## What differs between the pristine digests `tests/engine-modules.sha256`
	## records and `computed`, `shasum -a 256` of the modules after the
	## series was reverse-applied to copies of them under `stage`.
	digest_problems : Str, Str, Str -> List(Str)
	digest_problems = |recorded, computed, stage| {
		digests = |text, prefix|
			text.split_on("\n").keep_oks(
				|line|
					match line.split_on("  ") {
						[digest, path] if path.starts_with(prefix) => Ok({ digest, path: path.drop_prefix(prefix) })
						_ => Err(NotADigest)
					},
			)
		after = digests(computed, stage)
		digests(recorded, "").keep_oks(
			|{ digest, path }|
				match after.find_first(|entry| entry.path == path) {
					Ok(entry) if entry.digest == digest => Err(Same)
					Ok(_) => Ok("${path} is not roc-signals' file plus ${Repo.engine_patches}: change an engine module only through a recorded patch (${Repo.engine_patches}/README.adoc)")
					Err(_) => Ok("${path} has no computed digest")
				},
		)
	}

	## Every script, whose `expect`s the scripts stage runs.
	scripts : List(Str)
	scripts = ["scripts/check_all.roc", "scripts/build.roc", "scripts/link_inputs.roc", "scripts/bundle.roc", "scripts/release.roc", "scripts/record_demos.roc", "scripts/workflow.roc"]

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

expect Repo.engine_modules.len() == 13

series_readme : Str
series_readme = "= Engine patches\n\n. `0001-first.patch`: one. Upstream: not yet sent.\n. `0002-second.patch`: two. Upstream: https://example.invalid/1\n\nText naming `0003-other.patch` is no item.\n"

expect Repo.listed_patches(series_readme) == ["0001-first.patch", "0002-second.patch"]
expect Repo.series_problems(["0001-first.patch", "0002-second.patch"], Repo.listed_patches(series_readme)) == []
expect Repo.series_problems([], []) == []

## An unlisted patch, a listed one that is missing, a gap in the numbers.
expect
	Repo.series_problems(["0001-first.patch", "0003-third.patch"], ["0001-first.patch", "0002-second.patch"])
		== [
			"patches/roc-signals/0003-third.patch is not in patches/roc-signals/README.adoc's list: add it, with its upstream status",
			"patches/roc-signals/README.adoc lists 0002-second.patch, which is not in patches/roc-signals",
			"patches/roc-signals/0003-third.patch is patch 2 of the series: name it 0002-<name>.patch",
		]

expect Repo.series_problems(["0001-a.patch", "0002-b.patch"], ["0002-b.patch", "0001-a.patch"]) == ["patches/roc-signals/README.adoc lists the patches out of order: list them in name order"]

digests_recorded : Str
digests_recorded = "aaa  platform/Core.roc\nbbb  platform/Web.roc\n"

expect Repo.digest_problems(digests_recorded, "aaa  build/x/platform/Core.roc\nbbb  build/x/platform/Web.roc\n", "build/x/") == []
expect
	Repo.digest_problems(digests_recorded, "aaa  build/x/platform/Core.roc\nccc  build/x/platform/Web.roc\n", "build/x/")
		== ["platform/Web.roc is not roc-signals' file plus patches/roc-signals: change an engine module only through a recorded patch (patches/roc-signals/README.adoc)"]
expect Repo.digest_problems(digests_recorded, "aaa  build/x/platform/Core.roc\n", "build/x/") == ["platform/Web.roc has no computed digest"]

expect Repo.paint("PASS", Bool.False) == "PASS"
expect Repo.paint("PASS", Bool.True) == "\u(001b)[32mPASS\u(001b)[0m"
expect Repo.paint("failed", Bool.True) == "\u(001b)[31mfailed\u(001b)[0m"
expect Repo.paint("SKIP", Bool.True) == "\u(001b)[33mSKIP\u(001b)[0m"

expect Repo.fmt_skip("platform/Core.roc") == Err(Checked)
expect Repo.fmt_skip("examples/todos/main.roc") == Err(Checked)

expect (Repo.millis(12), Repo.millis(1204), Repo.millis(10000), Repo.millis(1002003)) == ("12ms", "1_204ms", "10_000ms", "1_002_003ms")

expect Repo.progress({ index: 3, total: 20, name: "counter/increment", outcome: "PASS", ms: 1204 }) == " [ 3/20] counter/increment ..................... PASS   1_204ms"
