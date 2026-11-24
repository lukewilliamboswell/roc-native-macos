import Eq
import JsonValue

## The listener's choices that outlast a launch: whether lyrics show, how
## large they are, which preset is chosen, the volume, the EQ, and the
## picture's sync offset for each audio output they calibrated. The
## lyrics choice belongs to the player, not to a preset: switching or
## importing a preset keeps it, and so does changing track.
##
## They are kept in local storage as one JSON object. Reading them back is
## forgiving: a field that is missing or wrong (an older app wrote it, or
## nothing did) takes its default, so a launch never fails over them.
Prefs := [].{

	Choices : { lyrics : Bool, lyric_size : LyricSize, preset : Str, volume : I64, eq : Eq.Settings, offsets : List(Offset) }

	## The picture's sync offset for one audio output, by its UID
	## (`Audio.Status.output`): milliseconds later than the sound
	## (negative: earlier), within `offset_range`.
	Offset : { output : Str, ms : I64 }

	offset_range : { min : I64, max : I64 }
	offset_range = { min: -300, max: 300 }

	## The offset kept for `output`, or 0.
	offset_for : List(Offset), Str -> I64
	offset_for = |offsets, output| (offsets.find_first(|o| o.output == output) ?? { output, ms: 0 }).ms

	## `offsets` with `output`'s set to `ms`, clamped; 0 forgets it.
	with_offset : List(Offset), Str, I64 -> List(Offset)
	with_offset = |offsets, output, ms| {
		kept = offsets.drop_if(|o| o.output == output)
		clamped = ms.max(Prefs.offset_range.min).min(Prefs.offset_range.max)
		if (clamped == 0 or output.is_empty()) kept else kept.append({ output, ms: clamped })
	}

	## The lyric sizes on offer.
	LyricSize : [Regular, Large, Huge]

	lyric_sizes : List(LyricSize)
	lyric_sizes = [Regular, Large, Huge]

	## A size as the overlay draws it, in points.
	points : LyricSize -> U32
	points = |size|
		match size {
			Regular => 20
			Large => 28
			Huge => 40
		}

	size_key : LyricSize -> Str
	size_key = |size|
		match size {
			Regular => "regular"
			Large => "large"
			Huge => "huge"
		}

	## A size one step up, or down; the ends stay.
	larger : LyricSize -> LyricSize
	larger = |size|
		match size {
			Regular => Large
			_ => Huge
		}

	smaller : LyricSize -> LyricSize
	smaller = |size|
		match size {
			Huge => Large
			_ => Regular
		}

	## Lyrics start off, at the regular size, with Orb Garden, at full volume and
	## a flat EQ.
	defaults : Choices
	defaults = { lyrics: Bool.False, lyric_size: Regular, preset: "builtin.orb-garden", volume: 100, eq: Eq.flat, offsets: [] }

	encode : Choices -> Str
	encode = |prefs|
		JsonValue.encode(
			JsonValue.Object([
				("lyrics", JsonValue.Bool(prefs.lyrics)),
				("lyric_size", JsonValue.Text(Prefs.size_key(prefs.lyric_size))),
				("preset", JsonValue.Text(prefs.preset)),
				("volume", JsonValue.Int(prefs.volume)),
				("eq", Eq.to_json(prefs.eq)),
				("offsets", JsonValue.Object(prefs.offsets.map(|o| (o.output, JsonValue.Int(o.ms))))),
			]),
		)

	decode : Str -> Choices
	decode = |text| {
		json = JsonValue.parse(text) ?? JsonValue.Null
		d = Prefs.defaults
		{
			lyrics: match JsonValue.field(json, "lyrics") {
				Ok(Bool(b)) => b
				_ => d.lyrics
			},
			lyric_size: match JsonValue.field(json, "lyric_size") {
				Ok(Text(key)) => Prefs.lyric_sizes.find_first(|s| Prefs.size_key(s) == key) ?? d.lyric_size
				_ => d.lyric_size
			},
			preset: match JsonValue.field(json, "preset") {
				Ok(Text(id)) => id
				_ => d.preset
			},
			volume: match JsonValue.field(json, "volume") {
				Ok(Int(n)) => n.max(0).min(100)
				_ => d.volume
			},
			eq: Eq.from_json(JsonValue.field(json, "eq") ?? JsonValue.Null),
			offsets: match JsonValue.field(json, "offsets") {
				Ok(Object(pairs)) =>
					pairs.fold(
						[],
						|kept, (output, value)|
							match value {
								Int(ms) => Prefs.with_offset(kept, output, ms)
								_ => kept
							},
					)
				_ => d.offsets
			},
		}
	}
}

expect {
	prefs = { lyrics: Bool.True, lyric_size: Huge, preset: "user.ember-tunnel", volume: 40, eq: Eq.with_band(Eq.flat, 0, -60), offsets: [{ output: "BuiltInSpeakerDevice", ms: -20 }, { output: "BT-Speaker", ms: 180 }] }
	Prefs.decode(Prefs.encode(prefs)) == prefs
}

## Nothing saved, or something damaged, reads as the defaults field by field.
expect Prefs.decode("") == Prefs.defaults and Prefs.decode("{\"lyrics\": true, \"volume\": 900, \"lyric_size\": \"tiny\"}") == { ..Prefs.defaults, lyrics: Bool.True, volume: 100 }

expect Prefs.larger(Huge) == Huge and Prefs.smaller(Large) == Regular and Prefs.points(Regular) == 20

## An offset is kept per output, clamped, and 0 forgets it.
expect {
	set = Prefs.with_offset(Prefs.with_offset(Prefs.with_offset([], "a", 40), "b", 900), "a", 0)
	(set, Prefs.offset_for(set, "b"), Prefs.offset_for(set, "c")) == ([{ output: "b", ms: 300 }], 300, 0)
}
