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
	## Swift host for each target the platform declares, Apple silicon and
	## Intel (`x64v1mac`, Roc's baseline Intel target, has a copy of the
	## `x64mac` host), and the generated linker stubs
	## (`targets/macos-sysroot`), which serve them all.
	host_libraries : List(Str)
	host_libraries = ["targets/arm64mac/libhost.a", "targets/x64mac/libhost.a", "targets/x64v1mac/libhost.a"]

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

	## How the consumer test packages the counter `init` made, in its
	## directory: as the release workflow `init` wrote does, with no secrets,
	## for a pushed pre-release tag, whose version overrides the starter
	## `macos.json`'s.
	package_args : List(Str)
	package_args = ["ci", "package"]

	## The GitHub Actions variables that run sees: a pushed tag.
	package_env : List((Str, Str))
	package_env = [("GITHUB_ACTIONS", "true"), ("GITHUB_REF_TYPE", "tag"), ("GITHUB_REF_NAME", "v1.0.0-rc.1"), ("RELEASE_VERSION", "")]

	## The zip that makes, relative to the counter's directory: its name
	## keeps the pre-release suffix.
	package_zip : Str
	package_zip = "dist/counter-1.0.0-rc.1.zip"

	## What the packaged `Info.plist` must say: the version's numbers alone,
	## and the build number following them.
	package_plist : List(Str)
	package_plist = [
		"<key>CFBundleShortVersionString</key><string>1.0.0</string>",
		"<key>CFBundleVersion</key><string>1.0.0</string>",
	]

	## The recorded case run on the program extracted from the zip.
	package_case : Str
	package_case = "increment"

	## What the zip must hold, in order, with each entry's Unix mode: an ad
	## hoc seal (`_CodeSignature/`) over the program, `Info.plist` and the
	## (empty) resources.
	package_entries : List({ name : Str, mode : U32 })
	package_entries = [
		{ name: "counter.app/", mode: 0o040755 },
		{ name: "counter.app/Contents/", mode: 0o040755 },
		{ name: "counter.app/Contents/Info.plist", mode: 0o100644 },
		{ name: "counter.app/Contents/MacOS/", mode: 0o040755 },
		{ name: "counter.app/Contents/MacOS/counter", mode: 0o100755 },
		{ name: "counter.app/Contents/Resources/", mode: 0o040755 },
		{ name: "counter.app/Contents/_CodeSignature/", mode: 0o040755 },
		{ name: "counter.app/Contents/_CodeSignature/CodeResources", mode: 0o100644 },
	]

	## A zip's entries from its central directory: each name, and the Unix
	## mode in the high half of its external attributes. Only an archive
	## made by a Unix tool (`version made by` 3) records a mode; any other
	## entry has mode 0.
	zip_entries : List(U8) -> Try(List({ name : Str, mode : U32 }), [NotAZip])
	zip_entries = |bytes| {
		if bytes.len() < 22 {
			return Err(NotAZip)
		}
		end = bytes.len() - 22
		if Bundle.le(bytes, end, 4) != 0x06054B50 {
			return Err(NotAZip)
		}
		count = Bundle.le(bytes, end + 10, 2)
		var $at = Bundle.le(bytes, end + 16, 4).to_u64()
		var $found = []
		for _ in (0.U32).range_exclusive_to(count) {
			if Bundle.le(bytes, $at, 4) != 0x02014B50 {
				return Err(NotAZip)
			}
			made_by_unix = Bundle.le(bytes, $at + 4, 2).shr_zf_wrap(8) == 3
			name_len = Bundle.le(bytes, $at + 28, 2).to_u64()
			skip = Bundle.le(bytes, $at + 30, 2).to_u64() + Bundle.le(bytes, $at + 32, 2).to_u64()
			mode = if (made_by_unix) Bundle.le(bytes, $at + 38, 4).shr_zf_wrap(16) else 0
			name = Str.from_utf8_lossy(bytes.drop_first($at + 46).take_first(name_len))
			$found = $found.append({ name, mode })
			$at = $at + 46 + name_len + skip
		}
		Ok($found)
	}

	## The little-endian number of `size` bytes at `at`; 0 past the end.
	le : List(U8), U64, U64 -> U32
	le = |bytes, at, size| bytes.drop_first(at).take_first(size).fold({ n: 0, shift: 0 }, |acc, b| { n: acc.n + b.to_u32().shl_wrap(acc.shift), shift: acc.shift + 8 }).n

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
	Bundle.files(["Ui.roc", "main.roc", "Core.roc"], ["targets/macos-sysroot/usr/lib/libSystem.tbd", "targets/x64mac/libhost.a", "targets/arm64mac/libhost.a"])
		== ["main.roc", "Core.roc", "Ui.roc", "targets/arm64mac/libhost.a", "targets/macos-sysroot/usr/lib/libSystem.tbd", "targets/x64mac/libhost.a", "LICENSE", "THIRD_PARTY_LICENSES.md"]

expect
	Bundle.released_main("app [main] { pf: platform \"../../platform/main.roc\" }\n", "http://localhost:8000/abc.tar.zst")
		== Ok("app [main] { pf: platform \"http://localhost:8000/abc.tar.zst\" }\n")
expect Bundle.released_main("app [main] { pf: platform \"x\" }\n", "u") == Err(NoPlatformPath)

expect Bundle.served_port("Serving HTTP on :: port 54321 (http://[::]:54321/) ...\n") == Ok(54321)
expect Bundle.served_port("Traceback") == Err(NoPort)

## A Unix entry's mode is the high half of its external attributes.
expect {
	central = [0x50, 0x4B, 0x01, 0x02, 0x1E, 0x03, 10, 0, 0, 8, 0, 0, 0, 0, 0x21, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x10, 0, 0xED, 0x41, 0, 0, 0, 0, 'a', '/']
	end = [0x50, 0x4B, 0x05, 0x06, 0, 0, 0, 0, 1, 0, 1, 0, 48, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	Bundle.zip_entries(central.concat(end)) == Ok([{ name: "a/", mode: 0o040755 }]) and Bundle.zip_entries([1, 2, 3]) == Err(NotAZip)
}
