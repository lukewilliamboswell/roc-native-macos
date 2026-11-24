#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	roc: "nightly-2026-11-22-3350b1c",
}

import cli.Path
import cli.Stdout

## Write the audio player's recorded-case fixtures,
## `examples/player/tests/fixtures/*.wav`, and the sync test's click track,
## `examples/visualizer/tests/fixtures/sync-clicks.wav` and the starter's
## `examples/starter/assets/sync-test.wav`, which are committed:
##
##     roc-stable scripts/audio_fixtures.roc
##
## Each is a short 16-bit PCM WAV file, synthesized here, so a case's
## measurements have known answers:
##
## - `clicks.wav`: 22.05 kHz mono, 1 s, a 2 ms click every 250 ms, for the
##   transport (pause, seek, completion), which the session resamples.
## - `tones-44100.wav`: 44.1 kHz mono, 0.5 s, 250 Hz and 4 kHz together,
##   each at -20 dBFS: widely separated, for the EQ and the bands.
## - `tones-48000.wav`: the same tones at 48 kHz in stereo, the right
##   channel the left inverted, so averaging channel powers must still
##   register them.
## - `silence-44100.wav` and `silence-48000.wav`: 0.25 s of digital silence.
## - `invalid.wav`: a RIFF header over bytes that are not audio.
## - `sync-clicks.wav` and `sync-test.wav`: 48 kHz mono, 8 s of silence with
##   a 5 ms burst of a 1 kHz square wave at 0.9 of full scale every 500 ms,
##   the first at 250 ms: the click track the audio/visual timing harness
##   (host/AVTiming.swift) and the starter's Sync test play.
main! = |_args| {
	dir = "examples/player/tests/fixtures"
	Path.create_all!(Path.utf8(dir))?
	for { name, bytes } in fixtures {
		Path.write_bytes!(Path.utf8("${dir}/${name}"), bytes)?
		Stdout.line!("wrote ${dir}/${name} (${bytes.len().to_str()} bytes)")?
	}
	sync = wav(48000, 1, bursts(48000, 8 * 48000))
	for path in ["examples/visualizer/tests/fixtures/sync-clicks.wav", "examples/starter/assets/sync-test.wav"] {
		Path.create_all!(Path.utf8(Str.join_with(path.split_on("/").drop_last(1), "/")))?
		Path.write_bytes!(Path.utf8(path), sync)?
		Stdout.line!("wrote ${path} (${sync.len().to_str()} bytes)")?
	}
	Ok({})
}

fixtures : List({ name : Str, bytes : List(U8) })
fixtures = [
	{ name: "clicks.wav", bytes: wav(22050, 1, clicks(22050, 22050)) },
	{ name: "tones-44100.wav", bytes: wav(44100, 1, tones(44100, 22050, Bool.False)) },
	{ name: "tones-48000.wav", bytes: wav(48000, 2, tones(48000, 24000, Bool.True)) },
	{ name: "silence-44100.wav", bytes: wav(44100, 1, List.repeat(0, 11025)) },
	{ name: "silence-48000.wav", bytes: wav(48000, 1, List.repeat(0, 12000)) },
	{ name: "invalid.wav", bytes: "RIFF".to_utf8().concat([56, 0, 0, 0]).concat("WAVEfmt ".to_utf8()).concat(List.repeat(0xA5, 48)) },
]

## `frames` samples at `rate`: silence with a 2 ms click of half full
## scale every 250 ms, the first at 0.
clicks : U64, U64 -> List(I16)
clicks = |rate, frames| {
	every = rate // 4
	width = rate // 500
	(0.U64).until(frames).fold([], |out, i| out.append(if (i % every < width) 16384 else 0))
}

## `frames` samples at `rate`: silence with a 5 ms burst of a 1 kHz square
## wave at 0.9 of full scale every 500 ms, the first at 250 ms.
bursts : U64, U64 -> List(I16)
bursts = |rate, frames| {
	every = rate // 2
	width = rate // 200
	half = rate // 2000
	(0.U64).until(frames).fold(
		[],
		|out, i| {
			at = (i + every - rate // 4) % every
			out.append(if (i < rate // 4 or at >= width) 0 else if ((at // half) % 2 == 0) 29491 else -29491)
		},
	)
}

## 250 Hz and 4 kHz sines, each of amplitude 0.1 (-20 dBFS). With
## `inverted`, interleaved stereo whose right channel is the left negated.
tones : U64, U64, Bool -> List(I16)
tones = |rate, frames, inverted|
	(0.U64).until(frames).fold(
		[],
		|out, i| {
			t = i.to_f64() / rate.to_f64()
			v = 0.1 * (2 * F64.pi * 250 * t).sin() + 0.1 * (2 * F64.pi * 4000 * t).sin()
			s = (v * 32767).to_i64_wrap().to_i16_wrap()
			if (inverted) out.append(s).append(-s) else out.append(s)
		},
	)

## A canonical 44-byte WAV header over 16-bit little-endian samples.
wav : U32, U16, List(I16) -> List(U8)
wav = |rate, channels, samples| {
	data = samples.fold([], |out, s| le16(out, s.to_u16_wrap()))
	block = channels * 2
	header = "RIFF".to_utf8()
		|> le32(36 + data.len().to_u32_wrap())
		.concat("WAVEfmt ".to_utf8())
		|> le32(16)
		|> le16(1)
		|> le16(channels)
		|> le32(rate)
		|> le32(rate * block.to_u32())
		|> le16(block)
		|> le16(16)
		.concat("data".to_utf8())
		|> le32(data.len().to_u32_wrap())
	header.concat(data)
}

le16 : List(U8), U16 -> List(U8)
le16 = |out, v| out.append((v % 256).to_u8_wrap()).append((v // 256).to_u8_wrap())

le32 : List(U8), U32 -> List(U8)
le32 = |out, v| le16(le16(out, (v % 65536).to_u16_wrap()), (v // 65536).to_u16_wrap())

expect {
	bytes = wav(8000, 1, [1, -1])
	(bytes.len(), bytes.take_first(4), bytes.sublist({ start: 24, len: 4 }), bytes.drop_first(44)) == (48, "RIFF".to_utf8(), [64, 31, 0, 0], [1, 0, 255, 255])
}

expect clicks(2000, 1000).keep_if(|s| s != 0).len() == 8

## Two bursts in a second: 5 ms each, the first at 250 ms, then 750 ms.
expect {
	b = bursts(4000, 4000)
	(b.keep_if(|s| s != 0).len(), b.get(999), b.get(1000), b.get(1019), b.get(1020), b.get(3000)) == (40, Ok(0), Ok(29491), Ok(-29491), Ok(0), Ok(29491))
}

expect {
	t = tones(48000, 4, Bool.True)
	t.len() == 8 and t.get(1) == t.get(0).map_ok(|s| -s)
}
