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
import src/Release
import src/SpecRun

## The `bundle` task: the platform bundle an app author's header names.
##
##     blueprint run bundle                              # build/platform/<hash>.tar.zst
##     blueprint run bundle -- --output-dir DIR          # somewhere else
##     blueprint run bundle -- --test                    # then create, build and test an app against it
##     blueprint run bundle -- --prebuilt                # bundle the inputs already built
##
## It builds the platform's native inputs (`scripts/build.roc -- --platform`)
## unless `--prebuilt`, stages the tracked `platform/*.roc` modules, the
## Swift hosts `targets/arm64mac/libhost.a` and `targets/x64mac/libhost.a`
## (Apple silicon and Intel), the generated linker stubs
## `targets/macos-sysroot/` and the licence notices under `build/`, and runs
## `roc bundle` there. The output directory then holds exactly one
## content-addressed `<hash>.tar.zst`.
##
## `--test` checks the bundle as an author would use it. It copies the
## bundle to `build/bundle-test/served/` and serves that on localhost (the
## compiler accepts `http` only for localhost), makes the `macos.roc` tool
## there naming the served URLs (`scripts/release.roc -- tool`), and then,
## with an empty Roc package cache, takes an author's first steps outside
## the checkout: `roc run URL init my-app`, which writes the starter app
## (`examples/starter`, with `src/main.roc`), then `build`, `test` (its
## `expect`s and specs) and `fuzz --check` (its roc-fuzz targets) in
## `my-app/`; then `roc macos.roc init --simple my-counter`, which writes
## the counter (`examples/counter`), and `test` in `my-counter/`, which
## builds it and runs its specs. It packages the starter twice with
## `macos.roc package`, and
## checks that the two zips are
## the same bytes, hold the sealed bundle with each entry's Unix mode, and
## extract with `ditto` to an app whose seal verifies and whose program runs
## a spec; `actionlint`, when it is on PATH, lints the release
## workflow `init` wrote. Then it builds and
## tests an app with assets, `examples/about` with its `assets/` and
## specs, through the tool, checks that its bundle holds the assets
## and an icon made from `assets/icon.png`, and runs a case on the program
## inside the bundle, which must find its images in `Contents/Resources`.
## Last, it runs that case under `roc macos.roc dev`, whose bare program
## must find them in `assets/` of the app's directory.
##
## The package compiler is the `roc` on PATH.
main! : List(OsStr) => Try({}, _)
main! = |raw_args| {
	options = match Bundle.options(raw_args.map(OsStr.display)) {
		Ok(found) => found
		Err(Unknown(arg)) => {
			warn!("bundle: unknown option ${arg}; the options are --output-dir DIR, --prebuilt and --test")
			return Err(Exit(2))
		}
		Err(MissingValue(arg)) => {
			warn!("bundle: ${arg} needs a value")
			return Err(Exit(2))
		}
	}
	root = Env.cwd!()?.display()
	out = if (options.output_dir.starts_with("/")) options.output_dir else "${root}/${options.output_dir}"
	if !options.prebuilt {
		step!(Cmd.new("roc-stable").args(["scripts/build.roc", "--", "--platform"]).env("ROC", "roc"), "scripts/build.roc -- --platform")?
	}
	for input in Bundle.host_libraries.append(Bundle.sysroot) {
		if !(Path.exists!(Path.utf8("platform/${input}"))?) {
			warn!("bundle: platform/${input} is not built: run `blueprint run build` (or drop --prebuilt)")
			return Err(Exit(1))
		}
	}

	# Stage the platform with its notices, so `roc bundle` sees one tree.
	stage = "${root}/build/bundle-stage"
	fresh!(stage)?
	listed = Cmd.new("git").args(["ls-files", "--", "platform/*.roc"]).capture!()?
	modules = listed.split_on("\n").keep_if(|line| !line.is_empty()).map(|path| path.drop_prefix("platform/"))
	for name in modules {
		Path.copy!(Path.utf8("platform/${name}"), Path.utf8("${stage}/${name}"))?
	}
	for library in Bundle.host_libraries {
		Path.create_all!(Path.utf8("${stage}/${Str.join_with(library.split_on("/").drop_last(1), "/")}"))?
		Path.copy!(Path.utf8("platform/${library}"), Path.utf8("${stage}/${library}"))?
	}
	Path.copy_dir!(Path.utf8("platform/${Bundle.sysroot}"), Path.utf8("${stage}/${Bundle.sysroot}"))?
	for notice in Bundle.notices {
		Path.copy!(Path.utf8(notice), Path.utf8("${stage}/${notice}"))?
	}
	target_files = walk!(stage, "targets")?
	files = Bundle.files(modules, target_files)

	fresh!(out)?
	step!(Cmd.new("roc").args(["bundle"].concat(files).concat(["--output-dir", out]).map(OsStr.from_str)).cwd(Path.utf8(stage)), "roc bundle (${files.len().to_str()} files)")?
	bundle = match Path.list!(Path.utf8(out))?.map(Path.display).keep_if(|path| path.ends_with(".tar.zst")) {
		[one] => Path.filename(Path.utf8(one))?.display()
		found => {
			warn!("bundle: roc bundle wrote ${found.len().to_str()} .tar.zst files to ${out}, not one")
			return Err(Exit(1))
		}
	}
	digest = Cmd.new("shasum").args(["-a", "256", "${out}/${bundle}"]).capture!()?.split_on(" ").first() ?? ""
	size = Path.size_in_bytes!(Path.utf8("${out}/${bundle}"))?
	note!("bundle: ${out}/${bundle}")
	note!("bundle: ${size.to_str()} bytes, sha256 ${digest}")
	if options.test {
		consumer_test!(root, out, bundle)?
	}
	Ok({})
}

