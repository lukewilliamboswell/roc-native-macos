app [main] { pf: platform "../../../platform/main.roc" }

import pf.Engine exposing [Elem, Signal, State, Table]
import pf.Ui

## A to-do list based on the roc-signals tutorial. The store's table feeds
## a filtered view, with a checkbox and remove button in each row.
## Return or Command-N adds the draft. Local storage keeps the list across
## launches.
main : Engine.Program(_)
main = Engine.program_store({ storage_keys: ["todos"] }, start, |_boot| view())

Todo : { title : Str, done : Bool }

store = Engine.store(
	Todos,
	{
		todos: Engine.table(Table.empty({})),
		next: Engine.cell(0.U64),
		draft: Engine.cell(""),
	}.Engine.Cells,
)

cells = store.cells()

## The store a launch starts with: the saved to-dos under the keys 0, 1, 2
## and so on, and the key after the last as the next.
start : Engine.Boot -> Engine.Store(_, _)
start = |boot| {
	saved = decode(Engine.boot_storage(boot, "todos") ?? "")
	match Table.from_list(saved.map_with_index(|todo, index| { key: index, row: todo })) {
		Ok(todos) =>
			store
				.with_initial(cells.todos, todos)
				.with_initial(cells.next, saved.len())
		Err(DuplicateKey(place)) => crash "start: the saved place ${place.to_str()} repeats"
	}
}

## The saved list: one to-do per line in key order, `+` for done and `-`
## for open.
encode : Table(U64, Todo) -> Str
encode = |table| {
	rows = table.fold([], |found, key, todo| found.append({ key, todo })).sort_by(|held| held.key)
	Str.join_with(rows.map(|{ todo, .. }| "${if (todo.done) "+" else "-"}${todo.title}"), "\n")
}

## The to-dos a saved text holds, in its order. A line that starts with
## neither sign is skipped.
decode : Str -> List(Todo)
decode = |text|
	text.split_on("\n").keep_oks(
		|line|
			if line.starts_with("+") {
				Ok({ title: line.drop_prefix("+"), done: Bool.True })
			} else if line.starts_with("-") {
				Ok({ title: line.drop_prefix("-"), done: Bool.False })
			} else {
				Err(Blank)
			},
	)

## The looks the list shares, in one place.
Theme : {
	page : Ui.VStackProps,
	quiet : Ui.TextProps,
	panel : Ui.BoxProps,
}

theme : Theme
theme = {
	page: { spacing: 16, align: Fill, width: AtLeast(440), padding: All(8) },
	quiet: { style: Subheadline, color: SecondaryLabel, design: MonospacedDigits },
	panel: { fill: TextBackground, padding: Axes({ horizontal: 6, vertical: 8 }), border: Line({ color: Separator, width: 1 }), radius: 12, height: Fill },
}

## Which to-dos the list shows.
Filter : [All, Open, Done]

view : () -> Elem(Engine.StoreRoot(_))
view = || {
	todos = cells.todos.signal()
	Ui.vstack(
		theme.page,
		[
			Ui.hstack(
				{ align: FirstBaseline },
				[
					Ui.text("To-do", { style: LargeTitle, weight: Bold }),
					Ui.spacer(),
					Ui.text(todos.map(remaining), theme.quiet),
				],
			),

			## Every change to the table after mount is saved.
			Engine.watch_changes(todos.map(encode), |text| [Engine.command(StorageSet("todos", text))], Engine.ignore({})),
			Ui.form(
				{ on_submit: Engine.handle_by(adding(), |at, _| added(at)), align: Fill },
				[
					Ui.hstack(
						{},
						[
							Ui.text_field(cells.draft.signal(), { placeholder: "What needs doing?", on_input: Engine.handle(|typed| [cells.draft.set(typed)]), bezel: Rounded, size: Large, width: Fill }),
							Ui.submit_button("Add", { icon: Symbol("plus"), size: Large }),
						],
					),
				],
			),
			Engine.state(
				All,
				|showing| Ui.vstack(
					{ spacing: 10, align: Fill, height: Fill },
					[
						Ui.segmented(
							showing.signal().map(filter_name),
							{ choices: ["All", "Open", "Done"], on_change: showing.set_value(|held, name| filter_named(name) ?? held), width: Fill },
						),
						Engine.when(
							cells.todos.signal().map(|table| table.len() == 0),
							|| empty(),
							|| Ui.box(
								theme.panel,
								Ui.scroll(
									{ opening_height: 220, spacing: 2 },
									Engine.table_view(
										cells.todos,
										{ query: showing.signal(), plan, window: Engine.const(Engine.every_row) },
										|key, todo| row(key, todo),
									),
								),
							),
						),
					],
				),
			),
			# Command-N adds the draft too, from anywhere in the window.
			Ui.shortcut([Ui.command("n")], { on_key: Engine.handle_by(adding(), |at, _| added(at)) }),
		],
	)
}

