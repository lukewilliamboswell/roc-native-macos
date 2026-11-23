#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	roc: "nightly-2026-11-22-3350b1c",
}

import cli.Cmd
import cli.Duration
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stderr
import cli.Stdout
import src/Bundle
import src/Recorded
import src/Release

## The `release` task: the steps of `.github/workflows/release.yml` after the
## bundle exists. Each works on a release directory that holds the bundle,
## as `blueprint run bundle -- --output-dir DIR` writes it.
##
##     blueprint run release -- tool VERSION DIR          # DIR/macos-<hash>.tar.zst and DIR/macos.roc
##     blueprint run release -- tool VERSION DIR --base-url URL   # naming URL in place of the release's
##     blueprint run release -- archive VERSION DIR       # DIR/roc-native-macos-examples-VERSION.zip
##     blueprint run release -- test DIR                  # build and run the archived examples against DIR's bundle
##     blueprint run release -- test DIR --binaries BIN   # run the archived examples' cases on prebuilt apps in BIN
##     blueprint run release -- notes VERSION DIR OUT     # the release notes, as Markdown, to OUT
##     blueprint run release -- bump VERSION [LATEST URL] # roc bump --expect against the latest final release
##     blueprint run release -- cross-run DIR CROSS TARGET   # test DIR's cases on every CROSS/cross-<system>/ app for TARGET
##     blueprint run release -- versions                  # the compilers and the Swift toolchain
##
## `tool` writes `macos.roc`, the app author's tool: it stages the tool's
## package (`cli/`) with a generated `Bundle.roc` naming the release (its
## version, the platform's URL and the Roc that tested it) and the counter
## scaffold, runs its `expect`s, and `roc bundle`s it as
## `macos-<hash>.tar.zst`. Then it writes `macos.roc`, the small app an
## author downloads, naming that bundle. Both are named by their URLs under
## `--base-url`, by default the release's download URL.
##
## `archive` writes the examples archive: every example with its header
## naming the bundle's release URL (`GITHUB_REPOSITORY`, the version and the
## bundle's file name), with their recorded cases and the files those use.
##
## `test` checks those exact files as an app author meets them. It unpacks
## the archive, serves DIR on localhost in place of the release URL (the
## compiler accepts `http` only for localhost), builds every example with an
## empty package cache and runs every recorded case against it. Then it
## takes an author's first steps with the release's `macos.roc`: `init` a
## counter, `build` it and `test` it, each through the tool. With
## `--binaries BIN` it builds nothing and runs the cases against `BIN/<example>`,
## apps cross-compiled on another system from the same archive and bundle,
## and against `BIN/<example>.app` where `macos.roc build` made one there.
## `cross-run` does that for each cross-compiling system's apps, with the
## programs built for TARGET, this Mac's own (`BIN/<TARGET>/<example>`),
## and the universal `BIN/<example>.app`.
##
## `bump` checks that VERSION goes far enough past LATEST, the latest final
## release, whose platform bundle is at URL: `roc bump --old URL --expect
## VERSION platform/main.roc` when they share a breaking boundary. A first
## release, or one past the boundary, needs no comparison. For the dry-run
## version it reports the bump the change needs and fails nothing.
##
## `notes` renders `docs/releases/VERSION.adoc` (for the dry-run version, the
## highest version there) with the real URLs, then adds the compilers, the
## Swift toolchain and the SHA-256 of every file in DIR.
##
## The package compiler is the `roc` on PATH.
main! : List(OsStr) => Try({}, _)
main! = |raw_args| {
	args = raw_args.map(OsStr.display).drop_if(|arg| arg == "--")
	root = Env.cwd!()?.display()
	result = match args {
		["tool", version, dir] => tool!(root, version, absolute(root, dir), Err(ReleaseUrl))
		["tool", version, dir, "--base-url", url] => tool!(root, version, absolute(root, dir), Ok(url.drop_suffix("/")))
		["archive", version, dir] => archive!(root, version, absolute(root, dir))
		["test", dir] => test!(root, absolute(root, dir), Err(NoBinaries))
		["test", dir, "--binaries", bin] => test!(root, absolute(root, dir), Ok({ programs: absolute(root, bin), apps: absolute(root, bin) }))
		["notes", version, dir, out] => notes!(version, absolute(root, dir), absolute(root, out))
		["bump", version] => bump!(version, "", "")
		["bump", version, latest, url] => bump!(version, latest, url)
		["cross-run", dir, cross, target] if cross_targets.contains(target) => cross_run!(root, absolute(root, dir), absolute(root, cross), target)
		["versions"] => versions!()
		_ => Err("usage: release tool VERSION DIR [--base-url URL] | archive VERSION DIR | test DIR [--binaries BIN] | notes VERSION DIR OUT | bump VERSION [LATEST URL] | cross-run DIR CROSS (arm64mac | x64mac) | versions")
	}
	match result {
		Ok({}) => Ok({})
		Err(problem) => {
			warn!("release: ${problem}")
			Err(Exit(1))
		}
	}
}

