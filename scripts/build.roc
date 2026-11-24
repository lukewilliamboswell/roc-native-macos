#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	roc: "nightly-2026-11-22-3350b1c",
}

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stderr
import cli.Stdout
import src/Build
import src/Facade
import src/LinkInputs
import src/Tar

## The `build` task: the platform's native inputs and every example.
##
##     blueprint run build                         # the host, the linker inputs, then every example
##     blueprint run build -- counter todos        # the named examples (after the platform is built)
##     blueprint run build -- --platform           # the platform only: the host and the linker inputs
##     blueprint run build -- --link-inputs DIR    # with a candidate from `link-inputs -- build DIR`
##     blueprint run build -- glue                 # regenerate the committed glue in host/
##     blueprint run build -- glue --check         # require the committed glue to be what roc generates
##     blueprint run build -- engine               # regenerate the engine facades in platform/
##     blueprint run build -- engine --check       # require the committed facades to be what the engine package gives
##     blueprint run build -- host --fingerprint   # print the hosts' fingerprint (CI's cache key)
##     blueprint run build -- host --reproduce     # build each host twice and require identical bytes
##
## The host: `host/*.swift`, with the committed glue `host/roc_swift_abi.h` as
## its bridging header, compiled for each of the platform's targets
## (`Build.host_targets`: `arm64mac` and `x64mac`, with an explicit Swift
## `-target`, so either Mac cross-compiles both) object by object under
## `build/host-<target>` and archived by `libtool -static -D` into
## `platform/targets/<target>/libhost.a`. Each is reproducible, so each is
## fingerprinted: its target, its sources, the glue header, this recipe,
## swiftc and Xcode. A `libhost.a` whose recorded `libhost.fingerprint`
## matches is reused, not recompiled.
##
## The linker inputs: the macOS TAPI stubs `platform/targets/macos-sysroot`,
## from the release `link-inputs.lock.json` selects (downloaded once into
## `build/link-inputs-cache`, and verified by size and SHA-256 on every
## use), or from a candidate directory. A lock whose input fingerprint is not
## this checkout's fails: a changed catalog or producer is a new release
## (`link-inputs.yml`, then `publish-link-inputs.yml`). Until the first
## release there is no lock, and the stubs are generated from the catalog.
## Then the host's unresolved references are audited against the catalog: a
## reference the catalog does not own fails the build. So are the system
## imports of the package compiler's run shims, the archives `roc main.roc`
## links the host with (carved out of the compiler, where they are embedded,
## into `build/run-shims`): one the catalog does not own, or owns without
## listing it in `run_shim`, fails the build too.
##
## An example: `roc build`, then `<name>.app` beside the binary, with its
## `assets/` under `Contents/Resources/assets` and an `assets/icon.icns` as
## its icon. The package compiler is `$ROC`, by default the `roc` on PATH.
main! : List(OsStr) => Try({}, _)
main! = |raw_args| {
	options = match Build.options(raw_args.map(OsStr.display)) {
		Ok(found) => found
		Err(Usage) => {
			warn!(Build.usage)
			return Err(Exit(2))
		}
	}
	roc = env!("ROC", "roc")
	result = match options.command {
		All => everything!(roc, options.link_inputs)
		Platform => platform!(roc, options.link_inputs)
		Examples(names) => examples!(roc, Ok(names))
		Glue => glue!(roc, Bool.False)
		GlueCheck => glue!(roc, Bool.True)
		Engine => engine!(Bool.False)
		EngineCheck => engine!(Bool.True)
		Host => host!()
		HostFingerprint => print_fingerprint!()
		HostReproduce => reproduce!()
	}
	match result {
		Ok({}) => Ok({})
		Err(problem) => {
			warn!("build: ${problem}")
			Err(Exit(1))
		}
	}
}

## The platform, then every example.
everything! : Str, Str => Try({}, Str)
everything! = |roc, candidate| {
	platform!(roc, candidate)?
	examples!(roc, Err(All))
}

