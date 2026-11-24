app [main] { pf: platform "../../../platform/main.roc" }

import pf.Engine exposing [Elem, File, Signal]
import pf.Ui

## A file inspector: pick files in an open panel or drop them from the
## Finder. The app holds each one as a handle (a `File`), never its bytes,
## and lists them; inspecting one asks the host for its SHA-256 digest and
## its first bytes as text and a URL that shows it, and "Save Copy…" saves
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

## The looks the inspector shares.
Theme : {
	caption : Ui.TextProps,
	field : Ui.TextProps,
	panel : Ui.BoxProps,
}

theme : Theme
theme = {
	caption: { style: Caption1, color: SecondaryLabel },
	field: { style: Callout, design: Monospaced, overflow: TruncateMiddle, width: Fill, squeeze: Yield },
	panel: { border: Line({ color: Separator, width: 1 }), width: Fill },
}

view : () -> Elem(Engine.StoreRoot(_))
view = || {
	selected = cells.selected.signal()
	files = cells.files.signal()
	Ui.vstack(
		{ spacing: 14, align: Fill, width: AtLeast(520) },
		[
			Ui.hstack(
				{},
				[
					Ui.text("File inspector", { style: Title2, weight: Semibold }),
					Ui.spacer(),
					Ui.file_button("Choose Files…", { on_files: Engine.handle(received), icon: Symbol("doc.badge.plus") }),
					Ui.button("Clear", { on_press: Engine.handle(|_| [cells.files.set([]), cells.selected.set(Nothing), cells.refused.set(0)]), enabled: files.map(|held| !held.is_empty()) }),
				],
			),
			Ui.drop_zone(
				{ on_drop: Engine.handle(received) },
				Ui.vstack(
					{ spacing: 4, align: Center, width: Fill },
					[
						Ui.image("arrow.down.doc", { style: Title1, color: SecondaryLabel }),
						Ui.text("Drop files here", { style: Headline, color: SecondaryLabel }),
						Ui.text("The app holds each file as a handle, never its bytes.", { style: Caption1, color: TertiaryLabel }),
					],
				),
			),
			Ui.text({ files, refused: cells.refused.signal() }.Signal.map(summary), theme.caption),
			Engine.when(
				files.map(|held| held.is_empty()),
				|| Engine.text(""),
				|| Ui.box(
					{ ..theme.panel, padding: Axes({ horizontal: 10, vertical: 6 }) },
					Ui.vstack(
						{ spacing: 4, align: Fill },
						[
							Engine.each(
								files.map(|held| held.map_with_index(|file, index| { file, index })),
								|item| item.index.to_str(),
								|row| {
									item = row.item()
									Ui.hstack(
										{},
										[
											Ui.image("doc", { style: Title3, color: Accent }),
											Ui.vstack(
												{ spacing: 1 },
												[
													Ui.text(item.map(|i| i.file.name()), { overflow: TruncateMiddle }),
													Ui.text(item.map(|i| "${size(i.file.size())} · ${kind(i.file)}"), theme.caption),
												],
											),
											Ui.spacer(),
											Ui.button("Inspect", { on_press: Engine.handle_by(item, |i, _| inspect(i.file)), size: Small }),
										],
									)
								},
							),
						],
					),
				),
			),
			Engine.when(
				selected.map(|s| s != Nothing),
				|| Ui.box(
					{ ..theme.panel, padding: All(14) },
					Ui.vstack(
						{ spacing: 8, align: Fill },
						[
							Ui.hstack(
								{},
								[
									Ui.image("doc.text.magnifyingglass", { style: Title2, color: Accent }),
									Ui.text(
										selected.map(
											|s| match s {
												Picked(f) => f.name()
												Nothing => ""
											},
										),
										{ style: Headline, overflow: TruncateMiddle, squeeze: Yield },
									),
									Ui.spacer(),
									Ui.button("Save Copy…", { on_press: Engine.handle_by(selected, |s, _| save_copy(s)), icon: Symbol("square.and.arrow.down") }),
								],
							),
							Ui.divider(),
							detail("SHA-256", cells.digest.signal()),
							detail("Starts", cells.preview.signal()),
							detail("URL", cells.url.signal()),
						],
					),
				),
				|| Ui.text("Choose or drop files, then inspect one.", { color: TertiaryLabel, align: Center, width: Fill }),
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
			# Each press of "Save Copy…" is a new value, so each one saves.
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

## One labelled line of the detail panel.
detail : Str, Signal(ctx, Str) -> Elem(ctx)
detail = |label, value|
	Ui.hstack(
		{ align: FirstBaseline },
		[
			Ui.text(Engine.const(label), { ..theme.caption, align: Trailing, width: Fixed(64) }),
			Ui.text(value, theme.field),
		],
	)

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
	if (refused == 0) held else "${held} (${refused.to_str()} refused: too many held)"
}

## A file's type as the host guessed it.
kind : File -> Str
kind = |f| if (f.mime().is_empty()) "unknown type" else f.mime()

## A byte count for people: bytes, KB or MB (1000s, as the Finder counts).
size : U64 -> Str
size = |bytes|
	if bytes < 1000 {
		"${bytes.to_str()} bytes"
	} else if bytes < 1_000_000 {
		"${(bytes // 1000).to_str()}.${((bytes % 1000) // 100).to_str()} KB"
	} else {
		"${(bytes // 1_000_000).to_str()}.${((bytes % 1_000_000) // 100_000).to_str()} MB"
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
expect [size(12), size(1_256), size(3_400_000)] == ["12 bytes", "1.2 KB", "3.4 MB"]