absolute : Str, Str -> Str
absolute = |root, path| if (path.starts_with("/")) path else "${root}/${path}"

## The one bundle in a release directory: its file name.
bundle_in! : Str => Try(Str, Str)
bundle_in! = |dir| {
	found = names_in!(dir)?.keep_if(|name| name.ends_with(".tar.zst") and !Release.is_tool_bundle(name))
	match found {
		[one] => Ok(one)
		_ => Err("${dir} holds ${found.len().to_str()} platform bundles (.tar.zst files not named macos-*), not one")
	}
}

## The `macos.roc` tool's bundle in a release directory: its file name.
tool_in! : Str => Try(Str, Str)
tool_in! = |dir| {
	found = names_in!(dir)?.keep_if(Release.is_tool_bundle)
	match found {
		[one] => Ok(one)
		_ => Err("${dir} holds ${found.len().to_str()} tool bundles (macos-*.tar.zst), not one: run `release -- tool` first")
	}
}

## The file names in a directory, sorted.
names_in! : Str => Try(List(Str), Str)
names_in! = |dir| {
	entries = Path.list!(Path.utf8(dir)) ? |error| "could not list ${dir}: ${Str.inspect(error)}"
	Ok(entries.keep_oks(|path| Path.filename(path).map_ok(Path.display)).sort_with(Bundle.compare))
}

repository! : () => Str
repository! = || {
	found = Env.var_str!(OsStr.from_str("GITHUB_REPOSITORY")) ?? ""
	if (found.is_empty()) Release.repository else found
}

