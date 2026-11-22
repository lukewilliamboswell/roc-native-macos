#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	roc: "nightly-2026-11-14-a87808d",
}

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stderr
import cli.Stdout
import src/LinkInputs
import src/Tar

## The `link-inputs` task: the producer of the platform's external linker
## inputs, the macOS TAPI stubs generated from `host/interfaces.json` alone
## (host/PROVENANCE.md). It reads only the catalog, the provenance statement,
## the licence and its own source, and never an Apple SDK file.
##
##     blueprint run link-inputs -- build DIR [--workflow W]   # DIR/link-inputs-arm64mac.tar and its manifest
##     blueprint run link-inputs -- candidate DIR              # build twice, require identical bytes (link-inputs.yml)
##     blueprint run link-inputs -- stubs DIR                  # the stub tree alone, DIR/<library path>
##     blueprint run link-inputs -- fingerprint                # this checkout's input fingerprint
##
## `build` writes the archive (`Tar`: the licence, PROVENANCE.md, the catalog
## and `macos-sysroot/<library path>` for every library, dated 0, in that
## order) and `build-input-release.json`, the manifest
## `actions/publish-build-inputs` admits: the archive's SHA-256 and size,
## bound to the source repository, commit, branch and workflow (from the
## GITHUB_* environment, or git) and to the input fingerprint. The same
## checkout writes the same bytes, which `link-inputs.yml` checks by building
## twice. `scripts/build.roc` installs the archive a lock selects.
main! : List(OsStr) => Try({}, _)
main! = |raw_args| {
	args = raw_args.map(OsStr.display).drop_if(|arg| arg == "--")
	result = match args {
		["build", dir] => build!(dir, "")
		["build", dir, "--workflow", workflow] => build!(dir, workflow)
		["candidate", dir] => candidate!(dir)
		["stubs", dir] => stubs!(dir)
		["fingerprint"] => print!(fingerprint!())
		_ => Err("usage: link-inputs build DIR [--workflow W] | candidate DIR | stubs DIR | fingerprint")
	}
	match result {
		Ok({}) => Ok({})
		Err(problem) => {
			Stderr.line!("link-inputs: ${problem}") ?? {}
			Err(Exit(1))
		}
	}
}

## The catalog, read and checked.
catalog! : () => Try(LinkInputs.Catalog, Str)
catalog! = || {
	text = read!("host/interfaces.json")?
	parsed : Try(LinkInputs.Catalog, _)
	parsed = Json.parse(text)
	found = parsed ? |error| "host/interfaces.json is not a schema 2 catalog: ${Str.inspect(error)}"
	_ = LinkInputs.check(found) ? |problem| "host/interfaces.json: ${problem}"
	Ok(found)
}

## The archive's files, in order.
entries! : LinkInputs.Catalog => Try(List(Tar.Entry), Str)
entries! = |found| {
	license = bytes!("LICENSE")?
	provenance = bytes!("host/PROVENANCE.md")?
	interfaces = bytes!("host/interfaces.json")?
	stubs = LinkInputs.stubs(found).map(|stub| { path: stub.path, bytes: Str.to_utf8(stub.text) })
	Ok([{ path: "LICENSE", bytes: license }, { path: "PROVENANCE.md", bytes: provenance }, { path: "interfaces.json", bytes: interfaces }].concat(stubs))
}

