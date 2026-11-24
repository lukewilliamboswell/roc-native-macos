import Preset

## What a preset draws, as a scene: the app's own description of the
## picture, in two forms.
##
## `Scene.of` gives a `Drawing`: one `Shape` a layer, in the preset's own
## units, each moving value a binding (`Follows`) that names a native data
## source (`audio.bass`) and the range it maps to. It is what the editor and
## the editor describes (`Scene.describe`), and what `Scene.at` evaluates
## for given measurements, as the host does, so a scene can be previewed and
## tested without sound.
##
## `Scene.marks` turns a drawing into the drawing surface's form: an ordered
## list of `Mark`s (fill and stroke a shape, move, scale, turn and fade what
## follows), in a `Scene.space` of 1000 by 1000 units fitted to the view, a
## `Scene.trail` for visual feedback, and a background colour. `Mark`,
## `Shape`, `Number`, `Pen`, `Area` and `Trail` here have the same tags and
## fields as the platform's `Ui` drawing types, colours aside (`Rgb`, a
## `0xRRGGBB`, where `Ui` takes a `Ui.Color`), so `src/Visual.roc` hands them
## on almost as they are. A moving value is a `Source` the host reads on
## each display refresh (`offset + scale * value`, the value from 0 to 1, or
## -1 to 1 for the waveform), so the picture moves with the music without
## Roc running every frame. Roc rebuilds the marks only when the preset
## changes.
Scene := [].{

	## A colour with its opacity.
	Rgba : { r : U8, g : U8, b : U8, a : U8 }

	## A number of a drawing, fixed, or following a source from 0 to 1000
	## onto the range `from` to `to`.
	Value : [Fixed(I64), Follows({ source : Str, from : I64, to : I64 })]

	## What a layer traces: the waveform across the view or round a circle,
	## the bands as bars, or a circle, at a size in per-mille of the view's
	## shorter side.
	Geometry : [Line({ samples : Str, height : Value }), Loop({ samples : Str, radius : Value }), Bars({ levels : Str, height : Value }), Circle({ radius : Value })]

	## One layer as drawn: its geometry, its colour and edge colour (the edge
	## drawn at `brightness` percent over the base), the stroke's width in
	## tenths of a point, its opacity in percent and its rotation in degrees
	## about the centre.
	Shape : { geometry : Geometry, color : Rgba, edge : Rgba, width : Value, opacity : Value, brightness : Value, rotation : Value }

	## Whether the last frame is kept under the new one, and how it fades
	## (by half every `half_life_ms`), zooms (per-mille a second) and turns
	## (degrees a second).
	Feedback : [NoTrail, Trail({ half_life_ms : I64, zoom : I64, rotation : I64 })]

	## The whole picture.
	Drawing : { background : Rgba, shapes : List(Shape), trail : Feedback }

	## The native data sources a scene binds to.
	waveform_source : Str
	waveform_source = "audio.waveform"

	bands_source : Str
	bands_source = "audio.bands"

	## The source of a feature: `audio.level`, `audio.bass`, `audio.mids`,
	## `audio.treble`, or `audio.bands[n]`.
	source : Preset.Feature -> Str
	source = |feature|
		match feature {
			Level => "audio.level"
			Bass => "audio.bass"
			Mids => "audio.mids"
			Treble => "audio.treble"
			Band(n) => "audio.bands[${n.to_str()}]"
		}

	## The scene a preset draws.
	of : Preset.Doc -> Drawing
	of = |preset| {
		background: Scene.opaque(preset.background),
		shapes: preset.layers.map(Scene.shape),
		trail: if (preset.feedback.enabled) Trail({ half_life_ms: preset.feedback.half_life_ms, zoom: preset.feedback.zoom, rotation: preset.feedback.rotation }) else NoTrail,
	}

	opaque : Preset.Color -> Rgba
	opaque = |c| { r: c.r, g: c.g, b: c.b, a: 255 }

	## A layer as a shape: each property its base value, or the binding its
	## mapping gives it.
	shape : Preset.Layer -> Shape
	shape = |layer| {
		value = |property, base|
			match layer.mappings.find_first(|m| m.property == property) {
				Ok(m) => Follows({ source: Scene.source(m.feature), from: m.from, to: m.to })
				Err(_) => Fixed(base)
			}
		base = layer.colors.first() ?? { r: 255, g: 255, b: 255 }
		{
			geometry: Scene.geometry(layer.kind, value(Size, layer.size)),
			color: Scene.opaque(base),
			edge: Scene.opaque(layer.colors.last() ?? base),
			width: value(Thickness, layer.thickness),
			opacity: value(Opacity, layer.opacity),
			brightness: value(Brightness, layer.brightness),
			rotation: value(Rotation, layer.rotation),
		}
	}

	## What a kind of layer traces, at a size.
	geometry : Preset.Kind, Value -> Geometry
	geometry = |kind, size|
		match kind {
			Waveform => Line({ samples: Scene.waveform_source, height: size })
			CircularWaveform => Loop({ samples: Scene.waveform_source, radius: size })
			Bars => Bars({ levels: Scene.bands_source, height: size })
			Ring => Circle({ radius: size })
		}

	## Measurements of the sound, each from 0 to 1000, as the analysis gives
	## them: the level, the bass, mids and treble, and the bands.
	Features : { level : I64, bass : I64, mids : I64, treble : I64, bands : List(I64) }

	## Silence.
	silent : Features
	silent = { level: 0, bass: 0, mids: 0, treble: 0, bands: List.repeat(0, Preset.band_count) }

	## A source's measurement.
	measured : Features, Str -> I64
	measured = |features, name|
		match name {
			"audio.level" => features.level
			"audio.bass" => features.bass
			"audio.mids" => features.mids
			"audio.treble" => features.treble
			_ =>
				match name.drop_prefix("audio.bands[").split_first("]") {
					Ok({ before: digits, after: "" }) => features.bands.get(U64.from_str(digits) ?? 1_000) ?? 0
					_ => 0
				}
		}

	## A value as it is for given measurements: a binding's source, clamped
	## to 0 to 1000, mapped onto its range.
	value_at : Value, Features -> I64
	value_at = |value, features|
		match value {
			Fixed(n) => n
			Follows({ source: name, from, to }) => {
				level = Scene.measured(features, name).max(0).min(1000)
				from + (to - from) * level // 1000
			}
		}

	## The scene with every binding evaluated for given measurements.
	at : Drawing, Features -> Drawing
	at = |drawing, features| {
		fixed = |value| Fixed(Scene.value_at(value, features))
		{
			..drawing,
			shapes: drawing.shapes.map(
				|s| {
					..s,
					geometry: match s.geometry {
						Line(g) => Line({ ..g, height: fixed(g.height) })
						Loop(g) => Loop({ ..g, radius: fixed(g.radius) })
						Bars(g) => Bars({ ..g, height: fixed(g.height) })
						Circle(g) => Circle({ radius: fixed(g.radius) })
					},
					width: fixed(s.width),
					opacity: fixed(s.opacity),
					brightness: fixed(s.brightness),
					rotation: fixed(s.rotation),
				},
			),
		}
	}

	## The scene in words, a line a shape and one for the trail: a readable
	## summary of a preset.
	describe : Drawing -> List(Str)
	describe = |drawing| {
		shapes = drawing.shapes.map_with_index(
			|s, index| {
				(what, size) =
					match s.geometry {
						Line({ height, .. }) => ("waveform", height)
						Loop({ radius, .. }) => ("circular waveform", radius)
						Bars({ height, .. }) => ("spectrum bars", height)
						Circle({ radius }) => ("ring", radius)
					}
				colors = if (s.color == s.edge) Scene.hex(s.color) else "${Scene.hex(s.color)} to ${Scene.hex(s.edge)}"
				moving = [("size", size), ("thickness", s.width), ("opacity", s.opacity), ("brightness", s.brightness), ("rotation", s.rotation)].keep_oks(
					|(name, value)|
						match value {
							Follows({ source: from_source, from, to }) => Ok("${name} follows ${from_source.drop_prefix("audio.")} ${from.to_str()}–${to.to_str()}")
							Fixed(_) => Err(Still)
						},
				)
				"${(index + 1).to_str()}. ${what} ${Scene.fixed_text(size)}, ${colors}${if (moving.is_empty()) "" else "; ${Str.join_with(moving, ", ")}"}"
			},
		)
		trail_line =
			match drawing.trail {
				NoTrail => "No trails"
				Trail({ half_life_ms, zoom, rotation }) => "Trails halve every ${half_life_ms.to_str()} ms, zoom ${zoom.to_str()}‰${if (rotation == 0) "" else ", turn ${rotation.to_str()}° a second"}"
			}
		(if (shapes.is_empty()) ["No layers yet"] else shapes).append(trail_line)
	}

	fixed_text : Value -> Str
	fixed_text = |value|
		match value {
			Fixed(n) => "${n.to_str()}‰"
			Follows(_) => "moving"
		}

	hex : Rgba -> Str
	hex = |c| Preset.hex({ r: c.r, g: c.g, b: c.b })

	# ------------------------------------------------- the surface's form

	## A colour as `0xRRGGBB`.
	Rgb : U32

	## A number of the surface: a constant, or `offset + scale * value` of a
	## native source's latest scalar, or of one value of its latest series
	## (`Element`, as a band of `audio.bands`).
	Number : [Value(F64), Source({ source : Str, scale : F64, offset : F64 }), Element({ source : Str, index : U64, scale : F64, offset : F64 })]

	## A rectangle: its top-left corner and its size, in scene units.
	Area : { x : F64, y : F64, width : F64, height : F64 }

	## The shapes the marks draw: an oval, or a series of a native source
	## drawn as a waveform across an area, a loop round a centre, or bars.
	SurfaceShape : [
		Oval(Area),
		Wave({ source : Str, area : Area, low : F64, high : F64 }),
		Ring({ source : Str, x : F64, y : F64, radius : F64, depth : F64, low : F64, high : F64 }),
		Bars({ source : Str, area : Area, low : F64, high : F64, gap : F64 }),
	]

	## How an outline is drawn: its colour and width in scene units.
	Pen : { color : Rgb, width : Number }

	## One step of the surface's scene, drawn in order. `Rotate` is in
	## radians, clockwise; `Opacity` multiplies; `Save` and `Restore` keep and
	## return to the transform and opacity.
	Mark : [
		Fill(SurfaceShape, Rgb),
		Stroke(SurfaceShape, Pen),
		Save,
		Restore,
		Translate(Number, Number),
		Rotate(Number),
		Scale(Number, Number),
		Opacity(Number),
	]

	## The surface's feedback: rates a second, the turn in radians.
	Trail : [NoTrail, Trail({ half_life_ms : F64, zoom : F64, turn : F64, shift : { x : F64, y : F64 } })]

	## The scene's units: 1000 by 1000, fitted to the view and centred, so a
	## preset's per-mille sizes are of the view's shorter side.
	space : { width : F64, height : F64 }
	space = { width: 1000, height: 1000 }

	## Scene units a tenth of a point of thickness takes, at the
	## visualization's opening size (about 250 points on its shorter side).
	units_per_tenth_point : F64
	units_per_tenth_point = 0.4

	## The background as the surface takes it.
	background : Drawing -> Rgb
	background = |drawing| Scene.rgb(drawing.background)

	rgb : Rgba -> Rgb
	rgb = |c| c.r.to_u32() * 65536 + c.g.to_u32() * 256 + c.b.to_u32()

	## The trail as the surface takes it: the zoom per-mille a second as a
	## factor a second, the turn in radians a second, and no shift.
	trail : Drawing -> Trail
	trail = |drawing|
		match drawing.trail {
			NoTrail => NoTrail
			Trail({ half_life_ms, zoom, rotation }) => Trail({ half_life_ms: half_life_ms.to_f64(), zoom: zoom.to_f64() / 1000, turn: Scene.radians(rotation.to_f64()), shift: { x: 0, y: 0 } })
		}

	radians : F64 -> F64
	radians = |degrees| degrees * 3.141592653589793 / 180

	## A value at rest: a fixed one, or where a binding starts.
	at_rest : Value -> I64
	at_rest = |value|
		match value {
			Fixed(n) => n
			Follows({ from, .. }) => from
		}

	## A drawing's value as a surface number, in its own units times `unit`:
	## a band of `audio.bands` is an `Element` of that series.
	number : Value, F64 -> Number
	number = |value, unit|
		match value {
			Fixed(n) => Value(n.to_f64() * unit)
			Follows({ source: name, from, to }) => {
				scale = (to - from).to_f64() * unit
				offset = from.to_f64() * unit
				match name.drop_prefix("audio.bands[").split_first("]") {
					Ok({ before: digits, after: "" }) if name.starts_with("audio.bands[") => Element({ source: Scene.bands_source, index: U64.from_str(digits) ?? 0, scale, offset })
					_ => Source({ source: name, scale, offset })
				}
			}
		}

	## The marks that draw a drawing, layer by layer. Each layer is drawn
	## about the centre: moved there, turned by its rotation, scaled by its
	## size (a size that follows the sound scales the shape drawn at its
	## largest, so the stroke grows and shrinks with it), faded by its
	## opacity, drawn in its colour, then drawn again in its edge colour at
	## its brightness.
	marks : Drawing -> List(Mark)
	marks = |drawing| drawing.shapes.join_map(Scene.layer_marks)

	layer_marks : Shape -> List(Mark)
	layer_marks = |s| {
		size =
			match s.geometry {
				Line({ height, .. }) => height
				Loop({ radius, .. }) => radius
				Bars({ height, .. }) => height
				Circle({ radius }) => radius
			}
		# The size the shape is drawn at, and the scale that takes it to the
		# size that follows the sound.
		(drawn, scale) =
			match size {
				Fixed(n) => (n.to_f64(), [])
				Follows({ from, to, .. }) => {
					largest = from.max(to).max(1).to_f64()
					k = Scene.number(size, 1 / largest)
					uniform = match s.geometry {
						Line(_) => Scale(Value(1), k)
						Bars(_) => Scale(Value(1), k)
						_ => Scale(k, k)
					}
					(largest, [uniform])
				}
			}
		drawn_shape = Scene.figure(s.geometry, drawn, Scene.at_rest(s.width).to_f64())
		paint = |color|
			match drawn_shape {
				Bars(_) => Fill(drawn_shape, Scene.rgb(color))
				_ => Stroke(drawn_shape, { color: Scene.rgb(color), width: Scene.number(s.width, Scene.units_per_tenth_point) })
			}
		edge = if (s.edge == s.color) [] else [Opacity(Scene.number(s.brightness, 0.01)), paint(s.edge)]
		lit = if (s.edge == s.color) [Opacity(Scene.number(s.brightness, 0.01))] else []
		[Save, Translate(Value(500), Value(500)), Rotate(Scene.number(s.rotation, Scene.radians(1)))]
			.concat(scale)
			.concat([Opacity(Scene.number(s.opacity, 0.01))])
			.concat(lit)
			.append(paint(s.color))
			.concat(edge)
			.append(Restore)
	}

	## A geometry as the surface's shape, about the centre, at size `size`.
	## A waveform runs from -1 to 1, its middle at the centre line; a loop's
	## silence is at its radius, and the wave swings an eighth of the radius
	## either side; bars rise from 0 to 1, `width` tenths of a point apart.
	figure : Geometry, F64, F64 -> SurfaceShape
	figure = |traced, size, width|
		match traced {
			Line({ samples, .. }) => Wave({ source: samples, area: { x: -500, y: -size / 2, width: 1000, height: size }, low: -1, high: 1 })
			Loop({ samples, .. }) => Ring({ source: samples, x: 0, y: 0, radius: size * 7 / 8, depth: size / 4, low: -1, high: 1 })
			Bars({ levels, .. }) => Bars({ source: levels, area: { x: -450, y: -size / 2, width: 900, height: size }, low: 0, high: 1, gap: width * Scene.units_per_tenth_point })
			Circle(_) => Oval({ x: -size, y: -size, width: size * 2, height: size * 2 })
		}
}