## The `macos.roc` tool: its package bundle, `macos-<hash>.tar.zst`, naming
## the platform bundle in `dir`, and the launcher `macos.roc` naming it.
tool! : Str, Str, Str, Try(Str, [ReleaseUrl]) => Try({}, Str)
tool! = |root, version, dir, base| {
	if !Release.version_ok(version) {
		return Err("${version} is not a release version (MAJOR.MINOR.PATCH, optionally -SUFFIX, no v)")
	}
	base_url = match base {
		Ok(url) => url
		Err(ReleaseUrl) => Release.download_root(repository!(), version)
	}
	bundle = bundle_in!(dir)?
	stage = "${root}/build/tool-stage"
	fresh!(stage) ? |error| "could not empty ${stage}: ${Str.inspect(error)}"
	# Every tool module but the checkout's Bundle.roc, which imports the
	# working tree; the release's is generated below.
	listed = capture!("git", ["ls-files", "--cached", "--others", "--exclude-standard", "--", "cli/*.roc"])?
	modules = listed.split_on("\n").keep_if(|line| !line.is_empty()).map(|path| path.drop_prefix("cli/")).drop_if(|name| name == "Bundle.roc")
	for name in modules {
		write!("${stage}/${name}", read!("cli/${name}")?)?
	}
	case_files = names_in!("examples/counter/tests")?
	for file in Release.scaffold(case_files) {
		write!("${stage}/scaffold/${file.path}", read!(file.source)?)?
	}
	for notice in ["LICENSE", "THIRD_PARTY_LICENSES.md"] {
		write!("${stage}/${notice}", read!(notice)?)?
	}
	roc_version = capture!("roc", ["version"])?.trim().drop_prefix("Roc compiler version ")
	write!("${stage}/Bundle.roc", Release.release_bundle({ version, platform_url: "${base_url}/${bundle}", roc_version }, case_files))?
	step!(Cmd.new("roc").args(["test", "main.roc"]).cwd(Path.utf8(stage)), "roc test (the tool, with the release's Bundle.roc)")?
	packed = "${root}/build/tool-bundle"
	fresh!(packed) ? |error| "could not empty ${packed}: ${Str.inspect(error)}"
	files = Release.tool_files(modules, case_files)
	step!(Cmd.new("roc").args(["bundle"].concat(files).concat(["--output-dir", packed]).map(OsStr.from_str)).cwd(Path.utf8(stage)), "roc bundle (the tool, ${files.len().to_str()} files)")?
	hashed = match names_in!(packed)?.keep_if(|name| name.ends_with(".tar.zst")) {
		[one] => one
		found => return Err("roc bundle wrote ${found.len().to_str()} .tar.zst files to ${packed}, not one")
	}
	for old in names_in!(dir)?.keep_if(Release.is_tool_bundle) {
		Path.delete!(Path.utf8("${dir}/${old}")) ? |error| "could not replace ${dir}/${old}: ${Str.inspect(error)}"
	}
	tool = Release.tool_bundle(hashed)
	Path.copy!(Path.utf8("${packed}/${hashed}"), Path.utf8("${dir}/${tool}")) ? |error| "could not copy the tool's bundle to ${dir}: ${Str.inspect(error)}"
	basic_cli = Release.platform_of(read!("cli/main.roc")?) ? |_| "cli/main.roc names no platform"
	write!("${dir}/macos.roc", Release.launcher({ version, basic_cli, tool_url: "${base_url}/${tool}" }))?
	note!("release: ${dir}/${tool}, the macos.roc tool naming ${base_url}/${bundle}")
	note!("release: ${dir}/macos.roc, naming ${base_url}/${tool}")
	Ok({})
}

## The examples archive: `roc-native-macos-examples-VERSION/` holding each
## example's `main.roc` with the release URL in its header, the recorded
## cases and fixtures, and a README.
archive! : Str, Str, Str => Try({}, Str)
archive! = |root, version, dir| {
	if !Release.version_ok(version) {
		return Err("${version} is not a release version (MAJOR.MINOR.PATCH, optionally -SUFFIX, no v)")
	}
	bundle = bundle_in!(dir)?
	url = "${Release.download_root(repository!(), version)}/${bundle}"
	name = Release.examples_name(version)
	stage = "${root}/build/examples-archive"
	fresh!(stage) ? |error| "could not empty ${stage}: ${Str.inspect(error)}"
	top = "${stage}/${name}"
	examples = tracked!(["examples"])?.keep_if(|path| path.ends_with("/main.roc"))
	for path in examples {
		source = read!(path)?
		released = Bundle.released_main(source, url) ? |_| "${path} does not name ../../platform/main.roc"
		write!("${top}/${path}", released)?
	}
	# Each example's assets/, byte for byte: images are not text.
	for path in tracked!(["examples"])?.keep_if(|path| path.contains("/assets/")) {
		copy!(path, "${top}/${path}")?
	}
	# Each example's recorded cases and the files they use, byte for byte.
	for path in tracked!(["examples"])?.keep_if(|path| path.contains("/tests/")) {
		copy!(path, "${top}/${path}")?
	}
	write!("${top}/README.md", readme(version, url, examples.len()))?
	zip = "${dir}/${name}.zip"
	if Path.exists!(Path.utf8(zip)) ?? Bool.False {
		Path.delete!(Path.utf8(zip)) ? |error| "could not replace ${zip}: ${Str.inspect(error)}"
	}
	step!(Cmd.new("zip").args(["-q", "-r", "-X", OsStr.from_str(zip), OsStr.from_str(name)]).cwd(Path.utf8(stage)), "zip ${name}.zip")?
	note!("release: ${zip}, ${examples.len().to_str()} examples naming ${url}")
	Ok({})
}

