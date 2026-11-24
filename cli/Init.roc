import cli.Env
import cli.Path
import cli.Stdout
import App
import Bundle
import Meta
import Workflow

## `init [DIR]`: create an app in `DIR` (by default, this directory): the
## starter example, an expense tracker with a logic package, fuzz targets,
## an icon and recorded cases. It writes only files that are not there yet,
## and copies this directory's `macos.roc` into a new directory so the app
## can run the tool from its own.
Init :: [].{

	## What `init` writes: a file's path in the app, and its text, its bytes
	## or the file it is copied from.
	Step : { path : Str, contents : [Text(Str), Bytes(List(U8)), CopyOf(Str)] }

	## Every file `init` writes into `dir`, for the app whose name is `name`.
	## The app's root module names the release's platform.
	plan : Str, Str -> List(Step)
	plan = |dir, name| {
		tool = if (dir == ".") [] else [{ path: "macos.roc", contents: CopyOf("macos.roc") }]
		scaffold = Bundle.scaffold.map(
			|file|
				match file.contents {
					Text(text) if file.path == App.nested_entry => { path: file.path, contents: Text(Init.with_platform(text, Bundle.platform_url)) }
					Text(text) => { path: file.path, contents: Text(text) }
					Bytes(bytes) => { path: file.path, contents: Bytes(bytes) }
				},
		)
		tool.concat(scaffold).concat([
			{ path: Meta.file, contents: Text(Meta.starter(name)) },
			{ path: ".gitignore", contents: Text(gitignore) },
			{ path: Workflow.path, contents: Text(Workflow.text) },
		])
	}

	## Create the app, after checking that no file it writes already exists
	## and, for a new directory, that there is a `macos.roc` here to copy.
	run! : Str => Try({}, _)
	run! = |dir| {
		location = if (dir == ".") Env.cwd!()?.display() else dir.drop_suffix("/")
		steps = Init.plan(dir, App.app_name(App.last_part(location)))
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
				Bytes(bytes) => Path.write_bytes!(Path.utf8(target), bytes)?
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
		lines = [
			"Created an app on roc-native-macos ${Bundle.version}, an expense tracker to build on:",
			"",
			"  src/         the app: its program, store, window, widgets and a worker",
			"  logic/       its business logic, a package of pure Roc with its expect tests",
			"  fuzz/        roc-fuzz targets for that logic, which `roc macos.roc fuzz` runs",
			"  assets/      its images; assets/icon.png is its icon",
			"  tests/       recorded runs of it, which `roc macos.roc test` checks",
			"  AGENTS.md    how the project is laid out and worked on",
			"  macos.json   its name, bundle identifier and version",
			"  macos.roc    the tool, which builds, runs, tests and packages it",
			"  .gitignore   keeps build output out of version control",
			"  .github/     a workflow that tests and packages it when you push a tag such as v1.0.0",
			"",
			"Next, run the app (on a Mac; `build` and `package` work anywhere):",
			"",
			next,
			"",
			"While you edit it, `roc macos.roc dev` runs it with hot reloading.",
		]
		Str.join_with(lines, "\n")
	}
}

gitignore =
	\\# Written by `roc macos.roc`: the build directory, the app and its zip,
	\\# and roc-fuzz's corpus and reports.
	\\/.macos/
	\\/*.app/
	\\/dist/
	\\/.roc-fuzz/
	\\# Written by Roc's watcher when you run `roc src/main.roc` yourself.
	\\/.zig-cache/
	\\

## The scaffold names the release's platform, not a path.
expect {
	source = "app [main] { pf: platform \"../../platform/main.roc\" }\n\nimport pf.Engine\n"
	Init.with_platform(source, "https://x/0.0.1/h.tar.zst") == "app [main] { pf: platform \"https://x/0.0.1/h.tar.zst\" }\n\nimport pf.Engine\n"
}

## A new directory gets a copy of the tool; this directory already has it.
## Every plan writes the app in src/, its logic package, fuzz targets, icon,
## recorded cases and the `.gitignore`.
expect {
	new = Init.plan("my-app", "my-app").map(|step| step.path)
	here = Init.plan(".", "my-app").map(|step| step.path)
	new.first() == Ok("macos.roc")
		and new.drop_first(1) == here
		and ["src/main.roc", "logic/main.roc", "fuzz/main.roc", "assets/icon.png", "AGENTS.md", ".gitignore", "macos.json", ".github/workflows/release.yml"].all(|path| here.contains(path))
		and here.any(|path| path.starts_with("tests/") and path.ends_with(".script"))
}

## The app's root module names the release's platform; the fuzz targets keep
## roc-fuzz's, and the icon is written as the bytes it is.
expect {
	steps = Init.plan(".", "my-app")
	contents = |path| steps.keep_if(|step| step.path == path).first().map_ok(|step| step.contents)
	root = match contents("src/main.roc") {
		Ok(Text(text)) => text.contains("pf: platform \"${Bundle.platform_url}\"")
		_ => Bool.False
	}
	fuzz = match contents("fuzz/main.roc") {
		Ok(Text(text)) => text.contains("roc-fuzz/releases/download/")
		_ => Bool.False
	}
	icon = match contents("assets/icon.png") {
		Ok(Bytes(bytes)) => bytes.take_first(4) == [0x89, 'P', 'N', 'G']
		_ => Bool.False
	}
	root and fuzz and icon
}

## The starter metadata names the app.
expect {
	starter = Init.plan(".", "my-app").keep_if(|step| step.path == "macos.json").first().map_ok(|step| step.contents)
	starter == Ok(Text(Meta.starter("my-app"))) and Meta.starter("my-app").contains("\"id\": \"com.example.my-app\"")
}

expect [Init.place("my-app/", "main.roc"), Init.place(".", "tests/a.script")] == ["my-app/main.roc", "tests/a.script"]
