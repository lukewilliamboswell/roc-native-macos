app [main] { pf: platform "../../platform/main.roc" }

import pf.Engine exposing [Elem, File, Signal]
import pf.Files
import pf.Ui
import pf.Worker

## Workers: Roc tasks that run off the main thread, each job in a worker
## instance of its own, while the window stays responsive.
##
## The Mandelbrot tab draws the set as text, eight bands at once, one job
## each. The heartbeat counts on while the workers compute; Cancel stops
## them, and zooming starts a new picture, which stops the old one's jobs.
##
## The Lab tab shows the rest of what a task can do and meet: a job that
## crashes (only it is lost; the next job runs in a fresh instance), many
## jobs at once, a job that finishes after its request is cancelled
## (`on_cancel: Finish`), a job that times out, and a dropped file read,
## counted and copied into a report file by a job, then searched line by
## line by a preparation that a worker keeps between questions.
main : Engine.Program(_)
main =
	Engine.program_store({}, |_boot| store, |_boot| view())
		.with_workers([
			band.registration(),
			crasher.registration(),
			squares.registration(),
			slow.registration(),
			late.registration(),
			inspect.registration(),
			lines.registration([find.registration()]),
		])

# ------------------------------------------------------------------ tasks

## One band of the picture: its rows, the view and how hard to look.
Band : { index : U64, top : U64, rows : U64, view : View }

## The part of the plane shown, in fixed point (`one` is 1.0), and the
## detail: samples per character along each side, and the most iterations
## a sample may take.
View : { cx : I64, cy : I64, span : I64, samples : U64, limit : U64 }

## Draws one band of the picture as text.
band : Worker.Task(Band, Str, Worker.Never)
band = Worker.task({ name: "roc-native-macos.example/workers/band", run!: |b| Ok(render(b)) })

## Always crashes: its job is lost, and only its job.
crasher : Worker.Task(U64, U64, Worker.Never)
crasher = Worker.task({ name: "roc-native-macos.example/workers/crash", run!: |n| crash "the crash task crashed on job ${n.to_str()}, as it always does" })

## A small sum, for running many jobs at once.
squares : Worker.Task(U64, U64, Worker.Never)
squares = Worker.task({ name: "roc-native-macos.example/workers/squares", run!: |n| Ok(sum_squares(n)) })

## A long job that runs to the end when its request is cancelled; its
## answer is dropped and its worker kept.
slow : Worker.Task(U64, U64, Worker.Never)
slow = Worker.task({ name: "roc-native-macos.example/workers/slow", run!: |n| Ok(spin(n)), on_cancel: Finish })

## A long job with a short timeout: it is stopped and answered `Timeout`.
late : Worker.Task(U64, U64, Worker.Never)
late = Worker.task({ name: "roc-native-macos.example/workers/late", run!: |n| Ok(spin(n)), timeout: Ms(300) })

## What a job learns about a file: its size, its lines, its FNV-1a hash,
## and a report it wrote, a new file the page can read and save.
Report : { bytes : U64, lines : U64, hash : U64, report : File }

## Reads a file a mebibyte at a time and writes a report.
inspect : Worker.Task(File, Report, [Unreadable, TooLarge])
inspect = Worker.task({ name: "roc-native-macos.example/workers/inspect", run!: inspect! })

inspect! : File => Try(Report, [Unreadable, TooLarge])
inspect! = |file| {
	var $hash = fnv_offset
	var $lines = 0.U64
	for span in file.spans(1_048_576) ?? [] {
		chunk = file.read!(span).map_err(|_| Unreadable)?
		for byte in chunk {
			$hash = $hash.bitwise_xor(byte.to_u64()).times_wrap(fnv_prime)
			if byte == '\n' {
				$lines = $lines + 1
			}
		}
	}
	out = Files.build!({ name: "${file.name()} report.txt", mime: Mime("text/plain") })
	out.append!("${file.name()}: ${file.size().to_str()} bytes, ${$lines.to_str()} lines, FNV-1a ${hex64($hash)}\n\n".to_utf8())?
	out.append_file!(file)
	Ok({ bytes: file.size(), lines: $lines, hash: $hash, report: out.finish!() })
}

