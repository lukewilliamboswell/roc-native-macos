import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stdout
import cli.System
import Icon

## Build an app with Roc into `<name>.app`, and start it.
##
## `roc build --target=arm64mac` writes the program to `.macos/<name>`: the
## platform carries the Swift host and the linker's inputs, and Roc's linker
## signs the program (ad hoc), so this works the same on macOS, Linux and
## Windows. The tool then writes `<name>.app` around it: the program in
## `Contents/MacOS/`, a copy of `assets/` in `Contents/Resources/`, the icon,
## and an `Info.plist` naming its bundle identifier. Only running it needs a
## Mac.
App := [].{

	## The app's bundle identifier and name in the menu bar; empty means the
	## default.
	Options : { id : Str, name : Str }

	## The build directory, beside `main.roc`.
	work : Str
	work = ".macos"

	## Build the program, `.macos/<name>`, from `main.roc`. `test` runs this
	## program; `build` and `run` put it in `<name>.app`.
	compile! : () => Try({ name : Str, program : Str }, _)
	compile! = || {
		if !(Path.exists!(Path.utf8("main.roc"))?) {
			return Err(NoMainRoc)
		}
		if !Cmd.check_available!("roc") {
			return Err(RocMissing)
		}
		cwd = Env.cwd!()?.display()
		name = App.app_name(App.last_part(cwd))
		program = "${App.work}/${name}"
		Path.create_all!(Path.utf8(App.work))?
		if Path.exists!(Path.utf8(program))? {
			Path.delete!(Path.utf8(program))?
		}
		Stdout.line!("Building main.roc for Apple silicon macOS...")?
		built = Cmd.new("roc").args(["build", "main.roc", "--target=arm64mac", "--output=${program}"].map(OsStr.from_str)).inherit_stdio().run!()?
		if built.status != Exited(0) {
			return Err(BuildFailed)
		}
		App.place_assets!("${App.work}/assets")?
		Ok({ name, program })
	}

	## Where an app keeps its images and other files, beside `main.roc`.
	assets : Str
	assets = "assets"

	## Copy the app's `assets/` to `dir`, replacing what was there. The
	## program looks for `assets/` beside it, or in the `.app`'s
	## `Contents/Resources/` (`docs/ui.adoc`, "Assets").
	place_assets! : Str => Try({}, _)
	place_assets! = |dir| {
		if Path.exists!(Path.utf8(dir))? {
			Path.delete_all!(Path.utf8(dir))?
		}
		if Path.exists!(Path.utf8(App.assets))? {
			if !(Path.is_dir!(Path.utf8(App.assets))?) {
				return Err(AssetsNotADirectory)
			}
			Path.copy_dir!(Path.utf8(App.assets), Path.utf8(dir))?
		}
		Ok({})
	}

	## The app's icon as an `.icns`: `assets/icon.icns` as it is, or
	## `assets/icon.png` wrapped in one; none if there is neither.
	icon! : () => Try([NoIcon, Icns(List(U8))], _)
	icon! = || {
		png = Path.utf8("${App.assets}/${Icon.png}")
		icns = Path.utf8("${App.assets}/${Icon.icns}")
		match (Path.exists!(png)?, Path.exists!(icns)?) {
			(Bool.True, Bool.True) => Err(TwoIcons)
			(Bool.True, _) =>
				match Icon.from_png(Path.read_bytes!(png)?) {
					Ok(bytes) => Ok(Icns(bytes))
					Err(problem) => Err(BadIcon(problem))
				}
			(_, Bool.True) => {
				bytes = Path.read_bytes!(icns)?
				if (Icon.is_icns(bytes)) Ok(Icns(bytes)) else Err(BadIcon(NotIcns))
			}
			_ => Ok(NoIcon)
		}
	}

	## Build `<name>.app` from `main.roc`, and say what it is.
	build! : Options => Try({ bundle : Str, name : Str }, _)
	build! = |options| {
		if !options.id.is_empty() and !App.valid_id(options.id) {
			return Err(BadId(options.id))
		}
		icon = App.icon!()?
		{ name, program } = App.compile!()?
		id = if (options.id.is_empty()) "com.example.${name}" else options.id
		label = if (options.name.is_empty()) name else options.name
		bundle = "${name}.app"
		if Path.exists!(Path.utf8(bundle))? {
			Path.delete_all!(Path.utf8(bundle))?
		}
		Path.create_all!(Path.utf8("${bundle}/Contents/MacOS"))?
		Path.create_all!(Path.utf8("${bundle}/Contents/Resources"))?
		Path.copy!(Path.utf8(program), Path.utf8("${bundle}/Contents/MacOS/${name}"))?
		App.place_assets!("${bundle}/Contents/Resources/assets")?
		has_icon = match icon {
			Icns(bytes) => {
				Path.write_bytes!(Path.utf8("${bundle}/Contents/Resources/${Icon.bundled}"), bytes)?
				Bool.True
			}
			NoIcon => Bool.False
		}
		Path.write_utf8!(Path.utf8("${bundle}/Contents/Info.plist"), App.info_plist({ id, name, label, icon: has_icon }))?
		Stdout.line!("Built ${bundle}: ${label} (${id}), for Apple silicon Macs with macOS 11 or later.")?
		Ok({ bundle, name })
	}

	## Build `<name>.app` and run the program inside it, with its output in
	## this terminal, until the app quits.
	run! : Options => Try({}, _)
	run! = |options| {
		{ bundle, name } = App.build!(options)?
		match App.system(System.target!()) {
			AppleSilicon => {}
			Other(here) => return Err(NotAppleSilicon({ command: "run", system: here, bundle }))
		}
		Stdout.line!("Running ${bundle}. Quit it (Command-Q) to return here.")?
		ran = Cmd.new(OsStr.from_str("${bundle}/Contents/MacOS/${name}")).inherit_stdio().run!()?
		match ran.status {
			Exited(0) => Ok({})
			Exited(code) => Err(AppFailed("exited with code ${code.to_str()}"))
			Signaled(signal) => Err(AppFailed("stopped on signal ${signal.to_str()}"))
		}
	}

	## Whether the app can run here: only an Apple silicon Mac runs it.
	## Otherwise, the system's name for a sentence.
	system : System.Target -> [AppleSilicon, Other(Str)]
	system = |target|
		match (target.os(), target.arch()) {
			(MacOS(_), Arm64) => AppleSilicon
			(MacOS(_), X64) => Other("an Intel Mac")
			(Linux(_), _) => Other("Linux")
			(Windows(_), _) => Other("Windows")
		}

	## The last part of a path, `/` or `\` separated.
	last_part : Str -> Str
	last_part = |path| path.split_on("\\").last().map_ok(|rest| rest.split_on("/").last() ?? rest) ?? path

	## The app's name, from its directory: lower-case letters, digits and
	## hyphens, which a bundle identifier also allows.
	app_name : Str -> Str
	app_name = |dir| {
		bytes = dir.to_utf8().map(
			|b|
				if b >= 'A' and b <= 'Z' {
					b + 32
				} else if (b >= 'a' and b <= 'z') or (b >= '0' and b <= '9') {
					b
				} else {
					'-'
				},
		)
		name = Str.from_utf8_lossy(bytes)
		if (name.is_empty() or name.to_utf8().all(|b| b == '-')) "app" else name
	}

	## Whether `id` is a bundle identifier: two or more dot-separated parts,
	## each of letters, digits and hyphens.
	valid_id : Str -> Bool
	valid_id = |id| {
		parts = id.split_on(".")
		parts.len() >= 2
			and parts.all(
				|part| {
					bytes = part.to_utf8()
					!bytes.is_empty() and bytes.all(|b| (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or (b >= '0' and b <= '9') or b == '-')
				},
			)
	}

	## The app's `Info.plist`. `LSMinimumSystemVersion` is the `minos` Roc's
	## linker writes. With an icon, `CFBundleIconFile` names it.
	info_plist : { id : Str, name : Str, label : Str, icon : Bool } -> Str
	info_plist = |{ id, name, label, icon }| {
		icon_key = if (icon) "\t<key>CFBundleIconFile</key><string>${Icon.bundled.drop_suffix(".icns")}</string>\n" else ""
		\\<?xml version="1.0" encoding="UTF-8"?>
		\\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
		\\<plist version="1.0">
		\\<dict>
		\\	<key>CFBundleIdentifier</key><string>${id}</string>
		\\	<key>CFBundleName</key><string>${App.escape(label)}</string>
		\\	<key>CFBundleExecutable</key><string>${name}</string>
		\\	<key>CFBundlePackageType</key><string>APPL</string>
		\\	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
		\\	<key>CFBundleShortVersionString</key><string>0.1</string>
		\\	<key>NSPrincipalClass</key><string>NSApplication</string>
		\\	<key>NSHighResolutionCapable</key><true/>
		\\	<key>LSMinimumSystemVersion</key><string>11.0</string>
		\\${icon_key}</dict>
		\\</plist>
		\\
	}

	## Text as XML character data.
	escape : Str -> Str
	escape = |text| text.replace_each("&", "&amp;").replace_each("<", "&lt;").replace_each(">", "&gt;")
}

expect [App.app_name("My App"), App.app_name("counter"), App.app_name("todo_list"), App.app_name("..")] == ["my-app", "counter", "todo-list", "app"]

expect [App.last_part("/Users/me/counter"), App.last_part("C:\\Users\\me\\counter"), App.last_part("counter")] == ["counter", "counter", "counter"]

expect [App.valid_id("com.example.counter"), App.valid_id("com.example.my-app"), App.valid_id("counter"), App.valid_id("com..app"), App.valid_id("com.my_app")] == [Bool.True, Bool.True, Bool.False, Bool.False, Bool.False]

expect {
	text = App.info_plist({ id: "com.example.counter", name: "counter", label: "Tom & Jerry", icon: Bool.False })
	text.contains("<key>CFBundleIdentifier</key><string>com.example.counter</string>") and text.contains("<string>Tom &amp; Jerry</string>") and text.contains("<key>CFBundleExecutable</key><string>counter</string>") and !text.contains("CFBundleIconFile")
}

## An app with an icon names it, `Contents/Resources/AppIcon.icns`.
expect App.info_plist({ id: "com.example.about", name: "about", label: "about", icon: Bool.True }).contains("\t<key>CFBundleIconFile</key><string>AppIcon</string>\n</dict>")
