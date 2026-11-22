#!/usr/bin/env bash
# Build and run the grid stress test (bench/grid/README.adoc).
#
#   bench/grid/run.sh               # N = 10 32 100 316 1000
#   bench/grid/run.sh 100 200       # just these sizes
#   NO_BUILD=1 bench/grid/run.sh    # reuse bench/grid/grid (BIN=path runs another build)
#   LIVE=1 bench/grid/run.sh 100    # move the mouse yourself; the HUD shows the timings
#   bench/grid/run.sh --smoke       # the gate's check: a 4x4 grid, a short sweep, exit 0
#
# Each N is a fresh process with ROC_BENCH=1 and a scripted sweep: the
# pointer crosses the grid's diagonal in 2N moves (at least 200, at most
# 2000), one every 10 ms, then waits for the trail to cool and prints the
# stats. A run that has not finished after TIMEOUT seconds (120) is killed.
# The platform must be built first (blueprint run build -- --platform).
set -euo pipefail

ROC="${ROC:-roc}"
here="$(cd "$(dirname "$0")" && pwd)"
timeout="${TIMEOUT:-120}"
smoke=""
if [[ ${1:-} == --smoke ]]; then
	# Proves the harness still builds, mounts, hovers, cools and reports:
	# no load, and any failure is the run's failure.
	smoke=1
	shift
	timeout="${TIMEOUT:-60}"
fi
sizes=("$@")
[[ ${#sizes[@]} -eq 0 && -n $smoke ]] && sizes=(4)
[[ ${#sizes[@]} -eq 0 ]] && sizes=(10 32 100 316 1000)

if [[ -z ${NO_BUILD:-} ]]; then
	(cd "$here" && "$ROC" build main.roc --output="$here/grid")
fi

for n in "${sizes[@]}"; do
	# The cell side main.roc's side_of gives; the grid starts at the root's
	# 20-point padding.
	side=$((640 / n))
	((side > 24)) && side=24
	((side < 1)) && side=1
	first=$((20 * 2 + side))  # twice the first cell's centre, to keep halves
	last=$((40 + side * (2 * n - 1)))
	moves=$((2 * n))
	((moves < 200)) && moves=200
	((moves > 2000)) && moves=2000
	[[ -n $smoke ]] && moves=12
	x0="$((first / 2)).$((first % 2 * 5))"
	x1="$((last / 2)).$((last % 2 * 5))"
	script="${SCRIPT:-wait:500;sweep:$x0,$x0,$x1,$x1,$moves,10;stats;wait:800;stats;quit}"
	[[ -n $smoke ]] && script="${SCRIPT:-wait:100;sweep:$x0,$x0,$x1,$x1,$moves,5;wait:700;stats;quit}"
	if [[ -n ${LIVE:-} ]]; then
		# A person drives it: no script, no timeout, the HUD shows the timings.
		echo "== N=$n ($((n * n)) cells, ${side} pt): live; quit with Command-Q"
		ROC_BENCH=1 ROC_STORAGE_SUITE=dev.roc.bench.grid "${BIN:-$here/grid}" -grid-n "$n" || true
		continue
	fi
	echo "== N=$n ($((n * n)) cells, ${side} pt): $script"
	start=$(date +%s)
	status=0
	log="$(mktemp)"
	ROC_BENCH=1 ROC_STORAGE_SUITE=dev.roc.bench.grid ROC_SCRIPT="$script" \
		perl -e 'alarm shift; exec @ARGV' "$timeout" "${BIN:-$here/grid}" -grid-n "$n" 2>&1 | tee "$log" || status=${PIPESTATUS[0]}
	echo "== N=$n: exit $status after $(($(date +%s) - start)) s"
	if [[ -n $smoke ]]; then
		# Every cell the sweep entered must have been hovered and cooled.
		if [[ $status -ne 0 ]] || ! grep -q '^bench: hover n [1-9]' "$log" || ! grep -q 'timers-live 0' "$log"; then
			echo "bench/grid --smoke: failed (exit $status, or no hover turns, or timers still live)" >&2
			rm -f "$log"
			exit 1
		fi
	fi
	rm -f "$log"
done
