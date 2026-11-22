## The pure parts of `scripts/record_demos.roc`: an example's demo script as
## `ROC_SCRIPT` steps, the window number a run prints, the frames' sizes and
## timings, and the ffmpeg filters that turn the frames into a tile.
Demo := [].{

	## The width of every tile, in pixels.
	tile_width : U64
	tile_width = 400

	## How often a frame is taken, in milliseconds (10 frames a second).
	frame_ms : U64
	frame_ms = 100

	## A demo script's steps as one `ROC_SCRIPT`: one or more steps a line,
	## blank lines skipped, with a `window` step first so the recorder learns
	## the window's number. The last step must be `quit`, which ends the
	## recording.
	steps : Str -> Try(Str, [NoSteps, NoQuit])
	steps = |text| {
		lines = text.split_on("\n").map(|line| line.trim()).keep_if(|line| !line.is_empty())
		joined = Str.join_with(lines, ";")
		if joined.is_empty() {
			Err(NoSteps)
		} else if !(joined.split_on(";").last() == Ok("quit")) {
			Err(NoQuit)
		} else {
			Ok("window;${joined}")
		}
	}

	## The window number in what the app printed: its `window <number>` line.
	window_number : Str -> Try(U64, [NoWindow])
	window_number = |printed| {
		found = printed.split_on("\n").keep_oks(
			|line|
				if line.starts_with("window ") {
					U64.from_str(line.drop_prefix("window ").trim()).map_err(|_| NoNumber)
				} else {
					Err(NotWindow)
				},
		)
		found.first().map_err(|_| NoWindow)
	}

	## A PNG's width and height, from its `IHDR` chunk.
	png_size : List(U8) -> Try({ width : U64, height : U64 }, [NotPng])
	png_size = |bytes| {
		signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
		if bytes.len() < 24 or bytes.take_first(8) != signature {
			Err(NotPng)
		} else {
			Ok({ width: Demo.be32(bytes.sublist({ start: 16, len: 4 })), height: Demo.be32(bytes.sublist({ start: 20, len: 4 })) })
		}
	}

	be32 : List(U8) -> U64
	be32 = |bytes| bytes.fold(0, |acc, byte| acc * 256 + byte.to_u64())

	## The tile's height: the tallest frame scaled to `tile_width`, rounded
	## up to an even number. Shorter frames (the window grew or shrank) are
	## padded below with the backdrop.
	tile_height : List({ width : U64, height : U64 }) -> U64
	tile_height = |sizes| {
		tallest = sizes.fold(
			0,
			|most, { width, height }| {
				scaled = if (width == 0) 0 else (height * Demo.tile_width + width - 1) // width
				if (scaled > most) scaled else most
			},
		)
		tallest + tallest % 2
	}

	## The frames worth showing. The first frame after the window changed
	## size can catch AppKit between resizing the window and redrawing it,
	## so it is dropped when a later frame of the same size follows (the
	## frame before is then shown 100 ms longer).
	settled : List({ file : Str, at_ms : U64, size : { width : U64, height : U64 } }) -> List({ file : Str, at_ms : U64 })
	settled = |frames| {
		var $kept = []
		var $index = 0
		while $index < frames.len() {
			frame = frames.get($index) ?? { file: "", at_ms: 0, size: { width: 0, height: 0 } }
			before = if ($index == 0) frame.size else frames.get($index - 1).map_ok(|f| f.size) ?? frame.size
			after = frames.get($index + 1).map_ok(|f| f.size)
			if before == frame.size or after != Ok(frame.size) {
				$kept = $kept.append({ file: frame.file, at_ms: frame.at_ms })
			}
			$index = $index + 1
		}
		$kept
	}

	## An ffmpeg concat list showing each frame from the time it was taken
	## until the next one, and the last one until `end_ms`. Times are in
	## milliseconds from the start of the recording.
	concat_list : List({ file : Str, at_ms : U64 }), U64 -> Str
	concat_list = |frames, end_ms| {
		var $lines = ["ffconcat version 1.0"]
		var $index = 0
		while $index < frames.len() {
			frame = frames.get($index) ?? { file: "", at_ms: 0 }
			next = frames.get($index + 1).map_ok(|f| f.at_ms) ?? end_ms
			shown = if (next > frame.at_ms) next - frame.at_ms else Demo.frame_ms
			$lines = $lines.concat(["file '${frame.file}'", "duration ${Demo.seconds(shown)}"])
			$index = $index + 1
		}
		match frames.last() {
			Ok(last) => Str.join_with($lines.append("file '${last.file}'"), "\n").concat("\n")
			Err(_) => Str.join_with($lines, "\n").concat("\n")
		}
	}

	## Milliseconds as seconds with three decimals: `1050` is `1.050`.
	seconds : U64 -> Str
	seconds = |ms| {
		fraction = (ms % 1000).to_str()
		"${(ms // 1000).to_str()}.${Str.repeat("0", 3 - fraction.count_utf8_bytes())}${fraction}"
	}

	## The light window background, which fills the window's transparent
	## rounded corners and the padding below a shorter frame. An opaque tile
	## lets the GIF store only what changed from one frame to the next.
	backdrop : Str
	backdrop = "0xEFF1F3"

	## The first pass: every frame scaled to the tile's width, laid on the
	## backdrop and padded below to the tile's height, with frames that
	## repeat the one before dropped (the one before is then shown longer).
	frames_filter : U64 -> Str
	frames_filter = |height| {
		w = Demo.tile_width.to_str()
		"[0:v]scale=${w}:-2:flags=lanczos,format=rgba,split[a][b];[a]drawbox=x=0:y=0:w=iw:h=ih:color=${Demo.backdrop}:t=fill:replace=1[bg];[bg][b]overlay=0:0,format=rgb24,pad=${w}:${height.to_str()}:0:0:color=${Demo.backdrop},mpdecimate=hi=512:lo=256:frac=0.1"
	}

	## The second pass: one palette for the whole tile, used with a light
	## ordered dither, so the parts of a frame that did not change stay
	## the same and only the changed rectangle is stored.
	gif_filter : Str
	gif_filter = "[0:v]split[a][b];[a]palettegen=max_colors=128:stats_mode=full[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle"
}

