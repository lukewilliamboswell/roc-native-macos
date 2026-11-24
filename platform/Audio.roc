import engine.Port
import Engine

## One local audio file played natively: a transport, a 10-band EQ and
## opt-in measurements of the signal (docs/ui.adoc, "Audio").
##
## The host's playback session (`host/Audio.swift`) serves these as typed
## ports, roc-signals' `Port`, in place of a page's JavaScript. An app that
## plays audio declares them once, `main = Engine.program_store(…)
## .with_ports(Audio.ports)`, then:
##
## - sends commands with `Audio.send(cmd)` from an effect plan (an
##   `Engine.on_post` site for a user's action);
## - follows `Audio.events({})` for what happened (a source loaded, failed
##   or played to its end), `Audio.status({ every_ms })` for where playback
##   stands, and `Audio.analysis({ every_ms })` for measurements, each from
##   an `Engine.watch` site. Measuring runs only while a subscription (or a
##   native drawing surface) holds it.
##
## Times are milliseconds on the source's own timeline: `position_ms` is
## where playback has rendered to (what is heard is `latency_ms` behind it).
Audio := [].{

	## What the session is told, in the order the app sends it. A command
	## takes effect before any later one: a seek after a load seeks the new
	## source, and a load replaces the source and everything scheduled for
	## the old one.
	##
	## - `Load({ track, file })`: open the whole file (a slice of one is
	##   `Failed(Unsupported(…))`) and stop at its start. `track` is the
	##   app's own name for it, which every event and status carries. The
	##   session holds the file while it is loaded, whatever the app does with
	##   the handle.
	## - `LoadAsset({ track, path })`: open a file the app ships in its
	##   `assets/` (`"song.mp3"`, `"music/intro.m4a"`), found as
	##   `Ui.asset_image` finds an image, and stop at its start, as `Load`
	##   does, with the same events. A path that leaves `assets/`, or names
	##   nothing there, is `Failed(Unsupported(…))`. It holds no file handle,
	##   so it does not count against the app's 64.
	## - `Play`: play from where playback stands (from the start after it
	##   ended). `Resume`: continue after `Pause`, and nothing otherwise.
	## - `Pause`: hold the playhead. `Stop`: let go of what is scheduled and
	##   go back to the start.
	## - `Seek(ms)`: move the playhead, clamped to the duration. Playing
	##   goes on playing, paused stays paused, and stopped stays stopped.
	## - `Volume(v)`: the output volume, 0 to 1. It comes after the EQ and
	##   the measurements, so it changes neither.
	## - `Gain({ band, db })`: the gain of EQ band `band` (0 to 9, see
	##   `band_centres_hz`), -12 to +12 dB. `Preamp(db)`: the gain before the
	##   bands, -24 to +12 dB. `Bypass(on)`: the unprocessed signal at the
	##   same volume, keeping the settings for when it is off again. `Flat`:
	##   every band and the preamp to 0 dB.
	## - `Close`: stop, and let go of the file and the audio engine.
	##
	## A value out of range is clamped (status reports what applies), a value
	## that is not a number is ignored, and a band other than 0 to 9 is a
	## fatal error of the host.
	Command : [
		Load({ track : U64, file : Engine.File }),
		LoadAsset({ track : U64, path : Str }),
		Play,
		Resume,
		Pause,
		Stop,
		Seek(U64),
		Volume(F32),
		Gain({ band : U8, db : F32 }),
		Preamp(F32),
		Bypass(Bool),
		Flat,
		Close,
	]

	## Why a source does not play, each recoverable: load another.
	##
	## - `Unsupported(why)`: a format the decoder does not play, or a slice
	##   of a file rather than a whole one.
	## - `Corrupt(why)`: the file is not the audio it claims to be.
	## - `Output(why)`: the audio output could not start.
	Error : [Unsupported(Str), Corrupt(Str), Output(Str)]

	## A source that opened: its length in milliseconds and in frames at its
	## own sample rate, and its channel count.
	Loaded : { track : U64, duration_ms : U64, frames : U64, sample_rate : U32, channels : U32 }

	## What happened, in order. `Ended` is natural completion, once per
	## start: a seek, a stop or a new load first discards any completion of
	## what came before, so an `Ended` always names the current source.
	Event : [Loaded(Loaded), Failed({ track : U64, error : Error }), Ended({ track : U64 })]

	## The transport: nothing loaded (`Idle`, also after a failure or
	## `Close`), opening a file, or loaded and stopped, playing, paused or
	## played to the end.
	State : [Idle, Loading, Stopped, Playing, Paused, Ended]

	## The EQ as it applies: `gains_db` has one gain per band of
	## `band_centres_hz`, in order.
	Eq : { bypass : Bool, preamp_db : F32, gains_db : List(F32) }

	## Where playback stands: sent when it subscribes, on every change, and
	## every `every_ms` while playing. Only the newest waits while the app is
	## busy. `latency_ms` is how long after `position_ms` a sample is heard.
	## `generation` changes with every load, seek, stop and restart: a
	## drawing surface's `reset` signal, so its trails start again.
	Status : { track : U64, generation : U64, state : State, position_ms : U64, duration_ms : U64, volume : F32, latency_ms : F32, eq : Eq }

	## One measurement of a 2048-sample window (43 ms at 48 kHz) of the
	## signal after the EQ and before the volume, the window nearest the
	## playhead, at most every `every_ms`, newest only.
	##
	## - `at_ms`: the window's centre on the source timeline.
	## - `rms_db`: the mean-square level, channel powers averaged, in dBFS
	##   (a full-scale sine reads -3); `peak_db`: the largest sample. Silence
	##   reads -120, the floor, never infinity.
	## - `bands_db`: the energy in each of the 24 bands of `band_edges_hz`
	##   (Hann window, 2048-point FFT, channel powers averaged), in dB
	##   relative to a full-scale sine whose energy is all in one band.
	## - `envelope`: the window's mono signal as 32 min/max pairs, -1 to 1.
	##
	## A seek, a stop or a new source discards the old measurements; paused
	## and ended sources send none until playback moves again.
	Snapshot : { track : U64, at_ms : F64, rms_db : F32, peak_db : F32, bands_db : List(F32), envelope : { min : List(F32), max : List(F32) } }

	## Why a subscription delivered nothing (roc-signals' `Port.Error`).
	PortError : Port.Error

	## The ports an app that plays audio declares: `.with_ports(Audio.ports)`.
	ports : List(Engine.PortRegistration)
	ports = Port.registrations(endpoints)

	## A command, for an effect plan: `Engine.on_post(cells.audio.signal(),
	## |cmds| cmds.map(Audio.send), Engine.ignore({}))`.
	send : Command -> Engine.Ask(output, error)
	send = |command| Engine.command(endpoints.command.send(command))

	## The session's events, for as long as the site lives. Up to 64 wait
	## while the app is busy.
	events : {} -> Engine.Ask(Event, PortError)
	events = |_| endpoints.events.ask({})

	## The transport's status, now and at least every `every_ms` (16 to
	## 60000) while playing.
	status : { every_ms : U32 } -> Engine.Ask(Status, PortError)
	status = |every| endpoints.status.ask(every)

	## Measurements while playing, at most every `every_ms` (16 to 60000).
	## The subscription turns the measuring on, and the last one to go turns
	## it off.
	analysis : { every_ms : U32 } -> Engine.Ask(Snapshot, PortError)
	analysis = |every| endpoints.analysis.ask(every)

	## The EQ bands' centre frequencies in Hz, one octave wide each. A band
	## whose centre is above 45% of the source's sample rate (16 kHz for a
	## source below 35.6 kHz) is bypassed, keeping its gain.
	band_centres_hz : List(F32)
	band_centres_hz = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

	## The 25 edges in Hz of the measurements' 24 bands, logarithmically
	## spaced from 40 Hz to 16 kHz: band `i` runs from edge `i` to edge
	## `i + 1`. A band above half the source's sample rate reads -120.
	band_edges_hz : List(F64)
	band_edges_hz = (0.U64).until(25).fold([], |edges, i| edges.append(40 * (400.F64).pow(i.to_f64() / 24)))
}