## A file's lines, prepared once and kept by a worker between questions.
lines : Worker.Preparation(File, List(Str), [Unreadable])
lines = Worker.preparation({ name: "roc-native-macos.example/workers/lines", prepare!: |file| file.contents_utf8!().map_ok(|text| text.split_on("\n")).map_err(|_| Unreadable) })

## How many of the prepared lines contain the text.
find = lines.task({ name: "roc-native-macos.example/workers/lines/find", run!: |all, text| Ok(all.keep_if(|line| !text.is_empty() and line.contains(text)).len()) })

# ------------------------------------------------------------------ store

## What the Mandelbrot tab asks for: nothing, or a picture (`serial`
## counts Draws, so drawing the same view again asks again).
Job : [Idle, Draw({ view : View, serial : U64 })]

## What the slow job's site asks for.
Slow : [Still, Run(U64)]

store = Engine.store(
	Workers,
	{
		tab: Engine.cell("Mandelbrot"),
		view: Engine.cell(home),
		detail: Engine.cell("Fine"),
		job: Engine.cell(Idle),
		bands: Engine.cell([]),
		done: Engine.cell(0.U64),
		status: Engine.cell("Press Draw."),
		ticks: Engine.cell(0.U64),
		serial: Engine.cell(0.U64),
		crash_run: Engine.cell(0.U64),
		crash_status: Engine.cell(""),
		many_run: Engine.cell(0.U64),
		many_count: Engine.cell(0.U64),
		many_sum: Engine.cell(0.U64),
		slow_run: Engine.cell(Still),
		slow_status: Engine.cell(""),
		late_run: Engine.cell(0.U64),
		late_status: Engine.cell(""),
		file: Engine.cell(NoFile),
		file_status: Engine.cell("Drop a file to inspect it in a worker."),
		report: Engine.cell(NoReport),
		digest: Engine.cell(""),
		query: Engine.cell(""),
		found: Engine.cell(""),
		saving: Engine.cell(NotYet),
	}.Engine.Cells,
)

cells = store.cells()

# ------------------------------------------------------------------ view

view : () -> Elem(Engine.StoreRoot(_))
view = ||
	Ui.vstack(
		{ spacing: 14, align: Fill, width: AtLeast(560) },
		[
			Ui.hstack(
				{},
				[
					Ui.text("Workers", { style: Title2, weight: Semibold }),
					Ui.spacer(),
					Ui.text("Roc jobs off the main thread", { style: Caption1, color: SecondaryLabel }),
				],
			),
			Ui.tabs(
				cells.tab.signal(),
				{
					choices: ["Mandelbrot", "Lab"],
					on_change: Engine.handle(|choice| [cells.tab.set(choice)]),
					page: |name| if (name == "Lab") lab() else mandelbrot(),
				},
			),
		],
	)

