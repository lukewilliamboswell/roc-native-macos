import JsonValue

## A visualizer preset: the versioned document that says what to draw and
## how sound moves it. Built-ins, the presets a listener makes, previews and
## imports are all this one format, checked by `Preset.problems` and drawn
## through `Scene.of`.
##
## A preset has an ID, a name, a background colour, ordered layers (drawn
## first to last, so the last is on top), and feedback settings. A layer is
## one of a small published list of kinds, with its colours (a palette:
## the first is its base colour, the last its edge), its size, thickness,
## opacity, brightness and rotation, and mappings: each sends one sound
## feature (the level, the bass, mids or treble, or one of 24 bands) to one
## property over a range. `Bass -> Size from 200 to 380` grows a ring from
## a fifth of the view to nearly two fifths as the bass rises.
##
## Every number is whole, in the unit its field names: `size` in per-mille
## of the view's shorter side, `thickness` in tenths of a point, `opacity`
## and `brightness` in percent, `rotation` in degrees, feedback `zoom` in
## per-mille a second (1000 is still), its `rotation` in degrees a
## second, and `half_life_ms` the time a trail takes to fade to half.
##
## To add a layer kind: add it to `Kind`, `kinds`, `kind_name` and
## `kind_key`, and draw it in `Scene.geometry` and `Scene.figure`. To add a
## mapping target: add it to `Property`, `properties`, `property_name` and
## `property_range`, and apply it in `Scene.shape` and `Scene.layer_marks`;
## a target must be something the drawing surface can bind to a source: a
## transform, an opacity or a pen's width.
Preset := [].{

	## The version this app writes and reads.
	current_version : I64
	current_version = 1

	## What the `format` field of a preset file says.
	format : Str
	format = "roc-music-preset"

	Doc : { id : Str, name : Str, background : Color, layers : List(Layer), feedback : Feedback, shaders : Shaders }

	## A preset's shader stages, for a drawing surface that runs
	## user-written Metal shaders: absent, or a JSON object kept as it is.
	## This version only checks that it is an object, and draws without it;
	## its warp and composite stages, uniforms and audio-bound parameters
	## will be read and validated when the surface takes them.
	Shaders : [NoShaders, Shaders(JsonValue)]

	Color : { r : U8, g : U8, b : U8 }

	Layer : { kind : Kind, colors : List(Color), size : I64, thickness : I64, opacity : I64, brightness : I64, rotation : I64, mappings : List(Mapping) }

	## The kinds of layer: a waveform drawn across the view (an
	## oscilloscope), one wrapped round a circle, the spectrum as bars, and a
	## plain ring.
	Kind : [Waveform, CircularWaveform, Bars, Ring]

	Mapping : { feature : Feature, property : Property, from : I64, to : I64 }

	## A measurement of the sound, from 0 (silence) to 1000 (the loudest the
	## display shows): the overall level, the bass, mids and treble, or one
	## of the 24 bands from the lowest (0) to the highest (23).
	Feature : [Level, Bass, Mids, Treble, Band(U64)]

	Property : [Size, Thickness, Opacity, Brightness, Rotation]

	## Visual feedback: whether each frame keeps the last one, faded by
	## `half_life_ms`, zoomed by `zoom` and turned by `rotation`, under the
	## new drawing.
	Feedback : { enabled : Bool, zoom : I64, rotation : I64, half_life_ms : I64 }

	## Where a preset needs attention: the field (`layers[0].size`) and
	## what is wrong with it.
	FieldError : { field : Str, problem : Str }

	## The most layers a preset has, colours a layer has, and mappings a
	## layer has.
	most_layers : U64
	most_layers = 8

	most_colors : U64
	most_colors = 4

	most_mappings : U64
	most_mappings = 4

	## How many bands the analysis gives.
	band_count : U64
	band_count = 24

	kinds : List(Kind)
	kinds = [Waveform, CircularWaveform, Bars, Ring]

	kind_name : Kind -> Str
	kind_name = |kind|
		match kind {
			Waveform => "Waveform"
			CircularWaveform => "Circular waveform"
			Bars => "Spectrum bars"
			Ring => "Ring"
		}

	## A kind as a file spells it.
	kind_key : Kind -> Str
	kind_key = |kind|
		match kind {
			Waveform => "waveform"
			CircularWaveform => "circular-waveform"
			Bars => "bars"
			Ring => "ring"
		}

	properties : List(Property)
	properties = [Size, Thickness, Opacity, Brightness, Rotation]

	property_name : Property -> Str
	property_name = |property|
		match property {
			Size => "Size"
			Thickness => "Thickness"
			Opacity => "Opacity"
			Brightness => "Brightness"
			Rotation => "Rotation"
		}

	property_key : Property -> Str
	property_key = |property| Preset.property_name(property).with_ascii_lowercased()

	## The values a property, and the layer field of the same name, may take.
	property_range : Property -> { min : I64, max : I64 }
	property_range = |property|
		match property {
			Size => { min: 0, max: 1000 }
			Thickness => { min: 1, max: 200 }
			Opacity => { min: 0, max: 100 }
			Brightness => { min: 0, max: 100 }
			Rotation => { min: -180, max: 180 }
		}

	## The values a layer's thickness may take.
	thickness_range : { min : I64, max : I64 }
	thickness_range = Preset.property_range(Thickness)

	## The features a mapping may name, as the editor offers them.
	features : List(Feature)
	features = [Level, Bass, Mids, Treble].concat(List.repeat(Level, Preset.band_count).map_with_index(|_, band| Band(band)))

	feature_name : Feature -> Str
	feature_name = |feature|
		match feature {
			Level => "Level"
			Bass => "Bass"
			Mids => "Mids"
			Treble => "Treble"
			Band(n) => "Band ${(n + 1).to_str()}"
		}

	feature_key : Feature -> Str
	feature_key = |feature|
		match feature {
			Band(n) => "band-${n.to_str()}"
			_ => Preset.feature_name(feature).with_ascii_lowercased()
		}

	## The ranges of the feedback settings.
	zoom_range : { min : I64, max : I64 }
	zoom_range = { min: 900, max: 1100 }

	spin_range : { min : I64, max : I64 }
	spin_range = { min: -360, max: 360 }

	half_life_range : { min : I64, max : I64 }
	half_life_range = { min: 20, max: 5000 }

	## No feedback: each frame is drawn afresh.
	no_feedback : Feedback
	no_feedback = { enabled: Bool.False, zoom: 1000, rotation: 0, half_life_ms: 300 }

	## A new layer of a kind, in green, with no mappings.
	layer : Kind -> Layer
	layer = |kind| { kind, colors: [{ r: 0x39, g: 0xFF, b: 0x7A }], size: 200, thickness: 20, opacity: 100, brightness: 100, rotation: 0, mappings: [] }

	## Everything wrong with a preset, every field at once, or nothing. A
	## preset with no problems can be drawn, saved and shared.
	problems : Doc -> List(FieldError)
	problems = |preset| {
		name = preset.name.trim()
		about_name =
			if name.is_empty() {
				[{ field: "name", problem: "needs a name" }]
			} else if name.count_utf8_bytes() > 40 {
				[{ field: "name", problem: "is longer than 40 characters" }]
			} else {
				[]
			}
		about_id = if (Preset.is_id(preset.id)) [] else [{ field: "id", problem: "is 1 to 64 lowercase letters, digits, dots and hyphens" }]
		about_layers = if (preset.layers.len() > Preset.most_layers) [{ field: "layers", problem: "has more than ${Preset.most_layers.to_str()} layers" }] else []
		in_layers = preset.layers.map_with_index(|l, index| Preset.layer_problems(l, "layers[${index.to_str()}]")).join()
		feedback = preset.feedback
		about_feedback = [
			Preset.within(feedback.zoom, Preset.zoom_range, "feedback.zoom"),
			Preset.within(feedback.rotation, Preset.spin_range, "feedback.rotation"),
			Preset.within(feedback.half_life_ms, Preset.half_life_range, "feedback.half_life_ms"),
		].join()
		[about_name, about_id, about_layers, in_layers, about_feedback].join()
	}

	## Whether a text is an ID: 1 to 64 of `a-z`, `0-9`, `.` and `-`.
	is_id : Str -> Bool
	is_id = |id| {
		bytes = id.to_utf8()
		!bytes.is_empty() and bytes.len() <= 64 and bytes.all(|b| (b >= 'a' and b <= 'z') or (b >= '0' and b <= '9') or b == '.' or b == '-')
	}

	layer_problems : Layer, Str -> List(FieldError)
	layer_problems = |l, at| {
		colors =
			if l.colors.is_empty() {
				[{ field: "${at}.colors", problem: "needs at least one colour" }]
			} else if l.colors.len() > Preset.most_colors {
				[{ field: "${at}.colors", problem: "has more than ${Preset.most_colors.to_str()} colours" }]
			} else {
				[]
			}
		fields = [
			Preset.within(l.size, Preset.property_range(Size), "${at}.size"),
			Preset.within(l.thickness, Preset.thickness_range, "${at}.thickness"),
			Preset.within(l.opacity, Preset.property_range(Opacity), "${at}.opacity"),
			Preset.within(l.brightness, Preset.property_range(Brightness), "${at}.brightness"),
			Preset.within(l.rotation, Preset.property_range(Rotation), "${at}.rotation"),
		].join()
		count = if (l.mappings.len() > Preset.most_mappings) [{ field: "${at}.mappings", problem: "has more than ${Preset.most_mappings.to_str()} mappings" }] else []
		mappings = l.mappings.map_with_index(
			|m, index| {
				spot = "${at}.mappings[${index.to_str()}]"
				range = Preset.property_range(m.property)
				band =
					match m.feature {
						Band(n) if n >= Preset.band_count => [{ field: "${spot}.feature", problem: "names band ${n.to_str()}; the bands are 0 to ${(Preset.band_count - 1).to_str()}" }]
						_ => []
					}
				twice = if (l.mappings.take_first(index).any(|earlier| earlier.property == m.property)) [{ field: "${spot}.property", problem: "maps ${Preset.property_key(m.property)} a second time" }] else []
				[band, Preset.within(m.from, range, "${spot}.from"), Preset.within(m.to, range, "${spot}.to"), twice].join()
			},
		)
		[colors, fields, count, mappings.join()].join()
	}

	## A problem if `n` is outside `range`.
	within : I64, { min : I64, max : I64 }, Str -> List(FieldError)
	within = |n, range, field| if (n < range.min or n > range.max) [{ field, problem: "must be between ${range.min.to_str()} and ${range.max.to_str()}" }] else []

	# ---------------------------------------------------------------- the file

	## A preset as the JSON document it is saved and shared as.
	to_json : Doc -> JsonValue
	to_json = |preset|
		JsonValue.Object(
			[
				("format", JsonValue.Text(Preset.format)),
				("version", JsonValue.Int(Preset.current_version)),
				("id", JsonValue.Text(preset.id)),
				("name", JsonValue.Text(preset.name)),
				("background", JsonValue.Text(Preset.hex(preset.background))),
				("layers", JsonValue.Array(preset.layers.map(Preset.layer_json))),
				(
					"feedback",
					JsonValue.Object([
						("enabled", JsonValue.Bool(preset.feedback.enabled)),
						("zoom", JsonValue.Int(preset.feedback.zoom)),
						("rotation", JsonValue.Int(preset.feedback.rotation)),
						("half_life_ms", JsonValue.Int(preset.feedback.half_life_ms)),
					]),
				),
			].concat(
				match preset.shaders {
					Shaders(stages) => [("shaders", stages)]
					NoShaders => []
				},
			),
		)

	layer_json : Layer -> JsonValue
	layer_json = |l|
		JsonValue.Object([
			("type", JsonValue.Text(Preset.kind_key(l.kind))),
			("colors", JsonValue.Array(l.colors.map(|c| JsonValue.Text(Preset.hex(c))))),
			("size", JsonValue.Int(l.size)),
			("thickness", JsonValue.Int(l.thickness)),
			("opacity", JsonValue.Int(l.opacity)),
			("brightness", JsonValue.Int(l.brightness)),
			("rotation", JsonValue.Int(l.rotation)),
			(
				"mappings",
				JsonValue.Array(
					l.mappings.map(
						|m|
							JsonValue.Object([
								("feature", JsonValue.Text(Preset.feature_key(m.feature))),
								("property", JsonValue.Text(Preset.property_key(m.property))),
								("from", JsonValue.Int(m.from)),
								("to", JsonValue.Int(m.to)),
							]),
					),
				),
			),
		])

	## A preset as text, ready to save or export.
	encode : Doc -> Str
	encode = |preset| JsonValue.encode(Preset.to_json(preset))

	## The preset a text holds, or every field that needs attention: first
	## that it is JSON and has the shape of a preset of this version, then
	## that every value is in range (`Preset.problems`).
	decode : Str -> Try(Doc, List(FieldError))
	decode = |text|
		match JsonValue.parse(text) {
			Err({ at, what }) => Err([{ field: "(file)", problem: "is not JSON: ${what} at ${Preset.place(text, at)}" }])
			Ok(json) =>
				match Preset.from_json(json) {
					Err(problem) => Err([problem])
					Ok(preset) =>
						match Preset.problems(preset) {
							[] => Ok(preset)
							found => Err(found)
						}
				}
		}

	## Where byte `at` of a text is, as `line 3, column 7`.
	place : Str, U64 -> Str
	place = |text, at| {
		before = text.to_utf8().take_first(at)
		line = before.keep_if(|b| b == '\n').len() + 1
		column = at - (before.find_last_index(|b| b == '\n').map_ok(|i| i + 1) ?? 0) + 1
		"line ${line.to_str()}, column ${column.to_str()}"
	}

	## A preset from a JSON value of the right shape, or the first field
	## that is missing, of the wrong type, or unknown.
	from_json : JsonValue -> Try(Doc, FieldError)
	from_json = |json| {
		fields = Preset.object_at(json, "(file)")?
		Preset.known(fields, ["format", "version", "id", "name", "background", "layers", "feedback", "shaders"], "")?
		match JsonValue.field(json, "format") {
			Ok(Text(f)) if f == Preset.format => {}
			Err(Missing) => {}
			_ => return Err({ field: "format", problem: "is not \"${Preset.format}\"" })
		}
		stated = Preset.int_at(json, "version", "")?
		if stated != Preset.current_version {
			return Err({ field: "version", problem: "is ${stated.to_str()}; this app reads version ${Preset.current_version.to_str()}" })
		}
		id = Preset.text_at(json, "id", "")?
		name = Preset.text_at(json, "name", "")?
		background = Preset.color_at(JsonValue.field(json, "background") ?? JsonValue.Null, "background")?
		layers =
			match JsonValue.field(json, "layers") {
				Ok(Array(items)) => Preset.all_of(items.map_with_index(|item, index| Preset.layer_from(item, "layers[${index.to_str()}]")))?
				Ok(_) => return Err({ field: "layers", problem: "is not a list" })
				Err(Missing) => return Err({ field: "layers", problem: "is missing" })
			}
		feedback =
			match JsonValue.field(json, "feedback") {
				Err(Missing) => Preset.no_feedback
				Ok(given) => {
					Preset.known(Preset.object_at(given, "feedback")?, ["enabled", "zoom", "rotation", "half_life_ms"], "feedback.")?
					{
						enabled: Preset.flag_at(given, "enabled", "feedback.")?,
						zoom: Preset.int_at(given, "zoom", "feedback.")?,
						rotation: Preset.int_or_at(given, "rotation", 0, "feedback.")?,
						half_life_ms: Preset.int_at(given, "half_life_ms", "feedback.")?,
					}
				}
			}
		shaders =
			match JsonValue.field(json, "shaders") {
				Err(Missing) => NoShaders
				Ok(Object(stages)) => Shaders(JsonValue.Object(stages))
				Ok(_) => return Err({ field: "shaders", problem: "is not an object of shader stages" })
			}
		Ok({ id, name, background, layers, feedback, shaders })
	}

	layer_from : JsonValue, Str -> Try(Layer, FieldError)
	layer_from = |json, at| {
		fields = Preset.object_at(json, at)?
		Preset.known(fields, ["type", "colors", "size", "thickness", "opacity", "brightness", "rotation", "mappings"], "${at}.")?
		key = Preset.text_at(json, "type", "${at}.")?
		kind = Preset.kinds.find_first(|k| Preset.kind_key(k) == key).map_err(|_| { field: "${at}.type", problem: "is \"${key}\", not one of ${Preset.listed(Preset.kinds.map(Preset.kind_key))}" })?
		colors =
			match JsonValue.field(json, "colors") {
				Ok(Array(items)) => Preset.all_of(items.map_with_index(|item, index| Preset.color_at(item, "${at}.colors[${index.to_str()}]")))?
				Ok(_) => return Err({ field: "${at}.colors", problem: "is not a list" })
				Err(Missing) => return Err({ field: "${at}.colors", problem: "is missing" })
			}
		mappings =
			match JsonValue.field(json, "mappings") {
				Ok(Array(items)) => Preset.all_of(items.map_with_index(|item, index| Preset.mapping_from(item, "${at}.mappings[${index.to_str()}]")))?
				Ok(_) => return Err({ field: "${at}.mappings", problem: "is not a list" })
				Err(Missing) => []
			}
		Ok({
			kind,
			colors,
			size: Preset.int_at(json, "size", "${at}.")?,
			thickness: Preset.int_at(json, "thickness", "${at}.")?,
			opacity: Preset.int_at(json, "opacity", "${at}.")?,
			brightness: Preset.int_or_at(json, "brightness", 100, "${at}.")?,
			rotation: Preset.int_or_at(json, "rotation", 0, "${at}.")?,
			mappings,
		})
	}

	mapping_from : JsonValue, Str -> Try(Mapping, FieldError)
	mapping_from = |json, at| {
		fields = Preset.object_at(json, at)?
		Preset.known(fields, ["feature", "property", "from", "to"], "${at}.")?
		feature_text = Preset.text_at(json, "feature", "${at}.")?
		feature = Preset.feature_named(feature_text).map_err(|_| { field: "${at}.feature", problem: "is \"${feature_text}\", not level, bass, mids, treble or band-0 to band-${(Preset.band_count - 1).to_str()}" })?
		property_text = Preset.text_at(json, "property", "${at}.")?
		property = Preset.properties.find_first(|p| Preset.property_key(p) == property_text).map_err(|_| { field: "${at}.property", problem: "is \"${property_text}\", not one of ${Preset.listed(Preset.properties.map(Preset.property_key))}" })?
		Ok({ feature, property, from: Preset.int_at(json, "from", "${at}.")?, to: Preset.int_at(json, "to", "${at}.")? })
	}

	## The feature a file's text names. A band past the last is read, and
	## `problems` reports it.
	feature_named : Str -> Try(Feature, [NotAFeature])
	feature_named = |text|
		match text {
			"level" => Ok(Level)
			"bass" => Ok(Bass)
			"mids" => Ok(Mids)
			"treble" => Ok(Treble)
			_ =>
				if text.starts_with("band-") {
					digits = text.drop_prefix("band-")
					if digits.count_utf8_bytes() <= 3 and digits.to_utf8().all(|b| b >= '0' and b <= '9') {
						U64.from_str(digits).map_ok(|n| Band(n)).map_err(|_| NotAFeature)
					} else {
						Err(NotAFeature)
					}
				} else {
					Err(NotAFeature)
				}
		}

	listed : List(Str) -> Str
	listed = |names| Str.join_with(names, ", ")

	## Every result's value, or the first error.
	all_of : List(Try(a, e)) -> Try(List(a), e)
	all_of = |results|
		results.fold(
			Ok([]),
			|acc, result|
				match (acc, result) {
					(Ok(held), Ok(item)) => Ok(held.append(item))
					(Err(e), _) => Err(e)
					(_, Err(e)) => Err(e)
				},
		)

	object_at : JsonValue, Str -> Try(List((Str, JsonValue)), FieldError)
	object_at = |json, at|
		match json {
			Object(fields) => Ok(fields)
			_ => Err({ field: at, problem: "is not an object" })
		}

	## An error naming the first key that is not one of `allowed`, so a
	## mistyped field is reported rather than ignored.
	known : List((Str, JsonValue)), List(Str), Str -> Try({}, FieldError)
	known = |fields, allowed, prefix|
		match fields.find_first(|(key, _)| !allowed.contains(key)) {
			Ok((key, _)) => Err({ field: "${prefix}${key}", problem: "is not a field here" })
			Err(_) => Ok({})
		}

	int_at : JsonValue, Str, Str -> Try(I64, FieldError)
	int_at = |json, key, prefix|
		match JsonValue.field(json, key) {
			Ok(Int(n)) => Ok(n)
			Ok(_) => Err({ field: "${prefix}${key}", problem: "is not a whole number" })
			Err(Missing) => Err({ field: "${prefix}${key}", problem: "is missing" })
		}

	int_or_at : JsonValue, Str, I64, Str -> Try(I64, FieldError)
	int_or_at = |json, key, otherwise, prefix|
		match JsonValue.field(json, key) {
			Err(Missing) => Ok(otherwise)
			_ => Preset.int_at(json, key, prefix)
		}

	text_at : JsonValue, Str, Str -> Try(Str, FieldError)
	text_at = |json, key, prefix|
		match JsonValue.field(json, key) {
			Ok(Text(s)) => Ok(s)
			Ok(_) => Err({ field: "${prefix}${key}", problem: "is not text" })
			Err(Missing) => Err({ field: "${prefix}${key}", problem: "is missing" })
		}

	flag_at : JsonValue, Str, Str -> Try(Bool, FieldError)
	flag_at = |json, key, prefix|
		match JsonValue.field(json, key) {
			Ok(Bool(b)) => Ok(b)
			Ok(_) => Err({ field: "${prefix}${key}", problem: "is not true or false" })
			Err(Missing) => Err({ field: "${prefix}${key}", problem: "is missing" })
		}

	color_at : JsonValue, Str -> Try(Color, FieldError)
	color_at = |json, at|
		match json {
			Text(s) => Preset.parse_hex(s).map_err(|_| { field: at, problem: "is \"${s}\", not a colour such as \"#FF8C1A\"" })
			_ => Err({ field: at, problem: "is not a colour such as \"#FF8C1A\"" })
		}

	## A colour as `#RRGGBB`.
	hex : Color -> Str
	hex = |c| {
		digits = "0123456789ABCDEF".to_utf8()
		pair = |n| [digits.get((n // 16).to_u64()) ?? '0', digits.get((n % 16).to_u64()) ?? '0']
		Str.from_utf8(['#'].concat(pair(c.r)).concat(pair(c.g)).concat(pair(c.b))) ?? "#000000"
	}

	## The colour `#RRGGBB` (either case) names.
	parse_hex : Str -> Try(Color, [NotAColor])
	parse_hex = |text| {
		bytes = text.to_utf8()
		if bytes.len() != 7 or bytes.first() != Ok('#') {
			return Err(NotAColor)
		}
		value = |i| {
			hi = Preset.nibble(bytes.get(i) ?? 'x')?
			lo = Preset.nibble(bytes.get(i + 1) ?? 'x')?
			Ok(hi * 16 + lo)
		}
		Ok({ r: value(1)?, g: value(3)?, b: value(5)? })
	}

	nibble : U8 -> Try(U8, [NotAColor])
	nibble = |b|
		if b >= '0' and b <= '9' {
			Ok(b - '0')
		} else if b >= 'a' and b <= 'f' {
			Ok(b - 'a' + 10)
		} else if b >= 'A' and b <= 'F' {
			Ok(b - 'A' + 10)
		} else {
			Err(NotAColor)
		}
}

expect Preset.parse_hex("#FF8c1A") == Ok({ r: 255, g: 140, b: 26 }) and Preset.hex({ r: 255, g: 140, b: 26 }) == "#FF8C1A"
expect ["FF8C1A", "#FF8C1", "#GG0000", ""].all(|text| Preset.parse_hex(text) == Err(NotAColor))
expect Preset.feature_named("band-23") == Ok(Band(23)) and Preset.feature_named("band-x") == Err(NotAFeature) and Preset.features.len() == 28
expect Preset.place("{\n  \"a\": x", 9) == "line 2, column 8"

## A layer out of range is reported field by field, every one at once.
expect {
	layer = { ..Preset.layer(Ring), size: 1200, opacity: -1, mappings: [{ feature: Band(30), property: Size, from: 0, to: 2000 }, { feature: Bass, property: Size, from: 0, to: 10 }] }
	preset = { id: "user.x", name: " ", background: { r: 0, g: 0, b: 0 }, layers: [layer], feedback: { ..Preset.no_feedback, half_life_ms: 1 }, shaders: NoShaders }
	Preset.problems(preset).map(|p| p.field)
		== ["name", "layers[0].size", "layers[0].opacity", "layers[0].mappings[0].feature", "layers[0].mappings[0].to", "layers[0].mappings[1].property", "feedback.half_life_ms"]
}

## A file is checked for JSON, then shape, then version, then ranges.
expect {
	field_of = |text|
		match Preset.decode(text) {
			Err([first, ..]) => first.field
			_ => "accepted"
		}
	field_of("{") == "(file)"
		and field_of("{\"version\": 2}") == "version"
		and field_of("{\"version\": 1, \"id\": \"a\", \"name\": \"A\", \"background\": \"#000000\", \"layers\": [{\"type\": \"spiral\"}]}") == "layers[0].type"
		and field_of("{\"version\": 1, \"id\": \"a\", \"name\": \"A\", \"background\": \"#000000\", \"layers\": [], \"colour\": 1}") == "colour"
		and field_of("{\"version\": 1, \"id\": \"a\", \"name\": \"A\", \"background\": \"#000000\", \"layers\": []}") == "accepted"
}
