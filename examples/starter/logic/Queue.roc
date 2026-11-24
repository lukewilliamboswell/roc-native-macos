## The play queue: the songs given, which one is current, and the rules for
## moving through them. It is generic in what a track is (`src/` keeps a
## file handle and its lyrics in each), so it is tested here with plain
## text.
##
## Each time the current song changes or restarts, the queue's
## `generation` grows. The player is told to load a song with the
## generation it was chosen at, and reports the song's end with it; an end
## reported with an older generation is stale (a song that finished just as
## the listener chose another) and is ignored, so it can never skip the new
## song.
##
## The platform holds at most 64 files at once for the app. The queue
## takes at most `Queue.most` songs, leaving room for lyric and preset
## files while they are read, and counts the songs it had no room for.
Queue(t) := { held : List({ id : U64, track : t }), on : [Nowhere, At(U64)], turn : U64, fresh_id : U64 }.{

	## The most songs the queue holds: 64 files, less 4 kept for reading
	## lyric and preset files.
	most : U64
	most = 60

	## A song in the queue, under an id that is never reused.
	Entry(t) : { id : U64, track : t }

	## A queue from its parts: the songs, the current one's id, the
	## generation and the next id to give.
	make : List(Entry(t)), [Nowhere, At(U64)], U64, U64 -> Queue(t)
	make = |held, on, turn, fresh_id| Queue.{ held, on, turn, fresh_id }

	## Two queues are equal when every part is.
	is_eq : Queue(t), Queue(t) -> Bool
		where [t.is_eq : t, t -> Bool]
	is_eq = |a, b| a.held == b.held and a.on == b.on and a.turn == b.turn and a.fresh_id == b.fresh_id

	empty : () -> Queue(t)
	empty = || Queue.make([], Nowhere, 0, 0)

	entries : Queue(t) -> List(Entry(t))
	entries = |queue| queue.held

	len : Queue(t) -> U64
	len = |queue| queue.held.len()

	generation : Queue(t) -> U64
	generation = |queue| queue.turn

	## The current song, if there is one.
	current : Queue(t) -> Try(Entry(t), [Nothing])
	current = |queue|
		match queue.on {
			At(id) => queue.held.find_first(|e| e.id == id).map_err(|_| Nothing)
			Nowhere => Err(Nothing)
		}

	## The current song's id, if there is one.
	current_id : Queue(t) -> Try(U64, [Nothing])
	current_id = |queue|
		match queue.on {
			At(id) => Ok(id)
			Nowhere => Err(Nothing)
		}

	## The current song's place in the queue, from 0.
	position : Queue(t) -> Try(U64, [Nothing])
	position = |queue|
		match queue.on {
			At(id) => queue.held.find_first_index(|e| e.id == id).map_err(|_| Nothing)
			Nowhere => Err(Nothing)
		}

	## Songs added at the end, as many as there is room for, with how many
	## had none. With no current song, the first added becomes current.
	added : Queue(t), List(t) -> { queue : Queue(t), refused : U64 }
	added = |queue, tracks| {
		room = Queue.most - queue.held.len().min(Queue.most)
		taken = tracks.take_first(room)
		arrived = taken.map_with_index(|track, index| { id: queue.fresh_id + index, track })
		grown = Queue.make(queue.held.concat(arrived), queue.on, queue.turn, queue.fresh_id + taken.len())
		chosen =
			match (queue.on, arrived.first()) {
				(Nowhere, Ok(first)) => Queue.select(grown, first.id)
				_ => grown
			}
		{ queue: chosen, refused: tracks.len() - taken.len() }
	}

	## The song `id` made current, starting again if it already was. An id
	## not in the queue changes nothing.
	select : Queue(t), U64 -> Queue(t)
	select = |queue, id| if (queue.held.any(|e| e.id == id)) Queue.make(queue.held, At(id), queue.turn + 1, queue.fresh_id) else queue

	## The song after the current one; at the last song, nothing changes.
	next : Queue(t) -> Queue(t)
	next = |queue|
		match Queue.position(queue) {
			Ok(at) =>
				match queue.held.get(at + 1) {
					Ok(after) => Queue.select(queue, after.id)
					Err(_) => queue
				}
			Err(_) => queue
		}

	## The song before the current one; the first song starts again.
	previous : Queue(t) -> Queue(t)
	previous = |queue|
		match Queue.position(queue) {
			Ok(at) =>
				match queue.held.get(at - at.min(1)) {
					Ok(before) => Queue.select(queue, before.id)
					Err(_) => queue
				}
			Err(_) => queue
		}

	## What the player's report that the song of `generation` ended comes to:
	## the next song, the end of the queue, or nothing at all for a stale
	## report.
	ended : Queue(t), U64 -> [Advanced(Queue(t)), Finished, Stale]
	ended = |queue, ended_generation|
		if ended_generation != queue.turn or queue.on == Nowhere {
			Stale
		} else {
			moved = Queue.next(queue)
			if (moved.turn == queue.turn) Finished else Advanced(moved)
		}

	## The queue without the song `id`. Removing the current song makes the
	## one after it current (or the one before, at the end), at a new
	## generation, or no song when it was the last.
	removed : Queue(t), U64 -> Queue(t)
	removed = |queue, id| {
		at = queue.held.find_first_index(|e| e.id == id)
		rest = queue.held.drop_if(|e| e.id == id)
		kept = Queue.make(rest, queue.on, queue.turn, queue.fresh_id)
		match (at, queue.on) {
			(Ok(index), At(playing)) if playing == id =>
				match rest.get(index) {
					Ok(after) => Queue.select(kept, after.id)
					Err(_) =>
						match rest.last() {
							Ok(before) => Queue.select(kept, before.id)
							Err(_) => Queue.make(rest, Nowhere, queue.turn + 1, queue.fresh_id)
						}
				}
			_ => kept
		}
	}

	## The queue with nothing in it, at a new generation so that no report
	## about the old songs counts.
	cleared : Queue(t) -> Queue(t)
	cleared = |queue| Queue.make([], Nowhere, queue.turn + 1, queue.fresh_id)

	## The queue with the track `id` changed by `f`, such as to give it its
	## lyrics; no other song, and not the generation, changes.
	changed : Queue(t), U64, (t -> t) -> Queue(t)
	changed = |queue, id, f| Queue.make(queue.held.map(|e| if (e.id == id) { id: e.id, track: f(e.track) } else e), queue.on, queue.turn, queue.fresh_id)
}