## The picture, its controls, the heartbeat and the site that asks for its
## bands. Leaving the tab disposes the site, which stops its jobs.
mandelbrot : () -> Elem(Engine.StoreRoot(_))
mandelbrot = || {
	job = cells.job.signal()
	drawing = job.map(|j| j != Idle)
	Ui.vstack(
		{ spacing: 10, align: Fill },
		[
			Ui.hstack(
				{ spacing: 8 },
				[
					Ui.button("Draw", { on_press: Engine.handle_by({ v: cells.view.signal(), d: cells.detail.signal(), s: cells.serial.signal() }.Signal.map(|x| x), |x, _| draw(x.v, x.d, x.s)), role: Default }),
					Ui.button("Cancel", { on_press: Engine.handle(|_| [cells.job.set(Idle), cells.status.set("Cancelled.")]), enabled: drawing }),
					Ui.button("Zoom In", { on_press: Engine.handle_by({ v: cells.view.signal(), d: cells.detail.signal(), s: cells.serial.signal() }.Signal.map(|x| x), |x, _| draw(zoom(x.v), x.d, x.s)) }),
					Ui.button("Reset", { on_press: Engine.handle_by({ d: cells.detail.signal(), s: cells.serial.signal() }.Signal.map(|x| x), |x, _| draw(home, x.d, x.s)) }),
					Ui.spacer(),
					Ui.segmented(cells.detail.signal(), { choices: ["Fast", "Fine", "Extreme"], on_change: Engine.handle(|choice| [cells.detail.set(choice)]) }),
				],
			),
			Ui.hstack(
				{ spacing: 10 },
				[
					Ui.progress(cells.done.signal().map(|n| n.to_i64_wrap()), { max: band_count.to_i64_wrap(), width: Fixed(160) }),
					Ui.text(cells.status.signal(), { style: Callout, squeeze: Yield }),
					Ui.spacer(),
					Engine.when(drawing, || heartbeat(), || Engine.text("")),
				],
			),
			Ui.box(
				{ padding: All(10), border: Line({ color: Separator, width: 1 }), width: Fill },
				Ui.text(cells.bands.signal().map(picture), { design: Monospaced, size: Fixed(10), overflow: Wrap, width: Fill }),
			),
			Engine.watch_latest(
				job,
				plan_bands,
				Engine.react_by(cells.done.signal(), drawn),
			),
			# The heartbeat: an interval that ticks only while a picture is
			# drawn. It goes on ticking because the jobs are not on the main
			# thread.
			Engine.watch_latest(
				drawing,
				|on| if (on) [Engine.interval(100)] else [],
				Engine.react(|_, _| [cells.ticks.update(|n| n + 1)]),
			),
		],
	)
}

## A spinner and the count of heartbeats since the picture was asked for.
heartbeat : () -> Elem(Engine.StoreRoot(_))
heartbeat = ||
	Ui.hstack(
		{ spacing: 6 },
		[
			Ui.busy(Engine.const(Bool.True), { size: Small, width: Fixed(60) }),
			Ui.text(cells.ticks.signal().map(|n| "heartbeat ${n.to_str()}"), { style: Caption1, design: MonospacedDigits, color: SecondaryLabel }),
		],
	)

