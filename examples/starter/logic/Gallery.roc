import Preset

## The Metal presets from the platform's visualizer example, represented
## as `Preset.Doc` values. Each pairs shader source and params with layers
## and feedback for the Core Graphics fallback.
##
## Params that follow audio map a measurement from 0 to 1 onto a range
## shared with the editor slider. Scale motion by the time since the last
## frame to keep it consistent across refresh rates.
## https://lukewilliamboswell.github.io/roc-native-macos/ui.html#shaders
Gallery := [].{

	## The twelve, in the gallery's order.
	all : List(Preset.Doc)
	all = [Gallery.liquid_drift, Gallery.blur_corridor, Gallery.superscope_bloom, Gallery.flux_streaks, Gallery.phase_scope, Gallery.peak_meter, Gallery.plasma_weave, Gallery.hyperspace, Gallery.mirror_shard, Gallery.spectrum_fire, Gallery.ripple_pool, Gallery.orb_garden]

	## The picture flows through a slowly turning field, lunges outward on
	## every kick, and drifts round the colour wheel as it fades.
	liquid_drift : Preset.Doc
	liquid_drift = {
		id: "builtin.liquid-drift",
		name: "Liquid Drift",
		background: { r: 0x05, g: 0x06, b: 0x0F },
		layers: [
			{ ..Preset.layer(CircularWaveform), colors: [{ r: 0x38, g: 0xE8, b: 0xFF }], size: 150, thickness: 30, opacity: 100, rotation: 0, mappings: [{ feature: Bass, property: Size, from: 150, to: 260 }] },
			{ ..Preset.layer(Waveform), colors: [{ r: 0xFF, g: 0x3F, b: 0xB4 }], size: 160, thickness: 20, opacity: 100, rotation: 0, mappings: [] },
		],
		feedback: { enabled: Bool.True, zoom: 1350, rotation: 20, half_life_ms: 380 },
		shaders: Shaders({
			warp: Some(Gallery.liquid_drift_warp),
			composite: Some(Gallery.soft_glow),
			params: [
				{ name: "zoom", value: 0.004, low: 0.0, high: 0.02, follows: Fixed, about: "how far the picture flows outward a frame" },
				{ name: "push", value: 0.0, low: 0.0, high: 0.03, follows: Feature(Bass), about: "the extra outward lunge, from the bass" },
				{ name: "drift", value: 0.0025, low: 0.0, high: 0.01, follows: Fixed, about: "how far round the colour wheel each frame turns" },
				{ name: "decay", value: 0.975, low: 0.9, high: 0.995, follows: Fixed, about: "how much of the picture a frame keeps" },
				{ name: "glow", value: 0.55, low: 0.0, high: 1.5, follows: Fixed, about: "how much the composite's bloom adds" },
			],
		}),
	}

	## A smoky tunnel: the old picture blurs and rushes toward you, faster on
	## the beat, through a palette that keeps cycling.
	blur_corridor : Preset.Doc
	blur_corridor = {
		id: "builtin.blur-corridor",
		name: "Blur Corridor",
		background: { r: 0x00, g: 0x00, b: 0x00 },
		layers: [
			{ ..Preset.layer(Waveform), colors: [{ r: 0xFF, g: 0xD0, b: 0x40 }], size: 240, thickness: 30, opacity: 100, rotation: 0, mappings: [] },
			{ ..Preset.layer(Ring), colors: [{ r: 0xFF, g: 0x7A, b: 0x20 }], size: 100, thickness: 20, opacity: 100, rotation: 0, mappings: [{ feature: Level, property: Size, from: 80, to: 180 }] },
		],
		feedback: { enabled: Bool.True, zoom: 1900, rotation: 0, half_life_ms: 300 },
		shaders: Shaders({
			warp: Some(Gallery.blur_corridor_warp),
			composite: Some(Gallery.blur_corridor_composite),
			params: [
				{ name: "speed", value: 0.012, low: 0.0, high: 0.04, follows: Fixed, about: "how fast the tunnel rushes outward" },
				{ name: "kick", value: 0.0, low: 0.0, high: 0.025, follows: Feature(Bass), about: "the extra rush on the beat" },
				{ name: "decay", value: 0.955, low: 0.9, high: 0.99, follows: Fixed, about: "how much of the smoke a frame keeps" },
				{ name: "cycle", value: 0.04, low: 0.0, high: 0.2, follows: Fixed, about: "how fast the palette cycles, a second" },
			],
		}),
	}

	## Three waveform curves spin against each other and breathe with the bass,
	## and every radius of the picture turns at its own speed.
	superscope_bloom : Preset.Doc
	superscope_bloom = {
		id: "builtin.superscope-bloom",
		name: "Superscope Bloom",
		background: { r: 0x02, g: 0x03, b: 0x08 },
		layers: [
			{ ..Preset.layer(CircularWaveform), colors: [{ r: 0x9D, g: 0xFF, b: 0x3A }], size: 200, thickness: 25, opacity: 100, rotation: 0, mappings: [{ feature: Bass, property: Size, from: 180, to: 320 }] },
		],
		feedback: { enabled: Bool.True, zoom: 1100, rotation: -34, half_life_ms: 220 },
		shaders: Shaders({
			warp: Some(Gallery.superscope_warp),
			composite: Some(Gallery.soft_glow),
			params: [
				{ name: "twist", value: 0.012, low: 0.0, high: 0.05, follows: Fixed, about: "how far each radius turns a frame, at most" },
				{ name: "breathe", value: 0.012, low: 0.0, high: 0.04, follows: Fixed, about: "how far the picture breathes in and out with the bass" },
				{ name: "decay", value: 0.93, low: 0.85, high: 0.98, follows: Fixed, about: "how much of the picture a frame keeps" },
				{ name: "glow", value: 0.8, low: 0.0, high: 1.5, follows: Fixed, about: "how much the composite's bloom adds" },
			],
		}),
	}

	## The waveform is dragged along a swirling field of currents into long
	## luminous streaks that change colour as they go.
	flux_streaks : Preset.Doc
	flux_streaks = {
		id: "builtin.flux-streaks",
		name: "Flux Streaks",
		background: { r: 0x00, g: 0x00, b: 0x00 },
		layers: [
			{ ..Preset.layer(Waveform), colors: [{ r: 0xFF, g: 0x8A, b: 0x1F }], size: 320, thickness: 25, opacity: 100, rotation: 0, mappings: [] },
			{ ..Preset.layer(Waveform), colors: [{ r: 0x2F, g: 0xD4, b: 0xFF }], size: 190, thickness: 15, opacity: 70, rotation: 0, mappings: [] },
		],
		feedback: { enabled: Bool.True, zoom: 1000, rotation: 0, half_life_ms: 600 },
		shaders: Shaders({
			warp: Some(Gallery.flux_warp),
			composite: Some(Gallery.flux_composite),
			params: [
				{ name: "scale", value: 1.3, low: 0.5, high: 3.0, follows: Fixed, about: "how large the currents' swirls are" },
				{ name: "speed", value: 0.002, low: 0.002, high: 0.006, follows: Feature(Mids), about: "how fast the currents carry the picture, from the mids" },
				{ name: "decay", value: 0.985, low: 0.95, high: 0.995, follows: Fixed, about: "how much of the streaks a frame keeps" },
			],
		}),
	}

	## A stereo vectorscope: left against right traced in glowing phosphor,
	## upright for mono and blooming wide as the stereo opens, the old trace
	## aging from green to pink.
	phase_scope : Preset.Doc
	phase_scope = {
		id: "builtin.phase-scope",
		name: "Phase Scope",
		background: { r: 0x01, g: 0x06, b: 0x04 },
		layers: [
			{ ..Preset.layer(Lissajous), colors: [{ r: 0x2D, g: 0xFF, b: 0xB0 }, { r: 0x9D, g: 0xFF, b: 0xD8 }], size: 340, thickness: 12, opacity: 100, rotation: -45, mappings: [{ feature: Level, property: Size, from: 300, to: 480 }] },
		],
		feedback: { enabled: Bool.True, zoom: 1020, rotation: 0, half_life_ms: 140 },
		shaders: Shaders({
			warp: Some(Gallery.phase_warp),
			composite: Some(Gallery.phase_composite),
			params: [
				{ name: "decay", value: 0.84, low: 0.7, high: 0.95, follows: Fixed, about: "how much of the phosphor a frame keeps" },
				{ name: "age", value: 0.08, low: 0.0, high: 0.3, follows: Fixed, about: "how fast old trace turns from green to pink, a frame" },
				{ name: "spread", value: 1.2, low: 0.0, high: 3.0, follows: Fixed, about: "how far old trace blurs a frame, in pixels" },
			],
		}),
	}

	## A segmented spectrum of 24 bars in green, amber and red, each with a cap
	## that falls slowly after its peak, mirrored in a glossy floor.
	peak_meter : Preset.Doc
	peak_meter = {
		id: "builtin.peak-meter",
		name: "Peak Meter",
		background: { r: 0x07, g: 0x08, b: 0x0B },
		layers: [
			{ ..Preset.layer(Bars), colors: [{ r: 0x34, g: 0xE0, b: 0x5A }, { r: 0xFF, g: 0xC0, b: 0x30 }], size: 600, thickness: 100, opacity: 100, rotation: 0, mappings: [] },
		],
		feedback: Preset.no_feedback,
		shaders: Shaders({
			warp: Some(Gallery.peak_warp),
			composite: Some(Gallery.peak_composite),
			params: [
				{ name: "fall", value: 0.35, low: 0.1, high: 1.5, follows: Fixed, about: "how fast a cap falls, in heights a second" },
				{ name: "floor", value: 0.74, low: 0.6, high: 0.9, follows: Fixed, about: "where the floor is, down the surface" },
				{ name: "shine", value: 0.3, low: 0.0, high: 0.6, follows: Fixed, about: "how bright the reflection is" },
			],
		}),
	}

	## Interfering waves of colour that churn faster with the mids and break
	## into bright filaments on the treble, the waveform glowing across them.
	plasma_weave : Preset.Doc
	plasma_weave = {
		id: "builtin.plasma-weave",
		name: "Plasma Weave",
		background: { r: 0x1A, g: 0x06, b: 0x30 },
		layers: [
			{ ..Preset.layer(Waveform), colors: [{ r: 0xFF, g: 0xF2, b: 0xD0 }], size: 240, thickness: 30, opacity: 100, rotation: 0, mappings: [] },
			{ ..Preset.layer(Bars), colors: [{ r: 0xFF, g: 0x4F, b: 0xA0 }], size: 320, thickness: 60, opacity: 60, rotation: 0, mappings: [] },
		],
		feedback: Preset.no_feedback,
		shaders: Shaders({
			warp: None,
			composite: Some(Gallery.plasma_composite),
			params: [
				{ name: "scale", value: 1.6, low: 0.5, high: 4.0, follows: Fixed, about: "how fine the plasma's waves are" },
				{ name: "churn", value: 0.3, low: 0.3, high: 1.7, follows: Feature(Mids), about: "how fast it moves, from the mids" },
				{ name: "spark", value: 0.0, low: 0.0, high: 1.0, follows: Feature(Treble), about: "how bright its filaments are, from the treble" },
			],
		}),
	}

	## Stars stream out of the centre and stretch into streaks, jumping to warp
	## speed on every bass hit.
	hyperspace : Preset.Doc
	hyperspace = {
		id: "builtin.hyperspace",
		name: "Hyperspace",
		background: { r: 0x00, g: 0x00, b: 0x05 },
		layers: [
			{ ..Preset.layer(CircularWaveform), colors: [{ r: 0x5B, g: 0x7C, b: 0xC8 }], size: 60, thickness: 15, opacity: 50, rotation: 0, mappings: [{ feature: Bass, property: Size, from: 40, to: 140 }] },
		],
		feedback: { enabled: Bool.True, zoom: 3500, rotation: 0, half_life_ms: 260 },
		shaders: Shaders({
			warp: Some(Gallery.hyperspace_warp),
			composite: Some(Gallery.hyperspace_composite),
			params: [
				{ name: "speed", value: 0.012, low: 0.002, high: 0.04, follows: Fixed, about: "how fast the stars stream out, a frame" },
				{ name: "boost", value: 0.0, low: 0.0, high: 0.07, follows: Feature(Bass), about: "the jump to warp speed, from the bass" },
				{ name: "stars", value: 60.0, low: 10.0, high: 300.0, follows: Fixed, about: "new stars a frame" },
				{ name: "decay", value: 0.94, low: 0.8, high: 0.98, follows: Fixed, about: "how long a streak lasts" },
			],
		}),
	}

	## A kaleidoscope: a slowly swirling picture of the waveform and spectrum
	## folded into turning mirrored slices.
	mirror_shard : Preset.Doc
	mirror_shard = {
		id: "builtin.mirror-shard",
		name: "Mirror Shard",
		background: { r: 0x05, g: 0x02, b: 0x08 },
		layers: [
			{ ..Preset.layer(Ring), colors: [{ r: 0x19, g: 0xC7, b: 0xC2 }], size: 220, thickness: 30, opacity: 100, rotation: 0, mappings: [{ feature: Bass, property: Size, from: 160, to: 300 }] },
			{ ..Preset.layer(Waveform), colors: [{ r: 0xFF, g: 0x9A, b: 0x2E }], size: 260, thickness: 30, opacity: 100, rotation: 34, mappings: [] },
			{ ..Preset.layer(CircularWaveform), colors: [{ r: 0xFF, g: 0x3D, b: 0x8B }], size: 140, thickness: 25, opacity: 100, rotation: 0, mappings: [] },
		],
		feedback: { enabled: Bool.True, zoom: 850, rotation: 29, half_life_ms: 500 },
		shaders: Shaders({
			warp: Some(Gallery.mirror_warp),
			composite: Some(Gallery.mirror_composite),
			params: [
				{ name: "slices", value: 8.0, low: 3.0, high: 16.0, follows: Fixed, about: "how many mirrored slices make the circle" },
				{ name: "decay", value: 0.965, low: 0.9, high: 0.99, follows: Fixed, about: "how much of the picture a frame keeps" },
				{ name: "swell", value: 0.0, low: 0.0, high: 0.25, follows: Feature(Bass), about: "how far the kaleidoscope swells on the bass" },
			],
		}),
	}

	## Demoscene fire: the spectrum burns along the bottom edge and its flames
	## rise, flicker and cool, with the waveform licking through them.
	spectrum_fire : Preset.Doc
	spectrum_fire = {
		id: "builtin.spectrum-fire",
		name: "Spectrum Fire",
		background: { r: 0x00, g: 0x00, b: 0x00 },
		layers: [
			{ ..Preset.layer(Bars), colors: [{ r: 0xC2, g: 0x3A, b: 0x0A }, { r: 0xFF, g: 0xB0, b: 0x20 }], size: 260, thickness: 20, opacity: 100, rotation: 0, mappings: [{ feature: Level, property: Brightness, from: 50, to: 100 }] },
			{ ..Preset.layer(Waveform), colors: [{ r: 0xFF, g: 0xD2, b: 0x4A }], size: 140, thickness: 30, opacity: 80, rotation: 0, mappings: [] },
		],
		feedback: { enabled: Bool.True, zoom: 1000, rotation: 0, half_life_ms: 240 },
		shaders: Shaders({
			warp: Some(Gallery.fire_warp),
			composite: Some(Gallery.fire_composite),
			params: [
				{ name: "rise", value: 0.005, low: 0.001, high: 0.012, follows: Fixed, about: "how far the flames rise a frame, in heights" },
				{ name: "cool", value: 0.02, low: 0.005, high: 0.04, follows: Fixed, about: "how much heat a frame loses" },
				{ name: "fuel", value: 0.7, low: 0.7, high: 1.3, follows: Feature(Level), about: "how hot the bottom edge burns, from the level" },
			],
		}),
	}

	## A pool of water: each beat drops a stone somewhere new, the waveform
	## stirs the surface, and the ripples refract a glowing floor.
	ripple_pool : Preset.Doc
	ripple_pool = {
		id: "builtin.ripple-pool",
		name: "Ripple Pool",
		background: { r: 0x02, g: 0x14, b: 0x1C },
		layers: [
			{ ..Preset.layer(Waveform), colors: [{ r: 0x9B, g: 0xE8, b: 0xFF }], size: 160, thickness: 20, opacity: 15, rotation: 0, mappings: [] },
			{ ..Preset.layer(Ring), colors: [{ r: 0x4F, g: 0xD6, b: 0xE0 }], size: 100, thickness: 20, opacity: 100, rotation: 0, mappings: [{ feature: Bass, property: Size, from: 40, to: 160 }] },
		],
		feedback: { enabled: Bool.True, zoom: 1600, rotation: 0, half_life_ms: 700 },
		shaders: Shaders({
			warp: Some(Gallery.ripple_warp),
			composite: Some(Gallery.ripple_composite),
			params: [
				{ name: "spacing", value: 2.5, low: 1.0, high: 4.0, follows: Fixed, about: "the water's grid, in pixels" },
				{ name: "damping", value: 0.988, low: 0.95, high: 0.998, follows: Fixed, about: "how much of a ripple a step keeps" },
				{ name: "threshold", value: 0.06, low: 0.02, high: 0.2, follows: Fixed, about: "how far the bass must jump over its average to drop a stone" },
				{ name: "refraction", value: 0.06, low: 0.0, high: 0.2, follows: Fixed, about: "how far the ripples bend the floor" },
			],
		}),
	}

	## Glowing orbs of magenta, teal and orange drift, merge and swell with
	## their bands over deep purple, trailing liquid light, with spiky stars
	## twinkling between them.
	orb_garden : Preset.Doc
	orb_garden = {
		id: "builtin.orb-garden",
		name: "Orb Garden",
		background: { r: 0x12, g: 0x05, b: 0x1F },
		layers: [
			{ ..Preset.layer(Ring), colors: [{ r: 0xFF, g: 0x3F, b: 0xC8 }], size: 90, thickness: 60, opacity: 100, rotation: 0, mappings: [{ feature: Band(2), property: Size, from: 70, to: 150 }] },
			{ ..Preset.layer(Ring), colors: [{ r: 0x22, g: 0xE0, b: 0xD0 }], size: 75, thickness: 60, opacity: 100, rotation: 0, mappings: [{ feature: Band(9), property: Size, from: 60, to: 130 }] },
			{ ..Preset.layer(Ring), colors: [{ r: 0xFF, g: 0x9A, b: 0x2A }], size: 65, thickness: 60, opacity: 100, rotation: 0, mappings: [{ feature: Band(16), property: Size, from: 50, to: 120 }] },
		],
		feedback: { enabled: Bool.True, zoom: 1050, rotation: 14, half_life_ms: 450 },
		shaders: Shaders({
			warp: Some(Gallery.orb_warp),
			composite: Some(Gallery.orb_composite),
			params: [
				{ name: "decay", value: 0.94, low: 0.85, high: 0.98, follows: Fixed, about: "how long the orbs' liquid trails last" },
				{ name: "size", value: 0.11, low: 0.05, high: 0.2, follows: Fixed, about: "an orb's size at rest, in half-heights" },
				{ name: "swell", value: 0.2, low: 0.2, high: 0.8, follows: Feature(Level), about: "how far the orbs swell with their bands" },
			],
		}),
	}

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

	fire_composite : Str
	fire_composite =
		\\// Heat to colour: black, deep red, orange, yellow, then white.
		\\float4 composite(Frame f, Params p) {
		\\    float h = saturate(sample(f, f.uv).r * 1.15);
		\\    float3 col = float3(saturate(h * 2.2), saturate(h * 2.2 - 0.55), saturate(h * 3.0 - 2.0));
		\\    col *= smoothstep(0.02, 0.2, h);
		\\    return opaque(col);
		\\}

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

}