readme : Str, Str, U64 -> Str
readme = |version, url, count|
	Str.join_with(
		[
			"# roc-native-macos ${version} examples",
			"",
			"These ${count.to_str()} examples name the platform by its release URL:",
			"",
			"    ${url}",
			"",
			"Build one with a Roc compiler on any system; the app runs on Apple silicon",
			"and Intel Macs with macOS 15 or later. With macos.roc, the tool this release",
			"publishes, saved beside this directory, build and start an example from its",
			"own directory:",
			"",
			"    cd examples/todos",
			"    roc ../../../macos.roc run",
			"",
			"`roc ../../../macos.roc build` builds `todos.app`, a universal app for both",
			"kinds of Mac, on any system. Without the tool, name the Mac to build for:",
			"",
			"    roc build main.roc --target=arm64mac   # Apple silicon",
			"    roc build main.roc --target=x64mac     # Intel",
			"",
			"Each example's `tests/<case>.script` holds the steps of a recorded run and",
			"`<case>.expected` what the app prints. Run them from the example's directory:",
			"",
			"    roc ../../../macos.roc test",
			"",
			"The window's size is written `--- <size>`, and the example's directory",
			"`<app>`, where the output printed the path.",
			"",
		],
		"\n",
	)

## Build every archived example against the served bundle and run its
## recorded cases, or run them against prebuilt apps.
test! : Str, Str, Try({ programs : Str, apps : Str }, [NoBinaries]) => Try({}, Str)
test! = |root, dir, binaries| {
	bundle = bundle_in!(dir)?
	zips = names_in!(dir)?.keep_if(|name| name.starts_with("roc-native-macos-examples-") and name.ends_with(".zip"))
	zip = match zips {
		[one] => one
		_ => return Err("${dir} holds ${zips.len().to_str()} examples archives, not one")
	}
	work = "${root}/build/release-test"
	fresh!(work) ? |error| "could not empty ${work}: ${Str.inspect(error)}"
	step!(Cmd.new("unzip").args(["-q", OsStr.from_str("${dir}/${zip}"), "-d", OsStr.from_str(work)]), "unzip ${zip}")?
	top_path = Path.canonicalize!(Path.utf8("${work}/${zip.drop_suffix(".zip")}")) ? |_| "${zip} does not hold ${zip.drop_suffix(".zip")}/"
	top = top_path.display()
	examples = names_in!("${top}/examples")?
	if examples.is_empty() {
		return Err("${zip} holds no examples")
	}
	{ programs, apps } = match binaries {
		Ok(given) => given
		Err(NoBinaries) => {
			tool = tool_in!(dir)?
			build_all!(work, top, dir, { bundle, tool }, examples)?
			{ programs: "${work}/apps", apps: "${work}/apps" }
		}
	}
	var $failed = []
	var $passed = 0.U64
	for example in examples {
		# The example's program, and the one inside `<example>.app` when
		# `macos.roc build` made one there (the cross-compiling jobs do).
		in_app = "${apps}/${example}.app/Contents/MacOS/${example}"
		# A bare program is run away from its assets, so ROC_ASSETS names
		# them; a bundled one finds its own in Contents/Resources.
		bundled = if (Path.exists!(Path.utf8(in_app)) ?? Bool.False) [{ exe: in_app, label: "${example}.app", assets: "" }] else []
		cases = names_in!("${top}/examples/${example}/tests")?.keep_oks(Recorded.case_name)
		if cases.is_empty() {
			$failed = $failed.append("${example} has no recorded case")
		}
		for { exe, label, assets } in [{ exe: "${programs}/${example}", label: example, assets: "${top}/examples/${example}/assets" }].concat(bundled) {
			for name in cases {
				match run_case!("${top}/examples/${example}", { exe, assets }, name) {
					Ok({}) => {
						note!("release: PASS ${label}/${name}")
						$passed = $passed + 1
					}
					Err(problem) => {
						warn!("release: FAIL ${label}/${name}: ${problem}")
						$failed = $failed.append("${label}/${name}")
					}
				}
			}
		}
	}
	if $failed.is_empty() {
		note!("release: ${$passed.to_str()} cases passed against ${bundle}")
		Ok({})
	} else {
		Err("${$failed.len().to_str()} failed: ${Str.join_with($failed, ", ")}")
	}
}

