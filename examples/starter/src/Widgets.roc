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
## it, in an `Engine.state`, as `card`'s is.
Widgets := [].{

	## A figure under its caption, such as "Spent" over "12.50". The
	## summary shows three.
	stat : Str, Signal(ctx, Str) -> Elem(ctx)
	stat = |caption, value|
		Ui.box(
			{ padding: Axes({ horizontal: 12, vertical: 8 }), width: Fill },
			Ui.vstack(
				{ spacing: 2 },
				[
					Ui.text(Engine.const(caption), { style: Caption1, color: SecondaryLabel }),
					Ui.text(value, { style: Title3, weight: Semibold, design: MonospacedDigits, overflow: TruncateTail }),
				],
			),
		)

	## Whether a card shows its body.
	Shown : [Open, Closed]

	## A titled section whose body can be hidden: "Hide Summary" folds it
	## and "Show Summary" brings it back. Whether it is open is local state,
	## one for each card placed: no one else reads it, so it is not in the
	## store, and it starts open whenever the card is built. Hiding the
	## body disposes it, and with it any local state inside.
	##
	## The body is built inside the card's state, so it is a function of no
	## arguments that builds a view for any context, as `Home.summary` does.
	card : Str, (() -> Elem(In(ctx, Shown))) -> Elem(ctx)
	card = |title, body|
		Engine.state(
			Open,
			|shown| {
				open = shown.signal().map(|s| s == Open)
				Ui.vstack(
					{ spacing: 8, align: Fill },
					[
						Ui.hstack(
							{},
							[
								Ui.text(Engine.const(title), { style: Headline }),
								Ui.spacer(),
								Ui.button(
									open.map(|o| if (o) "Hide ${title}" else "Show ${title}"),
									{ on_press: shown.update(flipped), icon: Symbol("chevron.up.chevron.down"), title_display: Hidden, bezel: Borderless },
								),
							],
						),
						Engine.when(open, body, || Engine.text("")),
					],
				)
			},
		)
}

flipped : Widgets.Shown -> Widgets.Shown
flipped = |shown|
	match shown {
		Open => Closed
		Closed => Open
	}
