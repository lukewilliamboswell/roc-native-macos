app [main] { pf: platform "../../platform/main.roc" }

import pf.Engine exposing [Elem, Signal, State, Table]
import pf.Ui

## A to-do list, after the roc-signals tutorial: a table of to-dos in the
## store, a form that adds one, a filtered view of the table whose rows each
## own a checkbox and a remove button, and a count of what is left. The
## list is saved under the local storage key `todos` and read back at boot.
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

view : () -> Elem(Engine.StoreRoot(_))
view = || {
	todos = cells.todos.signal()
	Ui.vstack(
		[
			Ui.title("To-do"),
			## Every change to the table after mount is saved.
			Engine.watch_changes(todos.map(encode), |text| [Engine.command(StorageSet("todos", text))], Engine.ignore({})),
			Ui.form(
				Engine.handle_by(adding(), |at, _| added(at)),
				[
					Ui.hstack(
						[
							Ui.text_field("What needs doing?", cells.draft.signal(), Engine.handle(|typed| [cells.draft.set(typed)])),
							Ui.submit_button("Add"),
						],
					),
				],
			),
			Engine.state(
				All,
				|showing| Ui.vstack(
					[
						Ui.hstack(
							[
								Ui.button("All", showing.update(|_| All)),
								Ui.button("Open", showing.update(|_| Open)),
								Ui.button("Done", showing.update(|_| Done)),
							],
						),
						Ui.divider(),
						Ui.vstack(
							[
								Engine.table_view(
									cells.todos,
									{ query: showing.signal(), plan, window: Engine.const(Engine.every_row) },
									|key, todo| row(key, todo),
								),
							],
						),
					],
				),
			),
			Engine.when(todos.map(|table| table.len() == 0), || Ui.label("Nothing to do."), || Engine.text("")),
			Ui.label_s(todos.map(remaining)),
		],
	)
}

## One row: the checkbox writes this to-do and no other; removing it is a
## decision over the whole table.
row : Signal(r, U64), State(r, Todo) -> Elem(r)
	where [r.store : () -> Engine.Reach(r, _)]
row = |key, todo|
	Ui.hstack(
		[
			Ui.checkbox(todo.signal().map(|t| t.title), todo.signal().map(|t| t.done), todo.set_value(|held, checked| { ..held, done: checked })),
			Ui.spacer(),
			Ui.button("Remove", Engine.handle_by(key, |id, _| [cells.todos.update(|table| table.remove(id))])),
		],
	)

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

expect {
	after = store.after(added({ title: "Buy milk", next: 0 }))
	after.read(cells.todos).get(0) == Ok({ title: "Buy milk", done: Bool.False }) and after.read(cells.next) == 1
}

expect added({ title: "", next: 3 }).is_empty()

## The saved text reads back as the same to-dos, in the order they were added.
expect {
	todos = [{ title: "Water the plants", done: Bool.False }, { title: "Buy milk", done: Bool.True }]
	table = Table.from_list(todos.map_with_index(|todo, index| { key: index, row: todo }))?
	encode(table) == "-Water the plants\n+Buy milk" and decode(encode(table)) == todos
}
