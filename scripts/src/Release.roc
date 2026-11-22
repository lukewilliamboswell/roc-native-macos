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

	## The release notes, from `docs/releases/<version>.adoc`, as the
	## Markdown body of the GitHub release. The source opens with
	## `= roc-native-macos <version>` and writes the bundle's URL as
	## `{platform-url}`, which does not exist until the release builds the
	## bundle, and may write `{examples-url}` for the examples archive. Its
	## headings and `[source,LANG]` blocks become Markdown; other lines are
	## kept as written, so links are written in Markdown.
	render_notes : { source : Str, version : Str, platform_url : Str, examples_url : Str } -> Try(Str, [WrongTitle(Str), NoPlatformUrl, Unresolved(Str), UnclosedBlock])
	render_notes = |{ source, version, platform_url, examples_url }| {
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
			resolved = line.replace_each("{platform-url}", platform_url).replace_each("{examples-url}", examples_url)
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
expect Release.served_main("app [main] { pf: platform \"../../platform/main.roc\" }", "Abc.tar.zst", "http://localhost:1/Abc.tar.zst") == Err(NoReleaseUrl)

expect Release.render_notes({ source: "= roc-native-macos 0.0.1\n\nThe first release.\n\n== Use it\n\n[source,roc]\n----\napp [main] { pf: platform \"{platform-url}\" }\n----\n\nThe [examples]({examples-url}).\n", version: "0.0.1", platform_url: "https://u/B.tar.zst", examples_url: "https://u/e.zip" }) == Ok("# roc-native-macos 0.0.1\n\nThe first release.\n\n## Use it\n\n```roc\napp [main] { pf: platform \"https://u/B.tar.zst\" }\n```\n\nThe [examples](https://u/e.zip).\n")

expect Release.render_notes({ source: "= roc-native-macos 0.0.2\n{platform-url}\n", version: "0.0.1", platform_url: "u", examples_url: "e" }) == Err(WrongTitle("= roc-native-macos 0.0.1"))
expect Release.render_notes({ source: "= roc-native-macos 0.0.1\nno url\n", version: "0.0.1", platform_url: "u", examples_url: "e" }) == Err(NoPlatformUrl)
expect Release.render_notes({ source: "= roc-native-macos 0.0.1\n{platform-url} {manual-url}\n", version: "0.0.1", platform_url: "u", examples_url: "e" }) == Err(Unresolved("manual-url"))
expect Release.render_notes({ source: "= roc-native-macos 0.0.1\n{platform-url}\n----\nx\n", version: "0.0.1", platform_url: "u", examples_url: "e" }) == Err(UnclosedBlock)
