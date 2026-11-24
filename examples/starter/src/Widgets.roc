import pf.Engine exposing [Elem, In, Signal]
import pf.Ui

## Reusable widgets: views that any screen can place, as often as it
## likes. A widget is handed everything it shows (values, signals, a
## handler or a view to wrap) and never imports `Store`, so it knows
## nothing of this app and can move to another one unchanged.
##
## To add a widget, write a function here that returns `Elem(ctx)` for
## any `ctx`, taking its subject first and what it needs after, as
## `Ui`'s own builders do. State only the widget cares about is local to
## it, in an `Engine.state`, as `section`'s and `confirm_button`'s are.
Widgets := [].{

	## Whether a section shows its body.
	Shown : [Open, Closed]

	## A titled part of a panel whose body can be folded away: "Hide Layer 1"
	## folds it and "Show Layer 1" brings it back. Whether it is open is
	## local state, one for each section placed: no one else reads it, so it
	## is not in the store, and it starts open whenever the section is built.
	## Hiding the body disposes it, and with it any local state inside. The
	## EQ's bands and each layer of the preset editor are sections.
	##
	## The body is built inside the section's state, so it is a function of
	## no arguments that builds a view for any context.
	section : Signal(ctx, Str), (() -> Elem(In(ctx, Shown))) -> Elem(ctx)
	section = |title, body|
		Engine.state(
			Open,
			|shown| {
				open = shown.signal().map(|s| s == Open)
				named = title.lift()
				Ui.vstack(
					{ spacing: 6, align: Fill },
					[
						Ui.hstack(
							{},
							[
								Ui.text(named, { style: Subheadline, weight: Semibold }),
								Ui.spacer(),
								Ui.button(
									{ o: open, t: named }.Signal.map(|x| if (x.o) "Hide ${x.t}" else "Show ${x.t}"),
									{ on_press: shown.update(Widgets.flipped), icon: Symbol("chevron.up.chevron.down"), title_display: Hidden, bezel: Borderless },
								),
							],
						),
						Engine.when(open, body, || Engine.text("")),
					],
				)
			},
		)

	flipped : Shown -> Shown
	flipped = |shown|
		match shown {
			Open => Closed
			Closed => Open
		}

	## Whether a confirm button is asking.
	Asking : [Idle, Asking]

	## A button for something that cannot be undone, such as deleting a
	## preset or clearing the queue: pressing it asks first, with a
	## destructive button titled `confirm` beside Cancel, and only that runs
	## `on_confirm`. Whether it is asking is local state, one for each button.
	confirm_button : Str, Str, Engine.HandlerOf(ctx, Engine.Click), Signal(ctx, Bool) -> Elem(ctx)
	confirm_button = |title, confirm, on_confirm, enabled|
		Engine.state(
			Idle,
			|asking| {
				held = asking.signal()
				Engine.when(
					held.map(|a| a == Asking),
					|| Ui.hstack(
						{ spacing: 4 },
						[
							Ui.button(Engine.const(confirm), { on_press: on_confirm.lift().also(asking.update(|_| Idle)), role: Destructive, size: Small }),
							Ui.button("Cancel", { on_press: asking.update(|_| Idle), role: Cancel, size: Small }),
						],
					),
					|| Ui.button(Engine.const(title), { on_press: asking.update(|_| Asking), enabled: enabled.lift(), size: Small }),
				)
			},
		)

	## A labelled slider with its value beside it, such as an EQ band:
	## `label`, the slider over `range`, and `readout` (the value as text).
	labelled_slider : Str, Signal(ctx, I64), { min : I64, max : I64 }, Engine.Handler(ctx), Signal(ctx, Str) -> Elem(ctx)
	labelled_slider = |label, value, range, on_input, readout|
		Ui.hstack(
			{ spacing: 8 },
			[
				Ui.text(Engine.const(label), { style: Caption1, color: SecondaryLabel, width: Fixed(64), align: Trailing }),
				Ui.slider(value, { range, on_input, width: Fill }),
				Ui.text(readout, { style: Caption1, design: MonospacedDigits, width: Fixed(64) }),
			],
		)
}

expect Widgets.flipped(Widgets.flipped(Open)) == Open
