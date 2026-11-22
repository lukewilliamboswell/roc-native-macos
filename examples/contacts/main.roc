app [main] { pf: platform "../../platform/main.roc" }

import pf.Engine exposing [Elem, Signal, State, Table]
import pf.Ui

## Ten thousand generated contacts in a `Ui.list` (a view-based
## NSTableView): a search field filters them through the `table_view`'s
## query, and selecting a row shows that contact below the list.
main : Engine.Program(_)
main = Engine.program_store({}, |_boot| store.with_initial(cells.contacts, generated(contact_count)), |_boot| view())

contact_count : U64
contact_count = 10000

Contact : { name : Str, email : Str, city : Str, search : Str }

store = Engine.store(
	Contacts,
	{
		contacts: Engine.table(Table.empty({})),
		search: Engine.cell(""),
		selected: Engine.cell(Nobody),
	}.Engine.Cells,
)

cells = store.cells()

view : () -> Elem(Engine.StoreRoot(_))
view = || {
	contacts = cells.contacts.signal()
	Ui.vstack(
		{ spacing: 10, align: Fill },
		[
			Ui.title("Contacts"),
			Ui.hstack(
				{},
				[
					Ui.text_field("Search names and cities", cells.search.signal(), Engine.handle(|typed| [cells.search.set(typed)])),
					Ui.text_s({ font: Caption, color: Secondary }, contacts.map2(cells.search.signal(), matching)),
				],
			),
			Ui.list(
				{ height: 360 },
				Engine.table_view(
					cells.contacts,
					{ query: cells.search.signal(), plan, window: Engine.const(Engine.every_row) },
					|key, contact| row(key, contact),
				),
			),
			Ui.hstack(
				{},
				[
					Ui.image("person.crop.circle.fill", Accent),
					Ui.text_s({ font: Headline }, contacts.map2(cells.selected.signal(), detail)),
				],
			),
		],
	)
}

## One row: selecting it selects this contact.
row : Signal(r, U64), State(r, Contact) -> Elem(r)
	where [r.store : () -> Engine.Reach(r, _)]
row = |key, contact|
	Ui.row(
		Engine.handle_by(key, |id, _| [cells.selected.set(Picked(id))]),
		[
			Ui.image("person.crop.circle", Secondary),
			Ui.vstack(
				{ spacing: 2 },
				[
					Ui.text_s({}, contact.signal().map(|c| c.name)),
					Ui.text_s({ font: Caption, color: Secondary }, contact.signal().map(|c| "${c.email} · ${c.city}")),
				],
			),
		],
	)

## The rows whose name or city contains the search text, ignoring ASCII
## case, in id order.
plan : Str -> Engine.QueryPlan(U64, Contact, (U64, U64))
plan = |query| {
	needle = lower(query.trim())
	Engine.sort_by({ keep: |_, contact| contact.search.contains(needle), sort: |key, _| key })
}

matching : Table(U64, Contact), Str -> Str
matching = |table, query| {
	needle = lower(query.trim())
	count = table.fold(0.U64, |n, _, contact| if (contact.search.contains(needle)) n + 1 else n)
	"${count.to_str()} of ${table.len().to_str()}"
}

detail : Table(U64, Contact), [Nobody, Picked(U64)] -> Str
detail = |table, selected|
	match selected {
		Nobody => "Select a contact"
		Picked(id) =>
			match table.get(id) {
				Ok(contact) => "${contact.name} <${contact.email}>, ${contact.city}"
				Err(_) => "Select a contact"
			}
	}

## ASCII lower case.
lower : Str -> Str
lower = |text| Str.from_utf8(text.to_utf8().map(|b| if (b >= 65 and b <= 90) b + 32 else b)) ?? text

firsts : List(Str)
firsts = ["Ada", "Alan", "Barbara", "Claude", "Dennis", "Edsger", "Frances", "Grace", "Hedy", "Ivan", "Joan", "Ken", "Leslie", "Margaret", "Niklaus", "Ole", "Peter", "Radia", "Robin", "Shafi", "Tony", "Ursula", "Vint", "Whitfield", "Xavier", "Yukihiro", "Zuse"]

lasts : List(Str)
lasts = ["Lovelace", "Turing", "Liskov", "Shannon", "Ritchie", "Dijkstra", "Allen", "Hopper", "Lamarr", "Sutherland", "Clarke", "Thompson", "Lamport", "Hamilton", "Wirth", "Dahl", "Naur", "Perlman", "Milner", "Goldwasser", "Hoare", "Franklin", "Cerf", "Diffie", "Leroy", "Matsumoto", "Knuth", "Backus", "McCarthy", "Kay"]

cities : List(Str)
cities = ["Amsterdam", "Berlin", "Cambridge", "Dublin", "Edinburgh", "Helsinki", "Kyoto", "Lisbon", "Melbourne", "Oslo", "Paris", "Toronto", "Zurich"]

initials : List(Str)
initials = ["A", "B", "C", "D", "E", "F", "G", "H", "J", "K", "L", "M", "N", "P", "R", "S", "T", "W"]

## `count` contacts, a pure function of their ids.
generated : U64 -> Table(U64, Contact)
generated = |count| {
	var $table = Table.empty({})
	for id in 0..<count {
		$table = $table.insert(id, contact_of(id))
	}
	$table
}

contact_of : U64 -> Contact
contact_of = |id| {
	pick = |names, n| names.get(n % names.len()) ?? ""
	first = pick(firsts, id)
	last = pick(lasts, id // firsts.len())
	initial = pick(initials, id // (firsts.len() * lasts.len()))
	city = pick(cities, id // 7)
	name = "${first} ${initial}. ${last}"
	{ name, email: "${lower(first)}.${lower(last)}${id.to_str()}@example.com", city, search: lower("${name} ${city}") }
}

expect lower("Ada LOVELACE") == "ada lovelace"

expect contact_of(28).name == "Alan A. Turing"

expect matching(generated(30), "ada") == "2 of 30"