## Serve the release directory on localhost and build every example against
## it, with an empty package cache, into `work/apps/<example>`; then take an
## author's first steps with the release's `macos.roc`.
build_all! : Str, Str, Str, { bundle : Str, tool : Str }, List(Str) => Try({}, Str)
build_all! = |work, top, dir, { bundle, tool }, examples| {
	server = Cmd.new("python3")
		.args(["-I", "-u", "-m", "http.server", "0", "--bind", "::", "--directory", OsStr.from_str(dir)])
		.stdin(Null)
		.stdout(Pipe)
		.stderr(MergeWithStdout)
		.spawn!() ? |error| "could not start the local server: ${Str.inspect(error)}"
	result = match served!(server) {
		Ok(port) => {
			served = "http://localhost:${port.to_str()}"
			match build_each!(work, top, "${served}/${bundle}", bundle, examples) {
				Ok({}) => beginner!(work, dir, served, { bundle, tool })
				Err(problem) => Err(problem)
			}
		}
		Err(problem) => Err(problem)
	}
	server.kill!() ?? {}
	server.close!() ?? {}
	result
}

build_each! : Str, Str, Str, Str, List(Str) => Try({}, Str)
build_each! = |work, top, url, bundle, examples| {
	cache = "${work}/cache"
	Path.create_all!(Path.utf8(cache)) ? |error| "could not create ${cache}: ${Str.inspect(error)}"
	for example in examples {
		app_dir = "${top}/examples/${example}"
		source = read!("${app_dir}/main.roc")?
		served = Release.served_main(source, bundle, url) ? |_| "examples/${example}/main.roc does not name the release URL of ${bundle}"
		write!("${app_dir}/main.roc", served)?
		out = "${work}/apps/${example}"
		Path.create_all!(Path.utf8("${work}/apps")) ? |error| "could not create ${work}/apps: ${Str.inspect(error)}"
		step!(Cmd.new("roc").args(["build", "main.roc", OsStr.from_str("--output=${out}")]).cwd(Path.utf8(app_dir)).env("XDG_CACHE_HOME", OsStr.from_str(cache)), "roc build examples/${example}/main.roc against ${url}")?
	}
	Ok({})
}

## An author's first steps, through the release's `macos.roc` served from
## localhost, with an empty package cache: `init` a counter, then `build`
## and `test` it. `init` names the platform by its release URL, which is
## served from localhost too.
beginner! : Str, Str, Str, { bundle : Str, tool : Str } => Try({}, Str)
beginner! = |work, dir, served, { bundle, tool }| {
	home = "${work}/beginner"
	cache = "${work}/beginner-cache"
	Path.create_all!(Path.utf8(cache)) ? |error| "could not create ${cache}: ${Str.inspect(error)}"
	launcher = Release.served_launcher(read!("${dir}/macos.roc")?, tool, "${served}/${tool}") ? |_| "${dir}/macos.roc does not name the release URL of ${tool}"
	write!("${home}/macos.roc", launcher)?
	tool_step! = |args, cwd| step!(Cmd.new("roc").args(["macos.roc"].concat(args).map(OsStr.from_str)).cwd(Path.utf8(cwd)).env("XDG_CACHE_HOME", OsStr.from_str(cache)), "roc macos.roc ${Str.join_with(args, " ")} (in ${cwd.drop_prefix("${work}/")})")
	tool_step!(["init", "counter"], home)?
	app_dir = "${home}/counter"
	source = read!("${app_dir}/main.roc")?
	write!("${app_dir}/main.roc", Release.served_main(source, bundle, "${served}/${bundle}") ? |_| "init wrote a main.roc that does not name the release URL of ${bundle}")?
	tool_step!(["build"], app_dir)?
	if !(Path.exists!(Path.utf8("${app_dir}/counter.app/Contents/Info.plist")) ?? Bool.False) {
		return Err("roc macos.roc build wrote no counter.app/Contents/Info.plist")
	}
	tool_step!(["test"], app_dir)?
	note!("release: macos.roc created, built and tested a counter against ${bundle}")
	Ok({})
}