## The hosts' fingerprint, over every target's, also as the step output
## `fingerprint` when the build runs in a workflow (the host job's cache key
## for every `libhost.a`).
print_fingerprint! : () => Try({}, Str)
print_fingerprint! = || {
	var $each = []
	for target in Build.host_targets {
		$each = $each.append((target, host_fingerprint!(target)?))
	}
	write!("build/hosts-fingerprint.txt", Build.hosts_fingerprint_text($each))?
	found = sha256!("build/hosts-fingerprint.txt")?
	note!(found)
	output = env!("GITHUB_OUTPUT", "")
	if output.is_empty() {
		Ok({})
	} else {
		before = Path.read_utf8!(Path.utf8(output)) ?? ""
		Path.write_utf8!(Path.utf8(output), "${before}fingerprint=${found}\n").map_err(|error| "could not write GITHUB_OUTPUT: ${Str.inspect(error)}")
	}
}

## The host, the linker inputs, and the audit of the host and of the
## compiler's run shims against them.
platform! : Str, Str => Try({}, Str)
platform! = |roc, candidate| {
	host!()?
	link_inputs!(candidate)?
	audit!(roc)
}

## The Swift sources of the host, relative to the checkout.
swift_sources! : () => Try(List(Str), Str)
swift_sources! = || {
	names = list!("host")?
	Ok(names.keep_if(|name| name.ends_with(".swift")).map(|name| "host/${name}"))
}

host_fingerprint! : Build.HostTarget => Try(Str, Str)
host_fingerprint! = |target| {
	var $files = []
	for path in Build.host_inputs(swift_sources!()?) {
		$files = $files.append({ path, sha256: sha256!(path)? })
	}
	text = Build.host_fingerprint_text({ target, swiftc: capture!("swiftc", ["--version"])?, xcode: capture!("xcodebuild", ["-version"])?, files: $files })
	path = "build/host-fingerprint-${target.roc}.txt"
	write!(path, text)?
	sha256!(path)
}

## Build each target's host unless its recorded fingerprint is this
## checkout's.
host! : () => Try({}, Str)
host! = || {
	for target in Build.host_targets {
		fingerprint = host_fingerprint!(target)?
		library = "platform/${Build.host_library(target)}"
		recorded = "platform/${Build.host_fingerprint_file(target)}"
		current = (Path.exists!(Path.utf8(library)) ?? Bool.False) and (read!(recorded) ?? "").trim() == fingerprint
		if current {
			note!("build: ${library} is current (host fingerprint ${fingerprint})")
		} else {
			compile!(target, Build.objects_dir(target), library)?
			write!(recorded, "${fingerprint}\n")?
			note!("build: ${library}, host fingerprint ${fingerprint}")
		}
		copies!(target)?
	}
	Ok({})
}

## Copy a target's host to the other Roc targets that link it (`also`).
copies! : Build.HostTarget => Try({}, Str)
copies! = |target| {
	library = "platform/${Build.host_library(target)}"
	for other in target.also {
		copy = "platform/targets/${other}/libhost.a"
		Path.create_all!(Path.utf8("platform/targets/${other}")) ? |error| "could not create platform/targets/${other}: ${Str.inspect(error)}"
		Path.copy!(Path.utf8(library), Path.utf8(copy)) ? |error| "could not copy ${library} to ${copy}: ${Str.inspect(error)}"
		note!("build: ${copy}, a copy of ${library}")
	}
	Ok({})
}

## Compile a target's host objects in `dir` (two levels below the checkout)
## and archive them into `library`.
compile! : Build.HostTarget, Str, Str => Try({}, Str)
compile! = |target, dir, library| {
	root = cwd!()?
	fresh!(dir)?
	parent = Str.join_with(library.split_on("/").drop_last(1), "/")
	Path.create_all!(Path.utf8(parent)) ? |error| "could not create ${parent}: ${Str.inspect(error)}"
	step!(Cmd.new("swiftc").args(Build.swiftc_args(target, swift_sources!()?).map(OsStr.from_str)).cwd(Path.utf8(dir)), "swiftc -target ${target.swift} (the host, into ${dir})")?
	objects = list!(dir)?.keep_if(|name| name.ends_with(".o"))
	step!(Cmd.new("libtool").args(Build.libtool_args("${root}/${library}", objects).map(OsStr.from_str)).cwd(Path.utf8(dir)).env("ZERO_AR_DATE", "1"), "libtool -static -D (${objects.len().to_str()} objects)")
}

