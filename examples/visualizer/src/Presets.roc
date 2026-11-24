import pf.Ui

## Twelve music visualizations, each a drawing surface's look as plain
## data: GPU shaders for the Metal renderer (`Ui.Shader`), and a scene and a
## trail that are the whole picture where shaders do not run (Core
## Graphics), so every one still looks like itself there.
##
## They take after the feedback visualizers of the late-90s players, each an
## original take on one idea of that era: a liquid warp, a blur tunnel, a
## superscope, flow-field streaks, a stereo vectorscope, a spectrum with
## falling caps, a plasma, a starfield, a kaleidoscope, demoscene fire,
## water ripples and glowing orbs. Every one reads the playback session's
## sources (`audio.waveform`, `audio.left`, `audio.right`, `audio.bands`,
## `audio.bass` and the rest): in its marks, through its params, and in the
## shaders' `Frame`.
##
## A preset is data, so another app (a music player, say) adopts it by
## copying this module and handing a preset's fields to `Ui.surface`:
##
## ```roc
## Ui.surface(Engine.const(p.scene), { label: p.name, space: Engine.const(p.space), background: Engine.const(p.background), pacing: Engine.const(Display), trail: Engine.const(p.trail), shader: Engine.const(Presets.shader(p)) })
## ```
##
## Reading a shader: each is one function, `warp` or `composite`, with
## helpers above it (docs/ui.adoc, "Shaders"). A warp makes the new frame
## from the previous one, and the marks are drawn over it; a composite maps
## the result to the screen. Motion is scaled by `k`, the frame's length in
## 60ths of a second, so it keeps time at 60 Hz and 120 Hz. The history
## keeps 8 bits a channel, so a fade also subtracts a little, or faint
## colours would never quite reach black.
Presets := [].{

	## A named number a preset's shaders read as `p.NAME`, and the range it
	## is meant to keep to.
	Param : { name : Str, number : Ui.Number, low : F64, high : F64, about : Str }

	## One visualization. `scene`, `space`, `background` and `trail` are what
	## Core Graphics draws alone; with Metal, `warp` replaces the trail and
	## `composite` maps the frame to the screen.
	Preset : {
		name : Str,
		about : Str,
		background : Ui.Color,
		space : Ui.Space,
		scene : List(Ui.Mark),
		trail : Ui.Trail,
		warp : [None, Some(Str)],
		composite : [None, Some(Str)],
		params : List(Param),
	}

	## The surface's shaders for a preset.
	shader : Preset -> Ui.Shader
	shader = |p| Shaders({ warp: p.warp, composite: p.composite, params: p.params.map(|param| (param.name, param.number)) })

	## Every preset, in the gallery's order.
	all : List(Preset)
	all = [
		liquid_drift,
		blur_corridor,
		superscope_bloom,
		flux_streaks,
		phase_scope,
		peak_meter,
		plasma_weave,
		hyperspace,
		mirror_shard,
		spectrum_fire,
		ripple_pool,
		orb_garden,
		sync_test,
	]

	## The presets' names, in order.
	names : List(Str)
	names = Presets.all.map(|p| p.name)

	## The preset named `name`, or the first.
	named : Str -> Preset
	named = |name|
		match Presets.all.find_first(|p| p.name == name) {
			Ok(p) => p
			Err(_) => liquid_drift
		}

	## A preset's params as a line: each name and its range.
	ranges : Preset -> Str
	ranges = |p|
		if p.params.is_empty() {
			"No params."
		} else {
			Str.join_with(p.params.map(|param| "${param.name} ${param.low.to_str()}–${param.high.to_str()}"), " · ")
		}
}

# --- Shared pieces of the scenes ---

## Every scene is 1000 by 625 units (16:10), fitted to the surface.
space : Ui.Space
space = Fit({ width: 1000, height: 625 })

## The scene's centre.
cx : F64
cx = 500

cy : F64
cy = 312.5

hex : U32 -> Ui.Color
hex = |rgb| Adaptive({ light: rgb, dark: rgb })

## A param fixed at `v`.
fixed : Str, F64, F64, F64, Str -> Presets.Param
fixed = |name, v, low, high, about| { name, number: Value(v), low, high, about }

## A turn a second-ish: `synthetic.level` rises from 0 to 1 every four
## seconds (and only on a spec's steps), so `turns` whole turns of it wrap
## without a jump.
spin : F64 -> Ui.Number
spin = |turns| Source({ source: "synthetic.level", scale: turns * 6.283185307179586, offset: 0 })

## A ring of a series around the centre.
ring : Str, F64, F64, Ui.Color, F64 -> Ui.Mark
ring = |source, radius, depth, color, width| Stroke(Ring({ source, x: 0, y: 0, radius, depth, low: -0.5, high: 0.5 }), { color, width: Value(width) })

## A wave of a series across an area.
wave : Str, Ui.Area, Ui.Color, F64 -> Ui.Mark
wave = |source, area, color, width| Stroke(Wave({ source, area, low: -0.6, high: 0.6 }), { color, width: Value(width) })

## Marks about the centre, turned and scaled.
about_centre : Ui.Number, Ui.Number, List(Ui.Mark) -> List(Ui.Mark)
about_centre = |angle, size, marks| [Save, Translate(Value(cx), Value(cy)), Rotate(angle), Scale(size, size)].concat(marks).concat([Restore])

# --- 1. Liquid Drift ---

liquid_drift : Presets.Preset
liquid_drift = {
	name: "Liquid Drift",
	about: "The picture flows through a slowly turning field, lunges outward on every kick, and drifts round the colour wheel as it fades.",
	background: hex(0x05060f),
	space,
	scene: about_centre(spin(1), Source({ source: "audio.bass", scale: 0.5, offset: 0.75 }), [ring("audio.waveform", 110, 70, hex(0x38e8ff), 3)])
		.concat([wave("audio.waveform", { x: 150, y: 262, width: 700, height: 100 }, hex(0xff3fb4), 2)]),
	trail: Trail({ half_life_ms: 380, zoom: 1.35, turn: 0.35, shift: { x: 0, y: 0 } }),
	warp: Some(liquid_drift_warp),
	composite: Some(soft_glow),
	params: [
		fixed("zoom", 0.004, 0, 0.02, "how far the picture flows outward a frame"),
		{ name: "push", number: Source({ source: "audio.bass", scale: 0.03, offset: 0 }), low: 0, high: 0.03, about: "the extra outward lunge, from the bass" },
		fixed("drift", 0.0025, 0, 0.01, "how far round the colour wheel each frame turns"),
		fixed("decay", 0.975, 0.9, 0.995, "how much of the picture a frame keeps"),
		fixed("glow", 0.55, 0, 1.5, "how much the composite's bloom adds"),
	],
}

