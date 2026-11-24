import Gallery
import JsonValue
import Preset
import "../specs/fixtures/ember-tunnel.json" as ember_file : Str

## The preset library: the three built-ins every listener has, the presets
## a listener makes (kept in local storage), and the rules for saving,
## duplicating and removing them.
##
## Built-ins have IDs that start `builtin.` and cannot be replaced or
## removed. A listener's presets have IDs that start `user.`, made from
## their names (`Ember Tunnel` is `user.ember-tunnel`), so saving under a
## name that is taken replaces that preset, as Save As does in any app.
## Every preset's name is distinct, so the preset selector can list them by
## name.
Library := [].{

	## A green oscilloscope: the waveform drawn across the view.
	scope : Preset.Doc
	scope = {
		id: "builtin.scope",
		name: "Scope",
		background: { r: 0x02, g: 0x0A, b: 0x04 },
		layers: [{ ..Preset.layer(Waveform), size: 400, thickness: 20, colors: [{ r: 0x39, g: 0xFF, b: 0x7A }] }],
		feedback: Preset.no_feedback,
		shaders: NoShaders,
	}

	## The spectrum as bars, blue rising to cyan.
	spectrum_bars : Preset.Doc
	spectrum_bars = {
		id: "builtin.spectrum-bars",
		name: "Spectrum Bars",
		background: { r: 0x05, g: 0x07, b: 0x12 },
		layers: [{ ..Preset.layer(Bars), size: 800, thickness: 60, colors: [{ r: 0x2E, g: 0x7D, b: 0xFF }, { r: 0x7C, g: 0xF0, b: 0xFF }], mappings: [{ feature: Treble, property: Brightness, from: 60, to: 100 }] }],
		feedback: Preset.no_feedback,
		shaders: NoShaders,
	}

	## A ring the level swells, leaving rings that zoom away and fade: visual
	## feedback.
	echo_rings : Preset.Doc
	echo_rings = {
		id: "builtin.echo-rings",
		name: "Echo Rings",
		background: { r: 0x08, g: 0x02, b: 0x10 },
		layers: [{ ..Preset.layer(Ring), size: 150, thickness: 30, colors: [{ r: 0xB2, g: 0x66, b: 0xFF }, { r: 0xFF, g: 0x66, b: 0xD9 }], mappings: [{ feature: Level, property: Size, from: 150, to: 450 }] }],
		feedback: { enabled: Bool.True, zoom: 1050, rotation: 30, half_life_ms: 600 },
		shaders: NoShaders,
	}

	builtins : List(Preset.Doc)
	builtins = [Library.scope, Library.spectrum_bars, Library.echo_rings].concat(Gallery.all)

	## The preset a first launch shows, and the one chosen when the chosen
	## preset is gone: one of the shaded built-ins, at its best with the
	## default song.
	default : Preset.Doc
	default = Gallery.orb_garden

	## The worked example a listener makes from a blank preset: a circular
	## waveform a fifth of the view across, which the bass swells from 20% to
	## 38% and the treble brightens at its edge, in amber, with a slight
	## outward zoom and trails that halve every 300 ms. Each kick expands the
	## ring into the fading outlines of the kicks before it.
	ember_tunnel : Preset.Doc
	ember_tunnel = {
		id: "user.ember-tunnel",
		name: "Ember Tunnel",
		background: { r: 0x0B, g: 0x07, b: 0x05 },
		layers: [
			{
				..Preset.layer(CircularWaveform),
				size: 200,
				thickness: 25,
				colors: [{ r: 0xFF, g: 0x8C, b: 0x1A }, { r: 0xFF, g: 0xD2, b: 0x7A }],
				mappings: [{ feature: Bass, property: Size, from: 200, to: 380 }, { feature: Treble, property: Brightness, from: 40, to: 100 }],
			},
		],
		feedback: { enabled: Bool.True, zoom: 1030, rotation: 0, half_life_ms: 300 },
		shaders: NoShaders,
	}

	## A new preset: a black background and no layers yet.
	blank : Preset.Doc
	blank = { id: "user.untitled", name: "Untitled", background: { r: 0, g: 0, b: 0 }, layers: [], feedback: Preset.no_feedback, shaders: NoShaders }

	## The palettes the editor offers for a layer: its base colour first and
	## its edge colour last.
	palettes : List({ name : Str, colors : List(Preset.Color) })
	palettes = [
		{ name: "Phosphor", colors: [{ r: 0x39, g: 0xFF, b: 0x7A }] },
		{ name: "Amber", colors: [{ r: 0xFF, g: 0x8C, b: 0x1A }, { r: 0xFF, g: 0xD2, b: 0x7A }] },
		{ name: "Ice", colors: [{ r: 0x2E, g: 0x7D, b: 0xFF }, { r: 0x7C, g: 0xF0, b: 0xFF }] },
		{ name: "Orchid", colors: [{ r: 0xB2, g: 0x66, b: 0xFF }, { r: 0xFF, g: 0x66, b: 0xD9 }] },
		{ name: "Paper", colors: [{ r: 0xF4, g: 0xF1, b: 0xEA }] },
	]

	## The name of the palette a layer's colours are, or `Custom`.
	palette_name : List(Preset.Color) -> Str
	palette_name = |colors| (Library.palettes.find_first(|p| p.colors == colors) ?? { name: "Custom", colors: [] }).name

	## Every preset: the built-ins, then the listener's in the order saved.
	all : List(Preset.Doc) -> List(Preset.Doc)
	all = |mine| Library.builtins.concat(mine)

	is_builtin : Str -> Bool
	is_builtin = |id| id.starts_with("builtin.")

	## The preset with `id`, among the built-ins and `mine`.
	find : List(Preset.Doc), Str -> Try(Preset.Doc, [NotFound])
	find = |mine, id| Library.all(mine).find_first(|p| p.id == id)

	## The preset named `name`.
	named : List(Preset.Doc), Str -> Try(Preset.Doc, [NotFound])
	named = |mine, name| Library.all(mine).find_first(|p| p.name == name)

	## A name as an ID's tail: lowercase letters and digits, with a hyphen
	## for each run of anything else. `Ember Tunnel!` is `ember-tunnel`.
	slug : Str -> Str
	slug = |name| {
		bytes = name.with_ascii_lowercased().to_utf8()
		kept = bytes.fold(
			[],
			|out, b|
				if (b >= 'a' and b <= 'z') or (b >= '0' and b <= '9') {
					out.append(b)
				} else if out.last() == Ok('-') or out.is_empty() {
					out
				} else {
					out.append('-')
				},
		)
		trimmed = if (kept.last() == Ok('-')) kept.drop_last(1) else kept
		text = Str.from_utf8(trimmed.take_first(56)) ?? ""
		if (text.is_empty()) "preset" else text
	}

	## Saving `preset` as `name` among the listener's presets: under the ID
	## its name gives, replacing a preset of that ID, after the others
	## otherwise. A built-in's name cannot be taken.
	saved_as : List(Preset.Doc), Preset.Doc, Str -> Try({ mine : List(Preset.Doc), saved : Preset.Doc }, [NeedsName, BuiltinName])
	saved_as = |mine, preset, name| {
		clean = name.trim()
		if clean.is_empty() {
			return Err(NeedsName)
		}
		if Library.builtins.any(|b| b.name == clean) {
			return Err(BuiltinName)
		}
		saved = { ..preset, id: "user.${Library.slug(clean)}", name: clean }
		replaced = if (mine.any(|p| p.id == saved.id)) mine.map(|p| if (p.id == saved.id) saved else p) else mine.append(saved)
		# Another of the listener's presets may hold this name under an older ID.
		Ok({ mine: replaced.drop_if(|p| p.name == clean and p.id != saved.id), saved })
	}

	## A copy of `preset` under the first free name of `<name> Copy`,
	## `<name> Copy 2` and so on, after the others.
	duplicated : List(Preset.Doc), Preset.Doc -> { mine : List(Preset.Doc), saved : Preset.Doc }
	duplicated = |mine, preset| {
		taken = |candidate| Library.all(mine).any(|p| p.name == candidate or p.id == "user.${Library.slug(candidate)}")
		var $n = 1.U64
		var $name = "${preset.name} Copy"
		while taken($name) {
			$n = $n + 1
			$name = "${preset.name} Copy ${$n.to_str()}"
		}
		saved = { ..preset, id: "user.${Library.slug($name)}", name: $name }
		{ mine: mine.append(saved), saved }
	}

	## The listener's presets without `id`; a built-in stays.
	removed : List(Preset.Doc), Str -> List(Preset.Doc)
	removed = |mine, id| mine.drop_if(|p| p.id == id)

	## The listener's presets as the text kept in local storage.
	to_storage : List(Preset.Doc) -> Str
	to_storage = |mine| JsonValue.encode(JsonValue.Object([("format", JsonValue.Text("roc-music-library")), ("presets", JsonValue.Array(mine.map(Preset.to_json)))]))

	## The listener's presets read back from local storage. A stored preset
	## that no longer reads (or a damaged store) is left out rather than
	## stopping the app; its name is lost, never the others.
	from_storage : Str -> List(Preset.Doc)
	from_storage = |text|
		match JsonValue.parse(text) {
			Ok(json) =>
				match JsonValue.field(json, "presets") {
					Ok(Array(items)) =>
						items.keep_oks(
							|item| {
								preset = Preset.from_json(item).map_err(|_| Unreadable)?
								if (Preset.problems(preset).is_empty() and !Library.is_builtin(preset.id)) Ok(preset) else Err(Unreadable)
							},
						)
					_ => []
				}
			Err(_) => []
		}
}

