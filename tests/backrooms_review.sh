#!/bin/sh
# Reviewer captures + perf comparison for backrooms-visual-atmosphere task 6.1.
# Real LÖVE under Xvfb, one process at a time (no CPU contention: do not run
# anything else meanwhile). From the repo root:
#   sh tests/backrooms_review.sh shots    [OUTDIR]   presets x seeds, scenes
#   sh tests/backrooms_review.sh fallback [OUTDIR]   forced shader / post failure + --no-shader
#   sh tests/backrooms_review.sh perf     [OUTDIR]   plain vs high/medium/low (+ post fallback), 3 reps
# Default OUTDIR /workspace/qa/atmos/review. Logs go next to the images.
# SEEDS="2026 7 1234" (default) overrides the seed list for `shots`.
set -u
MODE=${1:-shots}; OUT=${2:-/workspace/qa/atmos/review}
SEEDS=${SEEDS:-"2026 7 1234"}

# love <logfile> <args...>: one harness process; BR_* env comes from the caller
love_run() {
    log=$1; shift
    xvfb-run -a -s '-screen 0 1024x1024x24' timeout 400 love . --backrooms-shots "$@" > "$log" 2>&1 \
        || echo "FAILED: $log"
    grep -q 'ERROR' "$log" && echo "ERROR in $log"
    return 0
}

mkdir -p "$OUT"
echo "loadavg before: $(cat /proc/loadavg)"
case $MODE in
shots)
    for s in $SEEDS; do
        d=$OUT/seed-$s; mkdir -p "$d"
        # presets: long hall fog (spawn-hall), ceiling panels, plot+crop, pickup, exit
        for p in bright dim single-bulb near-dark; do
            BR_OUT=$d BR_SUFFIX=-$p BR_PRESET=$p BR_MODE=shots BR_WARMUP=30 BR_LEVELS=2 \
              BR_POSES=spawn-hall,ceiling BR_SCENES=plot-crop,pickup,exit \
              love_run "$d/log-$p.txt" --run-seed=$s
        done
        # themes (pit/ledge/gap) + props + nook, with the level's own preset
        BR_OUT=$d BR_SUFFIX=-scene BR_MODE=shots BR_WARMUP=30 BR_LEVELS=2 BR_POSES=none \
          BR_SCENES=pit,ledge,gap,prop,nook love_run "$d/log-scenes.txt" --run-seed=$s
    done ;;
fallback)
    d=$OUT/fallback; mkdir -p "$d"
    for v in full badpost badshader noshader; do
        envv=""; args=""
        case $v in
          badpost) envv="BR_BAD_POST=1" ;;
          badshader) envv="BR_BAD_SHADER=1" ;;
          noshader) args="--no-shader" ;;
        esac
        env $envv BR_MODE=shots BR_WARMUP=30 BR_LEVELS=2 BR_POSES=spawn-hall BR_SCENES=plot-crop,exit \
          BR_OUT=$d BR_SUFFIX=-$v love_run "$d/log-$v.txt" --run-seed=2026 $args
    done
    echo "byte compare (expect: badshader == noshader; badpost != full):"
    for f in "$d"/L2-*-badshader.png; do
        b=${f%-badshader.png}
        cmp -s "$f" "$b-noshader.png" && echo "same  $(basename "$f") vs noshader" || echo "DIFF  $(basename "$f") vs noshader"
    done
    for f in "$d"/L2-*-badpost.png; do
        b=${f%-badpost.png}
        cmp -s "$f" "$b-full.png" && echo "same  $(basename "$f") vs full" || echo "DIFF  $(basename "$f") vs full"
    done ;;
perf)
    d=$OUT/perf; mkdir -p "$d"
    for rep in 1 2 3; do
        for v in plain high medium low high-nopost; do
            envv=""; args="--quality=$v"
            case $v in
              plain) args="--no-shader" ;;
              high-nopost) envv="BR_BAD_POST=1"; args="--quality=high" ;;
            esac
            env $envv BR_MODE=perf BR_LEVELS=2 BR_POSES=spawn-hall,mid-hall,ceiling BR_SCENES=plot-crop,exit \
              BR_OUT=$d BR_SUFFIX=-$v-r$rep love_run "$d/log-$v-r$rep.txt" --run-seed=2026 $args
        done
    done
    # mean ms/frame over the poses, per config and rep
    for f in "$d"/perf-*.txt; do
        awk -v n="$(basename "$f" .txt)" '/ms\/frame/ {s += $4; c++} END {printf "%s %.3f ms/frame (mean of %d poses)\n", n, s / c, c}' "$f"
    done | tee "$d/summary.txt" ;;
esac
echo "loadavg after: $(cat /proc/loadavg)"