liquid_drift_warp : Str
liquid_drift_warp =
	\\// Liquid Drift's warp: every pixel takes its colour from a point a
	\\// little nearer the centre, turned by an amount that changes with the
	\\// radius and with time, so the picture pours outward in slow eddies.
	\\float4 warp(Frame f, Params p) {
	\\    float k = min(f.dt * 60.0, 4.0);           // this frame in 60ths of a second
	\\    float2 c = centered(f);
	\\    float2 ra = polar(c);
	\\    // A zoom: sampling nearer the centre makes the picture grow.
	\\    float zoom = 1.0 - (p.zoom + p.push * smoothstep(0.55, 0.95, f.bass)) * k;
	\\    // A turn that is faster near the middle and reverses slowly.
	\\    float turn = 0.006 * sin(f.time * 0.23) * k * (1.2 - ra.x);
	\\    // A ripple in the radius that runs round the picture.
	\\    float ripple = 1.0 + 0.004 * k * sin(ra.y * 5.0 + f.time * 0.8) * sin(ra.x * 7.0 - f.time * 1.3);
	\\    float2 q = cartesian(float2(ra.x * zoom * ripple, ra.y + turn));
	\\    // And a slow wander, like a current.
	\\    q += 0.0025 * k * float2(sin(c.y * 3.1 + f.time * 0.9), cos(c.x * 2.7 - f.time * 0.7));
	\\    float3 old = sample(f, uv_of(f, q)).rgb;
	\\    // The colours turn round the wheel as they fade.
	\\    float3 hsv = rgb2hsv(old);
	\\    hsv.x = fract(hsv.x + p.drift * k);
	\\    float3 rgb = hsv2rgb(hsv) * pow(p.decay, k);
	\\    return opaque(rgb - 1.5 / 255.0);
	\\}

## A composite shared by several presets: a bloom added, then a soft
## shoulder in place of clipping.
soft_glow : Str
soft_glow =
	\\// A soft bloom: the frame plus a wide blur of itself, then a curve that
	\\// rolls the brightest parts off gently instead of clipping them.
	\\float4 composite(Frame f, Params p) {
	\\    float3 c = sample(f, f.uv).rgb;
	\\    float3 wide = blur(f, f.uv, 9.0).rgb;
	\\    float3 col = c + wide * p.glow;
	\\    return opaque(1.0 - exp(-col * 1.6));
	\\}

# --- 2. Blur Corridor ---

blur_corridor : Presets.Preset
blur_corridor = {
	name: "Blur Corridor",
	about: "A smoky tunnel: the old picture blurs and rushes toward you, faster on the beat, through a palette that keeps cycling.",
	background: hex(0x000000),
	space,
	scene: [
		wave("audio.waveform", { x: 100, y: 237, width: 800, height: 150 }, hex(0xffd040), 3),
	]
		.concat(about_centre(spin(-1), Value(1), [ring("audio.bands", 60, 50, hex(0xff7a20), 2)])),
	trail: Trail({ half_life_ms: 300, zoom: 1.9, turn: 0, shift: { x: 0, y: 0 } }),
	warp: Some(blur_corridor_warp),
	composite: Some(blur_corridor_composite),
	params: [
		fixed("speed", 0.012, 0, 0.04, "how fast the tunnel rushes outward"),
		{ name: "kick", number: Source({ source: "audio.bass", scale: 0.025, offset: 0 }), low: 0, high: 0.025, about: "the extra rush on the beat" },
		fixed("decay", 0.955, 0.9, 0.99, "how much of the smoke a frame keeps"),
		fixed("cycle", 0.04, 0, 0.2, "how fast the palette cycles, a second"),
	],
}

blur_corridor_warp : Str
blur_corridor_warp =
	\\// Blur Corridor's warp keeps one channel of brightness: the old picture,
	\\// pulled outward from the centre and blurred, so every line becomes a
	\\// smoky ring rushing past. The composite colours it.
	\\float4 warp(Frame f, Params p) {
	\\    float k = min(f.dt * 60.0, 4.0);
	\\    float2 c = centered(f);
	\\    float rush = 1.0 - (p.speed + p.kick * smoothstep(0.5, 0.95, f.bass)) * k;
	\\    float2 q = rotate(c * rush, 0.004 * k * sin(f.time * 0.3));
	\\    float v = blur(f, uv_of(f, q), 1.6).r;
	\\    v = v * pow(p.decay, k) - 0.8 / 255.0;
	\\    return opaque(float3(v));
	\\}

blur_corridor_composite : Str
blur_corridor_composite =
	\\// The brightness through a cycling palette: dark smoke is deep colour,
	\\// and the brightest burns towards white.
	\\float4 composite(Frame f, Params p) {
	\\    float v = sample(f, f.uv).r;
	\\    float t = v * 0.9 + f.time * p.cycle;
	\\    float3 col = palette(t, float3(0.5), float3(0.5), float3(1.0), float3(0.0, 0.33, 0.67));
	\\    col *= smoothstep(0.0, 0.55, v);
	\\    col += pow(v, 3.0) * 0.5;
	\\    return opaque(col);
	\\}

# --- 3. Superscope Bloom ---

superscope_bloom : Presets.Preset
superscope_bloom = {
	name: "Superscope Bloom",
	about: "Three waveform curves spin against each other and breathe with the bass, and every radius of the picture turns at its own speed.",
	background: hex(0x020308),
	space,
	scene: about_centre(spin(1), Source({ source: "audio.bass", scale: 0.6, offset: 0.7 }), [ring("audio.waveform", 150, 110, hex(0x9dff3a), 2.5)])
		.concat(about_centre(spin(-2), Value(1), [ring("audio.left", 80, 60, hex(0x3ad8ff), 2)]))
		.concat(about_centre(spin(3), Source({ source: "audio.mids", scale: 0.3, offset: 0.85 }), [ring("audio.right", 230, 50, hex(0xff4fd8), 1.5)])),
	trail: Trail({ half_life_ms: 220, zoom: 1.1, turn: -0.6, shift: { x: 0, y: 0 } }),
	warp: Some(superscope_warp),
	composite: Some(soft_glow),
	params: [
		fixed("twist", 0.012, 0, 0.05, "how far each radius turns a frame, at most"),
		fixed("breathe", 0.012, 0, 0.04, "how far the picture breathes in and out with the bass"),
		fixed("decay", 0.93, 0.85, 0.98, "how much of the picture a frame keeps"),
		fixed("glow", 0.8, 0, 1.5, "how much the composite's bloom adds"),
	],
}

