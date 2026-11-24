app [main] { pf: platform "../../../platform/main.roc" }

import pf.Engine exposing [Elem, Signal]
import pf.Ui

## Fetch a URL: a text field, Fetch and Cancel, and the answer's status,
## size and the start of its body. The request is a store cell watched by
## `watch_latest`, so a second Fetch supersedes the first (the host cancels
## its transfer) and Cancel is a change whose plan asks for nothing.
main : Engine.Program(_)
main = Engine.program_store({}, |_boot| store, |_boot| view())

## What the watch site asks for: `serial` makes every Fetch a new value, even
## of the same URL; `active` false asks for nothing (and cancels).
Fetch : { serial : U64, url : Str, timeout : Bool, active : Bool }

## How the last request went, as the status badge shows it.
Outcome : [Idle, Fetching, Answered(U16), Failed(Str)]

store = Engine.store(
	HttpFetch,
	{
		url: Engine.cell("https://example.com"),
		timeout: Engine.cell(Bool.False),
		request: Engine.cell({ serial: 0, url: "", timeout: Bool.False, active: Bool.False }),
		outcome: Engine.cell(Idle),
		status: Engine.cell("Enter a URL and press Fetch."),
		preview: Engine.cell(""),
	}.Engine.Cells,
)

cells = store.cells()

view : () -> Elem(Engine.StoreRoot(_))
view = || {
	request = cells.request.signal()
	outcome = cells.outcome.signal()
	Ui.vstack(
		{ spacing: 14, align: Fill, padding: All(6), width: AtLeast(520) },
		[
			Ui.text("HTTP fetch", { style: Title2, weight: Semibold }),
			Ui.box(
				{ fill: ControlBackground, radius: 12, padding: All(12), width: Fill },
				Ui.vstack(
					{ spacing: 8, align: Fill },
					[
						Ui.form(
							{ on_submit: Engine.handle_by(starting(), |next, _| started(next)), align: Fill },
							[
								Ui.hstack(
									{},
									[
										Ui.image("globe", { color: SecondaryLabel }),
										Ui.text_field(cells.url.signal(), { placeholder: "https://…", on_input: Engine.handle(|typed| [cells.url.set(typed)]), bezel: Rounded, width: Fill }),
										Ui.submit_button("Fetch", { icon: Symbol("arrow.down.circle") }),
										Ui.button("Cancel", { on_press: Engine.handle_by(request, |r, _| cancelled(r)), enabled: request.map(|r| r.active) }),
									],
								),
							],
						),
						Ui.checkbox("Time out after 2 s", { checked: cells.timeout.signal(), on_change: Engine.handle(|on| [cells.timeout.set(on)]) }),
					],
				),
			),
			Ui.text("Response", { style: Headline }),
			Ui.hstack(
				{ spacing: 10 },
				[
					## The badge's colour follows the outcome: a `box_s`.
					Ui.box_s(outcome.map(badge_look), Ui.text(outcome.map(badge_text), { style: Caption1, weight: Bold, color: Adaptive({ light: 0xffffff, dark: 0xffffff }) })),
					Ui.text(cells.status.signal(), { color: SecondaryLabel, overflow: TruncateMiddle, squeeze: Yield }),
				],
			),
			Ui.box(
				{ fill: TextBackground, border: Line({ color: Separator, width: 1 }), padding: All(14), radius: 12, width: Fill },
				Ui.text_s(
					cells.preview.signal().map(|p| if (p.is_empty()) "The start of the body appears here." else p),
					cells.preview.signal().map(|p| { style: Callout, design: Monospaced, overflow: WrapUpTo(8), width: Fill, color: if (p.is_empty()) TertiaryLabel else Label }),
				),
			),
			Engine.watch_latest(request, plan, Engine.react(answered).with_progress({ every_ms: 100 }, Engine.react_progress(receiving))),
		],
	)
}

## A badge's words: the status code, or what happened instead.
badge_text : Outcome -> Str
badge_text = |outcome|
	match outcome {
		Idle => "IDLE"
		Fetching => "…"
		Answered(code) => code.to_str()
		Failed(why) => why
	}

