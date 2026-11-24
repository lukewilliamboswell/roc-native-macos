import pf.Audio
import pf.Engine exposing [Elem, File, Signal]
import logic.Eq

## The audio session: the one module that talks to the player (the
## platform's `Audio`), so that everything else speaks in the commands,
## events and status below. Roc owns the queue, the controls and what they
## mean; the host owns decoding, the EQ, the audio clock and the analysis.
##
## Decisions in `Store` post commands to the store's `media` outbox, a list
## a turn (`Store.send`), and `Media.session` sends them with `Audio.send`.
## The player's events come back to `Store.heard`, and its status (where
## playback stands, about five times a second while playing) to
## `Store.followed`. Every load names its song by `track`, the queue's
## generation when it was chosen (`logic/Queue.roc`), and every event and
## status carries it, so a late event about an older song changes nothing.
## The drawing surface reads the sound's measurements natively (the
## `audio.*` sources); Roc never relays them.
##
## The program declares the session's ports: `src/main.roc`'s
## `.with_ports(Audio.ports)`.
Media := [].{

	## What the player is doing, as the app shows it.
	Phase : [Stopped, Playing, Paused]

	## The player as the app knows it: what it is doing, where it is in the
	## song (milliseconds), how long the song is (0 until it is known), the
	## song it holds (its `track`, the queue's generation when it was
	## chosen), and the session's own generation, which changes with every
	## load, seek and stop: the drawing surface's `reset`, so its trails
	## start again.
	Player : { status : Phase, position_ms : U64, duration_ms : U64, generation : U64, reset : U64 }

	stopped : Player
	stopped = { status: Stopped, position_ms: 0, duration_ms: 0, generation: 0, reset: 0 }

	## What the app tells the player, in order (`Audio.Command`): `Load` a
	## file the listener gave, or `LoadAsset` one the app ships in
	## `assets/` (the default song), each stopping at the song's start;
	## `Play`, `Resume` after `Pause`, `Stop`; `Seek` in milliseconds;
	## `Volume` from 0 to 1; `Gain` of a band in dB (`Eq.centres`), `Preamp`
	## and `Bypass`.
	Command : Audio.Command

	## Why a song does not play.
	Error : Audio.Error

	## What happened: a song loaded, failed, or played to its end (once a
	## start).
	Event : Audio.Event

	## Where playback stands.
	Status : Audio.Status

	## The audio output playing: its name and its UID.
	Output : Audio.Output

	## Where a song comes from: a file the listener gave the app, or a path
	## in the app's `assets/`.
	Source : [Picked(File), Bundled(Str)]

	## The command that loads a song from its source.
	load : U64, Source -> Command
	load = |track, source|
		match source {
			Picked(file) => Load({ track, file })
			Bundled(path) => LoadAsset({ track, path })
		}

	## The commands that apply EQ settings: every band's gain, the preamp
	## and bypass.
	equalize : Eq.Settings -> List(Command)
	equalize = |settings|
		settings.bands
			.map_with_index(|tenths, band| Gain({ band: band.to_u8_wrap(), db: Eq.decibels(tenths) }))
			.concat([Preamp(Eq.decibels(settings.preamp)), Bypass(settings.bypass)])

	## A volume slider's percent as the session's 0 to 1.
	volume : I64 -> Command
	volume = |percent| Volume(percent.max(0).min(100).to_f32() / 100)

	## How often the session reports where playback stands while playing.
	status_ms : U32
	status_ms = 200

	## A status for the player at `position_ms`: what the boundary timer
	## supposes until the session's next status confirms it.
	status_at : Player, U64 -> Status
	status_at = |p, position_ms| {
		track: p.generation,
		generation: p.reset,
		state: if (p.status == Playing) Playing else Paused,
		position_ms,
		duration_ms: p.duration_ms,
		volume: 1,
		latency_ms: 0,
		visual_offset_ms: 0,
		output: { name: "", uid: "" },
		eq: { bypass: Bool.False, preamp_db: 0, gains_db: [] },
	}

	## The sites that send commands and hear events and status: place them
	## once in the window. `opening` is what the player is told when the
	## window opens (loading the song the queue starts with), `reading` what
	## the decisions need (the store's cells they read), `heard` the decision
	## for an event and `followed` the one for a status.
	session : { opening : List(Command), commands : Signal(ctx, Engine.Outbox(List(Command))), reading : Signal(ctx, s), heard : (s, Event -> List(Engine.Write(st))), followed : (s, Status -> List(Engine.Write(st))) } -> List(Elem(ctx))
		where [ctx.store : () -> Engine.Reach(ctx, st)]
	session = |{ opening, commands, reading, heard, followed }| [
		Engine.watch(Engine.const({}), |_| opening.map(Audio.send), Engine.ignore({})),
		Engine.on_post(commands, |sent| sent.map(Audio.send), Engine.ignore({})),
		Engine.watch(
			Engine.const({}),
			|_| [Audio.events({})],
			Engine.react_by(
				reading,
				|r, _, answer|
					match answer {
						Ok(event) => heard(r, event)
						Err(_) => []
					},
			),
		),
		Engine.watch(
			Engine.const({}),
			|_| [Audio.status({ every_ms: Media.status_ms })],
			Engine.react_by(
				reading,
				|r, _, answer|
					match answer {
						Ok(status) => followed(r, status)
						Err(_) => []
					},
			),
		),
	]

	## The site that keeps the session measuring while a song plays. The
	## drawing surface reads the measurements natively and holds them on
	## while it draws; this subscription holds them on too, so the
	## `audio.*` sources are fed wherever the surface's own hold is not
	## counted, as on a spec's manual audio clock. Its answers, once a
	## second, are ignored: the picture never waits on Roc.
	measuring : Signal(ctx, Player) -> Elem(ctx)
		where [ctx.store : () -> Engine.Reach(ctx, _)]
	measuring = |player|
		Engine.watch_latest(
			player.map(|p| p.status == Playing),
			|on| if (on) [Audio.analysis({ every_ms: 1000 })] else [],
			Engine.ignore({}),
		)

	## The site that follows which output is playing, for picture sync: a
	## status about once a second, each to `heard` (`Store.output_heard`),
	## which sends the offset kept for that output when it is not the one
	## that applies.
	output : { reading : Signal(ctx, s), heard : (s, Status -> List(Engine.Write(st))) } -> Elem(ctx)
		where [ctx.store : () -> Engine.Reach(ctx, st)]
	output = |{ reading, heard }|
		Engine.watch(
			Engine.const({}),
			|_| [Audio.status({ every_ms: 1000 })],
			Engine.react_by(
				reading,
				|r, _, answer|
					match answer {
						Ok(status) => heard(r, status)
						Err(_) => []
					},
			),
		)

	## A timer for the next lyric line: while playing, it fires when the
	## position should reach `at` (the next cue's start), so a line changes
	## on time however coarse the status reports are; the next status then
	## confirms the position. `None` sets nothing.
	boundary : { player : Signal(ctx, Player), at : Signal(ctx, [None, At(U64)]), reading : Signal(ctx, s), followed : (s, Status -> List(Engine.Write(st))) } -> Elem(ctx)
		where [ctx.store : () -> Engine.Reach(ctx, st)]
	boundary = |{ player, at, reading, followed }|
		Engine.watch_latest(
			{ p: player, at }.Signal.map(|both| Media.wait(both.p, both.at)),
			|pending|
				match pending {
					Wait({ ms, .. }) => [Engine.timer(ms.to_u32_wrap())]
					NoWait => []
				},
			Engine.react_by(
				reading,
				|r, pending, _|
					match pending {
						Wait({ until, player: p, .. }) => followed(r, Media.status_at(p, until))
						NoWait => []
					},
			),
		)

	## How long to wait for the position to reach `at`, while playing.
	wait : Player, [None, At(U64)] -> [NoWait, Wait({ ms : U64, until : U64, player : Player })]
	wait = |p, at|
		match at {
			At(until) if p.status == Playing and until > p.position_ms => Wait({ ms: until - p.position_ms, until, player: p })
			_ => NoWait
		}
}

expect {
	p = { ..Media.stopped, status: Playing, position_ms: 7_000, generation: 2 }
	Media.wait(p, At(12_000)) == Wait({ ms: 5_000, until: 12_000, player: p })
}
expect Media.wait({ ..Media.stopped, status: Paused, position_ms: 7_000 }, At(12_000)) == NoWait
expect Media.wait({ ..Media.stopped, status: Playing }, None) == NoWait

## EQ settings become every band's gain in dB, the preamp and bypass.
expect {
	commands = Media.equalize(Eq.with_band(Eq.flat, 2, -45))
	commands.len() == 12 and commands.get(2) == Ok(Gain({ band: 2, db: -4.5 })) and commands.last() == Ok(Bypass(Bool.False))
}

expect Media.volume(40) == Volume(0.4) and Media.volume(250) == Volume(1)
