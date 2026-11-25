import pf.Engine exposing [Elem, File]
import pf.Files
import pf.Worker
import logic.Library
import Store

## Build the preset's JSON file in a worker and return its `File` handle.
## The page sends the name and text, then offers the finished file to the
## save panel. Follow this path when adding a task: register it in
## `main.roc`, ask for a job from an effect site, and turn the answer into
## writes in `Store`. For small imports, see the bounded read in
## `Editor.importing`.
## https://lukewilliamboswell.github.io/roc-native-macos/ui.html#workers
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