## Green for 2xx, red for 4xx and 5xx, orange for a failure before any
## answer, grey otherwise.
badge_look : Outcome -> Ui.BoxProps
badge_look = |outcome| {
	fill : Ui.Color
	fill = match outcome {
		Answered(code) if code >= 200 and code < 300 => Green
		Answered(code) if code >= 400 => Red
		Failed(_) => Orange
		_ => Gray
	}
	{ fill, radius: 5, padding: Axes({ horizontal: 7, vertical: 2 }) }
}

## The next request, read when Fetch is pressed.
starting : () -> Signal(ctx, Fetch)
	where [ctx.store : () -> Engine.Reach(ctx, _)]
starting = ||
	{ url: cells.url.signal(), timeout: cells.timeout.signal(), last: cells.request.signal() }.Signal.map(|{ url, timeout, last }| { serial: last.serial + 1, url: url.trim(), timeout, active: Bool.True })

started : Fetch -> List(Engine.Write(_))
started = |next| [cells.request.set(next), cells.outcome.set(Fetching), cells.status.set("Fetching ${next.url} (#${next.serial.to_str()})…"), cells.preview.set("")]

cancelled : Fetch -> List(Engine.Write(_))
cancelled = |r| [cells.request.set({ ..r, active: Bool.False }), cells.outcome.set(Idle), cells.status.set("Cancelled #${r.serial.to_str()}")]

plan : Fetch -> List(Engine.Ask(Engine.Response, Engine.HttpFailure))
plan = |r|
	if (r.active)
		[Engine.http({ url: r.url, timeout: if (r.timeout) Ms(2000) else Unlimited, cache: NoStore })]
	else
		[]

## The answer for the request it was issued for; a superseded or cancelled
## request never gets here.
answered : Fetch, Try(Engine.Response, Engine.HttpFailure) -> List(Engine.Write(_))
answered = |r, result| {
	done = |outcome, text| [cells.request.set({ ..r, active: Bool.False }), cells.outcome.set(outcome), cells.status.set("#${r.serial.to_str()}: ${text}")]
	match result {
		Ok(response) => done(Answered(response.status), "${size(response.body.count_utf8_bytes())} from ${r.url}").concat([cells.preview.set(preview(response.body))])
		Err(Network(message)) => done(Failed("NETWORK"), message)
		Err(Timeout) => done(Failed("TIMEOUT"), "no answer within 2 s")
		Err(Refused) => done(Failed("REFUSED"), "too many requests in flight")
	}
}

receiving : Fetch, Engine.Transfer -> List(Engine.Write(_))
receiving = |r, transfer| {
	of = match transfer.total {
		Known(total) => " of ${size(total)}"
		Unknown => ""
	}
	[cells.status.set("Fetching #${r.serial.to_str()}: ${size(transfer.done)}${of}")]
}

## A byte count for people: bytes, KB or MB (1000s, as the Finder counts).
size : U64 -> Str
size = |bytes|
	if bytes < 1000 {
		"${bytes.to_str()} bytes"
	} else if bytes < 1_000_000 {
		"${(bytes // 1000).to_str()}.${((bytes % 1000) // 100).to_str()} KB"
	} else {
		"${(bytes // 1_000_000).to_str()}.${((bytes % 1_000_000) // 100_000).to_str()} MB"
	}

## The first 400 bytes of the body, on one line.
preview : Str -> Str
preview = |body| Str.join_with(Str.from_utf8_lossy(body.to_utf8().take_first(400)).split_on("\n").map(|line| line.trim()), " ")

expect preview("a\n  b") == "a b"
expect plan({ serial: 1, url: "u", timeout: Bool.False, active: Bool.False }).is_empty()
expect [size(512), size(1_256), size(3_400_000)] == ["512 bytes", "1.2 KB", "3.4 MB"]
expect [badge_text(Answered(404)), badge_text(Failed("NETWORK"))] == ["404", "NETWORK"]
