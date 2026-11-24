import Eq
import JsonValue

## The listener's choices that outlast a launch: whether lyrics show, how
## large they are, which preset is chosen, the volume and the EQ. The
## lyrics choice belongs to the player, not to a preset: switching or
## importing a preset keeps it, and so does changing track.
##
## They are kept in local storage as one JSON object. Reading them back is
## forgiving: a field that is missing or wrong (an older app wrote it, or
## nothing did) takes its default, so a launch never fails over them.
Prefs := [].{

	Choices : { lyrics : Bool, lyric_size : LyricSize, preset : Str, volume : I64, eq : Eq.Settings }

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

	## Lyrics start off, at the regular size, with Scope, at full volume and
	## a flat EQ.
	defaults : Choices
	defaults = { lyrics: Bool.False, lyric_size: Regular, preset: "builtin.scope", volume: 100, eq: Eq.flat }

	encode : Choices -> Str
	encode = |prefs|
		JsonValue.encode(
			JsonValue.Object([
				("lyrics", JsonValue.Bool(prefs.lyrics)),
				("lyric_size", JsonValue.Text(Prefs.size_key(prefs.lyric_size))),
				("preset", JsonValue.Text(prefs.preset)),
				("volume", JsonValue.Int(prefs.volume)),
				("eq", Eq.to_json(prefs.eq)),
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
		}
	}
}

expect {
	prefs = { lyrics: Bool.True, lyric_size: Huge, preset: "user.ember-tunnel", volume: 40, eq: Eq.with_band(Eq.flat, 0, -60) }
	Prefs.decode(Prefs.encode(prefs)) == prefs
}

## Nothing saved, or something damaged, reads as the defaults field by field.
expect Prefs.decode("") == Prefs.defaults and Prefs.decode("{\"lyrics\": true, \"volume\": 900, \"lyric_size\": \"tiny\"}") == { ..Prefs.defaults, lyrics: Bool.True, volume: 100 }

expect Prefs.larger(Huge) == Huge and Prefs.smaller(Large) == Regular and Prefs.points(Regular) == 20
