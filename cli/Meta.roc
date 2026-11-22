## The app's metadata: what `Info.plist` says about it, from `macos.json`
## beside `main.roc` and from the command line's flags, which override it.
##
## `macos.json` is a flat JSON object of text fields, every one optional:
##
## ```json
## {
##   "name": "Counter",
##   "id": "com.example.counter",
##   "version": "1.2.0",
##   "build": "7",
##   "copyright": "© 2026 Jane Doe",
##   "category": "public.app-category.utilities",
##   "minimum_macos": "13.0"
## }
## ```
##
## It is named for the tool that reads it, as `macos.roc` is, and so does not
## clash with another tool's `app.json` in the same repository. The tool
## reads it with its own strict parser, so that each mistake is reported by
## its line and field.
Meta := [].{

	## The file, beside `main.roc`.
	file : Str
	file = "macos.json"

	## Each field as it was given; empty means not given.
	Fields : { name : Str, id : Str, version : Str, build : Str, copyright : Str, category : Str, minimum_macos : Str }

	## The field names, in the order the file and help list them. Each is
	## also a flag, `--minimum-macos` for `minimum_macos`.
	names : List(Str)
	names = ["name", "id", "version", "build", "copyright", "category", "minimum_macos"]

	## No field given.
	none : Fields
	none = { name: "", id: "", version: "", build: "", copyright: "", category: "", minimum_macos: "" }

	## The app's metadata, every field decided.
	Resolved : { name : Str, id : Str, version : Str, build : Str, copyright : Str, category : Str, minimum_macos : Str }

	## The version an app has when nothing names one.
	default_version : Str
	default_version = "0.1"

	## The oldest macOS the platform runs on: the `minos` Roc's linker writes.
	oldest_macos : Str
	oldest_macos = "11.0"

	## Set the field `name` to `text`.
	set : Fields, Str, Str -> Try(Fields, [UnknownField(Str)])
	set = |fields, name, text|
		match name {
			"name" => Ok({ ..fields, name: text })
			"id" => Ok({ ..fields, id: text })
			"version" => Ok({ ..fields, version: text })
			"build" => Ok({ ..fields, build: text })
			"copyright" => Ok({ ..fields, copyright: text })
			"category" => Ok({ ..fields, category: text })
			"minimum_macos" => Ok({ ..fields, minimum_macos: text })
			_ => Err(UnknownField(name))
		}

	## The field a flag sets: `--minimum-macos` sets `minimum_macos`.
	flag_field : Str -> Try(Str, [NotAField])
	flag_field = |flag| {
		name = flag.drop_prefix("--").replace_each("-", "_")
		if (flag.starts_with("--") and Meta.names.contains(name)) Ok(name) else Err(NotAField)
	}

	## The fields of `macos.json`'s text.
	from_json : Str -> Try(Fields, [MetaMalformed({ line : U64, expected : Str }), MetaNotText({ field : Str, line : U64 }), MetaUnknownField(Str), MetaDuplicate(Str)])
	from_json = |text| {
		members = match parse_object(text) {
			Ok(found) => found
			Err(Malformed(at)) => return Err(MetaMalformed(at))
			Err(NotText(at)) => return Err(MetaNotText(at))
		}
		var $fields = Meta.none
		var $seen = []
		for { field, value } in members {
			if $seen.contains(field) {
				return Err(MetaDuplicate(field))
			}
			$seen = $seen.append(field)
			$fields = match Meta.set($fields, field, value) {
				Ok(next) => next
				Err(UnknownField(name)) => return Err(MetaUnknownField(name))
			}
		}
		Ok($fields)
	}

	## Check every field that was given, saying where it came from.
	check : Fields, [File, Flag] -> Try({}, [BadField({ field : Str, value : Str, from : [File, Flag] })])
	check = |fields, from| {
		given = [
			("name", fields.name),
			("id", fields.id),
			("version", fields.version),
			("build", fields.build),
			("copyright", fields.copyright),
			("category", fields.category),
			("minimum_macos", fields.minimum_macos),
		]
		for (field, value) in given {
			if !value.is_empty() and !Meta.valid(field, value) {
				return Err(BadField({ field, value, from }))
			}
		}
		Ok({})
	}

	## Whether `value` is a good value for `field`.
	valid : Str, Str -> Bool
	valid = |field, value|
		match field {
			"id" => valid_id(value)
			"version" | "build" => Meta.version_parts(value).is_ok()
			"minimum_macos" =>
				match Meta.version_parts(value) {
					Ok([major, ..]) => major >= 11
					_ => Bool.False
				}
			"category" => valid_category(value)
			_ => !value.to_utf8().any(|b| b < 0x20 or b == 0x7F)
		}

	## The numbers of a version: one to three dot-separated whole numbers,
	## as `CFBundleShortVersionString` and `CFBundleVersion` take them.
	version_parts : Str -> Try(List(U64), [NotAVersion])
	version_parts = |text| {
		parts = text.split_on(".")
		if parts.len() > 3 {
			return Err(NotAVersion)
		}
		var $numbers = []
		for part in parts {
			bytes = part.to_utf8()
			if bytes.is_empty() or bytes.len() > 9 or !bytes.all(|b| b >= '0' and b <= '9') {
				return Err(NotAVersion)
			}
			$numbers = $numbers.append(bytes.fold(0, |n, b| n * 10 + (b - '0').to_u64()))
		}
		Ok($numbers)
	}

	## The flags' fields over the file's: a flag that was given wins.
	over : Fields, Fields -> Fields
	over = |flags, written| {
		pick = |flag, from_file| if (flag.is_empty()) from_file else flag
		{
			name: pick(flags.name, written.name),
			id: pick(flags.id, written.id),
			version: pick(flags.version, written.version),
			build: pick(flags.build, written.build),
			copyright: pick(flags.copyright, written.copyright),
			category: pick(flags.category, written.category),
			minimum_macos: pick(flags.minimum_macos, written.minimum_macos),
		}
	}

	## Every field decided, for the app whose directory is named `dir_name`:
	## the name is `dir_name`, the bundle identifier `com.example.<dir_name>`, the
	## version 0.1, the build number the version, and the oldest macOS 11.0.
	resolve : Fields, Str -> Resolved
	resolve = |fields, dir_name| {
		given_or = |given, default| if (given.is_empty()) default else given
		version = given_or(fields.version, Meta.default_version)
		{
			name: given_or(fields.name, dir_name),
			id: given_or(fields.id, "com.example.${dir_name}"),
			version,
			build: given_or(fields.build, version),
			copyright: fields.copyright,
			category: fields.category,
			minimum_macos: given_or(fields.minimum_macos, Meta.oldest_macos),
		}
	}

	## The `macos.json` that `init` writes for the app in directory `dir_name`.
	starter : Str -> Str
	starter = |dir_name|
		\\{
		\\  "name": "${dir_name}",
		\\  "id": "com.example.${dir_name}",
		\\  "version": "0.1.0",
		\\  "build": "1",
		\\  "category": "public.app-category.utilities"
		\\}
		\\
}

