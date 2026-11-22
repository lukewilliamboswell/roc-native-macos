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

## The `bundle` task: the platform bundle an app author's header names.
##
##     blueprint run bundle                              # build/platform/<hash>.tar.zst
##     blueprint run bundle -- --output-dir DIR          # somewhere else
##     blueprint run bundle -- --test                    # then create, build and test an app against it
##     blueprint run bundle -- --prebuilt                # bundle the inputs already built
##
## It builds the platform's native inputs (`scripts/build.sh --platform`)
## unless `--prebuilt`, stages the tracked `platform/*.roc` modules, the
## Swift host `targets/arm64mac/libhost.a`, the generated linker stubs
## `targets/macos-sysroot/` and the licence notices under `build/`, and runs
## `roc bundle` there. The output directory then holds exactly one
## content-addressed `<hash>.tar.zst`.
##
## `--test` checks the bundle as an author would use it. It copies the
## bundle to `build/bundle-test/served/` and serves that on localhost (the
## compiler accepts `http` only for localhost), makes the `macos.roc` tool
## there naming the served URLs (`scripts/release.roc -- tool`), and then,
## with an empty Roc package cache, takes an author's first steps outside
## the checkout: `roc macos.roc init counter`, then `build` and `test` in
## `counter/`, which runs the counter's recorded cases.
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
		step!(Cmd.new("bash").args(["scripts/build.sh", "--platform"]).env("ROC", "roc"), "scripts/build.sh --platform")?
	}
	for input in [Bundle.host_library, Bundle.sysroot] {
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
	Path.create_all!(Path.utf8("${stage}/targets/arm64mac"))?
	Path.copy!(Path.utf8("platform/${Bundle.host_library}"), Path.utf8("${stage}/${Bundle.host_library}"))?
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
## it there, and create, build and test a counter with the tool.
consumer_test! : Str, Str, Str => Try({}, _)
consumer_test! = |root, out, bundle| {
	dir = "${root}/build/bundle-test"
	served_dir = "${dir}/served"
	fresh!(dir)?
	Path.create_all!(Path.utf8(served_dir))?
	Path.copy!(Path.utf8("${out}/${bundle}"), Path.utf8("${served_dir}/${bundle}"))?
	server = Cmd.new("python3")
		.args(["-I", "-u", "-m", "http.server", "0", "--bind", "::", "--directory", OsStr.from_str(served_dir)])
		.stdin(Null)
		.stdout(Pipe)
		.stderr(MergeWithStdout)
		.spawn!()?
	result = match served!(server) {
		Ok(port) => first_steps!(root, dir, "http://localhost:${port.to_str()}")
		Err(problem) => Err(problem)
	}
	server.kill!() ?? {}
	server.close!() ?? {}
	match result {
		Ok({}) => {
			note!("bundle: macos.roc created, built and tested a counter against the served bundle")
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
	match server.read!(Duration.seconds(10)) {
		Ok(Stdout(bytes)) => Bundle.served_port(Str.from_utf8_lossy(bytes)).map_err(|_| "the local server printed no port: ${Str.from_utf8_lossy(bytes)}")
		Ok(Stderr(bytes)) => Err("the local server failed: ${Str.from_utf8_lossy(bytes)}")
		Err(error) => Err("the local server did not start: ${Str.inspect(error)}")
	}

## `roc macos.roc init counter`, then `build` and `test`, as an author takes
## them, with the tool and the platform fetched from `base_url`.
first_steps! : Str, Str, Str => Try({}, Str)
first_steps! = |root, dir, base_url| {
	served_dir = "${dir}/served"
	cache = "${dir}/cache"
	step!(Cmd.new("roc-stable").args(["${root}/scripts/release.roc", "--", "tool", Bundle.test_version, served_dir, "--base-url", base_url].map(OsStr.from_str)), "scripts/release.roc -- tool ${Bundle.test_version} build/bundle-test/served --base-url ${base_url}") ? |_| "the macos.roc tool could not be made"
	Path.copy!(Path.utf8("${served_dir}/macos.roc"), Path.utf8("${dir}/macos.roc")) ? |error| "could not copy macos.roc: ${Str.inspect(error)}"
	Path.create_all!(Path.utf8(cache)) ? |error| "could not create ${cache}: ${Str.inspect(error)}"
	note!("bundle: an author's first steps in ${dir}, package cache ${cache}")
	for { args, cwd } in Bundle.first_steps {
		shown = "roc macos.roc ${Str.join_with(args, " ")}${if (cwd.is_empty()) "" else " (in ${cwd}/)"}"
		step!(Cmd.new("roc").args(["macos.roc"].concat(args).map(OsStr.from_str)).cwd(Path.utf8(if (cwd.is_empty()) dir else "${dir}/${cwd}")).env("XDG_CACHE_HOME", OsStr.from_str(cache)), shown) ? |_| "${shown} failed against the bundle"
	}
	Ok({})
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
