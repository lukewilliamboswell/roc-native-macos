app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
}

import cli.Monotonic
import cli.Stdout

## A record holding a large dictionary and one more refcounted field, and a
## write that takes the record apart, inserts into the dictionary and puts
## the record back together. Called three times in a loop on a record the
## loop owns, each insert should be in place: constant time, whatever the
## size of the dictionary.
##
## `put_let` takes the record apart with a destructuring statement,
## `put_param` with a parameter pattern and `put_match` with a `match`.
## Otherwise the three are the same. In an optimized build, `put_let` and
## `put_param` copy the dictionary on every call once the loop that calls
## them is a procedure of its own (each loop has a second caller, `once`,
## so it is not inlined), the record has a second refcounted field
## (`other`; any list, string or dictionary) and the dictionary's values
## are refcounted (`Item` holds a `Str`). Removing any of these, or
## calling `put_let` three times without a loop, makes it constant again.
## `put_match` is constant in every case.
Item : { name : Str, value : U64 }

T : { rows : Dict(U64, Item), other : Str, version : U64 }

put_let : T, U64, Item -> T
put_let = |t, key, row| {
	{ rows, other, version } = t
	{ rows: rows.insert(key, row), other, version: version + 1 }
}

put_param : T, U64, Item -> T
put_param = |{ rows, other, version }, key, row| { rows: rows.insert(key, row), other, version: version + 1 }

put_match : T, U64, Item -> T
put_match = |t, key, row| match t {
	{ rows, other, version } => { rows: rows.insert(key, row), other, version: version + 1 }
}

three_let : T -> T
three_let = |table| {
	var $t = table
	for id in 0..<3.U64 {
		$t = put_let($t, id, { name: "x", value: id })
	}
	$t
}

three_param : T -> T
three_param = |table| {
	var $t = table
	for id in 0..<3.U64 {
		$t = put_param($t, id, { name: "x", value: id })
	}
	$t
}

three_match : T -> T
three_match = |table| {
	var $t = table
	for id in 0..<3.U64 {
		$t = put_match($t, id, { name: "x", value: id })
	}
	$t
}

turns_let : T, U64 -> T
turns_let = |t, k| {
	var $t = t
	for _ in 0..<k {
		$t = three_let($t)
	}
	$t
}

turns_param : T, U64 -> T
turns_param = |t, k| {
	var $t = t
	for _ in 0..<k {
		$t = three_param($t)
	}
	$t
}

turns_match : T, U64 -> T
turns_match = |t, k| {
	var $t = t
	for _ in 0..<k {
		$t = three_match($t)
	}
	$t
}

make : U64 -> T
make = |n| {
	var $d = Dict.with_capacity(n)
	for i in 0..<n {
		$d = $d.insert(i, { name: "row ${i.to_str()}", value: i })
	}
	{ rows: $d, other: "other", version: 0 }
}

turns : U64
turns = 20

main! : List(_) => Try({}, _)
main! = |_args| {
	Stdout.line!("N: us per call of three_let / three_param / three_match")?
	for n in [10000, 100000, 1000000] {
		a = make(n)
		t0 = Monotonic.now!()
		ra = turns_let(a, turns)
		t1 = Monotonic.now!()
		b = make(n)
		t2 = Monotonic.now!()
		rb = turns_param(b, turns)
		t3 = Monotonic.now!()
		c = make(n)
		t4 = Monotonic.now!()
		rc = turns_match(c, turns)
		t5 = Monotonic.now!()
		by_let = t1.since(t0).to_nanos() // (turns * 1000)
		by_param = t3.since(t2).to_nanos() // (turns * 1000)
		by_match = t5.since(t4).to_nanos() // (turns * 1000)
		Stdout.line!("${n.to_str()}: ${by_let.to_str()} / ${by_param.to_str()} / ${by_match.to_str()} (${(ra.version + rb.version + rc.version).to_str()})")?
	}
	# The second caller of each loop.
	once = three_let(make(1)).version + three_param(make(1)).version + three_match(make(1)).version
	Stdout.line!("(${once.to_str()})")?
	Ok({})
}