superscope_warp : Str
superscope_warp =
	\\// Superscope Bloom's movement: each radius turns at its own rate, a
	\\// wave running out through the rings, while the whole picture breathes
	\\// in on quiet and out on the bass.
	\\float4 warp(Frame f, Params p) {
	\\    float k = min(f.dt * 60.0, 4.0);
	\\    float2 ra = polar(centered(f));
	\\    ra.y += p.twist * k * sin(ra.x * 6.0 - f.time * 1.7);
	\\    float beat = smoothstep(0.5, 0.95, f.bass);
	\\    ra.x *= 1.0 + p.breathe * k * (0.4 - beat);
	\\    float3 old = sample(f, uv_of(f, cartesian(ra))).rgb;
	\\    // A little colour bleeds towards violet as it fades.
	\\    old = mix(old, old.bgr, 0.03 * k);
	\\    return opaque(old * pow(p.decay, k) - 1.5 / 255.0);
	\\}

# --- 4. Flux Streaks ---

flux_streaks : Presets.Preset
flux_streaks = {
	name: "Flux Streaks",
	about: "The waveform is dragged along a swirling field of currents into long luminous streaks that change colour as they go.",
	background: hex(0x000000),
	space,
	scene: [
		wave("audio.waveform", { x: 80, y: 212, width: 840, height: 200 }, hex(0xff8a1f), 2.5),
		wave("audio.left", { x: 250, y: 150, width: 500, height: 120 }, hex(0x2fd4ff), 1.5),
		wave("audio.right", { x: 250, y: 355, width: 500, height: 120 }, hex(0xc65bff), 1.5),
	],
	trail: Trail({ half_life_ms: 600, zoom: 1, turn: 0, shift: { x: 0, y: -40 } }),
	warp: Some(flux_warp),
	composite: Some(flux_composite),
	params: [
		fixed("scale", 1.3, 0.5, 3, "how large the currents' swirls are"),
		{ name: "speed", number: Source({ source: "audio.mids", scale: 0.004, offset: 0.002 }), low: 0.002, high: 0.006, about: "how fast the currents carry the picture, from the mids" },
		fixed("decay", 0.985, 0.95, 0.995, "how much of the streaks a frame keeps"),
	],
}

flux_warp : Str
flux_warp =
	\\// The currents: the curl of a stream function made of a few drifting
	\\// waves, so the flow swirls round without ever piling up or thinning
	\\// out. Each wave's slope is written out, so it costs a handful of sines.
	\\float2 flow(float2 q, float t) {
	\\    // psi = sin(1.3x + t) cos(1.7y - 0.8t) + 0.5 sin(2.9x - 2.3y + 1.1t) + 0.35 cos(4.1x + 3.7y - 0.6t)
	\\    float a = 1.3 * q.x + t, b = 1.7 * q.y - 0.8 * t;
	\\    float c = 2.9 * q.x - 2.3 * q.y + 1.1 * t;
	\\    float d = 4.1 * q.x + 3.7 * q.y - 0.6 * t;
	\\    float dx = 1.3 * cos(a) * cos(b) + 0.5 * 2.9 * cos(c) - 0.35 * 4.1 * sin(d);
	\\    float dy = -1.7 * sin(a) * sin(b) - 0.5 * 2.3 * cos(c) - 0.35 * 3.7 * sin(d);
	\\    // The curl, (d psi / dy, -d psi / dx), turns along the contours.
	\\    return float2(dy, -dx) * 0.5;
	\\}
	\\
	\\// Flux Streaks' warp: each pixel looks back along the current, so the
	\\// picture is carried forward, and its hue moves on as it fades.
	\\float4 warp(Frame f, Params p) {
	\\    float k = min(f.dt * 60.0, 4.0);
	\\    float2 c = centered(f);
	\\    float2 v = flow(c * p.scale, f.time * 0.2);
	\\    float3 old = sample(f, uv_of(f, c - v * p.speed * k)).rgb;
	\\    float3 hsv = rgb2hsv(old);
	\\    hsv.x = fract(hsv.x + 0.0012 * k);
	\\    hsv.z = hsv.z * pow(p.decay, k) - 1.0 / 255.0;
	\\    return opaque(hsv2rgb(max(hsv, 0.0)));
	\\}

flux_composite : Str
flux_composite =
	\\// Richer colour and a dark edge: saturation is pushed up and the
	\\// corners fall away.
	\\float4 composite(Frame f, Params p) {
	\\    float3 c = sample(f, f.uv).rgb + blur(f, f.uv, 5.0).rgb * 0.4;
	\\    float grey = dot(c, float3(0.299, 0.587, 0.114));
	\\    c = mix(float3(grey), c, 1.35);
	\\    float edge = 1.0 - 0.45 * pow(length(f.uv - 0.5) * 1.4, 2.0);
	\\    return opaque((1.0 - exp(-c * 1.5)) * edge);
	\\}

# --- 5. Phase Scope ---

phase_scope : Presets.Preset
phase_scope = {
	name: "Phase Scope",
	about: "A stereo vectorscope: left against right traced in glowing phosphor, upright for mono and blooming wide as the stereo opens, the old trace aging from green to pink.",
	background: hex(0x010604),
	space,
	scene: [
		Save,
		Translate(Value(cx), Value(cy)),
		# Turned 45 degrees anticlockwise, so mono (left = right) stands upright.
		Rotate(Value(-0.7853981633974483)),
		Scale(Source({ source: "audio.level", scale: 0.6, offset: 0.7 }), Source({ source: "audio.level", scale: 0.6, offset: 0.7 })),
		Save,
		Opacity(Value(0.45)),
		Stroke(Lissajous({ across: "audio.left", down: "audio.right", area: { x: -170, y: -170, width: 340, height: 340 }, low: -0.6, high: 0.6 }), { color: hex(0x2dffb0), width: Value(5) }),
		Restore,
		Stroke(Lissajous({ across: "audio.left", down: "audio.right", area: { x: -170, y: -170, width: 340, height: 340 }, low: -0.6, high: 0.6 }), { color: hex(0x9dffd8), width: Value(1.2) }),
		Restore,
	],
	trail: Trail({ half_life_ms: 140, zoom: 1.02, turn: 0, shift: { x: 0, y: 0 } }),
	warp: Some(phase_warp),
	composite: Some(phase_composite),
	params: [
		fixed("decay", 0.84, 0.7, 0.95, "how much of the phosphor a frame keeps"),
		fixed("age", 0.08, 0, 0.3, "how fast old trace turns from green to pink, a frame"),
		fixed("spread", 1.2, 0, 3, "how far old trace blurs a frame, in pixels"),
	],
}

