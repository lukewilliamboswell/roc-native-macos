#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	roc: "nightly-2026-11-22-3350b1c",
}

import cli.OsStr
import cli.Stderr
import cli.Stdout
import src/Spec

## Print a spec's steps as the host performs them (`ROC_SPEC`), for a
## harness that drives a program without the `macos.roc` tool, such as the
## bench harnesses' timed sessions:
##
##     ROC_SPEC="$(roc-stable scripts/lower_spec.roc -- '(test "t" (steps (wait 300) (stats)))')" ./bench/rows/rows
##
## The argument is the spec's text, so a harness can write its sizes into
## it. A spec that does not parse is reported at its line and column.
main! : List(OsStr) => Try({}, _)
main! = |raw| {
	args = raw.map(OsStr.display).drop_if(|arg| arg == "--")
	match args {
		[text] =>
			match Spec.parse(text) {
				Ok(parsed) => Stdout.write!(Spec.lower(parsed))
				Err({ pos, message }) => {
					Stderr.line!("lower_spec: ${pos.line.to_str()}:${pos.column.to_str()}: ${message}")?
					Err(Exit(1))
				}
			}
		_ => {
			Stderr.line!("lower_spec: give the spec's text as the one argument")?
			Err(Exit(2))
		}
	}
}

expect Spec.parse("(test \"t\" (steps (wait 300) (stats)))").map_ok(Spec.lower) == Ok("roc-spec 1\n0\ttime\t0\n1\twait\t300\n2\tstats\n")