expect Demo.steps("wait:500\nclick:+;wait:400\n\nquit\n") == Ok("window;wait:500;click:+;wait:400;quit")
expect Demo.steps("click:+\n") == Err(NoQuit)
expect Demo.steps("\n \n") == Err(NoSteps)

expect Demo.window_number("2026-11-23 app[1:2] note\nwindow 4711\n") == Ok(4711)
expect Demo.window_number("key cmd+n\n") == Err(NoWindow)

expect Demo.png_size([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 2, 0xd0, 0, 0, 2, 0x12, 8, 6]) == Ok({ width: 720, height: 530 })
expect Demo.png_size([1, 2, 3]) == Err(NotPng)

## A 720×530 window and a taller 720×600 one: the tile fits the taller.
expect Demo.tile_height([{ width: 720, height: 530 }, { width: 720, height: 600 }]) == 334

## A frame taken just after the window grew is dropped; one taken while it
## was still growing again is kept.
expect {
	small = { width: 720, height: 530 }
	big = { width: 720, height: 600 }
	bigger = { width: 720, height: 700 }
	kept = Demo.settled([
		{ file: "a", at_ms: 0, size: small },
		{ file: "b", at_ms: 100, size: big },
		{ file: "c", at_ms: 200, size: big },
		{ file: "d", at_ms: 300, size: bigger },
	])
	kept.map(|f| f.file) == ["a", "c", "d"]
}

expect (Demo.seconds(100), Demo.seconds(1050), Demo.seconds(7)) == ("0.100", "1.050", "0.007")

expect
	Demo.concat_list([{ file: "a.png", at_ms: 0 }, { file: "b.png", at_ms: 120 }], 300)
		== "ffconcat version 1.0\nfile 'a.png'\nduration 0.120\nfile 'b.png'\nduration 0.180\nfile 'b.png'\n"