## The Lab: one row per kind of job, then the file panel.
lab : () -> Elem(Engine.StoreRoot(_))
lab = || {
	slow_running = cells.slow_run.signal().map(|s| s != Still)
	Ui.vstack(
		{ spacing: 10, align: Fill },
		[
			lab_row("Crash a job", Engine.handle_by(cells.crash_run.signal(), |n, _| [cells.crash_run.set(n + 1), cells.crash_status.set("Running…")]), cells.crash_status.signal()),
			lab_row("Run 24 jobs", Engine.handle_by(cells.many_run.signal(), |n, _| [cells.many_run.set(n + 1), cells.many_count.set(0), cells.many_sum.set(0)]), { count: cells.many_count.signal(), sum: cells.many_sum.signal() }.Signal.map(many_text)),
			Ui.hstack(
				{ spacing: 8 },
				[
					Ui.button("Slow job", { on_press: Engine.handle_by(cells.serial.signal(), |n, _| [cells.serial.set(n + 1), cells.slow_run.set(Run(n + 1)), cells.slow_status.set("Running…")]), width: Fixed(110) }),
					Ui.button("Cancel", { on_press: Engine.handle(|_| [cells.slow_run.set(Still), cells.slow_status.set("Cancelled; the job finishes and its answer is dropped.")]), enabled: slow_running }),
					Ui.text(cells.slow_status.signal(), { style: Callout, squeeze: Yield }),
				],
			),
			lab_row("Timed job", Engine.handle_by(cells.late_run.signal(), |n, _| [cells.late_run.set(n + 1), cells.late_status.set("Running…")]), cells.late_status.signal()),
			Ui.divider(),
			Ui.drop_zone(
				{ on_drop: Engine.handle(picked), padding: All(10) },
				Ui.hstack(
					{ spacing: 8 },
					[
						Ui.image("doc.text.magnifyingglass", { style: Title2, color: Accent }),
						Ui.text(cells.file_status.signal(), { style: Callout, squeeze: Yield }),
						Ui.spacer(),
						Ui.file_button("Choose…", { on_files: Engine.handle(picked) }),
					],
				),
			),
			Engine.when(
				cells.report.signal().map(|r| r != NoReport),
				|| report_panel(),
				|| Engine.text(""),
			),
			# One site per kind of job.
			Engine.watch_latest(cells.crash_run.signal(), |n| if (n == 0) [] else [crasher.ask(n)], Engine.react(|_, res| [cells.crash_status.set(outcome(res.map_ok(|v| v.to_str())))])),
			Engine.watch_latest(cells.many_run.signal(), |n| if (n == 0) [] else upto(24).map(|i| squares.ask((i + 1) * 1000)), Engine.react(|_, res| tallied(res))),
			Engine.watch_latest(
				cells.slow_run.signal(),
				|s|
					match s {
						Run(_) => [slow.ask(spin_units)]
						Still => []
					},
				Engine.react(|_, res| [cells.slow_status.set(outcome(res.map_ok(|v| "finished (${v.to_str()})"))), cells.slow_run.set(Still)]),
			),
			Engine.watch_latest(cells.late_run.signal(), |n| if (n == 0) [] else [late.ask(spin_units)], Engine.react(|_, res| [cells.late_status.set(outcome(res.map_ok(|v| v.to_str())))])),
			Engine.watch_latest(
				cells.file.signal(),
				|f|
					match f {
						Picked(file) => [inspect.ask(file)]
						NoFile => []
					},
				Engine.react(|_, res| inspected(res)),
			),
			Engine.watch_latest(
				cells.report.signal(),
				|r|
					match r {
						Done(info) => [info.report.sha256()]
						NoReport => []
					},
				Engine.react(
					|_, res|
						match res {
							Ok(bytes) => [cells.digest.set(hex(bytes))]
							Err(e) => [cells.digest.set("unavailable (${Str.inspect(e)})")]
						},
				),
			),
			Engine.watch_latest(
				{ file: cells.file.signal(), query: cells.query.signal() }.Signal.map(|q| q),
				|q|
					match q.file {
						Picked(file) if !q.query.is_empty() => [find.ask({ init: file, input: q.query })]
						_ => []
					},
				Engine.react_by(cells.query.signal(), |text, _, res| [cells.found.set(found_text(text, res))]),
			),
		],
	)
}

## A button and what its last job came to.

lab_row = |label, on_press, shown|
	Ui.hstack(
		{ spacing: 8 },
		[
			Ui.button(label, { on_press, width: Fixed(110) }),
			Ui.text(shown, { style: Callout, squeeze: Yield }),
		],
	)

