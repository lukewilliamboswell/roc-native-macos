import pf.Engine exposing [Elem, Signal]
import pf.Ui
import logic.Prefs
import Media
import Store
import Visual

## Choose how to show the lyrics and read a lyric file for its queue
## entry. `Store.overlay` picks the cue from the playback position and
## `Media.boundary` schedules the next cue independently of the frame
## clock. Read all lets the listener scroll the verses or timed lines.
Words := [].{

	## The overlay, for `Visual.view` to place over the picture.
	overlay : () -> Elem(ctx)
		where [ctx.store : () -> Engine.Reach(ctx, _)]
	overlay = || {
		cells = Store.cells
		state = { queue: cells.queue.signal(), player: cells.player.signal(), on: cells.lyrics_on.signal(), all: cells.reading_all.signal() }.Signal.map(Store.overlay)
		size = cells.lyric_size.signal()
		Ui.vstack(
			{ spacing: 6, align: Fill },
			[
				Engine.derive(
					state,
					|shown|
						Engine.switch(
							shown.map(Words.mode),
							["clear", "following", "reading"],
							|kind|
								match kind {
									"following" => Words.following(shown, size.lift())
									"reading" => Words.reading_all(shown, size.lift())
									_ => Engine.text("")
								},
						),
				),
				Media.boundary({
					player: cells.player.signal(),
					at: { queue: cells.queue.signal(), player: cells.player.signal(), on: cells.lyrics_on.signal() }.Signal.map(Store.boundary),
					reading: { queue: cells.queue.signal(), player: cells.player.signal() }.Signal.map(|s| s),
					followed: Store.followed,
				}),
			],
		)
	}

	mode : Store.Overlay -> Str
	mode = |o|
		match o {
			Clear => "clear"
			Following(_) => "following"
			ReadingAll(_) => "reading"
			Text(_) => "reading"
		}

	## The current line, large, and the next one beneath, on their backing.
	## Before the first line and in an empty cue, nothing shows.
	following : Signal(ctx, Store.Overlay), Signal(ctx, Prefs.LyricSize) -> Elem(ctx)
		where [ctx.store : () -> Engine.Reach(ctx, _)]
	following = |shown, size|
		Engine.when(
			shown.map(|o| Words.now(o).is_empty()),
			|| Ui.hstack({}, [Ui.spacer(), Words.toggle_button("Read all")]),
			|| Ui.box(
				{ fill: Visual.backing, padding: Axes({ horizontal: 14, vertical: 10 }), width: Fill },
				Ui.vstack(
					{ spacing: 4, align: Fill },
					[
						Ui.text_s(shown.map(|o| Str.join_with(Words.now(o), "\n")), size.map(|s| { size: Fixed(Prefs.points(s)), weight: Semibold, color: Visual.light, overflow: Wrap, align: Center, width: Fill })),
						Ui.text_s(shown.map(|o| Str.join_with(Words.coming(o), "\n")), size.map(|s| { size: Fixed(Prefs.points(s) * 2 // 3), color: Visual.dim, overflow: WrapUpTo(2), align: Center, width: Fill })),
						Ui.hstack({}, [Ui.spacer(), Words.toggle_button("Read all")]),
					],
				),
			),
		)

	## Every line, to read at the listener's own pace.
	reading_all : Signal(ctx, Store.Overlay), Signal(ctx, Prefs.LyricSize) -> Elem(ctx)
		where [ctx.store : () -> Engine.Reach(ctx, _)]
	reading_all = |shown, size|
		Ui.box(
			{ fill: Visual.backing, padding: Axes({ horizontal: 14, vertical: 10 }), width: Fill },
			Ui.vstack(
				{ spacing: 6, align: Fill },
				[
					Ui.scroll(
						{ opening_height: 140, height: Between({ min: 80, max: 220 }) },
						Ui.text_s(
							shown.map(
								|o|
									match o {
										ReadingAll(lines) => Str.join_with(lines, "\n")
										Text(lines) => Str.join_with(lines, "\n")
										_ => ""
									},
							),
							size.map(|s| { size: Fixed(Prefs.points(s) * 3 // 4), color: Visual.light, overflow: Wrap, width: Fill }),
						),
					),
					Engine.when(
						shown.map(Words.is_timed),
						|| Ui.hstack({}, [Ui.spacer(), Words.toggle_button("Follow")]),
						|| Engine.text(""),
					),
				],
			),
		)

	## Read all, or Follow, which returns to the current line.
	toggle_button : Str -> Elem(ctx)
		where [ctx.store : () -> Engine.Reach(ctx, _)]
	toggle_button = |title|
		Ui.button(Engine.const(title), { on_press: Engine.handle_by(Store.cells.reading_all.signal(), |all, _| [Store.cells.reading_all.set(!all)]), size: Small })

	now : Store.Overlay -> List(Str)
	now = |o|
		match o {
			Following({ now: lines, .. }) => lines
			_ => []
		}

	coming : Store.Overlay -> List(Str)
	coming = |o|
		match o {
			Following({ next: lines, .. }) => lines
			_ => []
		}

	## Whether the words shown in full are timed (and so can be followed).
	is_timed : Store.Overlay -> Bool
	is_timed = |o|
		match o {
			ReadingAll(_) => Bool.True
			_ => Bool.False
		}

	## The site that reads lyric files, one at a time, through the bounded
	## file API: at most `Words.most_bytes` of UTF-8 text, read on the page.
	## The handle is released once the read is done and the file leaves
	## `reads`. Removing the song cancels its read.
	reading : () -> Elem(ctx)
		where [ctx.store : () -> Engine.Reach(ctx, _)]
	reading = ||
		Engine.watch_latest(
			Store.cells.reads.signal().map(|held| held.first().map_err(|_| Nothing)),
			|head|
				match head {
					Ok(read) => [read.file.read_utf8({ max_bytes: Words.most_bytes })]
					Err(_) => []
				},
			Engine.react(
				|head, answer|
					match head {
						Ok(read) => Store.lyrics_read(read, answer)
						Err(_) => []
					},
			),
		)

	## The largest lyric file read: 256 KiB, far more than any song's words.
	most_bytes : U64
	most_bytes = 262_144
}
