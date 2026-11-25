app [main] {
	logic: "../logic/main.roc",
	pf: platform "../../../platform/main.roc",
}

import pf.Audio
import pf.Engine
import Export
import Player
import Store

## Music is a starter app with playback, lyrics and reactive visuals.
## Press Play to hear the bundled song, or drop in a song and its lyric
## file. Command-L shows the lyrics over the visualizer.
##
## Start here when adapting the starter:
##
## - Compose the window in `Player.roc` and put shared state and decisions
##   in `Store.roc`. Give reusable controls their inputs in `Widgets.roc`.
## - Keep rules such as parsing and validation in `logic/`, where the app
##   and the fuzz targets can share them.
## - Send playback commands through `Media.roc` and draw through
##   `Visual.roc`. See `Export.roc` for a worker that builds a file.
## - Update the affected behaviours in `tests/specs/`. Add fixtures in
##   `tests/fixtures/` and put new fuzz properties in `tests/fuzz/main.roc`.
##
## From the app created by `init`, use `roc macos.roc dev` to iterate,
## `roc macos.roc test` to run expects and specs, and `roc macos.roc run`
## to try the assembled app.
## https://lukewilliamboswell.github.io/roc-native-macos/apps.html#work-on-the-starter
main : Engine.Program(_)
main =
	Engine.program_store({ storage_keys: [Store.presets_key, Store.prefs_key] }, Store.start, |_boot| Player.view())
		.with_workers([Export.task.registration()])
		.with_ports(Audio.ports)
