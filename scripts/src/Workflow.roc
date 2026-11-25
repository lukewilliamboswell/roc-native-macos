import Release

## The pure decisions of the workflows' steps (scripts/workflow.roc): which
## release a run is for, which release is the latest, which files a release
## directory holds, and what a step writes for later steps to read.
Workflow := [].{

	## What `release.yml`'s validate job was given: the event, the version a
	## maintainer asked for, the default branch, the ref the run is on, and
	## whether the tag and the notes already exist.
	Request : { event : Str, requested : Str, default_branch : Str, ref_type : Str, ref_name : Str, tag_exists : Bool, notes_exist : Bool }

	## The version a run releases and whether it is a prerelease: the
	## requested version for a dispatch from the default branch with an unused
	## tag and written notes, and the dry-run version for a pull request.
	release_version : Request -> Try({ version : Str, prerelease : Bool }, Str)
	release_version = |r| {
		chosen = if r.event == "workflow_dispatch" {
			if r.ref_type != "branch" or r.ref_name != r.default_branch {
				return Err("release from ${r.default_branch} only, not ${r.ref_type} ${r.ref_name}")
			}
			if r.tag_exists {
				return Err("tag ${r.requested} already exists")
			}
			if !r.notes_exist {
				return Err("write docs/releases/${r.requested}.adoc first")
			}
			r.requested
		} else {
			"0.0.1-dryrun"
		}
		if !Workflow.semver(chosen) {
			return Err("version must be SemVer without a v prefix: ${chosen}")
		}
		Ok({ version: chosen, prerelease: chosen.contains("-") })
	}

	## `MAJOR.MINOR.PATCH`, numbers without leading zeros, and an optional
	## `-SUFFIX` of letters, digits, dots and hyphens.
	semver : Str -> Bool
	semver = |text| {
		(core, suffix) = match text.split_on("-") {
			[only] => (only, "")
			[first, .. as rest] => (first, Str.join_with(rest, "-"))
			[] => ("", "")
		}
		number = |part| {
			bytes = part.to_utf8()
			!bytes.is_empty() and bytes.all(|byte| byte >= '0' and byte <= '9') and (bytes.len() == 1 or !part.starts_with("0"))
		}
		suffix_ok = text.split_on("-").len() == 1 or (!suffix.is_empty() and suffix.to_utf8().all(|byte| (byte >= '0' and byte <= '9') or (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or byte == '.' or byte == '-'))
		match core.split_on(".") {
			[a, b, c] => number(a) and number(b) and number(c) and suffix_ok
			_ => Bool.False
		}
	}

	## The latest final release among tags: a bare version, the highest by
	## major, minor and patch, or empty when there is none. A prerelease, a
	## draft (not listed) and a `linker-inputs-*` release never are.
	latest_final : List(Str) -> Str
	latest_final = |tags| {
		finals = tags.map(Str.trim).keep_if(|tag| Workflow.semver(tag) and !tag.contains("-"))
		finals.fold("", |best, tag| if (best.is_empty() or Workflow.later(Workflow.numbers(tag), Workflow.numbers(best))) tag else best)
	}

	numbers : Str -> List(U64)
	numbers = |version| version.split_on(".").map(|part| U64.from_str(part) ?? 0)

	## Whether one list of version numbers comes after another.
	later : List(U64), List(U64) -> Bool
	later = |a, b|
		match (a, b) {
			([x, .. as xs], [y, .. as ys]) => if (x != y) x > y else Workflow.later(xs, ys)
			_ => Bool.False
		}

	## The platform bundle among a release's file names: the one `.tar.zst`
	## outside the tool and bootstrap archives.
	platform_bundle : List(Str) -> Try(Str, [NotOne(U64)])
	platform_bundle = |names| {
		found = names.keep_if(Release.is_platform_bundle)
		match found {
			[one] => Ok(one)
			_ => Err(NotOne(found.len()))
		}
	}

	tool_bundle : List(Str) -> Try(Str, [NotOne(U64)])
	tool_bundle = |names| {
		found = names.keep_if(Release.is_tool_bundle)
		match found {
			[one] => Ok(one)
			_ => Err(NotOne(found.len()))
		}
	}

	## What `nightly.yml` tests and whether it may touch the tracking issue:
	## only a run with neither input set reports on the latest pair.
	selection : { nightly_input : Str, release_input : Str, latest_nightly : Str, latest_release : Str } -> Try({ nightly : Str, release : Str, report : Bool }, Str)
	selection = |s| {
		release = if (s.release_input.is_empty()) s.latest_release else s.release_input
		if release.is_empty() {
			return Err("no final release has been published, so there is no release to test")
		}
		Ok({ nightly: if (s.nightly_input.is_empty()) s.latest_nightly else s.nightly_input, release, report: s.nightly_input.is_empty() and s.release_input.is_empty() })
	}

	## Step outputs, as `$GITHUB_OUTPUT` reads them.
	outputs : List((Str, Str)) -> Str
	outputs = |pairs| Str.join_with(pairs.map(|(name, value)| "${name}=${value}\n"), "")

	## The release's job summary: the platform URL, then the rendered notes.
	summary : Str, Str, Str, Str -> Str
	summary = |repository, version, bundle, notes| "Platform URL: `https://github.com/${repository}/releases/download/${version}/${bundle}`\n\n${notes}\n"
}

dispatch : Workflow.Request
dispatch = { event: "workflow_dispatch", requested: "0.2.0", default_branch: "main", ref_type: "branch", ref_name: "main", tag_exists: Bool.False, notes_exist: Bool.True }

expect Workflow.release_version(dispatch) == Ok({ version: "0.2.0", prerelease: Bool.False })
expect Workflow.release_version({ ..dispatch, requested: "0.2.0-rc1" }) == Ok({ version: "0.2.0-rc1", prerelease: Bool.True })
expect Workflow.release_version({ ..dispatch, ref_name: "topic" }) == Err("release from main only, not branch topic")
expect Workflow.release_version({ ..dispatch, tag_exists: Bool.True }) == Err("tag 0.2.0 already exists")
expect Workflow.release_version({ ..dispatch, notes_exist: Bool.False }) == Err("write docs/releases/0.2.0.adoc first")
expect Workflow.release_version({ ..dispatch, requested: "v0.2.0" }) == Err("version must be SemVer without a v prefix: v0.2.0")
expect Workflow.release_version({ ..dispatch, event: "pull_request", ref_name: "topic" }) == Ok({ version: "0.0.1-dryrun", prerelease: Bool.True })
expect Workflow.semver("1.10.0") and !Workflow.semver("01.0.0") and !Workflow.semver("1.0") and !Workflow.semver("1.0.0-") and Workflow.semver("0.1.0-rc.1")

expect Workflow.latest_final(["0.2.0", "0.10.0", "0.11.0-rc1", "linker-inputs-sha256-ab", "0.9.3", ""]) == "0.10.0"
expect Workflow.latest_final(["linker-inputs-sha256-ab"]) == ""

expect Workflow.platform_bundle(["init-macos-I.tar.zst", "macos-T.tar.zst", "B.tar.zst", "B.tar.zst.cdx.json", "x.zip"]) == Ok("B.tar.zst")
expect Workflow.platform_bundle(["macos-T.tar.zst"]) == Err(NotOne(0))
expect Workflow.tool_bundle(["macos-T.tar.zst", "B.tar.zst"]) == Ok("macos-T.tar.zst")

expect Workflow.selection({ nightly_input: "", release_input: "", latest_nightly: "n", latest_release: "0.1.0" }) == Ok({ nightly: "n", release: "0.1.0", report: Bool.True })
expect Workflow.selection({ nightly_input: "m", release_input: "", latest_nightly: "n", latest_release: "0.1.0" }) == Ok({ nightly: "m", release: "0.1.0", report: Bool.False })
expect Workflow.selection({ nightly_input: "", release_input: "", latest_nightly: "n", latest_release: "" }).is_err()

expect Workflow.outputs([("tag", "0.1.0"), ("url", "")]) == "tag=0.1.0\nurl=\n"
expect Workflow.summary("o/r", "0.1.0", "B.tar.zst", "# notes") == "Platform URL: `https://github.com/o/r/releases/download/0.1.0/B.tar.zst`\n\n# notes\n"
