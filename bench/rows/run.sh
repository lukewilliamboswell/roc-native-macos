#!/usr/bin/env bash
# Build and run the rows benchmark (bench/rows/README.adoc).
#
#   bench/rows/run.sh                 # N = 10000 100000 1000000
#   bench/rows/run.sh 50000           # just these sizes
#   NO_BUILD=1 bench/rows/run.sh      # reuse bench/rows/rows (BIN=path runs another build)
#   bench/rows/run.sh --smoke         # the gate's check: 200 rows, every phase, exit 0, then the
#                                     # window, write-scaling and insert-loop timings (end of this file)
#
# The timings are diagnostics: a ratio past its bound is reported, never a
# failure. What a turn costs is checked by counting its work, in the specs
# beside this file (tests/specs/rows-2000.scm and tests/specs/rows-200000.scm, the same
# bounds at both sizes), which `blueprint run check -- bench` runs.
#   LIST=every bench/rows/run.sh      # a Ui.list drawing every row instead of the windowed Ui.table_list
#
# Each N is a fresh process with ROC_BENCH=1 and a session of spec steps, one
# phase each (`phase:NAME`, reported as `event/NAME` and so on): select
# rows, scroll the list in steps and then far, tick (an interval changing
# three rows' values every 100 ms), type a filter a letter at a time, and
# clear it. A run that has not finished after TIMEOUT seconds (300) is
# killed. The platform must be built first (blueprint run build -- --platform).
set -euo pipefail

ROC="${ROC:-roc}"
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
# A timed session is a spec with real effects and time (`live-effects`),
# lowered to the steps the host performs (scripts/lower_spec.roc).
session() { roc-stable "$root/scripts/lower_spec.roc" -- "(test \"session\" (setup (live-effects)) (steps $1))"; }
timeout="${TIMEOUT:-300}"
smoke=""
if [[ ${1:-} == --smoke ]]; then
	smoke=1
	shift
	timeout="${TIMEOUT:-60}"