## Serve a copy of the bundle on localhost, make the `macos.roc` tool naming
## it there, and create, build, test and package an app with the tool.
consumer_test! : Str, Str, Str => Try({}, _)
consumer_test! = |root, out, bundle| {
	dir = "${root}/build/bundle-test"
	served_dir = "${dir}/served"
	fresh!(dir)?
	Path.create_all!(Path.utf8(served_dir))?
	Path.copy!(Path.utf8("${out}/${bundle}"), Path.utf8("${served_dir}/${bundle}"))?
	server = Cmd.new("python3")
		.args(["-I", "-u", "-c", OsStr.from_str(Bundle.serve_script), OsStr.from_str(served_dir)])
		.stdin(Null)
		.stdout(Pipe)
		.stderr(MergeWithStdout)
		.spawn!()?
	result = match served!(server) {
		Ok(port) =>
			match first_steps!(root, dir, "http://localhost:${port.to_str()}") {
				Ok({}) =>
					match package_app!(dir) {
						Ok({}) => assets_app!(root, dir, "http://localhost:${port.to_str()}/${bundle}")
						Err(problem) => Err(problem)
					}
				Err(problem) => Err(problem)
			}
		Err(problem) => Err(problem)
	}
	server.kill!() ?? {}
	server.close!() ?? {}
	match result {
		Ok({}) => {
			note!("bundle: macos.roc created, built, tested and packaged the starter app, created and tested the counter with init --simple, and built, tested and ran under dev ${Bundle.assets_example} with its assets, against the served bundle")
			Ok({})
		}
		Err(problem) => {
			warn!("bundle: ${problem}")
			Err(Exit(1))
		}
	}
}

## The port the server reports, from its first line of output.
served! : Cmd.Child => Try(U16, Str)
served! = |server|
	match server.read!(Duration.seconds(30)) {
		Ok(Stdout(bytes)) => Bundle.served_port(Str.from_utf8_lossy(bytes)).map_err(|_| "the local server printed no port: ${Str.from_utf8_lossy(bytes)}")
		Ok(Stderr(bytes)) => Err("the local server failed: ${Str.from_utf8_lossy(bytes)}")
		Err(error) => Err("the local server did not start: ${Str.inspect(error)}")
	}

