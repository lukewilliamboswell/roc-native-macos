#!/usr/bin/env bash
# Build and run the grid stress test (bench/grid/README.adoc).
#
#   bench/grid/run.sh               # N = 10 32 100 150 200 316
#   bench/grid/run.sh 100 200       # just these sizes
#   NO_BUILD=1 bench/grid/run.sh    # reuse bench/grid/grid (BIN=path runs another build)
#   LIVE=1 bench/grid/run.sh 100    # move the mouse yourself; the HUD shows the timings
#   bench/grid/run.sh --smoke       # the gate's check: a 4x4 grid, a short sweep, exit 0,
#                                   # then the mount- and turn-scaling timings (end of this file)
#
# The timings are diagnostics: a ratio past its bound is reported, never a
# failure. What a hover or a timer costs is checked by counting its work, in
# the specs beside this file (specs/grid-20.scm and specs/grid-60.scm, the
# same bounds at both sizes), which `blueprint run check -- bench` runs.
#
# Each N is a fresh process with ROC_BENCH=1 and a sweep (a spec's steps): the
# pointer crosses the grid's diagonal in 2N moves (at least 200, at most
# 2000), one every 10 ms, then waits for the trail to cool and prints the
# stats. A run that has not finished after TIMEOUT seconds (120) is killed.
# The platform must be built first (blueprint run build -- --platform).
set -euo pipefail

ROC="${ROC:-roc}"
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
# A timed session is a spec with real effects and time (`live-effects`),
# lowered to the steps the host performs (scripts/lower_spec.roc).
session() { roc-stable "$root/scripts/lower_spec.roc" -- "(test \"session\" (setup (live-effects)) (steps $1))"; }
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
[[ ${#sizes[@]} -eq 0 ]] && sizes=(10 32 100 150 200 316)

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
	steps="${STEPS:-(wait 500) (sweep ${x0%.*} ${x0%.*} ${x1%.*} ${x1%.*} $moves 10) (stats) (wait 800) (stats)}"
	[[ -n $smoke ]] && steps="${STEPS:-(wait 100) (sweep ${x0%.*} ${x0%.*} ${x1%.*} ${x1%.*} $moves 5) (wait 700) (stats)}"
	if [[ -n ${LIVE:-} ]]; then
		# A person drives it: no steps, no timeout, the HUD shows the timings.
		echo "== N=$n ($((n * n)) cells, ${side} pt): live; quit with Command-Q"
		ROC_BENCH=1 ROC_STORAGE_SUITE=dev.roc.bench.grid "${BIN:-$here/grid}" -grid-n "$n" || true
		continue
	fi
	echo "== N=$n ($((n * n)) cells, ${side} pt): $steps"
	start=$(date +%s)
	status=0
	log="$(mktemp)"
	ROC_BENCH=1 ROC_STORAGE_SUITE=dev.roc.bench.grid ROC_SPEC="$(session "$steps")" \
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

# The scaling checks, part of --smoke. Each mounts N=20 and N=60 (400 and
# 3,600 cells, 9 times as many) and sweeps 40 moves across it.
#
# Mount: report it if the mount's engine time grows more than 3 times faster
# than linear (a ratio above 27; a quadratic mount gives about 80). Mount
# was quadratic until roc-signals 0.8.0-rc2 (roc-signals#305, #306),
# which work around compiler behaviour a later engine change could bring
# back. The smaller time is floored at 2 ms so timer noise on a fast
# machine cannot fail it.
#
# Turns: a hover writes one cell's state, so its engine time must not grow
# with the grid. Report it if the hover turns' p50 at N=60 is more than 4 times
# N=20's (linear would be 9; before roc-signals#307 it was about 9:
# 0.1 and 0.9 ms). The smaller is floored at 0.1 ms, the host's resolution.
scaling_run() {
	local n=$1 side a b
	side=$((640 / n))
	((side > 24)) && side=24
	a=$(((40 + side) / 2))
	b=$(((40 + side * (2 * n - 1)) / 2))
	ROC_BENCH=1 ROC_STORAGE_SUITE=dev.roc.bench.grid ROC_SPEC="$(session "(sweep $a $a $b $b 40 5) (stats)")" \
		perl -e 'alarm shift; exec @ARGV' "$timeout" "${BIN:-$here/grid}" -grid-n "$n" 2>&1
}
mount_ms() { sed -n 's/.*mount engine \([0-9.]*\).*/\1/p' | head -1; }
hover_p50() { sed -n 's/^bench: hover .*| engine \([0-9.]*\)\/.*/\1/p' | head -1; }
if [[ -n $smoke && -z ${NO_SCALING:-} ]]; then
	small_log="$(scaling_run 20)"
	large_log="$(scaling_run 60)"
	small="$(mount_ms <<<"$small_log")"
	large="$(mount_ms <<<"$large_log")"
	if [[ -z $small || -z $large ]]; then
		echo "bench/grid --smoke: no mount time for N=20 or N=60 (did the mount finish?)" >&2
		exit 1
	fi
	ratio="$(perl -e 'my ($s, $l) = @ARGV; printf "%.1f", $l / ($s < 2 ? 2 : $s)' "$small" "$large")"
	echo "== mount scaling: N=20 $small ms, N=60 $large ms: ratio $ratio for 9x the cells (linear 9; past 27 is reported)"
	if perl -e 'exit($ARGV[0] > 27 ? 0 : 1)' "$ratio"; then
		echo "bench/grid --smoke: mount grows superlinearly with the cells; see roc-signals#305 and #306" >&2
		echo "  (timing is a diagnostic: the work is checked by the specs in $here/specs)" >&2
	fi
	small="$(hover_p50 <<<"$small_log")"
	large="$(hover_p50 <<<"$large_log")"
	if [[ -z $small || -z $large ]]; then
		echo "bench/grid --smoke: no hover turns for N=20 or N=60 (did the sweep run?)" >&2
		exit 1
	fi
	ratio="$(perl -e 'my ($s, $l) = @ARGV; printf "%.1f", $l / ($s < 0.1 ? 0.1 : $s)' "$small" "$large")"
	echo "== turn scaling: hover engine p50 N=20 $small ms, N=60 $large ms: ratio $ratio for 9x the cells (constant 1, linear 9; past 4 is reported)"
	if perl -e 'exit($ARGV[0] > 4 ? 0 : 1)' "$ratio"; then
		echo "bench/grid --smoke: a hover turn's engine time grows with the cells; see roc-signals#307" >&2
		echo "  (timing is a diagnostic: the work is checked by the specs in $here/specs)" >&2
	fi
fi
