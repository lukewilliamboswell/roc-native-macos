#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	roc: "nightly-2026-11-22-3350b1c",
}

import cli.Cmd
import cli.Duration
import cli.Monotonic
import cli.OsStr
import cli.Path
import cli.Sleep
import cli.Stderr
import cli.Stdout
import src/Demo

## Record the README's animated tiles, `docs/images/<example>.gif`, from the
## built examples (`blueprint run build` first):
##
##     roc-stable scripts/record_demos.roc                  # every example with a demo.scm
##     roc-stable scripts/record_demos.roc -- counter todos # the named ones
##
## Each example runs its `examples/<example>/demo.scm` spec, in the light
## appearance, while `screencapture -l<window> -o -x` takes a frame of its
## window every `Demo.frame_ms`. A capture names the window, so the app never
## needs focus and other windows never show. ffmpeg then scales the frames
## to `Demo.tile_width`, drops repeats and writes a looping GIF.
##
## It needs ffmpeg on PATH and the Screen Recording permission for the
## terminal, so it is not part of the check gate. While it records, the
## checkout is served at http://127.0.0.1:8737/ so the http-fetch demo has
## a local, deterministic URL to fetch.
main! : List(OsStr) => Try({}, _)
main! = |raw_args| {
	named = raw_args.map(OsStr.display).drop_if(|arg| arg == "--")
	listed = Path.list!(Path.utf8("examples"))?.keep_oks(|path| Path.filename(path).map_ok(Path.display))
	var $names = []
	for name in listed.sort_with(compare_str) {
		if Path.exists!(Path.utf8("examples/${name}/demo.scm"))? and (named.is_empty() or named.contains(name)) {
			$names = $names.append(name)
		}
	}
	for name in named {
		if !$names.contains(name) {
			warn!("record_demos: examples/${name}/demo.scm does not exist")
			return Err(Exit(2))
		}
	}
	server = Cmd.new("python3")
		.args(["-I", "-m", "http.server", "8737", "--bind", "127.0.0.1", "--directory", "."])
		.stdin(Null)
		.stdout(Null)
		.stderr(Null)
		.spawn!()?
	var $problems = []
	for name in $names {
		match record!(name) {
			Ok(made) => note!("docs/images/${name}.gif: ${kb(made.bytes)}, ${made.frames.to_str()} frames, ${Demo.seconds(made.ms)} s")
			Err(problem) => {
				warn!("${name}: ${problem}")
				$problems = $problems.append(name)
			}
		}
	}
	server.close!() ?? {}
	if $problems.is_empty() {
		Ok({})
	} else {
		warn!("record_demos: failed for ${Str.join_with($problems, ", ")}")
		Err(Exit(1))
	}
}

## Run one example's demo, capturing its window, and write its GIF.
record! : Str => Try({ bytes : U64, frames : U64, ms : U64 }, Str)
record! = |name| {
	exe = "examples/${name}/${name}"
	if !(Path.exists!(Path.utf8(exe)) ?? Bool.False) {
		return Err("${exe} is not built: run `blueprint run build` first")
	}
	text = Path.read_utf8!(Path.utf8("examples/${name}/demo.scm")) ? |error| "could not read its demo.scm: ${Str.inspect(error)}"
	steps = Demo.steps(text) ? |problem| "its demo.scm is not usable: ${Str.inspect(problem)} (it is a spec whose first step is (window))"
	dir = "build/demos/${name}"
	Path.delete_all!(Path.utf8(dir)) ?? {}
	Path.create_all!(Path.utf8(dir)) ? |error| "could not create ${dir}: ${Str.inspect(error)}"
	note!("record_demos: ${name}")
	demo = Cmd.new(OsStr.from_str(exe))
		.env("ROC_SPEC", OsStr.from_str(steps))
		.env("ROC_APPEARANCE", "light")
		.stdin(Null)
		.stdout(Null)
		.stderr(Pipe)
		.spawn!() ? |error| "could not start ${exe}: ${Str.inspect(error)}"
	window = window!(demo, "") ? |problem| {
		demo.close!() ?? {}
		problem
	}
	shots = capture!(demo, window, dir) ? |problem| {
		demo.close!() ?? {}
		problem
	}
	demo.close!() ?? {}

