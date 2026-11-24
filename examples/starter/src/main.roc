app [main] {
	logic: "../logic/main.roc",
	pf: platform "../../../platform/main.roc",
}

import pf.Engine
import Home
import Import
import Store

## Expenses: a starting point for a roc-native-macos app. Type what you
## bought and what it cost, import a CSV file in a worker, and see the
## totals; the list is saved between launches.
##
## Where things are (`AGENTS.md` says more):
##
## - `src/main.roc`: this file, the program: its store, its view and its
##   workers. The header names the platform (`pf`) and the logic package.
## - `src/Store.roc`: shared state and the decisions that change it.
## - `src/Home.roc`: the window, composed from the store and the widgets.
## - `src/Widgets.roc`: reusable widgets, with no knowledge of the store.
## - `src/Import.roc`: a worker task and the site that asks for it.
## - `logic/`: the business logic, a package of pure Roc with no platform.
## - `fuzz/main.roc`: roc-fuzz targets for the logic package.
## - `assets/`: images the app draws; `assets/icon.png` is its icon.
## - `specs/`: specs of what the app does (`roc macos.roc test`).
##
## State flows one way: an event runs a handler, which returns writes
## (decisions in `Store`, or a local state's update); the engine applies
## them and wakes only the views that read what changed. Effects (saving,
## a worker job) are asked for by sites that watch a signal, and their
## answers come back as writes.
main : Engine.Program(_)
main =
	Engine.program_store({ storage_keys: [Store.storage_key] }, Store.start, |_boot| Home.view())
		.with_workers([Import.task.registration()])
