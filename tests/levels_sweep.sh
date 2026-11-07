#!/bin/sh
# Sharded physical solvability sweep (tests/levels_sweep.lua). From the repo root:
#   sh tests/levels_sweep.sh [FROM TO [DIFFS]]      default: 1 70 "1,2,3" (210 levels)
# SWEEP_JOBS (default: nproc) parallel shards over the seed range; SWEEP_NEG=0 skips
# the empty/wrong-type negatives. Exit 0 only if every shard passes.
set -u
from=${1:-1}; to=${2:-70}; export SWEEP_DIFFS=${3:-1,2,3}
jobs=${SWEEP_JOBS:-$(nproc 2>/dev/null || echo 4)}
n=$((to - from + 1)); per=$(( (n + jobs - 1) / jobs ))
dir=$(mktemp -d); i=0; a=$from
while [ $a -le $to ]; do
    b=$((a + per - 1)); [ $b -gt $to ] && b=$to
    SWEEP_FROM=$a SWEEP_TO=$b love tests/love_runner tests/levels_sweep.lua > "$dir/$i.txt" 2>&1 &
    a=$((b + 1)); i=$((i + 1))
done
wait
fail=0
for f in "$dir"/*.txt; do
    grep -E '^FAIL|error' "$f"
    if ! grep -q ' 0 failures' "$f"; then fail=1; fi
done
grep -h 'levels_sweep seeds' "$dir"/*.txt
cat "$dir"/*.txt | grep 'levels_sweep seeds' | sed 's/.*: \([0-9]*\) levels.* \([0-9]*\) searches.*/\1 \2/' | awk '{l+=$1;s+=$2} END {print "TOTAL levels=" l " searches=" s}'
rm -rf "$dir"
if [ $fail -eq 0 ]; then echo "levels sweep: PASS"; else echo "levels sweep: FAIL"; fi
exit $fail
