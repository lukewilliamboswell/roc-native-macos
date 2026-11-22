app [main] { pf: platform "../../platform/main.roc" }

import pf.Engine exposing [Elem]
import pf.Ui

## A gallery of the native controls and looks: tabs over four pages of
## labelled sections (controls, text, styles and shortcuts), a dropdown,
## a slider, a multi-line text area, symbols, progress bars, text styles,
## semantic colours that name themselves under the pointer, and two
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
		pointed: Engine.cell(""),
	}.Engine.Cells,
)

cells = store.cells()

## The looks the gallery shares.
Theme : {
	section : Ui.BoxProps,
	heading : Ui.TextProps,
	caption : Ui.TextProps,
}

theme : Theme
theme = {
	section: { padding: All(14), border: Line({ color: Separator, width: 1 }), width: Fill },
	heading: { style: Subheadline, weight: Semibold, color: SecondaryLabel },
	caption: { style: Caption1, color: SecondaryLabel },
}

view : () -> Elem(Engine.StoreRoot(_))
view = ||
	Ui.vstack(
		{ spacing: 16, align: Fill, width: AtLeast(520) },
		[
			Ui.hstack(
				{ spacing: 10 },
				[
					Ui.image("square.grid.2x2.fill", { style: Title1, color: Accent }),
					Ui.vstack(
						{ spacing: 2 },
						[
							Ui.text("Gallery", { style: Title2, weight: Semibold }),
							Ui.text("Native AppKit controls driven by the roc-signals engine", theme.caption),
						],
					),
				],
			),
			Ui.tabs(cells.tab.signal(), { choices: ["Controls", "Text", "Styles", "Shortcuts"], on_change: Engine.handle(|name| [cells.tab.set(name)]), page }),
			Ui.shortcut([Ui.command("n")], { on_key: Engine.handle(|_key| [cells.presses.update(|n| n + 1)]) }),
			Ui.shortcut([Ui.command("k")], { on_key: Engine.handle(|_key| [cells.presses.set(0)]) }),
		],
	)

page : Str -> Elem(Engine.StoreRoot(_))
page = |name|
	match name {
		"Controls" => controls()
		"Text" => text()
		"Styles" => styles()
		_ => shortcuts()
	}

## A titled group of controls.
section : Str, Elem(ctx) -> Elem(ctx)
section = |title, content|
	Ui.vstack(
		{ spacing: 6, align: Fill },
		[
			Ui.text(Engine.const(title), theme.heading),
			Ui.box(theme.section, content),
		],
	)

controls : () -> Elem(Engine.StoreRoot(_))
controls = ||
	Ui.vstack(
		{ spacing: 14, align: Fill },
		[
			section(
				"CHOICE",
				Ui.vstack(
					{ spacing: 8 },
					[
						Ui.hstack(
							{},
							[
								Ui.image("leaf.fill", { color: Green }),
								Ui.text("Fruit", {}),
								Ui.dropdown(cells.fruit.signal(), { choices: ["Apple", "Banana", "Cherry"], on_change: Engine.handle(|chosen| [cells.fruit.set(chosen)]) }),
							],
						),
						Ui.text("You picked ${cells.fruit.signal()}", { color: Accent }),
					],
				),
			),
			section(
				"LEVEL",
				Ui.vstack(
					{ spacing: 8, align: Fill },
					[
						Ui.hstack(
							{},
							[
								Ui.image("speaker.wave.2.fill", { color: SecondaryLabel }),
								Ui.slider(cells.level.signal(), { range: { min: 0, max: 100 }, on_input: Engine.handle(|typed| [cells.level.set(I64.from_str(typed) ?? 0)]), width: Fill }),
								Ui.text("${cells.level.signal()}", { design: MonospacedDigits, align: Trailing, width: Fixed(32) }),
							],
						),
						Ui.progress(cells.level.signal(), {}),
					],
				),
			),
			section(
				"ACTIVITY",
				Ui.hstack(
					{ spacing: 12, width: Fill },
					[
						Ui.checkbox("Working", { checked: cells.busy.signal(), on_change: Engine.handle(|on| [cells.busy.set(on)]) }),
						Ui.busy(cells.busy.signal(), {}),
					],
				),
			),
		],
	)

text : () -> Elem(Engine.StoreRoot(_))
text = ||
	section(
		"NOTES",
		Ui.vstack(
			{ spacing: 6, align: Fill },
			[
				Ui.text_area(cells.notes.signal(), { on_input: Engine.handle(|typed| [cells.notes.set(typed)]), height: AtLeast(140) }),
				Ui.text(cells.notes.signal().map(summary), theme.caption),
			],
		),
	)

## Text styles and semantic colours, each named in its own look.
styles : () -> Elem(Engine.StoreRoot(_))
styles = ||
	Ui.vstack(
		{ spacing: 14, align: Fill },
		[
			section(
				"TEXT STYLES",
				Ui.vstack(
					{ spacing: 4 },
					[
						Ui.text("Large Title", { style: LargeTitle }),
						Ui.text("Title 1", { style: Title1 }),
						Ui.text("Headline", { style: Headline }),
						Ui.text("Body, the default", {}),
						Ui.text("Caption, in the secondary label colour", { style: Caption1, color: SecondaryLabel }),
						Ui.text("Monospaced 0123456789", { design: Monospaced }),
					],
				),
			),
			section(
				"COLOURS",
				Ui.vstack(
					{ spacing: 8 },
					[
						Ui.hstack(
							{ spacing: 10 },
							[("Red", Red), ("Orange", Orange), ("Yellow", Yellow), ("Green", Green), ("Teal", Teal), ("Blue", Blue), ("Indigo", Indigo), ("Purple", Purple), ("Pink", Pink), ("Slate", Adaptive({ light: 0x24404b, dark: 0x9fc3cf }))].map(swatch),
						),
						Ui.text(cells.pointed.signal().map(|name| if (name.is_empty()) "Point at a colour to name it" else name), theme.caption),
					],
				),
			),
		],
	)

## A small rounded square of one colour, which names itself while the
## pointer is over it.
swatch : (Str, Ui.Color) -> Elem(Engine.StoreRoot(_))
swatch = |(name, color)|
	Ui.hover(
		{ on_hover: Engine.handle(|inside| [cells.pointed.update(|shown| if (inside) name else if (shown == name) "" else shown)]) },
		Ui.box({ fill: color, radius: 6, padding: Zero, width: Fixed(26), height: Fixed(26) }, Ui.spacer()),
	)

shortcuts : () -> Elem(Engine.StoreRoot(_))
shortcuts = ||
	section(
		"SHORTCUTS",
		Ui.vstack(
			{ spacing: 8, align: Center, width: Fill },
			[
				Ui.text("${cells.presses.signal()}", { size: Fixed(48), weight: Light, design: MonospacedDigits }),
				Ui.hstack({ spacing: 6 }, [Ui.image("command", { color: SecondaryLabel }), Ui.text("Command-N counts a press, Command-K resets it.", theme.caption)]),
			],
		),
	)

summary : Str -> Str
summary = |notes| {
	lines = notes.split_on("\n").len()
	chars = notes.count_utf8_bytes()
	"${lines.to_str()} lines, ${chars.to_str()} bytes"
}

expect summary("a\nb") == "2 lines, 3 bytes"
