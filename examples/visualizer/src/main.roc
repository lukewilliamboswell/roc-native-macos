app [main] { pf: platform "../../../platform/main.roc" }

import pf.Engine exposing [Elem, Signal]
import pf.Audio
import pf.Ui
import Presets

## A visualizer: a drawing surface fed by the platform's synthetic sources,
## drawn at every display refresh without a turn of the engine, with a trail
## and a caption over it. `Scope` draws a wave and a marker that moves with a
## level; `Echo` draws a mark and a ring whose previous frames drift right and
## fade (a trail); `Bands` draws the wave as bars, with a marker riding one
## value of it, another bound past its end, which reads 0, and a line as
## thick as the level. The caption is native text over the surface, which
## the trail never draws. `Shaders` runs the surface's own GPU stages over
## Echo's marks (`Ui.Shader`): a warp that drags the previous frame right, a
## composite that inverts the colours, one whose red follows a param bound
## to a source, and a warp that does not compile; the line beside them says
## what the shaders are doing. `Gallery` plays an audio file the person
## chooses through any of twelve visualizations (`Presets`).
main : Engine.Program(_)
main = Engine.program_store({}, |_boot| store, |_boot| view()).with_ports(Audio.ports)

store = Engine.store(
	Visualizer,
	{
		mode: Engine.cell("Scope"),
		shown: Engine.cell(Bool.True),
		caption: Engine.cell(Bool.False),
		resets: Engine.cell(0.U64),
		test: Engine.cell("Warp"),
		status: Engine.cell("Shaders: none"),

		## The gallery: the preset shown, what its shaders are doing, and the
		## playback the commands a press posts (`outbox`) drive.
		preset: Engine.cell("Liquid Drift"),
		shading: Engine.cell(""),
		outbox: Engine.cell(Engine.outbox({})),
		track: Engine.cell(0.U64),
		song: Engine.cell(""),
		playback: Engine.cell(idle),
	}.Engine.Cells,
)

cells = store.cells()

view : () -> Elem(Engine.StoreRoot(_))
view = || {
	mode = cells.mode.signal()
	shown = cells.shown.signal()
	Engine.when(
		mode.map(|m| m == "Gallery"),
		|| gallery(),
		|| Ui.vstack(
			{ spacing: 12, align: Fill },
			[
				modes(),
				Engine.when(
					mode.map(|m| m == "Shaders"),
					|| Ui.hstack(
						{ spacing: 12 },
						[
							Ui.segmented(cells.test.signal(), { choices: tests, on_change: Engine.handle(|chosen| [cells.test.set(chosen)]) }),
							Ui.text(cells.status.signal(), { style: Caption1, color: SecondaryLabel, overflow: Wrap, width: Fill }),
						],
					),
					|| Engine.text(""),
				),
				Ui.hstack(
					{ spacing: 12, align: Top, width: Fill },
					[
						Ui.vstack(
							{ spacing: 8, align: Fill, width: Fixed(120) },
							[
								Ui.button(shown.map(|on| if (on) "Hide plot" else "Show plot"), { on_press: Engine.handle_by(shown, |on, _| [cells.shown.set(!on)]) }),
								Ui.button("Clear trail", { on_press: Engine.handle(|_| [cells.resets.update(|n| n + 1)]) }),
								Ui.checkbox("Caption", { checked: cells.caption.signal(), on_change: Engine.handle(|on| [cells.caption.set(on)]) }),
							],
						),
						Engine.when(shown, || plot(mode), || Engine.text("")),
					],
				),
			],
		),
	)
}

## The modes, as a segmented control.
modes : () -> Elem(Engine.StoreRoot(_))
modes = || Ui.segmented(cells.mode.signal(), { choices: ["Scope", "Echo", "Bands", "Shaders", "Gallery"], on_change: Engine.handle(|chosen| [cells.mode.set(chosen)]) })

# --- The gallery ---

## Where playback stood when the host last said.
idle : Audio.Status
idle = { track: 0, generation: 0, state: Idle, position_ms: 0, duration_ms: 0, volume: 1, latency_ms: 0, eq: { bypass: Bool.False, preamp_db: 0, gains_db: List.repeat(0, 10) } }

