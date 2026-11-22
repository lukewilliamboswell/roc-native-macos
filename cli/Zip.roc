## A zip archive of an app, written byte for byte so that it is the same on
## every system and every run.
##
## Each entry's Unix mode is set in the zip's external attributes, from what
## the entry is, not from the file system it was read from: directories and
## programs 0755, other files 0644. A zip made on Windows, or by a tool that
## drops the modes, loses a program's execute bit, and macOS then will not
## launch the app. Entries are sorted, carry one fixed time and no extra
## fields, and are stored, not compressed: basic-cli has no compressor.
Zip := [].{

	## What goes in the archive: a path with `/` separators (a directory's
	## ending in `/`), what it is, and its bytes.
	Entry : { path : Str, kind : [Directory, Program, Plain], bytes : List(U8) }

	## The archive of `entries`, every entry stamped with the time `seconds`
	## after the Unix epoch, in UTC.
	archive : List(Entry), U64 -> List(U8)
	archive = |entries, seconds| {
		{ time, date } = Zip.dos_time(seconds)
		sorted = entries.sort_with(|a, b| compare_bytes(a.path.to_utf8(), b.path.to_utf8()))
		var $out = []
		var $central = []
		for entry in sorted {
			name = entry.path.to_utf8()
			crc = Zip.crc32(entry.bytes)
			size = entry.bytes.len().to_u32_wrap()
			offset = $out.len().to_u32_wrap()
			# The fields both headers share, from "version needed" on.
			common = []
				.concat(u16(10))
				.concat(u16(utf8_names))
				.concat(u16(0))
				.concat(u16(time))
				.concat(u16(date))
				.concat(u32(crc))
				.concat(u32(size))
				.concat(u32(size))
				.concat(u16(name.len().to_u16_wrap()))
				.concat(u16(0))
			$out = $out.concat(u32(0x04034B50)).concat(common).concat(name).concat(entry.bytes)
			$central = $central
				.concat(u32(0x02014B50))
				.concat(u16(made_by_unix))
				.concat(common)
				.concat(u16(0))
				.concat(u16(0))
				.concat(u16(0))
				.concat(u32(Zip.attributes(entry.kind)))
				.concat(u32(offset))
				.concat(name)
		}
		count = sorted.len().to_u16_wrap()
		end = []
			.concat(u32(0x06054B50))
			.concat(u16(0))
			.concat(u16(0))
			.concat(u16(count))
			.concat(u16(count))
			.concat(u32($central.len().to_u32_wrap()))
			.concat(u32($out.len().to_u32_wrap()))
			.concat(u16(0))
		$out.concat($central).concat(end)
	}

	## An entry's Unix mode and type, as the zip's external attributes hold
	## them: in the high 16 bits, with MS-DOS's directory bit for a directory.
	attributes : [Directory, Program, Plain] -> U32
	attributes = |kind|
		match kind {
			Directory => (0o040000.U32 + 0o755).shl_wrap(16) + 0x10
			Program => (0o100000.U32 + 0o755).shl_wrap(16)
			Plain => (0o100000.U32 + 0o644).shl_wrap(16)
		}

	## The most entries and bytes an archive without Zip64 can hold.
	fits : List(Entry) -> Bool
	fits = |entries| entries.len() < 65535 and entries.fold(0, |total, entry| total + entry.bytes.len() + 128 + entry.path.count_utf8_bytes()) < 0xFFFFFFFF

	## The MS-DOS time and date a zip records, for `seconds` after the Unix
	## epoch in UTC; times before 1980, which it cannot record, are 1980.
	dos_time : U64 -> { time : U16, date : U16 }
	dos_time = |seconds| {
		earliest = 315532800
		at = if (seconds < earliest) earliest else seconds
		{ year, month, day } = civil(at // 86400)
		of_day = at % 86400
		hour = of_day // 3600
		minute = (of_day % 3600) // 60
		second = of_day % 60
		capped = if (year > 2107) 2107 else year
		{
			time: (hour.shl_wrap(11) + minute.shl_wrap(5) + second // 2).to_u16_wrap(),
			date: ((capped - 1980).shl_wrap(9) + month.shl_wrap(5) + day).to_u16_wrap(),
		}
	}

	## The time the archive is stamped with when `SOURCE_DATE_EPOCH` names
	## none: 1980-01-01 00:00, the earliest a zip records.
	default_time : U64
	default_time = 315532800

	## The CRC-32 a zip records of each entry's bytes (IEEE 802.3).
	crc32 : List(U8) -> U32
	crc32 = |bytes| {
		var $c = 0xFFFFFFFF
		for b in bytes {
			index = $c.bitwise_xor(b.to_u32()).bitwise_and(0xFF).to_u64()
			$c = (crc_table.get(index) ?? 0).bitwise_xor($c.shr_zf_wrap(8))
		}
		$c.bitwise_xor(0xFFFFFFFF)
	}
}

## "Version made by": Unix (3), zip 3.0, so readers take the high 16 bits
## of the external attributes as the Unix mode.
made_by_unix : U16
made_by_unix = 0x031E

## General purpose flag 11: names are UTF-8.
utf8_names : U16
utf8_names = 0x0800

crc_table : List(U32)
crc_table = {
	var $table = []
	for n in (0.U32).range_exclusive_to(256) {
		var $c = n
		for _ in (0.U8).range_exclusive_to(8) {
			$c = if ($c.bitwise_and(1) == 1) (0xEDB88320.U32).bitwise_xor($c.shr_zf_wrap(1)) else $c.shr_zf_wrap(1)
		}
		$table = $table.append($c)
	}
	$table
}

## The year, month and day of a count of days since 1970-01-01 (Howard
## Hinnant's `civil_from_days`, for days on or after 1970).
civil : U64 -> { year : U64, month : U64, day : U64 }
civil = |days| {
	z = days + 719468
	era = z // 146097
	doe = z - era * 146097
	yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
	doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
	mp = (5 * doy + 2) // 153
	day = doy - (153 * mp + 2) // 5 + 1
	month = if (mp < 10) mp + 3 else mp - 9
	year = yoe + era * 400 + (if (month <= 2) 1 else 0)
	{ year, month, day }
}

u16 : U16 -> List(U8)
u16 = |n| [n.to_u8_wrap(), n.shr_zf_wrap(8).to_u8_wrap()]

u32 : U32 -> List(U8)
u32 = |n| [n.to_u8_wrap(), n.shr_zf_wrap(8).to_u8_wrap(), n.shr_zf_wrap(16).to_u8_wrap(), n.shr_zf_wrap(24).to_u8_wrap()]

compare_bytes : List(U8), List(U8) -> [Before, Same, After]
compare_bytes = |a, b|
	match (a, b) {
		([], []) => Same
		([], _) => Before
		(_, []) => After
		([x, .. as xs], [y, .. as ys]) => if (x < y) Before else if (x > y) After else compare_bytes(xs, ys)
	}

expect Zip.crc32("123456789".to_utf8()) == 0xCBF43926 and Zip.crc32([]) == 0

## The modes are 0755 for directories and programs, 0644 for the rest.
expect [Zip.attributes(Directory), Zip.attributes(Program), Zip.attributes(Plain)] == [0x41ED0010, 0x81ED0000, 0x81A40000]

## 1980 is the earliest; SOURCE_DATE_EPOCH 1700000000 is 2023-11-14 22:13:20.
expect {
	earliest = Zip.dos_time(0) == { time: 0, date: 0x0021 } and Zip.dos_time(Zip.default_time) == { time: 0, date: 0x0021 }
	later = Zip.dos_time(1700000000) == { time: (22.U16).shl_wrap(11) + (13.U16).shl_wrap(5) + 10, date: (43.U16).shl_wrap(9) + (11.U16).shl_wrap(5) + 14 }
	earliest and later
}

expect civil(0) == { year: 1970, month: 1, day: 1 } and civil(19675) == { year: 2023, month: 11, day: 14 } and civil(11016) == { year: 2000, month: 2, day: 29 }

## An archive is its entries, sorted, then the central directory and its
## end, whatever order the entries came in.
expect {
	entries = [
		{ path: "a.app/Contents/MacOS/a", kind: Program, bytes: [1, 2, 3] },
		{ path: "a.app/", kind: Directory, bytes: [] },
	]
	empty = { path: "", kind: Plain, bytes: [] }
	zip = Zip.archive(entries, Zip.default_time)
	reversed = Zip.archive([entries.get(1) ?? empty, entries.get(0) ?? empty], Zip.default_time)
	local_name = Str.from_utf8_lossy(zip.drop_first(30).take_first(6))
	end = zip.take_last(22)
	zip == reversed
		and zip.take_first(4) == [0x50, 0x4B, 0x03, 0x04]
		and local_name == "a.app/"
		and end.take_first(4) == [0x50, 0x4B, 0x05, 0x06]
		and end.drop_first(8).take_first(4) == [2, 0, 2, 0]
		and zip.len() == (30 + 6) + (30 + 22 + 3) + (46 + 6) + (46 + 22) + 22
}
