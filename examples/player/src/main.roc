app [main] { pf: platform "../../../platform/main.roc" }

import pf.Audio
import pf.Engine exposing [Elem, File, Signal]
import pf.Ui

## An audio player: choose or drop a local audio file, then play, pause,
## seek and set the volume. Ten EQ sliders, a preamp, Bypass and Flat shape
## what plays, and "Measure levels" turns on the session's measurements,
## shown as a level readout and the loudest band. Play Sample loads a file
## the app ships in `assets/` (`LoadAsset`); Escape Assets asks for one
## outside it, which is refused. The host plays and
## measures the file (`Audio`); the app keeps only the controls' state.
main : Engine.Program(_)
main = Engine.program_store({}, |_boot| store, |_boot| view()).with_ports(Audio.ports)

## Where playback stood when the host last said.
idle : Audio.Status
idle = { track: 0, generation: 0, state: Idle, position_ms: 0, duration_ms: 0, volume: 1, latency_ms: 0, eq: { bypass: Bool.False, preamp_db: 0, gains_db: List.repeat(0, 10) } }

store = Engine.store(
	Player,
	{

		## The commands a press posts, which the `on_post` site sends.
		outbox: Engine.cell(Engine.outbox({})),
		track: Engine.cell(0.U64),
		name: Engine.cell(""),
		status: Engine.cell(idle),
		event: Engine.cell("Choose or drop an audio file."),
		measuring: Engine.cell(Bool.False),
		level: Engine.cell(Nothing),
		ended: Engine.cell(0.U64),
	}.Engine.Cells,
)

cells = store.cells()

## The commands a handler sends, in order.
send : List(Audio.Command) -> List(Engine.Write(_))
send = |commands| [cells.outbox.update(|box| box.post(commands))]

caption : Ui.TextProps
caption = { style: Caption1, color: SecondaryLabel }

view : () -> Elem(Engine.StoreRoot(_))
view = || {
	status = cells.status.signal()
	loaded = status.map(|s| s.state != Idle and s.state != Loading)
	Ui.vstack(
		{ spacing: 10, align: Fill, padding: All(6), width: AtLeast(600) },
		[
			Ui.hstack(
				{},
				[
					Ui.image("music.note", { style: Title1, color: Accent }),
					Ui.text("Player", { style: Title2, weight: Semibold }),
					Ui.spacer(),
					Ui.button("Play Sample", { on_press: Engine.handle_by(cells.track.signal(), |track, _| sample(track + 1, "sample.wav")), icon: Symbol("music.note.list") }),
					Ui.button("Escape Assets", { on_press: Engine.handle_by(cells.track.signal(), |track, _| sample(track + 1, "../specs/fixtures/clicks.wav")), size: Small }),
					Ui.file_button("Choose Audio…", { on_files: Engine.handle_by(cells.track.signal(), received), icon: Symbol("waveform") }),
				],
			),
			Ui.drop_zone(
				{ on_drop: Engine.handle_by(cells.track.signal(), received), padding: All(10) },
				Ui.text("Drop an audio file here", { style: Headline, color: SecondaryLabel, align: Center, width: Fill }),
			),
			Ui.box(
				{ fill: ControlBackground, radius: 12, padding: All(12), width: Fill },
				Ui.vstack(
					{ spacing: 8, align: Fill },
					[
						Ui.text({ name: cells.name.signal(), status }.Signal.map(|{ name, status: s }| headline(name, s)), { style: Headline, design: MonospacedDigits, overflow: TruncateMiddle, width: Fill }),
						Ui.slider(status.map(|s| s.position_ms.to_i64_wrap()), { range: { min: 0, max: 60_000 }, on_input: Engine.handle(seeked), enabled: loaded, width: Fill }),
						Ui.hstack(
							{ spacing: 8 },
							[
								Ui.button("Play", { on_press: Engine.handle(|_| send([Play])), enabled: loaded, icon: Symbol("play.fill") }),
								Ui.button("Pause", { on_press: Engine.handle(|_| send([Pause])), enabled: loaded, icon: Symbol("pause.fill") }),
								Ui.button("Resume", { on_press: Engine.handle(|_| send([Resume])), enabled: loaded }),
								Ui.button("Stop", { on_press: Engine.handle(|_| send([Stop])), enabled: loaded, icon: Symbol("stop.fill") }),
								Ui.spacer(),
								Ui.text("Volume", caption),
								Ui.slider(status.map(|s| whole(s.volume * 100)), { range: { min: 0, max: 100 }, on_input: Engine.handle(|typed| send([Volume(number(typed) / 100)])), width: Fixed(120) }),
							],
						),
					],
				),
			),
			Ui.box(
				{ fill: ControlBackground, radius: 12, padding: All(12), width: Fill },
				Ui.vstack(
					{ spacing: 8, align: Fill },
					[
						Ui.hstack(
							{},
							[
								Ui.text("Equalizer", { style: Headline }),
								Ui.spacer(),
								Ui.checkbox("Bypass", { checked: status.map(|s| s.eq.bypass), on_change: Engine.handle(|on| send([Bypass(on)])) }),
								Ui.button("Flat", { on_press: Engine.handle(|_| send([Flat])) }),
							],
						),
						Ui.vstack({ spacing: 2, align: Fill }, band_sliders(status)),
					],
				),
			),
			Ui.box(
				{ fill: ControlBackground, radius: 12, padding: All(12), width: Fill },
				Ui.vstack(
					{ spacing: 8, align: Fill },
					[
						Ui.hstack(
							{},
							[
								Ui.checkbox("Measure levels", { checked: cells.measuring.signal(), on_change: Engine.handle(|on| [cells.measuring.set(on), cells.level.set(Nothing)]) }),
								Ui.spacer(),
								Ui.text(cells.level.signal().map(readout), { design: MonospacedDigits }),
							],
						),
						level_meter(status, cells.measuring.signal(), cells.level.signal().map(meter)),
					],
				),
			),
			Ui.text(cells.event.signal(), caption),
			# The commands each press posted, sent in order.
			Engine.on_post(cells.outbox.signal(), |commands| commands.map(Audio.send), Engine.ignore({})),
			# What happened, and where playback stands, for the window's life.
			Engine.watch(Engine.const({}), |_| [Audio.events({})], Engine.react_by(cells.ended.signal(), happened)),
			Engine.watch(
				Engine.const({}),
				|_| [Audio.status({ every_ms: 200 })],
				Engine.react(
					|_, result| match result {
						Ok(s) => [cells.status.set(s)]
						Err(_) => []
					},
				),
			),
			# Measuring only while the box is checked: unchecking ends the
			# subscription, which turns the host's analysis off.
			Engine.watch_latest(
				cells.measuring.signal(),
				|on| if (on) [Audio.analysis({ every_ms: 100 })] else [],
				Engine.react(
					|_, result| match result {
						Ok(snap) => [cells.level.set(Measured({ rms: snap.rms_db, peak: snap.peak_db, band: loudest(snap.bands_db) }))]
						Err(_) => []
					},
				),
			),
		],
	)
}

