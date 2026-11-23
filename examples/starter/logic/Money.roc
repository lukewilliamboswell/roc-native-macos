## Amounts of money as whole cents in a `U64`, so that every sum is exact:
## `Money.parse("4.50") == Ok(450)` and `Money.format(450) == "4.50"`.
##
## Two properties hold for every amount, and `fuzz/main.roc` checks them
## with roc-fuzz: formatting then parsing gives the amount back, and any
## text `parse` accepts formats to text that parses to the same amount.
Money := [].{

	## The largest amount `parse` accepts: fifteen digits of whole units and
	## two of cents. Bounding it keeps `whole * 100 + cents` from overflowing.
	most : U64
	most = 99_999_999_999_999_999

	## The cents a text means: `"12"` is 1200, `"4.5"` 450 and `"0.05"` 5.
	## Spaces around it are ignored. It takes digits, then optionally a dot
	## and one or two digits: no sign, no currency symbol and no thousands
	## separator, and nothing above `Money.most`.
	parse : Str -> Try(U64, [NotAnAmount])
	parse = |text|
		match text.trim().split_on(".") {
			[whole] => Money.cents(whole, "")
			[whole, part] if !part.is_empty() => Money.cents(whole, part)
			_ => Err(NotAnAmount)
		}

	## Whole units and up to two digits of a fraction, as cents.
	cents : Str, Str -> Try(U64, [NotAnAmount])
	cents = |whole, part| {
		if whole.is_empty() or whole.count_utf8_bytes() > 15 or part.count_utf8_bytes() > 2 {
			return Err(NotAnAmount)
		}
		units = Money.digits(whole)?
		fraction = if (part.is_empty()) 0 else Money.digits(part)?
		# "4.5" is 4 units and 50 cents; "4.05" is 4 and 5.
		scaled = if (part.count_utf8_bytes() == 1) fraction * 10 else fraction
		Ok(units * 100 + scaled)
	}

	## A run of ASCII digits as a number. `U64.from_str` alone would also
	## take a sign or an underscore, which an amount never has.
	digits : Str -> Try(U64, [NotAnAmount])
	digits = |text|
		if text.to_utf8().all(|byte| byte >= '0' and byte <= '9') {
			U64.from_str(text).map_err(|_| NotAnAmount)
		} else {
			Err(NotAnAmount)
		}

	## Cents as text with two decimals: `Money.format(1205) == "12.05"`.
	format : U64 -> Str
	format = |amount| {
		part = amount % 100
		"${(amount // 100).to_str()}.${if (part < 10) "0" else ""}${part.to_str()}"
	}
}

expect Money.parse("12") == Ok(1200)
expect Money.parse(" 4.5 ") == Ok(450)
expect Money.parse("0.05") == Ok(5)
expect Money.format(1205) == "12.05" and Money.format(0) == "0.00"

## Text that is not an amount is refused, never misread.
expect ["", ".", "4.", ".5", "4.505", "-3", "+3", "1_000", "1,000", "$5", "4.5.6"].all(|text| Money.parse(text) == Err(NotAnAmount))

## The largest amount round-trips; one more digit is refused.
expect Money.parse(Money.format(Money.most)) == Ok(Money.most) and Money.parse("1000000000000000") == Err(NotAnAmount)
