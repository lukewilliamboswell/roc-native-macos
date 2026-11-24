app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.7.0/HBigHQhVZWEF2EkLxpYK35u8P6UNsAmPYxpNFTxXK1Br.tar.zst",
	logic: "../logic/main.roc",
}

import fuzz.Fuzz
import logic.JsonValue
import logic.Lyrics
import logic.Preset
import logic.Queue

## Fuzz targets for the player's logic in `logic/`, built with roc-fuzz
## (https://github.com/lukewilliamboswell/roc-fuzz), a platform of its own:
## this is a development program, never part of the app, and it imports
## `logic` exactly as `src/main.roc` does.
##
## `roc macos.roc fuzz` builds it (`roc build --fuzz fuzz/main.roc`, into
## `.macos/fuzz`) and runs each target in turn for ten seconds;
## `roc macos.roc fuzz --check` runs only the declared examples, quickly, as
## CI does. A failure leaves a report and the failing input under
## `.roc-fuzz/`, which `.macos/fuzz --target=NAME replay INPUT` reproduces;
## roc-fuzz's manual covers `show`, `minimize` and keeping a failure as a
## regression example.
##
## To add a target: write a property as a function returning `Fuzz.keep`
## (or `Fuzz.reject` for an input outside it) that `crash`es when the
## property fails, wrap it in `Fuzz.target_with` with a unique `name`, and
## add it to `target` below. Good properties are round trips, invariants
## and "never crashes" checks of a parser: the files a listener drops and
## imports are anything at all.
target = Fuzz.suite([lrc_parse, lrc_round_trip, json_round_trip, preset_decode, preset_round_trip, queue_invariants])

# ------------------------------------------------------------------ lyrics

## Any text reads as words without crashing, and timed words are in order:
## each cue starts after the one before, holds no blank line, and is the
## one `Lyrics.current` finds at its start.
lrc_parse = Fuzz.target_with({
	name: "lrc-parse",
	generator: Fuzz.str,
	test: |text|
		match Lyrics.from_lrc(text) {
			Timed(cues) => {
				starts = cues.map(|cue| cue.start_ms)
				ordered = List.map2(starts.drop_last(1), starts.drop_first(1), |a, b| a < b).all(|ok| ok)
				clean = cues.all(|cue| cue.lines.all(|line| !line.trim().is_empty() and !line.contains("\n")))
				found = cues.all(|cue| Lyrics.current(cues, cue.start_ms) == Ok(cue))
				if (ordered and clean and found) Fuzz.keep else crash "the cues of ${Str.inspect(text)} are out of order, blank or not found"
			}
			Plain(verses) => if (verses.all(|verse| !verse.is_empty())) Fuzz.keep else crash "an empty verse from ${Str.inspect(text)}"
			NoWords => Fuzz.keep
		},
	show: Str.inspect,
	examples: [
		Fuzz.example({ name: "timed", revision: "1", make: || "[ti:Clicks]\n[ar:Luke Boswell]\n[al:Roc]\n[length:02:59]\n[offset:+120]\n[00:05.00]First\n[00:12.00][00:30.00]Second\n[00:20.00]\n" }),
		Fuzz.example({ name: "malformed", revision: "1", make: || "[00:05.00]One\n[00:99.00]Two" }),
	],
})

## A cue as roc-fuzz generates it: a gap after the cue before, and its lines.
GeneratedCue : { gap : U64, lines : List(Str) }

## Cues written as LRC read back as the same cues: starts made increasing
## from the gaps, and each line as a file can hold it (one line, trimmed,
## not starting with a tag, not blank).
lrc_round_trip = Fuzz.target_with({
	name: "lrc-round-trip",
	generator: Fuzz.list({ gap: Fuzz.u64_in(1, 90_000), lines: Fuzz.list(Fuzz.str, 3) }.Fuzz, 12),
	test: |generated| {
		cues = cues_from(generated)
		if cues.is_empty() {
			Fuzz.reject
		} else if Lyrics.from_lrc(Lyrics.to_lrc(cues)) == Timed(cues) {
			Fuzz.keep
		} else {
			crash "cues did not read back as written: ${Str.inspect(Lyrics.to_lrc(cues))}"
		}
	},
	show: Str.inspect,
	examples: [Fuzz.example({ name: "two-cues", revision: "1", make: || [{ gap: 5_000, lines: ["First"] }, { gap: 7_000, lines: [] }] })],
})

