## The pure decisions of the bundle script: its options, which files the
## platform bundle carries, and how the consumer test names the bundle.
Bundle := [].{

	## What `scripts/bundle.roc` was asked to do. `output_dir` is relative to
	## the checkout unless it starts with `/`.
	Options : { output_dir : Str, prebuilt : Bool, test : Bool }

	## The options on the command line: `--output-dir DIR` (default
	## `build/platform`), `--prebuilt` (bundle the platform inputs already
	## built, without building them first) and `--test` (build and run an
	## example against the bundle, as an app author would).
	options : List(Str) -> Try(Options, [Unknown(Str), MissingValue(Str)])
	options = |args| Bundle.parse(args.drop_if(|arg| arg == "--"), { output_dir: "build/platform", prebuilt: Bool.False, test: Bool.False })

	parse : List(Str), Options -> Try(Options, [Unknown(Str), MissingValue(Str)])
	parse = |args, found|
		match args {
			[] => Ok(found)
			["--output-dir", dir, .. as rest] => Bundle.parse(rest, { ..found, output_dir: dir })
			["--output-dir"] => Err(MissingValue("--output-dir"))
			["--prebuilt", .. as rest] => Bundle.parse(rest, { ..found, prebuilt: Bool.True })
			["--test", .. as rest] => Bundle.parse(rest, { ..found, test: Bool.True })
			[other, ..] => Err(Unknown(other))
		}

	## The native inputs the bundle carries, relative to `platform/`: the
	## Swift host and the generated linker stubs (`targets/macos-sysroot`).
	host_library : Str
	host_library = "targets/arm64mac/libhost.a"

	sysroot : Str
	sysroot = "targets/macos-sysroot"

	## The notices every bundle carries beside the platform sources, copied
	## from the checkout's root.
	notices : List(Str)
	notices = ["LICENSE", "THIRD_PARTY_LICENSES.md"]

	## The files `roc bundle` packs, relative to the staged platform: the
	## root module first, then the other modules, the target files and the
	## notices, each group sorted.
	files : List(Str), List(Str) -> List(Str)
	files = |modules, target_files| {
		rest = modules.drop_if(|path| path == "main.roc").sort_with(Bundle.compare)
		["main.roc"].concat(rest).concat(target_files.sort_with(Bundle.compare)).concat(Bundle.notices)
	}

	## The release version the consumer test makes the `macos.roc` tool under.
	test_version : Str
	test_version = "0.0.1-dryrun"

	## An author's first steps, which the consumer test takes with the tool:
	## each command's arguments and the directory it runs in, relative to the
	## test's (empty for the test's own).
	first_steps : List({ args : List(Str), cwd : Str })
	first_steps = [
		{ args: ["init", "counter"], cwd: "" },
		{ args: ["build"], cwd: "counter" },
		{ args: ["test"], cwd: "counter" },
	]

	## The example with assets the consumer test builds and tests through
	## the tool, the files its bundle must then hold in
	## `Contents/Resources/`, and the case run on the bundled program.
	assets_example : Str
	assets_example = "about"

	assets_expected : List(Str)
	assets_expected = ["AppIcon.icns", "assets/icon.png", "assets/mark.pdf"]

	assets_case : Str
	assets_case = "switch"

	## An example's `main.roc` with its checkout platform path replaced by
	## the bundle's URL, as an app author's header names it.
	released_main : Str, Str -> Try(Str, [NoPlatformPath])
	released_main = |source, url| {
		local = "platform \"../../platform/main.roc\""
		if (source.contains(local)) Ok(source.replace_each(local, "platform \"${url}\"")) else Err(NoPlatformPath)
	}

	## The port Python's `http.server` says it is serving on, from its first
	## line: `Serving HTTP on :: port 54321 (http://[::]:54321/) ...`.
	served_port : Str -> Try(U16, [NoPort])
	served_port = |printed|
		match printed.split_on(" port ") {
			[_, rest, ..] =>
				match rest.split_on(" ").first() {
					Ok(digits) => U16.from_str(digits.trim()).map_err(|_| NoPort)
					Err(_) => Err(NoPort)
				}
			_ => Err(NoPort)
		}

	compare : Str, Str -> [Before, Same, After]
	compare = |a, b| Bundle.compare_bytes(a.to_utf8(), b.to_utf8())

	compare_bytes : List(U8), List(U8) -> [Before, Same, After]
	compare_bytes = |a, b|
		match (a, b) {
			([], []) => Same
			([], _) => Before
			(_, []) => After
			([x, .. as xs], [y, .. as ys]) => if (x < y) Before else if (x > y) After else Bundle.compare_bytes(xs, ys)
		}
}

expect Bundle.options([]) == Ok({ output_dir: "build/platform", prebuilt: Bool.False, test: Bool.False })
expect Bundle.options(["--", "--test", "--output-dir", "/tmp/out", "--prebuilt"]) == Ok({ output_dir: "/tmp/out", prebuilt: Bool.True, test: Bool.True })
expect Bundle.options(["--output-dir"]) == Err(MissingValue("--output-dir"))
expect Bundle.options(["--bogus"]) == Err(Unknown("--bogus"))

## The root module leads; the notices close.
expect
	Bundle.files(["Ui.roc", "main.roc", "Core.roc"], ["targets/macos-sysroot/usr/lib/libSystem.tbd", "targets/arm64mac/libhost.a"])
		== ["main.roc", "Core.roc", "Ui.roc", "targets/arm64mac/libhost.a", "targets/macos-sysroot/usr/lib/libSystem.tbd", "LICENSE", "THIRD_PARTY_LICENSES.md"]

expect
	Bundle.released_main("app [main] { pf: platform \"../../platform/main.roc\" }\n", "http://localhost:8000/abc.tar.zst")
		== Ok("app [main] { pf: platform \"http://localhost:8000/abc.tar.zst\" }\n")
expect Bundle.released_main("app [main] { pf: platform \"x\" }\n", "u") == Err(NoPlatformPath)

expect Bundle.served_port("Serving HTTP on :: port 54321 (http://[::]:54321/) ...\n") == Ok(54321)
expect Bundle.served_port("Traceback") == Err(NoPort)
