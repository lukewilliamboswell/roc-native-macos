#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	roc: "nightly-2026-11-22-3350b1c",
}

import cli.OsStr
import cli.Path
import cli.Stdout
import src/Spec

## Convert legacy recorded cases to specs, once:
##
##     roc-stable scripts/convert_cases.roc -- APP_DIR...
##
## Each `APP_DIR/tests/<case>.script` and its `.expected` becomes
## `APP_DIR/specs/<case>.scm`: every step its spec step, each `dump` an
## `expect-dump` of the dump the case recorded, each `workers` an
## `expect-workers` of the counts it recorded, and each `key` a `press`
## that says whether the app heard it. `pool:N` becomes the setup's
## `(worker-pool N)`, and the final `quit` is dropped: a spec ends after its
## last step. Every spec written must parse. An app author with 0.0.1 cases
## can run it from a checkout on their app's directory.
main! : List(OsStr) => Try({}, _)
main! = |raw| {
	dirs = raw.map(OsStr.display).drop_if(|arg| arg == "--")
	for dir in dirs {
		names = (Path.list!(Path.utf8("${dir}/tests")) ?? [])
			.keep_oks(|path| Path.filename(path).map_ok(Path.display))
			.keep_if(|name| name.ends_with(".script"))
			.map(|name| name.drop_suffix(".script"))
		for name in names {
			steps = Path.read_utf8!(Path.utf8("${dir}/tests/${name}.script"))?.trim()
			printed = Path.read_utf8!(Path.utf8("${dir}/tests/${name}.expected")) ?? ""
			text = convert(name, steps, printed) ? |message| ConvertFailed("${dir}/tests/${name}.script: ${message}")
			Path.create_all!(Path.utf8("${dir}/specs"))?
			Path.write_utf8!(Path.utf8("${dir}/specs/${name}.scm"), text)?
			Stdout.line!("wrote ${dir}/specs/${name}.scm")?
		}
	}
	Ok({})
}

## What a case printed, in pieces: each dump, and each line a step printed.
Piece : [Dump(List(Str)), Printed(Str)]

## Split a case's output into its dumps and the lines its steps printed.
pieces : Str -> List(Piece)
pieces = |printed| {
	var $out = []
	var $dump = Err(None)
	for line in printed.split_on("\n") {
		if line.starts_with("--- ") {
			$out = flush($out, $dump)
			$dump = Ok([line])
		} else if ["workers: ", "key ", "save ", "sweep: ", "window ", "roc worker fault "].any(|p| line.starts_with(p)) {
			$out = flush($out, $dump).append(Printed(line))
			$dump = Err(None)
		} else {
			match $dump {
				Ok(lines) if !line.is_empty() => {
					$dump = Ok(lines.append(line))
				}
				_ => {}
			}
		}
	}
	flush($out, $dump)
}

flush : List(Piece), Try(List(Str), [None]) -> List(Piece)
flush = |out, dump|
	match dump {
		Ok(lines) => out.append(Dump(lines))
		Err(_) => out
	}