## What the list shows before there is anything in it.
empty : () -> Elem(ctx)
empty = ||
	Ui.box(
		{ ..theme.panel, padding: All(28) },
		Ui.vstack(
			{ spacing: 6, align: Center, width: Fill },
			[
				Ui.image("checkmark.circle", { style: LargeTitle, color: TertiaryLabel }),
				Ui.text("Nothing to do", { style: Headline, color: SecondaryLabel }),
				Ui.text("Add a to-do above, or press Command-N.", { style: Caption1, color: TertiaryLabel }),
			],
		),
	)

## One row: the checkbox writes this to-do and no other; removing it is a
## decision over the whole table. A done to-do's title is greyed.
row : Signal(r, U64), State(r, Todo) -> Elem(r)
	where [r.store : () -> Engine.Reach(r, _)]
row = |key, todo| {
	held = todo.signal()
	Ui.hstack(
		{ padding: Axes({ horizontal: 8, vertical: 6 }) },
		[
			Ui.checkbox(held.map(|t| t.title), { checked: held.map(|t| t.done), on_change: todo.set_value(|was, checked| { ..was, done: checked }), title_display: Hidden }),
			Ui.text_s(held.map(|t| t.title), held.map(|t| if (t.done) { color: SecondaryLabel } else {})),
			Ui.spacer(),
			Ui.button(
				"Remove",
				{ on_press: Engine.handle_by(key, |id, _| [cells.todos.update(|table| table.remove(id))]), icon: Symbol("trash"), title_display: Hidden, bezel: Borderless },
			),
		],
	)
}

filter_name : Filter -> Str
filter_name = |filter|
	match filter {
		All => "All"
		Open => "Open"
		Done => "Done"
	}

## The filter a segment's title names.
filter_named : Str -> Try(Filter, [NotAFilter])
filter_named = |name|
	match name {
		"All" => Ok(All)
		"Open" => Ok(Open)
		"Done" => Ok(Done)
		_ => Err(NotAFilter)
	}

Adding : { title : Str, next : U64 }

adding : () -> Signal(ctx, Adding)
	where [ctx.store : () -> Engine.Reach(ctx, _)]
adding = ||
	{ draft: cells.draft.signal(), next: cells.next.signal() }.Signal.map(|{ draft, next }| { title: draft.trim(), next })

## A blank title writes nothing; any other adds the row, moves the key on
## and clears the draft, together.
added : Adding -> List(Engine.Write(_))
added = |{ title, next }|
	if title.is_empty() {
		[]
	} else {
		[
			cells.todos.update(|table| table.insert(next, { title, done: Bool.False })),
			cells.next.set(next + 1),
			cells.draft.set(""),
		]
	}

plan : [All, Open, Done] -> Engine.QueryPlan(U64, Todo, (U64, U64))
plan = |showing|
	Engine.sort_by({
		keep: |_, todo| match showing {
			All => Bool.True
			Open => !todo.done
			Done => todo.done
		},
		sort: |key, _| key,
	})

remaining : Table(U64, Todo) -> Str
remaining = |table|
	match table.fold(0.U64, |count, _, todo| if (todo.done) count else count + 1) {
		1 => "1 item left"
		count => "${count.to_str()} items left"
	}

## Adding a title inserts an open to-do and advances the next key.
expect {
	after = store.after(added({ title: "Buy milk", next: 0 }))
	after.read(cells.todos).get(0) == Ok({ title: "Buy milk", done: Bool.False }) and after.read(cells.next) == 1
}

## An empty title makes no changes.
expect added({ title: "", next: 3 }).is_empty()

## The saved text reads back as the same to-dos, in the order they were added.
expect {
	todos = [{ title: "Water the plants", done: Bool.False }, { title: "Buy milk", done: Bool.True }]
	table = Table.from_list(todos.map_with_index(|todo, index| { key: index, row: todo }))?
	encode(table) == "-Water the plants\n+Buy milk" and decode(encode(table)) == todos
}
