app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
}

import cli.Monotonic
import cli.Stdout

## A state machine whose state is a list its closure captures: each step
## appends one item and returns the next machine. Run it for N steps.
##
## Appending to a uniquely held list is amortized O(1), so the time per
## step should not grow with N. With the `boxed` function below in the
## program, every function a `Step` holds is erased (a `Box` is an erasure
## boundary by its type alone), and an erased call reads its captures
## borrowed: the list is shared during every step, each append copies it,
## and the run is quadratic. Delete `boxed` (and its one use) and it is
## linear again. See README.adoc.
main! : List(_) => Try({}, _)
main! = |_args| {
	for n in [5000, 10000, 20000, 40000] {
		start = Monotonic.now!()
		len = run(n)
		ns = Monotonic.elapsed!(start).to_nanos()
		Stdout.line!("n=${n.to_str()} len=${len.to_str()} ${(ns // 1000).to_str()} us, ${(ns // n).to_str()} ns per step")?
	}
	Ok({})
}

Step := [Step((U64 -> (Step, U64)))]

machine : List(U64) -> Step
machine = |list| Step(
	|x| {
		next = list.append(x)
		(machine(next), next.len())
	},
)

## Naming `Box(Step)` anywhere in the program erases every function a Step
## holds, whether or not this runs.
boxed : Step -> Box(Step)
boxed = |m| Box.box(m)

step : Step, U64 -> (Step, U64)
step = |Step(f), x| f(x)

run : U64 -> U64
run = |n| {
	var $m = if (n == 0) Box.unbox(boxed(machine([]))) else machine([])
	var $last = 0
	var $i = 0
	while $i < n {
		(m2, len) = step($m, $i)
		$m = m2
		$last = len
		$i = $i + 1
	}
	$last
}
