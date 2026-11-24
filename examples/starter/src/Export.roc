import pf.Engine exposing [Elem, File]
import pf.Files
import pf.Worker
import logic.Library
import Store

## Exporting a preset, in a worker: a Roc task that runs off the main
## thread and builds a new file the page can save.
##
## Page code cannot write a file; a worker job can, with the file builder
## (`Files.build!`), and its answer carries the finished `File` back, which
## the page offers to the save panel (`File.save`). A job runs in an
## instance of its own, and only data crosses: the job's input (the preset's
## name and text) and its answer (the file's handle). A job that crashes
## loses only that job. To add a worker:
##
## 1. Declare a task, `Worker.task({ name, run! })`, whose `run!` takes an
##    input and answers `Ok(output)` or `Err(error)`.
## 2. Register it in `src/main.roc`'s `.with_workers([...])`.
## 3. Ask for jobs from an effect site, `Engine.watch_latest(signal,
##    |value| [task.ask(input)], Engine.react(...))`, and turn each answer
##    into writes with a decision (`Store.exported`).
##
## Importing goes the other way and needs no worker: a preset file is small,
## so the page reads it with the bounded `read_utf8` (`Editor.importing`).
Export := [].{

	## What a job is given: the preset's name and its file's text.
	Job : { name : Str, text : Str }

	## The task. Its name is namespaced and unversioned; two tasks with one
	## name are an error.
	task : Worker.Task(Job, File, [TooLarge])
	task = Worker.task({ name: "app.example/export-preset", run!: Export.build! })

	## The job: a JSON file named for the preset, holding its text.
	build! : Job => Try(File, [TooLarge])
	build! = |{ name, text }| {
		out = Files.build!({ name: "${Library.slug(name)}.json", mime: Mime("application/json") })
		out.append!(text.to_utf8())?
		Ok(out.finish!())
	}

	## The site that asks for a job whenever Export… is pressed
	## (`Store.export_asked`), and passes the file it built on
	## (`Store.exported`). `Engine.watch_latest` cancels a job still running
	## when Export… is pressed again.
	site : () -> Elem(ctx)
		where [ctx.store : () -> Engine.Reach(ctx, _)]
	site = ||
		Engine.watch_latest(
			Store.cells.exporting.signal(),
			|exporting|
				match exporting {
					Building({ name, text, serial: _ }) => [Export.task.ask({ name, text })]
					NotExporting => []
				},
			Engine.react(|_, answer| Store.exported(answer)),
		)

	## The site that offers each exported file to the save panel. Every post
	## is a new value, so each export saves. A scripted run skips the panel
	## unless `ROC_SAVE_DIR` is set.
	saving : () -> Elem(ctx)
		where [ctx.store : () -> Engine.Reach(ctx, _)]
	saving = ||
		Engine.on_post(
			Store.cells.saving.signal(),
			|file| [Engine.command(File.save(file, {}))],
			Engine.ignore({}),
		)
}