## Ember Tunnel: a loop whose radius follows the bass from 200 to 380, its
## edge brightened by the treble, with trails.
expect {
	drawing = Scene.of({ id: "user.ember-tunnel", name: "Ember Tunnel", background: { r: 0x0B, g: 0x07, b: 0x05 }, layers: [{ ..Preset.layer(CircularWaveform), colors: [{ r: 0xFF, g: 0x8C, b: 0x1A }, { r: 0xFF, g: 0xD2, b: 0x7A }], mappings: [{ feature: Bass, property: Size, from: 200, to: 380 }, { feature: Treble, property: Brightness, from: 40, to: 100 }] }], feedback: { enabled: Bool.True, zoom: 1030, rotation: 0, half_life_ms: 300 }, shaders: NoShaders })
	quiet = Scene.at(drawing, Scene.silent)
	kick = Scene.at(drawing, { ..Scene.silent, bass: 1000, treble: 500 })
	radius = |d|
		match d.shapes {
			[{ geometry: Loop({ radius: Fixed(r), .. }), brightness: Fixed(b), .. }] => (r, b)
			_ => (0, 0)
		}
	radius(quiet) == (200, 40)
		and radius(kick) == (380, 70)
		and drawing.trail == Trail({ half_life_ms: 300, zoom: 1030, rotation: 0 })
		and Scene.describe(drawing) == ["1. circular waveform moving, #FF8C1A to #FFD27A; size follows bass 200–380, brightness follows treble 40–100", "Trails halve every 300 ms, zoom 1030‰"]
}

