app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
}

import cli.Monotonic
import cli.Stdout

## A state machine whose state is a list its closure captures: each step
## appends one item and returns the next machine. Appending to a uniquely
## held list is amortized O(1), so the time per step should not grow with
## the number of steps.
##
## `boxed` names `Box(T)` for each machine type, which makes every function
## that type holds erased. An erased call then reads the closure's captures
## borrowed, so the list is shared during the step and the append copies
## it (quadratic), in two cases:
##
## * `step` calls the closure in tail position: the call is deferred, and
##   a deferred call never transfers the closure to the callee.
## * the closure's result holds exactly one function (the next machine):
##   the callee keeps its own closure alive as the destination for that
##   function, and reads its captures borrowed until then.
##
## Only `bound_spare`, which avoids both, is linear. `Idle` and `Spare` are
## never built: they give `step` a recursive branch so it is not inlined,
## and `Spare` makes the result hold a list of functions, not one.
main! : List(_) => Try({}, _)
main! = |_args| {
	for n in [5000, 10000, 20000, 40000] {
		t1 = time!(|| run_tail_one(n))
		t2 = time!(|| run_bound_one(n))
		t3 = time!(|| run_tail_spare(n))
		t4 = time!(|| run_bound_spare(n))
		Stdout.line!("n=${n.to_str()} ns per step: tail_one ${(t1 // n).to_str()}, bound_one ${(t2 // n).to_str()}, tail_spare ${(t3 // n).to_str()}, bound_spare ${(t4 // n).to_str()}")?
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

# The result holds one function: the next machine.
One := [Step((U64 -> (One, U64))), Idle]

one : List(U64) -> One
one = |list| Step(
	|x| {
		next = list.append(x)
		(one(next), next.len())
	},
)

boxed_one : One -> Box(One)
boxed_one = |m| Box.box(m)

tail_one : One, U64 -> (One, U64)
tail_one = |m, x| match m {
	Step(f) => f(x)
	Idle => tail_one(one([]), x)
}

bound_one : One, U64 -> (One, U64)
bound_one = |m, x| match m {
	Step(f) => {
		(next, len) = f(x)
		(next, len)
	}
	Idle => bound_one(one([]), x)
}

# The result holds a list of functions as well, so not exactly one.
Spare := [Step((U64 -> (Spare, U64))), Spare(List(Spare))]

spare : List(U64) -> Spare
spare = |list| Step(
	|x| {
		next = list.append(x)
		(spare(next), next.len())
	},
)

boxed_spare : Spare -> Box(Spare)
boxed_spare = |m| Box.box(m)

tail_spare : Spare, U64 -> (Spare, U64)
tail_spare = |m, x| match m {
	Step(f) => f(x)
	Spare(ms) => tail_spare(ms.first() ?? spare([]), x)
}

bound_spare : Spare, U64 -> (Spare, U64)
bound_spare = |m, x| match m {
	Step(f) => {
		(next, len) = f(x)
		(next, len)
	}
	Spare(ms) => bound_spare(ms.first() ?? spare([]), x)
}

run_tail_one : U64 -> U64
run_tail_one = |n| {
	var $m = if (n == 0) Box.unbox(boxed_one(one([]))) else one([])
	var $last = 0
	var $i = 0
	while $i < n {
		(m2, len) = tail_one($m, $i)
		$m = m2
		$last = len
		$i = $i + 1
	}
	$last
}

run_bound_one : U64 -> U64
run_bound_one = |n| {
	var $m = if (n == 0) Box.unbox(boxed_one(one([]))) else one([])
	var $last = 0
	var $i = 0
	while $i < n {
		(m2, len) = bound_one($m, $i)
		$m = m2
		$last = len
		$i = $i + 1
	}
	$last
}

run_tail_spare : U64 -> U64
run_tail_spare = |n| {
	var $m = if (n == 0) Box.unbox(boxed_spare(spare([]))) else spare([])
	var $last = 0
	var $i = 0
	while $i < n {
		(m2, len) = tail_spare($m, $i)
		$m = m2
		$last = len
		$i = $i + 1
	}
	$last
}

run_bound_spare : U64 -> U64
run_bound_spare = |n| {
	var $m = if (n == 0) Box.unbox(boxed_spare(spare([]))) else spare([])
	var $last = 0
	var $i = 0
	while $i < n {
		(m2, len) = bound_spare($m, $i)
		$m = m2
		$last = len
		$i = $i + 1
	}
	$last
}