## The ports themselves, as the host serves them (`host/Audio.swift`).
endpoints : {
	command : Port.Command(Audio.Command),
	events : Port.Subscription({}, Audio.Event),
	status : Port.Subscription({ every_ms : U32 }, Audio.Status),
	analysis : Port.Subscription({ every_ms : U32 }, Audio.Snapshot),
}
endpoints = {
	command: Port.command({ name: "roc-native-macos/audio/command" }),
	events: Port.subscription({ name: "roc-native-macos/audio/events", delivery: Every(64) }),
	status: Port.subscription({ name: "roc-native-macos/audio/status", delivery: Latest }),
	analysis: Port.subscription({ name: "roc-native-macos/audio/analysis", delivery: Latest }),
}

## A command crosses as its JSON: tags by name, a U64 as a decimal string.
expect {
	sent = |command|
		match endpoints.command.send(command) {
			PortCommand({ port, message, .. }) => "${port} ${message.json}"
		}
	[sent(Seek(1500)), sent(Play), sent(Gain({ band: 3, db: -12 })), sent(Bypass(Bool.True)), sent(LoadAsset({ track: 2, path: "song.mp3" }))]
		== [
			"roc-native-macos/audio/command {\"Seek\":\"1500\"}",
			"roc-native-macos/audio/command \"Play\"",
			"roc-native-macos/audio/command {\"Gain\":{\"band\":3,\"db\":-12}}",
			"roc-native-macos/audio/command {\"Bypass\":true}",
			"roc-native-macos/audio/command {\"LoadAsset\":{\"path\":\"song.mp3\",\"track\":\"2\"}}",
		]
}

## The host's status and events decode as the app's types.
expect {
	status : Try(Audio.Status, Port.Error)
	status = endpoints.status.message(PortAnswer({ json: "{\"duration_ms\":\"1000\",\"eq\":{\"bypass\":false,\"gains_db\":[0.0,-12.0],\"preamp_db\":0.0},\"generation\":\"3\",\"latency_ms\":0.0,\"position_ms\":\"250\",\"state\":\"Playing\",\"track\":\"7\",\"volume\":1.0}", blobs: [], files: [] }))
	ended : Try(Audio.Event, Port.Error)
	ended = endpoints.events.message(PortAnswer({ json: "{\"Ended\":{\"track\":\"7\"}}", blobs: [], files: [] }))
	failed : Try(Audio.Event, Port.Error)
	failed = endpoints.events.message(PortAnswer({ json: "{\"Failed\":{\"error\":{\"Corrupt\":\"bad header\"},\"track\":\"2\"}}", blobs: [], files: [] }))
	(status.map_ok(|s| (s.state, s.position_ms, s.generation, s.eq.gains_db)), ended, failed)
		== (Ok((Playing, 250, 3, [0, -12])), Ok(Ended({ track: 7 })), Ok(Failed({ track: 2, error: Corrupt("bad header") })))
}

## Four ports, named once.
expect Audio.ports.len() == 4

## 24 bands from 40 Hz to 16 kHz.
expect {
	edges = Audio.band_edges_hz
	(edges.len(), (edges.first() ?? 0).to_str(), (edges.last() ?? 0) > 15999 and (edges.last() ?? 0) < 16001) == (25, "40", Bool.True)
}
