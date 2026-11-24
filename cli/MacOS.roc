import cli.OsStr
import cli.Stderr
import cli.Stdout
import App
import Bundle
import Cases
import Fuzz
import Init
import Meta
import Ci
import Package

## The `macos.roc` tool: create, build, run, test and package a
## roc-native-macos app. A project runs it with the small `macos.roc` app
## each release publishes, from the app's directory:
##
## ```sh
## roc macos.roc init my-app   # create an app
## roc macos.roc run           # build it and start it
## roc macos.roc dev           # start it with hot reloading
## roc macos.roc build         # build my-app.app, on any system
## roc macos.roc test          # run its expect tests and specs
## roc macos.roc fuzz          # run its roc-fuzz targets, tests/fuzz/main.roc
## roc macos.roc package       # dist/my-app-<version>.zip, to share
## ```
##
## The app's root module is `src/main.roc`, where `init` puts it
## (`App.entry!`). Everything else is at the top of the app's directory.
MacOS :: [].{

	## What the user asked for.
	Command : [Help, CommandHelp(Str), Init(Str), Build(Built), Run(Built), Dev, Test({ update : Bool, check : Bool, metrics : Bool }), Fuzz(Fuzz.Options), Package(Package.Options), CiPackage(Built), CiRelease]

	## What `build`, `run` and `ci package` were asked for: the metadata
	## flags, and what to build (universal, or `--target`'s one Mac).
	Built : { fields : Meta.Fields, how : App.Build }

	## The commands, in the order `help` lists them.
	commands : List(Str)
	commands = ["init", "build", "run", "dev", "test", "fuzz", "package", "ci"]

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
			Ok(Dev) => App.dev!()
			Ok(Test(chosen)) => Cases.run!(chosen)
			Ok(Fuzz(chosen)) => Fuzz.run!(chosen)
			Ok(Package(chosen)) => Package.run!(chosen, Package.environment!()).map_ok(|_| {})
			Ok(CiPackage(chosen)) => Ci.package!(chosen)
			Ok(CiRelease) => Ci.release!()
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
	parse : List(Str) -> Try(Command, [UnknownCommand(Str), UnexpectedArguments({ command : Str, extra : List(Str) }), UnknownTarget(Str)])
	parse = |args|
		match args {
			[] => Ok(Help)
			["help", ..] | ["--help", ..] | ["-h", ..] => Ok(Help)
			[command, "--help"] | [command, "-h"] if MacOS.commands.contains(command) => Ok(CommandHelp(command))
			["init"] => Ok(Init("."))
			["init", dir] if !dir.starts_with("-") => Ok(Init(dir))
			["build", .. as rest] => MacOS.options("build", rest, nothing).map_ok(|chosen| Build({ fields: chosen.fields, how: chosen.how }))
			["run", .. as rest] => MacOS.options("run", rest, nothing).map_ok(|chosen| Run({ fields: chosen.fields, how: chosen.how }))
			["package", .. as rest] => MacOS.options("package", rest, nothing).map_ok(|chosen| Package(chosen))
			["ci", "package", .. as rest] => MacOS.options("ci package", rest, nothing).map_ok(|chosen| CiPackage({ fields: chosen.fields, how: chosen.how }))
			["ci", "release"] => Ok(CiRelease)
			["dev"] => Ok(Dev)
			["test"] => Ok(Test({ update: Bool.False, check: Bool.False, metrics: Bool.False }))
			["test", "--update"] => Ok(Test({ update: Bool.True, check: Bool.False, metrics: Bool.False }))
			["test", "--check"] => Ok(Test({ update: Bool.False, check: Bool.True, metrics: Bool.False }))
			["test", "--metrics"] => Ok(Test({ update: Bool.False, check: Bool.False, metrics: Bool.True }))
			["fuzz", .. as rest] => Fuzz.options(rest, Fuzz.defaults).map_ok(|chosen| Fuzz(chosen))
			[command, .. as extra] if MacOS.commands.contains(command) => Err(UnexpectedArguments({ command, extra }))
			[command, ..] => Err(UnknownCommand(command))
		}

	## The metadata flags and `--target`, which `build`, `run` and `package`
	## take, and `package`'s `--sign` and `--notarize`.
	options : Str, List(Str), Package.Options -> Try(Package.Options, [UnexpectedArguments({ command : Str, extra : List(Str) }), UnknownTarget(Str)])
	options = |command, args, found| {
		packaging = command == "package"
		match args {
			[] => Ok(found)
			["--sign", .. as rest] if packaging => MacOS.options(command, rest, { ..found, sign: Bool.True })
			["--notarize", .. as rest] if packaging => MacOS.options(command, rest, { ..found, notarize: Bool.True })
			["--target", value, .. as rest] => MacOS.options(command, rest, { ..found, how: App.target_of(value)? })
			[flag, value, .. as rest] if !value.starts_with("--") =>
				match Meta.flag_field(flag) {
					Ok(field) =>
						match Meta.set(found.fields, field, value) {
							Ok(fields) => MacOS.options(command, rest, { ..found, fields })
							Err(_) => Err(UnexpectedArguments({ command, extra: args }))
						}
					Err(_) => Err(UnexpectedArguments({ command, extra: args }))
				}
			extra => Err(UnexpectedArguments({ command, extra }))
		}
	}

	usage =
		\\macos.roc creates, builds, runs, tests and packages a roc-native-macos app.
		\\Run it from the app's directory:
		\\
		\\  roc macos.roc init [DIR]       Create an app in DIR, or in this directory.
		\\  roc macos.roc build            Build the app, a universal <name>.app, on any system.
		\\  roc macos.roc run              Build it and start it, its output in this terminal.
		\\  roc macos.roc dev              Start it with roc src/main.roc, which reloads it as you save.
		\\  roc macos.roc test [--update]  Run its expect tests, then its specs, tests/specs/*.scm.
		\\  roc macos.roc fuzz [--check]   Build its roc-fuzz targets, tests/fuzz/main.roc, and run them.
		\\  roc macos.roc package          Build it, sign it and zip it, as dist/<name>-<version>.zip.
		\\  roc macos.roc ci package       Package it in CI, signing it as the secrets allow.
		\\  roc macos.roc ci release       Attach dist/*.zip to the pushed tag's GitHub release.
		\\
		\\<name> is the app's directory, which holds src/main.roc. The app's metadata
		\\is in macos.json there: its name, bundle identifier (by default
		\\com.example.<name>), version, build number, copyright, category and oldest
		\\macOS. build, run and package take each as a flag too,
		\\such as --version 1.2.0, which overrides the file, and --target arm64mac or
		\\--target x64mac, which builds for that Mac alone. Images and other files go
		\\in assets/, and assets/icon.png is the app's icon. `roc macos.roc COMMAND
		\\--help` describes a command.
		\\
		\\They need Roc as `roc`, on macOS, Linux or Windows; no Xcode is needed. The app
		\\runs on Apple silicon and Intel Macs with macOS 15 or later, so run, dev and the
		\\specs work only there; fuzz runs on Apple silicon Macs and Linux x64.
		\\This is roc-native-macos ${Bundle.version}, tested with Roc ${Bundle.roc_version}.
		\\Documentation: https://lukewilliamboswell.github.io/roc-native-macos/apps.html

	## Describe one command, without looking at the app or building anything.
	command_usage : Str -> Str
	command_usage = |command| {
		description = match command {
			"init" =>
				\\Create an app to build on: a music player with its tests.
				\\
				\\Usage: roc macos.roc init [DIR]
				\\
				\\DIR defaults to the current directory. init writes the app in src/ (its
				\\store, window, widgets and a worker), its business logic as a package of
				\\pure Roc in logic/, its icon in assets/, its tests in tests/ (specs of it
				\\in tests/specs/, the files they use in tests/fixtures/, and roc-fuzz
				\\targets for its logic in tests/fuzz/), macos.json (the app's name,
				\\identifier and version), .gitignore, and .github/workflows/release.yml,
				\\which packages the app on GitHub when you push a tag such as v1.0.0. It
				\\never overwrites a file. Keep macos.roc in the directory you run init
				\\from; a new app gets a copy.
			"build" =>
				\\Build the app as <name>.app, where <name> is the app's directory.
				\\
				\\Usage: roc macos.roc build [--target arm64mac|x64mac] [METADATA FLAGS]
				\\
				\\Run from the app's directory, containing src/main.roc. It works
				\\on macOS, Linux and Windows alike: the platform carries everything the link
				\\needs. The app is built for Apple silicon and for Intel Macs (roc build
				\\--target=arm64mac, then --target=x64mac), and the two programs are joined
				\\into one universal program, which each Mac runs natively. --target arm64mac
				\\(Apple silicon) or --target x64mac (Intel) builds only that one, a smaller
				\\app for that Mac alone. The build goes to .macos/, and then replaces
				\\<name>.app.
				\\The app directory's assets/, if there is one, is copied into the
				\\app, where Ui.asset_image finds its images. assets/icon.png (square, best
				\\1024 by 1024 pixels) or assets/icon.icns becomes the app's icon.
				\\A .app copied to a Mac from elsewhere may be quarantined; clear it with
				\\xattr -dr com.apple.quarantine <name>.app before you open it.
				\\
				\\${metadata_help}
			"run" =>
				\\Build the app and start it, with its output in this terminal.
				\\
				\\Usage: roc macos.roc run [--target arm64mac|x64mac] [METADATA FLAGS]
				\\
				\\Run from the app's directory, on a Mac. It builds <name>.app
				\\as build does, then runs the program inside it, so dbg
				\\output and crash reports appear here. Quit the app to return. It takes the
				\\flags build takes; an Apple silicon Mac runs an x64mac build under Rosetta.
			"dev" =>
				\\Start the app with hot reloading, with its output in this terminal.
				\\
				\\Usage: roc macos.roc dev
				\\
				\\Run from the app's directory, on a Mac. It runs
				\\`roc src/main.roc`, from .macos/:
				\\Roc builds the app with its development backend and starts it, with no
				\\.app, and watches the modules and packages it imports. When you save a
				\\change that compiles, Roc rebuilds the app and
				\\swaps the new code in; press Command-R (Reload in the app menu) to remount
				\\the window with it, which starts the state again. A change that does not
				\\compile prints its errors and leaves the app running. Quit the app to return.
				\\
				\\The app finds its images in assets/ here. macos.json and the icon belong to
				\\the .app, which dev does not make, so they do not apply here and dev takes
				\\no metadata flags; run builds and starts the app as people will see it.
				\\Variables such as ROC_APPEARANCE and ROC_TRACE reach the app as under run.
			"package" =>
				\\Build the app, sign it, and zip it as dist/<name>-<version>.zip, to share.
				\\
				\\Usage: roc macos.roc package [--sign] [--notarize] [--target arm64mac|x64mac]
				\\                            [METADATA FLAGS]
				\\
				\\Run from the app's directory, on any system. It builds <name>.app as build
				\\does (universal, or with --target for one Mac), seals it with an ad hoc
				\\signature (with codesign on a Mac, or rcodesign anywhere, when either is on
				\\PATH), and zips it with the program's execute
				\\bit set. Whoever downloads an ad hoc zip approves the app once, in System
				\\Settings > Privacy & Security, before it opens.
				\\
				\\--sign signs it with your Developer ID Application certificate, with the
				\\hardened runtime: on a Mac from the keychain, naming the identity in
				\\MACOS_SIGN_IDENTITY; anywhere with rcodesign, from the .p12 file at
				\\MACOS_SIGN_P12, whose password is MACOS_SIGN_P12_PASSWORD.
				\\--notarize also signs it, sends it to Apple's notary service, staples the
				\\ticket to the app and zips it again; then it opens with no warning. It uses
				\\an App Store Connect API key: MACOS_NOTARY_ISSUER (the issuer ID),
				\\MACOS_NOTARY_KEY_ID (the key ID) and MACOS_NOTARY_KEY (the .p8 file's path,
				\\or its contents). MACOS_SIGN_TOOL=codesign or rcodesign picks the tool.
				\\SOURCE_DATE_EPOCH, if set, is the time the zip's entries carry.
				\\
				\\The zip is named for the app's name and version, and with --target for its
				\\target too, as dist/<name>-<version>-x64mac.zip. A version may have a
				\\pre-release suffix, as 1.0.0-beta.1 does: the zip's name keeps it, and the
				\\app's Info.plist has 1.0.0.
				\\
				\\${metadata_help}
			"ci" =>
				\\Package the app in a CI run, and attach it to a GitHub release.
				\\
				\\Usage: roc macos.roc ci package [--target arm64mac|x64mac] [METADATA FLAGS]
				\\       roc macos.roc ci release
				\\
				\\The workflow init writes, .github/workflows/release.yml, runs these, so that
				\\each of its steps is one command.
				\\
				\\ci package runs package for the run. The version is --version, else
				\\RELEASE_VERSION, else the pushed tag without its v (v1.0.0-beta.1 is
				\\1.0.0-beta.1). With MACOS_SIGN_P12_BASE64 (a .p12 certificate, base64) or
				\\MACOS_SIGN_P12 or MACOS_SIGN_IDENTITY it signs with that Developer ID, and
				\\with all three MACOS_NOTARY_* it also notarizes; it says so when they are
				\\not set, and refuses part of a notary key. It decodes the certificate to a
				\\file only you can read, removed afterwards. When signing needs rcodesign
				\\and none is on PATH, it installs rcodesign ${Ci.rcodesign_version}, checked
				\\against its SHA-256, in RUNNER_TEMP. SOURCE_DATE_EPOCH, when unset, is the
				\\last commit's time.
				\\
				\\ci release attaches dist/*.zip to the release of the pushed tag
				\\(GITHUB_REF_NAME, in GITHUB_REPOSITORY) with gh, which reads GH_TOKEN. It
				\\creates the release when there is none, as a pre-release for a tag with a
				\\suffix, and replaces zips of the same name.
			"test" =>
				\\Run the app's expect tests, then build the app and run its specs.
				\\
				\\Usage: roc macos.roc test [--update | --check | --metrics]
				\\
				\\Run from the app's directory. It runs `roc test src/main.roc`, which runs
				\\the expects of every module of the app and of the packages it names by
				\\path, such as logic/; that works on any system. Then, on a Mac, it builds
				\\the app for that Mac and runs its specs.
				\\Each tests/specs/<name>.scm holds one spec, (test "name" (steps ...)): steps such as
				\\(click (button "+")), which drive the app's real controls without taking
				\\focus, and expectations such as (expect-text (text "1") "1") or a whole
				\\(expect-dump (window ...)), the window's view tree, compared node by node.
				\\A failure names the spec's file, line and column. --update rewrites each
				\\expect-dump with what the app shows now, and lowers each allocation bound, such as
				\\(expect-allocations-at-most N), to what the app allocated when that was less;
				\\it never raises one, and changes nothing else: review the change before you
				\\commit it. --metrics runs every spec and prints what it measured
				\\(allocations, bytes, the engine's work) without judging it, to set first
				\\bounds from. --check only parses the specs, on any system. A spec written
				\\(demo "name" ...) is a recording with real effects and waits: --check
				\\parses it, and test never runs it.
			"fuzz" =>
				\\Build the app's fuzz targets and run them.
				\\
				\\Usage: roc macos.roc fuzz [--check] [--time SECONDS] [TARGET...]
				\\
				\\Run from the app's directory, on an Apple silicon Mac or on Linux x64.
				\\tests/fuzz/main.roc is an app on roc-fuzz's platform that declares properties of
				\\the app's logic package; it builds it with `roc build --fuzz` into
				\\.macos/fuzz, then runs each target (or the TARGETs named) in turn: it
				\\explores inputs for SECONDS each (10 by default), keeping those worth
				\\revisiting in .roc-fuzz/corpus/<target>. --check runs only the examples
				\\each target declares, quickly, as CI does. A failure prints its report and
				\\leaves the failing input under .roc-fuzz/; `.macos/fuzz --target=NAME
				\\replay INPUT` runs it again, and `.macos/fuzz --target=NAME --help` lists
				\\what else the program does. roc-fuzz's manual is at
				\\https://lukewilliamboswell.github.io/roc-fuzz/.
			_ => return MacOS.usage
		}
		"${description}\n\nThis is roc-native-macos ${Bundle.version}, tested with Roc ${Bundle.roc_version}."
	}

	## How a command is used, for a misused command line.
	synopsis : Str -> Str
	synopsis = |command|
		match command {
			"init" => "Use it as `roc macos.roc init [DIR]`."
			"dev" => "Use it as `roc macos.roc dev`, with no arguments; `roc macos.roc dev --help` describes it."
			"build" | "run" => "Use it as `roc macos.roc ${command} [--target arm64mac|x64mac] [METADATA FLAGS]`; `roc macos.roc ${command} --help` lists the flags."
			"package" => "Use it as `roc macos.roc package [--sign] [--notarize] [--target arm64mac|x64mac] [METADATA FLAGS]`; `roc macos.roc package --help` lists the flags."
			"ci" | "ci package" => "Use it as `roc macos.roc ci package [--target arm64mac|x64mac] [METADATA FLAGS]` or `roc macos.roc ci release`; ci decides how to sign from the secrets that are set. `roc macos.roc ci --help` describes them."
			"test" => "Use it as `roc macos.roc test [--update | --check | --metrics]`."
			"fuzz" => "Use it as `roc macos.roc fuzz [--check] [--time SECONDS] [TARGET...]`, where SECONDS is a whole number above 0; `roc macos.roc fuzz --help` describes it."
			_ => "`roc macos.roc help` describes it."
		}

	## Where a field's value came from, for a sentence.
	source : Str, [File, Flag] -> Str
	source = |field, from|
		match from {
			Flag => "--${field.replace_each("_", "-")}"
			File => "${Meta.file}'s ${field}"
		}

	## Why a field's value is refused.
	bad_field : Str, Str, [File, Flag] -> Str
	bad_field = |field, value, from| {
		given = "${MacOS.source(field, from)}, \"${value}\","
		match field {
			"id" => "${given} is not a bundle identifier: it needs two or more parts separated by dots, made of letters, digits and hyphens, such as com.example.counter."
			"version" => "${given} is not a version: write one to three whole numbers separated by dots, such as 1.2.0, with no v, and optionally a pre-release suffix, such as 1.2.0-beta.1."
			"build" => "${given} is not a build number: write one to three whole numbers separated by dots, such as 7 or 1.2.0, with no suffix."
			"minimum_macos" => "${given} is not a macOS version this platform runs on: write ${Meta.oldest_macos} or later, such as 26.0."
			"category" => "${given} is not an App Store category: write public.app-category. and the category's name, such as public.app-category.utilities."
			_ => "${given} holds a control character, such as a tab or a line break, which an app's ${field} cannot."
		}
	}

	## The sentence a failure is explained with, and the exit code. This is
	## the one place the tool's failures are put into words.
	explain : _ -> { text : Str, code : I32 }
	explain = |problem|
		match problem {
			UnknownCommand(command) => { code: 2, text: "There is no command \"${command}\". The commands are init, build, run, dev, test, fuzz, package and ci; `roc macos.roc help` describes them." }
			UnexpectedArguments({ command, extra }) => { code: 2, text: "${command} does not take ${Str.join_with(extra.map(|a| "\"${a}\""), " ")}. ${MacOS.synopsis(command)}" }
			BadField({ field, value, from }) => { code: if (from == Flag) 2 else 1, text: MacOS.bad_field(field, value, from) }
			MetaMalformed({ line, expected }) => { code: 1, text: "${Meta.file} is not the JSON object the tool reads: on line ${line.to_str()} it expected ${expected}. It holds one object of text fields, such as { \"version\": \"1.2.0\" }." }
			MetaNotText({ field, line }) => { code: 1, text: "${Meta.file}'s ${field}, on line ${line.to_str()}, is not text: write it in double quotes, as \"${field}\": \"...\"." }
			MetaUnknownField(field) => { code: 1, text: "${Meta.file} has a field \"${field}\", which the tool does not know: the fields are ${Str.join_with(Meta.names, ", ")}." }
			MetaDuplicate(field) => { code: 1, text: "${Meta.file} gives ${field} twice: keep one of them." }
			BadSignTool(tool) => { code: 1, text: "MACOS_SIGN_TOOL is \"${tool}\", and the signing tools are codesign and rcodesign: set it to one of them, or unset it to use the one here." }
			SignToolMissing(tool) => { code: 1, text: "MACOS_SIGN_TOOL names ${tool}, which is not ${if (tool == "codesign") "here: codesign is on Macs only" else "on PATH"}: install it, or unset MACOS_SIGN_TOOL." }
			NoDeveloperId(why) => { code: 1, text: "Signing with a Developer ID needs your certificate: ${why}. `roc macos.roc package --help` describes it." }
			NoP12File(path) => { code: 1, text: "MACOS_SIGN_P12 names ${path}, and there is no such file: it is the path of your Developer ID Application certificate, exported as a .p12 file." }
			NoP12Password => { code: 1, text: "MACOS_SIGN_P12 names a certificate, but MACOS_SIGN_P12_PASSWORD is not set: set it to the password the .p12 file was exported with." }
			NoNotaryKey(missing) => { code: 1, text: "Notarizing needs an App Store Connect API key, and ${Str.join_with(missing, ", ")} ${if (missing.len() == 1) "is" else "are"} not set. `roc macos.roc package --help` describes them." }
			NoNotaryKeyFile(path) => { code: 1, text: "MACOS_NOTARY_KEY names ${path}, and there is no such file: set it to your API key's .p8 file, or to the file's contents." }
			NotaryToolMissing => { code: 1, text: "Notarizing from the keychain uses xcrun notarytool, which is not on PATH: install Xcode's command line tools (xcode-select --install), or sign with MACOS_SIGN_P12 and rcodesign instead." }
			BadSourceDateEpoch(text) => { code: 1, text: "SOURCE_DATE_EPOCH is \"${text}\", which is not a number of seconds since 1970: set it to one, such as the last commit's time (git log -1 --format=%ct), or unset it." }
			StepFailed(shown) => { code: 1, text: "Packaging stopped: `${shown}` failed, with its report above." }
			CannotZip(why) => { code: 1, text: "package could not zip the app: roc-zip refused it with ${why}." }
			NoReleaseVersion(ref) => { code: 1, text: "ci package needs a version, and this run has none: it is for ${ref}, not a tag such as v1.0.0. Push a tag, or give one with --version or RELEASE_VERSION." }
			PartialNotaryKey(missing) => { code: 1, text: "Some of the notary key's secrets are set, but not ${Str.join_with(missing, " or ")}: set all three to notarize, or none to sign without notarizing." }
			BadP12Base64 => { code: 1, text: "MACOS_SIGN_P12_BASE64 is not base64: set it to the .p12 file's base64, as `base64 -i developer-id.p12` prints it." }
			NoRcodesignHere => { code: 1, text: "Signing here needs rcodesign, and it is not released for this system: install it and put it on PATH." }
			RcodesignDownload(url) => { code: 1, text: "Could not download rcodesign from ${url}: curl's report is above." }
			RcodesignChecksum({ archive, expected, actual }) => { code: 1, text: "The downloaded ${archive} has SHA-256 ${actual}, not ${expected}, so it was not used." }
			RcodesignUnpack(file) => { code: 1, text: "Could not unpack rcodesign from ${file}: tar's report is above." }
			NotATag(ref) => { code: 1, text: "ci release attaches the zip to a pushed tag's release, and this run is for ${ref}: run it for a tag such as v1.0.0." }
			NoRepository => { code: 1, text: "ci release needs GITHUB_REPOSITORY, the owner/name of the repository whose release it adds to, which GitHub Actions sets." }
			GhMissing => { code: 1, text: "ci release uploads with GitHub's gh, which is not on PATH: install it (GitHub's runners have it)." }
			NoZips => { code: 1, text: "There is no zip in ${Package.dist}/ to attach: run `roc macos.roc ci package` first, or download its artifact there." }
			LinkInBundle(path) => { code: 1, text: "${path} is a symbolic link, which package does not zip: copy the file it names into assets/ instead." }
			RocMissing => { code: 1, text: "The Roc compiler is not on your PATH as `roc`, so the app cannot be built. Install Roc ${Bundle.roc_version} (or a later nightly) and put it on your PATH as `roc`." }
			NoMainRoc => { code: 1, text: "There is no src/main.roc here, so there is no app to build. Run this from your app's directory, or create an app with `roc macos.roc init my-app`." }
			ExpectsFailed(entry) => { code: 1, text: "roc test ${entry} failed, so the specs did not run: its report is above. Fix the expect, or the code it checks, and run test again." }
			NoFuzzTargets => { code: 1, text: "There is no tests/fuzz/main.roc here, so there is nothing to fuzz: it is an app on roc-fuzz's platform that checks the app's logic package, as `roc macos.roc init` writes one, and `roc macos.roc fuzz --help` describes it." }
			FuzzNotHere(system) => { code: 1, text: "roc-fuzz runs on Apple silicon Macs and on Linux x64, and this is ${system}, so fuzz cannot run here. `roc macos.roc test` runs the expect tests on any system." }
			UnknownFuzzTargets({ unknown, known }) => { code: 2, text: "tests/fuzz/main.roc has no target named ${Str.join_with(unknown, " or ")}: its targets are ${Str.join_with(known, ", ")}." }
			FuzzFailed({ failed, total }) => { code: 1, text: "${failed.len().to_str()} of ${total.to_str()} fuzz targets failed: ${Str.join_with(failed, ", ")}. Each report is above, and the input that failed is under .roc-fuzz/: `.macos/fuzz --target=NAME replay INPUT` runs it again." }
			BuildFailed => { code: 1, text: "The build failed: the compiler's report is above." }
			NotAMac({ command, system, bundle }) =>
				if command == "run" {
					{ code: 1, text: "Built ${bundle}, but this is ${system}, and the app runs only on a Mac: copy ${bundle} to one and open it there." }
				} else {
					{ code: 1, text: "The specs run the app, which runs only on a Mac, and this is ${system}, so test cannot run them here; `roc macos.roc test --check` parses them on any system, and `roc macos.roc build` builds the app." }
				}
			DevNotAMac(system) => { code: 1, text: "dev starts the app, which runs only on a Mac, and this is ${system}, so it cannot start it here. `roc macos.roc build` builds the app on any system." }
			UnknownTarget(given) => { code: 2, text: "--target is arm64mac (Apple silicon Macs) or x64mac (Intel Macs), not \"${given}\": leave it out to build a universal app, which runs on both." }
			NotThisMac({ bundle, mac, built }) => { code: 1, text: "Built ${bundle} for ${built}, which this Mac, one of the ${mac}, cannot run: build it with --target x64mac, or without --target for a universal app." }
			NotUniversal(_) => { code: 1, text: "roc build did not write one Mac program for Apple silicon and one for Intel in .macos/, so they cannot be joined into the app's universal program: build again, and report it if it recurs." }
			DevFailed({ how, code, entry }) => { code, text: "roc ${entry} ${how}: its output is above." }
			NoCases => { code: 1, text: "There is nothing to test: tests/specs/ holds no (test ...) spec. `roc macos.roc init` writes tests/specs/presets.scm as an example, and `roc macos.roc test --help` describes them." }
			CasesFailed({ failed, total }) => { code: 1, text: "${failed.len().to_str()} of ${total.to_str()} specs failed: ${Str.join_with(failed, ", ")}. If the app changed on purpose, rewrite their dumps with `roc macos.roc test --update`." }
			SpecsInvalid({ invalid, total }) => { code: 1, text: "${invalid.to_str()} of ${total.to_str()} specs could not be parsed, at the places above; `roc macos.roc test --help` describes the form." }
			AppFailed(how) => { code: 1, text: "The app ${how}: its output is above." }
			AssetsNotADirectory => { code: 1, text: "assets is not a directory: the app's images and other files go in a directory named assets in the app's directory." }
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

## No flags given.
nothing : Package.Options
nothing = { fields: Meta.none, sign: Bool.False, notarize: Bool.False, how: Universal }

## What `build --help` and `package --help` say about the metadata.
metadata_help : Str
metadata_help =
	\\The app's metadata comes from macos.json in the app's directory, if there is one,
	\\and from these flags, which override it. Each field is optional:
	\\
	\\  --name TEXT           its name in the menu bar and About (by default <name>)
	\\  --id ID               its bundle identifier, which also names its saved
	\\                        settings (by default com.example.<name>)
	\\  --version 1.2.0       CFBundleShortVersionString (by default 0.1)
	\\  --build 42            CFBundleVersion, the build number (by default the version)
	\\  --copyright TEXT      NSHumanReadableCopyright, shown in About
	\\  --category CATEGORY   LSApplicationCategoryType, such as public.app-category.utilities
	\\  --minimum-macos 26.0  LSMinimumSystemVersion (by default 15.0, the oldest it runs on)
	\\
	\\In macos.json the fields are text: { "version": "1.2.0", "minimum_macos": "26.0" }.

## Each command line names its command, with the defaults filled in.
expect {
	actual = [[], ["help"], ["init"], ["init", "my-app"], ["build"], ["run", "--id", "org.me.app", "--name", "My App"], ["dev"], ["test"], ["test", "--update"]].map(MacOS.parse)
	expected = [Ok(Help), Ok(Help), Ok(Init(".")), Ok(Init("my-app")), Ok(Build({ fields: Meta.none, how: Universal })), Ok(Run({ fields: { ..Meta.none, id: "org.me.app", name: "My App" }, how: Universal })), Ok(Dev), Ok(Test({ update: Bool.False, check: Bool.False, metrics: Bool.False })), Ok(Test({ update: Bool.True, check: Bool.False, metrics: Bool.False }))]
	actual == expected
}

## package takes the metadata flags, --sign and --notarize, in any order.
expect {
	actual = [["package"], ["package", "--version", "1.2.0", "--sign"], ["package", "--notarize", "--minimum-macos", "13.0", "--build", "7"]].map(MacOS.parse)
	expected = [
		Ok(Package(nothing)),
		Ok(Package({ ..nothing, fields: { ..Meta.none, version: "1.2.0" }, sign: Bool.True })),
		Ok(Package({ ..nothing, fields: { ..Meta.none, minimum_macos: "13.0", build: "7" }, notarize: Bool.True })),
	]
	actual == expected
}

## --target builds one Mac's thin program, for build, run, package and ci
## package alike; a target that is not a Mac's is refused, and test and dev
## take none.
expect {
	actual = [["build", "--target", "x64mac"], ["run", "--target", "arm64mac", "--version", "1.2.0"], ["package", "--sign", "--target", "x64mac"], ["ci", "package", "--target", "arm64mac"], ["build", "--target", "x64v1mac"], ["build", "--target"], ["test", "--target", "x64mac"]].map(MacOS.parse)
	expected = [
		Ok(Build({ fields: Meta.none, how: Native("x64mac") })),
		Ok(Run({ fields: { ..Meta.none, version: "1.2.0" }, how: Native("arm64mac") })),
		Ok(Package({ ..nothing, sign: Bool.True, how: Native("x64mac") })),
		Ok(CiPackage({ fields: Meta.none, how: Native("arm64mac") })),
		Err(UnknownTarget("x64v1mac")),
		Err(UnexpectedArguments({ command: "build", extra: ["--target"] })),
		Err(UnexpectedArguments({ command: "test", extra: ["--target", "x64mac"] })),
	]
	actual == expected
}

## An unknown target, and a build this Mac cannot run, each say what to do.
expect {
	explained = [UnknownTarget("x86"), NotThisMac({ bundle: "counter.app", mac: "Intel Macs (x64mac)", built: "Apple silicon Macs (arm64mac)" })].map(MacOS.explain)
	explained == [
		{ code: 2, text: "--target is arm64mac (Apple silicon Macs) or x64mac (Intel Macs), not \"x86\": leave it out to build a universal app, which runs on both." },
		{ code: 1, text: "Built counter.app for Apple silicon Macs (arm64mac), which this Mac, one of the Intel Macs (x64mac), cannot run: build it with --target x64mac, or without --target for a universal app." },
	]
}

## A misused command line is refused with what was wrong.
expect {
	actual = [["buld"], ["build", "--watch"], ["run", "--id"], ["init", "a", "b"], ["test", "--record"], ["build", "--sign"], ["package", "--version", "--sign"]].map(MacOS.parse)
	expected = [
		Err(UnknownCommand("buld")),
		Err(UnexpectedArguments({ command: "build", extra: ["--watch"] })),
		Err(UnexpectedArguments({ command: "run", extra: ["--id"] })),
		Err(UnexpectedArguments({ command: "init", extra: ["a", "b"] })),
		Err(UnexpectedArguments({ command: "test", extra: ["--record"] })),
		Err(UnexpectedArguments({ command: "build", extra: ["--sign"] })),
		Err(UnexpectedArguments({ command: "package", extra: ["--version", "--sign"] })),
	]
	actual == expected
}

## A bad field says which, where it came from, and what is wanted.
expect {
	actual = [
		BadField({ field: "version", value: "v1.0", from: Flag }),
		BadField({ field: "minimum_macos", value: "10.15", from: File }),
		MetaUnknownField("nmae"),
		MetaMalformed({ line: 3.U64, expected: "a comma or the closing }" }),
	].map(MacOS.explain)
	match actual {
		[flag, file, unknown, malformed] =>
			flag == { code: 2, text: "--version, \"v1.0\", is not a version: write one to three whole numbers separated by dots, such as 1.2.0, with no v, and optionally a pre-release suffix, such as 1.2.0-beta.1." }
				and file.text.starts_with("macos.json's minimum_macos, \"10.15\", is not a macOS version")
				and unknown.text.ends_with("the fields are name, id, version, build, copyright, category, minimum_macos.")
				and malformed.text.starts_with("macos.json is not the JSON object the tool reads: on line 3 it expected a comma or the closing }.")
		_ => Bool.False
	}
}

## fuzz takes --check, --time and target names; a bad time is refused.
expect {
	actual = [["fuzz"], ["fuzz", "--check"], ["fuzz", "money-parse", "--time", "60"], ["fuzz", "--time", "soon"], ["fuzz", "--update"]].map(MacOS.parse)
	expected = [
		Ok(Fuzz(Fuzz.defaults)),
		Ok(Fuzz({ ..Fuzz.defaults, check: Bool.True })),
		Ok(Fuzz({ ..Fuzz.defaults, names: ["money-parse"], seconds: 60 })),
		Err(UnexpectedArguments({ command: "fuzz", extra: ["--time", "soon"] })),
		Err(UnexpectedArguments({ command: "fuzz", extra: ["--update"] })),
	]
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
	explained = [UnknownCommand("x"), UnexpectedArguments({ command: "test", extra: ["-v"] }), BadField({ field: "id", value: "x", from: Flag }), NoMainRoc, NotAMac({ command: "run", system: "Linux", bundle: "counter.app" }), CasesFailed({ failed: ["reset"], total: 2 })].map(MacOS.explain)
	run_elsewhere = explained.drop_first(4).first().map_ok(|e| e.text)
	explained.map(|e| e.code) == [2, 2, 2, 1, 1, 1] and run_elsewhere == Ok("Built counter.app, but this is Linux, and the app runs only on a Mac: copy counter.app to one and open it there.")
}

## An icon that cannot be used says why, in its own words.
expect {
	explained = [BadIcon(NotSquare({ width: 1024.U32, height: 512.U32 })), BadIcon(UnsupportedSize(100.U32)), TwoIcons].map(|problem| MacOS.explain(problem).text)
	explained.all(|text| text.starts_with("assets/")) and explained.first() == Ok("assets/icon.png is 1024 by 512 pixels, and an app's icon is square: make it 1024 by 1024 pixels.")
}

## ci packages with metadata flags and decides signing itself; ci release takes nothing.
expect {
	actual = [["ci", "package"], ["ci", "package", "--version", "1.0.0-beta.1"], ["ci", "release"], ["ci", "package", "--sign"], ["ci", "release", "--draft"], ["ci"]].map(MacOS.parse)
	expected = [
		Ok(CiPackage({ fields: Meta.none, how: Universal })),
		Ok(CiPackage({ fields: { ..Meta.none, version: "1.0.0-beta.1" }, how: Universal })),
		Ok(CiRelease),
		Err(UnexpectedArguments({ command: "ci package", extra: ["--sign"] })),
		Err(UnexpectedArguments({ command: "ci", extra: ["release", "--draft"] })),
		Err(UnexpectedArguments({ command: "ci", extra: [] })),
	]
	actual == expected
}

## dev takes no arguments: the metadata flags belong to the .app, which it
## does not make, and `--` with arguments after it is refused, not passed on.
expect {
	actual = [["dev", "--id", "org.me.app"], ["dev", "main.roc"], ["dev", "-h"]].map(MacOS.parse)
	expected = [Err(UnexpectedArguments({ command: "dev", extra: ["--id", "org.me.app"] })), Err(UnexpectedArguments({ command: "dev", extra: ["main.roc"] })), Ok(CommandHelp("dev"))]
	actual == expected
}

## dev elsewhere points at build; a failed run keeps roc's exit code.
expect {
	explained = [DevNotAMac("Linux"), DevFailed({ how: "exited with code 3", code: 3, entry: "src/main.roc" })].map(MacOS.explain)
	explained == [
		{ code: 1, text: "dev starts the app, which runs only on a Mac, and this is Linux, so it cannot start it here. `roc macos.roc build` builds the app on any system." },
		{ code: 3, text: "roc src/main.roc exited with code 3: its output is above." },
	]
}
