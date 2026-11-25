import pf.Engine exposing [File, Signal]
import pf.Ui
import logic.Eq
import logic.Library
import logic.Lyrics
import logic.Pairing
import logic.Prefs
import logic.Preset
import logic.Queue
import logic.Scene
import Media
import "../assets/polymorphic-defunctionalization.lrc" as default_lrc : Str

## Own the queue, player, EQ, preset library, editor draft and lyrics
## settings here. Give state used by one widget to `Engine.state` (see
## `Widgets.section`). Use `.map` or `Engine.derive` for a value that
## follows other state (see `Player.drawing`).
##
## A decision returns writes, like `Store.toggled_lyrics`. Attach it with
## `Engine.handle_by` for an event or `Engine.react` for an effect reply.
## Check the result in an expect with `Store.store.after(writes).read(cell)`.
##
## Group playback commands in one `Store.send` per turn. Keep reusable
## widgets independent of this store by passing them values and handlers.
## https://lukewilliamboswell.github.io/roc-native-macos/apps.html#work-on-the-starter
Store := [Music].{

	## A song in the queue: where it comes from (a file the listener gave,
	## held as long as it is queued, or the app's own asset), its title, and
	## its words.
	Track : { file : Media.Source, title : Str, lyrics : LyricState }

	## A song's words: none, a lyric file being read, the words read from
	## one, or why one could not be read.
	LyricState : [NoLyrics, Reading(Str), Loaded({ name : Str, words : Lyrics.Words }), Unreadable({ name : Str, why : Str })]

	## A lyric file waiting to be read for the queue entry `entry`.
	LyricRead : { entry : U64, file : File }

	## The preset editor: the draft (always a valid preset, the last one
	## that was), the text of its file as the listener edits it, the fields
	## that need attention, and the name to save it as.
	Editor : { draft : Preset.Doc, text : Str, problems : List(Preset.FieldError), name : Str }

	## An export a worker is building (`Export`): the preset's name and file
	## text, and a count so that exporting the same preset again asks again.
	Exporting : [NotExporting, Building({ name : Str, text : Str, serial : U64 })]

	## The store: its name, then its cells with their starting values.
	## Each cell changes independently, and a write wakes only the views
	## that read that cell, so keep separate concerns in separate cells.
	##
	## A store needs at least two cells: a record builder with a single
	## field (`{ a: Engine.cell(0) }.Engine.Cells`) compiles but fails at run
	## time with current compilers, which `roc test` reports.
	store = Engine.store(
		Store.Music,
		{
			queue: Engine.cell(Store.first_queue),
			player: Engine.cell({ ..Media.stopped, generation: Queue.generation(Store.first_queue) }),

			## The commands for the player this turn (`Store.send`).
			media: Engine.cell(Engine.outbox({})),
			volume: Engine.cell(Prefs.defaults.volume),
			eq: Engine.cell(Prefs.defaults.eq),

			## Lyric files waiting to be read, read one at a time (`Words.reading`).
			reads: Engine.cell([]),
			lyrics_on: Engine.cell(Prefs.defaults.lyrics),
			lyric_size: Engine.cell(Prefs.defaults.lyric_size),

			## Whether the overlay shows every line (Read all) or follows the song.
			reading_all: Engine.cell(Bool.False),

			## The listener's own presets; the built-ins are `Library.builtins`.
			mine: Engine.cell([]),
			chosen: Engine.cell(Prefs.defaults.preset),

			## Which panel is open below the transport.
			panel: Engine.cell("Hide Panels"),
			editor: Engine.cell(Store.editing(Library.default)),

			## What the surface's shaders are doing: running, drawing the simple
			## fallback, or failing to compile.
			shader_status: Engine.cell(NoShader),

			## A preset file being imported, read on the page (`Editor.importing`).
			importing: Engine.cell(NotImporting),
			exporting: Engine.cell(NotExporting),

			## The file an export built, for the save panel (`Export.saving`).
			saving: Engine.cell(Engine.outbox({})),

			## The audio output playing (`Media.Status.output`), and the
			## picture's sync offset kept for each output calibrated.
			output: Engine.cell({ name: "", uid: "" }),
			offsets: Engine.cell(Prefs.defaults.offsets),

			## One line about the last thing that happened.
			notice: Engine.cell("Press Play for the default song, or drop your own songs here with their .lrc or .txt lyrics."),
		}.Engine.Cells,
	)

	## The store's cells, for views and decisions to read and write.
	cells = Store.store.cells()

	## The local storage keys: the listener's presets, and their other
	## choices. Every key the app uses is declared to the program
	## (`src/main.roc`).
	presets_key : Str
	presets_key = "presets"

	prefs_key : Str
	prefs_key = "prefs"

	## The store a launch starts with: the presets and choices saved last
	## time (`Player.saving` writes them), or none. A chosen preset that is
	## gone falls back to Scope.
	start : Engine.Boot -> Engine.Store(_, _)
	start = |boot| {
		mine = Library.from_storage(Engine.boot_storage(boot, Store.presets_key) ?? "")
		saved_prefs = Prefs.decode(Engine.boot_storage(boot, Store.prefs_key) ?? "")
		chosen = Library.find(mine, saved_prefs.preset) ?? Library.default
		Store.store
			.with_initial(Store.cells.mine, mine)
			.with_initial(Store.cells.chosen, chosen.id)
			.with_initial(Store.cells.editor, Store.editing(chosen))
			.with_initial(Store.cells.lyrics_on, saved_prefs.lyrics)
			.with_initial(Store.cells.lyric_size, saved_prefs.lyric_size)
			.with_initial(Store.cells.volume, saved_prefs.volume)
			.with_initial(Store.cells.eq, saved_prefs.eq)
			.with_initial(Store.cells.offsets, saved_prefs.offsets)
	}

	## The song queued at launch plays from `assets/`, with lyrics compiled
	## into the app. Its CC BY 4.0 credit is in `assets/CREDITS.md`.
	##
	## To ship without it, remove this value, `default_asset` and the
	## `default_lrc` import. Set `first_queue` to an empty queue and
	## `opening` to an empty list of commands. Update the expects and specs
	## that assume a bundled song. Remove the `.mp3` and `.lrc` files named
	## `assets/polymorphic-defunctionalization` and their credit.
	default : Track
	default = {
		file: Bundled(Store.default_asset),
		title: "Polymorphic Defunctionalization Through Lambda Set Specialization",
		lyrics: Loaded({ name: "polymorphic-defunctionalization.lrc", words: Lyrics.from_lrc(default_lrc) }),
	}

	## The default song's path in `assets/`.
	default_asset : Str
	default_asset = "polymorphic-defunctionalization.mp3"

	## The queue a launch starts with: the default song, current.
	first_queue : Queue(Track)
	first_queue = Queue.added(Queue.empty(), [Store.default]).queue

	## What the player is told when the window opens: to load the song the
	## queue starts with (`Media.session`'s `opening`).
	opening : List(Media.Command)
	opening = [Media.load(Queue.generation(Store.first_queue), Store.default.file)]

	## The writes that post `commands` to the player. Post at most once a
	## turn: a decision that sends several commands sends one list.
	send : List(Media.Command) -> List(Engine.Write(_))
	send = |commands| if (commands.is_empty()) [] else [Store.cells.media.update(|box| box.post(commands))]

	# ------------------------------------------------------------ the queue

	## Files a listener dropped or picked: songs join the queue, each with the
	## lyric file of the same name if there is exactly one, and those lyric
	## files are read. A lyric file given alone goes to the current song, as
	## Add lyrics… does. The notice counts what was added and what was not.
	received : Now, List(File), U64 -> List(Engine.Write(_))
	received = |{ queue, player }, files, refused_by_host| {
		paired = Pairing.pair(files.map(|f| f.name()))
		file_at = |i| files.get(i) ?? crash "Store.received: no file ${i.to_str()}"
		if paired.songs.is_empty() {
			match (paired.unpaired, Queue.current(queue)) {
				([only], Ok(current)) => Store.attached(current.id, file_at(only))
				_ => [Store.cells.notice.set(Store.nothing_added(paired.unpaired.len() + paired.others, refused_by_host))]
			}
		} else {
			arriving = paired.songs.map(
				|s| {
					song = file_at(s.song)
					partner =
						match s.lyrics {
							LyricsAt(i) => Ok(file_at(i))
							NoLyrics => Err(NoLyrics)
						}
					{ track: { file: Picked(song), title: Pairing.title(song.name()), lyrics: Store.reading_state(partner) }, partner }
				},
			)
			{ queue: grown, refused } = Queue.added(queue, arriving.map(|a| a.track))
			fresh = Queue.entries(grown).drop_first(Queue.len(queue))
			reads = List.map2(fresh, arriving, |entry, a| a.partner.map_ok(|file| { entry: entry.id, file })).keep_oks(|r| r)
			[
				Store.cells.queue.set(grown),
				Store.cells.reads.update(|held| held.concat(reads)),
				Store.cells.notice.set(Store.added_text(fresh.len(), reads.len(), refused + refused_by_host, paired.others + paired.unpaired.len())),
			].concat(Store.moved(queue, grown, player))
		}
	}

	## A new song's words: being read from its lyric file, or none.
	reading_state : Try(File, [NoLyrics]) -> LyricState
	reading_state = |partner|
		match partner {
			Ok(file) => Reading(file.name())
			Err(NoLyrics) => NoLyrics
		}

	## A lyric file for the queue entry `entry`, from Add lyrics… or given
	## alone: it replaces the entry's words once it is read.
	attached : U64, File -> List(Engine.Write(_))
	attached = |entry, file|
		match Pairing.kind(file.name()) {
			LyricFile => [
				Store.cells.queue.update(|q| Queue.changed(q, entry, |t| { ..t, lyrics: Reading(file.name()) })),
				Store.cells.reads.update(|held| held.drop_if(|r| r.entry == entry).append({ entry, file })),
				Store.cells.notice.set("Reading ${file.name()}…"),
			]
			_ => [Store.cells.notice.set("${file.name()} is not a lyric file: choose a .lrc or .txt file.")]
		}

	## Add lyrics… for the current song.
	added_lyrics : Queue(Track), List(File) -> List(Engine.Write(_))
	added_lyrics = |queue, files|
		match (Queue.current(queue), files.first()) {
			(Ok(current), Ok(file)) => Store.attached(current.id, file)
			_ => []
		}

	## What reading a lyric file came to. The words go to the entry they were
	## read for, which may no longer be current, or may be gone (then they
	## are dropped): words never land on another song.
	lyrics_read : LyricRead, Try(Str, _) -> List(Engine.Write(_))
	lyrics_read = |read, answer| {
		name = read.file.name()
		state =
			match answer {
				Ok(text) => Loaded({ name, words: Lyrics.from_file(name, text) })
				Err(why) => Unreadable({ name, why: Store.read_problem(why) })
			}
		notice =
			match state {
				Loaded({ words: NoWords, .. }) => "${name} has no words."
				Loaded({ words: Plain(_), .. }) if name.with_ascii_lowercased().ends_with(".lrc") => "${name} has no usable timing, so its words are shown as text."
				Loaded(_) => "Read the words of ${name}."
				Unreadable({ why, .. }) => "Could not read ${name}: ${why}."
				_ => ""
			}
		[
			Store.cells.queue.update(|q| Queue.changed(q, read.entry, |t| if (t.lyrics == Reading(name)) { ..t, lyrics: state } else t)),
			Store.cells.reads.update(|held| held.drop_if(|r| r.entry == read.entry and r.file == read.file)),
			Store.cells.notice.set(notice),
		]
	}

	## Why a file read failed, for people.
	read_problem : _ -> Str
	read_problem = |why|
		match why {
			FileFailed(TooLarge) => "it is too large for a lyric file"
			FileFailed(_) => "the file could not be read"
			_ => "it is not UTF-8 text"
		}

	## The current song changed (or the queue emptied): reset the position
	## and tell the player to load the new song, its `track` the queue's new
	## generation, or to stop. A load stops at the start of the song, so a
	## player that was playing is told to play it.
	moved : Queue(Track), Queue(Track), Media.Player -> List(Engine.Write(_))
	moved = |before, after, player|
		if Queue.generation(before) == Queue.generation(after) {
			[]
		} else {
			match Queue.current(after) {
				Ok(entry) => [
					Store.cells.player.set({ ..player, position_ms: 0, duration_ms: 0, generation: Queue.generation(after), status: if (player.status == Playing) Playing else Stopped }),
					Store.cells.reading_all.set(Bool.False),
				].concat(Store.send([Media.load(Queue.generation(after), entry.track.file)].concat(if (player.status == Playing) [Play] else [])))
				Err(_) => [Store.cells.player.set({ ..Media.stopped, generation: Queue.generation(after), reset: player.reset })].concat(Store.send([Stop]))
			}
		}

	## A queue move: the queue after it, then the load.
	queue_moved : Now, (Queue(Track) -> Queue(Track)) -> List(Engine.Write(_))
	queue_moved = |now, move| {
		after = move(now.queue)
		[Store.cells.queue.set(after)].concat(Store.moved(now.queue, after, now.player))
	}

	next : Now -> List(Engine.Write(_))
	next = |now| Store.queue_moved(now, Queue.next)

	previous : Now -> List(Engine.Write(_))
	previous = |now| Store.queue_moved(now, Queue.previous)

	selected : Now, U64 -> List(Engine.Write(_))
	selected = |now, id| Store.queue_moved(now, |q| Queue.select(q, id))

	removed : Now, U64 -> List(Engine.Write(_))
	removed = |now, id| [Store.cells.reads.update(|held| held.drop_if(|r| r.entry == id))].concat(Store.queue_moved(now, |q| Queue.removed(q, id)))

	cleared : Now -> List(Engine.Write(_))
	cleared = |now| [Store.cells.reads.set([]), Store.cells.notice.set("Cleared the queue.")].concat(Store.queue_moved(now, Queue.cleared))

	added_text : U64, U64, U64, U64 -> Str
	added_text = |songs, with_lyrics, refused, others| {
		lyric_part = if (with_lyrics == 0) "" else ", ${with_lyrics.to_str()} with lyrics"
		refused_part = if (refused == 0) "" else "; ${Store.counted(refused, "song")} did not fit (the queue holds ${Queue.most.to_str()})"
		other_part = if (others == 0) "" else "; ${Store.counted(others, "file")} left out"
		"Added ${Store.counted(songs, "song")}${lyric_part}${refused_part}${other_part}."
	}

	nothing_added : U64, U64 -> Str
	nothing_added = |others, refused| if (refused > 0) "No songs were added: ${Store.counted(refused, "file")} did not fit." else if (others > 0) "No songs were added: ${Store.counted(others, "file")} are not songs, or are lyrics with no song playing." else "No songs were added."

	counted : U64, Str -> Str
	counted = |n, noun| if (n == 1) "1 ${noun}" else "${n.to_str()} ${noun}s"

	# ------------------------------------------------------------ the player

	## Play, or resume after a pause; nothing to play does nothing.
	played : Queue(Track), Media.Player -> List(Engine.Write(_))
	played = |queue, p|
		if Queue.current(queue).is_err() or p.status == Playing {
			[]
		} else {
			[Store.cells.player.set({ ..p, status: Playing })].concat(Store.send([if (p.status == Paused) Resume else Play]))
		}

	paused : Media.Player -> List(Engine.Write(_))
	paused = |p| if (p.status == Playing) [Store.cells.player.set({ ..p, status: Paused })].concat(Store.send([Pause])) else []

	## Play or pause, as the one button does.
	play_pause : Queue(Track), Media.Player -> List(Engine.Write(_))
	play_pause = |queue, p| if (p.status == Playing) Store.paused(p) else Store.played(queue, p)

	stopped : Media.Player -> List(Engine.Write(_))
	stopped = |p| if (p.status == Stopped and p.position_ms == 0) [] else [Store.cells.player.set({ ..p, status: Stopped, position_ms: 0 })].concat(Store.send([Stop]))

	## A seek to `ms`, within the song once its length is known. Pausing
	## holds the position; a seek while paused stays paused.
	seeked : Media.Player, U64 -> List(Engine.Write(_))
	seeked = |p, ms| {
		target = if (p.duration_ms > 0) ms.min(p.duration_ms) else ms
		if (p.generation == 0) [] else [Store.cells.player.set({ ..p, position_ms: target })].concat(Store.send([Seek(target)]))
	}

	## A seek by `delta_ms` from where the player is, as the arrow keys do.
	nudged : Media.Player, I64 -> List(Engine.Write(_))
	nudged = |p, delta_ms| {
		target = if (delta_ms < 0) p.position_ms - p.position_ms.min((-delta_ms).to_u64_wrap()) else p.position_ms + delta_ms.to_u64_wrap()
		Store.seeked(p, target)
	}

	## The seek slider's per-mille of the song.
	sought : Media.Player, Str -> List(Engine.Write(_))
	sought = |p, typed| Store.seeked(p, p.duration_ms * (U64.from_str(typed) ?? 0) // 1000)

	volume_set : Str -> List(Engine.Write(_))
	volume_set = |typed| {
		v = (I64.from_str(typed) ?? 100).max(0).min(100)
		[Store.cells.volume.set(v)].concat(Store.send([Media.volume(v)]))
	}

	## What the player and queue are, for a decision that needs both.
	Now : { queue : Queue(Track), player : Media.Player }

	## The queue and the player together, for a handler's decision.
	queue_and_player : () -> Signal(ctx, Now)
		where [ctx.store : () -> Engine.Reach(ctx, _)]
	queue_and_player = || { queue: Store.cells.queue.signal(), player: Store.cells.player.signal() }.Signal.map(|both| both)

	## What the player reported. Each event names its song by `track`, the
	## queue's generation it was loaded at; an event about another song
	## changes nothing, and the end of the current one moves the queue on.
	heard : Now, Media.Event -> List(Engine.Write(_))
	heard = |{ queue, player }, event|
		match event {
			Loaded({ track, duration_ms, .. }) if track == player.generation => [Store.cells.player.set({ ..player, duration_ms })]
			Ended({ track }) =>
				match Queue.ended(queue, track) {
					Advanced(after) => [Store.cells.queue.set(after)].concat(Store.moved(queue, after, player))
					Finished => [Store.cells.player.set({ ..player, status: Stopped, position_ms: 0 }), Store.cells.notice.set("The queue has finished.")]
					Stale => []
				}
			Failed({ track, error }) if track == player.generation => [Store.cells.player.set({ ..player, status: Stopped }), Store.cells.notice.set("The song could not be played: ${Store.media_problem(error)}.")]
			_ => []
		}

	media_problem : Media.Error -> Str
	media_problem = |error|
		match error {
			Unsupported(why) => "its format is not supported (${why})"
			Corrupt(why) => "the file is damaged (${why})"
			Output(why) => "the sound output did not start (${why})"
		}

	## Where the player says playback stands. A status about another song
	## changes nothing; one about the current song moves the playhead (and
	## the lyrics with it), learns its length, and keeps the session's
	## generation for the picture's `reset`.
	followed : Now, Media.Status -> List(Engine.Write(_))
	followed = |{ queue: _, player }, status|
		if status.track != player.generation or player.generation == 0 {
			[]
		} else {
			phase =
				match status.state {
					Playing => Playing
					Paused => Paused
					Stopped => Stopped
					Ended => Stopped
					# Opening a song: what the app asked for stands until it plays.
					Idle => player.status
					Loading => player.status
				}
			[Store.cells.player.set({ ..player, status: phase, position_ms: status.position_ms, duration_ms: if (status.duration_ms > 0) status.duration_ms else player.duration_ms, reset: status.generation })]
		}

	# ------------------------------------------------------------ picture sync

	## What picture sync reads: the output playing and the offsets kept.
	Sync : { output : Media.Output, offsets : List(Prefs.Offset) }

	## A status names the output playing: it is kept, and when the offset
	## the player applies is not the one kept for that output (a new
	## launch, or another output chosen in Sound settings), the kept one is
	## sent.
	output_heard : Sync, Media.Status -> List(Engine.Write(_))
	output_heard = |{ output, offsets }, status| {
		want = Prefs.offset_for(offsets, status.output.uid).to_f32()
		kept = if (status.output == output) [] else [Store.cells.output.set(status.output)]
		off = status.visual_offset_ms - want
		kept.concat(if (status.output.uid.is_empty() or (off < 0.5 and off > -0.5)) [] else Store.send([VisualOffset(want)]))
	}

	## The offset slider moved: kept for the output playing, and applied.
	offset_set : Sync, Str -> List(Engine.Write(_))
	offset_set = |{ output, offsets }, typed| {
		kept = Prefs.with_offset(offsets, output.uid, I64.from_str(typed) ?? 0)
		[Store.cells.offsets.set(kept)].concat(Store.send([VisualOffset(Prefs.offset_for(kept, output.uid).to_f32())]))
	}

	## The Sync Test: its click track joins the queue and plays, under the
	## Sync Test preset.
	sync_test : Now, List(Preset.Doc) -> List(Engine.Write(_))
	sync_test = |{ queue, player }, mine| {
		{ queue: grown, refused: _ } = Queue.added(queue, [Store.sync_track])
		after = match Queue.entries(grown).last() {
			Ok(entry) => Queue.select(grown, entry.id)
			Err(_) => grown
		}
		[Store.cells.queue.set(after)]
			.concat(Store.chose(mine, Library.sync_test.id))
			.concat(Store.moved(queue, after, { ..player, status: Playing }))
	}

	## The Sync Test's track: a click every half second (`assets/sync-test.wav`).
	sync_track : Track
	sync_track = { file: Bundled("sync-test.wav"), title: "Sync Test", lyrics: NoLyrics }

	# ------------------------------------------------------------ the EQ

	eq_changed : Eq.Settings -> List(Engine.Write(_))
	eq_changed = |settings| [Store.cells.eq.set(settings)].concat(Store.send(Media.equalize(settings)))

	## A band's slider.
	band_set : Eq.Settings, U64, Str -> List(Engine.Write(_))
	band_set = |settings, band, typed| Store.eq_changed(Eq.with_band(settings, band, I64.from_str(typed) ?? 0))

	preamp_set : Eq.Settings, Str -> List(Engine.Write(_))
	preamp_set = |settings, typed| Store.eq_changed(Eq.with_preamp(settings, I64.from_str(typed) ?? 0))

	# ------------------------------------------------------------ lyrics

	## Lyrics on or off. The choice belongs to the player: it lasts across
	## songs, presets and launches.
	toggled_lyrics : Bool -> List(Engine.Write(_))
	toggled_lyrics = |on| [Store.cells.lyrics_on.set(!on), Store.cells.reading_all.set(Bool.False)]

	## What the overlay shows for the current song at the player's position:
	## nothing, the current and next lines, every line of timed words (Read
	## all), or plain words.
	Overlay : [Clear, Following(Lyrics.Shown), ReadingAll(List(Str)), Text(List(Str))]

	overlay : { queue : Queue(Track), player : Media.Player, on : Bool, all : Bool } -> Overlay
	overlay = |{ queue, player, on, all }|
		match (on, Queue.current(queue).map_ok(|e| e.track.lyrics)) {
			(Bool.True, Ok(Loaded({ words: Timed(cues), .. }))) => if (all) ReadingAll(Lyrics.all_lines(Timed(cues))) else Following(Lyrics.shown(cues, player.position_ms))
			(Bool.True, Ok(Loaded({ words: Plain(verses), .. }))) => Text(Lyrics.all_lines(Plain(verses)))
			_ => Clear
		}

	## The next time the shown line changes, for `Media.boundary`.
	boundary : { queue : Queue(Track), player : Media.Player, on : Bool } -> [None, At(U64)]
	boundary = |{ queue, player, on }|
		match (on, Queue.current(queue).map_ok(|e| e.track.lyrics)) {
			(Bool.True, Ok(Loaded({ words: Timed(cues), .. }))) =>
				match Lyrics.next_boundary(cues, player.position_ms) {
					Ok(ms) => At(ms)
					Err(NoMore) => None
				}
			_ => None
		}

	# ------------------------------------------------------------ presets

	## The editor opened on a preset: its draft, its file and its name.
	editing : Preset.Doc -> Editor
	editing = |preset| { draft: preset, text: Preset.encode(preset), problems: [], name: preset.name }

	## The preset the visualization shows: the editor's draft while the
	## editor is open, so every edit is seen as it is made; otherwise the
	## chosen one.
	shown : { mine : List(Preset.Doc), chosen : Str, editor : Editor, panel : Str } -> Preset.Doc
	shown = |{ mine, chosen, editor, panel }| if (panel == "Editor") editor.draft else Library.find(mine, chosen) ?? Library.default

	## The scene the visualization draws.
	drawing : { mine : List(Preset.Doc), chosen : Str, editor : Editor, panel : Str } -> Scene.Drawing
	drawing = |state| Scene.of(Store.shown(state))

	## What the surface said its shaders are doing. A stage that does not
	## compile is named, with its line and message, in the notice; the
	## surface goes on drawing that stage's last good source.
	shader_heard : Ui.ShaderStatus -> List(Engine.Write(_))
	shader_heard = |status|
		match status {
			Failed(errors) => [Store.cells.shader_status.set(status), Store.cells.notice.set(Store.shader_problem(errors))]
			_ => [Store.cells.shader_status.set(status)]
		}

	## A shader's compile errors in a line: the first, and how many more.
	shader_problem : List(Ui.ShaderError) -> Str
	shader_problem = |errors|
		match errors {
			[] => "The shader does not compile."
			[first, .. as rest] => {
				more = if (rest.is_empty()) "" else " (and ${Store.counted(rest.len(), "more error")})"
				"The ${Store.shader_place(first)}: ${first.message}${more}. The last good shader goes on drawing."
			}
		}

	## Where a shader error is: `warp, line 3`.
	shader_place : Ui.ShaderError -> Str
	shader_place = |e| {
		stage =
			match e.stage {
				Warp => "warp"
				Composite => "composite"
			}
		if (e.line == 0) stage else "${stage}, line ${e.line.to_str()}"
	}

	## Choosing a preset from the list: the editor follows, so it always
	## edits what is chosen.
	chose : List(Preset.Doc), Str -> List(Engine.Write(_))
	chose = |mine, id|
		match Library.find(mine, id) {
			Ok(preset) => [Store.cells.chosen.set(preset.id), Store.cells.editor.set(Store.editing(preset))]
			Err(_) => []
		}

	## The listener edited the preset's file. Text that is a valid preset
	## becomes the draft at once; otherwise its problems are shown, field by
	## field, and the draft stays the last valid preset.
	edited_text : Editor, Str -> List(Engine.Write(_))
	edited_text = |editor, typed|
		match Preset.decode(typed) {
			Ok(preset) => [Store.cells.editor.set({ ..editor, draft: preset, text: typed, problems: [] })]
			Err(found) => [Store.cells.editor.set({ ..editor, text: typed, problems: found })]
		}

	## A change made with the editor's controls, which keep every value in
	## range: the draft changes and its file is written afresh.
	edited : Editor, (Preset.Doc -> Preset.Doc) -> List(Engine.Write(_))
	edited = |editor, change| {
		draft = change(editor.draft)
		match Preset.problems(draft) {
			[] => [Store.cells.editor.set({ ..editor, draft, text: Preset.encode(draft), problems: [] })]
			found => [Store.cells.editor.set({ ..editor, problems: found })]
		}
	}

	named_as : Editor, Str -> List(Engine.Write(_))
	named_as = |editor, typed| [Store.cells.editor.set({ ..editor, name: typed })]

	## New: a blank preset in the editor, not yet saved.
	started_new : List(Engine.Write(_))
	started_new = [Store.cells.editor.set(Store.editing(Library.blank)), Store.cells.notice.set("A new preset: add a layer, then Save As.")]

	## Save As: the draft saved under the editor's name, and chosen.
	saved : List(Preset.Doc), Editor -> List(Engine.Write(_))
	saved = |mine, editor|
		match Library.saved_as(mine, editor.draft, editor.name) {
			Ok({ mine: kept, saved: preset }) => [Store.cells.mine.set(kept), Store.cells.chosen.set(preset.id), Store.cells.editor.set(Store.editing(preset)), Store.cells.notice.set("Saved ${preset.name}.")]
			Err(NeedsName) => [Store.cells.editor.set({ ..editor, problems: [{ field: "name", problem: "needs a name" }] })]
			Err(BuiltinName) => [Store.cells.editor.set({ ..editor, problems: [{ field: "name", problem: "is a built-in preset's; choose another" }] })]
		}

	## Duplicate: a copy of the draft, saved and chosen.
	duplicated : List(Preset.Doc), Editor -> List(Engine.Write(_))
	duplicated = |mine, editor| {
		{ mine: kept, saved: copy } = Library.duplicated(mine, editor.draft)
		[Store.cells.mine.set(kept), Store.cells.chosen.set(copy.id), Store.cells.editor.set(Store.editing(copy)), Store.cells.notice.set("Saved ${copy.name}.")]
	}

	## Delete: one of the listener's presets goes, and Scope is chosen.
	deleted : List(Preset.Doc), Str -> List(Engine.Write(_))
	deleted = |mine, id|
		if Library.is_builtin(id) {
			[Store.cells.notice.set("Built-in presets cannot be deleted.")]
		} else {
			[Store.cells.mine.set(Library.removed(mine, id)), Store.cells.chosen.set(Library.default.id), Store.cells.editor.set(Store.editing(Library.default)), Store.cells.notice.set("Deleted the preset.")]
		}

	## A preset file chosen to import: it is read (`Editor.importing`).
	import_chosen : List(File) -> List(Engine.Write(_))
	import_chosen = |files|
		match files.first() {
			Ok(file) => [Store.cells.importing.set(ImportReading(file)), Store.cells.notice.set("Importing ${file.name()}…")]
			Err(_) => []
		}

	## What importing came to: a valid preset is saved under its own name and
	## chosen; otherwise the editor shows what needs attention and the
	## preset shown stays as it was.
	imported : List(Preset.Doc), Editor, Str, Try(Str, _) -> List(Engine.Write(_))
	imported = |mine, editor, name, answer| {
		done = Store.cells.importing.set(NotImporting)
		match answer {
			Err(why) => [done, Store.cells.notice.set("Could not import ${name}: ${Store.read_problem(why)}.")]
			Ok(text) =>
				match Preset.decode(text) {
					Err(found) => [done, Store.cells.editor.set({ ..editor, text, problems: found }), Store.cells.panel.set("Editor"), Store.cells.notice.set("${name} needs attention before it can be imported.")]
					Ok(preset) =>
						match Library.saved_as(mine, preset, preset.name) {
							Ok({ mine: kept, saved: added }) => [done, Store.cells.mine.set(kept), Store.cells.chosen.set(added.id), Store.cells.editor.set(Store.editing(added)), Store.cells.notice.set("Imported ${added.name}.")]
							Err(_) => [done, Store.cells.notice.set("${name} has a built-in preset's name; rename it in the file first.")]
						}
				}
		}
	}

	## Export…: a worker builds the draft's file (`Export`).
	export_asked : Exporting, Editor -> List(Engine.Write(_))
	export_asked = |exporting, editor| {
		serial =
			match exporting {
				Building(job) => job.serial + 1
				NotExporting => 1
			}
		[Store.cells.exporting.set(Building({ name: editor.draft.name, text: Preset.encode(editor.draft), serial })), Store.cells.notice.set("Exporting ${editor.draft.name}…")]
	}

	## What the export worker built: the file, offered to the save panel.
	exported : Try(File, _) -> List(Engine.Write(_))
	exported = |answer|
		match answer {
			Ok(file) => [Store.cells.saving.update(|box| box.post(file)), Store.cells.notice.set("Exported ${file.name()}.")]
			Err(_) => [Store.cells.notice.set("The preset could not be exported.")]
		}

	## The listener's choices, as `Prefs` saves them.
	prefs : { lyrics : Bool, lyric_size : Prefs.LyricSize, chosen : Str, volume : I64, eq : Eq.Settings, offsets : List(Prefs.Offset) } -> Prefs.Choices
	prefs = |s| { lyrics: s.lyrics, lyric_size: s.lyric_size, preset: s.chosen, volume: s.volume, eq: s.eq, offsets: s.offsets }
}

## A song and its lyric file dropped together: the song is queued and
## current, its lyric file waits to be read, and the player is told to load
## the song.
expect {
	# Files are host handles, so the window's recorded cases cover dropping
	# real ones; here the pairing and its notice are checked.
	Store.added_text(2, 1, 0, 0) == "Added 2 songs, 1 with lyrics." and Store.added_text(1, 0, 3, 1) == "Added 1 song; 3 songs did not fit (the queue holds 60); 1 file left out."
}

## Lyrics start off; the toggle turns them on and back to following.
expect {
	after = Store.store.after(Store.toggled_lyrics(Bool.False))
	after.read(Store.cells.lyrics_on) and !after.read(Store.cells.reading_all)
}

## Before a song is loaded, play and seek do nothing.
expect Store.played(Queue.empty(), Media.stopped).is_empty() and Store.seeked(Media.stopped, 5_000).is_empty()

## A seek is clamped to a known length, and a nudge stops at the start.
expect {
	p = { ..Media.stopped, status: Paused, generation: 1, position_ms: 3_000, duration_ms: 20_000 }
	Store.store.after(Store.seeked(p, 90_000)).read(Store.cells.player) == { ..p, position_ms: 20_000 }
		and Store.store.after(Store.nudged(p, -5_000)).read(Store.cells.player) == { ..p, position_ms: 0 }
		and Store.store.after(Store.nudged(p, 5_000)).read(Store.cells.player).status == Paused
}

## A status about an older song is ignored; one about the current song
## moves the playhead, learns the length and keeps the session's
## generation; an end of an older song is stale.
expect {
	p = { ..Media.stopped, status: Playing, generation: 2 }
	state = { queue: Queue.empty(), player: p }
	Store.followed(state, Media.status_at({ ..p, generation: 1 }, 9_000)).is_empty()
		and Store.store.after(Store.followed(state, { ..Media.status_at(p, 9_000), duration_ms: 22_000, generation: 7 })).read(Store.cells.player) == { ..p, position_ms: 9_000, duration_ms: 22_000, reset: 7 }
		and Store.heard(state, Ended({ track: 1 })).is_empty()
		and Store.store.after(Store.heard(state, Loaded({ track: 2, duration_ms: 22_000, frames: 88_000, sample_rate: 4_000, channels: 1 }))).read(Store.cells.player).duration_ms == 22_000
}

## EQ sliders scale to tenths of a dB and post every gain, the preamp and
## bypass to the player.
expect {
	after = Store.store.after(Store.band_set(Eq.flat, 2, "-45"))
	after.read(Store.cells.eq).bands.get(2) == Ok(-45) and after.read(Store.cells.media).last() == Posted(Media.equalize(Eq.with_band(Eq.flat, 2, -45)))
}

## Ember Tunnel, edited as text from blank and saved: chosen, and kept in
## the listener's presets; choosing Scope then Ember Tunnel restores it.
expect {
	after_text = Store.store.after(Store.started_new).after(Store.edited_text(Store.editing(Library.blank), Preset.encode({ ..Library.ember_tunnel, id: Library.blank.id, name: Library.blank.name })))
	editor = { ..after_text.read(Store.cells.editor), name: "Ember Tunnel" }
	saved = after_text.after(Store.saved([], editor))
	mine = saved.read(Store.cells.mine)
	round_trip = saved.after(Store.chose(mine, Library.scope.id)).after(Store.chose(mine, Library.ember_tunnel.id))
	mine == [Library.ember_tunnel]
		and saved.read(Store.cells.chosen) == "user.ember-tunnel"
		and round_trip.read(Store.cells.editor).draft == Library.ember_tunnel
		and Store.shown({ mine, chosen: round_trip.read(Store.cells.chosen), editor: round_trip.read(Store.cells.editor), panel: "Hide Panels" }) == Library.ember_tunnel
}

## A preset file with a field out of range keeps the last valid draft and
## says which field needs attention.
expect {
	editor = Store.editing(Library.scope)
	broken = Preset.encode({ ..Library.scope, layers: Library.scope.layers.map(|l| { ..l, size: 1200 }) })
	after = Store.store.after(Store.edited_text(editor, broken)).read(Store.cells.editor)
	after.draft == Library.scope and after.text == broken and after.problems == [{ field: "layers[0].size", problem: "must be between 0 and 1000" }]
}

## A built-in cannot be deleted, nor its name taken.
expect {
	Store.store.after(Store.deleted([], Library.scope.id)).read(Store.cells.notice) == "Built-in presets cannot be deleted."
		and Store.store.after(Store.saved([], { ..Store.editing(Library.blank), name: "Scope" })).read(Store.cells.editor).problems.len() == 1
}

## A launch starts with the default song queued and current, its timed
## lyrics read, and the player told to load it from the assets.
expect {
	cues =
		match Store.default.lyrics {
			Loaded({ words: Timed(found), .. }) => found
			_ => []
		}
	Queue.len(Store.first_queue) == 1
		and Queue.current(Store.first_queue).map_ok(|e| e.track.title) == Ok(Store.default.title)
		and cues.len() == 45
		and Lyrics.shown(cues, 6_000).now == ["The Roc on the kick has a crack in its beak."]
		and Store.opening == [LoadAsset({ track: 1, path: "polymorphic-defunctionalization.mp3" })]
}

## A status from another output sends the offset kept for it; one that
## already applies it sends nothing.
expect {
	speakers = { name: "MacBook Air Speakers", uid: "BuiltIn" }
	status = { ..Media.status_at(Media.stopped, 0), output: speakers }
	offsets = [{ output: "BuiltIn", ms: 20 }]
	heard = Store.store.after(Store.output_heard({ output: { name: "", uid: "" }, offsets }, status))
	again = Store.output_heard({ output: speakers, offsets }, { ..status, visual_offset_ms: 20 })
	heard.read(Store.cells.output) == speakers and heard.read(Store.cells.media).last() == Posted([VisualOffset(20)]) and again.len() == 0
}
