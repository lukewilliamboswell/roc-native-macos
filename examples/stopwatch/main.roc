app [main] { pf: platform "../../platform/main.roc" }

import pf.Engine exposing [Elem]
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
	Ui.vstack(
		{},
		[
			Ui.title("Stopwatch"),
			Ui.readout_s(cells.elapsed_ms.signal().map(clock)),
			Ui.hstack(
				{},
				[
					Ui.button_s(running.map(|on| if (on) "Stop" else "Start"), Engine.handle_by(running, |on, _| toggled(on))),
					Ui.action_button(Engine.const("Lap"), running, Engine.handle_by(cells.elapsed_ms.signal(), |at, _| [cells.laps.update(|laps| laps.append(at))])),
					Ui.button("Reset", Engine.handle(|_| [cells.running.set(Bool.False), cells.elapsed_ms.set(0), cells.last_tick.set(0), cells.laps.set([])])),
				],
			),
			Ui.divider(),
			Ui.label_s(cells.laps.signal().map(|laps| if (laps.is_empty()) "No laps yet" else "Laps")),
			Ui.vstack(
				{},
				[
					Engine.each(
						cells.laps.signal().map(|laps| laps.map_with_index(|at, index| { number: index + 1, at })),
						|lap| lap.number.to_str(),
						|row| Ui.label_s(row.item().map(|lap| "Lap ${lap.number.to_str()}    ${clock(lap.at)}")),
					),
				],
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
