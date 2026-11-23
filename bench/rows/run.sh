#!/usr/bin/env bash
# Build and run the rows benchmark (bench/rows/README.adoc).
#
#   bench/rows/run.sh                 # N = 10000 100000 1000000
#   bench/rows/run.sh 50000           # just these sizes
#   NO_BUILD=1 bench/rows/run.sh      # reuse bench/rows/rows (BIN=path runs another build)
#   bench/rows/run.sh --smoke         # the gate's check: 200 rows, every phase, and the windowing guard
#   LIST=every bench/rows/run.sh      # a Ui.list drawing every row instead of the windowed Ui.table_list
#
# Each N is a fresh process with ROC_BENCH=1 and a scripted session, one
# phase each (`phase:NAME`, reported as `event/NAME` and so on): select
# rows, scroll the list in steps and then far, tick (an interval changing
# three rows' values every 100 ms), type a filter a letter at a time, and
# clear it. A run that has not finished after TIMEOUT seconds (300) is
# killed. The platform must be built first (blueprint run build -- --platform).
set -euo pipefail

ROC="${ROC:-roc}"
here="$(cd "$(dirname "$0")" && pwd)"
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
	(cd "$here" && "$ROC" build main.roc --output="$here/rows")
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
		ROC_BENCH=1 ROC_STORAGE_SUITE=dev.roc.bench.rows ROC_SCRIPT="wait:300;stats;quit" \
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
		return 1
	fi
	if ! awk -v a="${applies[0]}" -v b="${applies[1]}" 'BEGIN { exit !(b <= 3 * a + 15) }'; then
		echo "bench/rows --smoke: the mount's apply took ${applies[0]} ms at 2,000 rows and ${applies[1]} ms at 200,000; windowed, it should not grow with the rows" >&2
		return 1
	fi
}

for n in "${sizes[@]}"; do
	# Scroll a screenful at a time from the top, then jump to the middle
	# and near the end.
	scrolls="phase:scroll"
	for k in 20 40 60 80 100 120 140 160; do scrolls="$scrolls;scroll:$k"; done
	scrolls="$scrolls;scroll:$((n / 2));scroll:$((n - 40));scroll:0"
	script="wait:${SETTLE:-300};phase:select;select:#1;select:#2;select:#3;select:#10;select:#4;$scrolls"
	script="$script;phase:tick;toggle:Tick;wait:1000;toggle:Tick;wait:200"
	script="$script;phase:filter;type:e;type:ec;type:ech;type:echo;type:echo ;type:echo e;phase:clear;type:;wait:200;dump;stats;quit"
	script="${SCRIPT:-$script}"
	echo "== N=$n: $script"
	start=$(date +%s)
	status=0
	log="$(mktemp)"
	ROC_BENCH=1 ROC_STORAGE_SUITE=dev.roc.bench.rows ROC_SCRIPT="$script" \
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
		if [[ $status -ne 0 ]] || ! grep -q "ui-list \[$n rows" "$log"; then
			echo "bench/rows --smoke: failed (exit $status, or the list does not hold $n rows after the filter is cleared)" >&2
			rm -f "$log"
			exit 1
		fi
	fi
	rm -f "$log"
done

if [[ -n $smoke ]]; then
	window_guard
fi