build! : Str, Str => Try({}, Str)
build! = |dir, workflow_given| {
	found = catalog!()?
	archive = Tar.write(entries!(found)?) ? |BadPath(path)| "${path} cannot be an archive path"
	fresh!(dir)?
	archive_path = "${dir}/${LinkInputs.archive_name}"
	Path.write_bytes!(Path.utf8(archive_path), archive) ? |error| "could not write ${archive_path}: ${Str.inspect(error)}"
	repository = env!("GITHUB_REPOSITORY", "lukewilliamboswell/roc-native-macos")
	sha = if (env!("GITHUB_SHA", "").is_empty()) capture!("git", ["rev-parse", "HEAD"])?.trim() else env!("GITHUB_SHA", "")
	ref = if (env!("GITHUB_REF", "").is_empty()) "refs/heads/${capture!("git", ["rev-parse", "--abbrev-ref", "HEAD"])?.trim()}" else env!("GITHUB_REF", "")
	workflow = if (workflow_given.is_empty()) "${repository}/.github/workflows/link-inputs.yml" else workflow_given
	manifest = LinkInputs.manifest({ repository, sha, ref, workflow, fingerprint: fingerprint!()?, sha256: sha256!(archive_path)?, size: archive.len() })
	write!("${dir}/${LinkInputs.manifest_name}", manifest)?
	Stdout.line!("link-inputs: ${archive_path}, ${found.libraries.len().to_str()} stubs, ${archive.len().to_str()} bytes") ?? {}
	Ok({})
}

## The producer workflow's candidate: for a release candidate, the commit
## the publisher asked for (EXPECTED_SHA) is the one checked out; the
## archive and manifest are built twice, into DIR and DIR-again, and must be
## identical; the workflow is this repository's `link-inputs.yml`.
candidate! : Str => Try({}, Str)
candidate! = |dir| {
	expected = env!("EXPECTED_SHA", "")
	if env!("RELEASE_CANDIDATE", "false") == "true" and (expected.is_empty() or expected != env!("GITHUB_SHA", "")) {
		return Err("the publisher asked for ${expected}, but this run is at ${env!("GITHUB_SHA", "")}")
	}
	workflow = "${env!("GITHUB_REPOSITORY", "lukewilliamboswell/roc-native-macos")}/.github/workflows/link-inputs.yml"
	again = "${dir}-again"
	build!(dir, workflow)?
	build!(again, workflow)?
	for name in [LinkInputs.archive_name, LinkInputs.manifest_name] {
		if bytes!("${dir}/${name}")? != bytes!("${again}/${name}")? {
			return Err("two builds of ${name} differ")
		}
	}
	Stdout.line!(read!("${dir}/${LinkInputs.manifest_name}")?.trim()) ?? {}
	Ok({})
}

## The stub tree alone, as the bundle's `targets/macos-sysroot` holds it.
stubs! : Str => Try({}, Str)
stubs! = |dir| {
	found = catalog!()?
	fresh!(dir)?
	for stub in LinkInputs.stubs(found) {
		write!("${dir}/${stub.path.drop_prefix("${LinkInputs.sysroot_dir}/")}", stub.text)?
	}
	symbols = found.libraries.fold(0.U64, |total, library| total + library.symbols.len())
	Stdout.line!("wrote ${found.libraries.len().to_str()} interfaces (${symbols.to_str()} symbols) to ${dir}") ?? {}
	Ok({})
}

## The SHA-256 of the fingerprint text over every input and the tooling
## compiler.
fingerprint! : () => Try(Str, Str)
fingerprint! = || {
	compiler = LinkInputs.tooling_compiler(read!("Blueprint.roc")?) ? |_| "Blueprint.roc names no tooling compiler"
	var $files = []
	for path in LinkInputs.inputs {
		$files = $files.append({ path, sha256: sha256!(path)? })
	}
	text_path = "build/link-inputs-fingerprint.txt"
	write!(text_path, LinkInputs.fingerprint_text(compiler, $files))?
	sha256!(text_path)
}

print! : Try(Str, Str) => Try({}, Str)
print! = |found| {
	line = found?
	Stdout.line!(line) ?? {}
	Ok({})
}

sha256! : Str => Try(Str, Str)
sha256! = |path| {
	printed = capture!("shasum", ["-a", "256", path])?
	printed.split_on(" ").first().map_err(|_| "shasum printed nothing for ${path}")
}

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

bytes! : Str => Try(List(U8), Str)
bytes! = |path| Path.read_bytes!(Path.utf8(path)).map_err(|error| "could not read ${path}: ${Str.inspect(error)}")

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
