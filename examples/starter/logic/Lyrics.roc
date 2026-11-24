## A track's words: read from a `.lrc` file (timed lines) or a `.txt`
## file (plain text), and which of them is on screen at a playback
## position.
##
## Timing follows the simple LRC line tags. `[00:12.50]` is 12,500 ms from
## the start of the track; a line may carry several tags (`[00:05.00]
## [00:41.00]Chorus`), and is then a cue at each. Cues are ordered by start,
## and lines that start together are one cue, shown together. A tag with no
## words after it is an empty cue: the words clear until the next one.
## Metadata tags such as `[ar:Someone]` and `[offset:+120]` are skipped. A
## file whose timing is malformed (a tag that is not a time, words with no
## tag, a second of 75) is offered as plain text instead, without its tags,
## so the listener still has the words.
##
## Plain text keeps its verses: blank lines separate them, and each keeps
## its line breaks.
Lyrics := [].{

	## What a track has: no words, plain verses, or timed cues.
	Words : [NoWords, Plain(List(Verse)), Timed(List(Cue))]

	## A verse of plain text: its lines, in order.
	Verse : List(Str)

	## A timed group of lines: where it starts, in milliseconds from the start
	## of the track, and its lines, none for an empty cue.
	Cue : { start_ms : U64, lines : List(Str) }

	## The words a lyric file holds, by its name's extension: `.lrc` is timed
	## (or plain, if its timing is malformed), anything else plain text.
	from_file : Str, Str -> Words
	from_file = |name, text| if (name.with_ascii_lowercased().ends_with(".lrc")) Lyrics.from_lrc(text) else Lyrics.from_text(text)

	## The words of an LRC file.
	from_lrc : Str -> Words
	from_lrc = |text| {
		read = Lyrics.lines(text).map(Lyrics.read_line)
		if read.any(|line| line == Malformed) {
			Lyrics.from_text(Str.join_with(Lyrics.lines(text).map(Lyrics.untagged), "\n"))
		} else {
			placed = read.join_map(
				|line|
					match line {
						Placed({ starts, words }) => starts.map(|start_ms| { start_ms, words })
						_ => []
					},
			)
			if placed.is_empty() {
				Lyrics.from_text(Str.join_with(Lyrics.lines(text).map(Lyrics.untagged), "\n"))
			} else {
				Timed(Lyrics.grouped(placed))
			}
		}
	}

	## A text's lines, without a byte-order mark or carriage returns.
	lines : Str -> List(Str)
	lines = |text| text.drop_prefix("\u(feff)").split_on("\n").map(|line| line.drop_suffix("\r"))

	## One line of an LRC file: blank, a metadata tag, words at one or more
	## starts, or not LRC.
	read_line : Str -> [Blank, Meta, Placed({ starts : List(U64), words : Str }), Malformed]
	read_line = |raw| {
		trimmed = raw.trim()
		if trimmed.is_empty() {
			return Blank
		}
		var $rest = trimmed
		var $starts = []
		var $meta = Bool.False
		while $rest.starts_with("[") {
			match $rest.drop_prefix("[").split_first("]") {
				Ok({ before: tag, after }) => {
					match Lyrics.time(tag) {
						Ok(ms) => {
							$starts = $starts.append(ms)
						}
						Err(NotATime) =>
							if Lyrics.is_meta(tag) and $starts.is_empty() {
								$meta = Bool.True
							} else {
								return Malformed
							}
					}
					$rest = after.trim()
				}
				Err(_) => return Malformed
			}
		}
		if $meta {
			if ($starts.is_empty()) Meta else Malformed
		} else if $starts.is_empty() {
			Malformed
		} else {
			Placed({ starts: $starts, words: $rest })
		}
	}

	## A tag's time, `mm:ss`, `mm:ss.x`, `mm:ss.xx` or `mm:ss.xxx`, in
	## milliseconds: minutes of any length, seconds below 60.
	time : Str -> Try(U64, [NotATime])
	time = |tag|
		match tag.split_first(":") {
			Ok({ before: minutes, after: rest }) => {
				(seconds, fraction) =
					match rest.split_first(".") {
						Ok({ before, after }) => (before, after)
						Err(_) => (rest, "")
					}
				m = Lyrics.digits(minutes, 1, 4)?
				s = Lyrics.digits(seconds, 2, 2)?
				f = if (fraction.is_empty() and !rest.contains(".")) 0 else Lyrics.digits(fraction, 1, 3)?
				scaled =
					match fraction.count_utf8_bytes() {
						1 => f * 100
						2 => f * 10
						_ => f
					}
				if (s >= 60) Err(NotATime) else Ok((m * 60 + s) * 1000 + scaled)
			}
			Err(_) => Err(NotATime)
		}

	## A run of between `fewest` and `most` ASCII digits as a number.
	digits : Str, U64, U64 -> Try(U64, [NotATime])
	digits = |text, fewest, most| {
		bytes = text.to_utf8()
		if bytes.len() < fewest or bytes.len() > most or !bytes.all(|byte| byte >= '0' and byte <= '9') {
			Err(NotATime)
		} else {
			U64.from_str(text).map_err(|_| NotATime)
		}
	}

	## A metadata tag: a name of letters, a colon, then anything.
	is_meta : Str -> Bool
	is_meta = |tag|
		match tag.split_first(":") {
			Ok({ before: name, after: _ }) => !name.is_empty() and name.to_utf8().all(|byte| (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or byte == '#')
			Err(_) => Bool.False
		}

	## A line with its leading tags removed; a metadata line is blank.
	untagged : Str -> Str
	untagged = |raw|
		match Lyrics.read_line(raw) {
			Meta => ""
			_ => {
				var $rest = raw.trim()
				var $going = Bool.True
				while $going and $rest.starts_with("[") {
					match $rest.split_first("]") {
						Ok({ before: _, after }) => {
							$rest = after.trim()
						}
						Err(_) => {
							$going = Bool.False
						}
					}
				}
				$rest
			}
		}

	## Words placed at starts, as cues: ordered by start, keeping the file's
	## order among lines that start together, and grouped by start.
	grouped : List({ start_ms : U64, words : Str }) -> List(Cue)
	grouped = |placed|
		placed.map_with_index(|p, index| { p, index })
			.sort_with(
				|a, b|
					if a.p.start_ms < b.p.start_ms {
						Before
					} else if a.p.start_ms > b.p.start_ms {
						After
					} else if a.index < b.index {
						Before
					} else if a.index > b.index {
						After
					} else {
						Same
					},
			)
			.fold(
				[],
				|cues, { p, index: _ }| {
					spoken = if (p.words.is_empty()) [] else [p.words]
					match cues.last() {
						Ok(last) if last.start_ms == p.start_ms => cues.drop_last(1).append({ ..last, lines: last.lines.concat(spoken) })
						_ => cues.append({ start_ms: p.start_ms, lines: spoken })
					}
				},
			)

	## Plain text as verses: runs of lines between blank lines, each line
	## trimmed at its end.
	from_text : Str -> Words
	from_text = |text| {
		verses = Lyrics.lines(text)
			.map(|line| line.trim())
			.fold(
				{ done: [], verse: [] },
				|acc, line|
					if line.is_empty() {
						if (acc.verse.is_empty()) acc else { done: acc.done.append(acc.verse), verse: [] }
					} else {
						{ ..acc, verse: acc.verse.append(line) }
					},
			)
		all = if (verses.verse.is_empty()) verses.done else verses.done.append(verses.verse)
		if (all.is_empty()) NoWords else Plain(all)
	}

	## What the overlay shows at a position: the current cue's lines (none
	## before the first cue and in an empty cue), and the next cue's.
	Shown : { now : List(Str), next : List(Str) }

	## The cue whose time has come at `position_ms`: the last one starting
	## at or before it, which stays current until the next one starts.
	current : List(Cue), U64 -> Try(Cue, [BeforeFirst])
	current = |cues, position_ms|
		cues.fold(Err(BeforeFirst), |found, cue| if (cue.start_ms <= position_ms) Ok(cue) else found)

	## The lines shown at `position_ms`, and the next lines to come.
	shown : List(Cue), U64 -> Shown
	shown = |cues, position_ms| {
		now = Lyrics.current(cues, position_ms).map_ok(|cue| cue.lines) ?? []
		next = (cues.find_first(|cue| cue.start_ms > position_ms) ?? { start_ms: 0, lines: [] }).lines
		{ now, next }
	}

	## The next time after `position_ms` at which the shown line changes: the
	## next cue's start. A timer set for it changes the line exactly, however
	## often the position is reported.
	next_boundary : List(Cue), U64 -> Try(U64, [NoMore])
	next_boundary = |cues, position_ms|
		cues.find_first(|cue| cue.start_ms > position_ms).map_ok(|cue| cue.start_ms).map_err(|_| NoMore)

	## Cues as LRC text that `from_lrc` reads back: each line of a cue tagged
	## with its start, and an empty cue as its tag alone.
	to_lrc : List(Cue) -> Str
	to_lrc = |cues|
		Str.join_with(
			cues.join_map(
				|cue| {
					tag = Lyrics.stamp(cue.start_ms)
					if (cue.lines.is_empty()) [tag] else cue.lines.map(|line| "${tag}${line}")
				},
			),
			"\n",
		)

	## A time as a tag, `[mm:ss.xxx]`.
	stamp : U64 -> Str
	stamp = |ms| {
		pad = |n, width| Str.repeat("0", width - n.to_str().count_utf8_bytes().min(width)).concat(n.to_str())
		"[${pad(ms // 60_000, 2)}:${pad((ms // 1000) % 60, 2)}.${pad(ms % 1000, 3)}]"
	}

	## Every line of the words, for reading them all: a timed file's lines in
	## order, a plain file's verses with a blank line between.
	all_lines : Words -> List(Str)
	all_lines = |words|
		match words {
			NoWords => []
			Timed(cues) => cues.join_map(|cue| cue.lines)
			Plain(verses) => verses.map_with_index(|verse, index| if (index == 0) verse else [""].concat(verse)).join()
		}
}

expect Lyrics.time("00:12.50") == Ok(12_500) and Lyrics.time("01:02") == Ok(62_000) and Lyrics.time("2:03.5") == Ok(123_500) and Lyrics.time("00:00.007") == Ok(7)
expect ["00:60.00", "00:7x.50", "xx:10", "00:5.00", "00:05.", "00:05.1234", ""].all(|tag| Lyrics.time(tag) == Err(NotATime))

## Repeated timestamps expand, cues are ordered, and lines that start
## together are one cue; an empty tag is an empty cue.
expect {
	text = "[ti:Clicks]\n[00:12.00]Second\n[00:05.00][00:30.00]First and last\r\n[00:12.00]also second\n\n[00:20.00]\n"
	Lyrics.from_lrc(text)
		== Timed([
			{ start_ms: 5_000, lines: ["First and last"] },
			{ start_ms: 12_000, lines: ["Second", "also second"] },
			{ start_ms: 20_000, lines: [] },
			{ start_ms: 30_000, lines: ["First and last"] },
		])
}

## Malformed timing falls back to the words as plain text.
expect Lyrics.from_lrc("[00:05.00]One\n[00:99.00]Two\n\nThree") == Plain([["One", "Two"], ["Three"]])
expect Lyrics.from_lrc("[00:05.00]One\nno tag here") == Plain([["One", "no tag here"]])
expect Lyrics.from_lrc("[ar:Someone]\nJust words") == Plain([["Just words"]])
expect Lyrics.from_lrc("[ar:Someone]\n") == NoWords and Lyrics.from_lrc("") == NoWords

## Plain text keeps its verses and their line breaks.
expect Lyrics.from_text("\u(feff)One\r\nTwo  \n\n\n  Three\nFour\n") == Plain([["One", "Two"], ["Three", "Four"]])
expect Lyrics.from_file("Song.LRC", "[00:01.00]Hi") == Timed([{ start_ms: 1_000, lines: ["Hi"] }]) and Lyrics.from_file("Song.txt", "[00:01.00]Hi") == Plain([["[00:01.00]Hi"]])

## Before the first cue nothing shows; a cue stays until the next; an empty
## cue clears; the next line previews.
expect {
	cues = [{ start_ms: 5_000, lines: ["First"] }, { start_ms: 12_000, lines: ["Second"] }, { start_ms: 20_000, lines: [] }]
	Lyrics.shown(cues, 0) == { now: [], next: ["First"] }
		and Lyrics.shown(cues, 7_000) == { now: ["First"], next: ["Second"] }
		and Lyrics.shown(cues, 12_000) == { now: ["Second"], next: [] }
		and Lyrics.shown(cues, 25_000) == { now: [], next: [] }
		and Lyrics.next_boundary(cues, 7_000) == Ok(12_000)
		and Lyrics.next_boundary(cues, 12_000) == Ok(20_000)
		and Lyrics.next_boundary(cues, 20_000) == Err(NoMore)
}

expect Lyrics.all_lines(Plain([["a", "b"], ["c"]])) == ["a", "b", "", "c"] and Lyrics.all_lines(Timed([{ start_ms: 0, lines: ["x", "y"] }, { start_ms: 1, lines: [] }])) == ["x", "y"]

## Cues written as LRC read back as the same cues.
expect {
	cues = [{ start_ms: 5_000, lines: ["One", "and one"] }, { start_ms: 61_250, lines: [] }, { start_ms: 754_007, lines: ["Last"] }]
	Lyrics.stamp(61_250) == "[01:01.250]" and Lyrics.from_lrc(Lyrics.to_lrc(cues)) == Timed(cues)
}

## The standard ID tags are skipped wherever they stand, a title with a
## colon in it included.
expect {
	text = "[ti:Polymorphic Defunctionalization: A Song]\n[ar:Luke Boswell]\n[al:Roc]\n[au:Luke]\n[by:Luke]\n[length:02:59]\n[offset:+120]\n[re:roc]\n[ve:1.0]\n[#:a comment]\n[00:04.20]The Roc on the kick\n[ar:late]\n[00:08.72]Three amps hum"
	Lyrics.from_lrc(text) == Timed([{ start_ms: 4_200, lines: ["The Roc on the kick"] }, { start_ms: 8_720, lines: ["Three amps hum"] }])
}
