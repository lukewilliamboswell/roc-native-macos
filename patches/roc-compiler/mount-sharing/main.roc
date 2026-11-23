app [main] { pf: platform "../../../platform/main.roc" }

import pf.Engine exposing [Elem]
import pf.Ui

## Mount N cells (launch arguments `-n N -v VARIANT`) and nothing else, to
## time the engine's mount. See README.adoc.
##
## - `attrs`: static elements with seven attributes each.
## - `sites`: `Engine.state` cells, each a dynamic site in the one block.
main : Engine.Program(_)
main = Engine.program_boot(
	{ storage_keys: ["n", "v"] },
	|boot| {
		n = U64.from_str(Engine.boot_storage(boot, "n") ?? "100") ?? 100
		v = Engine.boot_storage(boot, "v") ?? "attrs"
		view(v, n)
	},
)

view : Str, U64 -> Elem(ctx)
view = |v, n| {
	side = sqrt_floor(n)
	cell = match v {
		"attrs" => || Engine.element("ui-box", attrs(), [])
		"sites" => || Engine.state(0.U64, |_| Engine.element("ui-box", attrs(), [Ui.divider()]))
		_ => crash "unknown variant ${v}"
	}
	Ui.vstack({ spacing: 0 }, List.repeat(Ui.hstack({ spacing: 0 }, List.repeat(cell(), side)), side))
}

attrs : () -> List(Engine.Attr(ctx))
attrs = || [
	Engine.attr("fill", "control-background"),
	Engine.attr("border", "none"),
	Engine.attr("radius", "0"),
	Engine.attr("padding", "0 0 0 0"),
	Engine.attr("width", "fixed:4"),
	Engine.attr("height", "fixed:4"),
	Engine.attr("squeeze", "standard"),
]

sqrt_floor : U64 -> U64
sqrt_floor = |n| {
	var $k = 0
	while ($k + 1) * ($k + 1) <= n {
		$k = $k + 1
	}
	$k
}