## `roc run URL init my-app`, then `build`, `test` and `fuzz --check`
## (not on an Intel Mac, which roc-fuzz does not run on), and
## `init --simple my-counter` and `test` there, as an author takes them,
## with the tool and the platform fetched from `base_url`.
first_steps! : Str, Str, Str => Try({}, Str)
first_steps! = |root, dir, base_url| {
	served_dir = "${dir}/served"
	cache = "${dir}/cache"
	step!(Cmd.new("roc-stable").args(["${root}/scripts/release.roc", "--", "tool", Bundle.test_version, served_dir, "--base-url", base_url].map(OsStr.from_str)), "scripts/release.roc -- tool ${Bundle.test_version} build/bundle-test/served --base-url ${base_url}") ? |_| "the macos.roc tool could not be made"
	entries = (Path.list!(Path.utf8(served_dir)) ? |error| "could not list ${served_dir}: ${Str.inspect(error)}").keep_oks(|path| Path.filename(path).map_ok(Path.display))
	bootstrap = match entries.keep_if(Release.is_bootstrap_bundle) {
		[file] => "${base_url}/${file}"
		_ => return Err("expected one bootstrap bundle in ${served_dir}")
	}
	Path.create_all!(Path.utf8(cache)) ? |error| "could not create ${cache}: ${Str.inspect(error)}"
	note!("bundle: an author's first steps in ${dir}, package cache ${cache}")
	machine = Cmd.new("uname").args(["-m"]).capture!() ?? ""
	if machine.trim() == "x86_64" {
		note!("bundle: roc-fuzz has no Intel Mac target, so this Intel Mac skips `roc macos.roc fuzz --check`")
	}
	for { args, cwd } in Bundle.first_steps_on(machine.trim()) {
		entry = if (args.first() == Ok("init")) ["run", bootstrap] else ["macos.roc"]
		shown = "roc ${Str.join_with(entry.concat(args), " ")}${if (cwd.is_empty()) "" else " (in ${cwd}/)"}"
		step!(Cmd.new("roc").args(entry.concat(args).map(OsStr.from_str)).cwd(Path.utf8(if (cwd.is_empty()) dir else "${dir}/${cwd}")).env("XDG_CACHE_HOME", OsStr.from_str(cache)), shown) ? |_| "${shown} failed against the bundle"
	}
	Ok({})
}