phase_warp : Str
phase_warp =
	\\// Phase Scope's warp is the phosphor: the scene draws the trace (a
	\\// Lissajous of the two channels), and here the old trace spreads a
	\\// little, fades, and turns from green toward pink as it ages, so the
	\\// figure leaves a soft, colour-shifting afterglow.
	\\float4 warp(Frame f, Params p) {
	\\    float k = min(f.dt * 60.0, 4.0);
	\\    float3 old = blur(f, f.uv, p.spread).rgb;
	\\    float glow = max(old.r, max(old.g, old.b));
	\\    float3 aged = glow * float3(1.0, 0.3, 0.7);
	\\    float3 col = mix(old, aged, saturate(p.age * k));
	\\    return opaque(col * pow(p.decay, k) - 1.0 / 255.0);
	\\}

phase_composite : Str
phase_composite =
	\\// A graticule behind the trace, and a bloom over it.
	\\float4 composite(Frame f, Params p) {
	\\    float2 c = centered(f);
	\\    float3 col = sample(f, f.uv).rgb + blur(f, f.uv, 7.0).rgb * 0.7;
	\\    float r = length(c);
	\\    float rings = smoothstep(0.004, 0.0, abs(fract(r * 4.0 + 0.5) - 0.5) / 4.0) * step(r, 1.0);
	\\    float axes = smoothstep(0.003, 0.0, min(abs(c.x), abs(c.y))) * step(r, 1.0);
	\\    float diag = smoothstep(0.003, 0.0, min(abs(c.x - c.y), abs(c.x + c.y)) * 0.7071) * step(r, 1.0);
	\\    col += float3(0.05, 0.16, 0.12) * max(rings, axes) + float3(0.08, 0.05, 0.1) * diag;
	\\    return opaque(1.0 - exp(-col * 1.4));
	\\}

# --- 6. Peak Meter ---

peak_meter : Presets.Preset
peak_meter = {
	name: "Peak Meter",
	about: "A segmented spectrum of 24 bars in green, amber and red, each with a cap that falls slowly after its peak, mirrored in a glossy floor.",
	background: hex(0x07080b),
	space,
	scene: meter_bars,
	trail: NoTrail,
	warp: Some(peak_warp),
	composite: Some(peak_composite),
	params: [
		fixed("fall", 0.35, 0.1, 1.5, "how fast a cap falls, in heights a second"),
		fixed("floor", 0.74, 0.6, 0.9, "where the floor is, down the surface"),
		fixed("shine", 0.3, 0, 0.6, "how bright the reflection is"),
	],
}

## The bars and their reflection, for Core Graphics.
meter_bars : List(Ui.Mark)
meter_bars = {
	bars = Fill(Bars({ source: "audio.bands", area: { x: 60, y: 90, width: 880, height: 370 }, low: 0, high: 1, gap: 10 }), hex(0x34e05a))
	tops = Fill(Bars({ source: "audio.bands", area: { x: 60, y: 90, width: 880, height: 370 }, low: 0.6, high: 1.6, gap: 10 }), hex(0xffc030))
	# y' = 621 - 0.35 y mirrors the bars below their floor, at 460, squashed.
	[bars, tops, Save, Matrix({ a: 1, b: 0, c: 0, d: -0.35, tx: 0, ty: 621 }), Opacity(Value(0.3)), bars, Restore]
}

peak_warp : Str
peak_warp =
	\\// Peak Meter keeps one number per band in the history: its cap's height,
	\\// in row 0 of the picture, in two channels for 16 bits. Each frame a cap
	\\// falls at `fall` heights a second, and the band's level pushes it up.
	\\// Nothing else is kept: the composite draws the rest from the bands.
	\\float4 warp(Frame f, Params p) {
	\\    if (f.pixel.y > 1.0) return float4(0.0, 0.0, 0.0, 1.0);
	\\    int band = clamp(int(f.uv.x * 24.0), 0, 23);
	\\    float cap = unpack(fetch(f, int2(f.pixel)).rg);
	\\    cap = max(cap - p.fall * f.dt, band_at(f, band));
	\\    return float4(pack(cap), 0.0, 1.0);
	\\}

peak_composite : Str
peak_composite =
	\\// One band's column at height `h` (0 at the floor, 1 at the top): lit
	\\// segments up to its level, green to amber to red, and its cap.
	\\float3 column(Frame f, float h, float level, float cap) {
	\\    if (h < 0.0 || h > 1.0) return float3(0.0);
	\\    float segment = step(0.28, fract(h * 30.0));
	\\    float3 hue = mix(float3(0.15, 0.95, 0.3), float3(1.0, 0.8, 0.15), smoothstep(0.35, 0.7, h));
	\\    hue = mix(hue, float3(1.0, 0.2, 0.12), smoothstep(0.78, 0.95, h));
	\\    float3 lit = hue * step(h, level) * segment;
	\\    float3 unlit = hue * 0.07 * segment;
	\\    float capped = step(abs(h - cap - 0.012), 0.007) * step(0.015, cap);
	\\    return max(lit, unlit) + float3(0.9, 0.95, 1.0) * capped;
	\\}
	\\
	\\// Peak Meter's screen: 24 columns standing on a floor, their caps from
	\\// row 0, and below the floor their reflection, darker and rippling.
	\\float4 composite(Frame f, Params p) {
	\\    float top = 0.1;
	\\    float x = f.uv.x * 1.08 - 0.04;
	\\    int band = clamp(int(x * 24.0), 0, 23);
	\\    float cell = fract(x * 24.0);
	\\    float inside = step(0.0, x) * step(x, 1.0) * step(0.14, cell) * step(cell, 0.86);
	\\    float level = band_at(f, band);
	\\    float cap = unpack(fetch(f, int2((float(band) + 0.5) / 24.0 * f.size.x, 0)).rg);
	\\    float h = (p.floor - f.uv.y) / (p.floor - top);
	\\    // A cool gradient behind, with faint scan lines.
	\\    float3 col = mix(float3(0.02, 0.03, 0.06), float3(0.05, 0.03, 0.08), f.uv.y);
	\\    col *= 0.85 + 0.15 * step(0.5, fract(f.pixel.y / 3.0));
	\\    if (h >= 0.0) {
	\\        col += column(f, h, level, cap) * inside;
	\\    } else {
	\\        float mirrored = -h * 2.6 + 0.01 * sin(f.uv.y * 140.0 + f.time * 2.0);
	\\        float fade = exp(h * 9.0) * p.shine;
	\\        col += column(f, mirrored, level, cap) * inside * fade;
	\\        col += float3(0.25, 0.3, 0.4) * smoothstep(0.004, 0.0, abs(h)) ;
	\\    }
	\\    if (f.pixel.y < 1.0) col = float3(0.02, 0.03, 0.06);
	\\    return opaque(col);
	\\}

