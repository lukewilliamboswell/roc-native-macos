app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
}

import cli.Monotonic
import cli.Stdout

## A nominal record of two dictionaries. `add` inserts a row and notes the
## key in `seen` with `Dict.update`, keeping a value already there. A loop
## that owns the bag adds n keys, so each `add` should be amortized
## constant time.
##
## It is linear in the size of the bag instead (the run is quadratic): one
## of the dictionaries is shared when `add` grows it, so it is copied, with
## an incref of every entry. Each of these changes alone makes it linear:
##
## * `seen.update(...)` written as
##   `if (seen.contains(key)) seen else seen.insert(key, Bool.True)`;
## * `Bag` a structural record (`Bag : { ... }` and `add` a plain
##   function) instead of a nominal one;
## * `Bag` with one dictionary (`rows` dropped);
## * `generated` called once instead of twice;
## * `generated` written as a recursive function instead of a `var` loop.
Bag :: { rows : Dict(U64, Str), seen : Dict(U64, Bool) }.{
	empty : {} -> Bag
	empty = |_| { rows: Dict.empty(), seen: Dict.empty() }

	len : Bag -> U64
	len = |bag| bag.rows.len()

	add : Bag, U64, Str -> Bag
	add = |bag, key, row| {
		{ rows, seen } = bag
		next_seen = seen.update(
			key,
			|found| match found {
				Ok(first) => Ok(first)
				Err(Missing) => Ok(Bool.True)
			},
		)
		{ rows: rows.insert(key, row), seen: next_seen }
	}
}

generated : U64 -> Bag
generated = |n| {
	var $b = Bag.empty({})
	for id in 0..<n {
		$b = $b.add(id, id.to_str())
	}
	$b
}

main! : List(_) => Try({}, _)
main! = |_args| {
	for n in [2000, 4000, 8000, 16000, 32000, 64000] {
		a = time!(|| generated(n).len())
		b = time!(|| generated(n + 1).len())
		Stdout.line!("n=${n.to_str()} ns per add: ${(a // n).to_str()}, ${(b // n).to_str()}")?
	}
	Ok({})
}

time! : (() -> U64) => U64
time! = |f| {
	start = Monotonic.now!()
	len = f()
	ns = Monotonic.elapsed!(start).to_nanos()
	if (len == 0) 0 else ns
}