## Keep the native RMS meter readable over either renderer.
level_meter : Signal(ctx, Audio.Status), Signal(ctx, Bool), Signal(ctx, I64) -> Elem(ctx)
level_meter = |status, measuring, level|
	Ui.overlay(
		{ vertical: Center, padding: Axes({ horizontal: 12, vertical: 0 }), height: Fixed(32) },
		Engine.when(
			measuring,
			|| Engine.when(status.map(|s| s.state == Playing), meter_surface, meter_panel),
			meter_panel,
		),
		Ui.progress(level, { max: 60, width: Fill }),
	)

meter_surface : () -> Elem(ctx)
meter_surface = ||
	Ui.surface(
		Engine.const([]),
		{
			label: "Meter backlight",
			pacing: Engine.const(Display),
			background: Engine.const(meter_background),
			shader: Engine.const(Shaders({ warp: None, composite: Some(meter_glow), params: [] })),
			height: Fixed(32),
		},
	)

meter_panel : () -> Elem(ctx)
meter_panel = || Ui.box({ fill: meter_background, padding: Zero, width: Fill, height: Fixed(32) }, Ui.spacer())

meter_background : Ui.Color
meter_background = Adaptive({ light: 0xE2EBE8, dark: 0x233330 })

meter_glow : Str
meter_glow =
	\\float4 composite(Frame f, Params p) {
	\\    float2 from_center = (f.uv - 0.5) * float2(2.0, 1.5);
	\\    float falloff = saturate(1.0 - length(from_center));
	\\    float light = saturate(f.level) * falloff * 0.45;
	\\    return opaque(mix(sample(f, f.uv).rgb, float3(0.25, 0.72, 0.60), light));
	\\}

## One row per EQ band and one for the preamp: a label, a slider in whole
## dB and the gain the host applies.
band_sliders : Signal(Engine.StoreRoot(_), Audio.Status) -> List(Elem(Engine.StoreRoot(_)))
band_sliders = |status| {
	bands = Audio.band_centres_hz.map_with_index(
		|hz, index| {
			band = index.to_u8_wrap()
			gain = status.map(|s| s.eq.gains_db.get(index) ?? 0)
			row(hz_label(hz.to_f64()), gain, { min: -12, max: 12 }, |db| Gain({ band, db }))
		},
	)
	bands.append(row("Preamp", status.map(|s| s.eq.preamp_db), { min: -24, max: 12 }, |db| Preamp(db)))
}

row : Str, Signal(Engine.StoreRoot(_), F32), { min : I64, max : I64 }, (F32 -> Audio.Command) -> Elem(Engine.StoreRoot(_))
row = |label, gain, range, command|
	Ui.hstack(
		{ spacing: 8 },
		[
			Ui.text(Engine.const(label), { ..caption, align: Trailing, width: Fixed(56) }),
			Ui.slider(gain.map(whole), { range, on_input: Engine.handle(|typed| send([command(number(typed))])), size: Small, width: Fill }),
			Ui.text(gain.map(|db| "${signed(whole(db))} dB"), { ..caption, design: MonospacedDigits, align: Trailing, width: Fixed(52) }),
		],
	)