# --- 7. Plasma Weave ---

plasma_weave : Presets.Preset
plasma_weave = {
	name: "Plasma Weave",
	about: "Interfering waves of colour that churn faster with the mids and break into bright filaments on the treble, the waveform glowing across them.",
	background: hex(0x1a0630),
	space,
	scene: [
		wave("audio.waveform", { x: 60, y: 237, width: 880, height: 150 }, hex(0xfff2d0), 3),
		Save,
		Opacity(Value(0.6)),
		Fill(Bars({ source: "audio.bands", area: { x: 0, y: 425, width: 1000, height: 200 }, low: 0, high: 1, gap: 6 }), hex(0xff4fa0)),
		Restore,
	],
	trail: NoTrail,
	warp: None,
	composite: Some(plasma_composite),
	params: [
		fixed("scale", 1.6, 0.5, 4, "how fine the plasma's waves are"),
		{ name: "churn", number: Source({ source: "audio.mids", scale: 1.4, offset: 0.3 }), low: 0.3, high: 1.7, about: "how fast it moves, from the mids" },
		{ name: "spark", number: Source({ source: "audio.treble", scale: 1, offset: 0 }), low: 0, high: 1, about: "how bright its filaments are, from the treble" },
	],
}

plasma_composite : Str
plasma_composite =
	\\// Plasma Weave: four sine fields summed, their phase a running clock, so
	\\// the pattern churns; the sum through a palette that slowly turns.
	\\// The time a moment of churn has run is not kept, so the speed changes
	\\// the clock's rate a little at a time rather than jumping.
	\\float4 composite(Frame f, Params p) {
	\\    float2 c = centered(f) * p.scale;
	\\    float t = f.time * 0.55 + sin(f.time * 0.13) * 2.0;
	\\    float s = 0.7 + 0.3 * p.churn;
	\\    float v = sin(c.x * 3.0 + t * s)
	\\            + sin(c.y * 2.3 - t * 1.3 * s)
	\\            + sin((c.x + c.y) * 2.1 + t * 0.7)
	\\            + sin(length(c + float2(sin(t * 0.5), cos(t * 0.4)) * 1.5) * 4.0 - t * s);
	\\    v *= 0.25;
	\\    float3 col = palette(v * 0.6 + f.time * 0.025, float3(0.5), float3(0.5), float3(1.0, 0.9, 0.75), float3(0.8, 0.1, 0.35));
	\\    // Where the field crosses its contours, filaments light with the treble.
	\\    float filament = pow(1.0 - abs(sin(v * PI * 5.0)), 18.0);
	\\    col += float3(1.0, 0.9, 1.0) * filament * (0.15 + 0.9 * p.spark);
	\\    // The scene's marks glow over it.
	\\    float4 marks = sample(f, f.uv) + blur(f, f.uv, 6.0) * 0.6;
	\\    col = col * (1.0 - 0.6 * saturate(marks.a)) + marks.rgb;
	\\    return opaque(col * 0.95);
	\\}

# --- 8. Hyperspace ---

hyperspace : Presets.Preset
hyperspace = {
	name: "Hyperspace",
	about: "Stars stream out of the centre and stretch into streaks, jumping to warp speed on every bass hit.",
	background: hex(0x000005),
	space,
	scene: about_centre(spin(1), Source({ source: "audio.bass", scale: 1, offset: 0.5 }), [Opacity(Value(0.5)), ring("audio.waveform", 26, 22, hex(0x5b7cc8), 1.5)]),
	trail: Trail({ half_life_ms: 260, zoom: 3.5, turn: 0, shift: { x: 0, y: 0 } }),
	warp: Some(hyperspace_warp),
	composite: Some(hyperspace_composite),
	params: [
		fixed("speed", 0.012, 0.002, 0.04, "how fast the stars stream out, a frame"),
		{ name: "boost", number: Source({ source: "audio.bass", scale: 0.07, offset: 0 }), low: 0, high: 0.07, about: "the jump to warp speed, from the bass" },
		fixed("stars", 60, 10, 300, "new stars a frame"),
		fixed("decay", 0.94, 0.8, 0.98, "how long a streak lasts"),
	],
}

hyperspace_warp : Str
hyperspace_warp =
	\\// Hyperspace's warp: the old picture streams outward from the centre,
	\\// faster the further out, so dots become streaks; a few new stars light
	\\// at random each frame, dim near the centre and brightening as they fly.
	\\float4 warp(Frame f, Params p) {
	\\    float k = min(f.dt * 60.0, 4.0);
	\\    float2 c = centered(f);
	\\    float speed = p.speed + p.boost * smoothstep(0.55, 0.95, f.bass);
	\\    float3 old = sample(f, uv_of(f, c / (1.0 + speed * k))).rgb;
	\\    float r = length(c);
	\\    float3 col = old * pow(p.decay, k) * (1.0 + 0.012 * r * k) - 1.5 / 255.0;
	\\    // New stars: the surface is cut into cells of 5 pixels, and each cell
	\\    // lights a round dot with a chance that gives `stars` a frame.
	\\    float2 cell = floor(f.pixel / 5.0);
	\\    float chance = p.stars * k * 25.0 / (f.size.x * f.size.y);
	\\    float2 seed = float2(fract(float(f.frame) * 0.618034) * 937.0, fract(float(f.frame) * 0.414214) * 571.0);
	\\    if (hash(cell + seed) < chance) {
	\\        float dot = smoothstep(0.55, 0.1, length(fract(f.pixel / 5.0) - 0.5));
	\\        float3 tint = mix(float3(0.65, 0.8, 1.0), float3(1.0, 0.85, 0.7), hash(cell * 1.7));
	\\        col += tint * dot * (0.7 + 2.5 * r) * (1.0 + f.treble);
	\\    }
	\\    return opaque(col);
	\\}

hyperspace_composite : Str
hyperspace_composite =
	\\// A radial smear toward the centre for motion, and a glow at the
	\\// vanishing point that swells with the bass.
	\\float4 composite(Frame f, Params p) {
	\\    float2 c = centered(f);
	\\    float3 col = float3(0.0);
	\\    for (int i = 0; i < 6; i++) col += sample(f, uv_of(f, c * (1.0 - 0.012 * float(i)))).rgb * (1.0 - float(i) * 0.12);
	\\    col *= 0.42;
	\\    float r = length(c);
	\\    col += float3(0.35, 0.45, 1.0) * exp(-r * 5.0) * (0.12 + 0.35 * f.bass);
	\\    return opaque(1.0 - exp(-col * 1.5));
	\\}

