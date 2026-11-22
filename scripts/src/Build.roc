## The pure decisions of the build script: what it was asked to do, how the
## Swift host is compiled and fingerprinted, and an example's `.app` bundle.
Build := [].{

	## What `scripts/build.roc` was asked to do. `link_inputs` is a candidate
	## directory from `link_inputs.roc build`, or empty for the lock's
	## release.
	Command : [All, Platform, Examples(List(Str)), Glue, GlueCheck, Host, HostFingerprint, HostReproduce]

	Options : { command : Command, link_inputs : Str }

	usage : Str
	usage = "usage: build [--link-inputs DIR] [--platform | NAME... | glue [--check] | host [--fingerprint | --reproduce]]"

	options : List(Str) -> Try(Options, [Usage])
	options = |raw| {
		args = raw.drop_if(|arg| arg == "--")
		(link_inputs, rest) = Build.take_link_inputs(args, [])?
		command = match rest {
			[] => All
			["--platform"] => Platform
			["glue"] => Glue
			["glue", "--check"] => GlueCheck
			["host"] => Host
			["host", "--fingerprint"] => HostFingerprint
			["host", "--reproduce"] => HostReproduce
			names if names.all(|name| !name.starts_with("-") and name != "glue" and name != "host") => Examples(names)
			_ => return Err(Usage)
		}
		Ok({ command, link_inputs })
	}

	take_link_inputs : List(Str), List(Str) -> Try((Str, List(Str)), [Usage])
	take_link_inputs = |args, kept|
		match args {
			["--link-inputs", dir, .. as rest] => Build.take_link_inputs(rest, kept).map_ok(|(_, others)| (dir, others))
			["--link-inputs"] => Err(Usage)
			[arg, .. as rest] => Build.take_link_inputs(rest, kept.append(arg))
			[] => Ok(("", kept))
		}

	## Where the host's objects are compiled, relative to the checkout. The
	## swiftc and libtool commands run there, and name everything by a
	## relative path: Swift hashes an object's output path into its
	## `__swift_modhash`, so fixed relative paths are what makes the same
	## commit build the same `libhost.a` on any checkout path.
	objects_dir : Str
	objects_dir = "build/host"

	## The host's archive and its recorded fingerprint, under `platform/`.
	host_library : Str
	host_library = "targets/arm64mac/libhost.a"

	host_fingerprint_file : Str
	host_fingerprint_file = "targets/arm64mac/libhost.fingerprint"

	## The swiftc arguments for the host's sources (paths relative to the
	## checkout), run from a directory two levels below it. Framework
	## autolinking and FORCE_LOAD symbols are off: the frameworks the host
	## links are exactly those the catalog generates stubs for.
	swiftc_args : List(Str) -> List(Str)
	swiftc_args = |sources|
		[
			"-O",
			"-parse-as-library",
			"-c",
			"-module-name",
			"RocHost",
			"-Xfrontend",
			"-disable-force-load-symbols",
			"-Xfrontend",
			"-disable-autolink-frameworks",
			"-import-objc-header",
			"../../host/roc_swift_abi.h",
		].concat(sources.sort_with(Build.compare).map(|source| "../../${source}"))

	## `libtool -static -D` over the sorted objects: zero dates, IDs and modes
	## in the archive (with `ZERO_AR_DATE=1` for the table of contents).
	libtool_args : Str, List(Str) -> List(Str)
	libtool_args = |output, objects| ["-static", "-D", "-o", output].concat(objects.sort_with(Build.compare))

	## The files whose contents make up the host: its Swift sources and the
	## committed glue header, and this build recipe.
	host_inputs : List(Str) -> List(Str)
	host_inputs = |swift_sources| swift_sources.append("host/roc_swift_abi.h").sort_with(Build.compare).concat(["scripts/build.roc", "scripts/src/Build.roc"])

	## The text the host's fingerprint is the SHA-256 of: a version, the
	## Swift compiler and Xcode that build it, the swiftc arguments, and each
	## input's digest. A host whose recorded fingerprint matches is reused.
	host_fingerprint_text : { swiftc : Str, xcode : Str, files : List({ path : Str, sha256 : Str }) } -> Str
	host_fingerprint_text = |{ swiftc, xcode, files }| {
		lines =
			["roc-native-macos host v1", "target arm64-apple-macos", "swiftc ${Str.join_with(swiftc.trim().split_on("\n"), " / ")}", "xcode ${Str.join_with(xcode.trim().split_on("\n"), " / ")}", "args ${Str.join_with(Build.swiftc_args([]), " ")}"]
				.concat(files.map(|file| "${file.sha256}  ${file.path}"))
		"${Str.join_with(lines, "\n")}\n"
	}

	## The files `glue/SwiftGlue.roc` writes into `host/`, which are committed.
	glue_files : List(Str)
	glue_files = ["roc_swift_abi.h", "RocGlue.swift"]

	## An example's `Contents/Info.plist`: its bundle identifier, name and
	## executable, and its icon when its assets hold an `icon.icns`.
	## LSMinimumSystemVersion matches the minos Roc's linker writes (11.0).
	info_plist : Str, Bool -> Str
	info_plist = |name, icon| {
		lines = [
			"<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
			"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">",
			"<plist version=\"1.0\">",
			"<dict>",
			"<key>CFBundleIdentifier</key><string>dev.roc.native.${name}</string>",
			"<key>CFBundleName</key><string>${name}</string>",
			"<key>CFBundleExecutable</key><string>${name}</string>",
			"<key>CFBundlePackageType</key><string>APPL</string>",
			"<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>",
			"<key>CFBundleShortVersionString</key><string>0.1</string>",
			"<key>NSPrincipalClass</key><string>NSApplication</string>",
			"<key>NSHighResolutionCapable</key><true/>",
			"<key>LSMinimumSystemVersion</key><string>11.0</string>",
		]
		icon_line = if (icon) ["<key>CFBundleIconFile</key><string>AppIcon</string>"] else []
		"${Str.join_with(lines.concat(icon_line).concat(["</dict>", "</plist>"]), "\n")}\n"
	}

	compare : Str, Str -> [Before, Same, After]
	compare = |a, b| Build.compare_bytes(a.to_utf8(), b.to_utf8())

	compare_bytes : List(U8), List(U8) -> [Before, Same, After]
	compare_bytes = |a, b|
		match (a, b) {
			([], []) => Same
			([], _) => Before
			(_, []) => After
			([x, .. as xs], [y, .. as ys]) => if (x < y) Before else if (x > y) After else Build.compare_bytes(xs, ys)
		}
}

