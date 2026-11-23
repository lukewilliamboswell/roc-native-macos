import Money

## Expenses, and everything the app decides about them without a window:
## reading one from what a person typed, the totals, and the text format
## the app saves and imports.
Ledger := [].{

	## One thing bought: what it was, what it cost in cents, and its kind.
	Expense : { title : Str, cents : U64, category : Category }

	## The kinds of expense. Adding one here means adding it to
	## `categories` and `category_name` too; `category_named` follows.
	Category : [Food, Transport, Home, Fun, Other]

	## Every category, in the order the app offers them.
	categories : List(Category)
	categories = [Food, Transport, Home, Fun, Other]

	category_name : Category -> Str
	category_name = |category|
		match category {
			Food => "Food"
			Transport => "Transport"
			Home => "Home"
			Fun => "Fun"
			Other => "Other"
		}

	## The category a name names, as `category_name` writes it.
	category_named : Str -> Try(Category, [NotACategory])
	category_named = |name|
		match Ledger.categories.keep_if(|category| Ledger.category_name(category) == name) {
			[found] => Ok(found)
			_ => Err(NotACategory)
		}

	## An expense from one line of typing: a title, then the amount as its
	## last word. `"Coffee 4.50"` is a coffee for 450 cents.
	entry : Str, Category -> Try(Expense, [NoTitle, NoAmount])
	entry = |typed, category| {
		words = Ledger.clean(typed).split_on(" ").drop_if(Str.is_empty)
		amount = words.last().map_err(|_| NoAmount)?
		cents = Money.parse(amount).map_err(|_| NoAmount)?
		title = Str.join_with(words.drop_last(1), " ")
		if (title.is_empty()) Err(NoTitle) else Ok({ title, cents, category })
	}

	## A title as the ledger keeps it: line breaks and tabs become spaces,
	## and the ends are trimmed, so it always fits on one line of the file.
	clean : Str -> Str
	clean = |title| title.replace_each("\r", " ").replace_each("\n", " ").replace_each("\t", " ").trim()

	## What the totals show.
	Summary : { count : U64, total : U64, largest : Str }

	## The number of expenses, what they cost together, and the largest
	## one ("" when there is none).
	summary : List(Expense) -> Summary
	summary = |expenses| {
		total = expenses.fold(0, |sum, expense| sum + expense.cents)
		largest = expenses.fold(
			Err(NoneYet),
			|best, expense|
				match best {
					Ok(held) if held.cents >= expense.cents => best
					_ => Ok(expense)
				},
		)
		{
			count: expenses.len(),
			total,
			largest: match largest {
				Ok(expense) => "${expense.title}, ${Money.format(expense.cents)}"
				Err(NoneYet) => ""
			},
		}
	}

	## The text the app saves and imports: one expense per line, as
	## `Food,4.50,Coffee`. The title comes last, so it may hold commas.
	to_csv : List(Expense) -> Str
	to_csv = |expenses| Str.join_with(expenses.map(|expense| "${Ledger.category_name(expense.category)},${Money.format(expense.cents)},${expense.title}"), "\n")

	## The expenses a text holds, and how many of its lines (not counting
	## blank ones) are not an expense, such as a header row. An unknown
	## category is read as `Other`.
	from_csv : Str -> { expenses : List(Expense), skipped : U64 }
	from_csv = |text| {
		lines = text.split_on("\n").map(|line| line.drop_suffix("\r")).drop_if(|line| line.trim().is_empty())
		expenses = lines.keep_oks(Ledger.read_line)
		{ expenses, skipped: lines.len() - expenses.len() }
	}

	## One line of the file as an expense.
	read_line : Str -> Try(Expense, [NotAnExpense])
	read_line = |text|
		match text.split_on(",") {
			[kind, amount, .. as rest] => {
				title = Ledger.clean(Str.join_with(rest, ","))
				cents = Money.parse(amount).map_err(|_| NotAnExpense)?
				if (title.is_empty()) Err(NotAnExpense) else Ok({ title, cents, category: Ledger.category_named(kind.trim()) ?? Other })
			}
			_ => Err(NotAnExpense)
		}
}

expect Ledger.entry("Coffee 4.50", Food) == Ok({ title: "Coffee", cents: 450, category: Food })
expect Ledger.entry("  Train  to   town 12 ", Transport) == Ok({ title: "Train to town", cents: 1200, category: Transport })
expect Ledger.entry("Coffee", Food) == Err(NoAmount) and Ledger.entry("4.50", Food) == Err(NoTitle)

expect Ledger.categories.all(|category| Ledger.category_named(Ledger.category_name(category)) == Ok(category))

expect {
	summary = Ledger.summary([{ title: "Rent", cents: 90000, category: Home }, { title: "Tea", cents: 350, category: Food }])
	summary == { count: 2, total: 90350, largest: "Rent, 900.00" }
}

expect Ledger.summary([]) == { count: 0, total: 0, largest: "" }

## The saved text reads back as the same expenses; a header row and a
## line that is not an expense are counted as skipped.
expect {
	expenses = [{ title: "Coffee, large", cents: 450, category: Food }, { title: "Bus", cents: 280, category: Transport }]
	Ledger.to_csv(expenses) == "Food,4.50,Coffee, large\nTransport,2.80,Bus"
		and Ledger.from_csv(Ledger.to_csv(expenses)) == { expenses, skipped: 0 }
		and Ledger.from_csv("category,amount,title\r\nFood,4.50,Coffee, large\n\nnonsense\nGifts,10,Flowers\n") == { expenses: [{ title: "Coffee, large", cents: 450, category: Food }, { title: "Flowers", cents: 1000, category: Other }], skipped: 2 }
}