## The gallery: a picker of the presets, a file to play through them, and
## the preset filling the window, with what it is and what its shaders are
## doing beneath it.
gallery : () -> Elem(Engine.StoreRoot(_))
gallery = || {
	preset = cells.preset.signal().map(Presets.named)
	playback = cells.playback.signal()
	loaded = playback.map(|s| s.state != Idle and s.state != Loading)
	Ui.vstack(
		{ spacing: 10, align: Fill },
		[
			modes(),
			Ui.hstack(
				{ spacing: 8 },
				[
					Ui.dropdown(cells.preset.signal(), { choices: Presets.names, on_change: Engine.handle(|name| [cells.preset.set(name)]) }),
					Ui.file_button("Choose Audio…", { on_files: Engine.handle_by(cells.track.signal(), chose), icon: Symbol("music.note") }),
					Ui.button("Play", { on_press: Engine.handle(|_| send([Play])), enabled: loaded, icon: Symbol("play.fill") }),
					Ui.button("Pause", { on_press: Engine.handle(|_| send([Pause])), enabled: loaded, icon: Symbol("pause.fill") }),
					Ui.text({ song: cells.song.signal(), playback }.Signal.map(|{ song, playback: s }| playing(song, s)), { design: MonospacedDigits, overflow: TruncateTail, width: Fill }),
				],
			),
			Ui.slider(playback.map(|s| s.position_ms.to_i64_wrap()), { range: { min: 0, max: 300_000 }, on_input: Engine.handle(|typed| send([Seek((I64.from_str(typed) ?? 0).max(0).to_u64_wrap())])), enabled: loaded, width: Fill }),
			Ui.text(preset.map(|p| p.about), { overflow: Wrap, width: Fill }),
			Ui.surface(
				preset.map(|p| p.scene),
				{
					label: "Gallery",
					space: preset.map(|p| p.space),
					background: preset.map(|p| p.background),
					pacing: Engine.const(Display),
					trail: preset.map(|p| p.trail),
					reset: playback.map(|s| s.generation),
					shader: preset.map(Presets.shader),
					on_shader: Handled(Engine.handle(|status| [cells.shading.set(describe(status))])),
					width: Fill,
					height: FillAtLeast(500),
				},
			),
			Ui.text(cells.shading.signal(), note),
			Ui.text(preset.map(Presets.ranges), note),
			# The commands each press posted, sent in order, and where
			# playback stands, while the gallery is shown.
			Engine.on_post(cells.outbox.signal(), |commands| commands.map(Audio.send), Engine.ignore({})),
			Engine.watch(
				Engine.const({}),
				|_| [Audio.status({ every_ms: 250 })],
				Engine.react(
					|_, result| match result {
						Ok(s) => [cells.playback.set(s)]
						Err(_) => []
					},
				),
			),
		],
	)
}

## The commands a handler sends, in order.
send : List(Audio.Command) -> List(Engine.Write(_))
send = |commands| [cells.outbox.update(|box| box.post(commands))]

## A chosen file: loaded as the next track, and played.
chose : U64, Engine.Received -> List(Engine.Write(_))
chose = |track, { files, .. }|
	match files.first() {
		Ok(file) => [cells.track.set(track + 1), cells.song.set(file.name())].concat(send([Load({ track: track + 1, file }), Play]))
		Err(_) => []
	}

## The song and where it stands.
playing : Str, Audio.Status -> Str
playing = |song, s|
	match s.state {
		Idle => "Choose an audio file to play."
		Loading => "Loading ${song}…"
		_ => "${song} · ${clock(s.position_ms)} / ${clock(s.duration_ms)}"
	}

## The gallery's small print.
note : Ui.TextProps
note = { style: Caption1, color: SecondaryLabel, overflow: Wrap, width: Fill }

