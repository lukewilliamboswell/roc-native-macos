app [main] { pf: platform "../../platform/main.roc" }

import pf.Engine exposing [Elem, In, Root, State]
import pf.Ui

## A counter: one piece of local state and three buttons that change it.
main : Engine.Program
main = Engine.program(|| Engine.state(0, view))

view : State(In(Root, I64), I64) -> Elem(In(Root, I64))
view = |count|
	Ui.vstack(
		{},
		[
			Ui.title("Counter"),
			Ui.readout_s(count.signal().map(|n| n.to_str())),
			Ui.hstack(
				{},
				[
					Ui.button("−", count.update(|n| n - 1)),
					Ui.button("Reset", count.update(|_| 0)),
					Ui.button("+", count.update(|n| n + 1)),
				],
			),
		],
	)