## The port Python's server reports, from its first line of output.
served! : Cmd.Child => Try(U16, Str)
served! = |server|
	match server.read!(Duration.seconds(10)) {
		Ok(Stdout(bytes)) => Bundle.served_port(Str.from_utf8_lossy(bytes)).map_err(|_| "the local server printed no port: ${Str.from_utf8_lossy(bytes)}")
		Ok(Stderr(bytes)) => Err("the local server failed: ${Str.from_utf8_lossy(bytes)}")
		Err(error) => Err("the local server did not start: ${Str.inspect(error)}")
	}

## One recorded case, `tests/<name>` of the example in `app_dir`, run from that
## directory as `macos.roc test` and `blueprint run examples` run it: exit 0,
## and print exactly the recorded output with the directory written `<app>`.
run_case! : Str, { exe : Str, assets : Str }, Str => Try({}, Str)
run_case! = |app_dir, { exe, assets }, name| {
	base = "tests/${name}"
	if !(Path.exists!(Path.utf8(exe)) ?? Bool.False) {
		return Err("${exe} does not exist")
	}
	steps = read!("${app_dir}/${base}.script")?.trim()
	expected = read!("${app_dir}/${base}.expected")?
	program = Cmd.new(OsStr.from_str(exe)).cwd(Path.utf8(app_dir)).env("ROC_SCRIPT", OsStr.from_str(steps))
	output = (if (assets.is_empty()) program else program.env("ROC_ASSETS", OsStr.from_str(assets)))
		.stdin(Null)
		.stderr(MergeWithStdout)
		.timeout(Duration.seconds(60))
		.run!() ? |error| "${exe} did not finish: ${Str.inspect(error)}"
	printed = Recorded.portable(Str.from_utf8_lossy(output.stdout_bytes), app_dir, "<app>")
	if output.status != Exited(0) {
		Err("exited with ${Str.inspect(output.status)}; it printed:\n${printed}")
	} else if printed != expected {
		Err("printed something other than ${base}.expected:\n--- expected\n${expected}--- printed\n${printed}")
	} else {
		Ok({})
	}
}

