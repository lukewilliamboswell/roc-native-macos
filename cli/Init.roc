import cli.Path
import cli.Stdout
import Bundle

## `init [DIR]`: create an app, a counter with two recorded cases, in `DIR`
## (by default, this directory). It writes only files that are not there
## yet, and copies this directory's `macos.roc` into a new directory so the
## app can run the tool from its own.
Init :: [].{

	## What `init` writes: a file's path in the app, and its text or the
	## file it is copied from.
	Step : { path : Str, contents : [Text(Str), CopyOf(Str)] }

	## Every file `init` writes into `dir`. `main.roc` names the release's
	## platform.
	plan : Str -> List(Step)
	plan = |dir| {
		tool = if (dir == ".") [] else [{ path: "macos.roc", contents: CopyOf("macos.roc") }]
		scaffold = Bundle.scaffold.map(
			|file| {
				text = if (file.path == "main.roc") Init.with_platform(file.text, Bundle.platform_url) else file.text
				{ path: file.path, contents: Text(text) }
			},
		)
		tool.concat(scaffold).append({ path: ".gitignore", contents: Text(gitignore) })
	}

	## Create the app, after checking that no file it writes already exists
	## and, for a new directory, that there is a `macos.roc` here to copy.
	run! : Str => Try({}, _)
	run! = |dir| {
		steps = Init.plan(dir)
		for step in steps {
			target = Init.place(dir, step.path)
			if Path.exists!(Path.utf8(target))? {
				return Err(InitWouldOverwrite(target))
			}
		}
		if dir != "." and !(Path.exists!(Path.utf8("macos.roc"))?) {
			return Err(NoToolToCopy(dir))
		}
		for step in steps {
			target = Init.place(dir, step.path)
			parent = Str.join_with(target.split_on("/").drop_last(1), "/")
			if !parent.is_empty() {
				Path.create_all!(Path.utf8(parent))?
			}
			match step.contents {
				Text(text) => Path.write_utf8!(Path.utf8(target), text)?
				CopyOf(source) => Path.copy!(Path.utf8(source), Path.utf8(target))?
			}
		}
		Stdout.line!(Init.summary(dir))?
		Ok({})
	}

	## Where a file of the app goes when the app is created in `dir`.
	place : Str, Str -> Str
	place = |dir, path| if (dir == ".") path else "${dir.drop_suffix("/")}/${path}"

	## A `main.roc` naming `url` as its platform in place of whatever its
	## header named.
	with_platform : Str, Str -> Str
	with_platform = |source, url|
		match source.split_on("platform \"") {
			[before, rest, ..] =>
				match rest.split_on("\"") {
					[_, .. as after] => "${before}platform \"${url}\"${Str.join_with(after, "\"")}"
					_ => source
				}
			_ => source
		}

	## What `init` prints: what it made, and what to do next.
	summary : Str -> Str
	summary = |dir| {
		next = if (dir == ".") "  roc macos.roc run" else "  cd ${dir}\n  roc macos.roc run"
		"Created a counter app on roc-native-macos ${Bundle.version}:\n\n  main.roc    the app: its state, view and program\n  tests/      recorded runs of it, which `roc macos.roc test` checks\n  macos.roc   the tool, which builds, runs and tests it\n  .gitignore  keeps build output out of version control\n\nNext, run the app (on an Apple silicon Mac; `build` works anywhere):\n\n${next}"
	}
}

gitignore =
	\\# Written by `roc macos.roc`: the build directory and the app.
	\\/.macos/
	\\/*.app/
	\\

## The scaffold names the release's platform, not a path.
expect {
	source = "app [main] { pf: platform \"../../platform/main.roc\" }\n\nimport pf.Engine\n"
	Init.with_platform(source, "https://x/0.0.1/h.tar.zst") == "app [main] { pf: platform \"https://x/0.0.1/h.tar.zst\" }\n\nimport pf.Engine\n"
}

## A new directory gets a copy of the tool; this directory already has it.
## Every plan writes the app, its recorded cases and the `.gitignore`.
expect {
	new = Init.plan("my-app").map(|step| step.path)
	here = Init.plan(".").map(|step| step.path)
	new.first() == Ok("macos.roc") and here.first() == Ok("main.roc") and new.drop_first(1) == here and here.contains(".gitignore") and here.any(|path| path.starts_with("tests/") and path.ends_with(".script"))
}

expect [Init.place("my-app/", "main.roc"), Init.place(".", "tests/a.script")] == ["my-app/main.roc", "tests/a.script"]
