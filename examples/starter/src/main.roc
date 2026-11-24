app [main] {
	logic: "../logic/main.roc",
	pf: platform "../../../platform/main.roc",
}

import pf.Audio
import pf.Engine
import Export
import Player
import Store

## Music: a starting point for a roc-native-macos app. Drop songs into the
## window with their lyric files, choose a visualizer preset and press
## Play; turn on Lyrics (Command-L) to follow the words over the picture,
## shape the sound with the EQ, and make, save, import and export presets
## of your own. Presets and choices are saved between launches.
##
## Roc owns the queue, the controls, the preset documents and the lyrics.
## The host owns decoding, the EQ, the audio clock and the drawing surface:
## `src/Media.roc` and `src/Visual.roc` are the only modules that speak to
## them, through the platform's `Audio` session and `Ui.surface`.
##
## Where things are (the platform manual's "Build an app" says more):
##
## - `src/main.roc`: this file, the program: its store, its view and its
##   workers. The header names the platform (`pf`) and the logic package.
## - `src/Store.roc`: shared state and the decisions that change it.
## - `src/Player.roc`: the window, composed from the store and the parts.
## - `src/Words.roc`: the lyrics over the picture, and reading lyric files.
## - `src/Panels.roc` and `src/Editor.roc`: the queue, EQ and preset editor.
## - `src/Widgets.roc`: reusable widgets, with no knowledge of the store.
## - `src/Export.roc`: a worker task that builds a preset's file.
## - `src/Media.roc`, `src/Visual.roc`: the audio session and the drawing
##   surface.
## - `logic/`: lyrics, the queue, presets and scenes, a package of pure Roc
##   with no platform.
## - `assets/`: images the app draws; `assets/icon.png` is its icon.
## - `tests/`: specs of the app in `tests/specs/` (`roc macos.roc test`),
##   the files they use in `tests/fixtures/`, and roc-fuzz targets for the
##   logic package in `tests/fuzz/main.roc` (`roc macos.roc fuzz`).
##
## State flows one way: an event runs a handler, which returns writes
## (decisions in `Store`, or a local state's update); the engine applies
## them and wakes only the views that read what changed. Effects (saving,
## reading a file, a worker job, a player command) are asked for by sites
## that watch a signal, and their answers come back as writes.
main : Engine.Program(_)
main =
	Engine.program_store({ storage_keys: [Store.presets_key, Store.prefs_key] }, Store.start, |_boot| Player.view())
		.with_workers([Export.task.registration()])
		.with_ports(Audio.ports)
