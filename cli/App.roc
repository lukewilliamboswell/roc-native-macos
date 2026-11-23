import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stdout
import cli.System
import Icon
import Meta
import Universal

## Build an app with Roc into `<name>.app`, and start it.
##
## `roc build --target=arm64mac` and `--target=x64mac` write the program for
## Apple silicon and for Intel Macs, and the tool joins the two into one
## universal program, `.macos/<name>` (`Universal`): the platform carries the
## Swift host for each and the linker's inputs, and Roc's linker signs each
## program (ad hoc), so this works the same on macOS, Linux and Windows. The
## tool then writes `<name>.app` around it: the program in
## `Contents/MacOS/`, a copy of `assets/` in `Contents/Resources/`, the icon,
## and an `Info.plist` with its metadata (`Meta`: `macos.json` and the
## flags). Only running it needs a Mac.
App := [].{

	## The build directory, beside `main.roc`.
	work : Str
	work = ".macos"

	## The Roc targets of the platform: Apple silicon and Intel Macs, in the
	## order they are built.
	mac_targets : List(Str)
	mac_targets = ["arm64mac", "x64mac"]

	## Build the program, `.macos/<name>`, from `main.roc`: for this Mac's
	## own target (`Native`), which `test` runs, or for every Mac
	## (`Universal`), which `build` and `run` put in `<name>.app`.
	compile! : [Native(Str), Universal] => Try({ name : Str, program : Str }, _)
	compile! = |how| {
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
		match how {
			Native(target) => App.build_for!(target, program)?
			Universal => {
				var $slices = []
				for target in App.mac_targets {
					thin = "${App.work}/${name}-${target}"
					App.build_for!(target, thin)?
					$slices = $slices.append(thin)
				}
				var $bytes = []
				for thin in $slices {
					$bytes = $bytes.append(Path.read_bytes!(Path.utf8(thin))?)
				}
				universal = Universal.merge($bytes) ? |problem| NotUniversal(problem)
				# A copy keeps the thin program's execute permission, which
				# writing over it keeps too.
				first = $slices.first() ? |_| NotUniversal(NotAProgram)
				Path.copy!(Path.utf8(first), Path.utf8(program))?
				Path.write_bytes!(Path.utf8(program), universal)?
			}
		}
		App.place_assets!("${App.work}/assets")?
		Ok({ name, program })
	}

	## `roc build` the program for one target into `program`.
	build_for! : Str, Str => Try({}, _)
	build_for! = |target, program| {
		Stdout.line!("Building main.roc for ${App.target_name(target)}...")?
		built = Cmd.new("roc").args(["build", "main.roc", "--target=${target}", "--output=${program}"].map(OsStr.from_str)).inherit_stdio().run!()?
		if built.status != Exited(0) {
			return Err(BuildFailed)
		}
		Ok({})
	}

	## A target's name in a sentence.
	target_name : Str -> Str
	target_name = |target| if (target == "x64mac") "Intel Macs (x64mac)" else "Apple silicon Macs (arm64mac)"

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

	## The fields `macos.json` gives, or none when there is no such file.
	written! : () => Try(Meta.Fields, _)
	written! = || {
		file = Path.utf8(Meta.file)
		if !(Path.exists!(file)?) {
			return Ok(Meta.none)
		}
		fields = Meta.from_json(Path.read_utf8!(file)?)?
		Meta.check(fields, File)?
		Ok(fields)
	}

	## Build `<name>.app` from `main.roc`, with the metadata `macos.json`
	## gives and `flags` override, and say what it is.
	build! : Meta.Fields => Try({ bundle : Str, name : Str, meta : Meta.Resolved }, _)
	build! = |flags| {
		Meta.check(flags, Flag)?
		written = App.written!()?
		icon = App.icon!()?
		{ name, program } = App.compile!(Universal)?
		meta = Meta.resolve(Meta.over(flags, written), name)
		bundle = "${Meta.bundle_name(meta.name)}.app"
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
		Path.write_utf8!(Path.utf8("${bundle}/Contents/Info.plist"), App.info_plist(meta, name, has_icon))?
		Stdout.line!("Built ${bundle}: ${meta.name} ${meta.release} (${meta.id}), for Apple silicon and Intel Macs with macOS ${meta.minimum_macos} or later.")?
		Ok({ bundle, name, meta })
	}

	## Build `<name>.app` and run the program inside it, with its output in
	## this terminal, until the app quits.
	run! : Meta.Fields => Try({}, _)
	run! = |flags| {
		{ bundle, name, .. } = App.build!(flags)?
		match App.system(System.target!()) {
			Mac(_) => {}
			Other(here) => return Err(NotAMac({ command: "run", system: here, bundle }))
		}
		Stdout.line!("Running ${bundle}. Quit it (Command-Q) to return here.")?
		ran = Cmd.new(OsStr.from_str("${bundle}/Contents/MacOS/${name}")).inherit_stdio().run!()?
		match ran.status {
			Exited(0) => Ok({})
			Exited(code) => Err(AppFailed("exited with code ${code.to_str()}"))
			Signaled(signal) => Err(AppFailed("stopped on signal ${signal.to_str()}"))
		}
	}

	## Start `roc main.roc` in this directory, with this terminal, until it
	## ends: Roc's run mode, which rebuilds the app when a file it reads is
	## saved and swaps the new code in, for Command-R (*Reload*) to remount.
	## The bare program finds `assets/` here; `macos.json` and the icon
	## belong to the `.app`, which this does not make.
	dev! : () => Try({}, _)
	dev! = || {
		if !(Path.exists!(Path.utf8("main.roc"))?) {
			return Err(NoMainRoc)
		}
		match App.system(System.target!()) {
			Mac(_) => {}
			Other(here) => return Err(DevNotAMac(here))
		}
		if !Cmd.check_available!("roc") {
			return Err(RocMissing)
		}
		Stdout.line!("Running main.roc with `roc main.roc`: it rebuilds when you save, and Command-R in the app shows the new code.")?
		ran = Cmd.new("roc").args(["main.roc"].map(OsStr.from_str)).inherit_stdio().run!()?
		match ran.status {
			Exited(0) => Ok({})
			Exited(code) => Err(DevFailed({ how: "exited with code ${code.to_str()}", code }))
			Signaled(signal) => Err(DevFailed({ how: "stopped on signal ${signal.to_str()}", code: 128 + signal }))
		}
	}

	## Whether the app can run here: a Mac runs it, Apple silicon or Intel,
	## and its own Roc target is the one `test` builds for. Otherwise, the
	## system's name for a sentence.
	system : System.Target -> [Mac(Str), Other(Str)]
	system = |target|
		match (target.os(), target.arch()) {
			(MacOS(_), Arm64) => Mac("arm64mac")
			(MacOS(_), X64) => Mac("x64mac")
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

	## The app's `Info.plist`, for the program `executable`. With an icon,
	## `CFBundleIconFile` names it; a copyright and a category are written
	## only when given. `LSMinimumSystemVersion` is by default the `minos`
	## Roc's linker writes.
	info_plist : Meta.Resolved, Str, Bool -> Str
	info_plist = |meta, executable, icon| {
		optional = [
			("NSHumanReadableCopyright", meta.copyright),
			("LSApplicationCategoryType", meta.category),
			("CFBundleIconFile", if (icon) Icon.bundled.drop_suffix(".icns") else ""),
		]
		extra = optional.keep_if(|(_, value)| !value.is_empty()).map(|(key, value)| "\t<key>${key}</key><string>${App.escape(value)}</string>\n")
		\\<?xml version="1.0" encoding="UTF-8"?>
		\\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
		\\<plist version="1.0">
		\\<dict>
		\\	<key>CFBundleIdentifier</key><string>${meta.id}</string>
		\\	<key>CFBundleName</key><string>${App.escape(meta.name)}</string>
		\\	<key>CFBundleDisplayName</key><string>${App.escape(meta.name)}</string>
		\\	<key>CFBundleExecutable</key><string>${executable}</string>
		\\	<key>CFBundlePackageType</key><string>APPL</string>
		\\	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
		\\	<key>CFBundleShortVersionString</key><string>${meta.version}</string>
		\\	<key>CFBundleVersion</key><string>${meta.build}</string>
		\\	<key>NSPrincipalClass</key><string>NSApplication</string>
		\\	<key>NSHighResolutionCapable</key><true/>
		\\	<key>LSMinimumSystemVersion</key><string>${meta.minimum_macos}</string>
		\\${Str.join_with(extra, "")}</dict>
		\\</plist>
		\\
	}

	## Text as XML character data.
	escape : Str -> Str
	escape = |text| text.replace_each("&", "&amp;").replace_each("<", "&lt;").replace_each(">", "&gt;")
}

expect [App.app_name("My App"), App.app_name("counter"), App.app_name("todo_list"), App.app_name("..")] == ["my-app", "counter", "todo-list", "app"]

expect [App.last_part("/Users/me/counter"), App.last_part("C:\\Users\\me\\counter"), App.last_part("counter")] == ["counter", "counter", "counter"]

## Without metadata the plist has the defaults, and no optional keys.
expect {
	text = App.info_plist({ ..Meta.resolve(Meta.none, "counter"), name: "Tom & Jerry" }, "counter", Bool.False)
	text.contains("<key>CFBundleIdentifier</key><string>com.example.counter</string>")
		and text.contains("<key>CFBundleName</key><string>Tom &amp; Jerry</string>")
		and text.contains("<key>CFBundleExecutable</key><string>counter</string>")
		and text.contains("<key>CFBundleShortVersionString</key><string>0.1</string>")
		and text.contains("<key>CFBundleVersion</key><string>0.1</string>")
		and text.contains("<key>LSMinimumSystemVersion</key><string>15.0</string>")
		and !text.contains("CFBundleIconFile")
		and !text.contains("NSHumanReadableCopyright")
}

## An app with an icon names it, `Contents/Resources/AppIcon.icns`; a
## copyright and a category are written when given.
expect {
	meta = { ..Meta.resolve(Meta.none, "about"), version: "1.2.0", build: "7", copyright: "© 2026 <Jane>", category: "public.app-category.utilities" }
	text = App.info_plist(meta, "about", Bool.True)
	text.contains("\t<key>NSHumanReadableCopyright</key><string>© 2026 &lt;Jane&gt;</string>\n\t<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>\n\t<key>CFBundleIconFile</key><string>AppIcon</string>\n</dict>")
		and text.contains("<key>CFBundleShortVersionString</key><string>1.2.0</string>")
		and text.contains("<key>CFBundleVersion</key><string>7</string>")
}