cues_from : List(GeneratedCue) -> List(Lyrics.Cue)
cues_from = |generated|
	generated.fold(
		{ at: 0.U64, cues: [] },
		|acc, g| {
			# Saved and mutated inputs bypass the generator's bounds.
			start = acc.at + g.gap.max(1).min(90_000)
			{ at: start, cues: acc.cues.append({ start_ms: start, lines: g.lines.map(one_line).drop_if(Str.is_empty) }) }
		},
	).cues

## A line as an LRC file can hold it.
one_line : Str -> Str
one_line = |text| {
	var $flat = text.replace_each("\r", " ").replace_each("\n", " ").trim()
	while $flat.starts_with("[") {
		$flat = $flat.drop_prefix("[").trim()
	}
	$flat
}

# ------------------------------------------------------------------ presets

## Any JSON value encodes to text that parses back to it.
json_round_trip = Fuzz.target_with({
	name: "json-round-trip",
	generator: Fuzz.str,
	test: |text|
		match JsonValue.parse(text) {
			Ok(value) => if (JsonValue.parse(JsonValue.encode(value)) == Ok(value)) Fuzz.keep else crash "${Str.inspect(text)} did not encode and parse back"
			Err(_) => Fuzz.keep
		},
	show: Str.inspect,
	examples: [
		Fuzz.example({ name: "object", revision: "1", make: || "{\"a\": [1, -2, \"\\u00e9\"], \"b\": {}}" }),
		Fuzz.example({ name: "deep", revision: "1", make: || Str.repeat("[", 40) }),
	],
})

## Any text a listener imports is refused with at least one field, or is a
## valid preset that saves and reads back unchanged.
preset_decode = Fuzz.target_with({
	name: "preset-decode",
	generator: Fuzz.str,
	test: |text|
		match Preset.decode(text) {
			Ok(preset) =>
				if Preset.problems(preset).is_empty() and Preset.decode(Preset.encode(preset)) == Ok(preset) {
					Fuzz.keep
				} else {
					crash "${Str.inspect(text)} was accepted but is not a preset that reads back"
				}
			Err([]) => crash "${Str.inspect(text)} was refused with no field to fix"
			Err(_) => Fuzz.keep
		},
	show: Str.inspect,
	examples: [
		Fuzz.example({ name: "ember-tunnel", revision: "1", make: || "{\"version\": 1, \"id\": \"user.ember-tunnel\", \"name\": \"Ember Tunnel\", \"background\": \"#0B0705\", \"layers\": [{\"type\": \"circular-waveform\", \"colors\": [\"#FF8C1A\", \"#FFD27A\"], \"size\": 200, \"thickness\": 25, \"opacity\": 100, \"mappings\": [{\"feature\": \"bass\", \"property\": \"size\", \"from\": 200, \"to\": 380}]}], \"feedback\": {\"enabled\": true, \"zoom\": 1030, \"half_life_ms\": 300}}" }),
		Fuzz.example({ name: "out-of-range", revision: "1", make: || "{\"version\": 1, \"id\": \"a\", \"name\": \"A\", \"background\": \"#000000\", \"layers\": [{\"type\": \"ring\", \"colors\": [], \"size\": 5000, \"thickness\": 0, \"opacity\": 100}]}" }),
	],
})

## A preset as roc-fuzz generates it: a name, and numbers that choose
## everything else, often out of range.
GeneratedPreset : { name : Str, numbers : List(U64) }

## Validation and the file agree: a preset reads back from its file as
## itself exactly when it has no problems, and otherwise is refused with
## exactly its problems, field by field.
preset_round_trip = Fuzz.target_with({
	name: "preset-round-trip",
	generator: { name: Fuzz.str, numbers: Fuzz.list(Fuzz.u64, 40) }.Fuzz,
	test: |generated| {
		preset = preset_from(generated)
		expected = if (Preset.problems(preset).is_empty()) Ok(preset) else Err(Preset.problems(preset))
		if Preset.decode(Preset.encode(preset)) == expected {
			Fuzz.keep
		} else {
			crash "a preset's file did not read back as its checks say: ${Preset.encode(preset)}"
		}
	},
	show: Str.inspect,
	examples: [
		Fuzz.example({ name: "valid", revision: "1", make: || { name: "Ember Tunnel", numbers: [1, 1, 1, 200, 25, 100, 2, 2, 1, 0, 200, 380] } }),
		Fuzz.example({ name: "every-problem", revision: "1", make: || { name: " ", numbers: [5, 9, 3, 1250, 0, 140, 6, 6, 29, 4, 900, 2000] } }),
	],
})

