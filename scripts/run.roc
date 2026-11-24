#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	roc: "nightly-2026-11-22-3350b1c",
}

import cli.Cmd
import cli.OsStr
import cli.Path
import cli.Stderr
import cli.Stdout

## The `run` task: start one example from the checkout, as `roc src/main.roc`
## from the example's directory, so it finds its `assets/` and reloads as
## you save:
##
##     blueprint run run -- about
##
## It builds the platform's host for this Mac first when it is not built
## (`scripts/build.roc -- --platform`), and runs the `roc` on PATH, the
## nightly the platform is developed with. With no name, or a name that is
## not an example, it lists the examples.
main! : List(OsStr) => Try({}, _)
main! = |raw| {
	args = raw.map(OsStr.display).drop_if(|arg| arg == "--")
	examples = examples!()
	name = match args {
		[one] if examples.contains(one) => one
		[one] => {
			Stderr.line!("run: ${one} is not an example; the examples are ${Str.join_with(examples, ", ")}")?
			return Err(Exit(2))
		}
		_ => {
			Stderr.line!("run: name one example: blueprint run run -- NAME, where NAME is one of ${Str.join_with(examples, ", ")}")?
			return Err(Exit(2))
		}
	}
	target = native_target!()
	if !(Path.exists!(Path.utf8("platform/targets/${target}/libhost.a")) ?? Bool.False) {
		Stdout.line!("run: the ${target} host is not built; building the platform first")?
		built = Cmd.new("roc-stable").args(["scripts/build.roc", "--", "--platform"]).env("ROC", "roc").inherit_stdio().run!()?
		if built.status != Exited(0) {
			Stderr.line!("run: the platform did not build")?
			return Err(Exit(1))
		}
	}
	Stdout.line!("run: roc src/main.roc in examples/${name}")?
	ran = Cmd.new("roc").args(["src/main.roc"]).cwd(Path.utf8("examples/${name}")).inherit_stdio().run!()?
	match ran.status {
		Exited(0) => Ok({})
		Exited(code) => Err(Exit(code))
		Signaled(signal) => Err(Exit(128 + signal))
	}
}

## Every directory under `examples/` with a `src/main.roc`, sorted.
examples! : () => List(Str)
examples! = || {
	names = match Path.list!(Path.utf8("examples")) {
		Ok(paths) => paths.keep_oks(|path| Path.filename(path).map_ok(Path.display))
		Err(_) => []
	}
	var $found = []
	for name in names {
		if Path.exists!(Path.utf8("examples/${name}/src/main.roc")) ?? Bool.False {
			$found = $found.append(name)
		}
	}
	$found.sort_with(compare)
}

## The platform target this Mac runs natively.
native_target! : () => Str
native_target! = || {
	machine = Cmd.new("uname").args(["-m"]).capture!() ?? "arm64"
	if (machine.trim() == "x86_64") "x64mac" else "arm64mac"
}

## Byte order, for a stable listing.
compare : Str, Str -> [Before, Same, After]
compare = |a, b| {
	xs = a.to_utf8()
	ys = b.to_utf8()
	var $i = 0
	while $i < xs.len() and $i < ys.len() {
		x = xs.get($i) ?? 0
		y = ys.get($i) ?? 0
		if x < y {
			return Before
		}
		if x > y {
			return After
		}
		$i = $i + 1
	}
	if (xs.len() < ys.len()) Before else if (xs.len() > ys.len()) After else Same
}

expect compare("about", "arith") == Before and compare("todos", "counter") == After and compare("a", "a") == Same
