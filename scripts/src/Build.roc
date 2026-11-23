## The pure decisions of the build script: what it was asked to do, how the
## Swift host is compiled and fingerprinted, and an example's `.app` bundle.
Build := [].{

	## What `scripts/build.roc` was asked to do. `link_inputs` is a candidate
	## directory from `link_inputs.roc build`, or empty for the lock's
	## release.
	Command : [All, Platform, Examples(List(Str)), Glue, GlueCheck, Engine, EngineCheck, Host, HostFingerprint, HostReproduce]

	Options : { command : Command, link_inputs : Str }

	usage : Str
	usage = "usage: build [--link-inputs DIR] [--platform | NAME... | glue [--check] | engine [--check] | host [--fingerprint | --reproduce]]"

	options : List(Str) -> Try(Options, [Usage])
	options = |raw| {
		args = raw.drop_if(|arg| arg == "--")
		(link_inputs, rest) = Build.take_link_inputs(args, [])?
		command = match rest {
			[] => All
			["--platform"] => Platform
			["glue"] => Glue
			["glue", "--check"] => GlueCheck
			["engine"] => Engine
			["engine", "--check"] => EngineCheck
			["host"] => Host
			["host", "--fingerprint"] => HostFingerprint
			["host", "--reproduce"] => HostReproduce
			names if names.all(|name| !name.starts_with("-") and name != "glue" and name != "engine" and name != "host") => Examples(names)
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

	## A Roc target the platform declares, the TAPI target of its linker
	## stubs, the Swift target its host is compiled for, and the other Roc
	## targets that link the same host (`also`).
	HostTarget : { roc : Str, tapi : Str, swift : Str, also : List(Str) }

	## The oldest macOS the host is compiled for, on every architecture: the
	## deployment target of `swift`, given explicitly so that the host does
	## not depend on the macOS of the machine that builds it. It is the
	## oldest macOS an app runs on (`LSMinimumSystemVersion`).
	deployment_target : Str
	deployment_target = "15.0"

	## The platform's targets: Apple silicon and Intel Macs. Each has its
	## own `libhost.a`, cross-compiled from either architecture, and both
	## link against the one `targets/macos-sysroot`. Roc's `x64mac` code
	## needs an x86-64-v3 CPU, which every Intel Mac that runs macOS 15 has;
	## `x64v1mac` is Roc's baseline, which `roc` picks for a machine whose
	## CPU does not report v3 (Rosetta, and some virtual machines). The Swift
	## host uses no v3 instruction, so `x64v1mac` links a copy of the same
	## `libhost.a`.
	host_targets : List(HostTarget)
	host_targets = [
		{ roc: "arm64mac", tapi: "arm64-macos", swift: "arm64-apple-macos${Build.deployment_target}", also: [] },
		{ roc: "x64mac", tapi: "x86_64-macos", swift: "x86_64-apple-macos${Build.deployment_target}", also: ["x64v1mac"] },
	]

	## Every Roc target's `libhost.a` under `platform/`, the copies too.
	host_libraries : List(Str)
	host_libraries = Build.host_targets.map(|t| [t.roc].concat(t.also)).join().map(|roc| "targets/${roc}/libhost.a")

	## Where a target's host objects are compiled, relative to the checkout,
	## two levels below it. The swiftc and libtool commands run there, and
	## name everything by a relative path: Swift hashes an object's output
	## path into its `__swift_modhash`, so fixed relative paths are what
	## makes the same commit build the same `libhost.a` on any checkout path.
	objects_dir : HostTarget -> Str
	objects_dir = |target| "build/host-${target.roc}"

	## A target's host archive and its recorded fingerprint, under `platform/`.
	host_library : HostTarget -> Str
	host_library = |target| "targets/${target.roc}/libhost.a"

	host_fingerprint_file : HostTarget -> Str
	host_fingerprint_file = |target| "targets/${target.roc}/libhost.fingerprint"

	## The swiftc arguments for the host's sources (paths relative to the
	## checkout) for a target, run from a directory two levels below it.
	## Framework autolinking and FORCE_LOAD symbols are off: the frameworks
	## the host links are exactly those the catalog generates stubs for.
	swiftc_args : HostTarget, List(Str) -> List(Str)
	swiftc_args = |target, sources|
		[
			"-target",
			target.swift,
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

	## The text a target's host fingerprint is the SHA-256 of: a version, the
	## target, the Swift compiler and Xcode that build it, the swiftc
	## arguments, and each input's digest. A host whose recorded fingerprint
	## matches is reused. `swiftc --version`'s `Target:` line names the
	## machine's default target, which the explicit `-target` overrides, so
	## it is left out: the same host has the same fingerprint built on
	## either architecture.
	host_fingerprint_text : { target : HostTarget, swiftc : Str, xcode : Str, files : List({ path : Str, sha256 : Str }) } -> Str
	host_fingerprint_text = |{ target, swiftc, xcode, files }| {
		swift = swiftc.trim().split_on("\n").drop_if(|line| line.starts_with("Target:"))
		lines =
			["roc-native-macos host v2", "target ${target.swift}", "swiftc ${Str.join_with(swift, " / ")}", "xcode ${Str.join_with(xcode.trim().split_on("\n"), " / ")}", "args ${Str.join_with(Build.swiftc_args(target, []), " ")}"]
				.concat(files.map(|file| "${file.sha256}  ${file.path}"))
		"${Str.join_with(lines, "\n")}\n"
	}

	## The text the platform's host fingerprint is the SHA-256 of: each
	## target's fingerprint (CI's cache key for every `libhost.a`).
	hosts_fingerprint_text : List((HostTarget, Str)) -> Str
	hosts_fingerprint_text = |found| Str.join_with(found.map(|(target, fingerprint)| "${fingerprint}  ${target.roc}\n"), "")

	## The files `glue/SwiftGlue.roc` writes into `host/`, which are committed.
	glue_files : List(Str)
	glue_files = ["roc_swift_abi.h", "RocGlue.swift"]

	## An example's `Contents/Info.plist`: its bundle identifier, name and
	## executable, and its icon when its assets hold an `icon.icns`.
	## LSMinimumSystemVersion is the host's deployment target: Roc's linker
	## writes `minos` 11.0, but the host needs the Swift runtime of macOS 15.
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
			"<key>LSMinimumSystemVersion</key><string>${Build.deployment_target}</string>",
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
expect Build.options(["engine", "--check"]) == Ok({ command: EngineCheck, link_inputs: "" })
expect Build.options(["host", "--fingerprint"]) == Ok({ command: HostFingerprint, link_inputs: "" })
expect Build.options(["--bogus"]) == Err(Usage)
expect Build.options(["--link-inputs"]) == Err(Usage)

x64 : Build.HostTarget
x64 = { roc: "x64mac", tapi: "x86_64-macos", swift: "x86_64-apple-macos15.0", also: ["x64v1mac"] }

## Both Macs, each named the same way everywhere.
expect Build.host_targets.map(|t| (t.roc, t.tapi, t.swift)) == [("arm64mac", "arm64-macos", "arm64-apple-macos15.0"), ("x64mac", "x86_64-macos", "x86_64-apple-macos15.0")]
expect Build.host_libraries == ["targets/arm64mac/libhost.a", "targets/x64mac/libhost.a", "targets/x64v1mac/libhost.a"]
expect Build.host_library(x64) == "targets/x64mac/libhost.a" and Build.objects_dir(x64) == "build/host-x64mac"

## Sources are sorted and named from two levels below the checkout, for
## the explicit target.
expect
	Build.swiftc_args(x64, ["host/Views.swift", "host/App.swift"]).take_last(2) == ["../../host/App.swift", "../../host/Views.swift"]
		and Build.swiftc_args(x64, []).take_first(2) == ["-target", "x86_64-apple-macos15.0"]
		and Build.swiftc_args(x64, []).contains("-disable-autolink-frameworks")
		and Build.swiftc_args(x64, []).contains("-disable-force-load-symbols")

expect Build.libtool_args("/x/libhost.a", ["Views.o", "App.o"]) == ["-static", "-D", "-o", "/x/libhost.a", "App.o", "Views.o"]
expect Build.host_inputs(["host/B.swift", "host/A.swift"]) == ["host/A.swift", "host/B.swift", "host/roc_swift_abi.h", "scripts/build.roc", "scripts/src/Build.roc"]

## The machine's default target is not part of the fingerprint: the
## explicit one is.
expect {
	text = Build.host_fingerprint_text({ target: x64, swiftc: "Apple Swift 6.2\nTarget: arm64-apple-macosx15.0\n", xcode: "Xcode 26.3\nBuild version 17C529\n", files: [{ path: "host/A.swift", sha256: "aa" }] })
	on_intel = Build.host_fingerprint_text({ target: x64, swiftc: "Apple Swift 6.2\nTarget: x86_64-apple-macosx15.0\n", xcode: "Xcode 26.3\nBuild version 17C529\n", files: [{ path: "host/A.swift", sha256: "aa" }] })
	text.starts_with("roc-native-macos host v2\ntarget x86_64-apple-macos15.0\nswiftc Apple Swift 6.2\nxcode Xcode 26.3 / Build version 17C529\nargs -target x86_64-apple-macos15.0 -O ")
		and text.ends_with("\naa  host/A.swift\n")
		and text == on_intel
}

expect Build.hosts_fingerprint_text([(x64, "ab"), ({ ..x64, roc: "arm64mac" }, "cd")]) == "ab  x64mac\ncd  arm64mac\n"
expect Build.info_plist("counter", Bool.False).contains("<key>LSMinimumSystemVersion</key><string>15.0</string>\n")

expect Build.info_plist("counter", Bool.False).contains("<key>CFBundleIdentifier</key><string>dev.roc.native.counter</string>\n") and !Build.info_plist("counter", Bool.False).contains("CFBundleIconFile")
expect Build.info_plist("about", Bool.True).contains("<key>CFBundleIconFile</key><string>AppIcon</string>\n</dict>\n</plist>\n")
