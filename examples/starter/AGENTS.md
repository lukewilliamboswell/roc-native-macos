# Working on this app

A native macOS app written in [Roc](https://www.roc-lang.org) on
[roc-native-macos](https://github.com/lukewilliamboswell/roc-native-macos),
whose views are real AppKit controls driven by the
[roc-signals](https://lukewilliamboswell.github.io/roc-signals/docs/guide/)
reactive engine. It starts as a music player with a visualizer and lyrics:
drop songs with their `.lrc` or `.txt` lyrics into the window, choose a
preset, press Play, and turn on Lyrics (Command-L) to follow the words over
the picture. Keep its structure and change its subject as you like. Every
module opens with a `##` comment saying what belongs in it: read that
before changing the module.

## About the default song

The queue starts with one song, so the app plays something before anyone
gives it a file: *Polymorphic Defunctionalization Through Lambda Set
Specialization* by Luke Boswell, a prog-metal song about the PLDI 2023
paper [Better Defunctionalization through Lambda Set
Specialization](https://doi.org/10.1145/3591260), the research behind how
Roc compiles closures. It is licensed under CC BY 4.0, not under the app's
own licence: keep `assets/CREDITS.md` with it. Its lyrics and liner notes
are at
<https://gist.github.com/lukewilliamboswell/be88b49154f602495f2821a01f995d1f>.

`assets/polymorphic-defunctionalization.mp3` is the song and
`assets/polymorphic-defunctionalization.lrc` its timed lyrics, which
`src/Store.roc` compiles in (`Store.default`): the song gist's own files. The player loads the
song from `assets/` (`Media.LoadAsset`) rather than from a file the
listener picked. To ship without it, delete the two files and
`Store.default`, and start the queue empty.

## Commands

Run them from this directory. They need Roc on PATH as `roc`.

| Command | What it does |
|---|---|
| `roc macos.roc dev` | start the app with hot reloading; save, then press Command-R in the app |
| `roc macos.roc run` | build `<name>.app` and start it, its output here |
| `roc test src/main.roc` | the `expect` tests alone, of `src/` and `logic/`: fast, on any system |
| `roc macos.roc test` | the `expect` tests, then the specs in `specs/` |
| `roc macos.roc test --update` | rewrite the specs' dumps and lower their allocation bounds; review the diff |
| `roc macos.roc test --metrics` | print each spec's allocations and work, to set a bound |
| `roc macos.roc fuzz` | build `fuzz/main.roc` and fuzz each target for 10 seconds |
| `roc macos.roc fuzz --check` | only each target's declared examples, as CI does |
| `roc macos.roc fuzz lrc-parse --time 120` | one target, for longer |
| `roc fmt src logic fuzz` | format the sources (`roc fmt --check ...` to check) |
| `roc macos.roc build`, `package` | the `.app`, and `dist/<name>-<version>.zip` to share |

`roc macos.roc COMMAND --help` describes a command. The app runs, and
`dev`, `run` and the specs work, only on an Apple silicon Mac;
`build`, `package` and `roc test` work anywhere, and `fuzz` on Apple
silicon and Linux x64. Before you finish a change, run `roc fmt src logic
fuzz`, `roc macos.roc test` and `roc macos.roc fuzz --check`.

## Layout

```
src/main.roc       the program: store, window and workers; its header names the platform and logic/
src/Store.roc      shared state (the store's cells) and every decision that changes it, with expects
src/Player.roc     the window: composes the store, the panels and the effect sites
src/Words.roc      the lyrics over the picture, the lyric-file reader and the next-line timer
src/Panels.roc     the queue and EQ panels
src/Editor.roc     the preset editor panel, and importing a preset
src/Widgets.roc    reusable widgets with local state, which never import Store
src/Export.roc     a worker task that builds a preset's file, and the save panel
src/Media.roc      the audio session (`pf.Audio`): commands out, events and status in
src/Visual.roc     the drawing surface (`Ui.surface` under `Ui.overlay`): a scene in, a picture out
logic/main.roc     the logic package's header: its modules, pure Roc with no platform
logic/Lyrics.roc   LRC and plain-text lyrics, and the line at a position
logic/Pairing.roc  songs and lyric files given together, paired by name
logic/Queue.roc    the play queue, its generations and its room
logic/Eq.roc       the EQ's settings in tenths of a dB
logic/Preset.roc   the versioned preset document, its JSON file and its checks
logic/Library.roc  the built-in presets, Ember Tunnel, palettes, and saving presets
logic/Scene.roc    what a preset draws, as the drawing surface takes it
logic/Prefs.roc    the listener's choices kept between launches
logic/JsonValue.roc JSON text and values
fuzz/main.roc      roc-fuzz targets for logic/: a development program, not part of the app
assets/icon.png    the app's icon, also drawn in the window (Ui.asset_image("icon.png", ...))
assets/polymorphic-defunctionalization.*  the default song (.mp3) and its timed lyrics (.lrc)
assets/CREDITS.md  the default song's credit and licence (CC BY 4.0)
specs/*.scm        specs: steps that drive the app's real controls, and what it then shows
specs/fixtures/    the songs, lyrics and preset files the specs use
macos.json         the app's name, bundle identifier and version
```

Generated and ignored: `.macos/` (builds), `<name>.app`, `dist/`, `.roc-fuzz/`.

## What Roc owns, and what the host owns

Roc owns the queue, the controls and what they mean, the preset documents
and the lyrics. The Swift host owns decoding, the EQ's audio processing,
the audio clock, the sound analysis and the drawing. Two kinds of input
reach the window independently: sound measurements move the picture, and
the playback position picks the lyric line.

Two modules are the only ones that speak to the host's media and
drawing, so the rest of the app never changes when those do:

- `src/Media.roc`, the audio session, with the platform's `Audio` types.
  Decisions post `Media.Command`s (`Load`, `Play`, `Resume`, `Pause`,
  `Stop`, `Seek`, `Volume`, `Gain`, `Preamp`, `Bypass`, ...) to the store's
  `media` outbox with `Store.send`, and `Media.session` sends them. The
  player's `Media.Event`s (`Loaded`, `Ended`, `Failed`) come back to
  `Store.heard`, and its `Media.Status` (where playback stands, five times
  a second while playing) to `Store.followed`, which moves the playhead
  and so the lyrics. A load names its song by `track`, the queue's
  generation when it was chosen (`logic/Queue.roc`), and every event and
  status carries it, so one about an older song (a late end, a late
  position) changes nothing.
- `src/Visual.roc`, the drawing surface. It is handed a `Scene.Drawing`
  (`logic/Scene.roc` makes one from a preset) and the words to show over
  it. `Scene.marks` turns a drawing into the surface's ordered marks, in
  the surface's own shapes (`Wave`, `Ring`, `Bars`, `Oval`), with moving
  values bound to native data sources by name (`audio.waveform`,
  `audio.bands`, `audio.level`, `audio.bass`, ...), so the host animates
  the picture each display refresh without Roc running. The words sit in
  the overlay's foreground, so they never enter the picture's trails.

`Media.measuring` also holds the session's measurements on while a song
plays (an `Audio.analysis` subscription whose answers are ignored), so the
surface's sources are fed even on a spec's manual audio clock, where the
surface's own hold is not counted.

## How state flows

A view runs once, when the window opens. An event runs a handler, which
returns writes; the engine applies them and wakes only the views that read
what changed. So:

- State more than one part of the window shares lives in the store
  (`Store.roc`): the queue, the player, the EQ, the preset library, the
  editor's draft, the lyrics choice. It changes only through decisions:
  pure functions that return writes (`Store.received`, `Store.seeked`,
  `Store.saved`), tested with `Store.store.after(writes).read(cell)`.
- State one piece of the view cares about is local to it, in
  `Engine.state(initial, |s| ...)`: whether a `Widgets.section` is folded,
  whether a `Widgets.confirm_button` is asking. It starts again when that
  piece is rebuilt.
- A value that follows from state is not state: `signal.map(...)`, or
  `Engine.derive` when it is costly or read in several places (the scene,
  in `Player.view`; the lyric overlay, in `Words.overlay`).
- Effects (reading a lyric file, saving, a worker job, a player command)
  are asked for by sites that watch a signal (`Engine.watch_latest`,
  `Engine.watch_changes`, `Engine.on_post`), and their answers come back as
  writes (`Engine.react`).
- Rules that need no window go in `logic/`, where they are tested with
  `expect` and fuzzed. `src/` imports `logic`; never the other way round.

Some rules the player keeps, each in one place:

- The lyrics choice belongs to the player: it survives changing song,
  switching or importing a preset, and launches (`logic/Prefs.roc`).
- A lyric file is read for one queue entry (`Store.LyricRead`), and its
  words land on that entry only, so a read that finishes after the
  listener moved on never shows on another song.
- The line shown follows the playback position alone (`Store.overlay`), and
  `Media.boundary` sets a timer for the next line, so lines change on time
  whatever the picture's frame rate or the position reports' interval.
- The editor's draft is always a valid preset. Edits that are not (the
  file's text with a field out of range) list each field that needs
  attention, and the picture keeps the last valid draft
  (`Store.edited_text`).
- The queue holds at most 60 songs, leaving 4 of the platform's 64 file
  handles for lyric and preset files being read, and says how many it
  refused (`logic/Queue.roc`).

## Recipes

- **A preset layer type**: in `logic/Preset.roc`, add the kind to `Kind`,
  `kinds`, `kind_name` and `kind_key`; draw it in `logic/Scene.roc`'s
  `geometry`, `figure` (the drawing surface's shape) and `describe`; the
  editor's Add Layer offers it from `Preset.kinds`. Add an `expect` that a
  preset with it round-trips through `Preset.encode` and `Preset.decode`,
  and one for its `Scene.marks`. A new mapping target is the same in
  `Property`, `properties`, `property_name`, `property_range`,
  `Scene.shape` and `Scene.layer_marks`; it must be something the surface
  can bind to a source: a translation, rotation, scale, opacity or a
  pen's width (`thickness`).
- **Shader stages**: a preset's optional `shaders` field holds a JSON
  object, kept through its file and drawn without for now
  (`Preset.Shaders`). When the surface takes user-written Metal shaders,
  `Preset.from_json` reads its stages, uniforms and audio-bound parameters
  into typed values, `Preset.problems` checks them, and `Scene` hands them
  to the surface beside the marks.
- **A built-in preset**: a value in `logic/Library.roc` added to
  `builtins`, with an ID starting `builtin.`. Its `expect` checks every
  built-in.
- **A widget**: a function in `Widgets.roc` returning `Elem(ctx)` for any
  `ctx`, handed what it shows (values, signals, handlers); local state
  inside it if only it reads that state.
- **A panel**: a function in `Panels.roc` (or a module of its own, as
  `Editor.roc` is), its name in `Panels.names`, and a case in
  `Player.panel`. A panel is built only while it is open.
- **A worker**: declare `Worker.task({ name, run! })` as `Export.roc` does,
  add `task.registration()` to `.with_workers([...])` in `src/main.roc`,
  and ask for jobs from an effect site. Only data and `File` handles cross
  to a worker.
- **Logic**: a type module `logic/<Name>.roc`, listed in `logic/main.roc`'s
  `package [...]`, with `expect`s beside it; a property of it as a target in
  `fuzz/main.roc`'s `Fuzz.suite([...])`.
- **An image**: put it in `assets/` and draw it with
  `Ui.asset_image("name.png", { width: Fixed(64), label: "..." })`.
- **A spec**: write `specs/<name>.scm`, a `(test "name" (setup …) (steps …))`
  form (`specs/lyrics.scm` drops a song with its lyrics, plays it on the
  manual audio clock with `(render MS)` and checks the line shown), end it
  with `(expect-dump _)`, run `roc macos.roc test --update`, and review the
  dump it writes. `(frame)` draws the surface; `(expect-probe …)` reads its
  pixels.

The builders and the steps are documented in
[Build an app](https://lukewilliamboswell.github.io/roc-native-macos/apps.html)
and [the Ui reference](https://lukewilliamboswell.github.io/roc-native-macos/ui.html);
the engine (`Engine`, `Worker`) in the
[roc-signals guide](https://lukewilliamboswell.github.io/roc-signals/docs/guide/);
fuzzing in the [roc-fuzz manual](https://lukewilliamboswell.github.io/roc-fuzz/).

## Gotchas

- A store needs at least two cells: a single-field record builder,
  `{ a: Engine.cell(0) }.Engine.Cells`, compiles but fails at run time.
  `roc test` reports it.
- Post to an outbox at most once a turn: a decision that sends the player
  several commands sends one list (`Store.send([Load(...), Play])`), and
  one handler runs one decision that posts.
- `Engine.watch` and `Engine.watch_changes` never cancel what they asked
  for when their value changes. Anything that must stop or restart (an
  interval, a timer, a file read superseded by a newer one) belongs under
  `Engine.watch_latest`.
- Roc does not allow shadowing, and a type module's own functions are in
  scope throughout it: a local or a lambda's argument cannot reuse one's
  name (`Store` names its local `saved_prefs` because `Store.prefs`
  exists). `where` is a keyword, too.
- A type module cannot hold a type of its own name (`Preset.Preset`): the
  preset document is `Preset.Doc`, and the saved choices `Prefs.Choices`.
  A module cannot be named after a builtin either, which is why JSON is
  `JsonValue`.
- A builder's text is a signal. A literal works as one
  (`Ui.text("Presets", {})`); a `Str` value needs `Engine.const(value)`, and
  state needs `.signal()` or `.map`. A signal from outside a local state or
  a row enters it with `.lift()`.
- A dropdown's `choices` and a slider's `range` are fixed when it is
  built. A list that changes (the presets) is an `Engine.each` of buttons,
  and the seek slider runs 0 to 1000 of the song.
- An `Engine.each` row's template must build a single element: a widget
  with local state (an `Engine.state`), an `Engine.when` or a `switch` is
  not one, so wrap it in a stack (`Editor.view`'s layer rows do).
- A helper whose parameter is a signal used at two types needs a type
  annotation; without one the compiler reports two incompatible `map`
  methods.
- A function with no arguments is `() -> T` in annotations and `|| ...` in
  definitions. `app` is a keyword and cannot name a value or a field.
- `logic/` cannot import the platform: a package that needs `pf.` belongs
  in `src/`.
- A fuzz target's saved and mutated inputs bypass its generator, so a
  property restates its preconditions and returns `Fuzz.reject` outside
  them (`lrc-round-trip` does).
- A spec's locators find controls as a person would, by what they show:
  `(click (button "Play"))` needs exactly one button titled so, and
  `(files …)` the one file button, so give buttons distinct titles
  (`title_display: Hidden` keeps an icon-only button's title for this and
  for VoiceOver).
- In a spec, timers are held until the spec fires them, so the next-line
  timer (`Media.boundary`) waits; on the manual audio clock the lyrics
  follow the status each `(render MS)` publishes. A song sampled at 4 kHz
  needs half a second of audio before its first measurement (a 2048-sample
  window).
- Hot reloading keeps the state the old code built until Command-R; after
  changing a cell's or a state's type, press Command-R before anything else.