## The built-ins and the worked example are valid presets, and each reads
## back from its file unchanged.
expect Library.builtins.append(Library.ember_tunnel).all(|p| Preset.problems(p).is_empty() and Preset.decode(Preset.encode(p)) == Ok(p))
expect Library.builtins.map(|p| p.name) == ["Scope", "Spectrum Bars", "Echo Rings", "Liquid Drift", "Blur Corridor", "Superscope Bloom", "Flux Streaks", "Phase Scope", "Peak Meter", "Plasma Weave", "Hyperspace", "Mirror Shard", "Spectrum Fire", "Ripple Pool", "Orb Garden"] and Library.default.id == "builtin.orb-garden"

## Every layer of the built-ins and Ember Tunnel uses a named palette.
expect [Library.scope, Library.spectrum_bars, Library.echo_rings, Library.ember_tunnel].all(|p| p.layers.all(|l| Library.palette_name(l.colors) != "Custom")) and Library.palette_name([]) == "Custom"

expect Library.slug("Ember Tunnel!") == "ember-tunnel" and Library.slug("  ---  ") == "preset" and Library.slug("Über 2") == "ber-2"

## Saving Ember Tunnel from blank gives it its ID; saving again replaces it;
## a built-in's name is refused.
expect {
	drafted = { ..Library.blank, layers: Library.ember_tunnel.layers, feedback: Library.ember_tunnel.feedback, background: Library.ember_tunnel.background }
	match Library.saved_as([], drafted, " Ember Tunnel ") {
		Ok({ mine, saved }) =>
			saved == Library.ember_tunnel
				and mine == [saved]
				and Library.saved_as(mine, { ..saved, layers: [] }, "Ember Tunnel").map_ok(|r| r.mine.len()) == Ok(1)
				and Library.saved_as(mine, saved, "Scope") == Err(BuiltinName)
				and Library.saved_as(mine, saved, "  ") == Err(NeedsName)
		Err(_) => Bool.False
	}
}

