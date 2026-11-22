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
import src/Workflow

## The `workflow` task: the steps of the workflows that ask GitHub or hand
## values to later steps, so that each workflow step is one line. It reads
## the run's context from the environment the workflow sets, never from
## arguments, writes step outputs to `$GITHUB_OUTPUT`, and asks GitHub only
## through `gh`, which reads `GH_TOKEN`.
##
##     blueprint run workflow -- validate             # release.yml: the version, the nightly, the latest release
##     blueprint run workflow -- select               # nightly.yml: the nightly and the release to test
##     blueprint run workflow -- download TAG DIR     # nightly.yml: a release's bundle, macos.roc and examples
##     blueprint run workflow -- files VERSION DIR    # release.yml: the files a release directory holds
##     blueprint run workflow -- summary VERSION DIR NOTES   # release.yml: the platform URL and the notes
##
## `validate` reads EVENT, REQUESTED and DEFAULT_BRANCH with GitHub's own
## GITHUB_REF_TYPE, GITHUB_REF_NAME and GITHUB_REPOSITORY; `select` reads
## NIGHTLY and RELEASE, the dispatch inputs (empty for the latest).
main! : List(OsStr) => Try({}, _)
main! = |raw_args| {
	args = raw_args.map(OsStr.display).drop_if(|arg| arg == "--")
	result = match args {
		["validate"] => validate!()
		["select"] => select!()
		["download", tag, dir] => download!(tag, dir)
		["files", version, dir] => files!(version, dir)
		["summary", version, dir, notes] => summary!(version, dir, notes)
		_ => Err("usage: workflow validate | select | download TAG DIR | files VERSION DIR | summary VERSION DIR NOTES")
	}
	match result {
		Ok({}) => Ok({})
		Err(problem) => {
			Stderr.line!("::error::${problem}") ?? {}
			Err(Exit(1))
		}
	}
}

## The release a run is for: the version (checked against the branch, the
## tags and the notes), the nightly for the whole run, and the latest final
## release with its platform bundle's URL, which `release -- bump` compares.
validate! : () => Try({}, Str)
validate! = || {
	repository = env!("GITHUB_REPOSITORY")
	requested = env!("REQUESTED")
	tag_exists = if (requested.is_empty()) Bool.False else succeeds!("gh", ["api", "repos/${repository}/git/ref/tags/${requested}"])
	notes_exist = !requested.is_empty() and (Path.is_file!(Path.utf8("docs/releases/${requested}.adoc")) ?? Bool.False)
	chosen = Workflow.release_version({ event: env!("EVENT"), requested, default_branch: env!("DEFAULT_BRANCH"), ref_type: env!("GITHUB_REF_TYPE"), ref_name: env!("GITHUB_REF_NAME"), tag_exists, notes_exist })?
	latest = latest_release!(repository)?
	url = if latest.is_empty() {
		""
	} else {
		names = capture!("gh", ["release", "view", latest, "-R", repository, "--json", "assets", "--jq", ".assets[].name"])?.split_on("\n")
		bundle = Workflow.platform_bundle(names) ? |NotOne(count)| "release ${latest} holds ${count.to_str()} platform bundles, not one"
		"https://github.com/${repository}/releases/download/${latest}/${bundle}"
	}
	output!([("version", chosen.version), ("prerelease", if (chosen.prerelease) "true" else "false"), ("nightly-tag", latest_nightly!()?), ("latest-tag", latest), ("latest-url", url)])
}

## The nightly and the release `nightly.yml` tests, and whether it reports.
select! : () => Try({}, Str)
select! = || {
	nightly_input = env!("NIGHTLY")
	release_input = env!("RELEASE")
	latest_nightly = if (nightly_input.is_empty()) latest_nightly!()? else ""
	latest_release = if (release_input.is_empty()) latest_release!(env!("GITHUB_REPOSITORY"))? else ""
	chosen = Workflow.selection({ nightly_input, release_input, latest_nightly, latest_release })?
	Stdout.line!("Testing release ${chosen.release} on ${chosen.nightly} (reporting: ${if (chosen.report) "yes" else "no"})") ?? {}
	output!([("nightly-tag", chosen.nightly), ("release-tag", chosen.release), ("report", if (chosen.report) "true" else "false")])
}

