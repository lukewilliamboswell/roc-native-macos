## The player's logic, as a package of its own: pure Roc, with no
## platform. The app names it in its header (`logic: "../logic/main.roc"`
## in `src/main.roc`) and imports its modules as `logic.Lyrics` and
## `logic.Queue`; the fuzz targets in `fuzz/main.roc` import it the same
## way, under roc-fuzz's platform instead of this one.
##
## - `Lyrics`: LRC and plain-text lyrics, and the line at a position.
## - `Pairing`: songs and lyric files given together, paired by name.
## - `Queue`: the play queue, its generations and its room.
## - `Eq`: the equalizer's settings, in tenths of a dB.
## - `Preset`: the versioned preset document, its file and its checks.
## - `Library`: the built-in presets, Ember Tunnel, and saving presets.
## - `Scene`: what a preset draws, for the drawing surface.
## - `Prefs`: the listener's choices kept between launches.
## - `JsonValue`: JSON text and values, which presets are written in.
##
## What belongs here: types and decisions that do not need a window, such
## as parsing, formatting, validation and file formats. Keep it free of
## `pf.` imports (a package cannot import a platform), so that it is tested
## with `expect`, fuzzed, and reused anywhere. To add a module, write
## `logic/<Name>.roc` as a type module (`Name := [].{ ... }`) and add `Name`
## to the list below; then `import logic.Name` where it is used.
package [Eq, JsonValue, Library, Lyrics, Pairing, Prefs, Preset, Queue, Scene] {}