## Duplicating finds a free name; a built-in cannot be removed.
expect {
	once = Library.duplicated([Library.ember_tunnel], Library.ember_tunnel)
	twice = Library.duplicated(once.mine, Library.ember_tunnel)
	once.saved.name == "Ember Tunnel Copy"
		and twice.saved.name == "Ember Tunnel Copy 2"
		and twice.saved.id == "user.ember-tunnel-copy-2"
		and Library.removed(twice.mine, "user.ember-tunnel-copy") == [Library.ember_tunnel, twice.saved]
		and Library.find(Library.removed([], "builtin.scope"), "builtin.scope") == Ok(Library.scope)
}

## Storage round-trips the listener's presets, and drops what does not read.
expect {
	mine = [Library.ember_tunnel, { ..Library.blank, id: "user.b", name: "B" }]
	Library.from_storage(Library.to_storage(mine)) == mine and Library.from_storage("nonsense") == [] and Library.from_storage("{\"presets\": [1, {\"version\": 1}]}") == []
}

## The fixture `specs/fixtures/ember-tunnel.json` is Ember Tunnel's file,
## exactly as Export… writes it, and reads back as Ember Tunnel.
expect Preset.encode(Library.ember_tunnel) == ember_file.trim() and Preset.decode(ember_file) == Ok(Library.ember_tunnel)

## A preset's shaders go through its file: their sources with quotes,
## backslashes and line breaks, and params fixed or following the sound.
expect {
	stages = {
		warp: Some("// \"warp\"\nfloat4 warp(Frame f, Params p) {\n    return sample(f, f.uv) * p.decay; // a \\ fade\n}"),
		composite: None,
		params: [
			{ name: "decay", value: 0.975, low: 0.9, high: 0.995, follows: Fixed, about: "how much a frame keeps" },
			{ name: "push", value: 0, low: 0, high: 0.03, follows: Feature(Bass), about: "" },
			{ name: "glow", value: 1, low: 0, high: 2, follows: Feature(Band(3)), about: "" },
		],
	}
	carrying = { ..Library.blank, shaders: Shaders(stages) }
	Preset.decode(Preset.encode(carrying)) == Ok(carrying)
		and Preset.decode(Preset.encode(Library.blank)) == Ok(Library.blank)
		and Preset.decode("{\"version\": 1, \"id\": \"a\", \"name\": \"A\", \"background\": \"#000000\", \"layers\": [], \"shaders\": 3}") == Err([{ field: "shaders", problem: "is not an object" }])
}

## A preset's shaders are checked field by field.
expect {
	param = { name: "decay", value: 0.5, low: 0, high: 1, follows: Fixed, about: "" }
	stages = {
		warp: Some(Str.repeat("x", 65_537)),
		composite: None,
		params: [{ ..param, name: "9lives" }, param, param, { ..param, low: 2 }, { ..param, value: 3 }].concat(List.repeat({ ..param, name: "n" }, 12)),
	}
	fields = Preset.problems({ ..Library.blank, shaders: Shaders(stages) }).map(|p| p.field)
	fields.contains("shaders.warp")
		and fields.contains("shaders.params")
		and fields.contains("shaders.params[0].name")
		and fields.contains("shaders.params[2].name")
		and fields.contains("shaders.params[3].high")
		and fields.contains("shaders.params[4].value")
		and Preset.problems({ ..Library.blank, shaders: Shaders({ warp: None, composite: None, params: [] }) }).map(|p| p.field) == ["shaders"]
}