## The spec for a case's steps and what it printed.
convert : Str, Str, Str -> Try(Str, Str)
convert = |name, script, printed| {
	var $left = pieces(printed)
	var $setup = []
	var $steps = []
	for step in script.split_on(";") {
		(verb, arg) = match step.split_on(":") {
			[v] => (v, "")
			[v, .. as rest] => (v, Str.join_with(rest, ":"))
			[] => ("", "")
		}
		take = |want|
			match $left.find_first(want) {
				Ok(found) => Ok(found)
				Err(_) => Err("${step} has no output left to expect")
			}
		line = match verb {
			"click" => Ok("(click (button ${quote(arg)}))")
			"type" => Ok("(fill (text-field) ${quote(arg)})")
			"write" => Ok("(fill (text-area) ${quote(arg.replace_each("\\n", "\n"))})")
			"enter" => Ok("(submit (text-field))")
			"toggle" => Ok("(toggle (checkbox ${quote(arg)}))")
			"files" | "drop" => Ok("(${verb} ${Str.join_with(arg.split_on(",").map(quote), " ")})")
			"choose" => Ok("(choose ${quote(arg)})")
			"select" if arg.starts_with("#") => Ok("(select (list-row ${arg.drop_prefix("#")}))")
			"select" => Ok("(select (list-row ${quote(arg)}))")
			"hover" if arg.starts_with("#") => Ok("(hover (hover-target ${arg.drop_prefix("#")}))")
			"hover" => Ok("(hover (text ${quote(arg)}))")
			"move" => Ok("(move ${Str.join_with(arg.split_on(","), " ")})")
			"leave" => Ok("(leave)")
			"sweep" => Ok("(sweep ${Str.join_with(arg.split_on(","), " ")})")
			"scroll" => Ok("(scroll ${arg})")
			"phase" => Ok("(phase ${quote(arg)})")
			"stats" => Ok("(stats)")
			"window" => Ok("(window)")
			"wait" => Ok("(wait ${arg})")
			"reload" => Ok("(reload)")
			"quit" => Err(Skip)
			"pool" => {
				$setup = $setup.append("(worker-pool ${arg})")
				Err(Skip)
			}
			"key" => {
				found = take(
					|p| match p {
						Printed(l) => l.starts_with("key ${arg}")
						_ => Bool.False
					},
				)?
				$left = drop_piece($left, found)
				heard = match found {
					Printed(l) => l.ends_with("(heard)")
					_ => Bool.False
				}
				Ok("(press ${quote(arg)} :heard ${if (heard) "true" else "false"})")
			}
			"workers" => {
				found = take(
					|p| match p {
						Printed(l) => l.starts_with("workers: ")
						_ => Bool.False
					},
				)?
				$left = drop_piece($left, found)
				match found {
					Printed(l) => Ok("(expect-workers ${worker_counts(l)})")
					_ => return Err("workers printed no counts")
				}
			}
			"dump" => {
				found = take(
					|p| match p {
						Dump(_) => Bool.True
						_ => Bool.False
					},
				)?
				$left = drop_piece($left, found)
				match found {
					Dump(lines) => Ok("(expect-dump \"\"\"\n${Str.join_with(lines.map(|l| if (l.is_empty()) "\n" else "      ${l}\n"), "")}      \"\"\")")
					_ => return Err("dump printed nothing")
				}
			}
			_ => return Err("unknown step ${step}")
		}
		match line {
			Ok(text) => {
				$steps = $steps.append(text)
			}
			Err(_) => {}
		}
	}
	setup = if ($setup.is_empty()) "" else "  (setup\n${Str.join_with($setup.map(|s| "    ${s}"), "\n")})\n"
	text = "; Converted from tests/${name}.script by scripts/convert_cases.roc.\n(test ${quote(name)}\n${setup}  (steps\n${Str.join_with($steps.map(|s| "    ${s}"), "\n")}))\n"
	match Spec.parse(text) {
		Ok(_) => Ok(text)
		Err({ pos, message }) => Err("the spec it made does not parse at ${pos.line.to_str()}:${pos.column.to_str()}: ${message}\n${text}")
	}
}

## The pieces after `found`: a step's output is the first of its kind left,
## and whatever came before it was printed by nothing the spec expects.
drop_piece : List(Piece), Piece -> List(Piece)
drop_piece = |left, found| {
	var $out = []
	var $seen = Bool.False
	for p in left {
		if $seen {
			$out = $out.append(p)
		} else if p == found {
			$seen = Bool.True
		}
	}
	$out
}

## `workers: limit 2, 2 live, 0 running, …` as `:limit 2 :live 2 :running 0 …`.
worker_counts : Str -> Str
worker_counts = |line| {
	words = line.drop_prefix("workers: ").replace_each(";", ",").split_on(",").map(|w| w.trim())
	Str.join_with(
		words.keep_oks(
			|w|
				match w.split_on(" ") {
					["limit", n] => Ok(":limit ${n}")
					[n, "timed", "out"] => Ok(":timed-out ${n}")
					[n, field] => Ok(":${field} ${n}")
					_ => Err(NotACount)
				},
		),
		" ",
	)
}

quote : Str -> Str
quote = |s| "\"${s.replace_each("\\", "\\\\").replace_each("\"", "\\\"").replace_each("\n", "\\n").replace_each("\t", "\\t")}\""

expect worker_counts("workers: limit 2, 1 live, 0 running, 0 queued; 2 started, 0 answered, 0 lost, 1 stopped, 1 timed out, 1 dropped") == ":limit 2 :live 1 :running 0 :queued 0 :started 2 :answered 0 :lost 0 :stopped 1 :timed-out 1 :dropped 1"

expect
	convert("reset", "pool:1;click:+;key:cmd+n;dump;quit", "key cmd+n (heard)\n--- 360x237\nui-vstack [1 views]\n  ui-text \"0\"\n")
		== Ok("; Converted from tests/reset.script by scripts/convert_cases.roc.\n(test \"reset\"\n  (setup\n    (worker-pool 1))\n  (steps\n    (click (button \"+\"))\n    (press \"cmd+n\" :heard true)\n    (expect-dump \"\"\"\n      --- 360x237\n      ui-vstack [1 views]\n        ui-text \"0\"\n      \"\"\")))\n")
