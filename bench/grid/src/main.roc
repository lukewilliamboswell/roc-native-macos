app [main] { pf: platform "../../../platform/main.roc" }

import pf.Engine exposing [Elem]
import pf.Ui

## The grid stress test: N×N cells, each a small fixed-size box. The pointer
## entering a cell turns it hot, and a one-shot timer for that cell turns it
## back `cool_ms` later, so a moving pointer leaves a fading trail. Nothing
## ticks globally: the live timers are the trail, not the grid.
##
## N is the local storage key `grid-n` at launch, which `run.sh` passes as a
## command-line default (`-grid-n 316`, Cocoa's argument domain), so the grid
## is built by the mount itself. It is fixed for the run: an
## `Engine.switch` over the sizes would let a control rebuild it, but the
## engine evaluates every branch's description at mount (1.2 s for the
## million-cell one), which would hide the cost being measured.
main : Engine.Program(_)
main = Engine.program_boot({ storage_keys: ["grid-n"], max_inflight: 4096 }, |boot| view(Engine.boot_storage(boot, "grid-n") ?? "10"))

## How long a cell stays hot after the pointer last entered it.
cool_ms : U32
cool_ms = 500

view : Str -> Elem(Engine.Root)
view = |n|
	Ui.vstack(
		{ spacing: 12 },
		[
			grid(n),
			Ui.text(Engine.const(caption(n)), { style: Caption1, color: SecondaryLabel }),
		],
	)

caption : Str -> Str
caption = |n| {
	side = U64.from_str(n) ?? 0
	"${n}×${n} = ${(side * side).to_str()} cells, ${side_of(n).to_str()} pt each, hot for ${cool_ms.to_str()} ms"
}

## A cell's side: the grid stays within about 640 points where it can, and
## never below one point.
side_of : Str -> U32
side_of = |n| {
	count = U32.from_str(n) ?? 10
	fit = 640 // count
	if (fit > 24) 24 else if (fit < 1) 1 else fit
}

## The N×N grid: N rows of N cells, with no spacing.
grid : Str -> Elem(ctx)
grid = |n| {
	count = U64.from_str(n) ?? 10
	row = Ui.hstack({ spacing: 0 }, List.repeat(cell(side_of(n)), count))
	Ui.vstack({ spacing: 0 }, List.repeat(row, count))
}

## One cell. Its state is its own: whether it is hot, and how many times
## the pointer has entered it, which names the timer of the latest entry.
## The timer site sits inside the box (it draws nothing), and
## `watch_latest` cancels an earlier entry's timer when the pointer
## enters again.
cell : U32 -> Elem(ctx)
cell = |side|
	Engine.state(
		{ hot: Bool.False, entered: 0.U64 },
		|st| {
			now = st.signal()
			Ui.hover(
				{ on_hover: st.set_value(|v, inside| if (inside) { hot: Bool.True, entered: v.entered + 1 } else v) },
				Ui.box_s(
					now.map(|v| look(side, v.hot)),
					Engine.watch_latest(
						now.map(|v| v.entered),
						|entered| if (entered == 0) [] else [Engine.timer(cool_ms)],
						st.on_result(|v, entered, _fired| if (v.entered == entered) { ..v, hot: Bool.False } else v),
					),
				),
			)
		},
	)

look : U32, Bool -> Ui.BoxProps
look = |side, hot| {
	fill: if (hot) Orange else ControlBackground,
	radius: 0,
	padding: Zero,
	width: Fixed(side),
	height: Fixed(side),
}

expect side_of("10") == 24 and side_of("100") == 6 and side_of("1000") == 1
expect caption("32") == "32×32 = 1024 cells, 20 pt each, hot for 500 ms"
