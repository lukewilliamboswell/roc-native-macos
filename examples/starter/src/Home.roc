import pf.Engine exposing [Elem, Signal, State]
import pf.Ui
import logic.Ledger
import logic.Money
import Import
import Store
import Widgets

## The window: the one screen of the app, composed from the store's cells,
## the widgets and the import site. This is a composing module: it imports
## `Store` and hands each widget what it shows.
##
## A view runs once, when the window opens. After that, a write wakes only
## the texts, rows and branches that read what it wrote, so a view reads
## state through signals (`cell.signal()`, `state.signal()`, `.map`) and
## never holds a value it read once.
##
## To add a screen, write a module like this one with a `view`, and switch
## between screens with `Ui.tabs` or `Engine.switch` over a cell that says
## which is shown; leaving a screen disposes its local state and its
## effect sites.
Home := [].{

	## The whole window, which `src/main.roc` mounts.
	view : () -> Elem(Engine.StoreRoot(_))
	view = ||
		Ui.vstack(
			{ spacing: 14, align: Fill, width: AtLeast(480), padding: Axes({ horizontal: 4, vertical: 4 }) },
			[
				Ui.hstack(
					{ spacing: 10 },
					[
						## `assets/icon.png` is also the app's icon.
						Ui.asset_image("icon.png", { width: Fixed(36) }),
						Ui.text("Expenses", { style: LargeTitle, weight: Bold }),
					],
				),
				Home.form(),

				## One widget, two cards, each with its own open state.
				Widgets.card("Summary", || Home.summary()),
				Widgets.card("Expenses", || Home.expenses()),
				Ui.text(Store.cells.notice.signal(), { style: Callout, color: SecondaryLabel, overflow: Wrap, width: Fill }),
				Import.site(),
				Home.saving(),
			],
		)

	## What the form holds while a person types: local state, because only
	## the form reads it, and it should start empty whenever the form does.
	Draft : { text : Str, category : Str, problem : Str }

	blank : Draft
	blank = { text: "", category: "Food", problem: "" }

	## A line to type an expense into ("Coffee 4.50"), its category and an
	## Add button; Return adds it too. Submitting composes two handlers: the
	## store's decision, read from the draft as it was submitted, and then
	## the draft's own change, which clears it or explains the problem.
	form : () -> Elem(ctx)
		where [ctx.store : () -> Engine.Reach(ctx, _)]
	form = ||
		Engine.state(
			Home.blank,
			|draft| {
				held = draft.signal()
				submit = Engine.handle_by(held, |typed, _| Home.submitted(typed)).also(draft.update(Home.answered))
				Ui.form(
					{ on_submit: submit, align: Fill },
					[
						Ui.hstack(
							{},
							[
								Ui.text_field(held.map(|d| d.text), { placeholder: "Coffee 4.50", on_input: draft.set_value(|d, typed| { ..d, text: typed, problem: "" }), bezel: Rounded, width: Fill }),
								Ui.dropdown(held.map(|d| d.category), { choices: Ledger.categories.map(Ledger.category_name), on_change: draft.set_value(|d, chosen| { ..d, category: chosen }) }),
								Ui.submit_button("Add", { icon: Symbol("plus") }),
							],
						),
						Engine.when(held.map(|d| !d.problem.is_empty()), || Ui.text(held.map(|d| d.problem), { style: Caption1, color: Red }), || Engine.text("")),
					],
				)
			},
		)

	## The expense a draft stands for, if it is one.
	entry : Draft -> Try(Ledger.Expense, [NoTitle, NoAmount])
	entry = |draft| Ledger.entry(draft.text, Ledger.category_named(draft.category) ?? Other)

	## What submitting writes to the store: the expense, or nothing.
	submitted : Draft -> List(Engine.Write(_))
	submitted = |draft|
		match Home.entry(draft) {
			Ok(expense) => Store.added(expense)
			Err(_) => []
		}

	## The draft after submitting: empty again, keeping the category, or
	## saying what is missing.
	answered : Draft -> Draft
	answered = |draft|
		match Home.entry(draft) {
			Ok(_) => { ..draft, text: "", problem: "" }
			Err(NoAmount) => { ..draft, problem: "End with what it cost, as in “Coffee 4.50”." }
			Err(NoTitle) => { ..draft, problem: "Start with what it was, as in “Coffee 4.50”." }
		}

	## Three figures over the expenses. `Engine.derive` computes the
	## summary once per change of the table, and the three `stat`s read it.
	summary : () -> Elem(ctx)
		where [ctx.store : () -> Engine.Reach(ctx, _)]
	summary = ||
		Engine.derive(
			Store.cells.expenses.signal().map(|table| Ledger.summary(Store.in_order(table))),
			|totals|
				Ui.hstack(
					{ spacing: 10, distribution: FillEqually },
					[
						Widgets.stat("Spent", totals.map(|s| Money.format(s.total))),
						Widgets.stat("Expenses", totals.map(|s| s.count.to_str())),
						Widgets.stat("Largest", totals.map(|s| if (s.largest.is_empty()) "None yet" else s.largest)),
					],
				),
		)

	## The list, newest first, with its import and clear buttons.
	expenses : () -> Elem(ctx)
		where [ctx.store : () -> Engine.Reach(ctx, _)]
	expenses = ||
		Ui.vstack(
			{ spacing: 8, align: Fill },
			[
				Ui.hstack(
					{},
					[
						Ui.file_button("Import CSV…", { on_files: Engine.handle(|received| Store.chosen(received.files)), icon: Symbol("square.and.arrow.down") }),
						Ui.spacer(),
						Ui.button("Clear All", { on_press: Engine.does(Store.cleared), enabled: Store.cells.expenses.signal().map(|table| table.len() > 0) }),
					],
				),
				Engine.when(
					Store.cells.expenses.signal().map(|table| table.len() == 0),
					|| Ui.text("No expenses yet.", { style: Callout, color: TertiaryLabel }),
					|| Ui.box(
						{ padding: Axes({ horizontal: 4, vertical: 6 }), border: Line({ color: Separator, width: 1 }) },
						Ui.scroll(
							{ opening_height: 180, spacing: 2 },
							Engine.table_view(
								Store.cells.expenses,
								{ query: Engine.const(NewestFirst), plan: Home.plan, window: Engine.const(Engine.every_row) },
								|key, expense| Home.row(key, expense),
							),
						),
					),
				),
			],
		)

	## Which rows the list shows, in what order: every row, newest first.
	plan : [NewestFirst] -> Engine.QueryPlan(U64, Ledger.Expense, (U64, U64))
	plan = |_| Engine.sort_by({ keep: |_, _| Bool.True, sort: |key, _| U64.highest - key })

	## One row of the list. The row reads its own expense, so changing one
	## row wakes that row alone; removing it is a decision on the store.
	row : Signal(r, U64), State(r, Ledger.Expense) -> Elem(r)
		where [r.store : () -> Engine.Reach(r, _)]
	row = |key, expense| {
		held = expense.signal()
		Ui.hstack(
			{ padding: Axes({ horizontal: 8, vertical: 3 }) },
			[
				Ui.text(held.map(|e| e.title), { squeeze: Yield, overflow: TruncateTail }),
				Ui.spacer(),
				Ui.text(held.map(|e| Ledger.category_name(e.category)), { style: Caption1, color: SecondaryLabel }),
				Ui.text(held.map(|e| Money.format(e.cents)), { design: MonospacedDigits }),
				Ui.button("Remove", { on_press: Engine.handle_by(key, |id, _| Store.removed(id)), icon: Symbol("trash"), title_display: Hidden, bezel: Borderless }),
			],
		)
	}

	## The site that saves the expenses whenever they change, read back at
	## the next launch (`Store.start`). `Engine.watch_changes` never cancels
	## a save it asked for.
	saving : () -> Elem(ctx)
		where [ctx.store : () -> Engine.Reach(ctx, _)]
	saving = ||
		Engine.watch_changes(
			Store.cells.expenses.signal().map(|table| Ledger.to_csv(Store.in_order(table))),
			|text| [Engine.command(StorageSet(Store.storage_key, text))],
			Engine.ignore({}),
		)
}

## A draft with an amount becomes an expense and empties; one without
## keeps its text and says why.
expect {
	typed = { ..Home.blank, text: "Coffee 4.50" }
	after = Store.store.after(Home.submitted(typed))
	after.read(Store.cells.expenses).len() == 1 and Home.answered(typed).text == ""
}

expect {
	typed = { ..Home.blank, text: "Coffee" }
	Home.submitted(typed).is_empty() and Home.answered(typed).text == "Coffee" and !Home.answered(typed).problem.is_empty()
}
