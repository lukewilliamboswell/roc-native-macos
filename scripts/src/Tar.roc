## A deterministic POSIX ustar archive of regular files, and a reader that
## admits only what the writer makes. The linker-input archive is written
## with it, so its bytes depend on nothing but the files: every entry is
## mode 0644, owned by uid and gid 0 with no user or group names, dated 0,
## in the order given, and the archive ends with two zero blocks.
Tar := [].{

	Entry : { path : Str, bytes : List(U8) }

	## The archive of `entries`, in their order. A path must be relative,
	## at most 100 bytes, without `.` or `..` components, and of letters,
	## digits and `._-$/`.
	write : List(Entry) -> Try(List(U8), [BadPath(Str)])
	write = |entries| {
		var $out = []
		for entry in entries {
			if !Tar.path_ok(entry.path) {
				return Err(BadPath(entry.path))
			}
			$out = $out.concat(Tar.header(entry.path, entry.bytes.len())).concat(entry.bytes).concat(List.repeat(0.U8, Tar.padding(entry.bytes.len())))
		}
		Ok($out.concat(List.repeat(0.U8, 1024)))
	}

	## The entries of an archive `write` made: regular files with admissible
	## paths, checked header by header, ending in a zero block.
	read : List(U8) -> Try(List(Entry), [Malformed(Str)])
	read = |archive| {
		var $offset = 0
		var $entries = []
		while $offset + 512 <= archive.len() {
			block = archive.sublist({ start: $offset, len: 512 })
			if block.all(|byte| byte == 0) {
				return Ok($entries)
			}
			path = Tar.field_text(block, 0, 100)
			size = Tar.octal_value(block.sublist({ start: 124, len: 12 })) ? |_| Malformed("${path} has a bad size")
			recorded = Tar.octal_value(block.sublist({ start: 148, len: 8 })) ? |_| Malformed("${path} has a bad checksum field")
			if recorded != Tar.checksum(block) {
				return Err(Malformed("${path} fails its header checksum"))
			}
			if block.sublist({ start: 257, len: 6 }) != Str.to_utf8("ustar").append(0) {
				return Err(Malformed("${path} is not a ustar entry"))
			}
			if block.get(156) != Ok('0') or !Tar.path_ok(path) {
				return Err(Malformed("${path} is not a regular file with an admissible path"))
			}
			start = $offset + 512
			if start + size > archive.len() {
				return Err(Malformed("${path} runs past the end of the archive"))
			}
			$entries = $entries.append({ path, bytes: archive.sublist({ start, len: size }) })
			$offset = start + size + Tar.padding(size)
		}
		Err(Malformed("the archive does not end with a zero block"))
	}

	## One entry's 512-byte header.
	header : Str, U64 -> List(U8)
	header = |path, size| {
		blank =
			Tar.field(Str.to_utf8(path), 100)
				.concat(Tar.octal(0o644, 8))
				.concat(Tar.octal(0, 8))
				.concat(Tar.octal(0, 8))
				.concat(Tar.octal(size, 12))
				.concat(Tar.octal(0, 12))
				.concat(List.repeat(' ', 8))
				.append('0')
				.concat(List.repeat(0.U8, 100))
				.concat(Str.to_utf8("ustar").append(0))
				.concat(Str.to_utf8("00"))
				.concat(List.repeat(0.U8, 32 + 32))
				.concat(Tar.octal(0, 8))
				.concat(Tar.octal(0, 8))
				.concat(List.repeat(0.U8, 155 + 12))
		sum = Tar.checksum(blank)
		blank.sublist({ start: 0, len: 148 }).concat(Tar.octal(sum, 7)).append(' ').concat(blank.sublist({ start: 156, len: 356 }))
	}

	## The header's checksum: every byte summed, the checksum field as spaces.
	checksum : List(U8) -> U64
	checksum = |block| {
		var $sum = 0
		var $index = 0
		for byte in block {
			$sum = $sum + (if ($index >= 148 and $index < 156) 32 else byte.to_u64())
			$index = $index + 1
		}
		$sum
	}

	## `value` in octal, zero-padded to `width - 1` digits and NUL-terminated.
	octal : U64, U64 -> List(U8)
	octal = |value, width| {
		var $digits = []
		var $rest = value
		var $count = 0
		while $count + 1 < width {
			$digits = [('0' + ($rest % 8).to_u8_wrap())].concat($digits)
			$rest = $rest // 8
			$count = $count + 1
		}
		$digits.append(0)
	}

	## The number an octal field holds, ignoring NULs and spaces around it.
	octal_value : List(U8) -> Try(U64, [NotOctal])
	octal_value = |bytes| {
		digits = bytes.keep_if(|byte| byte != 0 and byte != ' ')
		if digits.is_empty() or !digits.all(|byte| byte >= '0' and byte <= '7') {
			Err(NotOctal)
		} else {
			Ok(digits.fold(0, |total, byte| total * 8 + (byte - '0').to_u64()))
		}
	}

	field : List(U8), U64 -> List(U8)
	field = |bytes, width| bytes.concat(List.repeat(0.U8, width - bytes.len()))

	field_text : List(U8), U64, U64 -> Str
	field_text = |block, start, width| Str.from_utf8_lossy(block.sublist({ start, len: width }).take_first(block.sublist({ start, len: width }).find_first_index(|byte| byte == 0) ?? width))

	padding : U64 -> U64
	padding = |size| if (size % 512 == 0) 0 else 512 - size % 512

	path_ok : Str -> Bool
	path_ok = |path| {
		bytes = path.to_utf8()
		parts = path.split_on("/")
		!bytes.is_empty()
			and bytes.len() <= 100
			and !path.starts_with("/")
			and !parts.any(|part| part == "" or part == "." or part == "..")
			and bytes.all(|byte| (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or (byte >= '0' and byte <= '9') or byte == '.' or byte == '_' or byte == '-' or byte == '$' or byte == '/')
	}
}

expect Tar.octal(0o644, 8) == Str.to_utf8("0000644").append(0)
expect Tar.octal(5, 12) == Str.to_utf8("00000000005").append(0)
expect Tar.octal_value(Str.to_utf8("0000644").append(0)) == Ok(420)

## A header is one block, and its checksum is what it records.
expect {
	block = Tar.header("a/b.tbd", 5)
	block.len() == 512 and Tar.octal_value(block.sublist({ start: 148, len: 8 })) == Ok(Tar.checksum(block))
}

## What `write` makes, `read` gives back, padded to blocks.
expect {
	entries = [{ path: "LICENSE", bytes: Str.to_utf8("hello") }, { path: "macos-sysroot/usr/lib/libSystem.tbd", bytes: List.repeat('x', 600) }]
	archive = Tar.write(entries) ?? []
	archive.len() == 512 + 512 + 512 + 1024 + 1024 and Tar.read(archive) == Ok(entries)
}

expect Tar.write([{ path: "../escape", bytes: [] }]) == Err(BadPath("../escape"))
expect Tar.write([{ path: "/abs", bytes: [] }]) == Err(BadPath("/abs"))

## A changed byte fails the checksum.
expect {
	archive = Tar.write([{ path: "a", bytes: [1] }]) ?? []
	Tar.read(List.concat(['b'], archive.drop_first(1))).is_err()
}