## The preset the numbers choose: the nth number picks the nth choice,
## going round the list again when it runs out.
preset_from : GeneratedPreset -> Preset.Doc
preset_from = |{ name, numbers }| {
	pick = |i| if (numbers.is_empty()) 0 else numbers.get(i % numbers.len()) ?? 0
	signed = |i, range| (pick(i) % (range + 1)).to_i64_wrap() - 100
	color = |i| { r: (pick(i) % 256).to_u8_wrap(), g: (pick(i + 1) % 256).to_u8_wrap(), b: (pick(i + 2) % 256).to_u8_wrap() }
	layers = List.repeat(0, pick(1) % 10).map_with_index(
		|_, j| {
			at = 2 + j * 9
			{
				kind: Preset.kinds.get(pick(at) % 4) ?? Ring,
				size: signed(at + 1, 1300),
				thickness: signed(at + 2, 400),
				opacity: signed(at + 3, 300),
				brightness: signed(at + 4, 300),
				rotation: signed(at + 5, 500),
				colors: List.repeat(0, pick(at + 6) % 6).map_with_index(|_, k| color(at + k)),
				mappings: List.repeat(0, pick(at + 7) % 6).map_with_index(
					|_, k| {
						n = pick(at + 8 + k)
						{ feature: Preset.features.get(n % 26).map_ok(|f| if (n % 7 == 0) Band(n % 30) else f) ?? Level, property: Preset.properties.get(n % 5) ?? Size, from: signed(at + k, 1300), to: signed(at + k + 1, 1300) }
					},
				),
			}
		},
	)
	{
		id: if (pick(0) % 5 == 0) "Not An ID" else "user.p${(pick(0) % 100).to_str()}",
		name,
		background: color(3),
		layers,
		feedback: { enabled: pick(4) % 2 == 0, zoom: signed(5, 400) + 900, rotation: signed(6, 900) - 300, half_life_ms: signed(7, 6000) },
		shaders: if (pick(8) % 3 == 0) Shaders(JsonValue.Object([("warp", JsonValue.Text("w"))])) else NoShaders,
	}
}

# ------------------------------------------------------------------ the queue

## Any sequence of queue operations keeps the queue's invariants: it holds
## at most `Queue.most` songs under distinct ids, its current song is one of
## them, its generation never goes back, and an end reported for any other
## generation is stale.
queue_invariants = Fuzz.target_with({
	name: "queue-invariants",
	generator: Fuzz.list(Fuzz.u8, 64),
	test: |ops| {
		var $queue = Queue.empty()
		var $count = 0.U64
		for op in ops {
			before = Queue.generation($queue)
			$queue = step($queue, op, $count)
			$count = $count + 1
			ids = Queue.entries($queue).map(|e| e.id)
			distinct = List.map2(ids.drop_last(1), ids.drop_first(1), |a, b| a < b).all(|ok| ok)
			current_held =
				match Queue.current_id($queue) {
					Ok(id) => ids.contains(id)
					Err(Nothing) => Bool.True
				}
			stale = Queue.ended($queue, Queue.generation($queue) + 1) == Stale and (Queue.generation($queue) == 0 or Queue.ended($queue, Queue.generation($queue) - 1) == Stale)
			if Queue.len($queue) > Queue.most or !distinct or !current_held or Queue.generation($queue) < before or !stale {
				crash "the queue broke an invariant after operation ${op.to_str()}: ${Str.inspect(Queue.entries($queue))}"
			}
		}
		Fuzz.keep
	},
	show: Str.inspect,
	examples: [
		Fuzz.example({ name: "fill-and-move", revision: "1", make: || [63, 63, 63, 63, 63, 63, 63, 1, 1, 2, 5, 4, 6, 3, 255] }),
	],
})

## One operation, chosen by a byte: add songs, next, previous, select,
## remove, the current song's end, or clear.
step : Queue(U64), U8, U64 -> Queue(U64)
step = |queue, op, n| {
	arg = (op // 7).to_u64()
	match op % 7 {
		0 => Queue.added(queue, List.repeat(n, arg % 10)).queue
		1 => Queue.next(queue)
		2 => Queue.previous(queue)
		3 => Queue.select(queue, arg)
		4 => Queue.removed(queue, arg)
		5 =>
			match Queue.ended(queue, Queue.generation(queue)) {
				Advanced(after) => after
				_ => queue
			}
		_ => if (op == 255) Queue.cleared(queue) else Queue.added(queue, List.repeat(n, 9)).queue
	}
}