## Ember Tunnel's marks: a ring drawn at its largest radius, scaled by the
## bass from 200/380 to 1, faded, stroked amber, then stroked gold at the
## treble's brightness; its trail as the surface's rates.
expect {
	drawing = Scene.of({ id: "user.e", name: "E", background: { r: 0x0B, g: 0x07, b: 0x05 }, layers: [{ ..Preset.layer(CircularWaveform), thickness: 25, colors: [{ r: 0xFF, g: 0x8C, b: 0x1A }, { r: 0xFF, g: 0xD2, b: 0x7A }], mappings: [{ feature: Bass, property: Size, from: 190, to: 380 }, { feature: Treble, property: Brightness, from: 40, to: 100 }] }], feedback: { enabled: Bool.True, zoom: 1030, rotation: 0, half_life_ms: 300 }, shaders: NoShaders })
	ring = Ring({ source: "audio.waveform", x: 0, y: 0, radius: 332.5, depth: 95, low: -1, high: 1 })
	Scene.marks(drawing)
		== [
			Save,
			Translate(Value(500), Value(500)),
			Rotate(Value(0)),
			Scale(Source({ source: "audio.bass", scale: 0.5, offset: 0.5 }), Source({ source: "audio.bass", scale: 0.5, offset: 0.5 })),
			Opacity(Value(1)),
			Stroke(ring, { color: 0xFF8C1A, width: Value(10) }),
			Opacity(Source({ source: "audio.treble", scale: 0.6, offset: 0.4 })),
			Stroke(ring, { color: 0xFFD27A, width: Value(10) }),
			Restore,
		]
		and Scene.trail(drawing) == Trail({ half_life_ms: 300, zoom: 1.03, turn: 0, shift: { x: 0, y: 0 } })
		and Scene.background(drawing) == 0x0B0705
}