expect Build.options([]) == Ok({ command: All, link_inputs: "" })
expect Build.options(["--", "--platform"]) == Ok({ command: Platform, link_inputs: "" })
expect Build.options(["counter", "todos"]) == Ok({ command: Examples(["counter", "todos"]), link_inputs: "" })
expect Build.options(["--link-inputs", "build/li", "--platform"]) == Ok({ command: Platform, link_inputs: "build/li" })
expect Build.options(["glue", "--check"]) == Ok({ command: GlueCheck, link_inputs: "" })
expect Build.options(["host", "--fingerprint"]) == Ok({ command: HostFingerprint, link_inputs: "" })
expect Build.options(["--bogus"]) == Err(Usage)
expect Build.options(["--link-inputs"]) == Err(Usage)

## Sources are sorted and named from build/host.
expect
	Build.swiftc_args(["host/Views.swift", "host/App.swift"]).take_last(2) == ["../../host/App.swift", "../../host/Views.swift"]
		and Build.swiftc_args([]).contains("-disable-autolink-frameworks")
		and Build.swiftc_args([]).contains("-disable-force-load-symbols")

expect Build.libtool_args("/x/libhost.a", ["Views.o", "App.o"]) == ["-static", "-D", "-o", "/x/libhost.a", "App.o", "Views.o"]
expect Build.host_inputs(["host/B.swift", "host/A.swift"]) == ["host/A.swift", "host/B.swift", "host/roc_swift_abi.h", "scripts/build.roc", "scripts/src/Build.roc"]

expect {
	text = Build.host_fingerprint_text({ swiftc: "Apple Swift 6.2\nTarget: arm64\n", xcode: "Xcode 26.3\nBuild version 17C529\n", files: [{ path: "host/A.swift", sha256: "aa" }] })
	text.starts_with("roc-native-macos host v1\ntarget arm64-apple-macos\nswiftc Apple Swift 6.2 / Target: arm64\nxcode Xcode 26.3 / Build version 17C529\nargs -O ")
		and text.ends_with("\naa  host/A.swift\n")
}

expect Build.info_plist("counter", Bool.False).contains("<key>CFBundleIdentifier</key><string>dev.roc.native.counter</string>\n") and !Build.info_plist("counter", Bool.False).contains("CFBundleIconFile")
expect Build.info_plist("about", Bool.True).contains("<key>CFBundleIconFile</key><string>AppIcon</string>\n</dict>\n</plist>\n")
