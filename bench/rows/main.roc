app [main] { pf: platform "../../platform/main.roc" }

import pf.Engine exposing [Elem, Signal, State, Table]
import pf.Ui

## The rows benchmark: N generated rows in a `Ui.list` (a view-based
## NSTableView, which makes views only for the rows in sight), filtered by a
## search field through the `table_view`'s query, with a selection, and,
## while "Tick" is on, an interval that changes the value of a few rows
## every 100 ms, to check that a change costs the rows it changes.
##
## N is the local storage key `rows-n` at launch, which `run.sh` passes as
## a command-line default (`-rows-n 100000`), so the mount itself builds the
## table and time to first display is honest. The list is a windowed
## `Ui.table_list`, or with `rows-list` set to `every` (`-rows-list every`)
## a `Ui.list` of a `table_view` drawing every row, to compare the two.
main : Engine.Program(_)
main = Engine.program_store(
	{ storage_keys: ["rows-n", "rows-build", "rows-list"] },
	|boot| store.with_initial(cells.rows, built(Engine.boot_storage(boot, "rows-build"), count_of(Engine.boot_storage(boot, "rows-n") ?? "10000"))),
	|boot| view(Engine.boot_storage(boot, "rows-list") == Ok("every")),
)

## The rows, built as `rows-build` says: `insert` inserts them one at a
## time (`inserted`), as `examples/contacts` does; anything else keys a
## list once (`generated`).
built : Try(Str, [Missing]), U64 -> Table(U64, Item)
built = |how, count| if (how == Ok("insert")) inserted(count) else generated(count)

## How many rows the ticker changes on each tick: the first few, so they
## are on screen.
ticked_rows : U64
ticked_rows = 3

Item : { name : Str, value : U64, search : Str }

store = Engine.store(
	Rows,
	{
		rows: Engine.table(Table.empty({})),
		search: Engine.cell(""),
		selected: Engine.cell(Nobody),
		ticking: Engine.cell(Bool.False),
	}.Engine.Cells,
)

cells = store.cells()

count_of : Str -> U64
count_of = |text| U64.from_str(text) ?? 10000

view : Bool -> Elem(Engine.StoreRoot(_))
view = |every| {
	shown = cells.rows.signal().map2(cells.selected.signal(), picked)
	ticking = cells.ticking.signal()
	Ui.vstack(
		{ spacing: 12, align: Fill, width: AtLeast(520) },
		[
			Ui.hstack(
				{ spacing: 8 },
				[
					Ui.image("magnifyingglass", { color: SecondaryLabel }),
					Ui.text_field(cells.search.signal(), { placeholder: "Filter rows", on_input: Engine.handle(|typed| [cells.search.set(typed)]), bezel: Rounded, width: Fill }),
					Ui.checkbox("Tick", { checked: ticking, on_change: Engine.handle(|on| [cells.ticking.set(on)]) }),
				],
			),
			if every {
				Ui.list(
					{ opening_height: 420 },
					Engine.table_view(
						cells.rows,
						{ query: cells.search.signal(), plan, window: Engine.const(Engine.every_row) },
						|key, item| row(key, item),
					),
				)
			} else {
				Ui.table_list({ opening_height: 420 }, cells.rows, { query: cells.search.signal(), plan }, |key, item| row(key, item))
			},
			Ui.text(shown.map(describe), { style: Caption1, color: SecondaryLabel, design: MonospacedDigits }),
			# While ticking, an interval changes the first rows' values.
			Engine.watch_latest(
				ticking,
				|on| if (on) [Engine.interval(100)] else [],
				Engine.react(|_, result| if (result.is_ok()) [cells.rows.update(bump)] else []),
			),
		],
	)
}

## One row: its name, and its value at the trailing edge.
row : Signal(r, U64), State(r, Item) -> Elem(r)
	where [r.store : () -> Engine.Reach(r, _)]
row = |key, item|
	Ui.row(
		{ on_select: Engine.handle_by(key, |id, _| [cells.selected.set(Picked(id))]), spacing: 8, padding: Axes({ horizontal: 4, vertical: 2 }) },
		[
			Ui.text(item.signal().map(|i| i.name), {}),
			Ui.spacer(),
			Ui.text(item.signal().map(|i| i.value.to_str()), { color: SecondaryLabel, design: MonospacedDigits }),
		],
	)

## The selected row, while it is in the table.
Shown : [Nobody, Shown(Item)]

picked : Table(U64, Item), [Nobody, Picked(U64)] -> Shown
picked = |table, selected|
	match selected {
		Nobody => Nobody
		Picked(id) =>
			match table.get(id) {
				Ok(item) => Shown(item)
				Err(_) => Nobody
			}
	}

describe : Shown -> Str
describe = |shown|
	match shown {
		Nobody => "No row selected"
		Shown(item) => "Selected ${item.name}, value ${item.value.to_str()}"
	}

## The rows whose name contains the filter text, in key order.
plan : Str -> Engine.QueryPlan(U64, Item, (U64, U64))
plan = |query| {
	needle = query.trim()
	Engine.sort_by({ keep: |_, item| item.search.contains(needle), sort: |key, _| key })
}

## One tick: the first `ticked_rows` rows' values go up by one.
bump : Table(U64, Item) -> Table(U64, Item)
bump = |table| {
	var $t = table
	for id in 0..<ticked_rows {
		$t = $t.update(id, |item| { ..item, value: item.value + 1 })
	}
	$t
}

words : List(Str)
words = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india", "juliett", "kilo", "lima", "mike", "november", "oscar", "papa", "quebec", "romeo", "sierra", "tango", "uniform", "victor", "whiskey", "xray", "yankee", "zulu"]

## `count` rows, a pure function of their keys, built as a list and keyed
## once (`Table.from_list`), as rows loaded from a file would be.
generated : U64 -> Table(U64, Item)
generated = |count| {
	var $entries = List.with_capacity(count)
	for id in 0..<count {
		$entries = $entries.append({ key: id, row: item_of(id) })
	}
	Table.from_list($entries) ?? Table.empty({})
}

## The same rows inserted one at a time. `run.sh --smoke` checks that this
## costs time linear in the rows (it was quadratic before engine patch 0004).
inserted : U64 -> Table(U64, Item)
inserted = |count| {
	var $table = Table.empty({})
	for id in 0..<count {
		$table = $table.insert(id, item_of(id))
	}
	$table
}

item_of : U64 -> Item
item_of = |id| {
	pick = |n| words.get(n % words.len()) ?? ""
	name = "${pick(id)} ${pick(id // words.len())} ${id.to_str()}"
	{ name, value: id % 1000, search: name }
}

expect item_of(27).name == "bravo bravo 27"
expect describe(picked(generated(30), Picked(2))) == "Selected charlie alpha 2, value 2"
expect bump(generated(5)).get(1) == Ok({ name: "bravo alpha 1", value: 2, search: "bravo alpha 1" })
expect built(Ok("insert"), 30).len() == 30 and inserted(30).get(29) == generated(30).get(29)