## The report a job wrote: what it found, its digest as the page reads it,
## a search over the file's lines, and a button that saves it.
report_panel : () -> Elem(Engine.StoreRoot(_))
report_panel = || {
	report = cells.report.signal()
	Ui.box(
		{ padding: All(12), border: Line({ color: Separator, width: 1 }), width: Fill },
		Ui.vstack(
			{ spacing: 6, align: Fill },
			[
				Ui.hstack(
					{},
					[
						Ui.text(report.map(report_title), { style: Headline, squeeze: Yield, overflow: TruncateMiddle }),
						Ui.spacer(),
						Ui.button("Save Report…", { on_press: Engine.handle_by(report, |r, _| save(r)), icon: Symbol("square.and.arrow.down") }),
					],
				),
				Ui.text(report.map(report_text), { style: Callout, color: SecondaryLabel }),
				Ui.text(cells.digest.signal().map(|d| "SHA-256 ${d}"), { style: Caption1, design: Monospaced, overflow: TruncateMiddle, width: Fill, squeeze: Yield }),
				Ui.hstack(
					{ spacing: 8 },
					[
						Ui.text_field(cells.query.signal(), { placeholder: "Find lines containing…", on_input: Engine.handle(|text| [cells.query.set(text)]), width: Fixed(220) }),
						Ui.text(cells.found.signal(), { style: Callout }),
					],
				),
				# Each press of "Save Report…" is a new value, so each one saves.
				Engine.watch_changes(
					cells.saving.signal(),
					|s|
						match s {
							Save(f, _) => [Engine.command(File.save(f, {}))]
							NotYet => []
						},
					Engine.ignore({}),
				),
			],
		),
	)
}

# ------------------------------------------------------------------ writes

## Ask for a picture of `v` at `detail`.
draw : View, Str, U64 -> List(Engine.Write(_))
draw = |v, detail, serial| {
	sized = with_detail(v, detail)
	[
		cells.view.set(v),
		cells.serial.set(serial + 1),
		cells.job.set(Draw({ view: sized, serial: serial + 1 })),
		cells.bands.set(List.repeat("", band_count)),
		cells.done.set(0),
		cells.ticks.set(0),
		cells.status.set("Drawing ${band_count.to_str()} bands…"),
	]
}

## One band's answer: its text, in its place.
drawn : U64, Job, Try((U64, Str), Worker.Error(Worker.Never)) -> List(Engine.Write(_))
drawn = |done, job, res|
	match (job, res) {
		(Draw(_), Ok((index, text))) => {
			finished = done + 1 == band_count
			[
				cells.bands.update(|held| held.set(index, text) ?? held),
				cells.done.set(done + 1),
			].concat(if (finished) [cells.status.set("Drawn: ${band_count.to_str()} bands."), cells.job.set(Idle)] else [])
		}
		(_, Err(e)) => [cells.status.set("A band was not drawn: ${ended(e)}."), cells.job.set(Idle)]
		(Idle, Ok(_)) => []
	}

## One of the 24 sums.
tallied : Try(U64, Worker.Error(Worker.Never)) -> List(Engine.Write(_))
tallied = |res|
	match res {
		Ok(sum) => [cells.many_count.update(|n| n + 1), cells.many_sum.update(|s| s + sum)]
		Err(_) => []
	}

picked : Engine.Received -> List(Engine.Write(_))
picked = |{ files, .. }|
	match files.first() {
		Ok(file) => [cells.file.set(Picked(file)), cells.file_status.set("Inspecting ${file.name()}…"), cells.report.set(NoReport), cells.digest.set(""), cells.found.set("")]
		Err(_) => []
	}

inspected : Try(Report, Worker.Error([Unreadable, TooLarge])) -> List(Engine.Write(_))
inspected = |res|
	match res {
		Ok(info) => [cells.report.set(Done(info)), cells.file_status.set("Inspected in a worker.")]
		Err(e) => [cells.file_status.set("Not inspected: ${ended(e)}")]
	}

save : [NoReport, Done(Report)] -> List(Engine.Write(_))
save = |r|
	match r {
		Done(info) =>
			[
				cells.saving.update(
					|prev| match prev {
						Save(_, n) => Save(info.report, n + 1)
						NotYet => Save(info.report, 1)
					},
				),
			]
		NoReport => []
	}

# ------------------------------------------------------------------ text

## Why a job has no answer, for people.
ended : Worker.Error(e) -> Str
ended = |e|
	match e {
		Failed(error) => "failed (${Str.inspect(error)})"
		Timeout => "timed out"
		Refused => "refused: too many requests in flight"
		TooDeep => "its data was nested too deeply"
		NanKeys => "its data held a dictionary with two NaN keys"
		TooManyFiles => "its answer held too many files"
		Lost(fault) => "lost (${Str.inspect(fault)})"
	}

