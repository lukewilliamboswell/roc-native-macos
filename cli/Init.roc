import cli.Env
import cli.Path
import cli.Stdout
import App
import Bundle
import Meta
import Workflow

## `init [--simple] [DIR]`: create an app in `DIR` (by default, this
## directory). `init` writes the starter example, a music player with a
## logic package, fuzz targets, an icon and specs; `init --simple` writes the
## counter example, one `src/main.roc` and its specs. It writes only files
## that are not there yet. The project gets a launcher it can run locally.
Init :: [].{

	## What `init` writes: a file's path in the app, and its text, its bytes
	## or the file it is copied from.
	Step : { path : Str, contents : [Text(Str), Bytes(List(U8)), CopyOf(Str)] }

	## A downloaded launcher can be copied. A URL launch provides its source.
	Launcher : [Local, Bundled(Str)]

	## Which app `init` writes: the starter, or the counter with `--simple`.
	Template : [Starter, Simple]

	## The files of a template, as this copy of the tool carries them.
	files : Template -> List(Bundle.File)
	files = |template|
		match template {
			Starter => Bundle.starter
			Simple => Bundle.simple
		}

	## Every file `init` writes into `dir`, for the app whose name is `name`.
	## The app's root module names the release's platform.
	plan : { dir : Str, name : Str, template : Template, launcher : Launcher } -> List(Step)
	plan = |{ dir, name, template, launcher }| {
		tool = match launcher {
			Bundled(source) => [{ path: "macos.roc", contents: Text(source) }]
			Local if dir == "." => []
			Local => [{ path: "macos.roc", contents: CopyOf("macos.roc") }]
		}
		scaffold = Init.files(template).map(
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
	## and that any local launcher it plans to copy is present.
	run! : { dir : Str, template : Template, launcher : Launcher } => Try({}, _)
	run! = |{ dir, template, launcher }| {
		location = if (dir == ".") Env.cwd!()?.display() else dir.drop_suffix("/")
		steps = Init.plan({ dir, name: App.app_name(App.last_part(location)), template, launcher })
		for step in steps {
			target = Init.place(dir, step.path)
			if Path.exists!(Path.utf8(target))? {
				return Err(InitWouldOverwrite(target))
			}
		}
		if launcher == Local and dir != "." and !(Path.exists!(Path.utf8("macos.roc"))?) {
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
		Stdout.line!(Init.summary(dir, template))?
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

	## What `init` prints: which app it made, its files, and what to do next.
	summary : Str, Template -> Str
	summary = |dir, template| {
		next = if (dir == ".") "  roc macos.roc dev" else "  cd ${dir}\n  roc macos.roc dev"
		(made, listing, other) = match template {
			Starter => (
				"a music player to build on",
				[
					"  src/         the app: its program, store, window, panels, widgets and a worker",
					"  logic/       its logic (lyrics, the queue, presets), pure Roc with its expect tests",
					"  assets/      its images; assets/icon.png is its icon",
					"  tests/       specs of what it does (tests/specs/, which `roc macos.roc test` checks),",
					"               the files they use (tests/fixtures/) and roc-fuzz targets for the",
					"               logic (tests/fuzz/, which `roc macos.roc fuzz` runs)",
				],
				"For a smaller start, `roc macos.roc init --simple DIR` writes a counter in one file.",
			)
			Simple => (
				"a counter to build on",
				[
					"  src/         the app, src/main.roc: one piece of state and three buttons",
					"  tests/       specs of what it does (tests/specs/, which `roc macos.roc test` checks)",
				],
				"Images go in assets/, where assets/icon.png is the app's icon. For a larger start,\n`roc macos.roc init DIR` writes a music player with a logic package and fuzz targets.",
			)
		}
		lines = ["Created an app on roc-native-macos ${Bundle.version}, ${made}:", ""]
			.concat(listing)
			.concat([
				"  macos.json   its name, bundle identifier and version",
				"  macos.roc    the tool, which builds, runs, tests and packages it",
				"  .gitignore   keeps build output out of version control",
				"  .github/     a workflow that tests and packages it when you push a tag such as v1.0.0",
				"",
				"On a Mac, start the app in development mode:",
				"",
				next,
				"",
				"Save your changes, then press Command-R in the app to reload them.",
				"`roc macos.roc test` checks the specs.",
				"",
				other,
			])
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
## The starter writes the app in src/, its logic package, fuzz targets,
## icon, specs and the `.gitignore`.
expect {
	new = Init.plan({ dir: "my-app", name: "my-app", template: Starter, launcher: Local }).map(|step| step.path)
	here = Init.plan({ dir: ".", name: "my-app", template: Starter, launcher: Local }).map(|step| step.path)
	new.first() == Ok("macos.roc")
		and new.drop_first(1) == here
		and ["src/main.roc", "logic/main.roc", "tests/fuzz/main.roc", "assets/icon.png", ".gitignore", "macos.json", ".github/workflows/release.yml"].all(|path| here.contains(path))
		and here.any(|path| path.starts_with("tests/specs/") and path.ends_with(".scm"))
}

## `--simple` writes the counter: its src/main.roc and specs, with the same
## metadata, `.gitignore`, workflow and copy of the tool, and none of the
## starter's logic package, fuzz targets or assets.
expect {
	new = Init.plan({ dir: "my-app", name: "my-app", template: Simple, launcher: Local }).map(|step| step.path)
	here = Init.plan({ dir: ".", name: "my-app", template: Simple, launcher: Local }).map(|step| step.path)
	new.first() == Ok("macos.roc")
		and new.drop_first(1) == here
		and here.keep_if(|path| path.starts_with("src/")) == ["src/main.roc"]
		and ["tests/specs/increment.scm", "tests/specs/reset.scm", ".gitignore", "macos.json", ".github/workflows/release.yml"].all(|path| here.contains(path))
		and !here.any(|path| path.starts_with("logic/") or path.starts_with("tests/fuzz/") or path.starts_with("assets/"))
}

## Each template's root module names the release's platform.
expect [Starter, Simple].all(
	|template|
		match Init.plan({ dir: ".", name: "my-app", template: template, launcher: Local }).keep_if(|step| step.path == "src/main.roc") {
			[{ contents: Text(text), .. }] => text.contains("pf: platform \"${Bundle.platform_url}\"") and !text.contains("../../../platform/")
			_ => Bool.False
		},
)

## The summary names the template it wrote and points to the other.
expect {
	starter = Init.summary("my-app", Starter)
	simple = Init.summary(".", Simple)
	starter.contains("a music player to build on")
		and starter.contains("  cd my-app\n  roc macos.roc dev")
		and starter.contains("`roc macos.roc init --simple DIR` writes a counter")
		and simple.contains("a counter to build on")
		and simple.contains("  roc macos.roc dev")
		and !simple.contains("cd ")
		and !simple.contains("logic/")
		and simple.contains("`roc macos.roc init DIR` writes a music player")
}

## The starter's root module names the release's platform; the fuzz
## targets keep roc-fuzz's, and the icon is written as the bytes it is.
expect {
	steps = Init.plan({ dir: ".", name: "my-app", template: Starter, launcher: Local })
	contents = |path| steps.keep_if(|step| step.path == path).first().map_ok(|step| step.contents)
	root = match contents("src/main.roc") {
		Ok(Text(text)) => text.contains("pf: platform \"${Bundle.platform_url}\"")
		_ => Bool.False
	}
	fuzz = match contents("tests/fuzz/main.roc") {
		Ok(Text(text)) => text.contains("roc-fuzz/releases/download/")
		_ => Bool.False
	}
	icon = match contents("assets/icon.png") {
		Ok(Bytes(bytes)) => bytes.take_first(4) == [0x89, 'P', 'N', 'G']
		_ => Bool.False
	}
	root and fuzz and icon
}

## Either template's metadata names the app.
expect {
	metadata = |template| Init.plan({ dir: ".", name: "my-app", template: template, launcher: Local }).keep_if(|step| step.path == "macos.json").first().map_ok(|step| step.contents)
	[metadata(Starter), metadata(Simple)] == [Ok(Text(Meta.starter("my-app"))), Ok(Text(Meta.starter("my-app")))] and Meta.starter("my-app").contains("\"id\": \"com.example.my-app\"")
}

expect [Init.place("my-app/", "main.roc"), Init.place(".", "tests/specs/a.scm")] == ["my-app/main.roc", "tests/specs/a.scm"]

## URL launch writes the bundled launcher for either init location.
expect [".", "my-app"].all(
	|dir| Init.plan({ dir, name: "my-app", template: Simple, launcher: Bundled("launcher source") }).first() == Ok({ path: "macos.roc", contents: Text("launcher source") }),
)
