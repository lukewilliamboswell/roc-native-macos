import pf.Engine exposing [Elem, File]
import pf.Worker
import logic.Ledger
import Store

## Importing expenses from a CSV file, in a worker: a Roc task that runs
## off the main thread, so the window stays responsive however large the
## file is.
##
## A worker job runs in an instance of its own, on a worker thread. Only
## data crosses: the job's input (here a `File` handle, never its bytes)
## and its answer, which `Worker.task` encodes for you. A job that crashes
## loses only that job. To add a worker:
##
## 1. Declare a task, `Worker.task({ name, run! })`, whose `run!` takes an
##    input and answers `Ok(output)` or `Err(error)`.
## 2. Register it in `src/main.roc`'s `.with_workers([...])`.
## 3. Ask for jobs from an effect site, `Engine.watch_latest(signal,
##    |value| [task.ask(input)], Engine.react(...))`, and turn each answer
##    into writes with a decision (`Store.imported`).
Import := [].{

	## What a job answers: the file's name and what `Ledger.from_csv` read
	## from it.
	Read : { name : Str, expenses : List(Ledger.Expense), skipped : U64 }

	## The task. Its name is namespaced and unversioned; two tasks with one
	## name are an error.
	task : Worker.Task(File, Read, [Unreadable])
	task = Worker.task({ name: "app.example/import-expenses", run!: Import.read! })

	## The job: read the file as text and parse it with the logic package.
	read! : File => Try(Read, [Unreadable])
	read! = |file| {
		text = file.contents_utf8!().map_err(|_| Unreadable)?
		parsed = Ledger.from_csv(text)
		Ok({ name: file.name(), expenses: parsed.expenses, skipped: parsed.skipped })
	}

	## The site that asks for a job whenever a file is chosen
	## (`Store.chosen`), and writes its answer (`Store.imported`).
	##
	## `Engine.watch_latest` cancels what it asked for when the signal
	## changes again, so choosing a second file stops the first one's job.
	## Use it for anything that must stop or restart, such as an interval;
	## `Engine.watch` and `Engine.watch_changes` never cancel what they asked
	## for when the value changes, and suit a write that must always happen,
	## such as saving (`Home.saving`).
	site : () -> Elem(ctx)
		where [ctx.store : () -> Engine.Reach(ctx, _)]
	site = ||
		Engine.watch_latest(
			Store.cells.importing.signal(),
			|importing|
				match importing {
					Reading(file) => [Import.task.ask(file)]
					Idle => []
				},
			Engine.react(|_, answer| Store.imported(answer.map_err(Import.why))),
		)

	## Why a job has no answer, for the notice.
	why : Worker.Error([Unreadable]) -> Str
	why = |error|
		match error {
			Failed(Unreadable) => "the file is not text"
			Timeout => "reading it took too long"
			Lost(_) => "the worker reading it stopped"
			_ => "the worker could not answer"
		}
}