outcome : Try(Str, Worker.Error(e)) -> Str
outcome = |res|
	match res {
		Ok(text) => "Answered: ${text}"
		Err(e) => "No answer: ${ended(e)}"
	}

many_text : { count : U64, sum : U64 } -> Str
many_text = |{ count, sum }| if (count == 0) "" else "${count.to_str()} of 24 answered, total ${sum.to_str()}"

found_text : Str, Try(U64, Worker.Error([Unreadable])) -> Str
found_text = |text, res|
	match res {
		Ok(1) => "1 line contains “${text}”"
		Ok(n) => "${n.to_str()} lines contain “${text}”"
		Err(e) => "not searched: ${ended(e)}"
	}

report_title : [NoReport, Done(Report)] -> Str
report_title = |r|
	match r {
		Done(info) => info.report.name()
		NoReport => ""
	}

report_text : [NoReport, Done(Report)] -> Str
report_text = |r|
	match r {
		Done(info) => "${info.bytes.to_str()} bytes, ${info.lines.to_str()} lines, FNV-1a ${hex64(info.hash)}; the report is ${info.report.size().to_str()} bytes"
		NoReport => ""
	}

# ------------------------------------------------------------------ the work

## Fixed point: `one` is 1.0.
frac_bits : U8
frac_bits = 28

one : I64
one = 268_435_456