## Whether `id` is a bundle identifier: two or more dot-separated parts,
## each of letters, digits and hyphens.
valid_id : Str -> Bool
valid_id = |id| {
	parts = id.split_on(".")
	parts.len() >= 2
		and parts.all(
			|part| {
				bytes = part.to_utf8()
				!bytes.is_empty() and bytes.all(|b| (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or (b >= '0' and b <= '9') or b == '-')
			},
		)
}

## Whether `category` is an `LSApplicationCategoryType`:
## `public.app-category.` and a lower-case name, such as `utilities`.
valid_category : Str -> Bool
valid_category = |category| {
	prefix = "public.app-category."
	rest = category.drop_prefix(prefix).to_utf8()
	category.starts_with(prefix) and !rest.is_empty() and rest.all(|b| (b >= 'a' and b <= 'z') or b == '-')
}

## A flat JSON object whose values are all strings: its members in order.
## Anything else is refused with the line it was found on.
parse_object : Str -> Try(List({ field : Str, value : Str }), [Malformed({ line : U64, expected : Str }), NotText({ field : Str, line : U64 })])
parse_object = |text| {
	bytes = text.to_utf8()
	start = skip_space(bytes, 0)
	if bytes.get(start) != Ok('{') {
		return Err(Malformed({ line: line_at(bytes, start), expected: "an object, starting with {" }))
	}
	first = skip_space(bytes, start + 1)
	if bytes.get(first) == Ok('}') {
		finish(bytes, first + 1, [])
	} else {
		members(bytes, first, [])
	}
}

## The members from `at`, which is where a field's name should start.
members : List(U8), U64, List({ field : Str, value : Str }) -> Try(List({ field : Str, value : Str }), [Malformed({ line : U64, expected : Str }), NotText({ field : Str, line : U64 })])
members = |bytes, at, found| {
	if bytes.get(at) != Ok('"') {
		return Err(Malformed({ line: line_at(bytes, at), expected: "a field's name in double quotes" }))
	}
	{ text: field, next: after_field } = string(bytes, at + 1)?
	colon = skip_space(bytes, after_field)
	if bytes.get(colon) != Ok(':') {
		return Err(Malformed({ line: line_at(bytes, colon), expected: "a colon after \"${field}\"" }))
	}
	value_at = skip_space(bytes, colon + 1)
	match bytes.get(value_at) {
		Ok('"') => {}
		Ok(_) => return Err(NotText({ field, line: line_at(bytes, value_at) }))
		Err(_) => return Err(Malformed({ line: line_at(bytes, value_at), expected: "a value for \"${field}\"" }))
	}
	{ text: value, next: after_value } = string(bytes, value_at + 1)?
	next = skip_space(bytes, after_value)
	with_this = found.append({ field, value })
	match bytes.get(next) {
		Ok(',') => members(bytes, skip_space(bytes, next + 1), with_this)
		Ok('}') => finish(bytes, next + 1, with_this)
		_ => Err(Malformed({ line: line_at(bytes, next), expected: "a comma or the closing }" }))
	}
}

## Nothing but white space may follow the object.
finish : List(U8), U64, List({ field : Str, value : Str }) -> Try(List({ field : Str, value : Str }), [Malformed({ line : U64, expected : Str }), NotText({ field : Str, line : U64 })])
finish = |bytes, at, found| {
	end = skip_space(bytes, at)
	if (end >= bytes.len()) Ok(found) else Err(Malformed({ line: line_at(bytes, end), expected: "nothing after the closing }" }))
}

## A JSON string's text, from just after its opening quote, and where it
## ends.
string : List(U8), U64 -> Try({ text : Str, next : U64 }, [Malformed({ line : U64, expected : Str }), NotText({ field : Str, line : U64 })])
string = |bytes, start| {
	var $at = start
	var $out = []
	unterminated = Malformed({ line: line_at(bytes, start), expected: "a closing double quote on the same line" })
	while Bool.True {
		match bytes.get($at) {
			Err(_) => return Err(unterminated)
			Ok('"') =>
				return match Str.from_utf8($out) {
					Ok(text) => Ok({ text, next: $at + 1 })
					Err(_) => Err(Malformed({ line: line_at(bytes, start), expected: "text in UTF-8" }))
				}
			Ok('\\') =>
				if bytes.get($at + 1) == Ok('u') {
					{ code, next } = unicode_escape(bytes, $at)?
					$out = $out.concat(utf8(code))
					$at = next
				} else {
					escaped = escape(bytes.get($at + 1) ?? 0) ? |_| Malformed({ line: line_at(bytes, $at), expected: "an escape such as \\\" or \\n after the backslash" })
					$out = $out.append(escaped)
					$at = $at + 2
				}
			Ok(b) if b < 0x20 => return Err(unterminated)
			Ok(b) => {
				$out = $out.append(b)
				$at = $at + 1
			}
		}
	}
}

## The byte a one-letter escape, `\n` say, stands for.
escape : U8 -> Try(U8, [NotAnEscape])
escape = |letter|
	match letter {
		'"' => Ok('"')
		'\\' => Ok('\\')
		'/' => Ok('/')
		'b' => Ok(0x08)
		'f' => Ok(0x0C)
		'n' => Ok('\n')
		'r' => Ok('\r')
		't' => Ok('\t')
		_ => Err(NotAnEscape)
	}

## The code point of the `\uXXXX` escape at `at` (or the surrogate pair
## starting there), and where it ends.
unicode_escape : List(U8), U64 -> Try({ code : U32, next : U64 }, [Malformed({ line : U64, expected : Str }), NotText({ field : Str, line : U64 })])
unicode_escape = |bytes, at| {
	bad = Malformed({ line: line_at(bytes, at), expected: "four hex digits after \\u" })
	high = hex4(bytes, at + 2) ? |_| bad
	if high >= 0xD800 and high <= 0xDBFF {
		if bytes.get(at + 6) != Ok('\\') or bytes.get(at + 7) != Ok('u') {
			return Err(bad)
		}
		low = hex4(bytes, at + 8) ? |_| bad
		if low < 0xDC00 or low > 0xDFFF {
			return Err(bad)
		}
		Ok({ code: 0x10000 + (high - 0xD800).shl_wrap(10) + (low - 0xDC00), next: at + 12 })
	} else if high >= 0xDC00 and high <= 0xDFFF {
		Err(bad)
	} else {
		Ok({ code: high, next: at + 6 })
	}
}

hex4 : List(U8), U64 -> Try(U32, [NotHex])
hex4 = |bytes, at| {
	digits = bytes.drop_first(at).take_first(4)
	if digits.len() != 4 {
		return Err(NotHex)
	}
	var $n = 0
	for b in digits {
		d = if b >= '0' and b <= '9' {
			b - '0'
		} else if b >= 'a' and b <= 'f' {
			b - 'a' + 10
		} else if b >= 'A' and b <= 'F' {
			b - 'A' + 10
		} else {
			return Err(NotHex)
		}
		$n = $n * 16 + d.to_u32()
	}
	Ok($n)
}

## A code point as UTF-8.
utf8 : U32 -> List(U8)
utf8 = |c|
	if c < 0x80 {
		[c.to_u8_wrap()]
	} else if c < 0x800 {
		[(0xC0 + c.shr_zf_wrap(6)).to_u8_wrap(), (0x80 + c.bitwise_and(0x3F)).to_u8_wrap()]
	} else if c < 0x10000 {
		[(0xE0 + c.shr_zf_wrap(12)).to_u8_wrap(), (0x80 + c.shr_zf_wrap(6).bitwise_and(0x3F)).to_u8_wrap(), (0x80 + c.bitwise_and(0x3F)).to_u8_wrap()]
	} else {
		[(0xF0 + c.shr_zf_wrap(18)).to_u8_wrap(), (0x80 + c.shr_zf_wrap(12).bitwise_and(0x3F)).to_u8_wrap(), (0x80 + c.shr_zf_wrap(6).bitwise_and(0x3F)).to_u8_wrap(), (0x80 + c.bitwise_and(0x3F)).to_u8_wrap()]
	}

## The first byte at or after `at` that is not JSON white space.
skip_space : List(U8), U64 -> U64
skip_space = |bytes, at|
	match bytes.get(at) {
		Ok(' ') | Ok('\t') | Ok('\n') | Ok('\r') => skip_space(bytes, at + 1)
		_ => at
	}

## The line `at` is on, counting from 1.
line_at : List(U8), U64 -> U64
line_at = |bytes, at| bytes.take_first(at).count_if(|b| b == '\n') + 1

## A starter file is valid, and names the app.
expect {
	parsed = Meta.from_json(Meta.starter("counter"))
	parsed == Ok({ ..Meta.none, name: "counter", id: "com.example.counter", version: "0.1.0", build: "1", category: "public.app-category.utilities" })
		and (parsed ?? Meta.none).name == "counter"
		and Meta.check(parsed ?? Meta.none, File) == Ok({})
}

## Escapes, including a surrogate pair, become the text they stand for.
expect {
	parsed = Meta.from_json("{ \"copyright\": \"\\u00a9 2026 \\\"Q\\\" \\ud83d\\ude00\", \"name\": \"A/B\\\\C\" }")
	parsed == Ok({ ..Meta.none, copyright: "© 2026 \"Q\" 😀", name: "A/B\\C" })
}

expect Meta.from_json("  {}\n") == Ok(Meta.none)

## A mistake is reported by its line and what was expected there.
expect {
	actual = [
		Meta.from_json("{\n  \"name\": \"x\"\n  \"id\": \"y\"\n}"),
		Meta.from_json("{ \"name\": \"x\", }"),
		Meta.from_json("[]"),
		Meta.from_json("{ \"name\": \"x\" } extra"),
		Meta.from_json("{ \"name\": \"x"),
		Meta.from_json("{ \"name\" \"x\" }"),
	]
	expected = [
		Err(MetaMalformed({ line: 3, expected: "a comma or the closing }" })),
		Err(MetaMalformed({ line: 1, expected: "a field's name in double quotes" })),
		Err(MetaMalformed({ line: 1, expected: "an object, starting with {" })),
		Err(MetaMalformed({ line: 1, expected: "nothing after the closing }" })),
		Err(MetaMalformed({ line: 1, expected: "a closing double quote on the same line" })),
		Err(MetaMalformed({ line: 1, expected: "a colon after \"name\"" })),
	]
	actual == expected
}

## A value that is not text, a field the tool does not know, or a field
## given twice, is named.
expect {
	actual = [
		Meta.from_json("{\n\"build\": 7\n}"),
		Meta.from_json("{ \"nmae\": \"x\" }"),
		Meta.from_json("{ \"id\": \"a.b\", \"id\": \"c.d\" }"),
	]
	actual == [Err(MetaNotText({ field: "build", line: 2 })), Err(MetaUnknownField("nmae")), Err(MetaDuplicate("id"))]
}

## Versions are one to three whole numbers.
expect {
	actual = ["1", "1.2", "1.2.3", "10.0.15", "v1.2", "1.2.3.4", "1..2", "", "1.2-beta", "1.x"].map(|v| Meta.valid("version", v))
	actual == [Bool.True, Bool.True, Bool.True, Bool.True, Bool.False, Bool.False, Bool.False, Bool.False, Bool.False, Bool.False]
}

## The oldest macOS is 11 or later; a category is one of the App Store's.
expect {
	macos = ["11.0", "13", "14.2.1", "10.15", "eleven"].map(|v| Meta.valid("minimum_macos", v))
	categories = ["public.app-category.utilities", "public.app-category.developer-tools", "utilities", "public.app-category.", "public.app-category.Games"].map(|v| Meta.valid("category", v))
	macos == [Bool.True, Bool.True, Bool.True, Bool.False, Bool.False] and categories == [Bool.True, Bool.True, Bool.False, Bool.False, Bool.False]
}

expect [valid_id("com.example.counter"), valid_id("com.example.my-app"), valid_id("counter"), valid_id("com..app"), valid_id("com.my_app")] == [Bool.True, Bool.True, Bool.False, Bool.False, Bool.False]

## The first field that is wrong is named, with where it came from.
expect {
	actual = [
		Meta.check({ ..Meta.none, version: "v1.0" }, Flag),
		Meta.check({ ..Meta.none, id: "counter", version: "1.0" }, File),
		Meta.check({ ..Meta.none, name: "Tab\there" }, File),
		Meta.check({ ..Meta.none, name: "Tom & Jerry", copyright: "© 2026" }, File),
	]
	actual == [Err(BadField({ field: "version", value: "v1.0", from: Flag })), Err(BadField({ field: "id", value: "counter", from: File })), Err(BadField({ field: "name", value: "Tab\there", from: File })), Ok({})]
}

## Flags win over the file; what neither gives has its default.
expect {
	file = { ..Meta.none, name: "Counter", version: "1.2.0", copyright: "© me" }
	flags = { ..Meta.none, version: "1.3.0", id: "org.me.counter" }
	Meta.resolve(Meta.over(flags, file), "counter") == { name: "Counter", id: "org.me.counter", version: "1.3.0", build: "1.3.0", copyright: "© me", category: "", minimum_macos: "11.0" }
}

expect Meta.resolve(Meta.none, "counter") == { name: "counter", id: "com.example.counter", version: "0.1", build: "0.1", copyright: "", category: "", minimum_macos: "11.0" }

expect [Meta.flag_field("--minimum-macos"), Meta.flag_field("--id"), Meta.flag_field("--sign"), Meta.flag_field("name")] == [Ok("minimum_macos"), Ok("id"), Err(NotAField), Err(NotAField)]