## Adding to an empty queue makes the first song current, at generation 1.
expect {
	{ queue, refused } = Queue.added(Queue.empty(), ["a", "b"])
	refused == 0 and Queue.current(queue).map_ok(|e| e.track) == Ok("a") and Queue.generation(queue) == 1
}

## Next and previous move through the queue, bumping the generation; they
## stop at the ends, where previous restarts the first song.
expect {
	{ queue, refused: _ } = Queue.added(Queue.empty(), ["a", "b", "c"])
	last = Queue.next(Queue.next(queue))
	Queue.current(last).map_ok(|e| e.track) == Ok("c")
		and Queue.generation(Queue.next(last)) == Queue.generation(last)
		and Queue.current(Queue.previous(last)).map_ok(|e| e.track) == Ok("b")
		and Queue.generation(Queue.previous(queue)) == Queue.generation(queue) + 1
}

## An end advances once, for the current generation only; an old end is
## stale and the end of the last song finishes the queue.
expect {
	{ queue, refused: _ } = Queue.added(Queue.empty(), ["a", "b"])
	old = Queue.generation(queue)
	match Queue.ended(queue, old) {
		Advanced(moved) =>
			Queue.current(moved).map_ok(|e| e.track) == Ok("b")
				and Queue.ended(moved, old) == Stale
				and Queue.ended(moved, Queue.generation(moved)) == Finished
		_ => Bool.False
	}
}

## Choosing another song makes the old song's end stale.
expect {
	{ queue, refused: _ } = Queue.added(Queue.empty(), ["a", "b"])
	chosen = Queue.next(queue)
	Queue.ended(chosen, Queue.generation(queue)) == Stale
}

## The queue holds at most `Queue.most` songs and counts the rest.
expect {
	first = Queue.added(Queue.empty(), List.repeat("x", 50))
	second = Queue.added(first.queue, List.repeat("y", 20))
	first.refused == 0 and second.refused == 10 and Queue.len(second.queue) == Queue.most
}

## Removing the current song moves on; removing the last empties it.
expect {
	{ queue, refused: _ } = Queue.added(Queue.empty(), ["a", "b"])
	first_id = (Queue.current(queue) ?? { id: 99, track: "" }).id
	without = Queue.removed(queue, first_id)
	Queue.current(without).map_ok(|e| e.track) == Ok("b")
		and Queue.generation(without) == Queue.generation(queue) + 1
		and Queue.current(Queue.removed(without, first_id + 1)) == Err(Nothing)
		and Queue.len(Queue.cleared(queue)) == 0
}

## Changing one track leaves the rest and the generation alone.
expect {
	{ queue, refused: _ } = Queue.added(Queue.empty(), ["a", "b"])
	changed = Queue.changed(queue, 1, |t| Str.concat(t, "!"))
	Queue.entries(changed).map(|e| e.track) == ["a", "b!"] and Queue.generation(changed) == Queue.generation(queue)
}