## The release notes: the authored notes with the real URLs, the compilers
## and toolchain that built and tested the release, and every file's SHA-256.
notes! : Str, Str, Str => Try({}, Str)
notes! = |version, dir, out| {
	if !Release.version_ok(version) {
		return Err("${version} is not a release version")
	}
	dry_run = version == Release.dry_run
	notes_version = if dry_run {
		Release.highest(names_in!("docs/releases")?) ? |_| "docs/releases/ holds no <version>.adoc notes"
	} else {
		version
	}
	source_path = "docs/releases/${notes_version}.adoc"
	if !(Path.exists!(Path.utf8(source_path)) ?? Bool.False) {
		return Err("write ${source_path} first: every release publishes its notes")
	}
	bundle = bundle_in!(dir)?
	root_url = Release.download_root(repository!(), version)
	rendered = match Release.render_notes({ source: read!(source_path)?, version: notes_version, platform_url: "${root_url}/${bundle}", examples_url: "${root_url}/${Release.examples_name(version)}.zip", launcher_url: "${root_url}/macos.roc" }) {
		Ok(text) => text
		Err(WrongTitle(title)) => return Err("${source_path} must open with ${title}")
		Err(NoPlatformUrl) => return Err("${source_path} never writes {platform-url}, the URL an app's header names")
		Err(Unresolved(name)) => return Err("${source_path} writes {${name}}, which the release does not fill in")
		Err(UnclosedBlock) => return Err("${source_path} has a ---- block that is never closed")
	}
	var $sums = []
	for name in names_in!(dir)? {
		digest = capture!("shasum", ["-a", "256", "${dir}/${name}"])?.split_on(" ").first() ?? ""
		$sums = $sums.append("${digest}  ${name}")
	}
	roc = capture!("roc", ["version"])?.trim()
	stable = capture!("roc-stable", ["version"])?.trim()
	swift = capture!("swiftc", ["--version"])?.split_on("\n").first() ?? ""
	xcode = Str.join_with(capture!("xcodebuild", ["-version"])?.trim().split_on("\n"), ", ")
	sums = Str.join_with($sums, "\n")
	prefix = if (dry_run) "Dry run (${version}): the notes for ${notes_version}, as a release of it would publish them.\n\n" else ""
	body =
		Str.join_with(
			[
				"${prefix}${rendered.trim()}",
				"",
				"## Compilers and toolchain",
				"",
				"- Platform, examples and bundle: `${roc}`",
				"- Repository scripts: `${stable}`",
				"- Swift host: `${swift.trim()}` (${xcode})",
				"",
				"## Files",
				"",
				"The bundle, the examples archive, the tool's package and `macos.roc` each",
				"have SBOM documents beside them, bound to their SHA-256: SPDX 3",
				"(`.spdx.json`), SPDX 2.3 (`.spdx-2.3.json`), CycloneDX (`.cdx.json`) and",
				"the evidence manifest (`.sbom-manifest.json`). Every file has a",
				"build-provenance attestation, also published as `<file>.intoto.jsonl`:",
				"`gh attestation verify <file> --repo ${repository!()}`.",
				"",
				"```text",
				sums,
				"```",
			],
			"\n",
		)
	write!(out, body)?
	note!("release: notes for ${notes_version} written to ${out}")
	Ok({})
}

## `roc bump` against the latest final release, as `Release.bump_plan` decides.
bump! : Str, Str, Str => Try({}, Str)
bump! = |version, latest, url| {
	if !Release.version_ok(version) {
		return Err("${version} is not a release version")
	}
	if !latest.is_empty() and !Release.version_ok(latest) {
		return Err("${latest} is not a release version")
	}
	compare = Cmd.new("roc").args(["bump", "--old", url, "platform/main.roc"].map(OsStr.from_str))
	if version == Release.dry_run {
		if latest.is_empty() {
			note!("release: no final release yet, so there is no API to compare with")
			return Ok({})
		}
		# A dry run chooses no version: report what the change needs.
		match step!(compare, "roc bump --old ${url} platform/main.roc") {
			Ok({}) => {}
			Err(problem) => warn!("release: the dry run could not compare the API with ${latest}: ${problem}")
		}
		return Ok({})
	}
	match Release.bump_plan(version, latest) {
		Ok(FirstRelease) => {
			note!("release: ${version} is the first release; there is no API to compare with")
			Ok({})
		}
		Ok(NewBoundary) => {
			note!("release: ${version} starts a new breaking boundary after ${latest}, which permits every API change")
			Ok({})
		}
		Ok(Compare) => step!(compare.args(["--expect", Release.number_part(version)].map(OsStr.from_str)), "roc bump --old ${url} --expect ${Release.number_part(version)} platform/main.roc")
		Err(NotAfter) => Err("${version} does not come after ${latest}, the latest release")
	}
}

## The systems the release cross-compiles the examples on.
cross_systems : List(Str)
cross_systems = ["x86_64-linux", "aarch64-linux", "x86_64-windows"]

## The Macs the cross-compiled programs are for: each system builds every
## example into `<target>/<example>` for both, and its `.app`s universal.
cross_targets : List(Str)
cross_targets = ["arm64mac", "x64mac"]

