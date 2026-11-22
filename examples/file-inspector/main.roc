app [main] { pf: platform "../../platform/main.roc" }

import pf.Engine exposing [Elem, File, Signal]
import pf.Ui

## A file inspector: pick files in an open panel or drop them from the
## Finder. The app holds each one as a handle (a `File`), never its bytes,
## and lists them; inspecting one asks the host for its SHA-256 digest and
## its first bytes as text and a URL that shows it, and "Save copy…" saves
## it through a save panel.
## Clearing the list drops the handles, and the host lets the files go.
main : Engine.Program(_)
main = Engine.program_store({}, |_boot| store, |_boot| view())

## What one inspected file shows while its requests are answered.
Selected : [Nothing, Picked(File)]

store = Engine.store(
	Inspector,
	{
		files: Engine.cell([]),
		refused: Engine.cell(0.U64),
		selected: Engine.cell(Nothing),
		digest: Engine.cell(""),
		preview: Engine.cell(""),
		url: Engine.cell(""),
		save: Engine.cell(NotYet),
	}.Engine.Cells,
)

cells = store.cells()

view : () -> Elem(Engine.StoreRoot(_))
view = || {
	selected = cells.selected.signal()
	Ui.vstack(
		{},
		[
			Ui.title("File inspector"),
			Ui.hstack(
				{},
				[
					Ui.file_button("Choose files…", Engine.handle(received)),
					Ui.button("Clear", Engine.handle(|_| [cells.files.set([]), cells.selected.set(Nothing), cells.refused.set(0)])),
				],
			),
			Ui.drop_zone("Drop files here", Engine.handle(received)),
			Ui.label_s({ files: cells.files.signal(), refused: cells.refused.signal() }.Signal.map(summary)),
			Ui.vstack(
				{},
				[
					Engine.each(
						cells.files.signal().map(|files| files.map_with_index(|file, index| { file, index })),
						|item| item.index.to_str(),
						|row| Ui.hstack(
							{},
							[
								Ui.label_s(row.item().map(|item| describe(item.file))),
								Ui.spacer(),
								Ui.button("Inspect", Engine.handle_by(row.item(), |item, _| inspect(item.file))),
							],
						),
					),
				],
			),
			Ui.divider(),
			Engine.when(
				selected.map(|s| s != Nothing),
				|| Ui.vstack(
					{},
					[
						Ui.label_s(selected.map(|s| match s { Picked(f) => "Inspecting ${f.name()}" Nothing => "" })),
						Ui.label_s(cells.digest.signal().map(|d| "SHA-256: ${d}")),
						Ui.label_s(cells.preview.signal().map(|p| "Starts: ${p}")),
						Ui.label_s(cells.url.signal().map(|u| "URL: ${u}")),
						Ui.button("Save copy…", Engine.handle_by(selected, |s, _| save_copy(s))),
					],
				),
				|| Ui.label("Choose or drop files, then inspect one."),
			),
			# The digest and the first bytes of the inspected file. Inspecting
			# another file cancels what the last one still had in flight.
			Engine.watch_latest(
				selected,
				|s| match s {
					Picked(f) => [f.sha256()]
					Nothing => []
				},
				Engine.react(
					|_, result| match result {
						Ok(bytes) => [cells.digest.set(hex(bytes))]
						Err(e) => [cells.digest.set("unavailable (${Str.inspect(e)})")]
					},
				),
			),
			Engine.watch_latest(
				selected,
				|s| match s {
					Picked(f) =>
						match f.slice({ start: 0, len: f.size().min(preview_bytes) }) {
							Ok(head) => [head.read_bytes({})]
							Err(_) => []
						}
					Nothing => []
				},
				Engine.react(
					|_, result| match result {
						Ok(bytes) => [cells.preview.set(as_text(bytes))]
						Err(e) => [cells.preview.set("unreadable (${Str.inspect(e)})")]
					},
				),
			),
			Engine.watch_latest(
				selected,
				|s| match s {
					Picked(f) => [f.object_url()]
					Nothing => []
				},
				Engine.react(
					|_, result| match result {
						Ok(url) => [cells.url.set(url)]
						Err(e) => [cells.url.set("none (${Str.inspect(e)})")]
					},
				),
			),
			# Each press of "Save copy…" is a new value, so each one saves.
			Engine.watch_changes(
				cells.save.signal(),
				|s| match s {
					Save(f, _) => [Engine.command(File.save(f, { name: Named("Copy of ${f.name()}") }))]
					NotYet => []
				},
				Engine.ignore({}),
			),
		],
	)
}

## How many bytes the preview reads.
preview_bytes : U64
preview_bytes = 200

received : Engine.Received -> List(Engine.Write(_))
received = |{ files, refused }| [cells.files.update(|held| held.concat(files)), cells.refused.update(|n| n + refused)]

inspect : File -> List(Engine.Write(_))
inspect = |file| [cells.selected.set(Picked(file)), cells.digest.set("…"), cells.preview.set("…"), cells.url.set("…")]

save_copy : Selected -> List(Engine.Write(_))
save_copy = |s|
	match s {
		Picked(f) =>
			[
				cells.save.update(
					|prev| match prev {
						Save(_, n) => Save(f, n + 1)
						NotYet => Save(f, 1)
					},
				),
			]
		Nothing => []
	}

summary : { files : List(File), refused : U64 } -> Str
summary = |{ files, refused }| {
	held = match files.len() {
		0 => "No files yet"
		1 => "1 file"
		n => "${n.to_str()} files"
	}
	if refused == 0 held else "${held} (${refused.to_str()} refused: too many held)"
}

## `name — size — type`
describe : File -> Str
describe = |f| {
	kind = if f.mime().is_empty() "unknown type" else f.mime()
	"${f.name()} — ${f.size().to_str()} bytes — ${kind}"
}

## Lowercase hexadecimal.
hex : List(U8) -> Str
hex = |bytes| {
	digits = "0123456789abcdef".to_utf8()
	var $out = []
	for b in bytes {
		$out = $out.append(digits.get((b // 16).to_u64()) ?? '?').append(digits.get((b % 16).to_u64()) ?? '?')
	}
	Str.from_utf8($out) ?? ""
}

## The bytes as text, or "binary" for bytes that are not UTF-8 text. A
## multi-byte character the cut split at the end is dropped.
as_text : List(U8) -> Str
as_text = |bytes| {
	if bytes.contains(0) {
		return "binary"
	}
	var $drop = 0.U64
	while $drop < 4 and $drop <= bytes.len() {
		match Str.from_utf8(bytes.take_first(bytes.len() - $drop)) {
			Ok(text) => return text.trim()
			Err(_) => {}
		}
		$drop = $drop + 1
	}
	"binary"
}

expect hex([0, 15, 16, 255]) == "000f10ff"
expect as_text("hello\n".to_utf8()) == "hello"
expect as_text([104, 105, 0]) == "binary"
expect as_text([104, 105, 0xE2, 0x82]) == "hi"
expect as_text([0xFF, 0xFE, 0xFD, 0xFC, 0xFB]) == "binary"