## Files from the button or the drop zone: the first is loaded as the next
## track.
received : U64, Engine.Received -> List(Engine.Write(_))
received = |track, { files, .. }|
	match files.first() {
		Ok(file) => load(track + 1, file)
		Err(_) => []
	}

load : U64, File -> List(Engine.Write(_))
load = |track, file| [cells.track.set(track), cells.name.set(file.name()), cells.event.set("Loading ${file.name()}…")].concat(send([Load({ track, file })]))

## A file the app ships in `assets/`, loaded by its path there as the next
## track (`LoadAsset`): no file handle, and a name that is not there fails
## as a load does.
sample : U64, Str -> List(Engine.Write(_))
sample = |track, path| [cells.track.set(track), cells.name.set(path), cells.event.set("Loading ${path}…")].concat(send([LoadAsset({ track, path })]))

seeked : Str -> List(Engine.Write(_))
seeked = |typed| send([Seek((I64.from_str(typed) ?? 0).max(0).to_u64_wrap())])

happened : U64, {}, Try(Audio.Event, Audio.PortError) -> List(Engine.Write(_))
happened = |ended, _, result|
	match result {
		Ok(Loaded(l)) => [cells.event.set("Loaded: ${clock(l.duration_ms)}, ${l.sample_rate.to_str()} Hz, ${l.channels.to_str()} channel${if (l.channels == 1) "" else "s"}")]
		Ok(Failed({ error, .. })) => [cells.event.set("Could not play it: ${describe(error)}")]
		Ok(Ended(_)) => [cells.ended.set(ended + 1), cells.event.set("Played to the end (${(ended + 1).to_str()} in all)")]
		Err(e) => [cells.event.set("Audio events stopped: ${Str.inspect(e)}")]
	}

describe : Audio.Error -> Str
describe = |error|
	match error {
		Unsupported(why) => "unsupported (${why})"
		Corrupt(why) => "not audio (${why})"
		Output(why) => "no output (${why})"
	}

headline : Str, Audio.Status -> Str
headline = |name, s| {
	state = match s.state {
		Idle => "Nothing loaded"
		Loading => "Loading"
		Stopped => "Stopped"
		Playing => "Playing"
		Paused => "Paused"
		Ended => "Ended"
	}
	if (s.state == Idle) state else "${name} · ${state} · ${clock(s.position_ms)} / ${clock(s.duration_ms)}"
}

Level : [Nothing, Measured({ rms : F32, peak : F32, band : [None, Band(U64)] })]

readout : Level -> Str
readout = |level|
	match level {
		Nothing => "—"
		Measured({ rms, peak, band }) => {
			loud = match band {
				Band(b) => " · loudest ${hz_label(Audio.band_edges_hz.get(b) ?? 0)}–${hz_label(Audio.band_edges_hz.get(b + 1) ?? 0)}"
				None => ""
			}
			"level ${signed(whole(rms))} dB · peak ${signed(whole(peak))} dB${loud}"
		}
	}

## The meter: the RMS level from -60 to 0 dB.
meter : Level -> I64
meter = |level|
	match level {
		Measured({ rms, .. }) => (whole(rms) + 60).max(0).min(60)
		Nothing => 0
	}

## The loudest band above -60 dB, if any.
loudest : List(F32) -> [None, Band(U64)]
loudest = |bands| {
	var $best = None
	var $top = -60.F32
	var $index = 0.U64
	for db in bands {
		if db > $top {
			$best = Band($index)
			$top = db
		}
		$index = $index + 1
	}
	$best
}

hz_label : F64 -> Str
hz_label = |hz| if (hz >= 1000) "${(hz / 1000 + 0.5).to_i64_wrap().to_str()}k" else (hz + 0.5).to_i64_wrap().to_str()

## The nearest whole number.
whole : F32 -> I64
whole = |x| if (x < 0) -((0.5 - x).to_i64_wrap()) else (x + 0.5).to_i64_wrap()

number : Str -> F32
number = |typed| (I64.from_str(typed) ?? 0).to_f32()

signed : I64 -> Str
signed = |n| if (n > 0) "+${n.to_str()}" else n.to_str()

## `m:ss.cc`
clock : U64 -> Str
clock = |ms| {
	centis = (ms // 10) % 100
	seconds = (ms // 1000) % 60
	minutes = ms // 60000
	pad = |n| if (n < 10) "0${n.to_str()}" else n.to_str()
	"${minutes.to_str()}:${pad(seconds)}.${pad(centis)}"
}

expect clock(83_456) == "1:23.45"
expect [whole(-11.6), whole(2.5), whole(-0.2)] == [-12, 3, 0]
expect loudest([-120, -20, -30, -10]) == Band(3)
expect loudest([-120, -90]) == None
expect hz_label(16000) == "16k"