	# The frames that were taken: captures after the window closed fail.
	var $frames = []
	var $sizes = []
	for shot in shots.taken {
		match Path.read_bytes!(Path.utf8("${dir}/${shot.file}")) {
			Ok(bytes) =>
				match Demo.png_size(bytes) {
					Ok(size) => {
						$frames = $frames.append({ file: shot.file, at_ms: shot.at_ms, size })
						$sizes = $sizes.append(size)
					}
					Err(_) => {}
				}
			Err(_) => {}
		}
	}
	if $frames.is_empty() {
		return Err("no frame was captured: does the terminal have the Screen Recording permission?")
	}
	Path.write_utf8!(Path.utf8("${dir}/frames.ffconcat"), Demo.concat_list(Demo.settled($frames), shots.end_ms)) ? |error| "could not write the frame list: ${Str.inspect(error)}"
	ffmpeg!(["-f", "concat", "-safe", "0", "-i", "${dir}/frames.ffconcat", "-filter_complex", Demo.frames_filter(Demo.tile_height($sizes)), "-fps_mode", "vfr", "-c:v", "ffv1", "${dir}/frames.mkv"])?
	gif = "docs/images/${name}.gif"
	ffmpeg!(["-i", "${dir}/frames.mkv", "-filter_complex", Demo.gif_filter, "-fps_mode", "vfr", "-loop", "0", "-final_delay", "150", gif])?
	bytes = Path.size_in_bytes!(Path.utf8(gif)) ? |error| "ffmpeg wrote no ${gif}: ${Str.inspect(error)}"
	frames = Cmd.new("ffprobe").args(["-v", "error", "-count_frames", "-select_streams", "v:0", "-show_entries", "stream=nb_read_frames", "-of", "csv=p=0", OsStr.from_str(gif)]).capture!() ?? ""
	Ok({ bytes, frames: U64.from_str(frames.trim()) ?? 0, ms: shots.end_ms })
}

## The window number the app prints for its first step, `window`.
window! : Cmd.Child, Str => Try(U64, Str)
window! = |demo, printed|
	match Demo.window_number(printed) {
		Ok(number) => Ok(number)
		Err(NoWindow) =>
			match demo.read!(Duration.seconds(10)) {
				Ok(Stderr(bytes)) => window!(demo, printed.concat(Str.from_utf8_lossy(bytes)))
				Ok(Stdout(bytes)) => window!(demo, printed.concat(Str.from_utf8_lossy(bytes)))
				Err(error) => Err("the app printed no window number (${Str.inspect(error)}); it printed:\n${printed}")
			}
	}

## Take a frame every `Demo.frame_ms` until the app quits. A capture takes
## longer than that, so each runs in the background while the next starts.
capture! : Cmd.Child, U64, Str => Try({ taken : List({ file : Str, at_ms : U64 }), end_ms : U64 }, Str)
capture! = |demo, window, dir| {
	start = Monotonic.now!()
	var $children = []
	var $taken = []
	var $index = 0
	var $running = Bool.True
	while $running {
		at_ms = Monotonic.elapsed!(start).to_millis()
		if at_ms > 120_000 {
			return Err("the demo ran for more than two minutes; does its script end with quit?")
		}
		file = "frame-${pad(5, $index)}.png"
		child = Cmd.new("screencapture")
			.args(["-l${window.to_str()}", "-o", "-x", "${dir}/${file}"].map(OsStr.from_str))
			.stdin(Null)
			.stdout(Null)
			.stderr(Null)
			.spawn!() ? |error| "could not run screencapture: ${Str.inspect(error)}"
		$children = $children.append(child)
		$taken = $taken.append({ file, at_ms })
		$index = $index + 1
		drain!(demo)
		match demo.poll!() {
			Ok(Finished(_)) => {
				$running = Bool.False
			}
			_ => {
				next_ms = $index * Demo.frame_ms
				now_ms = Monotonic.elapsed!(start).to_millis()
				if next_ms > now_ms {
					Sleep.millis!(next_ms - now_ms) ?? {}
				}
			}
		}
	}
	end_ms = Monotonic.elapsed!(start).to_millis()
	for child in $children {
		_ = child.wait!()
		child.close!() ?? {}
	}
	Ok({ taken: $taken, end_ms })
}

## Read what the app has printed so far, so its pipe never fills.
drain! : Cmd.Child => {}
drain! = |demo|
	match demo.read!(Duration.zero) {
		Ok(_) => drain!(demo)
		Err(_) => {}
	}

ffmpeg! : List(Str) => Try({}, Str)
ffmpeg! = |args| {
	output = Cmd.new("ffmpeg").args(["-v", "error", "-y"].concat(args).map(OsStr.from_str)).stdin(Null).run!() ? |error| "could not run ffmpeg (is it on PATH?): ${Str.inspect(error)}"
	match output.status {
		Exited(0) => Ok({})
		_ => Err("ffmpeg ${Str.join_with(args, " ")} failed:\n${Str.from_utf8_lossy(output.stderr_bytes)}")
	}
}

pad : U64, U64 -> Str
pad = |width, n| {
	digits = n.to_str()
	Str.repeat("0", width - digits.count_utf8_bytes()).concat(digits)
}

kb : U64 -> Str
kb = |bytes| "${((bytes + 512) // 1024).to_str()} KB"

compare_str : Str, Str -> [Before, Same, After]
compare_str = |a, b| compare_bytes(a.to_utf8(), b.to_utf8())

compare_bytes : List(U8), List(U8) -> [Before, Same, After]
compare_bytes = |a, b|
	match (a, b) {
		([], []) => Same
		([], _) => Before
		(_, []) => After
		([x, .. as xs], [y, .. as ys]) => if (x < y) Before else if (x > y) After else compare_bytes(xs, ys)
	}

note! : Str => {}
note! = |line| Stdout.line!(line) ?? {}

warn! : Str => {}
warn! = |line| Stderr.line!(line) ?? {}

expect pad(5, 42) == "00042"
expect kb(300_000) == "293 KB"