## `m:ss`
clock : U64 -> Str
clock = |ms| {
	seconds = (ms // 1000) % 60
	"${(ms // 60000).to_str()}:${if (seconds < 10) "0" else ""}${seconds.to_str()}"
}

## The surface, with the caption over it while it is on.
plot : Engine.Signal(Engine.StoreRoot(_), Str) -> Elem(Engine.StoreRoot(_))
plot = |mode| {
	chosen = { mode, test: cells.test.signal() }.Signal
	surface = Ui.surface(
		mode.map(scene),
		{
			label: "Visualizer",
			space: mode.map(space),
			background: chosen.map(|{ mode: m, test }| if (m == "Shaders" and test == "Invert") black else Clear),
			pacing: Engine.const(Display),
			trail: mode.map(trail),
			reset: cells.resets.signal(),
			shader: chosen.map(|{ mode: m, test }| if (m == "Shaders") shader(test) else NoShader),
			on_shader: Handled(Engine.handle(|status| [cells.status.set(describe(status))])),
			width: FillAtLeast(360),
			height: Fixed(160),
		},
	)
	caption = Engine.when(
		cells.caption.signal(),
		|| Ui.box({ fill: black, radius: 6, padding: Axes({ horizontal: 10, vertical: 4 }) }, Ui.text("Echo, echo, fading slow: the old light under the new.", { color: white, overflow: Wrap, align: Center, width: Fill })),
		|| Engine.text(""),
	)
	Ui.overlay({ vertical: Bottom, padding: All(8) }, surface, caption)
}

## Scope draws a 640 by 160 scene fitted to the surface; the others draw
## in points.
space : Str -> Ui.Space
space = |mode| if (mode == "Scope") Fit({ width: 640, height: 160 }) else Points

## The marks of a mode, from the surface's top-left corner.
scene : Str -> List(Ui.Mark)
scene = |mode|
	if mode == "Echo" or mode == "Shaders" {
		[
			Fill(Rect({ x: 20, y: 20, width: 20, height: 20 }), red),
			Stroke(Ring({ source: "synthetic.wave", x: 240, y: 80, radius: 36, depth: 16, low: -1, high: 1 }), { color: Orange, width: Value(2) }),
		]
	} else if mode == "Bands" {
		[
			Fill(Bars({ source: "synthetic.wave", area: { x: 0, y: 20, width: 360, height: 120 }, low: -1, high: 1, gap: 4 }), Green),
			Save,
			Translate(Value(100), Element({ source: "synthetic.wave", index: 2, scale: -60, offset: 80 })),
			Fill(Oval({ x: -8, y: -8, width: 16, height: 16 }), amber),
			Restore,
			Save,
			Translate(Value(380), Element({ source: "synthetic.wave", index: 99, scale: -60, offset: 80 })),
			Fill(Rect({ x: -8, y: -8, width: 16, height: 16 }), red),
			Restore,
			Stroke(Polyline([{ x: 0, y: 150 }, { x: 360, y: 150 }]), { color: Orange, width: Source({ source: "synthetic.level", scale: 16, offset: 1 }) }),
		]
	} else {
		[
			Stroke(Wave({ source: "synthetic.wave", area: { x: 0, y: 20, width: 640, height: 120 }, low: -1, high: 1 }), { color: Green, width: Value(3) }),
			Save,
			Translate(Source({ source: "synthetic.level", scale: 640, offset: 0 }), Value(0)),
			Fill(Oval({ x: -12, y: 68, width: 24, height: 24 }), amber),
			Restore,
		]
	}

## Echo's trail: half gone in 100 ms, drifting right at 100 points a second.
## The shader tests keep it, so where shaders do not run (Core Graphics)
## they draw Echo; a warp shader takes its place.
trail : Str -> Ui.Trail
trail = |mode|
	if mode == "Echo" or mode == "Shaders" {
		Trail({ half_life_ms: 100, zoom: 1, turn: 0, shift: { x: 100, y: 0 } })
	} else {
		NoTrail
	}

## The shader tests.
tests : List(Str)
tests = ["Warp", "Invert", "Param", "Broken"]

## Each test's stages. `Warp` drags the previous frame a tenth of the width
## right each frame, with no fade, so a mark smears right; `Invert` maps
## each colour to its opposite on the way to the screen; `Param` paints the
## screen as red as `synthetic.level`, read each frame through a param;
## `Broken` names something that does not exist on its third line.
shader : Str -> Ui.Shader
shader = |test|
	match test {
		"Warp" =>
			Shaders({
				warp: Some(
					\\// Each pixel takes the colour `shift` of the width to its left.
					\\float4 warp(Frame f, Params p) {
					\\    return sample(f, f.uv - float2(p.shift, 0.0));
					\\}
				),
				composite: None,
				params: [("shift", Value(0.1))],
			})

		"Invert" =>
			Shaders({
				warp: None,
				composite: Some(
					\\// The opposite colour: red shows cyan, and black white.
					\\float4 composite(Frame f, Params p) {
					\\    float4 c = sample(f, f.uv);
					\\    return float4(c.a - c.rgb, c.a);
					\\}
				),
				params: [],
			})

		"Param" =>
			Shaders({
				warp: None,
				composite: Some(
					\\// Red as strong as the level param, everywhere.
					\\float4 composite(Frame f, Params p) {
					\\    return opaque(float3(p.level, 0.0, 0.0));
					\\}
				),
				params: [("level", Source({ source: "synthetic.level", scale: 1, offset: 0 }))],
			})

		_ =>
			Shaders({
				warp: Some(
					\\// A mistake on line 3: there is no `brightness`.
					\\float4 warp(Frame f, Params p) {
					\\    return sample(f, f.uv) * brightness;
					\\}
				),
				composite: None,
				params: [],
			})
	}

## What the shaders are doing, as the line beside the tests says it.
describe : Ui.ShaderStatus -> Str
describe = |status|
	match status {
		NoShader => "Shaders: none"
		Running => "Shaders: running"
		Fallback => "Shaders: not on this renderer, so the marks and the trail alone"
		Failed(errors) => Str.join_with(errors.map(|e| "${if (e.stage == Warp) "warp" else "composite"} line ${e.line.to_str()}:${e.column.to_str()}: ${e.message}"), "; ")
	}

red : Ui.Color
red = Adaptive({ light: 0xff0000, dark: 0xff0000 })

amber : Ui.Color
amber = Adaptive({ light: 0xffaa00, dark: 0xffaa00 })

black : Ui.Color
black = Adaptive({ light: 0x000000, dark: 0x000000 })

white : Ui.Color
white = Adaptive({ light: 0xffffff, dark: 0xffffff })

## The scenes encode as the host reads them.
expect scene("Echo").len() == 2 and scene("Scope").len() == 5 and scene("Bands").len() == 10

## A compile error reads with its stage, line and column.
expect describe(Failed([{ stage: Warp, line: 3, column: 30, message: "use of undeclared identifier 'brightness'" }])) == "warp line 3:30: use of undeclared identifier 'brightness'"
