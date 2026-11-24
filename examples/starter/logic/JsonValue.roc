## JSON text and values, small and strict: what the preset documents and
## the saved settings are written in. `JsonValue.parse` reads text into a value
## and `JsonValue.encode` writes one back, indented, so a preset a person
## exports is readable and editable by hand.
##
## Numbers are whole (`-12`, `300`): every number the app stores is a whole
## count of some unit (percent, per-mille, milliseconds, tenths of a dB),
## so a fraction or an exponent is refused with where it was, rather than
## rounded. Objects keep their keys in order, as written. Nesting deeper
## than `JsonValue.deepest` is refused, so a hostile file cannot exhaust the
## stack; the size of a file is bounded where it is read.
JsonValue := [Null, Bool(Bool), Int(I64), Text(Str), Array(List(JsonValue)), Object(List((Str, JsonValue)))].{

	## Two values are equal when they are the same kind with equal parts,
	## an object's fields in the same order.
	is_eq : JsonValue, JsonValue -> Bool
	is_eq = |a, b|
		match (a, b) {
			(Null, Null) => Bool.True
			(Bool(x), Bool(y)) => x == y
			(Int(x), Int(y)) => x == y
			(Text(x), Text(y)) => x == y
			(Array(xs), Array(ys)) => xs.len() == ys.len() and List.map2(xs, ys, JsonValue.is_eq).all(|same| same)
			(Object(xs), Object(ys)) => xs.len() == ys.len() and List.map2(xs, ys, |(kx, vx), (ky, vy)| kx == ky and JsonValue.is_eq(vx, vy)).all(|same| same)
			_ => Bool.False
		}

	## How deeply arrays and objects may nest.
	deepest : U64
	deepest = 32

	## Why a text is not JSON: what was wrong, and the byte offset where.
	Problem : { at : U64, what : Str }

	## The value a text holds. Whitespace around it is allowed; anything
	## else after it is not.
	parse : Str -> Try(JsonValue, Problem)
	parse = |text| {
		bytes = text.to_utf8()
		start = JsonValue.skip_space(bytes, 0)
		parsed = JsonValue.value(bytes, start, 0)?
		end = JsonValue.skip_space(bytes, parsed.next)
		if end < bytes.len() {
			Err({ at: end, what: "unexpected text after the value" })
		} else {
			Ok(parsed.value)
		}
	}

	## One value starting at `at`, and where it ends.
	value : List(U8), U64, U64 -> Try({ value : JsonValue, next : U64 }, Problem)
	value = |bytes, at, depth|
		match bytes.get(at) {
			Err(_) => Err({ at, what: "expected a value, found the end" })
			Ok('{') => if (depth >= JsonValue.deepest) Err({ at, what: "nested too deeply" }) else JsonValue.object(bytes, JsonValue.skip_space(bytes, at + 1), depth + 1, [])
			Ok('[') => if (depth >= JsonValue.deepest) Err({ at, what: "nested too deeply" }) else JsonValue.array(bytes, JsonValue.skip_space(bytes, at + 1), depth + 1, [])
			Ok('"') => JsonValue.string(bytes, at + 1, []).map_ok(|s| { value: JsonValue.Text(s.text), next: s.next })
			Ok('t') => JsonValue.word(bytes, at, "true", JsonValue.Bool(Bool.True))
			Ok('f') => JsonValue.word(bytes, at, "false", JsonValue.Bool(Bool.False))
			Ok('n') => JsonValue.word(bytes, at, "null", JsonValue.Null)
			Ok(byte) if byte == '-' or (byte >= '0' and byte <= '9') => JsonValue.number(bytes, at)
			Ok(_) => Err({ at, what: "expected a value" })
		}

	## A literal word such as `true`.
	word : List(U8), U64, Str, JsonValue -> Try({ value : JsonValue, next : U64 }, Problem)
	word = |bytes, at, spelled, meant| {
		expected = spelled.to_utf8()
		if bytes.sublist({ start: at, len: expected.len() }) == expected {
			Ok({ value: meant, next: at + expected.len() })
		} else {
			Err({ at, what: "expected a value" })
		}
	}

	## A whole number: an optional minus, then digits with no leading zero.
	number : List(U8), U64 -> Try({ value : JsonValue, next : U64 }, Problem)
	number = |bytes, at| {
		digits_from = if (bytes.get(at) == Ok('-')) at + 1 else at
		var $end = digits_from
		while JsonValue.is_digit(bytes.get($end)) {
			$end = $end + 1
		}
		count = $end - digits_from
		if count == 0 {
			return Err({ at, what: "expected digits" })
		}
		if count > 1 and bytes.get(digits_from) == Ok('0') {
			return Err({ at, what: "a number has a leading zero" })
		}
		match bytes.get($end) {
			Ok(byte) if byte == '.' or byte == 'e' or byte == 'E' => return Err({ at, what: "numbers here are whole" })
			_ => {}
		}
		text = Str.from_utf8(bytes.sublist({ start: at, len: $end - at })) ?? ""
		match I64.from_str(text) {
			Ok(n) => Ok({ value: JsonValue.Int(n), next: $end })
			Err(_) => Err({ at, what: "the number is too large" })
		}
	}

	is_digit : Try(U8, _) -> Bool
	is_digit = |got|
		match got {
			Ok(byte) => byte >= '0' and byte <= '9'
			Err(_) => Bool.False
		}

	## The rest of a string after its opening quote, unescaped.
	string : List(U8), U64, List(U8) -> Try({ text : Str, next : U64 }, Problem)
	string = |bytes, at, held| {
		var $at = at
		var $held = held
		var $done = Err({ at, what: "a string is not closed" })
		var $going = Bool.True
		while $going {
			match bytes.get($at) {
				Err(_) => {
					$going = Bool.False
				}
				Ok('"') => {
					$going = Bool.False
					$done = match Str.from_utf8($held) {
						Ok(text) => Ok({ text, next: $at + 1 })
						Err(_) => Err({ at, what: "a string is not UTF-8" })
					}
				}
				Ok('\\') =>
					match JsonValue.escape(bytes, $at + 1) {
						Ok(escaped) => {
							$held = $held.concat(escaped.bytes)
							$at = escaped.next
						}
						Err(problem) => {
							$going = Bool.False
							$done = Err(problem)
						}
					}
				Ok(byte) if byte < 0x20 => {
					$going = Bool.False
					$done = Err({ at: $at, what: "a string holds a control character" })
				}
				Ok(byte) => {
					$held = $held.append(byte)
					$at = $at + 1
				}
			}
		}
		$done
	}

	## The bytes an escape after a backslash stands for.
	escape : List(U8), U64 -> Try({ bytes : List(U8), next : U64 }, Problem)
	escape = |bytes, at|
		match bytes.get(at) {
			Ok('"') => Ok({ bytes: ['"'], next: at + 1 })
			Ok('\\') => Ok({ bytes: ['\\'], next: at + 1 })
			Ok('/') => Ok({ bytes: ['/'], next: at + 1 })
			Ok('b') => Ok({ bytes: [8], next: at + 1 })
			Ok('f') => Ok({ bytes: [12], next: at + 1 })
			Ok('n') => Ok({ bytes: ['\n'], next: at + 1 })
			Ok('r') => Ok({ bytes: ['\r'], next: at + 1 })
			Ok('t') => Ok({ bytes: ['\t'], next: at + 1 })
			Ok('u') => {
				high = JsonValue.hex4(bytes, at + 1)?
				if high >= 0xD800 and high <= 0xDBFF {
					# A surrogate pair: a second \u escape must follow.
					if bytes.sublist({ start: at + 5, len: 2 }) != ['\\', 'u'] {
						return Err({ at, what: "a surrogate is not paired" })
					}
					low = JsonValue.hex4(bytes, at + 7)?
					if low < 0xDC00 or low > 0xDFFF {
						return Err({ at, what: "a surrogate is not paired" })
					}
					point = 0x10000 + (high - 0xD800) * 0x400 + (low - 0xDC00)
					Ok({ bytes: JsonValue.utf8(point), next: at + 11 })
				} else if high >= 0xDC00 and high <= 0xDFFF {
					Err({ at, what: "a surrogate is not paired" })
				} else {
					Ok({ bytes: JsonValue.utf8(high), next: at + 5 })
				}
			}
			_ => Err({ at, what: "an unknown escape" })
		}

	## Four hexadecimal digits as a number.
	hex4 : List(U8), U64 -> Try(U32, Problem)
	hex4 = |bytes, at| {
		var $n = 0.U32
		for byte in bytes.sublist({ start: at, len: 4 }) {
			digit =
				if byte >= '0' and byte <= '9' {
					byte - '0'
				} else if byte >= 'a' and byte <= 'f' {
					byte - 'a' + 10
				} else if byte >= 'A' and byte <= 'F' {
					byte - 'A' + 10
				} else {
					return Err({ at, what: "a \\u escape needs four hex digits" })
				}
			$n = $n * 16 + digit.to_u32()
		}
		if bytes.len() < at + 4 {
			Err({ at, what: "a \\u escape needs four hex digits" })
		} else {
			Ok($n)
		}
	}

	## A code point's UTF-8 bytes.
	utf8 : U32 -> List(U8)
	utf8 = |point|
		if point < 0x80 {
			[point.to_u8_wrap()]
		} else if point < 0x800 {
			[(0xC0 + point // 64).to_u8_wrap(), (0x80 + point % 64).to_u8_wrap()]
		} else if point < 0x10000 {
			[(0xE0 + point // 4096).to_u8_wrap(), (0x80 + (point // 64) % 64).to_u8_wrap(), (0x80 + point % 64).to_u8_wrap()]
		} else {
			[(0xF0 + point // 262144).to_u8_wrap(), (0x80 + (point // 4096) % 64).to_u8_wrap(), (0x80 + (point // 64) % 64).to_u8_wrap(), (0x80 + point % 64).to_u8_wrap()]
		}

	## The rest of an array after its `[` and any space.
	array : List(U8), U64, U64, List(JsonValue) -> Try({ value : JsonValue, next : U64 }, Problem)
	array = |bytes, at, depth, held|
		if held.is_empty() and bytes.get(at) == Ok(']') {
			Ok({ value: JsonValue.Array([]), next: at + 1 })
		} else {
			item = JsonValue.value(bytes, at, depth)?
			after = JsonValue.skip_space(bytes, item.next)
			match bytes.get(after) {
				Ok(',') => JsonValue.array(bytes, JsonValue.skip_space(bytes, after + 1), depth, held.append(item.value))
				Ok(']') => Ok({ value: JsonValue.Array(held.append(item.value)), next: after + 1 })
				_ => Err({ at: after, what: "expected , or ] in an array" })
			}
		}

	## The rest of an object after its `{` and any space.
	object : List(U8), U64, U64, List((Str, JsonValue)) -> Try({ value : JsonValue, next : U64 }, Problem)
	object = |bytes, at, depth, held|
		if held.is_empty() and bytes.get(at) == Ok('}') {
			Ok({ value: JsonValue.Object([]), next: at + 1 })
		} else if bytes.get(at) != Ok('"') {
			Err({ at, what: "expected a key in quotes" })
		} else {
			key = JsonValue.string(bytes, at + 1, [])?
			colon = JsonValue.skip_space(bytes, key.next)
			if bytes.get(colon) != Ok(':') {
				return Err({ at: colon, what: "expected : after a key" })
			}
			item = JsonValue.value(bytes, JsonValue.skip_space(bytes, colon + 1), depth)?
			after = JsonValue.skip_space(bytes, item.next)
			if held.any(|(seen, _)| seen == key.text) {
				return Err({ at, what: "the key \"${key.text}\" repeats" })
			}
			entry = (key.text, item.value)
			match bytes.get(after) {
				Ok(',') => JsonValue.object(bytes, JsonValue.skip_space(bytes, after + 1), depth, held.append(entry))
				Ok('}') => Ok({ value: JsonValue.Object(held.append(entry)), next: after + 1 })
				_ => Err({ at: after, what: "expected , or } in an object" })
			}
		}

	## The first offset at or after `at` that is not JSON whitespace.
	skip_space : List(U8), U64 -> U64
	skip_space = |bytes, at| {
		var $at = at
		while JsonValue.is_space(bytes.get($at)) {
			$at = $at + 1
		}
		$at
	}

	is_space : Try(U8, _) -> Bool
	is_space = |got|
		match got {
			Ok(byte) => byte == ' ' or byte == '\n' or byte == '\r' or byte == '\t'
			Err(_) => Bool.False
		}

	## A value as text, indented by two spaces a level, with a key and its
	## value on one line and short arrays of numbers kept on one line.
	encode : JsonValue -> Str
	encode = |json| JsonValue.write(json, "")

	write : JsonValue, Str -> Str
	write = |json, indent|
		match json {
			Null => "null"
			Bool(b) => if (b) "true" else "false"
			Int(n) => n.to_str()
			Text(s) => JsonValue.quoted(s)
			Array([]) => "[]"
			Array(items) =>
				if items.all(JsonValue.is_flat) {
					"[${Str.join_with(items.map(|item| JsonValue.write(item, indent)), ", ")}]"
				} else {
					inner = "${indent}  "
					"[\n${Str.join_with(items.map(|item| "${inner}${JsonValue.write(item, inner)}"), ",\n")}\n${indent}]"
				}
			Object([]) => "{}"
			Object(fields) => {
				inner = "${indent}  "
				"{\n${Str.join_with(fields.map(|(key, item)| "${inner}${JsonValue.quoted(key)}: ${JsonValue.write(item, inner)}"), ",\n")}\n${indent}}"
			}
		}

	## A value printed on one line inside an array: anything but an array
	## or an object.
	is_flat : JsonValue -> Bool
	is_flat = |json|
		match json {
			Array(_) => Bool.False
			Object(_) => Bool.False
			_ => Bool.True
		}

	## A string in quotes, with what JSON requires escaped.
	quoted : Str -> Str
	quoted = |text| {
		var $out = ['"']
		for byte in text.to_utf8() {
			$out =
				match byte {
					'"' => $out.concat(['\\', '"'])
					'\\' => $out.concat(['\\', '\\'])
					'\n' => $out.concat(['\\', 'n'])
					'\r' => $out.concat(['\\', 'r'])
					'\t' => $out.concat(['\\', 't'])
					_ if byte < 0x20 => $out.concat(['\\', 'u', '0', '0', JsonValue.hex_digit(byte // 16), JsonValue.hex_digit(byte % 16)])
					_ => $out.append(byte)
				}
		}
		Str.from_utf8($out.append('"')) ?? "\"\""
	}

	hex_digit : U8 -> U8
	hex_digit = |n| if (n < 10) '0' + n else 'a' + n - 10

	## The field `key` of an object.
	field : JsonValue, Str -> Try(JsonValue, [Missing])
	field = |json, key|
		match json {
			Object(fields) =>
				match fields.find_first(|(name, _)| name == key) {
					Ok((_, found)) => Ok(found)
					Err(_) => Err(Missing)
				}
			_ => Err(Missing)
		}
}

expect JsonValue.parse("{\"a\": [1, -2, true, null], \"b\": \"x\"}") == Ok(JsonValue.Object([("a", JsonValue.Array([JsonValue.Int(1), JsonValue.Int(-2), JsonValue.Bool(Bool.True), JsonValue.Null])), ("b", JsonValue.Text("x"))]))

## Escapes read as what they stand for, including a surrogate pair.
expect JsonValue.parse("\"a\\n\\\"b\\u00e9\\ud83c\\udfb5\"") == Ok(JsonValue.Text("a\n\"bé🎵"))

## Encoding then parsing gives the value back.
expect {
	value = JsonValue.Object([("name", JsonValue.Text("Ember \"Tunnel\"\n")), ("sizes", JsonValue.Array([JsonValue.Int(200), JsonValue.Int(-380)])), ("layers", JsonValue.Array([JsonValue.Object([("on", JsonValue.Bool(Bool.False))]), JsonValue.Object([])]))])
	JsonValue.parse(JsonValue.encode(value)) == Ok(value)
}

expect JsonValue.encode(JsonValue.Object([("a", JsonValue.Array([JsonValue.Int(1), JsonValue.Int(2)])), ("b", JsonValue.Object([]))])) == "{\n  \"a\": [1, 2],\n  \"b\": {}\n}"

## What is not JSON, or not whole numbers, is refused with where.
expect JsonValue.parse("1.5") == Err({ at: 0, what: "numbers here are whole" })
expect JsonValue.parse("[1,]").is_err() and JsonValue.parse("{\"a\" 1}").is_err() and JsonValue.parse("01").is_err() and JsonValue.parse("").is_err()
expect JsonValue.parse("{\"a\": 1, \"a\": 2}").is_err() and JsonValue.parse("\"\\ud800\"").is_err() and JsonValue.parse("[1] x").is_err()
expect JsonValue.parse(Str.repeat("[", 40)).is_err() and JsonValue.parse("${Str.repeat("[", 20)}${Str.repeat("]", 20)}").is_ok()