# --- 9. Mirror Shard ---

mirror_shard : Presets.Preset
mirror_shard = {
	name: "Mirror Shard",
	about: "A kaleidoscope: a slowly swirling picture of the waveform and spectrum folded into turning mirrored slices.",
	background: hex(0x050208),
	space,
	scene: [
		Save,
		Translate(Value(720), Value(430)),
		Rotate(spin(-1)),
		Stroke(Ring({ source: "audio.bands", x: 0, y: 0, radius: 40, depth: 130, low: 0, high: 1 }), { color: hex(0x19c7c2), width: Value(3) }),
		Restore,
		Save,
		Translate(Value(560), Value(330)),
		Rotate(Value(0.6)),
		wave("audio.waveform", { x: 0, y: -80, width: 420, height: 160 }, hex(0xff9a2e), 3),
		Restore,
	]
		.concat(about_centre(spin(1), Value(1), [ring("audio.left", 90, 60, hex(0xff3d8b), 2.5)])),
	trail: Trail({ half_life_ms: 500, zoom: 0.85, turn: 0.5, shift: { x: 0, y: 0 } }),
	warp: Some(mirror_warp),
	composite: Some(mirror_composite),
	params: [
		fixed("slices", 8, 3, 16, "how many mirrored slices make the circle"),
		fixed("decay", 0.965, 0.9, 0.99, "how much of the picture a frame keeps"),
		{ name: "swell", number: Source({ source: "audio.bass", scale: 0.25, offset: 0 }), low: 0, high: 0.25, about: "how far the kaleidoscope swells on the bass" },
	],
}

mirror_warp : Str
mirror_warp =
	\\// Mirror Shard's warp: a gentle swirl outward with fading colour, the
	\\// raw material the kaleidoscope folds.
	\\float4 warp(Frame f, Params p) {
	\\    float k = min(f.dt * 60.0, 4.0);
	\\    float2 c = centered(f);
	\\    float2 q = rotate(c * (1.0 - 0.012 * k), 0.02 * k);
	\\    float3 old = blur(f, uv_of(f, q), 1.0).rgb;
	\\    float3 hsv = rgb2hsv(old);
	\\    hsv.x = fract(hsv.x + 0.002 * k);
	\\    return opaque(hsv2rgb(hsv) * pow(p.decay, k) - 1.5 / 255.0);
	\\}

mirror_composite : Str
mirror_composite =
	\\// Mirror Shard's screen: each pixel's angle folded into one slice and
	\\// mirrored, so `slices` copies of that slice make the circle; the slices
	\\// turn slowly and the whole swells with the bass.
	\\float4 composite(Frame f, Params p) {
	\\    float2 ra = polar(centered(f));
	\\    float slice = TAU / max(p.slices, 1.0);
	\\    float a = ra.y + f.time * 0.12;
	\\    a = a - slice * floor(a / slice);
	\\    a = min(a, slice - a);
	\\    float2 q = cartesian(float2(ra.x / (1.0 + p.swell), a + 0.35));
	\\    float3 col = sample_mirror(f, uv_of(f, q * 0.9)).rgb;
	\\    col += blur(f, uv_of(f, q * 0.9), 6.0).rgb * 0.35;
	\\    col *= 1.0 - smoothstep(0.85, 1.6, ra.x);
	\\    return opaque(1.0 - exp(-col * 1.5));
	\\}

# --- 10. Spectrum Fire ---

spectrum_fire : Presets.Preset
spectrum_fire = {
	name: "Spectrum Fire",
	about: "Demoscene fire: the spectrum burns along the bottom edge and its flames rise, flicker and cool, with the waveform licking through them.",
	background: hex(0x000000),
	space,
	scene: [
		Fill(Bars({ source: "audio.bands", area: { x: 0, y: 545, width: 1000, height: 80 }, low: 0, high: 1, gap: 2 }), hex(0xc23a0a)),
		Save,
		Opacity(Value(0.8)),
		wave("audio.waveform", { x: 0, y: 520, width: 1000, height: 90 }, hex(0xffd24a), 3),
		Restore,
	],
	trail: Trail({ half_life_ms: 240, zoom: 1, turn: 0, shift: { x: 0, y: -160 } }),
	warp: Some(fire_warp),
	composite: Some(fire_composite),
	params: [
		fixed("rise", 0.005, 0.001, 0.012, "how far the flames rise a frame, in heights"),
		fixed("cool", 0.02, 0.005, 0.04, "how much heat a frame loses"),
		{ name: "fuel", number: Source({ source: "audio.level", scale: 0.6, offset: 0.7 }), low: 0.7, high: 1.3, about: "how hot the bottom edge burns, from the level" },
	],
}

fire_warp : Str
fire_warp =
	\\// Spectrum Fire keeps heat in the red channel, as the classic demo
	\\// effect does: each pixel takes the mean heat of four pixels just below
	\\// it, jittered sideways at random every frame, and loses a little; the
	\\// loss varies with a noise that rises with the flames, which carves them
	\\// into tongues. The bottom edge is kept burning by the spectrum, and the
	\\// scene's marks (their red) add heat where they are drawn.
	\\float4 warp(Frame f, Params p) {
	\\    float k = min(f.dt * 60.0, 4.0);
	\\    float2 t = f.texel;
	\\    float jitter = (hash(f.pixel + float2(float(f.frame % 977u) * 1.31, 0.0)) - 0.5) * 3.0 * t.x;
	\\    float2 below = f.uv + float2(jitter, p.rise * k);
	\\    float heat = (sample(f, below).r + sample(f, below + float2(2.0 * t.x, 0.0)).r
	\\                + sample(f, below - float2(2.0 * t.x, 0.0)).r + sample(f, below + float2(0.0, 2.0 * t.y)).r) * 0.25;
	\\    float tongues = noise(float2(f.uv.x * 70.0, (f.uv.y + f.time * p.rise * 60.0) * 22.0));
	\\    heat -= p.cool * k * (0.2 + 1.6 * tongues * tongues);
	\\    // The fuel: the bottom edge burns as hot as each band, with a flicker.
	\\    if (f.uv.y > 0.985) {
	\\        float flicker = 0.7 + 0.6 * hash(floor(f.pixel / 4.0) + float2(float(f.frame % 977u), 3.0));
	\\        heat = max(heat, band(f, f.uv.x) * p.fuel * flicker);
	\\    }
	\\    return opaque(float3(heat));
	\\}