## A published release's platform bundle, tool and examples archive.
download! : Str, Str => Try({}, Str)
download! = |tag, dir| {
	step!("gh", ["release", "download", tag, "-R", env!("GITHUB_REPOSITORY"), "-D", dir, "-p", "*.tar.zst", "-p", "macos.roc", "-p", "roc-native-macos-examples-${tag}.zip"])?
	Stdout.line!("downloaded ${tag} into ${dir}") ?? {}
	Ok({})
}

## The release directory's platform bundle and tool, once each, beside the
## examples archive and macos.roc.
files! : Str, Str => Try({}, Str)
files! = |version, dir| {
	names = list!(dir)?
	bundle = Workflow.platform_bundle(names) ? |NotOne(count)| "${dir} holds ${count.to_str()} platform bundles, not one"
	tool = Workflow.tool_bundle(names) ? |NotOne(count)| "${dir} holds ${count.to_str()} tool bundles, not one"
	for name in ["roc-native-macos-examples-${version}.zip", "macos.roc"] {
		if !names.contains(name) {
			return Err("${dir} holds no ${name}")
		}
	}
	output!([("file", "${dir}/${bundle}"), ("name", bundle), ("tool", "${dir}/${tool}"), ("tool-name", tool)])
}

## The platform URL and the rendered notes, for the run's summary.
summary! : Str, Str, Str => Try({}, Str)
summary! = |version, dir, notes| {
	bundle = Workflow.platform_bundle(list!(dir)?) ? |NotOne(count)| "${dir} holds ${count.to_str()} platform bundles, not one"
	text = Path.read_utf8!(Path.utf8(notes)) ? |error| "could not read ${notes}: ${Str.inspect(error)}"
	append!("GITHUB_STEP_SUMMARY", Workflow.summary(env!("GITHUB_REPOSITORY"), version, bundle, text))
}

latest_nightly! : () => Try(Str, Str)
latest_nightly! = || Ok(capture!("gh", ["api", "repos/roc-lang/nightlies/releases/latest", "--jq", ".tag_name"])?.trim())

latest_release! : Str => Try(Str, Str)
latest_release! = |repository| {
	tags = capture!("gh", ["api", "repos/${repository}/releases", "--paginate", "--jq", ".[] | select(.draft == false and .prerelease == false) | .tag_name"])?
	Ok(Workflow.latest_final(tags.split_on("\n")))
}

output! : List((Str, Str)) => Try({}, Str)
output! = |pairs| {
	Stdout.line!(Workflow.outputs(pairs).trim()) ?? {}
	append!("GITHUB_OUTPUT", Workflow.outputs(pairs))
}

## Append to the file a GitHub environment variable names.
append! : Str, Str => Try({}, Str)
append! = |variable, text| {
	path = env!(variable)
	if path.is_empty() {
		return Err("${variable} is not set: run this in a workflow")
	}
	before = Path.read_utf8!(Path.utf8(path)) ?? ""
	Path.write_utf8!(Path.utf8(path), "${before}${text}").map_err(|error| "could not write ${variable}: ${Str.inspect(error)}")
}

list! : Str => Try(List(Str), Str)
list! = |dir| {
	entries = Path.list!(Path.utf8(dir)) ? |error| "could not list ${dir}: ${Str.inspect(error)}"
	Ok(entries.keep_oks(|path| Path.filename(path).map_ok(Path.display)))
}

env! : Str => Str
env! = |name| Env.var_str!(OsStr.from_str(name)) ?? ""

succeeds! : Str, List(Str) => Bool
succeeds! = |program, args|
	match Cmd.new(OsStr.from_str(program)).args(args.map(OsStr.from_str)).run!() {
		Ok(output) => output.status == Exited(0)
		Err(_) => Bool.False
	}

capture! : Str, List(Str) => Try(Str, Str)
capture! = |program, args|
	Cmd.new(OsStr.from_str(program)).args(args.map(OsStr.from_str)).capture!().map_err(|error| "${program} ${Str.join_with(args, " ")} failed: ${Str.inspect(error)}")

step! : Str, List(Str) => Try({}, Str)
step! = |program, args| {
	output = Cmd.new(OsStr.from_str(program)).args(args.map(OsStr.from_str)).inherit_stdio().run!() ? |error| "${program} did not run: ${Str.inspect(error)}"
	if (output.status == Exited(0)) Ok({}) else Err("${program} ${Str.join_with(args, " ")} failed: ${Str.inspect(output.status)}")
}
