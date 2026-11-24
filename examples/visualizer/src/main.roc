app [main] { pf: platform "../../../platform/main.roc" }

import pf.Engine exposing [Elem]
import pf.Ui

## A visualizer: a drawing surface fed by the platform's synthetic sources,
## drawn at every display refresh without a turn of the engine, with a trail
## and a caption over it. `Scope` draws a wave and a marker that moves with a
## level; `Echo` draws a mark and a ring whose previous frames drift right and
## fade (a trail). The caption is native text over the surface, which the
## trail never draws.
main : Engine.Program(_)
main = Engine.program_store({}, |_boot| store, |_boot| view())

store = Engine.store(
	Visualizer,
	{
		mode: Engine.cell("Scope"),
		shown: Engine.cell(Bool.True),
		caption: Engine.cell(Bool.False),
		resets: Engine.cell(0.U64),
	}.Engine.Cells,
)

cells = store.cells()

view : () -> Elem(Engine.StoreRoot(_))
view = || {
	mode = cells.mode.signal()
	shown = cells.shown.signal()
	Ui.vstack(
		{ spacing: 12, align: Fill },
		[
			Ui.segmented(mode, { choices: ["Scope", "Echo"], on_change: Engine.handle(|chosen| [cells.mode.set(chosen)]) }),
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
	)
}

## The surface, with the caption over it while it is on.
plot : Engine.Signal(Engine.StoreRoot(_), Str) -> Elem(Engine.StoreRoot(_))
plot = |mode| {
	surface = Ui.surface(
		mode.map(scene),
		{
			label: "Visualizer",
			space: mode.map(space),
			pacing: Engine.const(Display),
			trail: mode.map(trail),
			reset: cells.resets.signal(),
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

## Scope draws a 640 by 160 scene fitted to the surface; Echo draws in
## points.
space : Str -> Ui.Space
space = |mode| if (mode == "Echo") Points else Fit({ width: 640, height: 160 })

## The marks of a mode, from the surface's top-left corner.
scene : Str -> List(Ui.Mark)
scene = |mode|
	if mode == "Echo" {
		[
			Fill(Rect({ x: 20, y: 20, width: 20, height: 20 }), red),
			Stroke(Ring({ source: "synthetic.wave", x: 240, y: 80, radius: 36, depth: 16, low: -1, high: 1 }), { color: Orange, width: 2 }),
		]
	} else {
		[
			Stroke(Wave({ source: "synthetic.wave", area: { x: 0, y: 20, width: 640, height: 120 }, low: -1, high: 1 }), { color: Green, width: 3 }),
			Save,
			Translate(Source({ source: "synthetic.level", scale: 640, offset: 0 }), Value(0)),
			Fill(Oval({ x: -12, y: 68, width: 24, height: 24 }), amber),
			Restore,
		]
	}

## Echo's trail: half gone in 100 ms, drifting right at 100 points a second.
trail : Str -> Ui.Trail
trail = |mode|
	if mode == "Echo" {
		Trail({ half_life_ms: 100, zoom: 1, turn: 0, shift: { x: 100, y: 0 } })
	} else {
		NoTrail
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
expect scene("Echo").len() == 2 and scene("Scope").len() == 5
