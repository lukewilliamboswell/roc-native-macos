import pf.Engine exposing [Elem, Signal]
import pf.Ui
import logic.Library
import logic.Prefs
import logic.Queue
import logic.Scene
import Editor
import Export
import Media
import Panels
import Store
import Visual
import Words

## The player window, composed from the store's cells, the panels, the
## widgets and the effect sites. This is a composing module: it imports
## `Store` and hands each part what it shows.
##
## From the top: the title bar with the Lyrics toggle (Command-L) and Add
## lyrics…; the visualization, where songs are dropped, beside the preset
## list; the transport strip; the panel switcher and the open panel (queue,
## EQ or preset editor); and the notice. The visualization stays in view
## whatever panel is open.
##
## A view runs once, when the window opens. After that, a write wakes only
## the texts, rows and branches that read what it wrote, so a view reads
## state through signals (`cell.signal()`, `.map`) and never holds a value
## it read once.
Player := [].{

	## The whole window, which `src/main.roc` mounts.
	view : () -> Elem(Engine.StoreRoot(_))
	view = ||
		Ui.vstack(
			{ spacing: 12, align: Fill, width: AtLeast(720), padding: Axes({ horizontal: 4, vertical: 4 }) },
			[
				Player.title_bar(),
				Ui.hstack(
					{ spacing: 12, align: Top },
					[
						Ui.drop_zone(
							{ on_drop: Engine.handle_by(Store.queue_and_player(), |now, received| Store.received(now, received.files, received.refused)), padding: All(2) },
							Engine.derive(Player.drawing(), |scene| Visual.view(scene, Store.cells.player.signal().map(|p| p.reset), Engine.handle(Store.shader_heard), Words.overlay())),
						),
						Player.presets(),
					],
				),
				Player.transport(),
				Ui.segmented(Store.cells.panel.signal(), { choices: Panels.names, on_change: Engine.handle(|name| [Store.cells.panel.set(name)]) }),
				Engine.switch(Store.cells.panel.signal(), Panels.names, Player.panel),
				Ui.text(Store.cells.notice.signal(), { style: Callout, color: SecondaryLabel, overflow: Wrap, width: Fill }),
				Words.reading(),
				Editor.importing(),
				Export.site(),
				Export.saving(),
				Media.measuring(Store.cells.player.signal()),
				Media.output({ reading: { output: Store.cells.output.signal(), offsets: Store.cells.offsets.signal() }.Signal.map(|s| s), heard: Store.output_heard }),
			]
				.concat(Player.shortcuts())
				.concat(Player.saving())
				.concat(
					Media.session({
						opening: Store.opening,
						commands: Store.cells.media.signal(),
						reading: { queue: Store.cells.queue.signal(), player: Store.cells.player.signal() }.Signal.map(|s| s),
						heard: Store.heard,
						followed: Store.followed,
					}),
				),
		)

	## The panel the switcher names, built only while it is open.
	panel : Str -> Elem(Engine.StoreRoot(_))
	panel = |name|
		match name {
			"Queue" => Panels.queue()
			"EQ" => Panels.eq()
			"Editor" => Editor.view()
			_ => Engine.text("")
		}

	## The scene the visualization draws: the editor's draft while it is
	## open, the chosen preset otherwise. `Engine.derive` computes it once per
	## change of what it reads.
	drawing : () -> Signal(Engine.StoreRoot(_), Scene.Drawing)
	drawing = || { mine: Store.cells.mine.signal(), chosen: Store.cells.chosen.signal(), editor: Store.cells.editor.signal(), panel: Store.cells.panel.signal() }.Signal.map(Store.drawing)

	## The title, the current song, the Lyrics toggle and its size, and Add
	## lyrics… for the current song, with why its lyrics could not be read.
	title_bar : () -> Elem(Engine.StoreRoot(_))
	title_bar = || {
		queue = Store.cells.queue.signal()
		current = queue.map(|q| Queue.current(q).map_ok(|e| e.track))
		on = Store.cells.lyrics_on.signal()
		Ui.hstack(
			{ spacing: 10 },
			[
				## `assets/icon.png` is also the app's icon.
				Ui.asset_image("icon.png", { width: Fixed(30) }),
				Ui.text("Music", { style: Title2, weight: Bold }),
				Ui.text(current.map(|t| t.map_ok(|track| track.title) ?? "Nothing playing"), { style: Title3, color: SecondaryLabel, squeeze: Yield, overflow: TruncateTail }),
				Ui.spacer(),
				Engine.when(
					current.map(|t| t.is_ok()),
					|| Ui.hstack(
						{ spacing: 6 },
						[
							Ui.text(Store.cells.queue.signal().map(Player.lyrics_problem), { style: Caption1, color: Red, squeeze: Yield, overflow: TruncateTail }),
							Ui.file_button("Add lyrics…", { on_files: Engine.handle_by(Store.cells.queue.signal(), |q, received| Store.added_lyrics(q, received.files)), size: Small }),
						],
					),
					|| Engine.text(""),
				),
				Engine.when(
					on,
					|| Ui.hstack(
						{ spacing: 2 },
						[
							Ui.button("Smaller Lyrics", { on_press: Engine.handle(|_| [Store.cells.lyric_size.update(Prefs.smaller)]), icon: Symbol("textformat.size.smaller"), title_display: Hidden, bezel: Borderless }),
							Ui.button("Larger Lyrics", { on_press: Engine.handle(|_| [Store.cells.lyric_size.update(Prefs.larger)]), icon: Symbol("textformat.size.larger"), title_display: Hidden, bezel: Borderless }),
						],
					),
					|| Engine.text(""),
				),
				Ui.checkbox("Lyrics", { checked: on, on_change: Engine.handle(|checked| Store.toggled_lyrics(!checked)) }),
			],
		)
	}

	## Why the current song's lyric file could not be read, or nothing.
	lyrics_problem : Queue(Store.Track) -> Str
	lyrics_problem = |q|
		match Queue.current(q).map_ok(|e| e.track.lyrics) {
			Ok(Unreadable({ name, why })) => "${name}: ${why}"
			_ => ""
		}

	## The preset list beside the picture: every preset by name, the chosen
	## one marked, then New, Duplicate and Edit (Save As is in the editor).
	presets : () -> Elem(Engine.StoreRoot(_))
	presets = || {
		chosen = Store.cells.chosen.signal()
		items = { mine: Store.cells.mine.signal(), chosen }.Signal.map(|x| Library.all(x.mine).map(|p| { id: p.id, name: p.name, on: p.id == x.chosen }))
		Ui.vstack(
			{ spacing: 8, align: Fill, width: Fixed(190) },
			[
				Ui.hstack(
					{},
					[
						Ui.text("Presets", { style: Headline }),
						Ui.spacer(),

						## Shaders need the Metal renderer; elsewhere a preset draws its
						## layers alone, and says so.
						Engine.when(
							Store.cells.shader_status.signal().map(|s| s == Fallback),
							|| Ui.text("Simple visuals", { style: Caption1, color: SecondaryLabel }),
							|| Engine.text(""),
						),
					],
				),
				Ui.text(
					items.map(|rows| rows.find_first(|p| p.on).map_ok(|p| "Using ${p.name}") ?? ""),
					{ style: Caption1, color: SecondaryLabel, overflow: TruncateTail, width: Fill },
				),
				Ui.box(
					{ fill: TextBackground, border: Line({ color: Separator, width: 1 }), radius: 12, padding: All(4), width: Fill },
					Ui.scroll(
						{ opening_height: 190, height: Fixed(190), spacing: 2 },
						Engine.each(
							items,
							|row| row.id,
							|row| {
								item = row.item()
								Ui.hstack(
									{ spacing: 4, padding: Axes({ horizontal: 4, vertical: 3 }) },
									[
										Ui.text(item.map(|i| if (i.on) "●" else ""), { color: Accent, width: Fixed(12) }),
										Ui.button(item.map(|i| i.name), { on_press: Engine.handle_by({ i: item, mine: Store.cells.mine.signal() }.Signal.map(|x| x), |x, _| Store.chose(x.mine, x.i.id)), bezel: Borderless, squeeze: Yield }),
									],
								)
							},
						),
					),
				),
				Ui.hstack(
					{ spacing: 4 },
					[
						Ui.button("New", { on_press: Engine.does(Store.started_new.append(Store.cells.panel.set("Editor"))), size: Small }),
						Ui.button("Duplicate", { on_press: Engine.handle_by({ mine: Store.cells.mine.signal(), editor: Store.cells.editor.signal() }.Signal.map(|x| x), |x, _| Store.duplicated(x.mine, x.editor)), size: Small }),
						Ui.button("Edit", { on_press: Engine.does([Store.cells.panel.set("Editor")]), size: Small }),
					],
				),
			],
		)
	}

	## The transport: the time, the seek slider, Previous, Play or Pause,
	## Stop and Next, and the volume.
	transport : () -> Elem(Engine.StoreRoot(_))
	transport = || {
		player = Store.cells.player.signal()
		queue = Store.cells.queue.signal()
		both = { q: queue, p: player }.Signal.map(|x| x)
		Ui.box(
			{ fill: ControlBackground, radius: 12, padding: Axes({ horizontal: 12, vertical: 10 }), border: Line({ color: Separator, width: 1 }) },
			Ui.hstack(
				{ spacing: 8 },
				[
					Ui.text(player.map(Player.times), { weight: Medium, design: MonospacedDigits, width: Fixed(110) }),
					Ui.slider(player.map(Player.permille), { range: { min: 0, max: 1000 }, on_input: Engine.handle_by(player, Store.sought), enabled: player.map(|p| p.duration_ms > 0), width: Fill }),
					Ui.button("Previous", { on_press: Engine.handle_by(Store.queue_and_player(), |now, _| Store.previous(now)), icon: Symbol("backward.fill"), title_display: Hidden, bezel: Borderless }),
					Ui.button(player.map(|p| if (p.status == Playing) "Pause" else "Play"), { on_press: Engine.handle_by(both, |x, _| Store.play_pause(x.q, x.p)), icon: Symbol("playpause.fill"), enabled: queue.map(|q| Queue.len(q) > 0) }),
					Ui.button("Stop", { on_press: Engine.handle_by(player, |p, _| Store.stopped(p)), icon: Symbol("stop.fill"), title_display: Hidden, bezel: Borderless }),
					Ui.button("Next", { on_press: Engine.handle_by(Store.queue_and_player(), |now, _| Store.next(now)), icon: Symbol("forward.fill"), title_display: Hidden, bezel: Borderless }),
					Ui.image("speaker.wave.2.fill", { color: SecondaryLabel }),
					Ui.slider(Store.cells.volume.signal(), { range: { min: 0, max: 100 }, on_input: Engine.handle(Store.volume_set), width: Fixed(90) }),
				],
			),
		)
	}

	## Elapsed time and length, `0:07 / 3:12`; a length not known yet is
	## `–:––`.
	times : Media.Player -> Str
	times = |p| "${Player.clock(p.position_ms)} / ${if (p.duration_ms == 0) "–:––" else Player.clock(p.duration_ms)}"

	clock : U64 -> Str
	clock = |ms| {
		seconds = ms // 1000
		s = seconds % 60
		"${(seconds // 60).to_str()}:${if (s < 10) "0" else ""}${s.to_str()}"
	}

	permille : Media.Player -> I64
	permille = |p| if (p.duration_ms == 0) 0 else (p.position_ms * 1000 // p.duration_ms).to_i64_wrap()

	## Command-L shows or hides the lyrics; the arrow keys seek five seconds.
	shortcuts : () -> List(Elem(Engine.StoreRoot(_)))
	shortcuts = ||
		[
			Ui.shortcut([Ui.command("l")], { on_key: Engine.handle_by(Store.cells.lyrics_on.signal(), |on, _| Store.toggled_lyrics(on)) }),
			Ui.shortcut([Ui.plain_key("ArrowRight")], { on_key: Engine.handle_by(Store.cells.player.signal(), |p, _| Store.nudged(p, 5_000)) }),
			Ui.shortcut([Ui.plain_key("ArrowLeft")], { on_key: Engine.handle_by(Store.cells.player.signal(), |p, _| Store.nudged(p, -5_000)) }),
		]

	## The sites that save the listener's presets and choices whenever they
	## change, read back at the next launch (`Store.start`).
	## `Engine.watch_changes` never cancels a save it asked for.
	saving : () -> List(Elem(Engine.StoreRoot(_)))
	saving = ||
		[
			Engine.watch_changes(
				Store.cells.mine.signal().map(Library.to_storage),
				|text| [Engine.command(StorageSet(Store.presets_key, text))],
				Engine.ignore({}),
			),
			Engine.watch_changes(
				{ lyrics: Store.cells.lyrics_on.signal(), lyric_size: Store.cells.lyric_size.signal(), chosen: Store.cells.chosen.signal(), volume: Store.cells.volume.signal(), eq: Store.cells.eq.signal(), offsets: Store.cells.offsets.signal() }.Signal.map(|s| Prefs.encode(Store.prefs(s))),
				|text| [Engine.command(StorageSet(Store.prefs_key, text))],
				Engine.ignore({}),
			),
		]
}

expect Player.clock(0) == "0:00" and Player.clock(72_400) == "1:12" and Player.times({ ..Media.stopped, position_ms: 7_000 }) == "0:07 / –:––"
expect Player.permille({ ..Media.stopped, position_ms: 5_000, duration_ms: 20_000 }) == 250
