import cli.OsStr
import cli.Stderr
import cli.Stdout
import App
import Bundle
import Cases
import Init

## The `macos.roc` tool: create, build, run and test a roc-native-macos app.
## A project runs it with the small `macos.roc` app each release publishes,
## from the app's directory:
##
## ```sh
## roc macos.roc init my-app   # create an app
## roc macos.roc run           # build it and start it
## roc macos.roc build         # build my-app.app, on any system
## roc macos.roc test          # run its recorded cases
## ```
MacOS :: [].{

	## What the user asked for.
	Command : [Help, CommandHelp(Str), Init(Str), Build(App.Options), Run(App.Options), Test({ update : Bool })]

	## The commands, in the order `help` lists them.
	commands : List(Str)
	commands = ["init", "build", "run", "test"]

	## Run the tool on the arguments `roc macos.roc` passed it. Every failure
	## is explained in a sentence on standard error and ends the program with
	## a non-zero exit code (2 for a misused command line).
	run! : List(OsStr.OsStr) => Try({}, [Exit(I32)])
	run! = |raw| {
		args = raw.map(OsStr.display).drop_if(|arg| arg == "--")
		outcome = match MacOS.parse(args) {
			Ok(Help) => Stdout.line!(MacOS.usage)
			Ok(CommandHelp(command)) => Stdout.line!(MacOS.command_usage(command))
			Ok(Init(dir)) => Init.run!(dir)
			Ok(Build(chosen)) => App.build!(chosen).map_ok(|_| {})
			Ok(Run(chosen)) => App.run!(chosen)
			Ok(Test({ update })) => Cases.run!(update)
			Err(problem) => Err(problem)
		}
		match outcome {
			Ok({}) => Ok({})
			Err(problem) => {
				{ text, code } = MacOS.explain(problem)
				Stderr.line!(text) ?? {}
				Err(Exit(code))
			}
		}
	}

	## The command the arguments name.
	parse : List(Str) -> Try(Command, [UnknownCommand(Str), UnexpectedArguments({ command : Str, extra : List(Str) })])
	parse = |args|
		match args {
			[] => Ok(Help)
			["help", ..] | ["--help", ..] | ["-h", ..] => Ok(Help)
			[command, "--help"] | [command, "-h"] if MacOS.commands.contains(command) => Ok(CommandHelp(command))
			["init"] => Ok(Init("."))
			["init", dir] if !dir.starts_with("-") => Ok(Init(dir))
			["build", .. as rest] => MacOS.options("build", rest, { id: "", name: "" }).map_ok(|chosen| Build(chosen))
			["run", .. as rest] => MacOS.options("run", rest, { id: "", name: "" }).map_ok(|chosen| Run(chosen))
			["test"] => Ok(Test({ update: Bool.False }))
			["test", "--update"] => Ok(Test({ update: Bool.True }))
			[command, .. as extra] if MacOS.commands.contains(command) => Err(UnexpectedArguments({ command, extra }))
			[command, ..] => Err(UnknownCommand(command))
		}

	options : Str, List(Str), App.Options -> Try(App.Options, [UnexpectedArguments({ command : Str, extra : List(Str) })])
	options = |command, args, found|
		match args {
			[] => Ok(found)
			["--id", id, .. as rest] if !id.starts_with("-") => MacOS.options(command, rest, { ..found, id })
			["--name", name, .. as rest] if !name.starts_with("-") => MacOS.options(command, rest, { ..found, name })
			extra => Err(UnexpectedArguments({ command, extra }))
		}

	usage =
		\\macos.roc creates, builds, runs and tests a roc-native-macos app. Run it
		\\from the app's directory:
		\\
		\\  roc macos.roc init [DIR]       Create an app in DIR, or in this directory.
		\\  roc macos.roc build            Build the app, <name>.app, on any system.
		\\  roc macos.roc run              Build it and start it, its output in this terminal.
		\\  roc macos.roc test [--update]  Build it and run its recorded cases, tests/*.script.
		\\
		\\build and run take --id ID (the bundle identifier, by default com.example.<name>)
		\\and --name TEXT (the name in the menu bar, by default <name>), where <name> is
		\\the app's directory. Images and other files go in assets/ beside main.roc, and
		\\assets/icon.png is the app's icon. `roc macos.roc COMMAND --help` describes
		\\a command.
		\\
		\\They need Roc as `roc`, on macOS, Linux or Windows; no Xcode is needed. The app
		\\runs on Apple silicon Macs with macOS 11 or later, so run and test work only there.
		\\This is roc-native-macos ${Bundle.version}, tested with Roc ${Bundle.roc_version}.

	## Describe one command, without looking at the app or building anything.
	command_usage : Str -> Str
	command_usage = |command| {
		description = match command {
			"init" =>
				\\Create a counter app, with two recorded cases of it.
				\\
				\\Usage: roc macos.roc init [DIR]
				\\
				\\DIR defaults to the current directory. init writes main.roc, tests/*.script
				\\and tests/*.expected, and .gitignore, and never overwrites a file. Keep
				\\macos.roc in the directory you run init from; a new app gets a copy.
			"build" =>
				\\Build the app as <name>.app, where <name> is the app's directory.
				\\
				\\Usage: roc macos.roc build [--id ID] [--name TEXT]
				\\
				\\Run from the app's directory, containing main.roc. It works on macOS, Linux
				\\and Windows alike: the platform carries everything the link needs, and the
				\\app is built for Apple silicon (roc build --target=arm64mac). The build goes
				\\to .macos/, and then replaces <name>.app.
				\\--id sets the bundle identifier (by default com.example.<name>), which also
				\\names the app's saved settings; --name sets its name in the menu bar.
				\\The assets/ directory beside main.roc, if there is one, is copied into the
				\\app, where Ui.asset_image finds its images. assets/icon.png (square, best
				\\1024 by 1024 pixels) or assets/icon.icns becomes the app's icon.
				\\A .app copied to a Mac from elsewhere may be quarantined; clear it with
				\\xattr -dr com.apple.quarantine <name>.app before you open it.
			"run" =>
				\\Build the app and start it, with its output in this terminal.
				\\
				\\Usage: roc macos.roc run [--id ID] [--name TEXT]
				\\
				\\Run from the app's directory, containing main.roc, on an Apple silicon Mac.
				\\It builds <name>.app as build does, then runs the program inside it, so dbg
				\\output and crash reports appear here. Quit the app to return.
			"test" =>
				\\Build the app and run its recorded cases.
				\\
				\\Usage: roc macos.roc test [--update]
				\\
				\\Run from the app's directory, containing main.roc, on an Apple silicon Mac.
				\\Each tests/<case>.script holds steps (click:+;dump;quit), which drive the
				\\app's real controls without taking focus, and tests/<case>.expected what the
				\\run prints. A case passes when it exits normally having printed that, with
				\\window and point sizes allowed to differ by up to 4. --update records what
				\\each case prints now; review the change before you commit it.
			_ => return MacOS.usage
		}
		"${description}\n\nThis is roc-native-macos ${Bundle.version}, tested with Roc ${Bundle.roc_version}."
	}

	## How a command is used, for a misused command line.
	synopsis : Str -> Str
	synopsis = |command|
		match command {
			"init" => "Use it as `roc macos.roc init [DIR]`."
			"build" => "Use it as `roc macos.roc build [--id ID] [--name TEXT]`."
			"run" => "Use it as `roc macos.roc run [--id ID] [--name TEXT]`."
			"test" => "Use it as `roc macos.roc test [--update]`."
			_ => "`roc macos.roc help` describes it."
		}

	## The sentence a failure is explained with, and the exit code. This is
	## the one place the tool's failures are put into words.
	explain : _ -> { text : Str, code : I32 }
	explain = |problem|
		match problem {
			UnknownCommand(command) => { code: 2, text: "There is no command \"${command}\". The commands are init, build, run and test; `roc macos.roc help` describes them." }
			UnexpectedArguments({ command, extra }) => { code: 2, text: "${command} does not take ${Str.join_with(extra.map(|a| "\"${a}\""), " ")}. ${MacOS.synopsis(command)}" }
			BadId(id) => { code: 2, text: "\"${id}\" is not a bundle identifier: it needs two or more parts separated by dots, made of letters, digits and hyphens, such as com.example.counter." }
			RocMissing => { code: 1, text: "The Roc compiler is not on your PATH as `roc`, so the app cannot be built. Install Roc ${Bundle.roc_version} (or a later nightly) and put it on your PATH as `roc`." }
			NoMainRoc => { code: 1, text: "There is no main.roc here, so there is no app to build. Run this from your app's directory, or create an app with `roc macos.roc init my-app`." }
			BuildFailed => { code: 1, text: "The build failed: the compiler's report is above." }
			NotAppleSilicon({ command, system, bundle }) =>
				if command == "run" {
					{ code: 1, text: "Built ${bundle}, but this is ${system}, and the app runs only on an Apple silicon Mac: copy ${bundle} to one and open it there." }
				} else {
					{ code: 1, text: "The recorded cases run the app, which runs only on an Apple silicon Mac, and this is ${system}, so test cannot run them here. `roc macos.roc build` builds the app on any system." }
				}
			NoCases => { code: 1, text: "There are no recorded cases to run: tests/ holds no .script files. `roc macos.roc init` writes tests/increment.script as an example, and `roc macos.roc test --help` describes them." }
			CasesFailed({ failed, total }) => { code: 1, text: "${failed.len().to_str()} of ${total.to_str()} recorded cases failed: ${Str.join_with(failed, ", ")}. If the app changed on purpose, record what it prints now with `roc macos.roc test --update`." }
			AppFailed(how) => { code: 1, text: "The app ${how}: its output is above." }
			AssetsNotADirectory => { code: 1, text: "assets is not a directory: the app's images and other files go in a directory named assets beside main.roc." }
			TwoIcons => { code: 1, text: "assets/ holds both icon.png and icon.icns, and an app has one icon: remove one of them." }
			BadIcon(NotPng) => { code: 1, text: "assets/icon.png is not a PNG file, so it cannot be the app's icon: save it as a PNG, 1024 by 1024 pixels." }
			BadIcon(NotSquare({ width, height })) => { code: 1, text: "assets/icon.png is ${width.to_str()} by ${height.to_str()} pixels, and an app's icon is square: make it 1024 by 1024 pixels." }
			BadIcon(UnsupportedSize(size)) => { code: 1, text: "assets/icon.png is ${size.to_str()} pixels square, and an app's icon is 16, 32, 64, 128, 256, 512 or 1024: make it 1024 by 1024 pixels." }
			BadIcon(NotIcns) => { code: 1, text: "assets/icon.icns is not an .icns file, so it cannot be the app's icon: use a 1024 by 1024 pixel assets/icon.png instead." }
			InitWouldOverwrite(path) => { code: 1, text: "${path} already exists, so init changed nothing: it only creates files that are not there yet. Choose a new directory, for example `roc macos.roc init my-app`." }
			NoToolToCopy(dir) => { code: 1, text: "init copies macos.roc into the new app, but there is no macos.roc in this directory, so ${dir} was not created. Run init from the directory that holds macos.roc." }
			other => { code: 1, text: "macos.roc stopped on an error it did not expect: ${Str.inspect(other)}" }
		}
}

## Each command line names its command, with the defaults filled in.
expect {
	actual = [[], ["help"], ["init"], ["init", "my-app"], ["build"], ["run", "--id", "org.me.app", "--name", "My App"], ["test"], ["test", "--update"]].map(MacOS.parse)
	expected = [Ok(Help), Ok(Help), Ok(Init(".")), Ok(Init("my-app")), Ok(Build({ id: "", name: "" })), Ok(Run({ id: "org.me.app", name: "My App" })), Ok(Test({ update: Bool.False })), Ok(Test({ update: Bool.True }))]
	actual == expected
}

## A misused command line is refused with what was wrong.
expect {
	actual = [["buld"], ["build", "--watch"], ["run", "--id"], ["init", "a", "b"], ["test", "--record"]].map(MacOS.parse)
	expected = [Err(UnknownCommand("buld")), Err(UnexpectedArguments({ command: "build", extra: ["--watch"] })), Err(UnexpectedArguments({ command: "run", extra: ["--id"] })), Err(UnexpectedArguments({ command: "init", extra: ["a", "b"] })), Err(UnexpectedArguments({ command: "test", extra: ["--record"] }))]
	actual == expected
}

## Help belongs to an exact known command, and needs no app.
expect MacOS.commands.all(|command| ["--help", "-h"].all(|flag| MacOS.parse([command, flag]) == Ok(CommandHelp(command))))

## A help flag never turns an unknown command or extra arguments into help.
expect {
	actual = [["bogus", "--help"], ["init", "my-app", "--help"], ["build", "--watch", "--help"], ["test", "--update", "--help"]].map(MacOS.parse)
	expected = [Err(UnknownCommand("bogus")), Err(UnexpectedArguments({ command: "init", extra: ["my-app", "--help"] })), Err(UnexpectedArguments({ command: "build", extra: ["--watch", "--help"] })), Err(UnexpectedArguments({ command: "test", extra: ["--update", "--help"] }))]
	actual == expected
}

## Each help page names its usage and the release.
expect MacOS.commands.all(|command| MacOS.command_usage(command).contains("Usage: roc macos.roc ${command}") and MacOS.command_usage(command).contains("roc-native-macos ${Bundle.version}"))

## Every failure is a sentence, and a misused command line exits with 2.
expect {
	explained = [UnknownCommand("x"), UnexpectedArguments({ command: "test", extra: ["-v"] }), BadId("x"), NoMainRoc, NotAppleSilicon({ command: "run", system: "Linux", bundle: "counter.app" }), CasesFailed({ failed: ["reset"], total: 2 })].map(MacOS.explain)
	run_elsewhere = explained.drop_first(4).first().map_ok(|e| e.text)
	explained.map(|e| e.code) == [2, 2, 2, 1, 1, 1] and run_elsewhere == Ok("Built counter.app, but this is Linux, and the app runs only on an Apple silicon Mac: copy counter.app to one and open it there.")
}

## An icon that cannot be used says why, in its own words.
expect {
	explained = [BadIcon(NotSquare({ width: 1024.U32, height: 512.U32 })), BadIcon(UnsupportedSize(100.U32)), TwoIcons].map(|problem| MacOS.explain(problem).text)
	explained.all(|text| text.starts_with("assets/")) and explained.first() == Ok("assets/icon.png is 1024 by 512 pixels, and an app's icon is square: make it 1024 by 1024 pixels.")
}
