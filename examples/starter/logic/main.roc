## The app's business logic, as a package of its own: pure Roc, with no
## platform. The app names it in its header (`logic: "../logic/main.roc"`
## in `src/main.roc`) and imports its modules as `logic.Money` and
## `logic.Ledger`; the fuzz targets in `fuzz/main.roc` import it the same
## way, under roc-fuzz's platform instead of this one.
##
## What belongs here: types and decisions that do not need a window, such
## as parsing, formatting, validation, totals and file formats. Keep it
## free of `pf.` imports (a package cannot import a platform), so that it
## is tested with `expect`, fuzzed, and reused anywhere. To add a module,
## write `logic/<Name>.roc` as a type module (`Name := [].{ ... }`) and add
## `Name` to the list below; then `import logic.Name` where it is used.
package [Ledger, Money] {}
