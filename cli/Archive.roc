import zip.Zip

## A zip archive of an app, the same bytes on every system and every run,
## written by roc-zip and compressed with DEFLATE at its `Balanced` level.
##
## Each entry's Unix mode is set from what the entry is, not from the file
## system it was read from: directories and programs 0755, other files 0644.
## A zip made on Windows, or by a tool that drops the modes, loses a
## program's execute bit, and macOS then will not launch the app. Entries
## are sorted by path, and all carry one modification time.
Archive := [].{

	## What goes in the archive: a path with `/` separators (a directory's
	## ending in `/`), what it is, and its bytes.
	Entry : { path : Str, kind : [Directory, Program, Plain], bytes : List(U8) }

	## The archive of `entries`, every entry stamped with the time `seconds`
	## after the Unix epoch, in UTC (1980, the earliest a zip records, for
	## anything before it).
	archive : List(Entry), U64 -> Try(List(U8), [CannotZip(Str)])
	archive = |entries, seconds| {
		modified = Zip.dos_time(seconds)
		sorted = entries.sort_with(|a, b| compare_bytes(a.path.to_utf8(), b.path.to_utf8()))
		items : List(Zip.Item)
		items = sorted.map(|entry| item(entry, modified))
		Zip.create_items(items, Balanced).map_err(|problem| CannotZip(Str.inspect(problem)))
	}

	## An entry's Unix permission bits.
	mode : [Directory, Program, Plain] -> U16
	mode = |kind|
		match kind {
			Directory | Program => 0o755
			Plain => 0o644
		}

	## The time the archive is stamped with when `SOURCE_DATE_EPOCH` names
	## none: 1980-01-01 00:00, the earliest a zip records.
	default_time : U64
	default_time = 315532800
}

item : Archive.Entry, Zip.DosTime -> Zip.Item
item = |entry, modified|
	match entry.kind {
		Directory => Directory({ path: entry.path, mode: Unix(Archive.mode(Directory)), modified })
		kind => File({ path: entry.path, content: entry.bytes, mode: Unix(Archive.mode(kind)), modified })
	}

compare_bytes : List(U8), List(U8) -> [Before, Same, After]
compare_bytes = |a, b|
	match (a, b) {
		([], []) => Same
		([], _) => Before
		(_, []) => After
		([x, .. as xs], [y, .. as ys]) => if (x < y) Before else if (x > y) After else compare_bytes(xs, ys)
	}

## Entries are sorted, carry their modes (with their file type, as a reader
## sees them) and the one time, and round-trip;
## the order they came in does not change a byte.
expect {
	program = List.repeat(7, 4096)
	entries = [
		{ path: "a.app/Contents/MacOS/a", kind: Program, bytes: program },
		{ path: "a.app/Contents/Info.plist", kind: Plain, bytes: "<plist/>".to_utf8() },
		{ path: "a.app/", kind: Directory, bytes: [] },
	]
	empty = { path: "", kind: Plain, bytes: [] }
	reordered = [entries.get(2) ?? empty, entries.get(0) ?? empty, entries.get(1) ?? empty]
	zip = Archive.archive(entries, 1700000000) ?? []
	listed = (Zip.entries(zip) ?? []).map(|e| { path: e.path, mode: e.mode, modified: e.modified })
	when = Zip.dos_time(1700000000)
	zip == (Archive.archive(reordered, 1700000000) ?? [1])
		and listed
			== [
				{ path: "a.app/", mode: Unix(0o040755), modified: when },
				{ path: "a.app/Contents/Info.plist", mode: Unix(0o100644), modified: when },
				{ path: "a.app/Contents/MacOS/a", mode: Unix(0o100755), modified: when },
			]
		and zip.len() < program.len()
}

expect [Archive.mode(Directory), Archive.mode(Program), Archive.mode(Plain)] == [0o755, 0o755, 0o644]

## Before 1980 is 1980-01-01 00:00.
expect Zip.dos_time(0) == { date: 0x0021, time: 0 } and Zip.dos_time(Archive.default_time) == { date: 0x0021, time: 0 }
