## The pure decisions of the release script: versions, release names and
## URLs, the examples archive's headers, and the release notes.
Release := [].{

	## The repository a release is published from, when `GITHUB_REPOSITORY`
	## does not say.
	repository : Str
	repository = "lukewilliamboswell/roc-native-macos"

	## The version a pull request's dry run builds under. Roc rejects 0.0.0
	## in a package URL.
	dry_run : Str
	dry_run = "0.0.1-dryrun"

	## A release version: `MAJOR.MINOR.PATCH`, optionally followed by a
	## prerelease suffix of letters, digits, `.` and `-` (`0.1.0-rc1`). No
	## `v` prefix, no leading zeros and no build metadata.
	version_ok : Str -> Bool
	version_ok = |version| {
		(core, suffix) = match version.split_on("-") {
			[only] => (only, Ok(""))
			[first, .. as rest] => (first, Err(Str.join_with(rest, "-")))
			[] => ("", Ok(""))
		}
		suffix_ok = match suffix {
			Ok(_) => Bool.True
			Err(text) => !text.is_empty() and text.to_utf8().all(|byte| Release.is_alnum(byte) or byte == '.' or byte == '-')
		}
		match core.split_on(".") {
			[major, minor, patch] => Release.number_ok(major) and Release.number_ok(minor) and Release.number_ok(patch) and suffix_ok
			_ => Bool.False
		}
	}

	## Whether a version is a prerelease, published as one and never as the
	## latest release.
	prerelease : Str -> Bool
	prerelease = |version| version.contains("-")

	number_ok : Str -> Bool
	number_ok = |text| {
		bytes = text.to_utf8()
		!bytes.is_empty() and bytes.all(|byte| byte >= '0' and byte <= '9') and (bytes.len() == 1 or !text.starts_with("0"))
	}

	is_alnum : U8 -> Bool
	is_alnum = |byte| (byte >= '0' and byte <= '9') or (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z')

	## The examples archive's name, without `.zip`; it is also the one
	## directory the archive holds.
	examples_name : Str -> Str
	examples_name = |version| "roc-native-macos-examples-${version}"

	## Where a release's assets are downloaded from.
	download_root : Str, Str -> Str
	download_root = |repo, version| "https://github.com/${repo}/releases/download/${version}"

	## An archived example's `main.roc` with its released platform URL, which
	## must end in the bundle's file name, replaced by `url`: the test serves
	## the same bytes from localhost for the duration of a run.
	served_main : Str, Str, Str -> Try(Str, [NoReleaseUrl])
	served_main = |source, bundle, url|
		match source.split_on("platform \"") {
			[before, after] =>
				match after.split_on("\"") {
					[released, .. as rest] if released.starts_with("https://") and released.ends_with("/${bundle}") =>
						Ok("${before}platform \"${url}\"${Str.join_with(rest, "\"")}")
					_ => Err(NoReleaseUrl)
				}
			_ => Err(NoReleaseUrl)
		}

	## The `macos.roc` tool's package bundle: `roc bundle`'s content-addressed
	## name, prefixed so it is never taken for the platform's bundle.
	tool_bundle : Str -> Str
	tool_bundle = |hashed| "macos-${hashed}"

	## Whether a file in a release directory is the tool's bundle.
	is_tool_bundle : Str -> Bool
	is_tool_bundle = |name| name.starts_with("macos-") and name.ends_with(".tar.zst")

	## The examples among tracked paths: each example's name and its app's
	## entry, `src/main.roc` (with a logic package beside `src/` in the
	## starter), in order.
	examples : List(Str) -> List({ name : Str, entry : Str })
	examples = |paths| {
		found = paths.keep_oks(
			|path|
				match path.split_on("/") {
					["examples", name, "src", "main.roc"] => Ok({ name, entry: "src/main.roc" })
					_ => Err(NotAnEntry)
				},
		)
		found.sort_with(|a, b| Release.compare_text(a.name, b.name))
	}

	## The templates `macos.roc init` writes, each an example of this
	## repository: the starter for `init`, the counter for `init --simple`.
	## A template's name names its file list in `Bundle.roc`, and `about`
	## is that list's doc comment.
	templates : List({ name : Str, example : Str, about : List(Str) })
	templates = [
		{ name: "starter", example: "examples/starter", about: ["The files `init` writes: the starter example (`examples/starter`),", "with its logic package, assets and tests."] },
		{ name: "simple", example: "examples/counter", about: ["The files `init --simple` writes: the counter example", "(`examples/counter`), with its specs."] },
	]

	## The templates' examples, whose tracked files are the scaffold.
	template_dirs : List(Str)
	template_dirs = Release.templates.map(|template| template.example)

	## The scaffold `macos.roc init` writes, from tracked paths of the
	## checkout: every file of each template's example, by its template, its
	## path in the new app and its path in the checkout, a template at a
	## time and each template's files in order. Other paths are ignored.
	scaffold : List(Str) -> List({ template : Str, path : Str, source : Str })
	scaffold = |tracked|
		Release.templates.fold(
			[],
			|found, { name, example, .. }| {
				prefix = "${example}/"
				files = tracked.keep_if(|source| source.starts_with(prefix)).map(|source| source.drop_prefix(prefix)).sort_with(Release.compare_text)
				found.concat(files.map(|path| { template: name, path, source: "${prefix}${path}" }))
			},
		)

	## Where a release stages a scaffold file beside its `Bundle.roc`.
	staged : { template : Str, path : Str, source : Str } -> Str
	staged = |file| "scaffold/${file.template}/${file.path}"

	## Whether a scaffold file is bytes, such as an image, rather than text.
	binary : Str -> Bool
	binary = |path| [".png", ".jpg", ".jpeg", ".pdf", ".icns", ".wav", ".mp3"].any(|ext| path.ends_with(ext))

	## The checked-in `cli/Bundle.roc`: the tool in a checkout, importing the
	## scaffold from the working tree.
	development_bundle : List(Str) -> Str
	development_bundle = |tracked|
		Release.bundle_module(
			{ version: "development", platform_url: "../platform/main.roc", roc_version: "development" },
			Release.scaffold(tracked).map(|file| { template: file.template, path: file.path, from: "../${file.source}" }),
		)

	## A release's `Bundle.roc`, importing the scaffold staged beside it
	## under `scaffold/<template>/`.
	release_bundle : { version : Str, platform_url : Str, roc_version : Str }, List(Str) -> Str
	release_bundle = |facts, tracked| Release.bundle_module(facts, Release.scaffold(tracked).map(|file| { template: file.template, path: file.path, from: Release.staged(file) }))

	## The tool's `Bundle.roc`, exactly as `roc fmt` writes it, with a file
	## list for each template. An image is imported as bytes, every other
	## file as text.
	bundle_module : { version : Str, platform_url : Str, roc_version : Str }, List({ template : Str, path : Str, from : Str }) -> Str
	bundle_module = |{ version, platform_url, roc_version }, files| {
		import_lines = files.map(|file| "import \"${file.from}\" as ${Release.alias(file.template, file.path)} : ${if (Release.binary(file.path)) "List(U8)" else "Str"}")
		lists = Release.templates.map(
			|{ name, about, .. }| {
				entries = files.keep_if(|file| file.template == name).map(|file| "\t\t{ path: \"${file.path}\", contents: ${if (Release.binary(file.path)) "Bytes" else "Text"}(${Release.alias(file.template, file.path)}) },")
				Str.join_with([""].concat(about.map(|line| "\t## ${line}")).concat(["\t${name} : List(File)", "\t${name} = ["]).concat(entries).concat(["\t]"]), "\n")
			},
		)
		header =
			\\# Generated by scripts/src/Release.roc: for each release, bundled beside
			\\# copies of the files it imports, and as cli/Bundle.roc for a checkout, where
			\\# it imports them from the working tree. `check` fails when cli/Bundle.roc
			\\# differs from what the script generates for a checkout.
		body =
			\\## What this copy of the tool ships with: the release it belongs to, that
			\\## release's platform, the Roc it was tested with, and the apps `init`
			\\## writes.
			\\Bundle := [].{
			\\
			\\	## A file `init` writes, by its path in the app: text, or bytes such
			\\	## as an image.
			\\	File : { path : Str, contents : [Text(Str), Bytes(List(U8))] }
			\\
			\\	## The roc-native-macos release this copy of the tool belongs to.
			\\	version : Str
			\\	version = "${version}"
			\\
			\\	## The release's platform bundle, which `init` names in the app's
			\\	## `src/main.roc`.
			\\	platform_url : Str
			\\	platform_url = "${platform_url}"
			\\
			\\	## The Roc the release was built and tested with.
			\\	roc_version : Str
			\\	roc_version = "${roc_version}"
		Str.join_with([header].concat(import_lines).concat(["", body]).concat(lists).concat(["}", ""]), "\n")
	}

	## A Roc name for a file of a template: the template's name and the
	## file's path, with `_` for anything but a letter or a digit.
	alias : Str, Str -> Str
	alias = |template, path| "${template}_${Str.from_utf8_lossy(path.to_utf8().map(|c| if ((c >= 'a' and c <= 'z') or (c >= '0' and c <= '9')) c else if (c >= 'A' and c <= 'Z') c + 32 else '_'))}"

	## The files `roc bundle` packs for the tool, relative to its stage: the
	## package root first, then its modules, the generated `Bundle.roc`, the
	## scaffold, a template at a time, and the notices.
	tool_files : List(Str), List(Str) -> List(Str)
	tool_files = |modules, tracked|
		["main.roc"]
			.concat(modules.drop_if(|name| name == "main.roc" or name == "Bundle.roc").sort_with(Release.compare_text))
			.concat(["Bundle.roc"])
			.concat(Release.scaffold(tracked).map(Release.staged))
			.concat(["LICENSE", "THIRD_PARTY_LICENSES.md"])

	## The platform a package's or an app's header names.
	platform_of : Str -> Try(Str, [NoPlatform])
	platform_of = |source|
		match source.split_on("platform \"") {
			[_, rest, ..] => rest.split_on("\"").first().map_err(|_| NoPlatform)
			_ => Err(NoPlatform)
		}

	## `macos.roc`, the app an author downloads to run the tool: it names
	## basic-cli and this release's tool package, and pins no compiler.
	launcher : { version : Str, basic_cli : Str, tool_url : Str } -> Str
	launcher = |{ version, basic_cli, tool_url }|
		\\# macos.roc, from roc-native-macos ${version}: create, build, run and test a
		\\# roc-native-macos app. Keep it in the app's directory and run it with Roc:
		\\#
		\\#     roc macos.roc init my-app    create an app in my-app/
		\\#     roc macos.roc run            build it and start it
		\\#     roc macos.roc dev            start it, reloading it as you save
		\\#     roc macos.roc build          build my-app.app, on any system
		\\#     roc macos.roc test           run its expect tests and specs, tests/specs/*.scm
		\\#     roc macos.roc fuzz           run its roc-fuzz targets, tests/fuzz/main.roc
		\\#
		\\# To move to another release, download that release's macos.roc over
		\\# this one and change the platform in src/main.roc to match.
		\\app [main!] {
		\\	cli: platform "${basic_cli}",
		\\	macos: "${tool_url}",
		\\}
		\\
		\\import macos.MacOS
		\\
		\\main! = |args| MacOS.run!(args)
		\\

	## A released `macos.roc` with its tool URL, which must end in the tool
	## bundle's file name, replaced by `url`, as `served_main` does for an
	## app's platform.
	served_launcher : Str, Str, Str -> Try(Str, [NoReleaseUrl])
	served_launcher = |source, tool, url|
		match source.split_on("macos: \"") {
			[before, after] =>
				match after.split_on("\"") {
					[released, .. as rest] if released.starts_with("https://") and released.ends_with("/${tool}") =>
						Ok("${before}macos: \"${url}\"${Str.join_with(rest, "\"")}")
					_ => Err(NoReleaseUrl)
				}
			_ => Err(NoReleaseUrl)
		}

	## The highest release version among the notes files in `docs/releases/`
	## (`0.0.1.adoc`): the notes a dry run renders.
	highest : List(Str) -> Try(Str, [NoNotes])
	highest = |files| {
		versions = files.keep_if(|name| name.ends_with(".adoc")).map(|name| name.drop_suffix(".adoc")).keep_if(Release.version_ok)
		match versions.sort_with(Release.compare_versions).last() {
			Ok(found) => Ok(found)
			Err(_) => Err(NoNotes)
		}
	}

	## Release versions in order: by major, minor and patch, and a final
	## release after its prereleases, which order by their suffixes.
	compare_versions : Str, Str -> [Before, Same, After]
	compare_versions = |a, b| {
		key = |version| {
			(core, suffix) = match version.split_on("-") {
				[only] => (only, "")
				[first, .. as rest] => (first, Str.join_with(rest, "-"))
				[] => ("", "")
			}
			numbers = core.split_on(".").map(|part| U64.from_str(part) ?? 0)
			(numbers, suffix)
		}
		(an, asuf) = key(a)
		(bn, bsuf) = key(b)
		match Release.compare_numbers(an, bn) {
			Same =>
				if asuf == bsuf {
					Same
				} else if asuf.is_empty() {
					After
				} else if bsuf.is_empty() {
					Before
				} else {
					Release.compare_text(asuf, bsuf)
				}
			other => other
		}
	}

	compare_numbers : List(U64), List(U64) -> [Before, Same, After]
	compare_numbers = |a, b|
		match (a, b) {
			([], []) => Same
			([], _) => Before
			(_, []) => After
			([x, .. as xs], [y, .. as ys]) => if (x < y) Before else if (x > y) After else Release.compare_numbers(xs, ys)
		}

	compare_text : Str, Str -> [Before, Same, After]
	compare_text = |a, b| Release.compare_numbers(a.to_utf8().map(U8.to_u64), b.to_utf8().map(U8.to_u64))

	## What `roc bump --expect` must check before `version` is released,
	## given the latest final release (empty when there is none). A first
	## release has nothing to compare with. A version past the latest's
	## breaking boundary (the major; before 1.0 the minor; before 0.1 the
	## patch, as Cargo reads `0.0.z`) permits every
	## API change, as roc-automation's release utility accepts without a diff.
	## Otherwise the API comparison decides.
	bump_plan : Str, Str -> Try([FirstRelease, NewBoundary, Compare], [NotAfter])
	bump_plan = |version, latest|
		if latest.is_empty() {
			Ok(FirstRelease)
		} else if Release.compare_versions(version, latest) != After {
			Err(NotAfter)
		} else if Release.compare_numbers(Release.boundary(version), Release.boundary(latest)) == After {
			Ok(NewBoundary)
		} else {
			Ok(Compare)
		}

	## The breaking-change boundary of a version: `[major]`, `[0, minor]`
	## before 1.0, or `[0, 0, patch]` before 0.1, where every release may
	## break.
	boundary : Str -> List(U64)
	boundary = |version| {
		numbers = Release.number_part(version).split_on(".").map(|part| U64.from_str(part) ?? 0)
		match numbers {
			[0, 0, patch, ..] => [0, 0, patch]
			[0, minor, ..] => [0, minor]
			[major, ..] => [major]
			[] => []
		}
	}

	## A version without its prerelease suffix: `0.2.0-rc1` is `0.2.0`, the
	## number `roc bump --expect` takes.
	number_part : Str -> Str
	number_part = |version| version.split_on("-").first() ?? version

	## The release notes, from `docs/releases/<version>.adoc`, as the
	## Markdown body of the GitHub release. The source opens with
	## `= roc-native-macos <version>` and writes the bundle's URL as
	## `{platform-url}`, which does not exist until the release builds the
	## bundle, and may write `{examples-url}` for the examples archive and
	## `{launcher-url}` for `macos.roc`. Its
	## headings and `[source,LANG]` blocks become Markdown; other lines are
	## kept as written, so links are written in Markdown.
	render_notes : { source : Str, version : Str, platform_url : Str, examples_url : Str, launcher_url : Str } -> Try(Str, [WrongTitle(Str), NoPlatformUrl, Unresolved(Str), UnclosedBlock])
	render_notes = |{ source, version, platform_url, examples_url, launcher_url }| {
		title = "= roc-native-macos ${version}"
		lines = source.split_on("\n")
		if lines.first() != Ok(title) {
			return Err(WrongTitle(title))
		}
		if !source.contains("{platform-url}") {
			return Err(NoPlatformUrl)
		}
		var $out = []
		var $in_block = Bool.False
		var $pending = Err(NoLanguage)
		for line in lines {
			resolved = line.replace_each("{platform-url}", platform_url).replace_each("{examples-url}", examples_url).replace_each("{launcher-url}", launcher_url)
			if $in_block {
				if line == "----" {
					$out = $out.append("```")
					$in_block = Bool.False
				} else {
					$out = $out.append(resolved)
				}
			} else if line.starts_with("[source") {
				$pending = Ok(line.drop_prefix("[source").drop_prefix(",").drop_suffix("]"))
			} else if line == "----" {
				$out = $out.append("```${$pending ?? ""}")
				$in_block = Bool.True
				$pending = Err(NoLanguage)
			} else if line.starts_with("=== ") {
				$out = $out.append("### ${resolved.drop_prefix("=== ")}")
			} else if line.starts_with("== ") {
				$out = $out.append("## ${resolved.drop_prefix("== ")}")
			} else if line.starts_with("= ") {
				$out = $out.append("# ${resolved.drop_prefix("= ")}")
			} else {
				$out = $out.append(resolved)
			}
		}
		if $in_block {
			return Err(UnclosedBlock)
		}
		rendered = Str.join_with($out, "\n")
		match rendered.split_on("-url}") {
			[_] => Ok(rendered)
			[before, ..] => Err(Unresolved("${before.split_on("{").last() ?? ""}-url"))
			[] => Ok(rendered)
		}
	}
}

expect Release.version_ok("0.0.1")
expect Release.version_ok("0.1.0-rc1")
expect Release.version_ok(Release.dry_run)
expect !Release.version_ok("v0.0.1")
expect !Release.version_ok("0.01.0")
expect !Release.version_ok("0.1")
expect !Release.version_ok("0.1.0-")
expect !Release.version_ok("0.1.0+build")
expect Release.prerelease("0.1.0-rc1") and !Release.prerelease("0.0.1")

expect Release.highest(["0.0.1.adoc", "0.1.0-rc1.adoc", "0.1.0.adoc", "README.md"]) == Ok("0.1.0")
expect Release.highest(["0.0.1.adoc", "0.0.10.adoc", "0.0.9.adoc"]) == Ok("0.0.10")
expect Release.highest(["0.2.0-rc1.adoc", "0.2.0-rc2.adoc"]) == Ok("0.2.0-rc2")
expect Release.highest([]) == Err(NoNotes)

## The archived header names the release; the test serves it from localhost.
expect Release.served_main("app [main] { pf: platform \"https://github.com/o/r/releases/download/0.0.1/Abc.tar.zst\" }\n\nimport pf.Ui\n", "Abc.tar.zst", "http://localhost:8000/Abc.tar.zst") == Ok("app [main] { pf: platform \"http://localhost:8000/Abc.tar.zst\" }\n\nimport pf.Ui\n")

## A header that names another bundle, or a checkout path, is refused.
expect Release.served_main("app [main] { pf: platform \"https://x/Other.tar.zst\" }", "Abc.tar.zst", "http://localhost:1/Abc.tar.zst") == Err(NoReleaseUrl)
expect Release.served_main("app [main] { pf: platform \"../../../platform/main.roc\" }", "Abc.tar.zst", "http://localhost:1/Abc.tar.zst") == Err(NoReleaseUrl)

expect Release.render_notes({ source: "= roc-native-macos 0.0.1\n\nThe first release.\n\n== Use it\n\n[source,roc]\n----\napp [main] { pf: platform \"{platform-url}\" }\n----\n\nThe [examples]({examples-url}).\n", version: "0.0.1", platform_url: "https://u/B.tar.zst", examples_url: "https://u/e.zip", launcher_url: "https://u/macos.roc" }) == Ok("# roc-native-macos 0.0.1\n\nThe first release.\n\n## Use it\n\n```roc\napp [main] { pf: platform \"https://u/B.tar.zst\" }\n```\n\nThe [examples](https://u/e.zip).\n")

expect Release.render_notes({ source: "= roc-native-macos 0.0.2\n{platform-url}\n", version: "0.0.1", platform_url: "u", examples_url: "e", launcher_url: "l" }) == Err(WrongTitle("= roc-native-macos 0.0.1"))
expect Release.render_notes({ source: "= roc-native-macos 0.0.1\nno url\n", version: "0.0.1", platform_url: "u", examples_url: "e", launcher_url: "l" }) == Err(NoPlatformUrl)
expect Release.render_notes({ source: "= roc-native-macos 0.0.1\n{platform-url} {manual-url}\n", version: "0.0.1", platform_url: "u", examples_url: "e", launcher_url: "l" }) == Err(Unresolved("manual-url"))
expect Release.render_notes({ source: "= roc-native-macos 0.0.1\n{platform-url}\n----\nx\n", version: "0.0.1", platform_url: "u", examples_url: "e", launcher_url: "l" }) == Err(UnclosedBlock)

## The tool's bundle is told apart from the platform's by its prefix.
expect Release.tool_bundle("Abc.tar.zst") == "macos-Abc.tar.zst" and Release.is_tool_bundle("macos-Abc.tar.zst") and !Release.is_tool_bundle("Abc.tar.zst")

## An example's entry is its src/main.roc; a top-level main.roc, a logic
## package's or a fuzz target's main.roc is not one.
expect
	Release.examples(["examples/todos/src/main.roc", "examples/old/main.roc", "examples/starter/logic/main.roc", "examples/starter/src/main.roc", "examples/starter/tests/fuzz/main.roc", "examples/about/assets/icon.png"])
		== [{ name: "starter", entry: "src/main.roc" }, { name: "todos", entry: "src/main.roc" }]

## The scaffold is every file of each template's example, the starter's
## first, each in order; other paths are not in it.
expect
	Release.scaffold(["examples/counter/src/main.roc", "examples/starter/src/main.roc", "examples/starter/assets/icon.png", "examples/about/src/main.roc", "examples/counter/tests/specs/reset.scm", "examples/starter/tests/specs/presets.scm"])
		== [
			{ template: "starter", path: "assets/icon.png", source: "examples/starter/assets/icon.png" },
			{ template: "starter", path: "src/main.roc", source: "examples/starter/src/main.roc" },
			{ template: "starter", path: "tests/specs/presets.scm", source: "examples/starter/tests/specs/presets.scm" },
			{ template: "simple", path: "src/main.roc", source: "examples/counter/src/main.roc" },
			{ template: "simple", path: "tests/specs/reset.scm", source: "examples/counter/tests/specs/reset.scm" },
		]

## `init` writes the starter, `init --simple` the counter.
expect Release.template_dirs == ["examples/starter", "examples/counter"]

## A checkout's Bundle.roc imports the working tree; a release's, its
## copies. Each template has its own list, and an image is imported as
## bytes.
expect {
	dev = Release.development_bundle(["examples/starter/tests/specs/a.scm", "examples/starter/assets/icon.png", "examples/counter/src/main.roc"])
	rel = Release.release_bundle({ version: "0.0.1", platform_url: "https://u/B.tar.zst", roc_version: "r" }, ["examples/starter/src/main.roc", "examples/counter/src/main.roc"])
	dev.contains("import \"../examples/starter/tests/specs/a.scm\" as starter_tests_specs_a_scm : Str\n")
		and dev.contains("import \"../examples/starter/assets/icon.png\" as starter_assets_icon_png : List(U8)\n")
		and dev.contains("import \"../examples/counter/src/main.roc\" as simple_src_main_roc : Str\n")
		and dev.contains("\tstarter = [\n\t\t{ path: \"assets/icon.png\", contents: Bytes(starter_assets_icon_png) },\n")
		and dev.contains("\tsimple = [\n\t\t{ path: \"src/main.roc\", contents: Text(simple_src_main_roc) },\n\t]\n}\n")
		and dev.contains("\tversion = \"development\"\n")
		and rel.contains("import \"scaffold/starter/src/main.roc\" as starter_src_main_roc : Str\n")
		and rel.contains("import \"scaffold/simple/src/main.roc\" as simple_src_main_roc : Str\n")
		and rel.contains("\tplatform_url = \"https://u/B.tar.zst\"\n")
		and rel.contains("\t\t{ path: \"src/main.roc\", contents: Text(starter_src_main_roc) },\n")
}

expect Release.tool_files(["MacOS.roc", "main.roc", "Bundle.roc", "App.roc"], ["examples/counter/src/main.roc", "examples/starter/src/main.roc", "examples/starter/assets/icon.png"]) == ["main.roc", "App.roc", "MacOS.roc", "Bundle.roc", "scaffold/starter/assets/icon.png", "scaffold/starter/src/main.roc", "scaffold/simple/src/main.roc", "LICENSE", "THIRD_PARTY_LICENSES.md"]

expect Release.platform_of("package\n\t[MacOS]\n\t{\n\t\tcli: platform \"https://b/c.tar.zst\",\n\t}\n") == Ok("https://b/c.tar.zst")

## The launcher names the tool; the test serves it from localhost.
expect {
	launcher = Release.launcher({ version: "0.0.1", basic_cli: "https://b/c.tar.zst", tool_url: "https://g/0.0.1/macos-T.tar.zst" })
	served = Release.served_launcher(launcher, "macos-T.tar.zst", "http://localhost:1/macos-T.tar.zst")
	launcher.contains("\tmacos: \"https://g/0.0.1/macos-T.tar.zst\",\n")
		and served.map_ok(|text| text.contains("\tmacos: \"http://localhost:1/macos-T.tar.zst\",\n")) == Ok(Bool.True)
		and Release.served_launcher(launcher, "macos-U.tar.zst", "http://localhost:1/macos-U.tar.zst") == Err(NoReleaseUrl)
}

## A first release compares with nothing; a new breaking boundary needs no
## diff; within one, the API comparison decides; an older version is refused.
expect Release.bump_plan("0.1.0", "") == Ok(FirstRelease)
expect Release.bump_plan("0.2.0", "0.1.3") == Ok(NewBoundary)
expect Release.bump_plan("1.0.0-rc1", "0.9.0") == Ok(NewBoundary)
expect Release.bump_plan("0.1.4", "0.1.3") == Ok(Compare)
expect Release.bump_plan("0.0.2", "0.0.1") == Ok(NewBoundary)
expect Release.bump_plan("0.1.0", "0.0.9") == Ok(NewBoundary)
expect Release.bump_plan("1.3.0", "1.2.0") == Ok(Compare)
expect Release.bump_plan("0.1.3", "0.1.3") == Err(NotAfter)
expect Release.bump_plan("0.1.0", "0.2.0") == Err(NotAfter)
expect Release.number_part("0.2.0-rc1") == "0.2.0" and Release.number_part("0.2.0") == "0.2.0"
