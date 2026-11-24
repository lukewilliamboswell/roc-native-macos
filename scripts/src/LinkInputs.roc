## The pure decisions of the platform's external linker inputs: the macOS
## TAPI stubs generated from the reviewed catalog `host/interfaces.json`
## alone (host/PROVENANCE.md). It checks the catalog, renders each library's
## stub, audits a host archive's references against the catalog, names the
## files that make up the release, and writes the release manifest and reads
## the lock `actions/publish-build-inputs` commits.
LinkInputs := [].{

	## A symbol, and the targets it is exported for when that is not every
	## catalog target: `only`, which a symbol of one architecture names. A
	## symbol without `only` is exported for every target.
	Symbol : { name : Str, evidence : Str, only : Try(List(Str), [Missing]) }

	Library : { name : Str, path : Str, install_name : Str, evidence : Str, symbols : List(Symbol) }

	## The system symbols Roc's own run-mode shims import (host/PROVENANCE.md,
	## "Roc's run-mode shims"): a second consumer of the stubs beside the host,
	## each symbol owned by a library like any other.
	RunShim : { evidence : Str, symbols : List(Str) }

	## `tapi_targets` names the TAPI targets every stub is for (`targets` is
	## a word Roc reserves).
	Catalog : { schema_version : U64, tapi_targets : List(Str), run_shim : RunShim, libraries : List(Library) }

	## The TAPI targets the stubs are for, one per Roc target the platform
	## declares: `arm64-macos` for `arm64mac` and `x86_64-macos` for
	## `x64mac`. Roc's linker takes the one `targets/macos-sysroot` for every
	## macOS target, so each stub lists both, and the linker reads the slice
	## of the architecture it links.
	tapi_targets : List(Str)
	tapi_targets = ["arm64-macos", "x86_64-macos"]

	## The manifest's and the lock's name for the one archive, which serves
	## every macOS target.
	asset_key : Str
	asset_key = "macos"

	## The release's file names: the archive and its manifest.
	archive_name : Str
	archive_name = "link-inputs-macos.tar"

	manifest_name : Str
	manifest_name = "build-input-release.json"

	## The lock `actions/publish-build-inputs` commits, at the repository root.
	lock_path : Str
	lock_path = "link-inputs.lock.json"

	## The archive's directory of stubs, which the bundle carries as
	## `targets/macos-sysroot`.
	sysroot_dir : Str
	sysroot_dir = "macos-sysroot"

	## Every file the archive's bytes depend on, in order: the catalog, the
	## provenance statement and licence it carries, and the producer's source.
	## With the tooling compiler, they are the release's input fingerprint.
	inputs : List(Str)
	inputs = ["LICENSE", "host/PROVENANCE.md", "host/interfaces.json", "scripts/link_inputs.roc", "scripts/src/LinkInputs.roc", "scripts/src/Tar.roc"]

	## The catalog, checked as the stub generator always checked it: the
	## targets, unique relative library paths, an absolute install name and
	## evidence for every library, and for every symbol a well-formed name,
	## its own evidence, one owner and, when it is not exported for every
	## target, some of them. The result maps each symbol to its library.
	check : Catalog -> Try(List((Str, Str)), Str)
	check = |catalog| {
		if catalog.schema_version != 3 or catalog.tapi_targets != LinkInputs.tapi_targets {
			return Err("expected schema_version 3 for ${Str.join_with(LinkInputs.tapi_targets, " and ")}")
		}
		var $paths = []
		var $owners = []
		for library in catalog.libraries {
			path = library.path
			if $paths.contains(path) or path.starts_with("/") or path.split_on("/").contains("..") {
				return Err("bad or repeated path ${path}")
			}
			$paths = $paths.append(path)
			if !library.install_name.starts_with("/") or library.evidence.is_empty() {
				return Err("${library.name} needs an absolute install name and evidence")
			}
			for symbol in library.symbols {
				if !LinkInputs.symbol_ok(symbol.name) {
					return Err("${Str.inspect(symbol.name)} is not a symbol name")
				}
				if symbol.evidence.is_empty() {
					return Err("${symbol.name} names no evidence")
				}
				match symbol.only {
					Ok(only) if only.is_empty() or only.len() >= LinkInputs.tapi_targets.len() or !only.all(|t| LinkInputs.tapi_targets.contains(t)) or LinkInputs.unique(only) != only =>
						return Err("${symbol.name} must name some, not all, of ${Str.join_with(LinkInputs.tapi_targets, " and ")} in `only`, each once")
					_ => {}
				}
				match $owners.find_first(|(owned, _)| owned == symbol.name) {
					Ok((_, owner)) => return Err("${symbol.name} is owned by both ${owner} and ${library.name}")
					Err(_) => {}
				}
				$owners = $owners.append((symbol.name, library.name))
			}
		}
		if catalog.run_shim.evidence.is_empty() {
			return Err("run_shim names no evidence")
		}
		var $shim = []
		for name in catalog.run_shim.symbols {
			if $shim.contains(name) {
				return Err("run_shim lists ${name} twice")
			}
			if !$owners.any(|(owned, _)| owned == name) {
				return Err("run_shim lists ${name}, which no library owns")
			}
			$shim = $shim.append(name)
		}
		Ok($owners)
	}

	## A symbol name: `[A-Za-z_$][A-Za-z0-9_$.]*`.
	symbol_ok : Str -> Bool
	symbol_ok = |name| {
		bytes = name.to_utf8()
		letter = |byte| (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or byte == '_' or byte == '$'
		match bytes {
			[first, .. as rest] => letter(first) and rest.all(|byte| letter(byte) or (byte >= '0' and byte <= '9') or byte == '.')
			[] => Bool.False
		}
	}

	## One library's TAPI v4 text stub: its targets, install name and sorted
	## symbols, nothing else. The symbols every target exports come first,
	## then those of one target alone, in the order of `tapi_targets`.
	tbd : Library -> Str
	tbd = |library| {
		head = ["--- !tapi-tbd", "tbd-version: 4", "targets: [ ${Str.join_with(LinkInputs.tapi_targets, ", ")} ]", "install-name: '${library.install_name}'"]
		everywhere = LinkInputs.export_group(LinkInputs.tapi_targets, library.symbols.keep_if(|symbol| symbol.only.is_err()))
		var $groups = everywhere
		for target in LinkInputs.tapi_targets {
			$groups = $groups.concat(LinkInputs.export_group([target], library.symbols.keep_if(|symbol| symbol.only == Ok([target]))))
		}
		exports = if ($groups.is_empty()) [] else ["exports:"].concat($groups)
		"${Str.join_with(head.concat(exports).append("..."), "\n")}\n"
	}

	## One `exports` entry of a stub: the targets and their sorted symbols,
	## or nothing for no symbols.
	export_group : List(Str), List(Symbol) -> List(Str)
	export_group = |group, symbols| {
		names = symbols.map(|symbol| symbol.name).sort_with(LinkInputs.compare)
		if (names.is_empty()) [] else ["  - targets: [ ${Str.join_with(group, ", ")} ]", "    symbols:"].concat(names.map(|name| "      - '${name}'"))
	}

	## Each symbol the catalog's libraries export for `target`, with its
	## library: what a host or run shim built for that target may reference.
	exported : Catalog, Str -> List((Str, Str))
	exported = |catalog, target| {
		var $found = []
		for library in catalog.libraries {
			for symbol in library.symbols {
				wanted = match symbol.only {
					Ok(only) => only.contains(target)
					Err(_) => Bool.True
				}
				if wanted {
					$found = $found.append((symbol.name, library.name))
				}
			}
		}
		$found
	}

	## The TAPI target of a thin 64-bit Mach-O file, from its header: the
	## CPU type after the magic `cf fa ed fe`, little-endian. A compiler's
	## run shims are for the architecture the compiler itself is built for.
	macho_target : List(U8) -> Try(Str, [NotMachO])
	macho_target = |bytes|
		match bytes.take_first(8) {
			[0xCF, 0xFA, 0xED, 0xFE, 0x0C, 0x00, 0x00, 0x01] => Ok("arm64-macos")
			[0xCF, 0xFA, 0xED, 0xFE, 0x07, 0x00, 0x00, 0x01] => Ok("x86_64-macos")
			_ => Err(NotMachO)
		}

	## The stubs, as archive paths under `macos-sysroot/` and their text.
	stubs : Catalog -> List({ path : Str, text : Str })
	stubs = |catalog| catalog.libraries.map(|library| { path: "${LinkInputs.sysroot_dir}/${library.path}", text: LinkInputs.tbd(library) })

	## What a host archive references that the catalog does not own, which
	## fails the build, and what the catalog owns that neither the archive
	## nor the run shims (`run_shim`) reference, which is only noted (the
	## linker and Roc-compiled code may need it). `undefined` and `defined`
	## are `nm -u` and `nm -gUj`: one member may reference another's
	## definition, and `_roc_engine_*` are the Roc application's own.
	audit : { undefined : List(Str), defined : List(Str), owners : List((Str, Str)), run_shim : List(Str) } -> { missing : List(Str), unused : List(Str) }
	audit = |{ undefined, defined, owners, run_shim }| {
		wanted = LinkInputs.references(undefined, defined)
		owned = owners.map(|(name, _)| name)
		missing = wanted.drop_if(|name| owned.contains(name) or LinkInputs.roc_provided(name)).sort_with(LinkInputs.compare)
		unused = owned.drop_if(|name| wanted.contains(name) or run_shim.contains(name)).sort_with(LinkInputs.compare)
		{ missing, unused }
	}

	## An archive's unresolved references: `nm -u` less `nm -gUj`, without
	## the member headers and blank lines.
	references : List(Str), List(Str) -> List(Str)
	references = |undefined, defined| {
		symbols = |lines| lines.map(Str.trim).keep_if(|line| !line.is_empty() and !line.ends_with(":"))
		local = symbols(defined)
		LinkInputs.unique(symbols(undefined).drop_if(|name| local.contains(name)))
	}

	## The run shims' system imports against the catalog. `shim_refs` is
	## what a compiler's shim archives reference (`LinkInputs.references` of
	## each); their `_roc_*` imports are for the host and the compiler's
	## generated objects to define. A system import the catalog does not own
	## is `missing`, and fails the build: the stubs cannot link that
	## compiler's run mode. One the catalog owns that `run_shim` does not
	## list is `unlisted`, and fails too, so the audit never calls it unused.
	## A `run_shim` name the shims do not import is `stale`, and only noted:
	## another supported compiler's shim may import it.
	shim_audit : { shim_refs : List(Str), owners : List((Str, Str)), run_shim : List(Str) } -> { missing : List(Str), unlisted : List(Str), stale : List(Str) }
	shim_audit = |{ shim_refs, owners, run_shim }| {
		wanted = LinkInputs.unique(shim_refs.drop_if(|name| name.starts_with("_roc_")))
		owned = owners.map(|(name, _)| name)
		missing = wanted.drop_if(|name| owned.contains(name)).sort_with(LinkInputs.compare)
		unlisted = wanted.drop_if(|name| run_shim.contains(name) or missing.contains(name)).sort_with(LinkInputs.compare)
		stale = run_shim.drop_if(|name| wanted.contains(name)).sort_with(LinkInputs.compare)
		{ missing, unlisted, stale }
	}

	## Each Unix `ar` archive embedded in `bytes`, with where it starts, how
	## long it is and its member names: a Roc compiler embeds its run shims
	## as archives and extracts one for every run. A BSD long name (`#1/N`) is read
	## from the member's data, and members are padded to an even offset from
	## the archive's start. An archive ends at the first bytes that are not
	## a member header.
	embedded_archives : List(U8) -> List({ start : U64, len : U64, members : List(Str) })
	embedded_archives = |bytes| {
		magic = Str.to_utf8("!<arch>\n")
		total = bytes.len()
		var $found = []
		var $index = 0
		while $index + 8 <= total {
			if bytes.get($index) == Ok('!') and bytes.sublist({ start: $index, len: 8 }) == magic {
				var $at = $index + 8
				var $members = []
				var $reading = Bool.True
				while $reading and $at + 60 <= total {
					header = bytes.sublist({ start: $at, len: 60 })
					ended = header.sublist({ start: 58, len: 2 }) == ['`', '\n']
					match LinkInputs.decimal(header.sublist({ start: 48, len: 10 })) {
						Ok(size) if ended and $at + 60 + size <= total => {
							raw = Str.from_utf8_lossy(header.sublist({ start: 0, len: 16 })).trim()
							long = if (raw.starts_with("#1/")) LinkInputs.decimal(raw.drop_prefix("#1/").to_utf8()) ?? 0 else 0
							name = if (long > 0) Str.from_utf8_lossy(bytes.sublist({ start: $at + 60, len: long }).drop_if(|byte| byte == 0)) else raw
							$members = $members.append(name)
							$at = $at + 60 + size
							if ($at - $index) % 2 == 1 {
								$at = $at + 1
							}
						}
						_ => {
							$reading = Bool.False
						}
					}
				}
				if !$members.is_empty() {
					$found = $found.append({ start: $index, len: $at - $index, members: $members })
				}
				$index = $at
			} else {
				$index = $index + 1
			}
		}
		$found
	}

	## The run shim an archive holds, named by its `roc_<kind>_shim_zcu.o`
	## member less `_zcu.o`.
	run_shim_name : List(Str) -> Try(Str, [NotAShim])
	run_shim_name = |members|
		match members.find_first(|name| name.starts_with("roc_") and name.ends_with("_shim_zcu.o")) {
			Ok(member) => Ok(member.drop_suffix("_zcu.o"))
			Err(_) => Err(NotAShim)
		}

	## A space-padded decimal field of an `ar` header.
	decimal : List(U8) -> Try(U64, [NotDecimal])
	decimal = |field| {
		digits = field.drop_if(|byte| byte == ' ')
		if digits.is_empty() or !digits.all(|byte| byte >= '0' and byte <= '9') {
			return Err(NotDecimal)
		}
		Ok(digits.fold(0, |total, byte| total * 10 + (byte - '0').to_u64()))
	}

	## The shim audit's failures and its note, as the build prints them.
	shim_missing_message : Str, List(Str) -> Str
	shim_missing_message = |compiler, missing| "the run shims of ${compiler} import system symbols the catalog does not own, so `roc main.roc` cannot link against the stubs; review and add them to host/interfaces.json, and to its run_shim:\n  ${Str.join_with(missing, "\n  ")}"

	shim_unlisted_message : Str, List(Str) -> Str
	shim_unlisted_message = |compiler, unlisted| "the run shims of ${compiler} import symbols the catalog owns but its run_shim does not list; add them to run_shim in host/interfaces.json: ${Str.join_with(unlisted, " ")}"

	shim_stale_message : Str, List(Str) -> Str
	shim_stale_message = |compiler, stale| "note: run_shim symbols the run shims of ${compiler} do not import (another supported compiler's may): ${Str.join_with(stale, " ")}"

	## `_roc_engine_` and one or more word characters: the entry points the
	## Roc application object provides at the final link.
	roc_provided : Str -> Bool
	roc_provided = |name|
		match name.drop_prefix("_roc_engine_").to_utf8() {
			[] => Bool.False
			rest if name.starts_with("_roc_engine_") => rest.all(|byte| (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or (byte >= '0' and byte <= '9') or byte == '_')
			_ => Bool.False
		}

	## The audit's failure, as the build prints it.
	missing_message : List(Str) -> Str
	missing_message = |missing| "the host references system symbols the catalog does not own; review and add them to host/interfaces.json:\n  ${Str.join_with(missing, "\n  ")}"

	unused_message : List(Str) -> Str
	unused_message = |unused| "note: catalog symbols the host archive does not reference (linker or Roc code may): ${Str.join_with(unused, " ")}"

	## The text the input fingerprint is the SHA-256 of: a version, the
	## tooling compiler that runs the producer, and each input's digest.
	fingerprint_text : Str, List({ path : Str, sha256 : Str }) -> Str
	fingerprint_text = |compiler, files| {
		lines = ["roc-native-macos link-inputs v1", "compiler ${compiler}"].concat(files.map(|file| "${file.sha256}  ${file.path}"))
		"${Str.join_with(lines, "\n")}\n"
	}

	## The tooling compiler Blueprint.roc names: `tooling = { compiler: "…" }`.
	tooling_compiler : Str -> Try(Str, [NoTooling])
	tooling_compiler = |blueprint|
		match blueprint.split_on("tooling = { compiler: \"") {
			[_, rest, ..] =>
				match rest.split_on("\"").first() {
					Ok(tag) if !tag.is_empty() => Ok(tag)
					_ => Err(NoTooling)
				}
			_ => Err(NoTooling)
		}

	## The release manifest `actions/publish-build-inputs` admits (schema 1,
	## kind `link-inputs`), as canonical JSON: keys sorted, no spaces.
	manifest : { repository : Str, sha : Str, ref : Str, workflow : Str, fingerprint : Str, sha256 : Str, size : U64 } -> Str
	manifest = |m| {
		q = LinkInputs.json_string
		asset = "{\"asset\":${q(LinkInputs.archive_name)},\"sha256\":${q(m.sha256)},\"size\":${m.size.to_str()}}"
		source = "{\"input_fingerprint\":${q(m.fingerprint)},\"ref\":${q(m.ref)},\"repository\":${q(m.repository)},\"sha\":${q(m.sha)},\"workflow\":${q(m.workflow)}}"
		"{\"assets\":{${q(LinkInputs.asset_key)}:${asset}},\"kind\":\"link-inputs\",\"schema_version\":1,\"source\":${source}}\n"
	}

	## What the build reads of a manifest or a lock.
	Asset : { asset : Str, sha256 : Str, size : U64 }

	Source : { input_fingerprint : Str }

	Targets : { macos : Asset }

	Manifest : { schema_version : U64, kind : Str, source : Source, assets : Targets }

	## A lock, less its `targets` (a word Roc reserves), which `lock_targets`
	## reads.
	Lock : { schema_version : U64, kind : Str, repository : Str, release : Str, source : Source }

	## Where a lock's archive is published.
	download_url : Lock, Asset -> Str
	download_url = |lock, asset| "https://github.com/${lock.repository}/releases/download/${lock.release}/${asset.asset}"

	## The text of the JSON object a top-level key of `text` holds, such as
	## a lock's `targets`, for `Json.parse` to read on its own.
	object_at : Str, Str -> Try(Str, [NoObject])
	object_at = |text, key| {
		after = match text.split_on("\"${key}\":") {
			[_, rest, ..] => rest.to_utf8()
			_ => return Err(NoObject)
		}
		start = after.find_first_index(|byte| byte == '{') ? |_| NoObject
		var $depth = 0
		var $in_string = Bool.False
		var $escaped = Bool.False
		var $index = start
		while $index < after.len() {
			byte = after.get($index) ?? 0
			if $in_string {
				if $escaped {
					$escaped = Bool.False
				} else if byte == '\\' {
					$escaped = Bool.True
				} else if byte == '"' {
					$in_string = Bool.False
				}
			} else if byte == '"' {
				$in_string = Bool.True
			} else if byte == '{' {
				$depth = $depth + 1
			} else if byte == '}' {
				$depth = $depth - 1
				if $depth == 0 {
					return Ok(Str.from_utf8_lossy(after.sublist({ start, len: $index + 1 - start })))
				}
			}
			$index = $index + 1
		}
		Err(NoObject)
	}

	## Whether a lock, or a manifest, describes the inputs of this checkout.
	current : Str, Str -> Try({}, [Stale(Str)])
	current = |recorded, fingerprint|
		if recorded == fingerprint {
			Ok({})
		} else {
			Err(Stale("its input fingerprint is ${recorded}, but this checkout's is ${fingerprint}"))
		}

	json_string : Str -> Str
	json_string = |text| {
		escaped = text.to_utf8().map(
			|byte|
				if byte == '"' {
					"\\\""
				} else if byte == '\\' {
					"\\\\"
				} else if byte == '\n' {
					"\\n"
				} else if byte < 32 {
					"\\u00${LinkInputs.hex(byte // 16)}${LinkInputs.hex(byte % 16)}"
				} else {
					Str.from_utf8_lossy([byte])
				},
		)
		"\"${Str.join_with(escaped, "")}\""
	}

	hex : U8 -> Str
	hex = |digit| Str.from_utf8_lossy([if (digit < 10) '0' + digit else 'a' + digit - 10])

	unique : List(Str) -> List(Str)
	unique = |names| names.fold([], |seen, name| if (seen.contains(name)) seen else seen.append(name))

	compare : Str, Str -> [Before, Same, After]
	compare = |a, b| LinkInputs.compare_bytes(a.to_utf8(), b.to_utf8())

	compare_bytes : List(U8), List(U8) -> [Before, Same, After]
	compare_bytes = |a, b|
		match (a, b) {
			([], []) => Same
			([], _) => Before
			(_, []) => After
			([x, .. as xs], [y, .. as ys]) => if (x < y) Before else if (x > y) After else LinkInputs.compare_bytes(xs, ys)
		}
}

lib : LinkInputs.Library
lib = { name: "libobjc", path: "usr/lib/libobjc.tbd", install_name: "/usr/lib/libobjc.A.dylib", evidence: "objc4", symbols: [{ name: "_objc_retain", evidence: "objc4", only: Err(Missing) }, { name: "_OBJC_CLASS_$_NSObject", evidence: "objc4", only: Err(Missing) }] }

stret : LinkInputs.Symbol
stret = { name: "_objc_msgSend_stret", evidence: "objc4", only: Ok(["x86_64-macos"]) }

catalog : LinkInputs.Catalog
catalog = { schema_version: 3, tapi_targets: ["arm64-macos", "x86_64-macos"], run_shim: { evidence: "roc", symbols: ["_objc_retain"] }, libraries: [lib] }

## The stub: both targets, sorted symbols, quoted.
expect
	LinkInputs.tbd(lib)
		== "--- !tapi-tbd\ntbd-version: 4\ntargets: [ arm64-macos, x86_64-macos ]\ninstall-name: '/usr/lib/libobjc.A.dylib'\nexports:\n  - targets: [ arm64-macos, x86_64-macos ]\n    symbols:\n      - '_OBJC_CLASS_$_NSObject'\n      - '_objc_retain'\n...\n"
expect LinkInputs.tbd({ ..lib, symbols: [] }) == "--- !tapi-tbd\ntbd-version: 4\ntargets: [ arm64-macos, x86_64-macos ]\ninstall-name: '/usr/lib/libobjc.A.dylib'\n...\n"

## A symbol of one architecture is exported for its target alone, after
## those of every target.
expect
	LinkInputs.tbd({ ..lib, symbols: lib.symbols.append(stret) })
		== "--- !tapi-tbd\ntbd-version: 4\ntargets: [ arm64-macos, x86_64-macos ]\ninstall-name: '/usr/lib/libobjc.A.dylib'\nexports:\n  - targets: [ arm64-macos, x86_64-macos ]\n    symbols:\n      - '_OBJC_CLASS_$_NSObject'\n      - '_objc_retain'\n  - targets: [ x86_64-macos ]\n    symbols:\n      - '_objc_msgSend_stret'\n...\n"
expect LinkInputs.tbd({ ..lib, symbols: [stret] }) == "--- !tapi-tbd\ntbd-version: 4\ntargets: [ arm64-macos, x86_64-macos ]\ninstall-name: '/usr/lib/libobjc.A.dylib'\nexports:\n  - targets: [ x86_64-macos ]\n    symbols:\n      - '_objc_msgSend_stret'\n...\n"

expect {
	both = { ..catalog, libraries: [{ ..lib, symbols: lib.symbols.append(stret) }] }
	LinkInputs.exported(both, "arm64-macos").len() == 2 and LinkInputs.exported(both, "x86_64-macos").contains(("_objc_msgSend_stret", "libobjc"))
}

expect LinkInputs.check(catalog) == Ok([("_objc_retain", "libobjc"), ("_OBJC_CLASS_$_NSObject", "libobjc")])
expect LinkInputs.check({ ..catalog, schema_version: 2 }).is_err()
expect LinkInputs.check({ ..catalog, tapi_targets: ["arm64-macos"] }).is_err()
expect LinkInputs.check({ ..catalog, libraries: [lib, { ..lib, path: "usr/lib/other.tbd", name: "other" }] }) == Err("_objc_retain is owned by both libobjc and other")
expect LinkInputs.check({ ..catalog, libraries: [{ ..lib, symbols: [{ name: "_x", evidence: "", only: Err(Missing) }] }] }) == Err("_x names no evidence")
expect LinkInputs.check({ ..catalog, libraries: [{ ..lib, symbols: lib.symbols.append(stret) }] }).is_ok()
expect LinkInputs.check({ ..catalog, libraries: [{ ..lib, symbols: [{ ..stret, only: Ok([]) }] }] }).is_err()
expect LinkInputs.check({ ..catalog, libraries: [{ ..lib, symbols: [{ ..stret, only: Ok(["arm64-macos", "x86_64-macos"]) }] }] }).is_err()
expect LinkInputs.check({ ..catalog, libraries: [{ ..lib, symbols: [{ ..stret, only: Ok(["i386-macos"]) }] }] }).is_err()

expect LinkInputs.macho_target([0xCF, 0xFA, 0xED, 0xFE, 0x07, 0x00, 0x00, 0x01, 3]) == Ok("x86_64-macos") and LinkInputs.macho_target([0xCF, 0xFA, 0xED, 0xFE, 0x0C, 0x00, 0x00, 0x01]) == Ok("arm64-macos") and LinkInputs.macho_target([0xCA, 0xFE]) == Err(NotMachO)
expect LinkInputs.check({ ..catalog, libraries: [{ ..lib, path: "../x.tbd" }] }) == Err("bad or repeated path ../x.tbd")
expect LinkInputs.check({ ..catalog, run_shim: { evidence: "roc", symbols: ["_mmap"] } }) == Err("run_shim lists _mmap, which no library owns")
expect LinkInputs.check({ ..catalog, run_shim: { evidence: "", symbols: [] } }) == Err("run_shim names no evidence")
expect LinkInputs.symbol_ok("_realpath$DARWIN_EXTSN") and LinkInputs.symbol_ok("dyld_stub_binder") and !LinkInputs.symbol_ok("9x") and !LinkInputs.symbol_ok("a b")

## A reference the catalog does not own fails; a defined one and a Roc
## entry point do not; an owned one never referenced is noted, unless the
## run shims import it.
expect
	LinkInputs.audit({ undefined: ["libhost.a(App.o):", "_objc_retain", "_new", "_local", "_roc_engine_init", ""], defined: ["_local"], owners: [("_objc_retain", "libobjc"), ("_free", "libSystem"), ("_mmap", "libSystem")], run_shim: ["_mmap"] })
		== { missing: ["_new"], unused: ["_free"] }

## A shim's import the catalog does not own fails, one it owns but run_shim
## omits fails, and a listed one no shim imports is stale; `_roc_*` are not
## system symbols.
expect
	LinkInputs.shim_audit({ shim_refs: ["_mmap", "_roc_alloc", "_roc_shim_hosted_fns", "_dlsym", "_free"], owners: [("_mmap", "libSystem"), ("_free", "libSystem"), ("_write", "libSystem")], run_shim: ["_mmap", "_write"] })
		== { missing: ["_dlsym"], unlisted: ["_free"], stale: ["_write"] }

## An embedded archive between other bytes: its members, a BSD long name,
## and padding to an even offset from the archive's start.
expect {
	member = |name, data| {
		size = data.len().to_str()
		Str.to_utf8(name).concat(List.repeat(' ', 48 - name.count_utf8_bytes())).concat(Str.to_utf8(size)).concat(List.repeat(' ', 10 - size.count_utf8_bytes())).concat(['`', '\n']).concat(data)
	}
	long = Str.to_utf8("roc_machine_code_shim_zcu.o").append(0)
	archive = Str.to_utf8("!<arch>\n").concat(member("a.o", [1, 2, 3])).append('\n').concat(member("#1/28", long.concat([9, 9])))
	found = LinkInputs.embedded_archives([7, 7, 7].concat(archive).concat([0, 0]))
	found == [{ start: 3, len: archive.len(), members: ["a.o", "roc_machine_code_shim_zcu.o"] }]
}
expect LinkInputs.run_shim_name(["a.o", "roc_machine_code_shim_zcu.o"]) == Ok("roc_machine_code_shim") and LinkInputs.run_shim_name(["compiler_rt.o"]) == Err(NotAShim)
expect LinkInputs.decimal(Str.to_utf8("104       ")) == Ok(104) and LinkInputs.decimal(Str.to_utf8("  ")) == Err(NotDecimal)
expect !LinkInputs.roc_provided("_roc_engine_") and LinkInputs.roc_provided("_roc_engine_drop") and !LinkInputs.roc_provided("_roc_engine_a.b")

expect LinkInputs.tooling_compiler("tooling = { compiler: \"nightly-2026-11-14-a87808d\" }\n") == Ok("nightly-2026-11-14-a87808d")
expect LinkInputs.fingerprint_text("n", [{ path: "a", sha256: "00" }]) == "roc-native-macos link-inputs v1\ncompiler n\n00  a\n"

expect
	LinkInputs.manifest({ repository: "o/r", sha: "s", ref: "refs/heads/b", workflow: "o/r/.github/workflows/link-inputs.yml", fingerprint: "f", sha256: "d", size: 3 })
		== "{\"assets\":{\"macos\":{\"asset\":\"link-inputs-macos.tar\",\"sha256\":\"d\",\"size\":3}},\"kind\":\"link-inputs\",\"schema_version\":1,\"source\":{\"input_fingerprint\":\"f\",\"ref\":\"refs/heads/b\",\"repository\":\"o/r\",\"sha\":\"s\",\"workflow\":\"o/r/.github/workflows/link-inputs.yml\"}}\n"
expect LinkInputs.object_at("{\n  \"kind\": \"x\",\n  \"targets\": {\n    \"macos\": {\"asset\": \"a}\"}\n  }\n}\n", "targets") == Ok("{\n    \"macos\": {\"asset\": \"a}\"}\n  }")
expect LinkInputs.object_at("{}", "targets") == Err(NoObject)
expect LinkInputs.json_string("a\"b\\c\n") == "\"a\\\"b\\\\c\\n\""
expect LinkInputs.current("a", "a") == Ok({}) and LinkInputs.current("a", "b").is_err()
