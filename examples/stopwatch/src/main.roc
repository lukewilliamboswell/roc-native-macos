app [main] { pf: platform "../../../platform/main.roc" }

import pf.Engine exposing [Elem, Signal]
import pf.Ui

## A stopwatch: a store of three cells, an interval effect that runs only
## while the watch does, and a list of laps.
main : Engine.Program(_)
main = Engine.program_store({}, |_boot| store, |_boot| view())

store = Engine.store(
	Stopwatch,
	{
		running: Engine.cell(Bool.False),
		elapsed_ms: Engine.cell(0.I64),
		last_tick: Engine.cell(0.I64),
		laps: Engine.cell([]),
	}.Engine.Cells,
)

cells = store.cells()

view : () -> Elem(Engine.StoreRoot(_))
view = || {
	running = cells.running.signal()
	laps = cells.laps.signal()
	Ui.vstack(
		{ spacing: 18, align: Fill, width: AtLeast(380) },
		[
			Ui.text(cells.elapsed_ms.signal().map(clock), { size: Fixed(56), weight: Light, design: MonospacedDigits, align: Center, width: Fill }),
			Ui.hstack(
				{ spacing: 12, distribution: FillEqually, width: Fill },
				[
					Ui.button("Reset", { on_press: Engine.handle(|_| [cells.running.set(Bool.False), cells.elapsed_ms.set(0), cells.last_tick.set(0), cells.laps.set([])]), size: Large, width: AtLeast(84) }),
					Ui.button("Lap", { on_press: Engine.handle_by(cells.elapsed_ms.signal(), |at, _| [cells.laps.update(|held| held.append(at))]), enabled: running, size: Large, width: AtLeast(84) }),

					## The prominent button: Return starts and stops the watch.
					Ui.button(running.map(|on| if (on) "Stop" else "Start"), { on_press: Engine.handle_by(running, |on, _| toggled(on)), role: Default, size: Large, width: AtLeast(84) }),
				],
			),
			Ui.hstack(
				{ align: FirstBaseline },
				[
					Ui.text("Laps", { style: Headline }),
					Ui.spacer(),
					Ui.text(laps.map(|held| if (held.is_empty()) "" else "${held.len().to_str()} recorded"), { style: Caption1, color: SecondaryLabel }),
				],
			),
			Ui.box(
				{ padding: Axes({ horizontal: 12, vertical: 8 }), border: Line({ color: Separator, width: 1 }) },
				Ui.vstack(
					{ spacing: 6, align: Fill },
					[
						Engine.when(laps.map(|held| held.is_empty()), || Ui.text("Press Lap while the watch runs.", { color: TertiaryLabel }), || Engine.text("")),
						Engine.each(laps.map(splits), |lap| lap.number.to_str(), |row| lap_row(row.item())),
					],
				),
			),
			# While the watch runs, an interval ticks every 47 ms; stopping it
			# cancels the request (watch_latest supersedes it).
			Engine.watch_latest(
				running,
				|on| if (on) [Engine.interval(47)] else [],
				Engine.react_by(cells.last_tick.signal(), ticked),
			),
		],
	)
}

## One lap: its number, its own time (green for the fastest, red for the
## slowest) and the total when it was taken.
lap_row : Signal(r, Lap) -> Elem(r)
lap_row = |lap|
	Ui.hstack(
		{},
		[
			Ui.text(lap.map(|l| "Lap ${l.number.to_str()}"), { color: SecondaryLabel, width: Fixed(64) }),
			Ui.text_s(
				lap.map(|l| clock(l.split)),
				lap.map(
					|l| {
						color = match l.mark {
							Fastest => Green
							Slowest => Red
							Ordinary => Label
						}
						{ design: MonospacedDigits, color }
					},
				),
			),
			Ui.spacer(),
			Ui.text(lap.map(|l| clock(l.at)), { design: MonospacedDigits, color: SecondaryLabel }),
		],
	)

## A lap as the list shows it.
Lap : { number : U64, at : I64, split : I64, mark : [Fastest, Slowest, Ordinary] }

## The laps, newest first, each with its split from the one before; with
## two or more, the fastest and slowest split are marked.
splits : List(I64) -> List(Lap)
splits = |times| {
	timed = times.map_with_index(|at, index| { number: index + 1, at, split: at - (if (index == 0) 0 else times.get(index - 1) ?? 0) })
	fastest = timed.map(|l| l.split).min() ?? 0
	slowest = timed.map(|l| l.split).max() ?? 0
	marked = timed.map(
		|l| {
			mark =
				if timed.len() < 2 or fastest == slowest {
					Ordinary
				} else if l.split == fastest {
					Fastest
				} else if l.split == slowest {
					Slowest
				} else {
					Ordinary
				}
			{ number: l.number, at: l.at, split: l.split, mark }
		},
	)
	marked.sort_with(|a, b| if (a.number > b.number) Before else if (a.number < b.number) After else Same)
}

## Starting forgets the last tick, so the first tick after it only sets it.
toggled : Bool -> List(Engine.Write(_))
toggled = |on| [cells.running.set(!on), cells.last_tick.set(0)]

## A tick adds the time since the previous one; the first tick after a
## start only records when it came.
ticked : I64, Bool, Try(I64, _) -> List(Engine.Write(_))
ticked = |last, _, result|
	match result {
		Ok(at_ms) if last == 0 => [cells.last_tick.set(at_ms)]
		Ok(at_ms) => [cells.last_tick.set(at_ms), cells.elapsed_ms.update(|elapsed| elapsed + at_ms - last)]
		_ => []
	}

## `m:ss.cc`
clock : I64 -> Str
clock = |ms| {
	centis = (ms // 10) % 100
	seconds = (ms // 1000) % 60
	minutes = ms // 60000
	pad = |n| if (n < 10) "0${n.to_str()}" else n.to_str()
	"${minutes.to_str()}:${pad(seconds)}.${pad(centis)}"
}

expect clock(83_456) == "1:23.45"

## Splits are the gaps between laps, newest first, with the extremes marked.
expect {
	actual = splits([1000, 2500, 3100]).map(|l| "${l.number.to_str()} ${l.split.to_str()} ${Str.inspect(l.mark)}")
	actual == ["3 600 Fastest", "2 1500 Slowest", "1 1000 Ordinary"]
}

## One lap marks nothing.
expect splits([1200]).map(|l| l.mark) == [Ordinary]