## Scope is a wave across the view, Spectrum Bars filled bars; a single
## colour is drawn once, at its brightness.
expect {
	scope = Scene.marks(Scene.of({ id: "x", name: "x", background: { r: 0, g: 0, b: 0 }, layers: [{ ..Preset.layer(Waveform), size: 400 }], feedback: Preset.no_feedback, shaders: NoShaders }))
	bars = Scene.marks(Scene.of({ id: "x", name: "x", background: { r: 0, g: 0, b: 0 }, layers: [{ ..Preset.layer(Bars), size: 800, thickness: 60 }], feedback: Preset.no_feedback, shaders: NoShaders }))
	scope.any(|m| m == Stroke(Wave({ source: "audio.waveform", area: { x: -500, y: -200, width: 1000, height: 400 }, low: -1, high: 1 }), { color: 0x39FF7A, width: Value(8) }))
		and bars.any(|m| m == Fill(Bars({ source: "audio.bands", area: { x: -450, y: -400, width: 900, height: 800 }, low: 0, high: 1, gap: 24 }), 0x39FF7A))
		and scope.len() == 7
}

## A band source reads its band; measurements are clamped.
expect {
	features = { ..Scene.silent, bands: List.repeat(0, 24).set(3, 500) ?? [] }
	Scene.value_at(Follows({ source: Scene.source(Band(3)), from: 0, to: 100 }), features) == 50
		and Scene.value_at(Follows({ source: "audio.level", from: 100, to: 0 }), { ..Scene.silent, level: 5000 }) == 0
		and Scene.value_at(Follows({ source: "audio.nothing", from: 7, to: 9 }), features) == 7
}

expect Scene.describe(Scene.of({ id: "user.untitled", name: "Untitled", background: { r: 0, g: 0, b: 0 }, layers: [], feedback: Preset.no_feedback, shaders: NoShaders })) == ["No layers yet", "No trails"]

## A band binds one value of `audio.bands`, and a thickness mapping drives
## the pen.
expect {
	layer = { ..Preset.layer(Ring), mappings: [{ feature: Band(3), property: Size, from: 100, to: 300 }, { feature: Level, property: Thickness, from: 10, to: 60 }] }
	marks = Scene.marks(Scene.of({ id: "x", name: "x", background: { r: 0, g: 0, b: 0 }, layers: [layer], feedback: Preset.no_feedback, shaders: NoShaders }))
	by_band = |m|
		match m {
			Scale(Element({ source: "audio.bands", index: 3, .. }), Element({ source: "audio.bands", index: 3, .. })) => Bool.True
			_ => Bool.False
		}
	marks.any(by_band) and marks.any(|m| m == Stroke(Oval({ x: -300, y: -300, width: 600, height: 600 }), { color: 0x39FF7A, width: Source({ source: "audio.level", scale: 20, offset: 4 }) }))
}
