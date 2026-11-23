#!/usr/bin/env bash
# Build and run the rows benchmark (bench/rows/README.adoc).
#
#   bench/rows/run.sh                 # N = 10000 100000 1000000
#   bench/rows/run.sh 50000           # just these sizes
#   NO_BUILD=1 bench/rows/run.sh      # reuse bench/rows/rows (BIN=path runs another build)
#   bench/rows/run.sh --smoke         # the gate's check: 200 rows, every phase, exit 0,
#                                     # then insert_scaling_guard (below)
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
		perl -e 'alarm shift; exec @ARGV' "$timeout" "${BIN:-$here/rows}" -rows-n "$n" 2>&1 | tee "$log" || status=${PIPESTATUS[0]}
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

# Building a table with `Table.insert` in a loop must cost time linear in
# the rows (engine patch 0006): the mount's engine time for 18,000 rows
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
		exit 1
	fi
}

# The faster mount engine time (ms) of two runs inserting `$1` rows.
insert_mount_ms() {
	local best="" ms
	for _ in 1 2; do
		ms=$(ROC_BENCH=1 ROC_STORAGE_SUITE=dev.roc.bench.rows ROC_SCRIPT='stats;quit' \
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
