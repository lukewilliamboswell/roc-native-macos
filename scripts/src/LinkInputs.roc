## The pure decisions of the platform's external linker inputs: the macOS
## TAPI stubs generated from the reviewed catalog `host/interfaces.json`
## alone (host/PROVENANCE.md). It checks the catalog, renders each library's
## stub, audits a host archive's references against the catalog, names the
## files that make up the release, and writes the release manifest and reads
## the lock `actions/publish-build-inputs` commits.
LinkInputs := [].{

	Symbol : { name : Str, evidence : Str }

	Library : { name : Str, path : Str, install_name : Str, evidence : Str, symbols : List(Symbol) }

	Catalog : { schema_version : U64, target : Str, libraries : List(Library) }

	## The one target the stubs are for, and the Roc target the archive serves.
	target : Str
	target = "arm64-macos"

	roc_target : Str
	roc_target = "arm64mac"

	## The release's file names: the archive and its manifest.
	archive_name : Str
	archive_name = "link-inputs-arm64mac.tar"

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

	## The catalog, checked as the stub generator always checked it: the one
	## target, unique relative library paths, an absolute install name and
	## evidence for every library, and for every symbol a well-formed name,
	## its own evidence and one owner. The result maps each symbol to its
	## library.
	check : Catalog -> Try(List((Str, Str)), Str)
	check = |catalog| {
		if catalog.schema_version != 2 or catalog.target != LinkInputs.target {
			return Err("expected schema_version 2 for ${LinkInputs.target}")
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
				match $owners.find_first(|(owned, _)| owned == symbol.name) {
					Ok((_, owner)) => return Err("${symbol.name} is owned by both ${owner} and ${library.name}")
					Err(_) => {}
				}
				$owners = $owners.append((symbol.name, library.name))
			}
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

	## One library's TAPI v4 text stub: its target, install name and sorted
	## symbols, nothing else.
	tbd : Library -> Str
	tbd = |library| {
		head = ["--- !tapi-tbd", "tbd-version: 4", "targets: [ ${LinkInputs.target} ]", "install-name: '${library.install_name}'"]
		symbols = library.symbols.map(|symbol| symbol.name).sort_with(LinkInputs.compare)
		exports = if (symbols.is_empty()) [] else ["exports:", "  - targets: [ ${LinkInputs.target} ]", "    symbols:"].concat(symbols.map(|symbol| "      - '${symbol}'"))
		"${Str.join_with(head.concat(exports).append("..."), "\n")}\n"
	}

	## The stubs, as archive paths under `macos-sysroot/` and their text.
	stubs : Catalog -> List({ path : Str, text : Str })
	stubs = |catalog| catalog.libraries.map(|library| { path: "${LinkInputs.sysroot_dir}/${library.path}", text: LinkInputs.tbd(library) })

	## What a host archive references that the catalog does not own, which
	## fails the build, and what the catalog owns that the archive does not
	## reference, which is only noted (the linker and Roc-compiled code may
	## need it). `undefined` and `defined` are `nm -u` and `nm -gUj`: one
	## member may reference another's definition, and `_roc_engine_*` are the
	## Roc application's own.
	audit : { undefined : List(Str), defined : List(Str), owners : List((Str, Str)) } -> { missing : List(Str), unused : List(Str) }
	audit = |{ undefined, defined, owners }| {
		symbols = |lines| lines.map(Str.trim).keep_if(|line| !line.is_empty() and !line.ends_with(":"))
		local = symbols(defined)
		wanted = LinkInputs.unique(symbols(undefined).drop_if(|name| local.contains(name)))
		owned = owners.map(|(name, _)| name)
		missing = wanted.drop_if(|name| owned.contains(name) or LinkInputs.roc_provided(name)).sort_with(LinkInputs.compare)
		unused = owned.drop_if(|name| wanted.contains(name)).sort_with(LinkInputs.compare)
		{ missing, unused }
	}

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
		"{\"assets\":{${q(LinkInputs.roc_target)}:${asset}},\"kind\":\"link-inputs\",\"schema_version\":1,\"source\":${source}}\n"
	}

	## What the build reads of a manifest or a lock.
	Asset : { asset : Str, sha256 : Str, size : U64 }

	Source : { input_fingerprint : Str }

	Targets : { arm64mac : Asset }

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
lib = { name: "libobjc", path: "usr/lib/libobjc.tbd", install_name: "/usr/lib/libobjc.A.dylib", evidence: "objc4", symbols: [{ name: "_objc_retain", evidence: "objc4" }, { name: "_OBJC_CLASS_$_NSObject", evidence: "objc4" }] }

catalog : LinkInputs.Catalog
catalog = { schema_version: 2, target: "arm64-macos", libraries: [lib] }

## The stub the Python generator wrote: sorted symbols, quoted.
expect
	LinkInputs.tbd(lib)
		== "--- !tapi-tbd\ntbd-version: 4\ntargets: [ arm64-macos ]\ninstall-name: '/usr/lib/libobjc.A.dylib'\nexports:\n  - targets: [ arm64-macos ]\n    symbols:\n      - '_OBJC_CLASS_$_NSObject'\n      - '_objc_retain'\n...\n"
expect LinkInputs.tbd({ ..lib, symbols: [] }) == "--- !tapi-tbd\ntbd-version: 4\ntargets: [ arm64-macos ]\ninstall-name: '/usr/lib/libobjc.A.dylib'\n...\n"

expect LinkInputs.check(catalog) == Ok([("_objc_retain", "libobjc"), ("_OBJC_CLASS_$_NSObject", "libobjc")])
expect LinkInputs.check({ ..catalog, schema_version: 1 }).is_err()
expect LinkInputs.check({ ..catalog, libraries: [lib, { ..lib, path: "usr/lib/other.tbd", name: "other" }] }) == Err("_objc_retain is owned by both libobjc and other")
expect LinkInputs.check({ ..catalog, libraries: [{ ..lib, symbols: [{ name: "_x", evidence: "" }] }] }) == Err("_x names no evidence")
expect LinkInputs.check({ ..catalog, libraries: [{ ..lib, path: "../x.tbd" }] }) == Err("bad or repeated path ../x.tbd")
expect LinkInputs.symbol_ok("_realpath$DARWIN_EXTSN") and LinkInputs.symbol_ok("dyld_stub_binder") and !LinkInputs.symbol_ok("9x") and !LinkInputs.symbol_ok("a b")

## A reference the catalog does not own fails; a defined one and a Roc
## entry point do not; an owned one never referenced is noted.
expect
	LinkInputs.audit({ undefined: ["libhost.a(App.o):", "_objc_retain", "_new", "_local", "_roc_engine_init", ""], defined: ["_local"], owners: [("_objc_retain", "libobjc"), ("_free", "libSystem")] })
		== { missing: ["_new"], unused: ["_free"] }
expect !LinkInputs.roc_provided("_roc_engine_") and LinkInputs.roc_provided("_roc_engine_drop") and !LinkInputs.roc_provided("_roc_engine_a.b")

expect LinkInputs.tooling_compiler("tooling = { compiler: \"nightly-2026-11-14-a87808d\" }\n") == Ok("nightly-2026-11-14-a87808d")
expect LinkInputs.fingerprint_text("n", [{ path: "a", sha256: "00" }]) == "roc-native-macos link-inputs v1\ncompiler n\n00  a\n"

expect
	LinkInputs.manifest({ repository: "o/r", sha: "s", ref: "refs/heads/b", workflow: "o/r/.github/workflows/link-inputs.yml", fingerprint: "f", sha256: "d", size: 3 })
		== "{\"assets\":{\"arm64mac\":{\"asset\":\"link-inputs-arm64mac.tar\",\"sha256\":\"d\",\"size\":3}},\"kind\":\"link-inputs\",\"schema_version\":1,\"source\":{\"input_fingerprint\":\"f\",\"ref\":\"refs/heads/b\",\"repository\":\"o/r\",\"sha\":\"s\",\"workflow\":\"o/r/.github/workflows/link-inputs.yml\"}}\n"
expect LinkInputs.object_at("{\n  \"kind\": \"x\",\n  \"targets\": {\n    \"arm64mac\": {\"asset\": \"a}\"}\n  }\n}\n", "targets") == Ok("{\n    \"arm64mac\": {\"asset\": \"a}\"}\n  }")
expect LinkInputs.object_at("{}", "targets") == Err(NoObject)
expect LinkInputs.json_string("a\"b\\c\n") == "\"a\\\"b\\\\c\\n\""
expect LinkInputs.current("a", "a") == Ok({}) and LinkInputs.current("a", "b").is_err()