## Every recorded case against each system's cross-compiled apps for
## `target`, this Mac's own, which the artifact download leaves without
## their executable bits.
cross_run! : Str, Str, Str, Str => Try({}, Str)
cross_run! = |root, dir, cross, target| {
	for system in cross_systems {
		bin = "${cross}/cross-${system}"
		programs = "${bin}/${target}"
		note!("== apps cross-compiled on ${system}, for ${target}")
		for name in names_in!(programs)? {
			path = "${programs}/${name}"
			step!(Cmd.new("chmod").args(["+x", OsStr.from_str(path)]), "chmod +x ${path}")?
		}
		for name in names_in!(bin)?.keep_if(|name| name.ends_with(".app")) {
			path = "${bin}/${name}/Contents/MacOS/${name.drop_suffix(".app")}"
			step!(Cmd.new("chmod").args(["+x", OsStr.from_str(path)]), "chmod +x ${path}")?
		}
		test!(root, dir, Ok({ programs, apps: bin }))?
	}
	Ok({})
}

## What builds and tests a release, as its log and notes record it.
versions! : () => Try({}, Str)
versions! = || {
	for (program, args) in [("roc", ["version"]), ("roc-stable", ["version"]), ("swiftc", ["--version"]), ("xcodebuild", ["-version"])] {
		note!(capture!(program, args)?.trim())
	}
	Ok({})
}

## The files git tracks under the given paths.
tracked! : List(Str) => Try(List(Str), Str)
tracked! = |paths| {
	listed = capture!("git", ["ls-files", "--"].concat(paths))?
	Ok(listed.split_on("\n").keep_if(|line| !line.is_empty()))
}

capture! : Str, List(Str) => Try(Str, Str)
capture! = |program, args|
	Cmd.new(OsStr.from_str(program)).args(args.map(OsStr.from_str)).capture!().map_err(|error| "${program} ${Str.join_with(args, " ")} failed: ${Str.inspect(error)}")

read! : Str => Try(Str, Str)
read! = |path| Path.read_utf8!(Path.utf8(path)).map_err(|error| "could not read ${path}: ${Str.inspect(error)}")

## Write a file, creating its directory.
write! : Str, Str => Try({}, Str)
write! = |path, text| {
	parent = Str.join_with(path.split_on("/").drop_last(1), "/")
	Path.create_all!(Path.utf8(parent)) ? |error| "could not create ${parent}: ${Str.inspect(error)}"
	Path.write_utf8!(Path.utf8(path), text).map_err(|error| "could not write ${path}: ${Str.inspect(error)}")
}

## Copy a file byte for byte, creating its directory.
copy! : Str, Str => Try({}, Str)
copy! = |source, target| {
	parent = Str.join_with(target.split_on("/").drop_last(1), "/")
	Path.create_all!(Path.utf8(parent)) ? |error| "could not create ${parent}: ${Str.inspect(error)}"
	Path.copy!(Path.utf8(source), Path.utf8(target)).map_err(|error| "could not copy ${source} to ${target}: ${Str.inspect(error)}")
}

## Remove a directory and everything in it, then create it empty.
fresh! : Str => Try({}, _)
fresh! = |dir| {
	if Path.exists!(Path.utf8(dir))? {
		Path.delete_all!(Path.utf8(dir))?
	}
	Path.create_all!(Path.utf8(dir))
}

## Run a program with the terminal inherited; it must exit 0.
step! : Cmd.Command, Str => Try({}, Str)
step! = |command, shown| {
	note!("RUN ${shown}")
	output = command.inherit_stdio().run!() ? |error| "${shown} did not run: ${Str.inspect(error)}"
	match output.status {
		Exited(0) => Ok({})
		_ => Err("${shown} failed: ${Str.inspect(output.status)}")
	}
}

note! : Str => {}
note! = |line| Stdout.line!(line) ?? {}

warn! : Str => {}
warn! = |line| Stderr.line!(line) ?? {}
