## Pure Roc decisions and data types shared by the app and its fuzz
## targets. Put parsing, validation and file formats here so they can
## run without the macOS platform.
##
## To add a module, create `logic/<Name>.roc` and expose its type in the
## package header below. Callers can then write `import logic.Name`.
package [Eq, Gallery, JsonValue, Library, Lyrics, Pairing, Prefs, Preset, Queue, Scene] {}