## Build each target's host twice, in two directories, require the same
## bytes, and install the first as the platform's host with its fingerprint.
reproduce! : () => Try({}, Str)
reproduce! = || {
	for target in Build.host_targets {
		fingerprint = host_fingerprint!(target)?
		first_path = "build/host-${target.roc}-first.a"
		second_path = "build/host-${target.roc}-second.a"
		compile!(target, Build.objects_dir(target), first_path)?
		compile!(target, "build/again-${target.roc}", second_path)?
		first = sha256!(first_path)?
		second = sha256!(second_path)?
		if first != second {
			return Err("two builds of the ${target.roc} host differ: ${first} and ${second}")
		}
		library = "platform/${Build.host_library(target)}"
		write!("platform/${Build.host_fingerprint_file(target)}", "${fingerprint}\n")?
		Path.copy!(Path.utf8(first_path), Path.utf8(library)) ? |error| "could not install ${library}: ${Str.inspect(error)}"
		note!("build: the ${target.roc} host is reproducible: both builds are sha256 ${first}; installed as ${library}, host fingerprint ${fingerprint}")
		copies!(target)?
	}
	Ok({})
}

## Install the linker inputs into `platform/targets/macos-sysroot`: from a
## candidate directory, the lock's release, or before any release, the
## catalog.
link_inputs! : Str => Try({}, Str)
link_inputs! = |candidate| {
	fingerprint = link_fingerprint!()?
	archive = if !candidate.is_empty() {
		manifest_text = read!("${candidate}/${LinkInputs.manifest_name}")?
		parsed : Try(LinkInputs.Manifest, _)
		parsed = Json.parse(manifest_text)
		manifest = parsed ? |error| "${candidate}/${LinkInputs.manifest_name} is not a manifest: ${Str.inspect(error)}"
		LinkInputs.current(manifest.source.input_fingerprint, fingerprint) ? |Stale(why)| "the candidate in ${candidate} is not built from this checkout: ${why}"
		verified!("${candidate}/${LinkInputs.archive_name}", manifest.assets.macos)?
	} else if Path.exists!(Path.utf8(LinkInputs.lock_path)) ?? Bool.False {
		locked!(fingerprint)?
	} else {
		note!("build: no ${LinkInputs.lock_path} yet, so the stubs are generated from host/interfaces.json (until the first linker-input release)")
		generated!()?
	}
	install!(archive)
}

## The lock's archive, from the cache or its release, verified.
locked! : Str => Try(List(U8), Str)
locked! = |fingerprint| {
	text = read!(LinkInputs.lock_path)?
	parsed : Try(LinkInputs.Lock, _)
	parsed = Json.parse(text)
	lock = parsed ? |error| "${LinkInputs.lock_path} is not a lock: ${Str.inspect(error)}"
	targets_text = LinkInputs.object_at(text, "targets") ? |_| "${LinkInputs.lock_path} has no targets"
	targets_parsed : Try(LinkInputs.Targets, _)
	targets_parsed = Json.parse(targets_text)
	asset = (targets_parsed ? |_| "${LinkInputs.lock_path} has no ${LinkInputs.asset_key} target").macos
	match LinkInputs.current(lock.source.input_fingerprint, fingerprint) {
		Ok({}) => {}
		Err(Stale(why)) => return Err("${LinkInputs.lock_path} selects linker inputs for other sources (${why}). A change to the catalog or its producer is a new release: push it in a pull request, then dispatch publish-link-inputs.yml from main with its number, which commits the new lock")
	}
	cached = "build/link-inputs-cache/${asset.sha256}.tar"
	match verified!(cached, asset) {
		Ok(bytes) => Ok(bytes)
		Err(_) => {
			url = LinkInputs.download_url(lock, asset)
			download = "build/link-inputs-cache/download.tar"
			Path.create_all!(Path.utf8("build/link-inputs-cache")) ? |error| "could not create build/link-inputs-cache: ${Str.inspect(error)}"
			step!(Cmd.new("curl").args(["-fsSL", "--retry", "3", "-o", download, url].map(OsStr.from_str)), "curl ${url}")?
			bytes = verified!(download, asset)?
			Path.rename!(Path.utf8(download), Path.utf8(cached)) ? |error| "could not keep ${cached}: ${Str.inspect(error)}"
			Ok(bytes)
		}
	}
}

