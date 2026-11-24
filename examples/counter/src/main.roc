app [main] { pf: platform "../../../platform/main.roc" }

import pf.Engine exposing [Elem, In, Root, State]
import pf.Ui

## A counter: one piece of local state and three buttons that change it.
## `Engine.state(0, view)` holds the count, starting at 0, and builds the
## window once with `view`; after that, a change to the count updates only
## what depends on it.
main : Engine.Program
main = Engine.program(|| Engine.state(0, view))

## The window's contents. `count` is the state: `count.signal()` reads it
## where the view shows it, and `count.update` makes an action that changes
## it, such as a button's `on_press`.
view : State(In(Root, I64), I64) -> Elem(In(Root, I64))
view = |count|
	Ui.vstack(
		{ spacing: 16, align: Center, padding: Axes({ horizontal: 24, vertical: 14 }), width: AtLeast(320) },
		[
			Ui.text("Counter", { style: Headline, color: SecondaryLabel }),

			## Interpolating a signal makes a text that follows it.
			Ui.box(
				{ fill: ControlBackground, border: Line({ color: Separator, width: 1 }), radius: 16, padding: All(16), width: Fill },
				Ui.text("${count.signal()}", { size: Fixed(72), weight: Medium, design: MonospacedDigits, align: Center, width: Fill }),
			),

			## The specs in tests/specs/ find these buttons by their titles,
			## so the hidden titles "−" and "+" still matter.
			Ui.hstack(
				{ spacing: 12 },
				[
					Ui.button("−", { on_press: count.update(|n| n - 1), icon: Symbol("minus"), title_display: Hidden, size: Large }),
					Ui.button("Reset", { on_press: count.update(|_| 0), size: Large, width: AtLeast(88) }),
					Ui.button("+", { on_press: count.update(|n| n + 1), icon: Symbol("plus"), title_display: Hidden, size: Large }),
				],
			),
		],
	)
