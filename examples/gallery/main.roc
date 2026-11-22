app [main] { pf: platform "../../platform/main.roc" }

import pf.Engine exposing [Elem]
import pf.Ui

## A gallery of the native controls: tabs over three pages, a dropdown, a
## multi-line text area, symbols, progress bars, styled text and two
## window-wide shortcuts (Command-N and Command-K).
main : Engine.Program(_)
main = Engine.program_store({}, |_boot| store, |_boot| view())

store = Engine.store(
	Gallery,
	{
		tab: Engine.cell("Controls"),
		fruit: Engine.cell("Apple"),
		level: Engine.cell(40.I64),
		busy: Engine.cell(Bool.False),
		notes: Engine.cell(""),
		presses: Engine.cell(0.I64),
	}.Engine.Cells,
)

cells = store.cells()

view : () -> Elem(Engine.StoreRoot(_))
view = ||
	Ui.vstack(
		{ spacing: 12, align: Fill },
		[
			Ui.title("Gallery"),
			Ui.text({ font: Caption, color: Secondary }, "Native AppKit controls driven by the roc-signals engine"),
			Ui.tabs(["Controls", "Text", "Shortcuts"], cells.tab.signal(), Engine.handle(|name| [cells.tab.set(name)]), page),
			Ui.shortcut([Ui.command("n")], Engine.handle(|_key| [cells.presses.update(|n| n + 1)])),
			Ui.shortcut([Ui.command("k")], Engine.handle(|_key| [cells.presses.set(0)])),
		],
	)

page : Str -> Elem(Engine.StoreRoot(_))
page = |name|
	match name {
		"Controls" => controls()
		"Text" => text()
		_ => shortcuts()
	}

controls : () -> Elem(Engine.StoreRoot(_))
controls = ||
	Ui.vstack(
		{ spacing: 10 },
		[
			Ui.hstack(
				{},
				[
					Ui.image("leaf.fill", Green),
					Ui.text({ font: Headline }, "Fruit"),
					Ui.dropdown(["Apple", "Banana", "Cherry"], cells.fruit.signal(), Engine.handle(|chosen| [cells.fruit.set(chosen)])),
				],
			),
			Ui.text_s({ color: Accent }, cells.fruit.signal().map(|fruit| "You picked ${fruit}")),
			Ui.divider(),
			Ui.hstack(
				{},
				[
					Ui.text({ font: Headline }, "Level"),
					Ui.slider({ min: 0, max: 100 }, cells.level.signal(), Engine.handle(|typed| [cells.level.set(I64.from_str(typed) ?? 0)])),
					Ui.text_s({ font: Mono }, cells.level.signal().map(|n| n.to_str())),
				],
			),
			Ui.progress({ max: 100 }, cells.level.signal()),
			Ui.hstack(
				{},
				[
					Ui.checkbox(Engine.const("Working"), cells.busy.signal(), Engine.handle(|on| [cells.busy.set(on)])),
					Ui.busy(cells.busy.signal()),
				],
			),
		],
	)

text : () -> Elem(Engine.StoreRoot(_))
text = ||
	Ui.vstack(
		{ spacing: 6, align: Fill },
		[
			Ui.text({ font: Headline }, "Notes"),
			Ui.text_area({ height: 120 }, cells.notes.signal(), Engine.handle(|typed| [cells.notes.set(typed)])),
			Ui.text_s({ font: Caption, color: Secondary }, cells.notes.signal().map(summary)),
		],
	)

shortcuts : () -> Elem(Engine.StoreRoot(_))
shortcuts = ||
	Ui.vstack(
		{ spacing: 6 },
		[
			Ui.hstack({}, [Ui.image("command", Secondary), Ui.text({}, "Command-N counts a press, Command-K resets it.")]),
			Ui.readout_s(cells.presses.signal().map(|n| n.to_str())),
		],
	)

summary : Str -> Str
summary = |notes| {
	lines = notes.split_on("\n").len()
	chars = notes.count_utf8_bytes()
	"${lines.to_str()} lines, ${chars.to_str()} bytes"
}

expect summary("a\nb") == "2 lines, 3 bytes"