## A file's bytes, if its size and SHA-256 are the asset's.
verified! : Str, LinkInputs.Asset => Try(List(U8), Str)
verified! = |path, asset| {
	bytes = Path.read_bytes!(Path.utf8(path)) ? |_| "${path} is missing"
	if bytes.len() != asset.size {
		return Err("${path} is ${bytes.len().to_str()} bytes, not ${asset.size.to_str()}")
	}
	digest = sha256!(path)?
	if digest != asset.sha256 {
		return Err("${path} has sha256 ${digest}, not ${asset.sha256}")
	}
	Ok(bytes)
}

## The archive `link_inputs.roc build` would write, generated here.
generated! : () => Try(List(U8), Str)
generated! = || {
	dir = "build/link-inputs-bootstrap"
	step!(Cmd.new("roc-stable").args(["scripts/link_inputs.roc", "--", "build", dir].map(OsStr.from_str)), "scripts/link_inputs.roc -- build ${dir}")?
	Path.read_bytes!(Path.utf8("${dir}/${LinkInputs.archive_name}")).map_err(|error| "could not read the generated archive: ${Str.inspect(error)}")
}

## Unpack the archive's `macos-sysroot/` into `platform/targets/macos-sysroot`.
install! : List(U8) => Try({}, Str)
install! = |archive| {
	entries = Tar.read(archive) ? |Malformed(why)| "the linker-input archive is malformed: ${why}"
	sysroot = "platform/targets/macos-sysroot"
	fresh!(sysroot)?
	prefix = "${LinkInputs.sysroot_dir}/"
	stubs = entries.keep_if(|entry| entry.path.starts_with(prefix))
	if stubs.is_empty() {
		return Err("the linker-input archive holds no ${prefix} files")
	}
	for entry in stubs {
		path = "${sysroot}/${entry.path.drop_prefix(prefix)}"
		parent = Str.join_with(path.split_on("/").drop_last(1), "/")
		Path.create_all!(Path.utf8(parent)) ? |error| "could not create ${parent}: ${Str.inspect(error)}"
		Path.write_bytes!(Path.utf8(path), entry.bytes) ? |error| "could not write ${path}: ${Str.inspect(error)}"
	}
	note!("build: ${sysroot}, ${stubs.len().to_str()} interfaces")
	Ok({})
}

## Each target's host's unresolved references against what the catalog
## exports for that target, then the system imports of the compiler's run
## shims against what it exports for the compiler's own.
audit! : Str => Try({}, Str)
audit! = |roc| {
	text = read!("host/interfaces.json")?
	parsed : Try(LinkInputs.Catalog, _)
	parsed = Json.parse(text)
	catalog = parsed ? |error| "host/interfaces.json is not a schema 3 catalog: ${Str.inspect(error)}"
	owners = LinkInputs.check(catalog) ? |problem| "host/interfaces.json: ${problem}"
	# Noted only when no target's host references it.
	var $unused = owners.map(|(name, _)| name)
	for target in Build.host_targets {
		library = "platform/${Build.host_library(target)}"
		undefined = capture!("nm", ["-u", library])?.split_on("\n")
		defined = capture!("nm", ["-gUj", library])?.split_on("\n")
		exported = LinkInputs.exported(catalog, target.tapi)
		result = LinkInputs.audit({ undefined, defined, owners: exported, run_shim: catalog.run_shim.symbols })
		if !result.missing.is_empty() {
			return Err("${target.roc}: ${LinkInputs.missing_message(result.missing)}")
		}
		note!("build: the ${target.roc} host references only symbols the catalog exports for ${target.tapi} (${exported.len().to_str()} symbols)")
		here = LinkInputs.audit({ undefined, defined, owners, run_shim: catalog.run_shim.symbols }).unused
		$unused = $unused.keep_if(|name| here.contains(name))
	}
	if !$unused.is_empty() {
		warn!(LinkInputs.unused_message($unused.sort_with(LinkInputs.compare)))
	}
	shim_audit!(roc, catalog, catalog.run_shim.symbols)
}

