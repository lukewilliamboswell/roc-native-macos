#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	roc: "nightly-2026-11-14-a87808d",
}

import cli.Cmd
import cli.Duration
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stderr
import cli.Stdout
import src/Bundle
import src/Release
import src/Repo

## The `release` task: the steps of `.github/workflows/release.yml` after the
## bundle exists. Each works on a release directory that holds the bundle,
## as `blueprint run bundle -- --output-dir DIR` writes it.
##
##     blueprint run release -- archive VERSION DIR       # DIR/roc-native-macos-examples-VERSION.zip
##     blueprint run release -- test DIR                  # build and run the archived examples against DIR's bundle
##     blueprint run release -- test DIR --binaries BIN   # run the archived examples' cases on prebuilt apps in BIN
##     blueprint run release -- notes VERSION DIR OUT     # the release notes, as Markdown, to OUT
##
## `archive` writes the examples archive: every example with its header
## naming the bundle's release URL (`GITHUB_REPOSITORY`, the version and the
## bundle's file name), and the recorded cases and fixtures they run with.
##
## `test` checks those exact files as an app author meets them. It unpacks
## the archive, serves DIR on localhost in place of the release URL (the
## compiler accepts `http` only for localhost), builds every example with an
## empty package cache and runs every recorded case against it. With
## `--binaries BIN` it builds nothing and runs the cases against `BIN/<example>`,
## apps cross-compiled on another system from the same archive and bundle.
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
		["archive", version, dir] => archive!(root, version, absolute(root, dir))
		["test", dir] => test!(root, absolute(root, dir), Err(NoBinaries))
		["test", dir, "--binaries", bin] => test!(root, absolute(root, dir), Ok(absolute(root, bin)))
		["notes", version, dir, out] => notes!(version, absolute(root, dir), absolute(root, out))
		_ => Err("usage: release archive VERSION DIR | test DIR [--binaries BIN] | notes VERSION DIR OUT")
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
	found = names_in!(dir)?.keep_if(|name| name.ends_with(".tar.zst"))
	match found {
		[one] => Ok(one)
		_ => Err("${dir} holds ${found.len().to_str()} .tar.zst files, not one")
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
	for path in tracked!(["tests/examples", "tests/fixtures"])? {
		write!("${top}/${path}", read!(path)?)?
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
			"macOS 11 or later. On a system other than an Apple silicon Mac, pass the",
			"target:",
			"",
			"    cd examples/counter",
			"    roc build main.roc --target=arm64mac",
			"",
			"`tests/examples/<example>/<case>.script` holds the steps of a recorded run",
			"and `<case>.expected` what the app prints. Run a case from this directory,",
			"the one that holds `tests/`:",
			"",
			"    ROC_SCRIPT=\"$(cat tests/examples/counter/increment.script)\" ./examples/counter/main",
			"",
			"The window's size is written `--- <size>`, and this directory's path",
			"`<repo>`, where the output printed the path.",
		],
		"\n",
	)

## Build every archived example against the served bundle and run its
## recorded cases, or run them against prebuilt apps.
test! : Str, Str, Try(Str, [NoBinaries]) => Try({}, Str)
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
	apps = match binaries {
		Ok(bin) => bin
		Err(NoBinaries) => {
			build_all!(work, top, dir, bundle, examples)?
			"${work}/apps"
		}
	}
	var $failed = []
	var $passed = 0.U64
	for example in examples {
		exe = "${apps}/${example}"
		cases = names_in!("${top}/tests/examples/${example}")?.keep_oks(Repo.case_name)
		if cases.is_empty() {
			$failed = $failed.append("${example} has no recorded case")
		}
		for name in cases {
			match run_case!(top, exe, "tests/examples/${example}/${name}") {
				Ok({}) => {
					note!("release: PASS ${example}/${name}")
					$passed = $passed + 1
				}
				Err(problem) => {
					warn!("release: FAIL ${example}/${name}: ${problem}")
					$failed = $failed.append("${example}/${name}")
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
## it, with an empty package cache, into `work/apps/<example>`.
build_all! : Str, Str, Str, Str, List(Str) => Try({}, Str)
build_all! = |work, top, dir, bundle, examples| {
	server = Cmd.new("python3")
		.args(["-I", "-u", "-m", "http.server", "0", "--bind", "::", "--directory", OsStr.from_str(dir)])
		.stdin(Null)
		.stdout(Pipe)
		.stderr(MergeWithStdout)
		.spawn!() ? |error| "could not start the local server: ${Str.inspect(error)}"
	result = match served!(server) {
		Ok(port) => build_each!(work, top, "http://localhost:${port.to_str()}/${bundle}", bundle, examples)
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

## The port Python's server reports, from its first line of output.
served! : Cmd.Child => Try(U16, Str)
served! = |server|
	match server.read!(Duration.seconds(10)) {
		Ok(Stdout(bytes)) => Bundle.served_port(Str.from_utf8_lossy(bytes)).map_err(|_| "the local server printed no port: ${Str.from_utf8_lossy(bytes)}")
		Ok(Stderr(bytes)) => Err("the local server failed: ${Str.from_utf8_lossy(bytes)}")
		Err(error) => Err("the local server did not start: ${Str.inspect(error)}")
	}

## One recorded case, run from the archive's top directory as `blueprint run
## examples` runs it from the checkout: exit 0, and print exactly the
## recorded output with that directory written `<repo>`.
run_case! : Str, Str, Str => Try({}, Str)
run_case! = |top, exe, base| {
	if !(Path.exists!(Path.utf8(exe)) ?? Bool.False) {
		return Err("${exe} does not exist")
	}
	steps = read!("${top}/${base}.script")?.trim()
	expected = read!("${top}/${base}.expected")?
	output = Cmd.new(OsStr.from_str(exe))
		.cwd(Path.utf8(top))
		.env("ROC_SCRIPT", OsStr.from_str(steps))
		.stdin(Null)
		.stderr(MergeWithStdout)
		.timeout(Duration.seconds(60))
		.run!() ? |error| "${exe} did not finish: ${Str.inspect(error)}"
	printed = Repo.portable(Str.from_utf8_lossy(output.stdout_bytes), top)
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
	rendered = match Release.render_notes({ source: read!(source_path)?, version: notes_version, platform_url: "${root_url}/${bundle}", examples_url: "${root_url}/${Release.examples_name(version)}.zip" }) {
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
				"The bundle's SBOM documents sit beside it, bound to its SHA-256: SPDX 3",
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
