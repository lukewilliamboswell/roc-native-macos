## Recorded cases: `<case>.script` holds the `ROC_SCRIPT` steps of a run and
## `<case>.expected` what the run prints. `macos.roc test` checks an app's
## cases with these rules, and the repository's scripts its examples' cases.
##
## `scripts/src/Recorded.roc` is a byte-identical copy of `cli/Recorded.roc`
## (a script cannot import a module outside its own directory), and `check`
## fails when the two differ. Change `cli/Recorded.roc`, then copy it.
Recorded := [].{

	## The case a file is the script of: `increment.script` is `increment`.
	case_name : Str -> Try(Str, [NotACase])
	case_name = |file|
		if file.ends_with(".script") {
			Ok(file.drop_suffix(".script"))
		} else {
			Err(NotACase)
		}

	## Whether a case printed what was recorded. Text must match exactly,
	## except measurements, which depend on the system's fonts: a dump's
	## `--- WxH` window line and any `NNNpt` value may each differ by up to
	## `Recorded.tolerance_pt` points.
	matches : Str, Str -> Bool
	matches = |expected, printed| {
		want = expected.split_on("\n")
		got = printed.split_on("\n")
		want.len() == got.len() and List.map2(want, got, |w, g| { w, g }).all(|{ w, g }| w == g or same_but_measures(w, g))
	}

	## How far a measurement may move between systems, in points.
	tolerance_pt : I64
	tolerance_pt = 4

	## A case's printed output with the absolute path `root` (where the case
	## ran) written `placeholder`, so a recorded case does not depend on
	## where it ran (a file's URL, for example). When the path was printed,
	## the window's size (a dump's `--- WxH` line) depends on it too, so that
	## line becomes `--- <size>`.
	portable : Str, Str, Str -> Str
	portable = |printed, root, placeholder|
		if root.is_empty() or !printed.contains(root) {
			printed
		} else {
			lines = Str.join_with(printed.split_on(root), placeholder)
				.split_on("\n")
				.map(|line| if (line.starts_with("--- ") and line.drop_prefix("--- ").contains("x")) "--- <size>" else line)
			Str.join_with(lines, "\n")
		}
}

## Two lines that differ only in their measurements, within the tolerance.
same_but_measures : Str, Str -> Bool
same_but_measures = |want, got| {
	w = measure_tokens(want)
	g = measure_tokens(got)
	w.len() == g.len()
		and List.map2(w, g, |a, b| { a, b }).all(
			|{ a, b }|
				match (a, b) {
					(Word(x), Word(y)) => x == y
					(Number(x), Number(y)) => (x - y).abs() <= Recorded.tolerance_pt
					_ => Bool.False
				},
		)
}

## A line split into words, with each measurement (the numbers of a `--- WxH`
## window line, and an `NNNpt` value) as a number.
measure_tokens : Str -> List([Word(Str), Number(I64)])
measure_tokens = |line| {
	if line.starts_with("--- ") {
		match line.drop_prefix("--- ").split_on("x") {
			[w, h] =>
				match (I64.from_str(w), I64.from_str(h)) {
					(Ok(a), Ok(b)) => return [Word("---"), Number(a), Number(b)]
					_ => {}
				}
			_ => {}
		}
	}
	line.split_on(" ").map(
		|word|
			match I64.from_str(word.drop_suffix("pt")) {
				Ok(n) if word.ends_with("pt") => Number(n)
				_ => Word(word)
			},
	)
}

expect (Recorded.case_name("increment.script"), Recorded.case_name("increment.expected")) == (Ok("increment"), Err(NotACase))

## The absolute path becomes the placeholder wherever it is printed.
expect Recorded.portable("URL: file:///home/ci/repo/tests/a.txt\n", "/home/ci/repo", "<repo>") == "URL: file://<repo>/tests/a.txt\n"

## Output that never printed the path keeps its window size.
expect Recorded.portable("--- 360x145\nui-label \"1\"\n", "/home/ci/repo", "<repo>") == "--- 360x145\nui-label \"1\"\n"

## Output that printed the path loses its window size, which depended on it.
expect Recorded.portable("--- 570x351\nURL: file:///Users/me/counter/a.txt\n", "/Users/me/counter", "<app>") == "--- <size>\nURL: file://<app>/a.txt\n"

## A window one point wider on another system still matches.
expect Recorded.matches("--- 406x493\nui-title \"Contacts\"\n", "--- 405x493\nui-title \"Contacts\"\n")

## A scroll area's height may move a little too.
expect Recorded.matches("ui-scroll [1 views, 226pt high]", "ui-scroll [1 views, 228pt high]")

## A bigger change in size, or any change in text, still fails.
expect {
	actual =
		\\size: ${Str.inspect(Recorded.matches("--- 406x493", "--- 360x493"))}
		\\text: ${Str.inspect(Recorded.matches("ui-label \"1 item left\"", "ui-label \"2 items left\""))}
		\\count: ${Str.inspect(Recorded.matches("ui-list [371 rows]", "ui-list [372 rows]"))}
	expected =
		\\size: False
		\\text: False
		\\count: False
	actual == expected
}