## The whole set.
home : View
home = { cx: -(one * 3 // 4), cy: 0, span: one * 3, samples: 1, limit: 1 }

## An eighth of the span, about a point in the seahorse valley, where the
## set's edge is most intricate.
zoom : View -> View
zoom = |v| { ..v, cx: -(one * 743_645 // 1_000_000), cy: one * 131_825 // 1_000_000, span: (v.span // 8).max(4096) }

with_detail : View, Str -> View
with_detail = |v, detail|
	match detail {
		"Fast" => { ..v, samples: 1, limit: 200 }
		"Extreme" => { ..v, samples: 8, limit: 40_000 }
		_ => { ..v, samples: 3, limit: 1_500 }
	}

columns : U64
columns = 72

band_rows : U64
band_rows = 3

band_count : U64
band_count = 8

## The bands of a picture.
plan_bands : Job -> List(Engine.Ask((U64, Str), Worker.Error(Worker.Never)))
plan_bands = |job|
	match job {
		Draw({ view: v, .. }) => upto(band_count).map(|i| band.ask({ index: i, top: i * band_rows, rows: band_rows, view: v }).map_ok(|text| (i, text)))
		Idle => []
	}

## The bands drawn so far, as one block of text; a band not drawn yet is
## blank lines.
picture : List(Str) -> Str
picture = |bands| {
	blank = Str.repeat(" ", columns)
	Str.join_with(bands.map(|text| if (text.is_empty()) Str.join_with(List.repeat(blank, band_rows), "\n") else text), "\n")
}

## A band's rows, one character per cell: how much of the cell lies in the
## set or near it, from its samples.
render : Band => Str
render = |{ top, rows, view: v, .. }| {
	shades = " .:-=+*#%@".to_utf8()
	height = band_rows * band_count
	# A character is about twice as tall as it is wide.
	step_x = v.span // (columns * v.samples).to_i64_wrap()
	step_y = step_x * 2
	left = v.cx - v.span // 2
	upper = v.cy - (step_y * (height * v.samples).to_i64_wrap()) // 2
	var $lines = []
	for row in top.until(top + rows) {
		var $line = List.with_capacity(columns)
		for col in (0.U64).until(columns) {
			var $total = 0.U64
			for sy in (0.U64).until(v.samples) {
				for sx in (0.U64).until(v.samples) {
					x = left + step_x * (col * v.samples + sx).to_i64_wrap()
					y = upper + step_y * (row * v.samples + sy).to_i64_wrap()
					$total = $total + shade_of(escape(x, y, v.limit), v.limit)
				}
			}
			# The mean shade of the samples, rounded.
			count = v.samples * v.samples
			shade = ($total + count // 2) // count
			$line = $line.append(shades.get(shade) ?? ' ')
		}
		$lines = $lines.append(Str.from_utf8($line) ?? "")
	}
	Str.join_with($lines, "\n")
}

## A sample's shade, 0 to 9: 9 inside the set, otherwise how many bits its
## escape count takes, so the bands near the edge show.
shade_of : U64, U64 -> U64
shade_of = |n, limit|
	if n >= limit {
		9
	} else {
		var $bits = 0.U64
		var $x = n
		while $x > 0 {
			$x = $x // 2
			$bits = $bits + 1
		}
		$bits.min(8)
	}

## The iterations before `c` leaves the radius-2 disk, at most `limit`.
escape : I64, I64, U64 -> U64
escape = |cr, ci, limit| {
	var $zr = 0.I64
	var $zi = 0.I64
	var $n = 0.U64
	var $going = Bool.True
	while $going and $n < limit {
		zr2 = ($zr * $zr).shr_wrap(frac_bits)
		zi2 = ($zi * $zi).shr_wrap(frac_bits)
		if zr2 + zi2 > 4 * one {
			$going = Bool.False
		} else {
			$zi = ($zr * $zi).shr_wrap(frac_bits - 1) + ci
			$zr = zr2 - zi2 + cr
			$n = $n + 1
		}
	}
	$n
}

## The units of work a slow or timed job does.
spin_units : U64
spin_units = 6_000

## Busy work that allocates as it goes: a stopped job unwinds at its next
## allocation.
spin : U64 -> U64
spin = |units| {
	var $acc = 7.U64
	for unit in (0.U64).until(units) {
		chunk = List.repeat(unit, 16)
		for x in chunk {
			var $i = 0.U64
			while $i < 2_000 {
				$acc = ($acc * 31 + x + $i) % 1_000_003
				$i = $i + 1
			}
		}
	}
	$acc
}

sum_squares : U64 -> U64
sum_squares = |n| (0.U64).until(n).fold(0, |sum, i| (sum + i * i) % 1_000_000_007)

fnv_offset : U64
fnv_offset = 14_695_981_039_346_656_037

fnv_prime : U64
fnv_prime = 1_099_511_628_211

hex64 : U64 -> Str
hex64 = |n| hex(upto(8).map(|i| n.shr_zf_wrap((56 - 8 * i).to_u8_wrap()).bitwise_and(255).to_u8_wrap()))

## Lowercase hexadecimal.
hex : List(U8) -> Str
hex = |bytes| {
	digits = "0123456789abcdef".to_utf8()
	var $out = []
	for b in bytes {
		$out = $out.append(digits.get((b // 16).to_u64()) ?? '?').append(digits.get((b % 16).to_u64()) ?? '?')
	}
	Str.from_utf8($out) ?? ""
}

## 0, 1, … n - 1.
upto : U64 -> List(U64)
upto = |n| {
	var $out = List.with_capacity(n)
	var $i = 0.U64
	while $i < n {
		$out = $out.append($i)
		$i = $i + 1
	}
	$out
}

expect hex([0, 15, 16, 255]) == "000f10ff"
expect hex64(0x0123456789abcdef) == "0123456789abcdef"
expect sum_squares(4) == 14
expect escape(0, 0, 50) == 50
expect escape(one * 2, one * 2, 50) == 1
expect picture(["ab", ""]).split_on("\n").len() == 1 + band_rows

expect (shade_of(0, 10), shade_of(5, 10), shade_of(10, 10), shade_of(1000, 5000)) == (0, 3, 9, 8)