fire_composite : Str
fire_composite =
	\\// Heat to colour: black, deep red, orange, yellow, then white.
	\\float4 composite(Frame f, Params p) {
	\\    float h = saturate(sample(f, f.uv).r * 1.15);
	\\    float3 col = float3(saturate(h * 2.2), saturate(h * 2.2 - 0.55), saturate(h * 3.0 - 2.0));
	\\    col *= smoothstep(0.02, 0.2, h);
	\\    return opaque(col);
	\\}

# --- 11. Ripple Pool ---

ripple_pool : Presets.Preset
ripple_pool = {
	name: "Ripple Pool",
	about: "A pool of water: each beat drops a stone somewhere new, the waveform stirs the surface, and the ripples refract a glowing floor.",
	background: hex(0x02141c),
	space,
	scene: [
		Save,
		Opacity(Value(0.15)),
		wave("audio.waveform", { x: 150, y: 262, width: 700, height: 100 }, hex(0x9be8ff), 2),
		Restore,
	]
		.concat(about_centre(Value(0), Source({ source: "audio.bass", scale: 1.2, offset: 0.4 }), [ring("audio.bands", 60, 18, hex(0x4fd6e0), 2)])),
	trail: Trail({ half_life_ms: 700, zoom: 1.6, turn: 0, shift: { x: 0, y: 0 } }),
	warp: Some(ripple_warp),
	composite: Some(ripple_composite),
	params: [
		fixed("spacing", 2.5, 1, 4, "the water's grid, in pixels"),
		fixed("damping", 0.988, 0.95, 0.998, "how much of a ripple a step keeps"),
		fixed("threshold", 0.06, 0.02, 0.2, "how far the bass must jump over its average to drop a stone"),
		fixed("refraction", 0.06, 0, 0.2, "how far the ripples bend the floor"),
	],
}

ripple_warp : Str
ripple_warp =
	\\// Ripple Pool runs the wave equation in the history: red is the water's
	\\// height now, green its height a frame ago, both around 0.5. Each step
	\\// the new height is half the four neighbours' sum less the old height,
	\\// damped. Pixel (0, 0) keeps a slow average of the bass in blue: when the
	\\// bass jumps above it, a stone drops at a place picked by the frame.
	\\float4 warp(Frame f, Params p) {
	\\    float2 d = f.texel * p.spacing;
	\\    float4 here = sample(f, f.uv);
	\\    float before = here.g - 0.5;
	\\    float around = sample(f, f.uv + float2(d.x, 0.0)).r + sample(f, f.uv - float2(d.x, 0.0)).r
	\\                 + sample(f, f.uv + float2(0.0, d.y)).r + sample(f, f.uv - float2(0.0, d.y)).r - 2.0;
	\\    float next = (around * 0.5 - before) * p.damping;
	\\    float average = fetch(f, int2(0, 0)).b;
	\\    bool beat = f.bass > average + p.threshold;
	\\    if (beat) {
	\\        float2 at = 0.15 + 0.7 * float2(hash(float2(float(f.frame % 1000u), 1.0)), hash(float2(float(f.frame % 1000u), 2.0)));
	\\        float2 off = (f.uv - at) * float2(f.aspect, 1.0);
	\\        next -= 0.5 * exp(-dot(off, off) / 0.004);
	\\    }
	\\    float4 out = float4(saturate(next + 0.5), here.r, 0.0, 1.0);
	\\    if (f.pixel.x < 1.0 && f.pixel.y < 1.0) {
	\\        // A beat resets the average, so one kick drops one stone.
	\\        float k = min(f.dt * 60.0, 4.0);
	\\        out.b = beat ? f.bass : mix(average, f.bass, 0.03 * k);
	\\    }
	\\    return out;
	\\}

ripple_composite : Str
ripple_composite =
	\\// Ripple Pool's screen: the height's slope bends the view of a glowing
	\\// floor of soft light, and catches a highlight from above.
	\\float4 composite(Frame f, Params p) {
	\\    float2 d = f.texel * 2.0;
	\\    float sx = sample(f, f.uv + float2(d.x, 0.0)).r - sample(f, f.uv - float2(d.x, 0.0)).r;
	\\    float sy = sample(f, f.uv + float2(0.0, d.y)).r - sample(f, f.uv - float2(0.0, d.y)).r;
	\\    float2 slope = float2(sx, sy);
	\\    float2 uv = f.uv + slope * p.refraction * 4.0;
	\\    float2 q = uv * float2(f.aspect, 1.0) * 6.0;
	\\    // The floor: deep teal, with moving caustic light.
	\\    float caustic = pow(1.0 - abs(noise(q + f.time * 0.25) - noise(q * 1.7 - f.time * 0.2)), 6.0);
	\\    float3 col = mix(float3(0.0, 0.07, 0.12), float3(0.0, 0.3, 0.38), uv.y) + float3(0.2, 0.6, 0.65) * caustic * 0.35;
	\\    // The highlight: light from up and to the left on the slope.
	\\    float3 n = normalize(float3(-slope * 14.0, 1.0));
	\\    float spec = pow(saturate(dot(n, normalize(float3(-0.4, -0.5, 1.0)))), 60.0);
	\\    col += float3(0.85, 0.95, 1.0) * spec * 0.9;
	\\    return opaque(col);
	\\}

# --- 12. Orb Garden ---

orb_garden : Presets.Preset
orb_garden = {
	name: "Orb Garden",
	about: "Glowing orbs of magenta, teal and orange drift, merge and swell with their bands over deep purple, trailing liquid light, with spiky stars twinkling between them.",
	background: hex(0x12051f),
	space,
	scene: orb_marks,
	trail: Trail({ half_life_ms: 450, zoom: 1.05, turn: 0.25, shift: { x: 0, y: 0 } }),
	warp: Some(orb_warp),
	composite: Some(orb_composite),
	params: [
		fixed("decay", 0.94, 0.85, 0.98, "how long the orbs' liquid trails last"),
		fixed("size", 0.11, 0.05, 0.2, "an orb's size at rest, in half-heights"),
		{ name: "swell", number: Source({ source: "audio.level", scale: 0.6, offset: 0.2 }), low: 0.2, high: 0.8, about: "how far the orbs swell with their bands" },
	],
}

# --- 13. Sync Test ---