## The run shims embedded in the compiler `roc`, carved out into
## `build/run-shims` and their imports (`nm -u` less `nm -gUj`) audited
## against what the catalog exports for the compiler's own architecture,
## which is the shims' (an Intel `roc`'s run mode links the `x64mac` host):
## `roc main.roc` links the host with one of them.
shim_audit! : Str, LinkInputs.Catalog, List(Str) => Try({}, Str)
shim_audit! = |roc, catalog, run_shim| {
	compiler = capture!("which", [roc])?.trim()
	version = capture!(compiler, ["version"])?.trim()
	bytes = Path.read_bytes!(Path.utf8(compiler)) ? |error| "could not read ${compiler}: ${Str.inspect(error)}"
	target = LinkInputs.macho_target(bytes) ? |_| "${compiler} is not a 64-bit Mach-O program for Apple silicon or Intel, so its run shims cannot be audited"
	owners = LinkInputs.exported(catalog, target)
	fresh!("build/run-shims")?
	var $names = []
	var $references = []
	for found in LinkInputs.embedded_archives(bytes) {
		match LinkInputs.run_shim_name(found.members) {
			Ok(name) => {
				path = "build/run-shims/lib${name}.a"
				Path.write_bytes!(Path.utf8(path), bytes.sublist({ start: found.start, len: found.len })) ? |error| "could not write ${path}: ${Str.inspect(error)}"
				undefined = capture!("nm", ["-u", path])?.split_on("\n")
				defined = capture!("nm", ["-gUj", path])?.split_on("\n")
				$names = $names.append(name)
				$references = $references.concat(LinkInputs.references(undefined, defined))
			}
			Err(NotAShim) => {}
		}
	}
	if $names.is_empty() {
		return Err("${compiler} (${version}) embeds no run shim that the audit can find; its run mode cannot be checked")
	}
	result = LinkInputs.shim_audit({ shim_refs: $references, owners, run_shim })
	if !result.stale.is_empty() {
		warn!(LinkInputs.shim_stale_message(version, result.stale))
	}
	if !result.missing.is_empty() {
		return Err(LinkInputs.shim_missing_message(version, result.missing))
	}
	if !result.unlisted.is_empty() {
		return Err(LinkInputs.shim_unlisted_message(version, result.unlisted))
	}
	note!("build: the run shims of ${version} (${Str.join_with($names, ", ")}) import only symbols the catalog exports for ${target}")
	Ok({})
}

## The linker inputs' fingerprint, as `link_inputs.roc fingerprint` prints it.
link_fingerprint! : () => Try(Str, Str)
link_fingerprint! = || {
	printed = capture!("roc-stable", ["scripts/link_inputs.roc", "--", "fingerprint"])?
	Ok(printed.trim())
}

## Regenerate the committed glue, or check that it is current.
glue! : Str, Bool => Try({}, Str)
glue! = |roc, check| {
	out = if (check) "build/glue" else "host"
	if check {
		fresh!(out)?
	}
	step!(Cmd.new(OsStr.from_str(roc)).args(["glue", "glue/SwiftGlue.roc", out, "platform/main.roc"].map(OsStr.from_str)).stdout(Null), "${roc} glue glue/SwiftGlue.roc ${out} platform/main.roc")?
	if !check {
		note!("build: wrote host/${Str.join_with(Build.glue_files, " and host/")}; review the diff, and the host with it")
		return Ok({})
	}
	var $stale = []
	for name in Build.glue_files {
		if Path.read_bytes!(Path.utf8("host/${name}")) ?? [] != Path.read_bytes!(Path.utf8("${out}/${name}")) ?? [1] {
			$stale = $stale.append("host/${name}")
		}
	}
	if $stale.is_empty() {
		note!("build: the committed glue is what ${roc} generates")
		Ok({})
	} else {
		Err("${Str.join_with($stale, " and ")} differ from what glue/SwiftGlue.roc generates with this roc: run `blueprint run build -- glue`, review the diff and change the host to match")
	}
}

