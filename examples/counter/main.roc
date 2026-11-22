app [main] { pf: platform "../../platform/main.roc" }

import pf.Engine exposing [Elem, In, Root, State]
import pf.Ui

## A counter: one piece of local state and three buttons that change it.
main : Engine.Program
main = Engine.program(|| Engine.state(0, view))

view : State(In(Root, I64), I64) -> Elem(In(Root, I64))
view = |count|
	Ui.vstack(
		{ spacing: 16, align: Center, padding: Axes({ horizontal: 24, vertical: 8 }), width: AtLeast(320) },
		[
			Ui.text("Counter", { style: Headline, color: SecondaryLabel }),

			## Interpolating a signal makes a text that follows it.
			Ui.text("${count.signal()}", { size: Fixed(64), weight: Light, design: MonospacedDigits }),
			Ui.hstack(
				{ spacing: 12 },
				[
					Ui.button("−", { on_press: count.update(|n| n - 1), icon: Symbol("minus"), title_display: Hidden, size: Large }),
					Ui.button("Reset", { on_press: count.update(|_| 0), size: Large, width: AtLeast(88) }),
					Ui.button("+", { on_press: count.update(|n| n + 1), icon: Symbol("plus"), title_display: Hidden, size: Large }),
				],
			),
			Ui.text("Each click is one engine turn.", { style: Caption1, color: TertiaryLabel }),
		],
	)