## Not a visualization: the audio/visual sync test. The screen flashes white
## as the level crosses half way, so played with a click track (the
## specs' `fixtures/sync-clicks.wav`) every click is one flash, to measure
## (host/AVTiming.swift) or to film beside the speaker.
sync_test : Presets.Preset
sync_test = {
	name: "Sync Test",
	about: "A white flash on every click of a click track: play specs/fixtures/sync-clicks.wav and film the screen beside the speaker to see how far apart they are.",
	background: hex(0x000000),
	space,
	scene: [Save, Opacity(Source({ source: "audio.level", scale: 1, offset: 0 })), Fill(Rect({ x: 0, y: 0, width: 1000, height: 625 }), hex(0xffffff)), Restore],
	trail: NoTrail,
	warp: None,
	composite: Some(
		\\// White while the level is at least half way, black otherwise: a hard
		\\// edge, so the frame a flash starts on is unmistakable.
		\\float4 composite(Frame f, Params p) {
		\\    return opaque(float3(f.level >= 0.5 ? 1.0 : 0.0));
		\\}
	),
	params: [],
}

## Core Graphics' orbs: a disc for each colour, riding a band.
orb_marks : List(Ui.Mark)
orb_marks = {
	orb = |x, y, band, color, r| [
		Save,
		Translate(Value(x), Element({ source: "audio.bands", index: band, scale: -60, offset: y })),
		Scale(Element({ source: "audio.bands", index: band, scale: 0.8, offset: 0.6 }), Element({ source: "audio.bands", index: band, scale: 0.8, offset: 0.6 })),
		Save,
		Opacity(Value(0.35)),
		Fill(Oval({ x: -r * 1.6, y: -r * 1.6, width: r * 3.2, height: r * 3.2 }), color),
		Restore,
		Fill(Oval({ x: -r, y: -r, width: r * 2, height: r * 2 }), color),
		Restore,
	]
	orb(300, 260, 2, hex(0xff3fc8), 55)
		.concat(orb(520, 360, 9, hex(0x22e0d0), 45))
		.concat(orb(700, 240, 16, hex(0xff9a2a), 40))
		.concat(about_centre(spin(1), Value(1), [ring("audio.waveform", 200, 40, hex(0x7a4cff), 1.5)]))
}

orb_warp : Str
orb_warp =
	\\// Where orb `i` is at time `t`: each wanders on its own slow figure.
	\\float2 orb_at(int i, float t) {
	\\    float fi = float(i);
	\\    return float2(sin(t * 0.29 * (1.0 + fi * 0.21) + fi * 1.7) * 1.05,
	\\                  cos(t * 0.23 * (1.0 + fi * 0.17) + fi * 2.9) * 0.62);
	\\}
	\\
	\\// Orb Garden's warp: the old picture drifts on slow noise and fades,
	\\// leaving liquid trails, and six metaballs are drawn over it: their
	\\// fields add, so near each other they merge, and each is coloured by
	\\// how much of the field is its own.
	\\float4 warp(Frame f, Params p) {
	\\    float k = min(f.dt * 60.0, 4.0);
	\\    float2 c = centered(f);
	\\    float2 drift = float2(noise(c * 2.2 + f.time * 0.2), noise(c * 2.2 - f.time * 0.17 + 9.0)) - 0.5;
	\\    float3 old = sample(f, uv_of(f, c + drift * 0.008 * k)).rgb * pow(p.decay, k) - 1.0 / 255.0;
	\\    float3 colours[3] = { float3(1.0, 0.22, 0.78), float3(0.12, 0.9, 0.82), float3(1.0, 0.58, 0.15) };
	\\    float field = 0.0;
	\\    float3 tint = float3(0.0);
	\\    for (int i = 0; i < 6; i++) {
	\\        float r = p.size * (0.7 + p.swell * band_at(f, i * 4 + 1));
	\\        float2 off = c - orb_at(i, f.time);
	\\        float w = r * r / (dot(off, off) + 1e-4);
	\\        field += w;
	\\        tint += w * colours[i % 3];
	\\    }
	\\    tint /= max(field, 1e-4);
	\\    float body = smoothstep(0.8, 1.3, field);
	\\    float halo = saturate(field * 0.35) * (1.0 - body);
	\\    float3 col = max(old, tint * (body * 0.85 + halo * 0.5));
	\\    // A bright rim where the surface of the merged blob is.
	\\    col += tint * smoothstep(0.25, 0.0, abs(field - 1.0)) * 0.35;
	\\    return opaque(col);
	\\}

orb_composite : Str
orb_composite =
	\\// Where star `i` is: a slow drift across the whole surface.
	\\float2 star_at(int i, float t) {
	\\    float fi = float(i);
	\\    return float2(sin(t * 0.07 * (1.0 + fi * 0.3) + fi * 2.1) * 1.4, cos(t * 0.09 * (1.0 + fi * 0.2) + fi * 1.3) * 0.8);
	\\}
	\\
	\\// Orb Garden's screen: deep purple behind, the orbs with a bloom, and
	\\// five spiky stars whose points lengthen with the treble.
	\\float4 composite(Frame f, Params p) {
	\\    float2 c = centered(f);
	\\    float3 col = mix(float3(0.09, 0.02, 0.16), float3(0.03, 0.0, 0.07), length(c) * 0.6);
	\\    float3 orbs = sample(f, f.uv).rgb + blur(f, f.uv, 10.0).rgb * 0.6;
	\\    col += orbs;
	\\    for (int i = 0; i < 5; i++) {
	\\        float2 off = c - star_at(i, f.time);
	\\        // Far from a star its glow is nothing: skip the costly part.
	\\        if (dot(off, off) > 0.5) continue;
	\\        float2 ra = polar(off);
	\\        // cos^24 by squaring, much cheaper than pow.
	\\        float s = cos(ra.y * 3.0 + f.time * (0.3 + 0.1 * float(i)));
	\\        s *= s; s *= s; s *= s;
	\\        float points = s * s * s;
	\\        float reach = 0.012 + (0.05 + 0.12 * f.treble) * points;
	\\        float glow = exp(-ra.x / reach) * (0.6 + 0.4 * sin(f.time * 2.0 + float(i) * 1.9));
	\\        float3 tint = (i % 2 == 0) ? float3(1.0, 0.75, 0.4) : float3(0.5, 1.0, 0.95);
	\\        col += tint * glow * 0.9;
	\\    }
	\\    return opaque(1.0 - exp(-col * 1.5));
	\\}

## Twelve, each named once, each with shaders, a scene and a description.
expect {
	names = Presets.names
	unique = names.fold([], |seen, n| if (seen.contains(n)) seen else seen.append(n))
	names.len() == 13 and unique.len() == 13 and Presets.all.all(|p| !p.scene.is_empty() and !p.about.is_empty() and (p.warp != None or p.composite != None))
}

## A preset's params cross as its shader's, in order.
expect
	match Presets.shader(Presets.named("Peak Meter")) {
		Shaders({ params, warp: Some(_), composite: Some(_) }) => params.map(|(name, _)| name) == ["fall", "floor", "shine"]
		_ => Bool.False
	}