## Regenerate the engine facades, `platform/{Engine,Layout,Wire,Worker}.roc`,
## from the engine package `platform/main.roc` names (`scripts/src/Facade.roc`),
## or check that the committed ones are current. The package is downloaded
## once into `build/engine-package`; `roc` verifies the same URL's hash
## whenever it builds the platform.
engine! : Bool => Try({}, Str)
engine! = |check| {
	url = Facade.package_url(read!("platform/main.roc")?) ? |_| "platform/main.roc names no `engine:` package"
	archive = url.split_on("/").last() ? |_| "${url} names no file"
	cache = "build/engine-package"
	source = "${cache}/${archive.drop_suffix(".tar.zst")}"
	if !(Path.exists!(Path.utf8("${source}/main.roc")) ?? Bool.False) {
		fresh!(source)?
		download = "${cache}/${archive}"
		step!(Cmd.new("curl").args(["-fsSL", "--retry", "3", "-o", download, url].map(OsStr.from_str)), "curl ${url}")?
		step!(Cmd.new("zstd").args(["-q", "-d", "-f", "-o", "${cache}/package.tar", download].map(OsStr.from_str)), "zstd -d ${download}")?
		step!(Cmd.new("tar").args(["-x", "-f", "${cache}/package.tar", "-C", source].map(OsStr.from_str)), "tar -x -C ${source}")?
	}
	var $stale = []
	for name in Facade.modules {
		text = Facade.source_of(name, read!("${source}/${name}.roc")?, url) ? |_| "${source}/${name}.roc has no `${name} := [].{` block"
		path = "platform/${name}.roc"
		if check {
			if (Path.read_utf8!(Path.utf8(path)) ?? "") != text {
				$stale = $stale.append(path)
			}
		} else {
			write!(path, text)?
		}
	}
	if !check {
		note!("build: wrote the engine facades in platform/ from ${url}")
		Ok({})
	} else if $stale.is_empty() {
		note!("build: the engine facades are what ${url} gives")
		Ok({})
	} else {
		Err("the engine package gives other facades than ${Str.join_with($stale, " and ")}: run `blueprint run build -- engine` and review the diff")
	}
}

## Every example, or the named ones.
examples! : Str, Try(List(Str), [All]) => Try({}, Str)
examples! = |roc, named| {
	names = match named {
		Ok(given) => given
		Err(All) => {
			var $found = []
			for name in list!("examples")? {
				if Path.exists!(Path.utf8("examples/${name}/${example_entry}")) ?? Bool.False {
					$found = $found.append(name)
				}
			}
			$found
		}
	}
	for name in names {
		example!(roc, name)?
	}
	Ok({})
}

## An example's entry, where `macos.roc` finds an app's.
example_entry : Str
example_entry = "src/main.roc"