fi
sizes=("$@")
[[ ${#sizes[@]} -eq 0 && -n $smoke ]] && sizes=(200)
[[ ${#sizes[@]} -eq 0 ]] && sizes=(10000 100000 1000000)

if [[ -z ${NO_BUILD:-} ]]; then
	(cd "$here" && "$ROC" build src/main.roc --output="$here/rows")
fi

# The windowing guard (part of --smoke): the windowed list mounted over
# 2,000 rows and over 200,000 draws the same rows, and the host applies the
# mount in about the same time (at most 3 times the small mount's, plus
# 15 ms); a list that drew every row would apply 100 times the rows. The
# engine's time is not compared: building the table and the view of it is
# linear in the rows, windowed or not.
window_guard() {
	local n log drawn apply
	local -a drawns=() applies=()
	for n in 2000 200000; do
		log="$(mktemp)"
		ROC_BENCH=1 ROC_STORAGE_SUITE=dev.roc.bench.rows ROC_SPEC="$(session '(wait 300) (stats)')" \
			perl -e 'alarm shift; exec @ARGV' "$timeout" "${BIN:-$here/rows}" -rows-n "$n" -rows-list window >"$log" 2>&1 || true
		drawn=$(sed -n 's/^bench: list rows [0-9]* drawn \([0-9]*\) .*/\1/p' "$log")
		apply=$(sed -n 's/^bench: first-display .* apply \([0-9.]*\) layout .*/\1/p' "$log")
		if ! grep -q "^bench: list rows $n drawn" "$log" || [[ -z $drawn || -z $apply ]]; then
			echo "bench/rows --smoke: the windowed list over $n rows did not report its rows and mount:" >&2
			cat "$log" >&2
			rm -f "$log"
			return 1
		fi
		rm -f "$log"
		echo "== window guard: N=$n draws $drawn rows, mount apply $apply ms"
		drawns+=("$drawn")
		applies+=("$apply")
	done
	if [[ ${drawns[0]} != "${drawns[1]}" ]] || ((drawns[1] > 300)); then
		echo "bench/rows --smoke: the windowed list draws ${drawns[0]} rows of 2,000 and ${drawns[1]} of 200,000; it should draw the same window, at most 300" >&2
		echo "  (timing is a diagnostic: the work is checked by the specs in $here/tests/specs)" >&2
	fi
	if ! awk -v a="${applies[0]}" -v b="${applies[1]}" 'BEGIN { exit !(b <= 3 * a + 15) }'; then
		echo "bench/rows --smoke: the mount's apply took ${applies[0]} ms at 2,000 rows and ${applies[1]} ms at 200,000; windowed, it should not grow with the rows" >&2
		echo "  (timing is a diagnostic: the work is checked by the specs in $here/tests/specs)" >&2
	fi
}

for n in "${sizes[@]}"; do
	# Scroll a screenful at a time from the top, then jump to the middle
	# and near the end.
	scrolls='(phase "scroll")'
	for k in 20 40 60 80 100 120 140 160; do scrolls="$scrolls (scroll $k)"; done
	scrolls="$scrolls (scroll $((n / 2))) (scroll $((n - 40))) (scroll 0)"
	steps="(wait ${SETTLE:-300}) (phase \"select\") (select (list-row 1)) (select (list-row 2)) (select (list-row 3)) (select (list-row 10)) (select (list-row 4)) $scrolls"
	steps="$steps (phase \"tick\") (toggle (checkbox \"Tick\")) (wait 1000) (toggle (checkbox \"Tick\")) (wait 200)"
	steps="$steps (phase \"filter\")"
	for typed in e ec ech echo "echo " "echo e"; do steps="$steps (fill (text-field) \"$typed\")"; done
	steps="$steps (phase \"clear\") (fill (text-field) \"\") (wait 200) (expect-dump _) (stats)"
	steps="${STEPS:-$steps}"
	echo "== N=$n: $steps"
	start=$(date +%s)
	status=0
	log="$(mktemp)"
	ROC_BENCH=1 ROC_STORAGE_SUITE=dev.roc.bench.rows ROC_SPEC="$(session "$steps")" \
		perl -e 'alarm shift; exec @ARGV' "$timeout" "${BIN:-$here/rows}" -rows-n "$n" -rows-list "${LIST:-window}" 2>&1 | tee "$log" || status=${PIPESTATUS[0]}
	echo "== N=$n: exit $status after $(($(date +%s) - start)) s"
	if [[ -n $smoke ]]; then
		# Every phase must have run: rows selected, scrolled, ticked,
		# filtered and cleared, and the list back to every row.
		for kind in event/select scroll/scroll timer/tick event/filter event/clear; do
			if ! grep -q "^bench: $kind n [1-9]" "$log"; then
				echo "bench/rows --smoke: no $kind operations (exit $status)" >&2
				rm -f "$log"
				exit 1
			fi
		done
		if [[ $status -ne 0 ]] || ! grep -q "(list :rows $n " "$log"; then
			echo "bench/rows --smoke: failed (exit $status, or the list does not hold $n rows after the filter is cleared)" >&2
			rm -f "$log"
			exit 1
		fi
	fi
	rm -f "$log"
done

# The --smoke guards: the window guard (defined above), then the write-scaling
# and insert-loop guards below.
if [[ -n $smoke ]]; then
	window_guard
fi

# The write-scaling check, part of --smoke. It mounts 2,000 and 200,000
# rows (100 times as many) and ticks for a second: ten turns that each
# write three rows of the table, under the list's table_view and the
# selection's reader. A write must cost the rows written, so report it if the
# ticks' engine p50 at 200,000 rows is more than 5 times 2,000's. Before
# roc-signals 0.8.0-rc2 (roc-signals#308, #309) it grew with the
# rows: 0.5 and 18.8 ms, a ratio of 38; with them, 0.3 and 0.3. The
# smaller is floored at 0.2 ms, twice the host's resolution, so timer
# noise on a fast machine cannot fail it.
tick_p50() {
	ROC_BENCH=1 ROC_STORAGE_SUITE=dev.roc.bench.rows ROC_SPEC="$(session '(wait 300) (phase "tick") (toggle (checkbox "Tick")) (wait 1000) (toggle (checkbox "Tick")) (wait 200) (stats)')" \
		perl -e 'alarm shift; exec @ARGV' "$timeout" "${BIN:-$here/rows}" -rows-n "$1" 2>&1 | sed -n 's/^bench: timer\/tick .*| engine \([0-9.]*\)\/.*/\1/p' | head -1
}
if [[ -n $smoke && -z ${NO_SCALING:-} ]]; then
	small="$(tick_p50 2000)"
	large="$(tick_p50 200000)"
	if [[ -z $small || -z $large ]]; then
		echo "bench/rows --smoke: no tick turns at 2,000 or 200,000 rows (did the interval run?)" >&2
		exit 1
	fi
	ratio="$(perl -e 'my ($s, $l) = @ARGV; printf "%.1f", $l / ($s < 0.2 ? 0.2 : $s)' "$small" "$large")"
	echo "== write scaling: tick engine p50 2,000 rows $small ms, 200,000 rows $large ms: ratio $ratio for 100x the rows (constant 1, linear 100; past 5 is reported)"
	if perl -e 'exit($ARGV[0] > 5 ? 0 : 1)' "$ratio"; then
		echo "bench/rows --smoke: a 3-row table write's engine time grows with the table; see roc-signals#308 and #309" >&2
		echo "  (timing is a diagnostic: the work is checked by the specs in $here/tests/specs)" >&2
	fi
fi

# Building a table with `Table.insert` in a loop must cost time linear in
# the rows (roc-signals#308): the mount's engine time for 18,000 rows
# inserted one at a time (`-rows-build insert`), against 2,000. Linear is
# about 9 times (less, with the mount's fixed costs); quadratic is about
# 81 (it was 50 to 60 before the patch). The faster of two runs each.
insert_scaling_guard() {
	local small large
	small=$(insert_mount_ms 2000)
	large=$(insert_mount_ms 18000)
	echo "== insert loop: mount engine ${small} ms at 2000 rows, ${large} ms at 18000"
	if ! awk -v s="$small" -v l="$large" 'BEGIN { exit !(s > 0 && l > 0 && l < 25 * (s > 1 ? s : 1)) }'; then
		echo "bench/rows --smoke: building 18000 rows with Table.insert took ${large} ms, more than 25 times the ${small} ms for 2000 (quadratic?)" >&2
		echo "  (timing is a diagnostic: the work is checked by the specs in $here/tests/specs)" >&2
	fi
}

# The faster mount engine time (ms) of two runs inserting `$1` rows.
insert_mount_ms() {
	local best="" ms
	for _ in 1 2; do
		ms=$(ROC_BENCH=1 ROC_STORAGE_SUITE=dev.roc.bench.rows ROC_SPEC="$(session '(stats)')" \
			perl -e 'alarm shift; exec @ARGV' "$timeout" "${BIN:-$here/rows}" -rows-n "$1" -rows-build insert 2>&1 |
			sed -n 's/.*first-display.*mount engine \([0-9.]*\).*/\1/p' | head -n 1)
		if [[ -z $best ]] || awk -v a="$ms" -v b="$best" 'BEGIN { exit !(a != "" && a + 0 < b + 0) }'; then
			best="$ms"
		fi
	done
	echo "${best:-0}"
}

[[ -n $smoke ]] && insert_scaling_guard
exit 0
