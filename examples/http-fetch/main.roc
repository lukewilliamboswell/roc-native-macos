app [main] { pf: platform "../../platform/main.roc" }

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

store = Engine.store(
	HttpFetch,
	{
		url: Engine.cell("https://example.com"),
		timeout: Engine.cell(Bool.False),
		request: Engine.cell({ serial: 0, url: "", timeout: Bool.False, active: Bool.False }),
		status: Engine.cell("Idle"),
		preview: Engine.cell(""),
	}.Engine.Cells,
)

cells = store.cells()

view : () -> Elem(Engine.StoreRoot(_))
view = || {
	request = cells.request.signal()
	Ui.vstack(
		[
			Ui.title("HTTP fetch"),
			Ui.form(
				Engine.handle_by(starting(), |next, _| started(next)),
				[
					Ui.hstack(
						[
							Ui.text_field("URL", cells.url.signal(), Engine.handle(|typed| [cells.url.set(typed)])),
							Ui.submit_button("Fetch"),
							Ui.action_button(Engine.const("Cancel"), request.map(|r| r.active), Engine.handle_by(request, |r, _| cancelled(r))),
						],
					),
				],
			),
			Ui.checkbox(Engine.const("Time out after 2 s"), cells.timeout.signal(), Engine.handle(|on| [cells.timeout.set(on)])),
			Ui.divider(),
			Ui.label_s(cells.status.signal()),
			Ui.label_s(cells.preview.signal()),
			Engine.watch_latest(request, plan, Engine.react(answered).with_progress({ every_ms: 100 }, Engine.react_progress(receiving))),
		],
	)
}

## The next request, read when Fetch is pressed.
starting : () -> Signal(ctx, Fetch)
	where [ctx.store : () -> Engine.Reach(ctx, _)]
starting = ||
	{ url: cells.url.signal(), timeout: cells.timeout.signal(), last: cells.request.signal() }.Signal.map(|{ url, timeout, last }| { serial: last.serial + 1, url: url.trim(), timeout, active: Bool.True })

started : Fetch -> List(Engine.Write(_))
started = |next| [cells.request.set(next), cells.status.set("Fetching ${next.url} (#${next.serial.to_str()})…"), cells.preview.set("")]

cancelled : Fetch -> List(Engine.Write(_))
cancelled = |r| [cells.request.set({ ..r, active: Bool.False }), cells.status.set("Cancelled #${r.serial.to_str()}")]

plan : Fetch -> List(Engine.Ask(Engine.Response, Engine.HttpFailure))
plan = |r|
	if r.active
		[Engine.http({ url: r.url, timeout: if r.timeout Ms(2000) else Unlimited, cache: NoStore })]
	else
		[]

## The answer for the request it was issued for; a superseded or cancelled
## request never gets here.
answered : Fetch, Try(Engine.Response, Engine.HttpFailure) -> List(Engine.Write(_))
answered = |r, result| {
	done = |text| [cells.request.set({ ..r, active: Bool.False }), cells.status.set("#${r.serial.to_str()}: ${text}")]
	match result {
		Ok(response) => done("HTTP ${response.status.to_str()}, ${response.body.count_utf8_bytes().to_str()} bytes").concat([cells.preview.set(preview(response.body))])
		Err(Network(message)) => done("network error: ${message}")
		Err(Timeout) => done("timed out")
		Err(Refused) => done("refused (too many requests in flight)")
	}
}

receiving : Fetch, Engine.Transfer -> List(Engine.Write(_))
receiving = |r, transfer| {
	of = match transfer.total {
		Known(total) => " of ${total.to_str()}"
		Unknown => ""
	}
	[cells.status.set("Fetching #${r.serial.to_str()}: ${transfer.done.to_str()}${of} bytes")]
}

## The first 200 bytes of the body, on one line.
preview : Str -> Str
preview = |body| Str.join_with(Str.from_utf8_lossy(body.to_utf8().take_first(200)).split_on("\n").map(|line| line.trim()), " ")

expect preview("a\n  b") == "a b"
expect plan({ serial: 1, url: "u", timeout: Bool.False, active: Bool.False }).is_empty()
