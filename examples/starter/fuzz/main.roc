app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.7.0/HBigHQhVZWEF2EkLxpYK35u8P6UNsAmPYxpNFTxXK1Br.tar.zst",
	logic: "../logic/main.roc",
}

import fuzz.Fuzz
import logic.Ledger
import logic.Money

## Fuzz targets for the business logic in `logic/`, built with roc-fuzz
## (https://github.com/lukewilliamboswell/roc-fuzz), a platform of its own:
## this is a development program, never part of the app, and it imports
## `logic` exactly as `src/main.roc` does.
##
## `roc macos.roc fuzz` builds it (`roc build --fuzz fuzz/main.roc`, into
## `.macos/fuzz`) and runs each target in turn for ten seconds;
## `roc macos.roc fuzz --check` runs only the declared examples, quickly, as
## CI does. A failure leaves a report and the failing input under
## `.roc-fuzz/`, which `.macos/fuzz --target=NAME replay INPUT` reproduces;
## roc-fuzz's manual covers `show`, `minimize` and keeping a failure as a
## regression example.
##
## To add a target: write a property as a function returning `Fuzz.keep`
## (or `Fuzz.reject` for an input outside it) that `crash`es when the
## property fails, wrap it in `Fuzz.target_with` with a unique `name`, and
## add it to `target` below. Good properties are round trips, invariants
## and "never crashes" checks of a parser.
target = Fuzz.suite([money_round_trip, money_parse, ledger_round_trip, ledger_import])

## Every amount formats to text that parses back to it.
money_round_trip = Fuzz.target_with({
	name: "money-round-trip",
	generator: Fuzz.u64_in(0, Money.most),
	test: |cents|
		if cents > Money.most {
			# Saved and mutated inputs bypass the generator's bound, so the
			# property states it again.
			Fuzz.reject
		} else if Money.parse(Money.format(cents)) == Ok(cents) {
			Fuzz.keep
		} else {
			crash "${Money.format(cents)} did not parse back to ${cents.to_str()}"
		},
	show: Str.inspect,
	examples: [
		Fuzz.example({ name: "zero", revision: "1", make: || 0 }),
		Fuzz.example({ name: "most", revision: "1", make: || Money.most }),
	],
})

## Any text either is not an amount, or is one that formats back to an
## amount equal to it, within the bound.
money_parse = Fuzz.target_with({
	name: "money-parse",
	generator: Fuzz.str,
	test: |text|
		match Money.parse(text) {
			Ok(cents) if cents > Money.most => crash "${Str.inspect(text)} parsed to ${cents.to_str()}, above Money.most"
			Ok(cents) if Money.parse(Money.format(cents)) != Ok(cents) => crash "${Str.inspect(text)} parsed to ${cents.to_str()}, which does not round-trip"
			_ => Fuzz.keep
		},
	show: Str.inspect,
	examples: [
		Fuzz.example({ name: "amount", revision: "1", make: || "4.50" }),
		Fuzz.example({ name: "not-an-amount", revision: "1", make: || "4.5.0" }),
	],
})

## An expense as roc-fuzz generates it: any text, any amount within the
## bound, and a byte that picks the category.
Generated := { title : Str, cents : U64, kind : U8 }.{
	parser_for : _
	encoder_for : _

	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Generated)
	generator_for = |_| { title: Fuzz.str, cents: Fuzz.u64_in(0, Money.most), kind: Fuzz.u8 }.Fuzz
}

## The expense a generated one stands for, with its title as the ledger
## keeps it; none when that title is empty, as `Ledger.entry` refuses it,
## or the amount is above `Money.most`, which saved and mutated inputs can
## hold because they bypass the generator.
expense : Generated -> Try(Ledger.Expense, [OutOfDomain])
expense = |generated| {
	title = Ledger.clean(generated.title)
	category = Ledger.categories.get(generated.kind.to_u64() % Ledger.categories.len()) ?? Other
	if (title.is_empty() or generated.cents > Money.most) Err(OutOfDomain) else Ok({ title, cents: generated.cents, category })
}

## The saved file reads back as exactly the expenses it was written from.
ledger_round_trip = Fuzz.target_with({
	name: "ledger-round-trip",
	generator: Fuzz.list(Generated.generator_for(Default), 8),
	test: |generated| {
		expenses = generated.keep_oks(expense)
		if Ledger.from_csv(Ledger.to_csv(expenses)) == { expenses, skipped: 0 } {
			Fuzz.keep
		} else {
			crash "the saved ledger did not read back as written"
		}
	},
	show: Str.inspect,
	examples: [
		Fuzz.example({ name: "empty", revision: "1", make: || [] }),
		Fuzz.example({ name: "comma-in-title", revision: "1", make: || [Generated.{ title: "Coffee, large", cents: 450, kind: 0 }] }),
	],
})

## Any text imports without crashing, and what it imports saves and
## reads back unchanged.
ledger_import = Fuzz.target_with({
	name: "ledger-import",
	generator: Fuzz.str,
	test: |text| {
		imported = Ledger.from_csv(text).expenses
		if Ledger.from_csv(Ledger.to_csv(imported)).expenses == imported {
			Fuzz.keep
		} else {
			crash "an imported ledger did not save and read back unchanged"
		}
	},
	show: Str.inspect,
	examples: [Fuzz.example({ name: "header-and-row", revision: "1", make: || "category,amount,title\nFood,4.50,Coffee\n" })],
})