## `roc macos.roc ci package` the app `init` made, twice, as the release
## workflow `init` wrote does for a pushed pre-release tag
## with no secrets: both zips must be the same bytes, hold exactly the entries
## `Bundle.package_entries` names with their modes, pass `unzip -t`, and
## extract with `ditto` (as Archive Utility does) to an app whose seal
## `codesign --verify --strict` accepts and whose program runs a
## spec, and whose Info.plist has the tag's version. The workflow is linted
## when actionlint is on PATH.
package_app! : Str => Try({}, Str)
package_app! = |dir| {
	app_dir = "${dir}/my-app"
	cache = "${dir}/cache"
	zip = "${app_dir}/${Bundle.package_zip}"
	shown = "roc macos.roc ${Str.join_with(Bundle.package_args, " ")} (in my-app/)"
	var $digests = []
	for _ in ["first", "second"] {
		command = Bundle.package_env.fold(
			Cmd.new("roc").args(["macos.roc"].concat(Bundle.package_args).map(OsStr.from_str)).cwd(Path.utf8(app_dir)).env("XDG_CACHE_HOME", OsStr.from_str(cache)),
			|cmd, (name, value)| cmd.env(OsStr.from_str(name), OsStr.from_str(value)),
		)
		step!(command, shown) ? |_| "${shown} failed against the bundle"
		digest = Cmd.new("shasum").args(["-a", "256", OsStr.from_str(zip)]).capture!() ? |_| "could not take the digest of ${zip}"
		$digests = $digests.append(digest.split_on(" ").first() ?? "")
	}
	match $digests {
		[a, b] if a == b => note!("bundle: packaged twice, the same zip both times: sha256 ${a}")
		_ => return Err("roc macos.roc package made different zips from the same app: ${Str.join_with($digests, " and ")}")
	}
	bytes = Path.read_bytes!(Path.utf8(zip)) ? |error| "could not read ${zip}: ${Str.inspect(error)}"
	entries = Bundle.zip_entries(bytes) ? |_| "${zip} is not a zip archive"
	if entries != Bundle.package_entries {
		listed = Str.join_with(entries.map(|e| "${e.name} ${e.mode.to_str()}"), ", ")
		return Err("${zip} holds other entries or modes than a sealed my-app.app should: ${listed}")
	}
	step!(Cmd.new("unzip").args(["-tq", OsStr.from_str(zip)]), "unzip -tq ${Bundle.package_zip}") ? |_| "unzip found ${zip} damaged"
	extracted = "${dir}/extracted"
	fresh!(extracted) ? |_| "could not empty ${extracted}"
	step!(Cmd.new("ditto").args(["-x", "-k", OsStr.from_str(zip), OsStr.from_str(extracted)]), "ditto -x -k ${Bundle.package_zip}") ? |_| "ditto could not extract ${zip}"
	extracted_app = "${extracted}/my-app.app"
	step!(Cmd.new("codesign").args(["--verify", "--strict", "--verbose=2", OsStr.from_str(extracted_app)]), "codesign --verify --strict the extracted my-app.app") ? |_| "the extracted my-app.app's seal does not verify"
	plist = Path.read_utf8!(Path.utf8("${extracted_app}/Contents/Info.plist")) ? |error| "could not read the extracted Info.plist: ${Str.inspect(error)}"
	for line in Bundle.package_plist {
		if !plist.contains(line) {
			return Err("the packaged my-app.app's Info.plist does not hold ${line}, for the tag v1.0.0-rc.1")
		}
	}
	spec = "tests/specs/${Bundle.package_case}.scm"
	note!("RUN the extracted my-app.app/Contents/MacOS/my-app with ${spec}")
	passes!({ program: "${extracted_app}/Contents/MacOS/my-app", dir: app_dir, spec, update: Bool.False, metrics: Bool.False, args: [], env: [] }, "the extracted my-app.app's program")?
	workflow = "${app_dir}/.github/workflows/release.yml"
	if Cmd.check_available!("actionlint") {
		step!(Cmd.new("actionlint").args([OsStr.from_str(workflow)]), "actionlint my-app/.github/workflows/release.yml") ? |_| "actionlint found problems in the workflow init writes"
	} else {
		note!("bundle: actionlint is not on PATH, so the workflow init writes was not linted")
	}
	Ok({})
}

