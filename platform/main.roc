## A native macOS platform spike over the roc-signals reactive engine.
##
## The engine modules (`Core.roc`, `Engine.roc` and the modules they import)
## are copied verbatim from roc-signals. The engine emits the roc-signals
## command stream (design.md, Appendix B); instead of a browser runtime, the
## Swift host (`../host/Host.swift`) applies those commands to AppKit views and
## routes AppKit events back as turns. `Ui.roc` is the small native
## vocabulary apps use, built only on `Engine`.
##
## Only the page instance's entry points are provided: no workers, ports,
## files or crypto keys, and no hosted functions.
platform ""
	requires {
		[Store : st] for main : Engine.Program(st)
	}
	exposes [Engine, Ui, Layout]
	packages { parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/6.0.0-rc.5/822J9njyNR1vgyX1KG4ck496dBx3AnLfvn2zHXn15Ksw.tar.zst" }
	provides {
		"roc_engine_drop": drop_for_host,
		"roc_engine_event": event_for_host,
		"roc_engine_init": init_for_host,
		"roc_engine_version": version_for_host,
	}
	hosted {}
	targets: {
		inputs_dir: "targets/",
		arm64mac: { inputs: ["libhost.a", app] },
	}

import Core
import Engine
import Layout
import Ui

## One host call's result: the state (owned by the host until the next call),
## this turn's command bytes and the instance's work record (both owned
## by the host and passed back into the next call for reuse).
Step : { cmds : List(U8), state : Handle, work : List(U8) }

## Copied from roc-signals `platform/main.roc`: the host owns one opaque box
## containing the store as plain Roc data and the site tree beside it.
## The nested boxed Iter is the narrow #12953 workaround for sites containing
## functions: https://github.com/roc-lang/roc/issues/12953.
Handle : Box({ store : Store, sites : Box(Iter(Core.Sites(Store))) })

## The handle over the state the host keeps until its next call.
hold : Core.App(Store) -> Handle
hold = |engine| {
	(store, sites) = Core.split(engine)
	Box.box({
		store,
		sites: Box.box(
			Iter.custom(
				Some(sites),
				Ok(1),
				|seed|
					match seed {
						Some(state) => Ok((state, None))
						None => Err(NoMore)
					},
			),
		),
	})
}

## The state a handle holds; the host passes each handle back once.
release : Handle -> Core.App(Store)
release = |handle| {
	{ store, sites } = Box.unbox(handle)
	match Box.unbox(sites).next() {
		One({ item, rest: _ }) => Core.join(store, item)
		_ => crash "internal: the host passed an engine handle whose state was already taken"
	}
}

## The wire protocol version the engine speaks (design.md, Appendix B).
version_for_host : () -> U32
version_for_host = || Core.driver(main).version

## Mount with the boot bytes (empty bytes: every default).
init_for_host : List(U8) -> Step
init_for_host = |boot| {
	(state, cmds, work) = (Core.driver(main).init)(boot)
	{ cmds, state: hold(state), work }
}

## Route an event (node id, handler number, payload bytes) through one
## turn, reusing the previous call's command and work buffers.
event_for_host : Handle, List(U8), List(U8), U32, U32, List(U8) -> Step
event_for_host = |boxed, buf, wbuf, node, handler, payload| {
	(next, cmds, work) = (Core.driver(main).event)(release(boxed), buf, wbuf, node, handler, payload)
	{ cmds, state: hold(next), work }
}

## Teardown: the state and both buffers are released with the call.
drop_for_host : Handle, List(U8), List(U8) -> {}
drop_for_host = |_boxed, _buf, _wbuf| {}