## One example's binary and its `.app`.
example! : Str, Str => Try({}, Str)
example! = |roc, name| {
	dir = "examples/${name}"
	main = example_entry
	note!("building ${dir}")
	step!(Cmd.new(OsStr.from_str(roc)).args(["build", main, "--output=${name}"].map(OsStr.from_str)).cwd(Path.utf8(dir)), "${roc} build ${dir}/${main}")?
	bundle_dir = "${dir}/${name}.app"
	if Path.exists!(Path.utf8(bundle_dir)) ?? Bool.False {
		Path.delete_all!(Path.utf8(bundle_dir)) ? |error| "could not replace ${bundle_dir}: ${Str.inspect(error)}"
	}
	Path.create_all!(Path.utf8("${bundle_dir}/Contents/MacOS")) ? |error| "could not create ${bundle_dir}: ${Str.inspect(error)}"
	Path.copy!(Path.utf8("${dir}/${name}"), Path.utf8("${bundle_dir}/Contents/MacOS/${name}")) ? |error| "could not copy ${name} into ${bundle_dir}: ${Str.inspect(error)}"
	assets = "${dir}/assets"
	icon = (Path.is_dir!(Path.utf8(assets)) ?? Bool.False) and (Path.exists!(Path.utf8("${assets}/icon.icns")) ?? Bool.False)
	if Path.is_dir!(Path.utf8(assets)) ?? Bool.False {
		Path.create_all!(Path.utf8("${bundle_dir}/Contents/Resources")) ? |error| "could not create ${bundle_dir}/Contents/Resources: ${Str.inspect(error)}"
		Path.copy_dir!(Path.utf8(assets), Path.utf8("${bundle_dir}/Contents/Resources/assets")) ? |error| "could not copy ${assets}: ${Str.inspect(error)}"
		if icon {
			Path.copy!(Path.utf8("${assets}/icon.icns"), Path.utf8("${bundle_dir}/Contents/Resources/AppIcon.icns")) ? |error| "could not copy the icon: ${Str.inspect(error)}"
		}
	}
	write!("${bundle_dir}/Contents/Info.plist", Build.info_plist(name, icon))
}

## A directory's entry names, sorted.
list! : Str => Try(List(Str), Str)
list! = |dir| {
	entries = Path.list!(Path.utf8(dir)) ? |error| "could not list ${dir}: ${Str.inspect(error)}"
	Ok(entries.keep_oks(|path| Path.filename(path).map_ok(Path.display)).sort_with(Build.compare))
}

sha256! : Str => Try(Str, Str)
sha256! = |path| {
	printed = capture!("shasum", ["-a", "256", path])?
	printed.split_on(" ").first().map_err(|_| "shasum printed nothing for ${path}")
}

cwd! : () => Try(Str, Str)
cwd! = || Env.cwd!().map_ok(|path| path.display()).map_err(|error| "no working directory: ${Str.inspect(error)}")

env! : Str, Str => Str
env! = |name, default| {
	found = Env.var_str!(OsStr.from_str(name)) ?? ""
	if (found.is_empty()) default else found
}

capture! : Str, List(Str) => Try(Str, Str)
capture! = |program, args|
	Cmd.new(OsStr.from_str(program)).args(args.map(OsStr.from_str)).capture!().map_err(|error| "${program} ${Str.join_with(args, " ")} failed: ${Str.inspect(error)}")

read! : Str => Try(Str, Str)
read! = |path| Path.read_utf8!(Path.utf8(path)).map_err(|error| "could not read ${path}: ${Str.inspect(error)}")

## Write a file, creating its directory.
write! : Str, Str => Try({}, Str)
write! = |path, text| {
	parent = Str.join_with(path.split_on("/").drop_last(1), "/")
	Path.create_all!(Path.utf8(parent)) ? |error| "could not create ${parent}: ${Str.inspect(error)}"
	Path.write_utf8!(Path.utf8(path), text).map_err(|error| "could not write ${path}: ${Str.inspect(error)}")
}

## Remove a directory and everything in it, then create it empty.
fresh! : Str => Try({}, Str)
fresh! = |dir| {
	if Path.exists!(Path.utf8(dir)) ?? Bool.False {
		Path.delete_all!(Path.utf8(dir)) ? |error| "could not empty ${dir}: ${Str.inspect(error)}"
	}
	Path.create_all!(Path.utf8(dir)).map_err(|error| "could not create ${dir}: ${Str.inspect(error)}")
}

## Run a program with the terminal inherited; it must exit 0.
step! : Cmd.Command, Str => Try({}, Str)
step! = |command, shown| {
	note!("RUN ${shown}")
	output = command.inherit_stdio().run!() ? |error| "${shown} did not run: ${Str.inspect(error)}"
	match output.status {
		Exited(0) => Ok({})
		_ => Err("${shown} failed: ${Str.inspect(output.status)}")
	}
}

note! : Str => {}
note! = |line| Stdout.line!(line) ?? {}

warn! : Str => {}
warn! = |line| Stderr.line!(line) ?? {}
