import pf.Engine exposing [File, Table]
import logic.Ledger

## The app's shared state: the store, its cells, how a launch fills them,
## and the decisions that change them.
##
## State goes here when more than one part of the window reads or writes
## it, or it must outlive the piece of the view that shows it. State that
## one piece of the view cares about stays local to it, in an
## `Engine.state` (see `Home.form` and `Widgets.card`). A value that follows
## from other state is not state at all: `map` it, or `Engine.derive` it
## when it is costly or widely read (see `Home.summary`).
##
## A decision is a pure function that returns the writes it makes, such as
## `Store.added`. Views attach decisions to events (`Engine.handle_by`) and
## to answers (`Engine.react`) and decide nothing themselves, so every
## change of state is tested here with `expect`, with no window:
## `Store.store.after(writes).read(cell)` is the state after the writes.
##
## Only composing modules (`Home`, `Import`) import this one. A widget is
## handed what it needs instead, so that it works in any app.
Store := [Expenses].{

	## What the import site is doing: nothing, or reading a chosen file in
	## a worker (`Import`).
	Importing : [Idle, Reading(File)]

	## The store: its name, then its cells with their starting values.
	## Each cell changes independently, and a write wakes only the views
	## that read that cell, so keep separate concerns in separate cells.
	##
	## A store needs at least two cells: a record builder with a single
	## field (`{ a: Engine.cell(0) }.Engine.Cells`) compiles but fails at run
	## time with current compilers, which `roc test` reports.
	store = Engine.store(
		Store.Expenses,
		{

			## Every expense, by a key that only grows. A table keeps rows
			## by key, so writing one wakes only that row's views.
			expenses: Engine.table(Table.empty({})),
			importing: Engine.cell(Idle),

			## One line about the last thing that happened.
			notice: Engine.cell("Type what you bought and what it cost, then press Return."),
		}.Engine.Cells,
	)

	## The store's cells, for views and decisions to read and write.
	cells = Store.store.cells()

	## The local storage key the expenses are saved under. Every key the
	## app uses is declared to the program (`src/main.roc`).
	storage_key : Str
	storage_key = "expenses"

	## The store a launch starts with: the expenses saved last time
	## (`Home.saving` writes them), or none.
	start : Engine.Boot -> Engine.Store(_, _)
	start = |boot| {
		saved = Ledger.from_csv(Engine.boot_storage(boot, Store.storage_key) ?? "").expenses
		Store.store.with_initial(Store.cells.expenses, Store.keyed(saved))
	}

	## Expenses as a table, keyed 0, 1, 2 and so on in their order.
	keyed : List(Ledger.Expense) -> Table(U64, Ledger.Expense)
	keyed = |expenses|
		match Table.from_list(expenses.map_with_index(|expense, index| { key: index, row: expense })) {
			Ok(table) => table
			Err(DuplicateKey(key)) => crash "Store.keyed: the key ${key.to_str()} repeats"
		}

	## The expenses in the order they were added.
	in_order : Table(U64, Ledger.Expense) -> List(Ledger.Expense)
	in_order = |table| table.fold([], |found, key, expense| found.append({ key, expense })).sort_by(|held| held.key).map(|held| held.expense)

	## The key after every key in the table.
	next_key : Table(U64, Ledger.Expense) -> U64
	next_key = |table| table.fold(0, |next, key, _| if (key >= next) key + 1 else next)

	## Adding an expense: the table gains it under a new key, and the
	## notice says so.
	added : Ledger.Expense -> List(Engine.Write(_))
	added = |expense| [
		Store.cells.expenses.update(|table| table.insert(Store.next_key(table), expense)),
		Store.cells.notice.set("Added ${expense.title}."),
	]

	## Removing the expense under `key`.
	removed : U64 -> List(Engine.Write(_))
	removed = |key| [
		Store.cells.expenses.update(|table| table.remove(key)),
		Store.cells.notice.set("Removed an expense."),
	]

	## Removing every expense.
	cleared : List(Engine.Write(_))
	cleared = [
		Store.cells.expenses.set(Table.empty({})),
		Store.cells.notice.set("Cleared every expense."),
	]

	## A file chosen to import: the import site (`Import.site`) asks a
	## worker to read it.
	chosen : List(File) -> List(Engine.Write(_))
	chosen = |files|
		match files.first() {
			Ok(file) => [Store.cells.importing.set(Reading(file)), Store.cells.notice.set("Importing ${file.name()}…")]
			Err(_) => []
		}

	## What an import came to: the expenses it read, added after the
	## others, or why there were none.
	imported : Try({ name : Str, expenses : List(Ledger.Expense), skipped : U64 }, Str) -> List(Engine.Write(_))
	imported = |result|
		match result {
			Ok({ name, expenses, skipped }) => [
				Store.cells.expenses.update(|table| expenses.fold(table, |held, expense| held.insert(Store.next_key(held), expense))),
				Store.cells.importing.set(Idle),
				Store.cells.notice.set("Imported ${Store.counted(expenses.len())} from ${name}${Store.skipped_text(skipped)}."),
			]
			Err(why) => [Store.cells.importing.set(Idle), Store.cells.notice.set("Nothing was imported: ${why}.")]
		}

	counted : U64 -> Str
	counted = |n| if (n == 1) "1 expense" else "${n.to_str()} expenses"

	skipped_text : U64 -> Str
	skipped_text = |n|
		match n {
			0 => ""
			1 => "; 1 line was not an expense"
			_ => "; ${n.to_str()} lines were not expenses"
		}
}

## Adding writes the new expense under the next key, after the others.
expect {
	tea = { title: "Tea", cents: 350, category: Food }
	after = Store.store.after(Store.added(tea)).after(Store.added({ ..tea, title: "Cake" }))
	Store.in_order(after.read(Store.cells.expenses)).map(|expense| expense.title) == ["Tea", "Cake"] and after.read(Store.cells.notice) == "Added Cake."
}

## An import adds what it read after what was there, and stops importing.
expect {
	rent = { title: "Rent", cents: 90000, category: Home }
	after = Store.store.after(Store.added(rent)).after(Store.imported(Ok({ name: "march.csv", expenses: [rent, rent], skipped: 1 })))
	Store.in_order(after.read(Store.cells.expenses)).len() == 3
		and after.read(Store.cells.importing) == Idle
		and after.read(Store.cells.notice) == "Imported 2 expenses from march.csv; 1 line was not an expense."
}

## Removing one key leaves the rest; the next key follows the largest.
expect {
	tea = { title: "Tea", cents: 350, category: Food }
	after = Store.store.after(Store.added(tea)).after(Store.added(tea)).after(Store.removed(0))
	Store.next_key(after.read(Store.cells.expenses)) == 2 and after.read(Store.cells.expenses).len() == 1
}
