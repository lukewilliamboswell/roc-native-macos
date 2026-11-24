import JsonValue

## The graphic equalizer's settings, as the app keeps and shows them: ten
## bands at fixed centres, a preamp, and bypass.
##
## A slider gives whole numbers, so each gain is kept in tenths of a
## decibel: a band's slider runs from -120 to 120 (-12 dB to +12 dB) and the
## preamp's from -120 to 0, a cut that leaves headroom for boosts. The host
## applies them to the audio graph in decibels (`Eq.decibels`).
Eq := [].{

	## The gains in tenths of a dB, a band's in the order of `Eq.centres`.
	Settings : { bands : List(I64), preamp : I64, bypass : Bool }

	## Each band's centre frequency, in Hz, as the player's EQ has them
	## (`Audio.band_centres_hz`).
	centres : List(U64)
	centres = [32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]

	## The range of a band's slider, and of the preamp's.
	band_range : { min : I64, max : I64 }
	band_range = { min: -120, max: 120 }

	preamp_range : { min : I64, max : I64 }
	preamp_range = { min: -120, max: 0 }

	## Every gain at zero, not bypassed.
	flat : Settings
	flat = { bands: List.repeat(0, Eq.centres.len()), preamp: 0, bypass: Bool.False }

	## Flat: every gain back to zero, keeping whether it is bypassed.
	flattened : Settings -> Settings
	flattened = |settings| { ..Eq.flat, bypass: settings.bypass }

	## Whether every gain is zero.
	is_flat : Settings -> Bool
	is_flat = |settings| settings.preamp == 0 and settings.bands.all(|gain| gain == 0)

	## The settings with band `index` set to `tenths`, kept within its range.
	## An index past the last band changes nothing.
	with_band : Settings, U64, I64 -> Settings
	with_band = |settings, index, tenths| { ..settings, bands: settings.bands.set(index, Eq.clamped(tenths, Eq.band_range)) ?? settings.bands }

	with_preamp : Settings, I64 -> Settings
	with_preamp = |settings, tenths| { ..settings, preamp: Eq.clamped(tenths, Eq.preamp_range) }

	clamped : I64, { min : I64, max : I64 } -> I64
	clamped = |n, range| n.max(range.min).min(range.max)

	## A slider's value (tenths of a dB) in decibels, as the audio graph
	## takes it.
	decibels : I64 -> F32
	decibels = |tenths| tenths.to_f32() / 10

	## A gain as text: `+3.5 dB`, `-12.0 dB`, `0.0 dB`.
	label : I64 -> Str
	label = |tenths| {
		sign = if (tenths > 0) "+" else if (tenths < 0) "-" else ""
		size = tenths.abs()
		"${sign}${(size // 10).to_str()}.${(size % 10).to_str()} dB"
	}

	## A centre frequency as text: `32 Hz`, `1 kHz`, `16 kHz`.
	centre_label : U64 -> Str
	centre_label = |hz| if (hz >= 1_000) "${(hz // 1_000).to_str()} kHz" else "${hz.to_str()} Hz"

	## The settings as JSON, for the saved preferences.
	to_json : Settings -> JsonValue
	to_json = |settings|
		JsonValue.Object([
			("bands", JsonValue.Array(settings.bands.map(|gain| JsonValue.Int(gain)))),
			("preamp", JsonValue.Int(settings.preamp)),
			("bypass", JsonValue.Bool(settings.bypass)),
		])

	## Settings read back from JSON. Saved settings are the app's own, so
	## anything missing or out of range reads as flat rather than failing.
	from_json : JsonValue -> Settings
	from_json = |json| {
		bands =
			match JsonValue.field(json, "bands") {
				Ok(Array(items)) if items.len() == Eq.centres.len() =>
					items.map(
						|item|
							match item {
								Int(n) => Eq.clamped(n, Eq.band_range)
								_ => 0
							},
					)
				_ => Eq.flat.bands
			}
		preamp =
			match JsonValue.field(json, "preamp") {
				Ok(Int(n)) => Eq.clamped(n, Eq.preamp_range)
				_ => 0
			}
		bypass =
			match JsonValue.field(json, "bypass") {
				Ok(Bool(b)) => b
				_ => Bool.False
			}
		{ bands, preamp, bypass }
	}
}

expect Eq.label(35) == "+3.5 dB" and Eq.label(-120) == "-12.0 dB" and Eq.label(0) == "0.0 dB" and Eq.label(-5) == "-0.5 dB"
expect Eq.decibels(35) == 3.5 and Eq.decibels(-120) == -12.0
expect Eq.centre_label(32) == "32 Hz" and Eq.centre_label(16_000) == "16 kHz"

## A band is kept within its range, and Flat restores zero but not bypass.
expect {
	boosted = Eq.with_preamp(Eq.with_band({ ..Eq.flat, bypass: Bool.True }, 0, 500), 30)
	boosted.bands.first() == Ok(120)
		and boosted.preamp == 0
		and !Eq.is_flat(Eq.with_band(Eq.flat, 9, -30))
		and Eq.flattened(boosted) == { ..Eq.flat, bypass: Bool.True }
		and Eq.with_band(Eq.flat, 10, 50) == Eq.flat
}

## The saved form reads back; a damaged one reads as flat.
expect {
	settings = Eq.with_preamp(Eq.with_band(Eq.flat, 3, -45), -60)
	Eq.from_json(Eq.to_json(settings)) == settings and Eq.from_json(JsonValue.Null) == Eq.flat
}
