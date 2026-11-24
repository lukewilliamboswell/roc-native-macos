app [main] { pf: platform "../../../../platform/main.roc" }

import pf.Engine exposing [Elem, In, Root, State]
import pf.Ui

## The numbers a build can lower to library calls: 128-bit integer
## multiplication, division, remainder and shifts, `Dec` arithmetic,
## `F64` and `F32` maths, and the conversions between them and strings.
## Each row is computed from a count the button changes at run time, so no
## build can fold it away. `blueprint run check -- matrix` builds this
## fixture with every `--opt` and `--specialize` and runs its specs.
main : Engine.Program
main = Engine.program(|| Engine.state(7, view))

## The highest count: Next stops here, so every row's operations stay in
## range for every count the app can reach. `I128.pow` crashes on overflow
## (`(n + 10)^30` would from n = 9), so its base is bounded, and `pow_try`
## shows the overflow instead.
highest : I64
highest = 12

view : State(In(Root, I64), I64) -> Elem(In(Root, I64))
view = |count| {
	n = count.signal()
	Ui.vstack(
		{ spacing: 10, align: Fill, padding: All(12), width: AtLeast(560) },
		[
			Ui.hstack(
				{},
				[
					Ui.text("Arithmetic", { style: Title2, weight: Semibold }),
					Ui.spacer(),
					Ui.text(n.map(|k| "n ${k.to_str()}"), { style: Headline, design: MonospacedDigits }),
					Ui.button("Next", { on_press: count.update(|k| if (k < highest) k + 1 else k), enabled: n.map(|k| k < highest) }),
				],
			),
			Ui.scroll(
				{ opening_height: 490, spacing: 8, padding: All(2) },
				Ui.vstack(
					{ spacing: 12, align: Fill },
					groups.map(
						|(title, rows)| Ui.box(
							{ padding: All(10), width: Fill },
							Ui.vstack(
								{ spacing: 3, align: Fill },
								[Ui.text(Engine.const(title), { style: Headline })]
									.concat(rows.map(|row| Ui.text(n.map(row), { style: Callout, design: Monospaced, overflow: Wrap, width: Fill }))),
							),
						),
					),
				),
			),
		],
	)
}

## The rows, each a short line of results from the count.
groups : List((Str, List((I64 -> Str))))
groups = [
	(
		"Wide integers",
		[
			|k| "u128 ${wide(k).to_str()}",
			|k| "u128 / ${divisor(k).to_str()} = ${(wide(k) // divisor(k)).to_str()} rem ${(wide(k) % divisor(k)).to_str()}",
			|k| "i128 / ${(k.to_i128() + 2).to_str()} = ${(negative(k) // (k.to_i128() + 2)).to_str()} rem ${(negative(k) % (k.to_i128() + 2)).to_str()}",
			|k| "i128 parsed ${(I128.from_str(negative(k).to_str()) ?? 0).to_str()}",
			|k| "u128 << ${shift(k).to_str()} ${wide(k).shl_wrap(shift(k)).to_str()}",
			|k| "u128 >> ${(shift(k) // 2).to_str()} ${wide(k).shr_wrap(shift(k) // 2).to_str()}",
			|k| "i128 >> ${negative(k).shr_wrap(shift(k) // 2).to_str()} >>> ${negative(k).shr_zf_wrap(shift(k)).to_str()}",
		],
	),
	(
		"Decimal and floating point",
		[
			|k| "dec ${third(k).to_str()} ${(third(k) * 1.25).to_str()} ${third(k).round().to_str()}",
			|k| "dec sqrt ${k.to_dec().sqrt().to_str()} sin ${k.to_dec().sin().to_str()}",
			|k| "dec pow ${k.to_dec().pow(2.5).to_str()} rem ${(k.to_dec() % 2.75).to_str()}",
			|k| "f64 ${x64(k).to_str()} ${x64(k).sqrt().to_str()} ${x64(k).pow(1.7).to_str()}",
			|k| "f64 ${x64(k).sin().to_str()} ${x64(k).cos().to_str()} ${x64(k).tan().to_str()}",
			|k| "f64 ${x64(k).atan().to_str()} ${(1 / x64(k)).asin().to_str()} ${(x64(k) % 0.7).to_str()}",
			|k| "f32 ${x32(k).to_str()} ${x32(k).sqrt().to_str()} ${x32(k).pow(1.7).to_str()}",
			|k| "f32 ${x32(k).sin().to_str()} ${x32(k).cos().to_str()} ${F32.atan2({ x: 2.5, y: x32(k) }).to_str()} ${(x32(k) % 0.7).to_str()}",
		],
	),
	(
		"Conversions and collections",
		[
			|k| "to float ${wide(k).to_f64().to_str()} ${negative(k).to_f64().to_str()} ${wide(k).to_f32().to_str()}",
			|k| "from float ${wide(k).to_f64().to_u128_wrap().to_str()} ${(-parsed(k) * 1e20).to_i128_wrap().to_str()}",
			|k| "parsed ${parsed(k).to_str()}",
			|k| "rounded ${(x64(k).floor_to_i64_try() ?? 0).to_str()} ${(x64(k).ceiling_to_i64_try() ?? 0).to_str()} ${(x64(k).round_to_i128_try() ?? 0).to_str()} ${(x32(k).round_to_i64_try() ?? 0).to_str()} ${(-x32(k)).floor_to_i32_try().map_ok(|v| v.to_str()) ?? ""}",
			|k| "dec rounded ${third(k).floor().to_str()} ${third(k).ceiling().to_str()} ${(-third(k)).trunc().to_str()}",
			|k| "bits ${wide(k).count_one_bits().to_str()} ${wide(k).count_leading_zero_bits().to_str()} ${negative(k).count_trailing_zero_bits().to_str()}",
			|k| "pow ${(k.to_i128() + 4).pow(30).to_str()} ${(k.to_i128() + 10).pow_try(30).map_ok(|v| v.to_str()) ?? "overflow"} ${(I128.times_try(negative(k), negative(k)) ?? 0).to_str()}",
			list_row,
		],
	),
]

## A U128 too wide for 64 bits, from the count.
wide : I64 -> U128
wide = |k| k.to_u128_wrap() * 18_446_744_073_709_551_557 * 1_000_003

negative : I64 -> I128
negative = |k| I128.negate(wide(k).to_i128_wrap())

divisor : I64 -> U128
divisor = |k| k.to_u128_wrap() + 3

## A shift wider than 64 bits for most counts.
shift : I64 -> U8
shift = |k| ((k * 13) % 128).to_u8_wrap()

third : I64 -> Dec
third = |k| k.to_dec() / 3

x64 : I64 -> F64
x64 = |k| k.to_f64() / 3

x32 : I64 -> F32
x32 = |k| k.to_f32() / 3

parsed : I64 -> F64
parsed = |k| F64.from_str("${k.to_str()}.125e3") ?? 0

list_row : I64 -> Str
list_row = |k| {
	values = List.from_iter((1.I64).to(k * 3).map(|i| (i * 7919) % 101))
	sorted = values.sort_with(|a, b| if (a < b) Before else if (a > b) After else Same)
	"list ${values.len().to_str()} sum ${values.fold(0, |acc, v| acc + v).to_str()} first ${Str.join_with(sorted.take_first(5).map(|v| v.to_str()), ",")}"
}