## The repository's example with assets, as an author would have it beside
## the tool: `src/main.roc` naming the served bundle, `assets/` and
## `tests/specs/`.
## `macos.roc build` and `test` it, check the bundle it made, and run its
## spec on the program inside the bundle, then under `macos.roc dev`.
assets_app! : Str, Str, Str => Try({}, Str)
assets_app! = |root, dir, url| {
	name = Bundle.assets_example
	app_dir = "${dir}/${name}"
	cache = "${dir}/cache"
	source = Path.read_utf8!(Path.utf8("${root}/examples/${name}/src/main.roc")) ? |error| "could not read examples/${name}/src/main.roc: ${Str.inspect(error)}"
	served = Bundle.released_main(source, url) ? |_| "examples/${name}/src/main.roc does not name ../../../platform/main.roc"
	for sub in ["tests/specs", "src"] {
		Path.create_all!(Path.utf8("${app_dir}/${sub}")) ? |error| "could not create ${app_dir}/${sub}: ${Str.inspect(error)}"
	}
	Path.write_utf8!(Path.utf8("${app_dir}/src/main.roc"), served) ? |error| "could not write ${app_dir}/src/main.roc: ${Str.inspect(error)}"
	Path.copy_dir!(Path.utf8("${root}/examples/${name}/assets"), Path.utf8("${app_dir}/assets")) ? |error| "could not copy examples/${name}/assets: ${Str.inspect(error)}"
	spec = "tests/specs/${Bundle.assets_case}.scm"
	Path.copy!(Path.utf8("${root}/examples/${name}/${spec}"), Path.utf8("${app_dir}/${spec}")) ? |error| "could not copy ${spec}: ${Str.inspect(error)}"
	Path.copy!(Path.utf8("${dir}/my-app/macos.roc"), Path.utf8("${app_dir}/macos.roc")) ? |error| "could not copy macos.roc: ${Str.inspect(error)}"
	for command in ["build", "test"] {
		shown = "roc macos.roc ${command} (in ${name}/)"
		step!(Cmd.new("roc").args(["macos.roc", command].map(OsStr.from_str)).cwd(Path.utf8(app_dir)).env("XDG_CACHE_HOME", OsStr.from_str(cache)), shown) ? |_| "${shown} failed against the bundle"
	}
	resources = "${app_dir}/${name}.app/Contents/Resources"
	for file in Bundle.assets_expected {
		if !(Path.exists!(Path.utf8("${resources}/${file}")) ?? Bool.False) {
			return Err("roc macos.roc build put no ${file} in ${name}.app/Contents/Resources")
		}
	}
	plist = Path.read_utf8!(Path.utf8("${app_dir}/${name}.app/Contents/Info.plist")) ? |error| "could not read ${name}.app's Info.plist: ${Str.inspect(error)}"
	if !plist.contains("<key>CFBundleIconFile</key><string>AppIcon</string>") {
		return Err("${name}.app's Info.plist names no icon")
	}
	# The program inside the bundle, which has no assets/ beside it.
	note!("RUN ${name}.app/Contents/MacOS/${name} with ${spec}")
	passes!({ program: "${app_dir}/${name}.app/Contents/MacOS/${name}", dir: app_dir, spec, update: Bool.False, metrics: Bool.False, args: [], env: [] }, "${name}.app's own program")?
	# `macos.roc dev`: `roc ../src/main.roc` from .macos/, pointed at assets/ here.
	note!("RUN roc macos.roc dev (in ${name}/) with ${spec}")
	passes!({ program: "roc", dir: app_dir, spec, update: Bool.False, metrics: Bool.False, args: ["macos.roc", "dev"], env: [("XDG_CACHE_HOME", cache)] }, "roc macos.roc dev (in ${name}/)")
}

## A spec run that must pass, or the reason it did not.
passes! : SpecRun.Run, Str => Try({}, Str)
passes! = |run, what|
	match SpecRun.run!(run) {
		Ok(Passed) | Ok(Updated) | Ok(Measured(_)) => Ok({})
		Ok(Failed(problems)) => Err("${what} did not pass ${run.spec}:\n  ${Str.join_with(problems, "\n  ")}")
		Err(error) => Err("${what} could not run ${run.spec}: ${Str.inspect(error)}")
	}

## Every file under `base/sub`, relative to `base`.
walk! : Str, Str => Try(List(Str), _)
walk! = |base, sub| {
	var $found = []
	for entry in Path.list!(Path.utf8("${base}/${sub}"))? {
		name = Path.filename(entry)?.display()
		relative = "${sub}/${name}"
		if Path.is_dir!(entry)? {
			$found = $found.concat(walk!(base, relative)?)
		} else {
			$found = $found.append(relative)
		}
	}
	Ok($found)
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
step! : Cmd.Command, Str => Try({}, _)
step! = |command, shown| {
	note!("RUN ${shown}")
	output = command.inherit_stdio().run!()?
	match output.status {
		Exited(0) => Ok({})
		_ => {
			warn!("bundle: ${shown} failed: ${Str.inspect(output.status)}")
			Err(Exit(1))
		}
	}
}

note! : Str => {}
note! = |line| Stdout.line!(line) ?? {}

warn! : Str => {}
warn! = |line| Stderr.line!(line) ?? {}
