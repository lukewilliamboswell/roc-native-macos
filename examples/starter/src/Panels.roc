import pf.Engine exposing [Elem, Signal]
import pf.Ui
import logic.Eq
import logic.Queue
import Store
import Widgets

## The queue and EQ panels, below the transport. Opening a panel leaves
## the song playing and the picture in view, so each change is seen and
## heard as it is made. The preset editor is the third panel
## (`Editor.roc`).
##
## To add a panel: write a function here (or a module of its own, as the
## editor is) returning `Elem(ctx)`, add its name to `Panels.names`, and
## build it in `Player.panel`.
Panels := [].{

	## The panels the switcher offers, the first showing none.
	names : List(Str)
	names = ["Hide Panels", "Queue", "EQ", "Editor"]

	## The queue: every song, the current one marked, each with its lyrics'
	## state, a button to play it and one to remove it.
	queue : () -> Elem(ctx)
		where [ctx.store : () -> Engine.Reach(ctx, _)]
	queue = || {
		held = Store.cells.queue.signal()
		Ui.vstack(
			{ spacing: 8, align: Fill },
			[
				Ui.hstack(
					{},
					[
						Ui.text(held.map(|q| "Queue · ${Store.counted(Queue.len(q), "song")} of ${Queue.most.to_str()}"), { style: Headline }),
						Ui.spacer(),
						Widgets.confirm_button("Clear Queue", "Clear", Engine.handle_by(Store.queue_and_player(), |now, _| Store.cleared(now)), held.map(|q| Queue.len(q) > 0)),
					],
				),
				Engine.when(
					held.map(|q| Queue.len(q) == 0),
					|| Ui.text("The queue is empty. Drop songs on the picture, with their lyric files.", { style: Callout, color: TertiaryLabel }),
					|| Ui.scroll(
						{ opening_height: 160, spacing: 2 },
						Engine.each(
							held.map(Panels.rows),
							|row| row.id.to_str(),
							|row| Panels.entry_row(row.item()),
						),
					),
				),
			],
		)
	}

	## What a queue row shows.
	Row : { id : U64, n : U64, title : Str, lyrics : Str, current : Bool }

	rows : Queue(Store.Track) -> List(Row)
	rows = |q| {
		current = Queue.current_id(q) ?? U64.highest
		Queue.entries(q).map_with_index(|e, i| { id: e.id, n: i + 1, title: e.track.title, lyrics: Panels.lyrics_badge(e.track.lyrics), current: e.id == current })
	}

	lyrics_badge : Store.LyricState -> Str
	lyrics_badge = |state|
		match state {
			NoLyrics => "no lyrics"
			Reading(_) => "reading lyrics…"
			Loaded({ words: Timed(_), .. }) => "timed lyrics"
			Loaded({ words: Plain(_), .. }) => "lyrics as text"
			Loaded({ words: NoWords, .. }) => "no words"
			Unreadable(_) => "lyrics unreadable"
		}

	entry_row : Signal(r, Row) -> Elem(r)
		where [r.store : () -> Engine.Reach(r, _)]
	entry_row = |item|
		Ui.hstack(
			{ padding: Axes({ horizontal: 6, vertical: 2 }) },
			[
				Ui.text(item.map(|r| if (r.current) "▶" else "${r.n.to_str()}."), { design: MonospacedDigits, color: SecondaryLabel, width: Fixed(24), align: Trailing }),
				Ui.text(item.map(|r| r.title), { squeeze: Yield, overflow: TruncateTail }),
				Ui.spacer(),
				Ui.text(item.map(|r| r.lyrics), { style: Caption1, color: SecondaryLabel }),
				Ui.button(item.map(|r| "Play ${r.title}"), { on_press: Engine.handle_by({ r: item, now: Store.queue_and_player() }.Signal.map(|x| x), |x, _| Store.selected(x.now, x.r.id)), icon: Symbol("play.fill"), title_display: Hidden, bezel: Borderless }),
				Ui.button(item.map(|r| "Remove ${r.title}"), { on_press: Engine.handle_by({ r: item, now: Store.queue_and_player() }.Signal.map(|x| x), |x, _| Store.removed(x.now, x.r.id)), icon: Symbol("minus.circle"), title_display: Hidden, bezel: Borderless }),
			],
		)

	## The EQ: bypass, Flat, the preamp, and the ten bands. The player
	## applies each change as the slider moves (`Store.eq_changed`).
	eq : () -> Elem(ctx)
		where [ctx.store : () -> Engine.Reach(ctx, _)]
	eq = || {
		settings = Store.cells.eq.signal()
		Ui.vstack(
			{ spacing: 8, align: Fill },
			[
				Ui.hstack(
					{},
					[
						Ui.text("Equalizer", { style: Headline }),
						Ui.spacer(),
						Ui.checkbox("Bypass", { checked: settings.map(|s| s.bypass), on_change: Engine.handle_by(settings, |s, on| Store.eq_changed({ ..s, bypass: on })) }),
						Ui.button("Flat", { on_press: Engine.handle_by(settings, |s, _| Store.eq_changed(Eq.flattened(s))), enabled: settings.map(|s| !Eq.is_flat(s)), size: Small }),
					],
				),
				Widgets.labelled_slider("Preamp", settings.map(|s| s.preamp), Eq.preamp_range, Engine.handle_by(settings, Store.preamp_set), settings.map(|s| Eq.label(s.preamp))),
				Widgets.section(
					Engine.const("Bands"),
					|| Ui.vstack(
						{ spacing: 4, align: Fill },
						Eq.centres.map_with_index(
							|hz, band| {
								gain = Store.cells.eq.signal().map(|s| s.bands.get(band) ?? 0)
								Widgets.labelled_slider(Eq.centre_label(hz), gain, Eq.band_range, Engine.handle_by(Store.cells.eq.signal(), |s, typed| Store.band_set(s, band, typed)), gain.map(Eq.label))
							},
						),
					),
				),
			],
		)
	}
}
