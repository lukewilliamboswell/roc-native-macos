## A native macOS platform spike over the roc-signals reactive engine.
##
## The engine modules (`Core.roc`, `Engine.roc` and the modules they import)
## are copied verbatim from roc-signals. The engine emits the roc-signals
## command stream (design.md, Appendix B); instead of a browser runtime, the
## Swift host (`../host/Host.swift`) applies those commands to AppKit views and
## routes AppKit events back as turns. `Ui.roc` is the small native
## vocabulary apps use, built only on `Engine`.
##
## The page instance's entry points are provided, including files-kind
## events (`roc_engine_files`), and so are a worker instance's
## (`roc_engine_work`, `roc_engine_prepare`, `roc_engine_ask`,
## `roc_engine_forget`), which the host runs on its worker threads, one Roc
## instance per thread (docs/architecture.adoc, "Workers"). A job's hosted
## effects (`Hosted.roc`, reached only through `Effects.roc` and `Files.roc`)
## are the platform's `roc_task_*` functions. There are no ports or crypto
## keys, and the declarations (`roc_engine_keys`) cross without roc-signals'
## section 12.
platform ""
	requires {
		[Store : st] for main : Engine.Program(st)
	}
	exposes [Engine, Files, Layout, Ui, Wire, Worker]
	packages { cbor: "https://github.com/lukewilliamboswell/roc-cbor/releases/download/0.6.3/J3xX4n61WoMZKK3tdWTnZBdKaVbi8SvXvmtC5i3qDAER.tar.zst", parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/6.0.0-rc.5/822J9njyNR1vgyX1KG4ck496dBx3AnLfvn2zHXn15Ksw.tar.zst" }
	provides {
		"roc_engine_ask": ask_for_host!,
		"roc_engine_drop": drop_for_host,
		"roc_engine_event": event_for_host,
		"roc_engine_files": files_for_host,
		"roc_engine_forget": forget_for_host,
		"roc_engine_init": init_for_host,
		"roc_engine_keys": keys_for_host,
		"roc_engine_prepare": prepare_for_host!,
		"roc_engine_version": version_for_host,
		"roc_engine_work": work_for_host!,
	}
	hosted {
		"roc_task_append": Hosted.append!,
		"roc_task_append_file": Hosted.append_file!,
		"roc_task_finish": Hosted.finish!,
		"roc_task_mint": Hosted.mint!,
		"roc_task_open": Hosted.open!,
		"roc_task_read": Hosted.read!,
		"roc_task_size": Hosted.size!,
	}
	targets: {
		inputs_dir: "targets/",
		arm64mac: { inputs: ["libhost.a", app] },
	}

import Core
import Effects
import Engine
import Files
import Hosted
import Layout
import Ui
import Wire
import Worker

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

## The program's declaration sections (2, 5, 6, 10, 11 and 14), which tell
## the host what to read before mount: storage keys, media queries, the zone
## span and the startup profile. roc-signals appends section 12 (protocol
## facts, a CBOR item) here with `ProtocolFacts.append_declaration`; this
## host binds no roles from it and would need the cbor package to build it,
## so the declarations cross as the engine writes them.
keys_for_host : () -> List(U8)
keys_for_host = || (Core.driver(main).keys)()

## Mount with the boot bytes the host read for those declarations.
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

## Copied from roc-signals `platform/main.roc`: a files-kind event, the file
## record and the handles the host minted for its files, which move into the
## engine with the call.
files_for_host : Handle, List(U8), List(U8), U32, U32, List(U8), List(Box(U64)) -> Step
files_for_host = |boxed, buf, wbuf, node, handler, record, blobs| {
	(next, cmds, work) = (Core.driver(main).files)(release(boxed), buf, wbuf, node, handler, record, blobs)
	{ cmds, state: hold(next), work }
}

## Copied from roc-signals `platform/main.roc`: a worker instance's job
## (design.md, "Workers"): run the task named in the payload
## (`name:str input:rest`) with the handles the host minted for the job's
## files, which move into Roc with the call, and return its answer,
## `n:u32 (token:u64)* output:rest`. The engine gets the platform's hosted
## effects with the call (`Effects.job`), and the job's files and builders
## carry them. A worker instance never mounts.
work_for_host! : List(U8), List(Box(U64)) => List(U8)
work_for_host! = |payload, handles| Core.work!(main, Effects.job, payload, handles)

## Copied from roc-signals `platform/main.roc`: a worker instance's
## preparation (design.md, "Prepared state"): run the preparation named in
## `prep:str init:rest` with the handles of its files and return the state
## the instance keeps, which the host owns until a job runs a task on it or
## the instance forgets it.
prepare_for_host! : List(U8), List(Box(U64)) => Box(Core.Kept)
prepare_for_host! = |payload, handles| Box.box(Core.work_prepare!(main, Effects.job, payload, handles))

## Copied from roc-signals `platform/main.roc`: a job of a preparation's task
## on the held state; the state moves in and back out with the job's answer.
ask_for_host! : Box(Core.Kept), List(U8), List(Box(U64)) => { held : Box(Core.Kept), out : List(U8) }
ask_for_host! = |boxed, payload, handles| {
	state = Box.unbox(boxed)
	out = Core.work_ask!(state, payload, handles)
	{ held: Box.box(state), out }
}

## Let go of the held state: the instance evicts it or prepares another.
forget_for_host : Box(Core.Kept) -> {}
forget_for_host = |_boxed| {}

## Teardown: the state and both buffers are released with the call.
drop_for_host : Handle, List(U8), List(U8) -> {}
drop_for_host = |_boxed, _buf, _wbuf| {}
